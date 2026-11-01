import AppKit
import AVFoundation
import AudioToolbox
import CoreAudio
import CoreMedia
import Speech

// MARK: - Audio routing

/// Stateful sample-rate / sample-format converter.
final class PCMConverter {
    private var converter: AVAudioConverter?

    func convert(_ input: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if input.format == format { return input }
        if converter == nil || converter!.inputFormat != input.format || converter!.outputFormat != format {
            converter = AVAudioConverter(from: input.format, to: format)
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }
        if status == .error || out.frameLength == 0 { return nil }
        return out
    }
}

/// Moves audio off the real-time thread, converts it for the analyzer,
/// feeds the live transcriber, and keeps a short ring buffer for language detection.
final class AudioRouter: @unchecked Sendable {
    struct Stats {
        var voicedTotal: Double
        var silenceRun: Double
        /// Seconds of audio since the last pause of ≥ `gapSeconds`.
        var sinceGap: Double
        var recentVoiced: Double
    }

    static let gapSeconds = 1.5

    private let queue = DispatchQueue(label: "com.wquguru.cicada.audio", qos: .userInitiated)
    private let converter = PCMConverter()
    private var format: AVAudioFormat?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var ring: [(buffer: AVAudioPCMBuffer, seconds: Double, voiced: Bool)] = []
    private var ringSeconds = 0.0
    private let ringLimit = 10.0
    private var voicedTotal = 0.0
    private var silenceRun = 0.0
    private var sinceGap = 0.0

    private var recordURL: URL?
    private var recorder: AVAudioFile?

    /// Below this RMS the block counts as silence (≈ -40 dBFS).
    private let voiceThreshold: Float = 0.01

    func push(_ mono: AVAudioPCMBuffer) {
        queue.async { [self] in process(mono) }
    }

    private func process(_ mono: AVAudioPCMBuffer) {
        let n = Int(mono.frameLength)
        guard n > 0, let data = mono.floatChannelData else { return }
        var sum: Float = 0
        for i in 0..<n { sum += data[0][i] * data[0][i] }
        let rms = (sum / Float(n)).squareRoot()
        let seconds = Double(n) / mono.format.sampleRate
        let voiced = rms >= voiceThreshold
        if voiced {
            if silenceRun >= Self.gapSeconds { sinceGap = 0 }
            voicedTotal += seconds
            silenceRun = 0
        } else {
            silenceRun += seconds
        }
        sinceGap += seconds

        guard let format, let converted = converter.convert(mono, to: format) else { return }
        continuation?.yield(AnalyzerInput(buffer: converted))
        if continuation != nil { fed += seconds }
        record(converted)
        ring.append((converted, seconds, voiced))
        ringSeconds += seconds
        while ringSeconds > ringLimit, !ring.isEmpty {
            ringSeconds -= ring.removeFirst().seconds
        }
    }

    /// `replaySeconds` re-feeds recent audio so a newly detected language
    /// doesn't lose the words spoken while detection was running.
    /// Starts writing everything the analyzer hears to an AAC file (nil stops).
    func setRecording(_ url: URL?) {
        queue.sync {
            recorder = nil // closes the previous file
            recordURL = url
        }
    }

    private func record(_ buffer: AVAudioPCMBuffer) {
        guard let url = recordURL else { return }
        if recorder == nil {
            recorder = AudioFileWriter.open(url, format: buffer.format)
            if recorder == nil { recordURL = nil; return }
        }
        try? recorder?.write(from: buffer)
    }

    /// Seconds of audio given to the current analyzer, replay included: the analyzer's clock. A
    /// result ending at t was spoken (fed − t) seconds ago, since the tap runs in real time.
    private var fed = 0.0
    func fedSeconds() -> Double { queue.sync { fed } }

    func attach(format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation, replaySeconds: Double = 0) {
        queue.sync {
            fed = 0
            if self.format != format {
                ring.removeAll()
                ringSeconds = 0
            } else if replaySeconds > 0 {
                var acc = 0.0
                var replay: [AVAudioPCMBuffer] = []
                for item in ring.reversed() {
                    if acc >= replaySeconds { break }
                    acc += item.seconds
                    replay.append(item.buffer)
                }
                for buffer in replay.reversed() { continuation.yield(AnalyzerInput(buffer: buffer)) }
                fed = acc
            }
            self.format = format
            self.continuation?.finish()
            self.continuation = continuation
        }
    }

    func detach() {
        queue.sync {
            continuation?.finish()
            continuation = nil
        }
    }

    func reset() {
        queue.sync {
            continuation?.finish()
            continuation = nil
            ring.removeAll()
            ringSeconds = 0
            voicedTotal = 0
            silenceRun = 0
            sinceGap = 0
        }
    }

    func stats(window: Double = 6) -> Stats {
        queue.sync {
            var acc = 0.0, voiced = 0.0
            for item in ring.reversed() {
                if acc >= window { break }
                acc += item.seconds
                if item.voiced { voiced += item.seconds }
            }
            return Stats(voicedTotal: voicedTotal, silenceRun: silenceRun, sinceGap: sinceGap, recentVoiced: voiced)
        }
    }

    func snapshot(seconds: Double) -> [AVAudioPCMBuffer] {
        queue.sync {
            var acc = 0.0
            var out: [AVAudioPCMBuffer] = []
            for item in ring.reversed() {
                if acc >= seconds { break }
                acc += item.seconds
                out.append(item.buffer)
            }
            return out.reversed()
        }
    }
}


enum AudioFileWriter {
    /// AAC .m4a, mono, at the buffer's sample rate. The processing format must
    /// match the buffers written to it exactly.
    static func open(_ url: URL, format: AVAudioFormat) -> AVAudioFile? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: 32_000,
        ]
        return try? AVAudioFile(forWriting: url, settings: settings,
                                commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    }
}
