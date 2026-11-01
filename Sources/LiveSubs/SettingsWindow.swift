import AppKit
import Carbon.HIToolbox
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case listen, speak, overlay, records
    var id: String { rawValue }
    var title: String {
        switch self {
        case .listen: "听"
        case .speak: "我说话也翻译"
        case .overlay: "字幕条"
        case .records: "会议记录"
        }
    }
    var icon: String {
        switch self {
        case .listen: "waveform"
        case .speak: "mic"
        case .overlay: "captions.bubble"
        case .records: "doc.text"
        }
    }
}

// MARK: - Building blocks

/// A white card of rows separated by hairlines, like System Settings.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var divider = true
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13)).foregroundStyle(Palette.ink)
                    if let detail {
                        Text(detail).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            if divider { Divider().padding(.leading, 16) }
        }
    }
}

/// A grey pill that opens a menu: the value and a small chevron.
struct PillMenu: View {
    let value: String
    let options: [(id: String, title: String)]
    let onPick: (String) -> Void
    var body: some View {
        Menu {
            ForEach(options, id: \.id) { o in Button(o.title) { onPick(o.id) } }
        } label: {
            HStack(spacing: 6) {
                Text(value).font(.system(size: 13)).foregroundStyle(Palette.ink).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.ground))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

struct SoftButton: View {
    let title: String
    var dark = false
    let action: () -> Void
    init(_ title: String, dark: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.dark = dark
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(dark ? Color.white : Palette.ink)
                .padding(.horizontal, 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(dark ? Palette.ink : Color(white: 0.925)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shortcut field

/// Shows a shortcut as key caps; click it, then press the new keys (esc cancels).
/// The talk key also accepts the right ⌥ on its own.
struct ShortcutField: View {
    @ObservedObject var model: AppModel
    let role: AppModel.ShortcutRole
    @State private var recording = false
    @State private var error: String?
    @State private var monitor: Any?
    @State private var rightDown = false

    private var current: Shortcut { role == .talk ? model.settings.talkKey : model.settings.toggleKey }
    private var standard: Shortcut { role == .talk ? .defaultTalk : .defaultToggle }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if current != standard && !recording {
                    Button { error = model.setShortcut(standard, for: role) } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.secondary).frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("恢复默认（\(standard.display)）")
                }
                Button { recording ? stop() : start() } label: {
                    HStack(spacing: 4) {
                        if recording {
                            Text(role == .talk ? "按下组合键，或单按右 ⌥" : "按下新的组合键")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accentInk)
                        } else {
                            ForEach(Array(current.keys.enumerated()), id: \.offset) { KeyCap($0.element) }
                        }
                    }
                    .padding(.horizontal, 8).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(recording ? Palette.accentPale : Palette.ground))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(recording ? Palette.accent : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(recording ? "按 esc 取消" : "点一下，换成别的按键")
            }
            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(Palette.accentInk)
            }
        }
        .onDisappear { stop() }
        // Another app grabbed the keys (its launcher came up): stop waiting for them.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }

    private func start() {
        error = nil
        recording = true
        rightDown = false
        model.suspendShortcuts(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            handle(e)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        model.suspendShortcuts(false)
    }

    private func handle(_ e: NSEvent) {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch e.type {
        case .keyDown:
            if e.keyCode == UInt16(kVK_Escape) && flags.isEmpty { stop(); return }
            commit(Shortcut(keyCode: e.keyCode, flags: flags))
        case .flagsChanged:
            if role == .talk && e.keyCode == UInt16(kVK_RightOption) {
                // Right ⌥ pressed and released with nothing else: that's the choice.
                if e.modifierFlags.rawValue & 0x40 != 0 { rightDown = true } else if rightDown { commit(.rightOption) }
            } else {
                rightDown = false
            }
        default:
            break
        }
    }

    private func commit(_ s: Shortcut) {
        error = model.setShortcut(s, for: role)
        stop()
    }
}

/// "输入监控" is missing for the right ⌥ key: one line and a button.
struct TalkKeyPermissionRow: View {
    @ObservedObject var model: AppModel
    var body: some View {
        SettingsRow(title: "还差一步：允许“输入监控”",
                    detail: "按住右 ⌥ 要用到它。在系统设置里打开 \(appDisplayName)，回到这里就生效") {
            SoftButton("去允许", dark: true) { model.allowTalkKey() }
        }
    }
}

let appDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Live Subs"

// MARK: - Virtual microphone checklist

/// The one place the virtual mic is set up: onboarding step 3 and the settings window.
/// Not ready → a three-step checklist with one button that does the next step.
/// Ready → one line with a status dot and the sound test.
struct MicSetupCard: View {
    @ObservedObject var installer: VirtualMicInstaller
    /// Re-read the device list when the app's copy changes.
    var deviceName: String?

    private var onDisk: Bool { installer.isOnDisk || deviceName != nil }
    private var loaded: Bool { deviceName != nil }

    var body: some View {
        if loaded && installer.passed && installer.state != .testing {
            ready
        } else {
            checklist
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(Color(red: 0.12, green: 0.62, blue: 0.33)).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("虚拟麦克风已就绪").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text("\(deviceName ?? "BlackHole 2ch") · 试音通过，对方听得到").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
                Spacer()
                SoftButton("再试一次") { installer.runTest() }
            }
            if let t = installer.test { TestResultView(result: t) }
        }
        .padding(16)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("虚拟麦克风").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text(statusTag).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(installer.busy ? Palette.accentInk : Palette.tertiary)
            }
            step(1, "安装", "输一次电脑密码", done: onDisk,
                 active: installer.state == .downloading || installer.state == .installing,
                 activeText: installer.state == .downloading ? "正在下载…" : "正在安装…")
            step(2, "让系统认出它", "声音会断一下，约 1 秒", done: loaded,
                 active: installer.state == .reloading, activeText: "正在让系统认出它…")
            step(3, "试音", "自动播一句，确认对方听得到", done: installer.passed,
                 active: installer.state == .testing, activeText: "正在试音…")
            if let t = installer.test, !t.heard, installer.state != .testing {
                TestResultView(result: t)
            }
            if case .failed(let msg) = installer.state {
                Text(msg).font(.system(size: 12)).foregroundStyle(Palette.accentInk)
            }
            if !installer.busy {
                SoftButton(buttonTitle, dark: true) { installer.next() }
            }
        }
        .padding(16)
    }

    private var statusTag: String {
        if installer.busy { return "进行中" }
        if !onDisk { return "没装" }
        if !loaded { return "系统还没认出" }
        return installer.test == nil ? "还没试音" : "没听到声音"
    }

    private var buttonTitle: String {
        if !onDisk { return "一键安装" }
        if !loaded { return "让系统认出它" }
        return installer.test == nil ? "试音" : "再试一次"
    }

    private func step(_ n: Int, _ title: String, _ detail: String, done: Bool, active: Bool, activeText: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Palette.ink : active ? Palette.accentPale : Palette.ground)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                } else if active {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.secondary)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(active ? activeText : title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(done || active ? Palette.ink : Palette.secondary)
                if !done && !active {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
            }
            .padding(.top, 2)
        }
    }
}

struct TestResultView: View {
    let result: VirtualMicInstaller.TestResult
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if result.heard { HStack(alignment: .center, spacing: 2) {
                ForEach(Array(result.levels.enumerated()), id: \.offset) { _, l in
                    Capsule().fill(result.heard ? Palette.accent : Color(white: 0.8))
                        .frame(width: 3, height: max(3, CGFloat(min(1, l * 2.5)) * 24))
                }
            }
            .frame(height: 24) }
            if result.heard {
                (Text("对方会听到：") + Text(result.text.isEmpty ? "一段声音" : "“\(result.text)”").bold())
                    .font(.system(size: 12)).foregroundStyle(Palette.ink)
            } else {
                Text(result.problem ?? "虚拟麦克风里没收到声音，再试一次").font(.system(size: 12)).foregroundStyle(Palette.accentInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(result.heard ? Palette.ground : Palette.accentPale))
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var installer: VirtualMicInstaller

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 190)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.settingsSection.title).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.ink)
                    switch model.settingsSection {
                    case .listen: listen
                    case .speak: speak
                    case .overlay: overlay
                    case .records: records
                    }
                }
                .padding(.leading, 12).padding(.trailing, 28).padding(.top, 40).padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 720, height: 600)
        .background(Color(red: 0.965, green: 0.969, blue: 0.976))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { s in
                let on = s == model.settingsSection
                Button { model.settingsSection = s } label: {
                    HStack(spacing: 10) {
                        Image(systemName: s.icon).font(.system(size: 13))
                            .foregroundStyle(on ? Palette.accent : Palette.secondary).frame(width: 18)
                        Text(s.title).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(Palette.ink)
                        Spacer()
                        if s == .speak && settings.speakEnabled && model.virtualMic == nil {
                            Circle().fill(Palette.accent).frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.white : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Palette.line : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.top, 44).padding(.bottom, 14)
    }

    // MARK: Sections

    private var listen: some View {
        SettingsCard {
            SettingsRow(title: "听到") {
                PillMenu(value: heardValue, options: [("auto", "自动识别")] + sourceLanguages.map { ($0.locale, $0.name) }) {
                    model.sourceSelection = $0
                }
            }
            SettingsRow(title: "翻译成", divider: false) {
                PillMenu(value: settings.target == "system" ? "跟随系统（\(targetName(model.listen.resolvedTarget))）"
                                                            : targetName(settings.target),
                         options: [("system", "跟随系统")] + targetLanguages.map { ($0.code, $0.name) }) {
                    model.targetSelection = $0
                }
            }
        }
    }

    private var heardValue: String {
        if case .fixed(let l) = settings.sourceMode { return l.name }
        return "自动识别"
    }

    private var speak: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard { MicSetupCard(installer: installer, deviceName: model.virtualMic?.name) }
            SettingsCard {
                SettingsRow(title: "我说话也翻译") {
                    Toggle("我说话也翻译", isOn: Binding(get: { settings.speakEnabled }, set: { model.enableSpeaking($0) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: "按住说话",
                            detail: settings.talkKey.isRightOption ? "只按右边的 ⌥；和别的键一起按不算" : nil) {
                    ShortcutField(model: model, role: .talk)
                }
                if settings.speakEnabled && model.talkNeedsPermission { TalkKeyPermissionRow(model: model) }
                SettingsRow(title: "我说的语言") {
                    PillMenu(value: settings.speakFromLang.name, options: sourceLanguages.map { ($0.locale, $0.name) }) {
                        settings.speakFrom = $0
                        model.speakFromChanged()
                    }
                }
                SettingsRow(title: "对方听到") {
                    PillMenu(value: settings.speakTo == "room" ? "跟随对方的语言" : targetName(settings.speakTo),
                             options: [("room", "跟随对方的语言")] + targetLanguages.map { ($0.code, $0.name) }) {
                        settings.speakTo = $0
                    }
                }
                SettingsRow(title: "声音送到", divider: false) {
                    PillMenu(value: outputName,
                             options: [("", "虚拟麦克风（自动）")] + model.outputs.map { ($0.uid, $0.name) }) {
                        settings.speakOutput = $0
                    }
                }
            }
            Text("在会议软件里，把麦克风选成「\(model.virtualMic?.name ?? "BlackHole 2ch")」。")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.horizontal, 4)
        }
    }

    private var outputName: String {
        if settings.speakOutput.isEmpty { return "虚拟麦克风（自动）" }
        return model.outputs.first { $0.uid == settings.speakOutput }?.name ?? "虚拟麦克风（自动）"
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsRow(title: "显示") {
                    Picker("显示", selection: Binding(get: { settings.overlayAuto }, set: { model.setOverlayAuto($0) })) {
                        Text("说话时").tag(true)
                        Text("一直").tag(false)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                }
                if settings.overlayAuto {
                    SettingsRow(title: "安静多久后收起") {
                        Picker("收起", selection: $settings.overlayHideAfter) {
                            Text("2 秒").tag(2.0)
                            Text("4 秒").tag(4.0)
                            Text("8 秒").tag(8.0)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                    }
                }
                SettingsRow(title: "随时显示 / 隐藏", detail: model.toggleKeyTaken ? "被其他应用占用了，点右边换一个" : nil) {
                    ShortcutField(model: model, role: .toggle)
                }
                SettingsRow(title: "位置和大小", detail: "鼠标停住不动可拖动，拖右下角缩放", divider: false) {
                    SoftButton("恢复默认") { model.overlay.resetPosition() }
                }
            }
        }
    }

    private var records: some View {
        SettingsCard {
            SettingsRow(title: "保存会议录音", detail: "只存在这台 Mac 上") {
                Toggle("保存会议录音", isOn: $settings.recordAudio)
                    .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
            }
            SettingsRow(title: "记录文件夹") {
                SoftButton("打开") { NSWorkspace.shared.open(model.store.root) }
            }
            SettingsRow(title: "首次引导", divider: false) {
                SoftButton("重新看") { model.onboardingStep = 1; model.openOnboarding?() }
            }
        }
    }
}
