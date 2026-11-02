import AppKit
import AVFoundation
import AVKit
import SwiftUI

// MARK: - Brand mark (logo B: a cicada's eyes and wings peeking over a white subtitle card)

/// The logo in its 100-unit design space, y down (same geometry as site/icon.svg and
/// Sources/LiveSubsIcon; keep the three in step). Design: claude.ai/artifact/96R6Md276c3jAS4Mk4Ustn
enum CicadaLogo {
    static let orange = rgb(0xE8552B)
    static let ink = rgb(0x15171C)
    static let white = CGColor(gray: 1, alpha: 1)

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    static func gradient(_ stops: [(UInt32, CGFloat)], at locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { rgb($0.0, $0.1) } as CFArray,
                   locations: locations)!
    }
    static func circle(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        c.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    static func wings(_ c: CGContext) {
        c.move(to: CGPoint(x: 21, y: 42)); c.addQuadCurve(to: CGPoint(x: 44, y: 27), control: CGPoint(x: 26, y: 17))
        c.move(to: CGPoint(x: 78, y: 39)); c.addQuadCurve(to: CGPoint(x: 55, y: 25), control: CGPoint(x: 73, y: 14))
    }
    static let eyes: [(CGFloat, CGFloat)] = [(36, 51), (63, 49)]
    /// The card leans 5° and bleeds off the right and bottom edges, so the eyes peek over it.
    static func tilt(_ c: CGContext) {
        c.translateBy(x: 50, y: 70); c.rotate(by: -5 * .pi / 180); c.translateBy(x: -50, y: -70)
    }

    /// The whole icon, clipped to its squircle. `unit` is device pixels per design unit
    /// (shadows are in device space).
    static func drawIcon(_ c: CGContext, unit: CGFloat) {
        c.saveGState()
        c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100), cornerWidth: 23, cornerHeight: 23, transform: nil))
        c.clip()
        c.drawLinearGradient(gradient([(0xF57447, 1), (0xDC461C, 1)], at: [0, 1]),
                             start: .zero, end: CGPoint(x: 100, y: 100), options: [])
        c.drawLinearGradient(gradient([(0xFFFFFF, 0.2), (0xFFFFFF, 0)], at: [0, 1]),
                             start: .zero, end: CGPoint(x: 0, y: 50), options: [])
        c.setLineCap(.round)
        c.setStrokeColor(white); c.setLineWidth(5.5); wings(c); c.strokePath()

        let eyeShade = gradient([(0x3A3E48, 1), (0x0E0F12, 1)], at: [0, 1])
        for (x, y) in eyes {
            c.saveGState(); circle(c, x, y, 12.5); c.clip()
            let centre = CGPoint(x: x - 3.75, y: y - 6.25)
            c.drawRadialGradient(eyeShade, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: 22.5,
                                 options: [.drawsAfterEndLocation])
            c.restoreGState()
            c.setStrokeColor(white); c.setLineWidth(5); circle(c, x, y, 12.5); c.strokePath()
            c.setFillColor(white); circle(c, x, y, 8.4); c.fillPath()
            c.setFillColor(ink); circle(c, x + 2, y + 2.2, 4.7); c.fillPath()
            c.setFillColor(white); circle(c, x + 3.5, y + 0.6, 1.5); c.fillPath()
        }

        c.saveGState()
        tilt(c)
        let card = CGPath(roundedRect: CGRect(x: 9, y: 60, width: 104, height: 56), cornerWidth: 12, cornerHeight: 12, transform: nil)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: unit), blur: 4 * unit, color: rgb(0x7A1E05, 0.3))
        c.setFillColor(white); c.addPath(card); c.fillPath()
        c.restoreGState()
        c.saveGState(); c.addPath(card); c.clip()
        c.drawLinearGradient(gradient([(0xFFFFFF, 1), (0xF1EEEC, 1)], at: [0, 1]),
                             start: CGPoint(x: 0, y: 60), end: CGPoint(x: 0, y: 116), options: [])
        c.restoreGState()
        c.saveGState(); c.addPath(card); c.setLineWidth(2); c.replacePathWithStrokedPath(); c.clip()
        c.drawLinearGradient(gradient([(0xFFC9B4, 1), (0xFFFFFF, 1), (0xFFE3A8, 1)], at: [0, 0.5, 1]),
                             start: CGPoint(x: 9, y: 0), end: CGPoint(x: 113, y: 0), options: [])
        c.restoreGState()
        c.setLineWidth(5.4)
        c.setStrokeColor(ink); c.move(to: CGPoint(x: 22, y: 75)); c.addLine(to: CGPoint(x: 72, y: 75)); c.strokePath()
        c.setStrokeColor(orange); c.move(to: CGPoint(x: 22, y: 86)); c.addLine(to: CGPoint(x: 49, y: 86)); c.strokePath()
        c.restoreGState()
        c.restoreGState()
    }

    /// One colour for the menu bar: wings, eyes and a whole (not bleeding) card; whites of the eyes and text lines cut out.
    static func drawTemplate(_ c: CGContext, color: CGColor) {
        c.setLineCap(.round)
        c.setStrokeColor(color); c.setLineWidth(6.5); wings(c); c.strokePath()
        c.setFillColor(color)
        for (x, y) in eyes { circle(c, x, y, 12.5) }
        c.fillPath()
        c.saveGState()
        tilt(c)
        let card = CGPath(roundedRect: CGRect(x: 10, y: 60, width: 80, height: 30), cornerWidth: 9, cornerHeight: 9, transform: nil)
        // In one colour the eyes would melt into the card: cut a thin gap around it first.
        c.setBlendMode(.clear); c.setLineWidth(9); c.addPath(card); c.strokePath(); c.setBlendMode(.normal)
        c.addPath(card); c.fillPath()
        c.setBlendMode(.clear); c.setLineWidth(6)
        c.move(to: CGPoint(x: 22, y: 70.5)); c.addLine(to: CGPoint(x: 72, y: 70.5))
        c.move(to: CGPoint(x: 22, y: 80.5)); c.addLine(to: CGPoint(x: 49, y: 80.5))
        c.strokePath()
        c.restoreGState()
        // Eyes as in colour: ring, cut-out white, pupil.
        c.setBlendMode(.clear)
        for (x, y) in eyes { circle(c, x, y, 8.4) }
        c.fillPath()
        c.setBlendMode(.normal)
        for (x, y) in eyes { circle(c, x + 2, y + 2.2, 4.7) }
        c.fillPath()
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
            CicadaLogo.drawIcon(c, unit: abs(c.ctm.a))
            return true
        }
    }()

    /// Menu bar template glyph: the logo in one colour. Paused draws it at 40%.
    static func menuBar(live: Bool, badge: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            // Design units 8…92 across and 16…94 down fill the 16 pt height.
            c.translateBy(x: 1, y: 0.4); c.scaleBy(x: 0.19, y: 0.19); c.translateBy(x: -8, y: -16)
            CicadaLogo.drawTemplate(c, color: CGColor(gray: 0, alpha: live ? 1 : 0.4))
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = appDisplayName
        return badge ? withBadge(img) : img
    }

    /// The glyph with an orange dot top right, while an update is available. A coloured dot
    /// can't be part of a template image, so the glyph is filled with the label colour instead.
    private static func withBadge(_ glyph: NSImage) -> NSImage {
        let image = NSImage(size: glyph.size, flipped: false) { rect in
            glyph.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.labelColor.setFill()
            rect.fill(using: .sourceIn)
            NSColor(red: 0xE8 / 255, green: 0x55 / 255, blue: 0x2B / 255, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 5.5, height: 5.5)).fill()
            return true
        }
        image.accessibilityDescription = L("\(appDisplayName)（有新版本）")
        return image
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
    /// Permissions, Ling key, sample video, speaking.
    static let steps = 4


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 34)
            Group {
                switch step {
                case 1: permissions
                case 2: OnboardingKeyStep(ling: model.ling, settings: settings)
                case 3: tryIt
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
                ForEach(1...Self.steps, id: \.self) { i in
                    Capsule().fill(i <= step ? Palette.ink : Color(white: 0.87)).frame(height: 4)
                }
            }
            Text("\(step) / \(Self.steps)").font(.system(size: 12)).foregroundStyle(Palette.secondary)
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
            if step == 2 {
                OnboardingKeyFooter(ling: model.ling, skip: { step = 3 }, next: { step = 3 })
            } else if step == 1 && !model.systemAudioOK {
                Text("先打开“听电脑里的声音”")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 24).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.87)))
            } else {
                Button {
                    if step < Self.steps { step += 1 } else { onFinish() }
                } label: {
                    HStack(spacing: 8) {
                        Text(step < Self.steps ? L("继续") : L("开始使用"))
                        if step < Self.steps { Image(systemName: "arrow.right") }
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
            title(L("先打开两个开关"), L("去系统设置打开，回来会自动识别。"))
            VStack(spacing: 0) {
                row(icon: "speaker.wave.2", title: L("听电脑里的声音"), tag: L("必需"), tagAccent: true, detail: L("用于生成字幕，不会录制屏幕画面")) {
                    if model.systemAudioOK { done(L("已打开")) } else { primary(L("去开启")) { model.requestSystemAudio() } }
                }
                Divider().padding(.horizontal, 22)
                row(icon: "mic", title: L("麦克风"), tag: L("可选"), detail: L("仅在同声传译时使用")) {
                    switch model.micStatus {
                    case .authorized: done(L("已允许"))
                    case .notDetermined: secondary(L("允许")) { model.requestMicrophone() }
                    default: secondary(L("去打开")) { model.openMicrophoneSettings() }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
            Label("声音只在本机识别", systemImage: "lock")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
    }

    // MARK: Step 3

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 22) {
            title(L("放一段视频试试"), L("点击播放，看看实时字幕效果。"))
            ZStack {
                PlayerSurface(player: sample.player)
                if !sample.playing {
                    Color.black.opacity(0.35)
                    Button { model.ensureListening(); sample.play() } label: {
                        Circle().fill(Color.white).frame(width: 64, height: 64)
                            .overlay(Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(Palette.ink).offset(x: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("播放示例视频"))
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
                            Text(model.liveSource.isEmpty ? L("正在听…") : model.liveSource)
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
                ChoiceRow(label: L("听到"), value: heardName, badge: nil, options: sourceOptions) { model.sourceSelection = $0 }
                ChoiceRow(label: L("翻译成"), value: targetName(model.listen.resolvedTarget),
                          badge: settings.target == "system" ? L("跟随系统") : nil, options: targetOptions) { model.targetSelection = $0 }
            }
            Text("字幕条可任意拖动，拖拽右下角可调整大小。").font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
    }

    private var heardName: String {
        if case .fixed(let l) = settings.sourceMode { return l.name }
        return model.listen.activeLang.map { L("自动 · \($0.name)") } ?? L("自动识别")
    }
    private var sourceOptions: [(id: String, title: String)] {
        [("auto", L("自动识别"))] + sourceLanguages.map { ($0.locale, $0.name) }
    }
    private var targetOptions: [(id: String, title: String)] {
        [("system", L("跟随系统"))] + targetLanguages.map { ($0.code, $0.name) }
    }

    // MARK: Step 4

    private var speaking: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 24) {
                title(L("想让对方听懂你？"), L("按住说\(settings.speakFromLang.name)，对方听到翻译后的语音。"))
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(alignment: .bottom, spacing: 6) {
                        if settings.talkKey.isRightOption {
                            key("⌥", L("右侧 option"), width: 96)
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

            // Turns green by itself once a meeting app reads the virtual mic.
            if model.virtualMic != nil && installer.passed {
                if let user = model.micUsers.first(where: { $0.state == .virtualMic }) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.ok)
                        Text("\(user.name)已选虚拟麦克风，对方能听到译文").font(.system(size: 13)).foregroundStyle(Palette.ok)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.okPale))
                } else {
                    HStack(spacing: 10) {
                        (Text("最后一步：在会议软件中，将麦克风选为 ") + Text(model.virtualMic?.name ?? "BlackHole 2ch").bold())
                            .font(.system(size: 13)).foregroundStyle(Palette.ink)
                        Spacer(minLength: 8)
                        Text("等你选好…").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.accentPale))
                }
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
