import AppKit
import AVFoundation
import Carbon.HIToolbox
import CoreAudio
import Speech

// MARK: - Output devices

struct OutputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    var isVirtualMic: Bool {
        let n = name.lowercased()
        return n.contains("blackhole") || n.contains("livesubs") || n.contains("loopback")
    }
}

enum AudioDevices {
    private static func string(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(device, &addr, 0, nil, &size, $0) }
        return status == noErr ? value as String : nil
    }

    static func outputs() -> [OutputDevice] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var s: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &s) == noErr, s > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName),
                  !uid.hasPrefix("com.wquguru.cicada") else { return nil }
            return OutputDevice(id: id, uid: uid, name: name)
        }
    }

    static var virtualMic: OutputDevice? { outputs().first(where: \.isVirtualMic) }

    /// The system output (speakers or headphones): voice previews play here, not into the room.
    static var defaultOutput: OutputDevice? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
        return outputs().first { $0.id == id }
    }
}

// MARK: - Speak engine

/// Hold to talk: microphone → on-device transcription → translation →
/// system voice → chosen output device (a virtual microphone for the call).
@MainActor
final class SpeakEngine {
    enum Phase { case idle, listening, translating, speaking }

    var onLive: ((_ phase: Phase, _ source: String, _ translation: String) -> Void)?
    /// A finished utterance for the meeting record.
    var onUtterance: ((_ source: String, _ translation: String, _ from: String, _ to: String, _ secondsAgo: Double) -> Void)?
    var onStatus: ((String) -> Void)?
    /// Translator shared with the listening side.
    var translate: ((_ text: String, _ from: String, _ to: String, _ trace: TranslateTrace) async -> String?)?
    /// Diagnostics: key released → transcript → translation → voice finished.
    var onTiming: ((SentenceTiming) -> Void)?
    private var releasedAt: Date?
    /// Language the room speaks (for "follow the room").
    var roomLanguage: (() -> String?)?

    let settings: AppSettings
    private(set) var phase: Phase = .idle

    private let mic = AVAudioEngine()
    private let micQueue = DispatchQueue(label: "com.wquguru.cicada.mic", qos: .userInitiated)
    private let converter = PCMConverter()
    private var analyzerFormat: AVAudioFormat?
    private var analyzerLocale = ""
    private nonisolated(unsafe) var feeding = false
    private var finals: [String] = []
    private var volatile = ""
    private var pressStarted = Date()
    private nonisolated(unsafe) var micRecorder: AVAudioFile?
    private nonisolated(unsafe) var micRecordURL: URL?

    private let synth = AVSpeechSynthesizer()
    private let out = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var outFormat: AVAudioFormat?
    private var outDeviceUID: String?
    /// Debug: also write synthesized speech here.
    var debugOutputURL: URL?

    init(settings: AppSettings) {
        self.settings = settings
        out.attach(player)
    }

    var targetCode: String {
        if settings.speakTo != "room" { return settings.speakTo }
        let room = roomLanguage?() ?? "en"
        return room == settings.speakFromLang.code ? "en" : room
    }

    func setRecording(_ url: URL?) {
        micQueue.sync {
            micRecorder = nil
            micRecordURL = url
        }
    }

    // MARK: Transcriber

    /// Makes sure the speech model for my language is installed and learns the
    /// audio format it wants. Each press then gets its own short-lived analyzer.
    func prepare() async {
        let lang = settings.speakFromLang
        guard analyzerLocale != lang.locale || analyzerFormat == nil else { return }
        let t = SpeechTranscriber(locale: Locale(identifier: lang.locale), transcriptionOptions: [],
                                  reportingOptions: [.volatileResults], attributeOptions: [])
        do {
            if await AssetInventory.status(forModules: [t]) != .installed,
               let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
                onStatus?("正在下载 \(lang.name) 语音模型…")
                try await req.downloadAndInstall()
            }
            analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])
                ?? AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
            analyzerLocale = lang.locale
            debugLog("speak transcriber ready locale=\(lang.locale)")
        } catch {
            debugLog("speak transcriber failed: \(error)")
            onStatus?("无法准备语音识别：\(error.localizedDescription)")
        }
    }

    func teardownAnalyzer() async {
        utterance?.input.finish()
        utterance = nil
        analyzerFormat = nil
        analyzerLocale = ""
    }

    /// One press = one analyzer over a finite stream. Finishing the stream and
    /// awaiting `finalizeAndFinishThroughEndOfInput` guarantees every word
    /// spoken during the press is in the result before we translate it.
    private var utterance: (input: AsyncStream<AnalyzerInput>.Continuation, text: Task<String, Never>)?

    private func beginUtterance() -> AsyncStream<AnalyzerInput>.Continuation? {
        guard analyzerFormat != nil else { return nil }
        let lang = settings.speakFromLang
        let t = SpeechTranscriber(locale: Locale(identifier: lang.locale), transcriptionOptions: [],
                                  reportingOptions: [.volatileResults], attributeOptions: [])
        let (stream, cont) = AsyncStream.makeStream(of: AnalyzerInput.self)
        finals = []
        volatile = ""
        let task = Task { [weak self] () -> String in
            let collector = Task { [weak self] in
                do {
                    for try await r in t.results { self?.handle(r) }
                } catch {
                    debugLog("speak recognition error: \(error)")
                }
            }
            let analyzer = SpeechAnalyzer(inputSequence: stream, modules: [t])
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                debugLog("speak analyzer error: \(error)")
            }
            await collector.value
            return self?.currentText ?? ""
        }
        utterance = (cont, task)
        return cont
    }

    private func handle(_ r: SpeechTranscriber.Result) {
        let text = String(r.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isFinal {
            if !text.isEmpty { finals.append(text) }
            volatile = ""
        } else {
            volatile = text
        }
        if phase == .listening { onLive?(.listening, currentText, "") }
    }

    private var currentText: String {
        let j = joiner(for: settings.speakFromLang.code)
        return (finals + [volatile]).filter { !$0.isEmpty }.joined(separator: j.isEmpty ? "" : " ")
    }

    // MARK: Push to talk

    func pressBegan() {
        guard settings.speakEnabled, phase == .idle || phase == .speaking else { return }
        guard let format = analyzerFormat, let input = beginUtterance() else {
            Task { await prepare() }
            onStatus?("语音识别仍在准备中，请再按一次")
            return
        }
        debugLog("speak: press began")
        pressStarted = Date()
        phase = .listening
        onLive?(.listening, "", "")
        startMic(format: format, input: input)
    }

    /// The talk key turned out to be part of a chord: drop what was heard, send nothing.
    func pressCancelled() {
        guard phase == .listening else { return }
        stopMic()
        utterance?.input.finish()
        utterance = nil
        finals = []
        volatile = ""
        phase = .idle
        onLive?(.idle, "", "")
        debugLog("speak: press cancelled (chord)")
    }

    func pressEnded() {
        guard phase == .listening else { return }
        debugLog("speak: press ended")
        releasedAt = Date()
        // Keep the mic open a moment so the last syllable isn't cut off.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated { self?.finishUtterance() }
        }
    }

    /// Debug path: feed an audio file as if it were spoken into the mic.
    func speakFile(_ url: URL) {
        guard phase == .idle || phase == .speaking else { return }
        guard let format = analyzerFormat, let file = try? AVAudioFile(forReading: url),
              let input = beginUtterance() else {
            debugLog("speakFile: not ready or unreadable \(url.path)")
            return
        }
        pressStarted = Date()
        phase = .listening
        onLive?(.listening, "", "")
        let conv = PCMConverter()
        while true {
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096),
                  (try? file.read(into: buf)) != nil, buf.frameLength > 0 else { break }
            if let c = conv.convert(buf, to: format) { input.yield(AnalyzerInput(buffer: c)) }
        }
        finishUtterance()
    }

    private func startMic(format: AVAudioFormat, input cont: AsyncStream<AnalyzerInput>.Continuation) {
        let inputNode = mic.inputNode
        let inFormat = inputNode.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else {
            onStatus?("没有可用的麦克风")
            phase = .idle
            return
        }
        inputNode.removeTap(onBus: 0)
        let conv = converter
        let queue = micQueue
        feeding = true
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buf, _ in
            queue.async {
                guard let self, self.feeding else { return }
                if let c = conv.convert(buf, to: format) {
                    cont.yield(AnalyzerInput(buffer: c))
                    self.recordMic(c)
                }
            }
        }
        do {
            try mic.start()
        } catch {
            debugLog("mic start failed: \(error)")
            onStatus?("麦克风无法启动，请在系统设置里允许 Live Subs 使用麦克风")
            phase = .idle
        }
    }

    private nonisolated func recordMic(_ buffer: AVAudioPCMBuffer) {
        guard let url = micRecordURL else { return }
        if micRecorder == nil { micRecorder = AudioFileWriter.open(url, format: buffer.format) }
        try? micRecorder?.write(from: buffer)
    }

    private func stopMic() {
        micQueue.sync { feeding = false }
        if mic.isRunning {
            mic.inputNode.removeTap(onBus: 0)
            mic.stop()
        }
    }

    private func finishUtterance() {
        stopMic()
        phase = .translating
        guard let u = utterance else { phase = .idle; return }
        utterance = nil
        u.input.finish()
        let released = releasedAt ?? Date()
        releasedAt = nil
        Task {
            let text = await u.text.value
            let textAt = Date()
            finals = []
            volatile = ""
            guard !text.isEmpty else {
                phase = .idle
                onLive?(.idle, "", "")
                return
            }
            let from = settings.speakFromLang.code
            let to = targetCode
            onLive?(.translating, text, "")
            // Never speak the untranslated original into the room: if translation
            // fails, say so on the bar and send nothing.
            let trace = TranslateTrace()
            let result = await translate?(text, from, to, trace)
            let translatedAt = Date()
            @MainActor func timing(voice: Double?) -> SentenceTiming {
                SentenceTiming(at: textAt, side: "me", chars: text.count, recognize: textAt.timeIntervalSince(released),
                               queue: trace.lingQueue, translate: translatedAt.timeIntervalSince(textAt), voice: voice,
                               failed: trace.failedSeconds, via: result == nil ? "none" : trace.via, fallbacks: trace.fallbacks)
            }
            guard let translated = result else {
                debugLog("speak: translation failed, nothing sent")
                onTiming?(timing(voice: nil))
                phase = .idle
                onLive?(.idle, text, "翻译失败，这句话未发送")
                return
            }
            contentLog("SPEAK [\(from)→\(to)] \(text) => \(translated)")
            onUtterance?(text, translated, from, to, Date().timeIntervalSince(pressStarted))
            phase = .speaking
            onLive?(.speaking, text, translated)
            await speak(translated, language: to)
            onTiming?(timing(voice: Date().timeIntervalSince(translatedAt)))
            if phase == .speaking { phase = .idle }
            onLive?(.idle, text, translated)
        }
    }

    // MARK: Voice output

    private func voice(for code: String, identifier: String? = nil) -> AVSpeechSynthesisVoice? {
        if let identifier, let v = AVSpeechSynthesisVoice(identifier: identifier) { return v }
        let lang = code == "zh-CN" ? "zh-CN" : code == "zh-TW" ? "zh-TW" : code
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(lang) }
        return voices.max(by: { $0.quality.rawValue < $1.quality.rawValue }) ?? AVSpeechSynthesisVoice(language: lang)
    }

    func outputDevice() -> OutputDevice? {
        let all = AudioDevices.outputs()
        if !settings.speakOutput.isEmpty, let d = all.first(where: { $0.uid == settings.speakOutput }) { return d }
        return all.first(where: \.isVirtualMic)
    }

    private func synthesize(_ text: String, language: String, voiceID: String?) async -> [AVAudioPCMBuffer] {
        let u = AVSpeechUtterance(string: text)
        u.voice = voice(for: language, identifier: voiceID)
        return await withCheckedContinuation { cont in
            var buffers: [AVAudioPCMBuffer] = []
            var done = false
            synth.write(u) { buf in
                guard !done else { return }
                guard let pcm = buf as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    done = true
                    cont.resume(returning: buffers)
                    return
                }
                buffers.append(pcm)
            }
        }
    }

    /// `device` overrides the chosen output (the virtual mic sound test).
    /// How a language is voiced: a PCM stream (Ming's built-in voices or the user's cloned one) or
    /// a voice on this Mac (nil: the best one for the language).
    enum VoiceRoute {
        case stream((String) -> AsyncThrowingStream<Data, Error>)
        case system(String?)
    }

    /// Set by the app: the voice chosen for a language.
    var route: ((String) -> VoiceRoute)?

    /// Returns after the audio has played. A stream that fails before any audio falls back to the
    /// Mac's voice, so the room always hears the sentence.
    func speak(_ text: String, language: String, device override: OutputDevice? = nil, route forced: VoiceRoute? = nil) async {
        var voiceID: String?
        switch forced ?? route?(language) ?? .system(nil) {
        case .stream(let make):
            if await speakStream(make(text), device: override ?? outputDevice()) { return }
        case .system(let id):
            voiceID = id
        }
        let buffers = await synthesize(text, language: language, voiceID: voiceID)
        guard let first = buffers.first else { return }
        if let url = debugOutputURL, let f = AudioFileWriter.open(url, format: first.format) {
            for b in buffers { try? f.write(from: b) }
        }
        let device = override ?? outputDevice()
        configureOutput(format: first.format, device: device)
        do {
            if !out.isRunning { try out.start() }
        } catch {
            debugLog("voice output failed: \(error)")
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            for (i, b) in buffers.enumerated() {
                if i == buffers.count - 1 {
                    player.scheduleBuffer(b, completionCallbackType: .dataPlayedBack) { _ in cont.resume() }
                } else {
                    player.scheduleBuffer(b)
                }
            }
            player.play()
        }
        var cur = AudioObjectID(0); var sz = UInt32(MemoryLayout<AudioObjectID>.size)
        if let unit = out.outputNode.audioUnit {
            AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &cur, &sz)
        }
        debugLog("spoke \(buffers.count) buffers to \(device?.name ?? "default output") id=\(device?.id ?? 0) readback=\(cur)")
    }

    /// Core Audio restarted (virtual mic install): device IDs changed, rebuild the output next time.
    /// Plays 24 kHz mono 16-bit PCM chunks as they arrive. Returns false if nothing came, so the
    /// caller can fall back to the system voice.
    private func speakStream(_ stream: AsyncThrowingStream<Data, Error>, device: OutputDevice?) async -> Bool {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false) else { return false }
        let started = Date()
        var carry = Data()
        var count = 0
        var firstAt: TimeInterval?
        do {
            for try await chunk in stream {
                var bytes = carry + chunk
                if bytes.count % 2 == 1 { carry = bytes.suffix(1); bytes = bytes.dropLast() } else { carry = Data() }
                let frames = bytes.count / 2
                guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { continue }
                buf.frameLength = AVAudioFrameCount(frames)
                bytes.withUnsafeBytes { raw in
                    let src = raw.bindMemory(to: Int16.self)
                    let dst = buf.floatChannelData![0]
                    for i in 0..<frames { dst[i] = Float(Int16(littleEndian: src[i])) / 32768 }
                }
                if count == 0 {
                    firstAt = Date().timeIntervalSince(started)
                    configureOutput(format: format, device: device)
                    if !out.isRunning { try out.start() }
                }
                player.scheduleBuffer(buf, completionHandler: nil)
                if !player.isPlaying { player.play() }
                count += 1
            }
        } catch {
            debugLog("ming voice failed: \(error)")
            if count == 0 { return false }
        }
        guard count > 0 else { return false }
        // Wait for the queued audio to finish before the next utterance.
        if let tail = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 240) {
            tail.frameLength = 240
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                player.scheduleBuffer(tail, completionCallbackType: .dataPlayedBack) { _ in cont.resume() }
            }
        }
        debugLog("spoke ming \(count) chunks to \(device?.name ?? "default output") first audio \(String(format: "%.2f", firstAt ?? 0)) s")
        return true
    }

    func resetOutput() {
        player.stop()
        out.stop()
        outFormat = nil
        outDeviceUID = nil
    }

    private func configureOutput(format: AVAudioFormat, device: OutputDevice?) {
        let uid = device?.uid ?? ""
        guard outFormat != format || outDeviceUID != uid else { return }
        player.stop()
        out.stop()
        if let device, let unit = out.outputNode.audioUnit {
            var id = device.id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioObjectID>.size))
        }
        out.disconnectNodeOutput(player)
        out.connect(player, to: out.mainMixerNode, format: format)
        outFormat = format
        outDeviceUID = uid
    }

    /// Plays a short sample through the chosen output so the user can check it.
    func preview() {
        Task { await speak(targetCode.hasPrefix("zh") ? "这是对方会听到的声音。" : "This is the voice the room will hear.", language: targetCode) }
    }
}
