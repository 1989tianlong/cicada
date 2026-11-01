import AVFoundation
import SwiftUI

/// Settings › 同声传译 › 对方听到的声音: one voice per language the room may speak, each playable,
/// plus the user's own cloned voice.
struct VoiceSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var ling: LingClient

    @State private var tab: String?
    @State private var recording = false
    /// Bumped when the recording changes on disk.
    @State private var cloneVersion = 0

    private var roomKey: String { VoiceCatalog.key(for: model.speak.targetCode) }
    private var current: String { tab ?? roomKey }
    private var language: String { current == "zh" ? "zh-CN" : current }
    private var chosen: String? { model.voiceID(for: language) }
    private static let mainTabs = ["en", "zh", "ja"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("对方听到的声音").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
                Spacer()
                tabs
            }
            Text("每种语言会记住你选的声音。对方当前在说\(title(roomKey))。")
                .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(VoiceCatalog.options(for: language)) { v in card(v) }
            }
            cloneCard
            Text(footnote).font(.system(size: 12)).foregroundStyle(Palette.tertiary).lineSpacing(2)
        }
        .sheet(isPresented: $recording) {
            VoiceCloneSheet(model: model, settings: settings, language: language) { saved in
                recording = false
                if saved {
                    cloneVersion += 1
                    model.setVoice("clone", for: language)
                }
            }
        }
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(Self.mainTabs, id: \.self) { k in tabButton(k, title(k)) }
            Menu {
                ForEach(VoiceCatalog.languages.filter { !Self.mainTabs.contains($0.key) }, id: \.key) { l in
                    Button(l.title) { tab = l.key }
                }
            } label: {
                Text(Self.mainTabs.contains(current) ? "更多…" : title(current))
                    .font(.system(size: 12, weight: Self.mainTabs.contains(current) ? .regular : .semibold))
                    .foregroundStyle(Self.mainTabs.contains(current) ? Palette.secondary : Palette.ink)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Self.mainTabs.contains(current) ? .clear : Color.white))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.925)))
    }

    private func tabButton(_ key: String, _ text: String) -> some View {
        let on = current == key
        return Button { tab = key } label: {
            Text(text).font(.system(size: 12, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Palette.ink : Palette.secondary)
                .padding(.horizontal, 10).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.white : .clear)
                    .shadow(color: .black.opacity(on ? 0.06 : 0), radius: 1, y: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func title(_ key: String) -> String {
        VoiceCatalog.languages.first { $0.key == key }?.title ?? targetName(key)
    }

    // MARK: Cards

    private func card(_ v: VoiceOption) -> some View {
        let selected = chosen == v.id
        let usable = !v.needsKey || ling.usable
        return Button { if usable { model.setVoice(v.id, for: language) } } label: {
            HStack(spacing: 10) {
                playButton(v.id, highlighted: selected, enabled: usable) { model.previewVoice(v.id, language: language) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(v.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    HStack(spacing: 4) {
                        ForEach(usable ? v.tags : [v.tags.first ?? "", "需要 Ling key"], id: \.self) { tagView($0) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Palette.accentWash : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Palette.accent : Palette.line, lineWidth: selected ? 2 : 1))
            .opacity(usable ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tagView(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(Palette.fill))
            .fixedSize()
    }

    private func playButton(_ id: String, highlighted: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        let playing = model.previewing == id
        return Button(action: action) {
            ZStack {
                Circle().fill(highlighted ? Palette.accent : Palette.fill)
                if playing {
                    Spinner(size: 12, track: highlighted ? Color.white.opacity(0.4) : Palette.accentPale)
                } else {
                    Image(systemName: "play.fill").font(.system(size: 10))
                        .foregroundStyle(highlighted ? Color.white : Palette.ink)
                }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || playing)
        .help("试听")
        .accessibilityLabel("试听")
    }

    @ViewBuilder
    private var cloneCard: some View {
        let has = VoiceReference.exists && cloneVersion >= 0
        let selected = chosen == "clone"
        HStack(spacing: 10) {
            if has {
                playButton("clone", highlighted: selected, enabled: ling.usable) { model.previewVoice("clone", language: language) }
            } else {
                ZStack {
                    Circle().fill(Palette.accentPale)
                    Image(systemName: "mic").font(.system(size: 13)).foregroundStyle(Palette.accentInk)
                }
                .frame(width: 30, height: 30)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("我自己的声音").font(.system(size: 13, weight: .semibold))
                Text(has ? "已录好 · \(Int(VoiceReference.duration.rounded())) 秒 · \(cloneNote)"
                         : "录制 15 秒原声，让对方听到你的音色；说外语时会保留你的口音，延迟约 3 秒")
                    .font(.system(size: 12)).foregroundStyle(Palette.tertiary).lineLimit(2)
            }
            Spacer(minLength: 6)
            if has {
                if !selected {
                    SoftButton("用这个") { model.setVoice("clone", for: language) }.disabled(!ling.usable)
                }
                Button("重录") { recording = true }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Button("删除") {
                    VoiceReference.remove()
                    for (k, v) in settings.speakVoices where v == "clone" { settings.speakVoices[k] = nil }
                    cloneVersion += 1
                }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            } else {
                SoftButton("录制") { recording = true }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Palette.accentWash : Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Palette.accent : Palette.line, lineWidth: selected ? 2 : 1))
    }

    private var cloneNote: String {
        let own = VoiceCatalog.key(for: settings.speakFromLang.locale)
        return own == current ? "说\(title(current))最像你，晚约 3 秒" : "说\(title(current))会带你的口音，晚约 3 秒"
    }

    private var footnote: String {
        if !ling.usable { return "未填写 Ling key 时仅可使用系统声音；填入 key 后可使用 Ming 语音或克隆你自己的声音。" }
        if chosen == "clone" { return "录音仅保存在本机，每次发言时随文字发送给 Ling 合成语音；Ling 不可用时自动切回系统声音。" }
        return "Ming 语音需使用 Ling key，延迟约 1.5 秒；Ling 不可用时自动切回系统声音。"
    }
}

// MARK: - Recording sheet

/// Read a passage for 15 s → transcribe it on this Mac → listen to the original and to the clone
/// speaking the room's language → keep it.
struct VoiceCloneSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let language: String
    let onDone: (Bool) -> Void

    @StateObject private var recorder = VoiceRecorder()
    @State private var consent = false
    @State private var player: AVAudioPlayer?
    @State private var clonePlaying = false

    private var ownLocale: String { settings.speakFromLang.locale }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch recorder.phase {
            case .ready: review
            default: record
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(Color.white)
        .onDisappear { recorder.cancel(); player?.stop() }
    }

    // MARK: Record

    private var record: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("录制你的声音").font(.system(size: 18, weight: .bold))
                Text("请用平时开会的自然语气朗读以下段落，约 15 秒，在安静环境下录制效果最佳。")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            Text(VoiceReference.passage(for: ownLocale))
                .font(.system(size: 16)).lineSpacing(7)
                .padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.raised))
                .textSelection(.enabled)
            meter
            Toggle(isOn: $consent) {
                Text("这是我自己的声音。只在我说话时用它替我翻译。").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            .toggleStyle(.checkbox)
            .disabled(recorder.phase == .recording)
            HStack {
                SoftButton("取消") { recorder.cancel(); onDone(false) }
                Spacer()
                switch recorder.phase {
                case .recording:
                    SoftButton("读完了", dark: true) { recorder.finish() }
                        .disabled(recorder.seconds < VoiceRecorder.minSeconds)
                case .checking:
                    HStack(spacing: 8) { Spinner(size: 14); Text("正在听写…").font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                default:
                    SoftButton(recorder.phase == .idle ? "开始录" : "再录一次", dark: true) {
                        recorder.start(locale: ownLocale)
                    }
                    .disabled(!consent)
                }
            }
        }
    }

    @ViewBuilder
    private var meter: some View {
        switch recorder.phase {
        case .recording:
            HStack(spacing: 14) {
                LiveDot()
                Text(NotesEngine.clock(recorder.seconds)).font(.system(size: 14, weight: .semibold).monospacedDigit())
                LevelBars(level: recorder.level)
                Text("\(Int(VoiceRecorder.minSeconds))–\(Int(VoiceRecorder.maxSeconds)) 秒").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.accentWash))
        case .failed(let why):
            Text(why).font(.system(size: 12)).foregroundStyle(Palette.error)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.errorPale))
        default:
            EmptyView()
        }
    }

    // MARK: Review

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("录好了，先听听像不像").font(.system(size: 18, weight: .bold))
                Text("\(Int(recorder.seconds.rounded())) 秒 · 识别出的文字会与录音一起用于学习你的音色")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            VStack(spacing: 0) {
                row(icon: playing ? "stop.fill" : "play.fill", accent: false, title: "你的原声", detail: recorder.transcript) {
                    togglePlayOriginal()
                }
                Divider()
                row(icon: clonePlaying ? nil : "play.fill", accent: true,
                    title: "用你的声音说\(targetTitle)", detail: VoiceCatalog.sample(for: language), tag: "对方会听到这个") {
                    playClone()
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
            if !model.ling.usable {
                Text("需先在“AI 服务”中填入 Ling key，才能使用你自己的声音。").font(.system(size: 12)).foregroundStyle(Palette.error)
            }
            Text("听起来不像或有杂音？换个安静的地方重录一次。录音仅保存在本机，可随时删除。")
                .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            HStack {
                SoftButton("重录") { player?.stop(); recorder.start(locale: ownLocale) }
                Spacer()
                SoftButton("用这个声音", dark: true) { save() }
            }
        }
    }

    private var targetTitle: String {
        VoiceCatalog.languages.first { $0.key == VoiceCatalog.key(for: language) }?.title ?? targetName(language)
    }

    private var playing: Bool { player?.isPlaying ?? false }

    private func row(icon: String?, accent: Bool, title: String, detail: String, tag: String? = nil,
                     action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: action) {
                ZStack {
                    Circle().fill(accent ? Palette.accent : Palette.fill)
                    if let icon {
                        Image(systemName: icon).font(.system(size: 10)).foregroundStyle(accent ? Color.white : Palette.ink)
                    } else {
                        Spinner(size: 12, track: Color.white.opacity(0.4))
                    }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(icon == nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.tertiary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let tag { Tag(tag, live: true) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(accent ? Palette.accentWash : Color.clear)
    }

    private func togglePlayOriginal() {
        if let p = player, p.isPlaying { p.stop(); player = nil; return }
        player = try? AVAudioPlayer(contentsOf: recorder.url)
        player?.play()
    }

    private func playClone() {
        guard model.ling.usable, let data = try? Data(contentsOf: recorder.url) else { return }
        clonePlaying = true
        let ref = (audio: "data:audio/wav;base64," + data.base64EncodedString(), text: recorder.transcript)
        let lang = VoiceCatalog.mingLanguage(for: language)
        let ling = model.ling
        Task {
            await model.speak.speak(VoiceCatalog.sample(for: language), language: language, device: AudioDevices.defaultOutput,
                                    route: .stream { text in ling.speech(text, voice: nil, reference: ref, language: lang) })
            clonePlaying = false
        }
    }

    private func save() {
        do {
            try VoiceReference.save(wav: recorder.url, text: recorder.transcript)
            debugLog("voice clone saved \(Int(recorder.seconds)) s")
            onDone(true)
        } catch {
            debugLog("voice clone save failed: \(error.localizedDescription)")
        }
    }
}

/// A row of bars following the microphone level.
private struct LevelBars: View {
    let level: Float
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<14, id: \.self) { i in
                    let wobble = 0.55 + 0.45 * sin(t * 9 + Double(i) * 1.3)
                    Capsule().fill(Palette.accent)
                        .frame(width: 4, height: max(4, 28 * CGFloat(level) * CGFloat(wobble)))
                }
            }
            .frame(height: 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
