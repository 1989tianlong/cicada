import AppKit
import AVFoundation
import AVKit
import SwiftUI

// MARK: - Brand mark (logo H1: a cicada's eyes and wings peeking over a subtitle bar)

/// The logo in its 100-unit design space, y down (same geometry as site/icon.svg and
/// Sources/LiveSubsIcon; keep the three in step).
enum CicadaLogo {
    static let orange = CGColor(srgbRed: 0.91, green: 0.333, blue: 0.169, alpha: 1)   // #E8552B
    static let ink = CGColor(srgbRed: 0.082, green: 0.09, blue: 0.11, alpha: 1)       // #15171C
    static let white = CGColor(gray: 1, alpha: 1)

    static func wings(_ c: CGContext) {
        c.move(to: CGPoint(x: 18, y: 36)); c.addQuadCurve(to: CGPoint(x: 45, y: 20), control: CGPoint(x: 26, y: 10))
        c.move(to: CGPoint(x: 82, y: 36)); c.addQuadCurve(to: CGPoint(x: 55, y: 20), control: CGPoint(x: 74, y: 10))
    }
    static func circle(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        c.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    static let bar = CGPath(roundedRect: CGRect(x: 12, y: 58, width: 76, height: 28), cornerWidth: 9, cornerHeight: 9, transform: nil)
    static func line(_ c: CGContext, y: CGFloat, length: CGFloat) {
        c.move(to: CGPoint(x: 21, y: y)); c.addLine(to: CGPoint(x: 21 + length, y: y))
    }

    /// Full colour, without the orange squircle (callers draw their own ground).
    static func drawMark(_ c: CGContext) {
        c.setLineCap(.round)
        c.setStrokeColor(white); c.setLineWidth(6); wings(c); c.strokePath()
        c.setFillColor(white); circle(c, 36, 46, 13); circle(c, 64, 46, 13); c.fillPath()
        c.setFillColor(ink); circle(c, 39, 49, 6); circle(c, 67, 49, 6); c.fillPath()
        c.addPath(bar); c.fillPath()
        c.setLineWidth(5)
        c.setStrokeColor(white); line(c, y: 68, length: 44); c.strokePath()
        c.setStrokeColor(orange); line(c, y: 77, length: 26); c.strokePath()
    }

    /// One colour: wings, eyes and bar filled; pupils and text lines cut out.
    static func drawTemplate(_ c: CGContext, color: CGColor) {
        c.setLineCap(.round)
        c.setStrokeColor(color); c.setLineWidth(7); wings(c); c.strokePath()
        c.setFillColor(color); circle(c, 36, 46, 13); circle(c, 64, 46, 13); c.fillPath()
        // In one colour the eyes would melt into the bar: cut a thin gap around it first.
        c.setBlendMode(.clear); c.setLineWidth(9); c.addPath(bar); c.strokePath(); c.setBlendMode(.normal)
        c.addPath(bar); c.fillPath()
        c.setBlendMode(.clear)
        circle(c, 39, 49, 6.5); circle(c, 67, 49, 6.5); c.fillPath()
        c.setLineWidth(6); line(c, y: 68, length: 44); line(c, y: 77, length: 26); c.strokePath()
        c.setBlendMode(.normal)
    }
}

struct BrandMark: View {
    var size: CGFloat = 36
    var body: some View {
        Image(nsImage: BrandImage.mark)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

enum BrandImage {
    /// The in-app mark: the logo on its orange squircle, drawn as a vector image so it is sharp at any size.
    static let mark: NSImage = {
        NSImage(size: NSSize(width: 100, height: 100), flipped: true) { rect in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.scaleBy(x: rect.width / 100, y: rect.height / 100)
            c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100), cornerWidth: 23, cornerHeight: 23, transform: nil))
            c.setFillColor(CicadaLogo.orange); c.fillPath()
            CicadaLogo.drawMark(c)
            return true
        }
    }()

    /// Menu bar template glyph: the logo in one colour. Paused draws it at 40%.
    static func menuBar(live: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            // Design units 10…90 across and 8…88 down fill the 16 pt height.
            c.translateBy(x: 1, y: 0); c.scaleBy(x: 0.2, y: 0.2); c.translateBy(x: -10, y: -8)
            CicadaLogo.drawTemplate(c, color: CGColor(gray: 0, alpha: live ? 1 : 0.4))
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = appDisplayName
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
                row(icon: "speaker.wave.2", title: "听电脑里的声音", tag: "必需", tagAccent: true, detail: "用于生成字幕，不会录制屏幕画面") {
                    if model.systemAudioOK { done("已打开") } else { primary("去开启") { model.requestSystemAudio() } }
                }
                Divider().padding(.horizontal, 22)
                row(icon: "mic", title: "麦克风", tag: "可选", detail: "仅在同声传译时使用") {
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
            title("放一段视频试试", "点击播放，看看实时字幕效果。")
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
            Text("字幕条可任意拖动，拖拽右下角可调整大小。").font(.system(size: 12)).foregroundStyle(Palette.secondary)
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
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(alignment: .bottom, spacing: 6) {
                        if settings.talkKey.isRightOption {
                            key("⌥", "右侧 option", width: 96)
                        } else {
                            ForEach(Array(settings.talkKey.keys.enumerated()), id: \.offset) {
                                key($0.element, "", width: $0.element.count > 2 ? 96 : 52)
                            }
                        }
                    }
                    Text("可在设置中更改").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
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
                if settings.speakEnabled && model.talkNeedsPermission {
                    Divider().padding(.horizontal, 22)
                    TalkKeyPermissionRow(model: model).padding(.horizontal, 6).padding(.vertical, 4)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))

            if model.virtualMic != nil && installer.passed {
                (Text("最后一步：在会议软件中，将麦克风选为 ") + Text(model.virtualMic?.name ?? "BlackHole 2ch").bold())
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
