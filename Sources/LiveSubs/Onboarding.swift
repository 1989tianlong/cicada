import AppKit
import AVFoundation
import AVKit
import SwiftUI

// MARK: - Brand mark (logo C: sound bars turning into lines of text)

private func logoBars(_ r: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect) -> [(CGRect, Double)] {
    [(r(20, 42, 7, 16), 1), (r(31, 34, 7, 32), 1), (r(42, 40, 7, 20), 1), (r(57, 40, 24, 7), 1), (r(57, 53, 16, 7), 0.7)]
}

struct BrandMark: View {
    var size: CGFloat = 36
    var body: some View {
        Canvas { ctx, sz in
            let u = sz.width / 100
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * u, y: y * u, width: w * u, height: h * u)
            }
            ctx.fill(Path(roundedRect: r(4, 4, 92, 92), cornerRadius: 22 * u), with: .color(Palette.accent))
            for (rect, alpha) in logoBars(r) {
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2),
                         with: .color(.white.opacity(alpha)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum BrandImage {
    /// Menu bar template glyph: sound bars and text lines. Paused draws it at 40%.
    static func menuBar(live: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { _ in
            NSColor.black.withAlphaComponent(live ? 1 : 0.4).setFill()
            // 100-unit logo design space scaled into 20 × 16 (bars are a little bolder at this size).
            let u: CGFloat = 0.22
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
                NSRect(x: (x - 14) * u, y: (y - 26) * u - 0.4, width: w * u + 0.6, height: h * u + 0.6)
            }
            for (rect, _) in logoBars(r) {
                NSBezierPath(roundedRect: rect, xRadius: min(rect.width, rect.height) / 2,
                             yRadius: min(rect.width, rect.height) / 2).fill()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Live Subs"
        return img
    }
}

// MARK: - Sample clip

/// Plays the bundled 7-second sample. The picture shows in the onboarding card;
/// the sound is played by a separate `afplay` process, because the app leaves
/// its own audio out of what it listens to.
@MainActor
final class SamplePlayer: ObservableObject {
    @Published private(set) var playing = false
    @Published private(set) var progress = 0.0
    let player: AVPlayer?
    private var audio: Process?
    private var timer: Timer?
    private var started = Date()
    private let duration = 7.4

    init() {
        if let url = Bundle.main.url(forResource: "sample", withExtension: "mp4") {
            player = AVPlayer(url: url)
            player?.isMuted = true
        } else {
            player = nil
        }
    }

    func play() {
        guard !playing, let audioURL = Bundle.main.url(forResource: "sample", withExtension: "m4a") else { return }
        player?.seek(to: .zero)
        player?.play()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        p.arguments = [audioURL.path]
        try? p.run()
        audio = p
        playing = true
        started = Date()
        progress = 0
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func tick() {
        progress = min(1, Date().timeIntervalSince(started) / duration)
        if progress >= 1 { stop() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if audio?.isRunning == true { audio?.terminate() }
        audio = nil
        player?.pause()
        playing = false
    }
}

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer?
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .none
        v.videoGravity = .resizeAspectFill
        v.player = player
        return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

// MARK: - Onboarding

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var installer: VirtualMicInstaller
    @ObservedObject var sample: SamplePlayer
    private var step: Int {
        get { model.onboardingStep }
        nonmutating set { model.onboardingStep = newValue }
    }
    var onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 34)
            Group {
                switch step {
                case 1: permissions
                case 2: tryIt
                default: speaking
                }
            }
            .padding(.top, 28)
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 64)
        .padding(.bottom, 36)
        .frame(width: 860, height: 640)
        .background(Color(red: 0.965, green: 0.969, blue: 0.976))
        .onChange(of: step) { _, _ in sample.stop() }
    }

    // MARK: Header / footer

    private var header: some View {
        HStack(spacing: 14) {
            BrandMark(size: 34)
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { i in
                    Capsule().fill(i <= step ? Palette.ink : Color(white: 0.87)).frame(height: 4)
                }
            }
            Text("\(step) / 3").font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if step == 1 {
                Button("以后再说") { step = 2 }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
            } else {
                Button("上一步") { step -= 1 }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
            }
            Spacer()
            if step == 1 && !model.systemAudioOK {
                Text("先打开“听电脑里的声音”")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 24).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.87)))
            } else {
                Button {
                    if step < 3 { step += 1 } else { onFinish() }
                } label: {
                    HStack(spacing: 8) {
                        Text(step < 3 ? "继续" : "开始使用")
                        if step < 3 { Image(systemName: "arrow.right") }
                    }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 28).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.ink))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13))
    }

    private func title(_ text: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.ink)
            Text(sub).font(.system(size: 14)).foregroundStyle(Palette.secondary)
        }
    }

    private func row<Trailing: View>(icon: String, tint: Color = Palette.ground, iconColor: Color = Palette.ink,
                                     title: String, tag: String? = nil, tagAccent: Bool = false, detail: String,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 12).fill(tint).frame(width: 44, height: 44)
                .overlay(Image(systemName: icon).font(.system(size: 18)).foregroundStyle(iconColor))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                    if let tag {
                        Text(tag).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tagAccent ? Palette.accentInk : Palette.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(tagAccent ? Palette.accentPale : Color(white: 0.94)))
                    }
                }
                Text(detail).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 22).padding(.vertical, 20)
    }

    private func done(_ text: String) -> some View {
        Label(text, systemImage: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
    }

    private func primary(_ text: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 16).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.ink))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func secondary(_ text: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 16).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.84), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var card: some ShapeStyle { Color.white }

    // MARK: Step 1

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 24) {
            title("先打开两个开关", "去系统设置打开，回来会自动识别。")
            VStack(spacing: 0) {
                row(icon: "speaker.wave.2", title: "听电脑里的声音", tag: "必需", tagAccent: true, detail: "生成字幕用，不录屏幕") {
                    if model.systemAudioOK { done("已打开") } else { primary("去打开") { model.requestSystemAudio() } }
                }
                Divider().padding(.horizontal, 22)
                row(icon: "mic", title: "麦克风", tag: "可选", detail: "说话翻译时才用") {
                    switch model.micStatus {
                    case .authorized: done("已允许")
                    case .notDetermined: secondary("允许") { model.requestMicrophone() }
                    default: secondary("去打开") { model.openMicrophoneSettings() }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
            Label("声音只在本机识别", systemImage: "lock")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
    }

    // MARK: Step 2

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("放一段视频试试", "点播放，看字幕出来。")
            ZStack {
                PlayerSurface(player: sample.player)
                if !sample.playing {
                    Color.black.opacity(0.35)
                    Button { model.ensureListening(); sample.play() } label: {
                        Circle().fill(Color.white).frame(width: 64, height: 64)
                            .overlay(Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(Palette.ink).offset(x: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("播放示例视频")
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("示例 · 0:07").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.5)))
                        }
                    }
                    .padding(12)
                }
                if sample.playing || !model.liveTranslation.isEmpty {
                    VStack {
                        GeometryReader { g in
                            Rectangle().fill(Palette.accent).frame(width: g.size.width * sample.progress, height: 3)
                        }
                        .frame(height: 3)
                        Spacer()
                        VStack(spacing: 4) {
                            Text(model.liveSource.isEmpty ? "正在听…" : model.liveSource)
                                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65)).lineLimit(1).truncationMode(.head)
                            Text(model.liveTranslation)
                                .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white).lineLimit(2).truncationMode(.head)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.05, opacity: 0.9)))
                        .padding(.horizontal, 40).padding(.bottom, 18)
                    }
                }
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.1, green: 0.11, blue: 0.13)))

            HStack(spacing: 12) {
                ChoiceRow(label: "听到", value: heardName, badge: nil, options: sourceOptions) { model.sourceSelection = $0 }
                ChoiceRow(label: "翻译成", value: targetName(model.listen.resolvedTarget),
                          badge: settings.target == "system" ? "跟随系统" : nil, options: targetOptions) { model.targetSelection = $0 }
            }
            Text("字幕条可以拖动，拖右下角改大小。").font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
    }

    private var heardName: String {
        if case .fixed(let l) = settings.sourceMode { return l.name }
        return model.listen.activeLang.map { "自动 · \($0.name)" } ?? "自动识别"
    }
    private var sourceOptions: [(id: String, title: String)] {
        [("auto", "自动识别")] + sourceLanguages.map { ($0.locale, $0.name) }
    }
    private var targetOptions: [(id: String, title: String)] {
        [("system", "跟随系统")] + targetLanguages.map { ($0.code, $0.name) }
    }

    // MARK: Step 3

    private var speaking: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 24) {
                title("想让对方听懂你？", "按住说\(settings.speakFromLang.name)，对方听到翻译后的语音。")
                Spacer()
                HStack(alignment: .bottom, spacing: 6) {
                    key("⌥", "option", width: 58)
                    key("", "space", width: 120)
                }
            }
            VStack(spacing: 0) {
                MicSetupCard(installer: installer, deviceName: model.virtualMic?.name)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                Divider().padding(.horizontal, 22)
                HStack(spacing: 16) {
                    Text("按住说话").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Toggle("按住说话", isOn: Binding(get: { settings.speakEnabled }, set: { model.enableSpeaking($0) }))
                        .toggleStyle(.switch).labelsHidden().tint(Palette.ink)
                }
                .padding(.horizontal, 22).padding(.vertical, 14)
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))

            if model.virtualMic != nil && installer.passed {
                (Text("最后一步：在会议软件里，把麦克风选成 ") + Text(model.virtualMic?.name ?? "BlackHole 2ch").bold())
                    .font(.system(size: 13)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.accentPale))
            }
        }
    }

    private func key(_ top: String, _ bottom: String, width: CGFloat) -> some View {
        VStack(alignment: .leading) {
            Text(top).frame(maxWidth: .infinity, alignment: .trailing)
            Spacer(minLength: 0)
            Text(bottom)
        }
        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(width: width, height: 52)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.84), lineWidth: 1))
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.84)).frame(height: 3).padding(.horizontal, 1)
        }
    }
}
