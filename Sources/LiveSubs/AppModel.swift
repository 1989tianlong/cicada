import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Wires the engines, the meeting store, the subtitle bar and the UI together.
@MainActor
final class AppModel: ObservableObject {
    let settings = AppSettings()
    let store = SessionStore()
    let overlay = OverlayController()
    let hotkey = HotKey()
    let toggleKey = HotKey(id: 2, keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey)
    lazy var listen = ListenEngine(settings: settings)
    lazy var speak = SpeakEngine(settings: settings)

    @Published var running = false
    @Published var status = "准备就绪"
    @Published var summary = ""
    @Published var installed: Set<String> = []
    @Published var candidates: [Lang] = []
    @Published var outputs: [OutputDevice] = []
    @Published var speakPhase: SpeakEngine.Phase = .idle
    @Published var showSettings = false
    @Published var systemAudioOK = false
    @Published var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var liveSource = ""
    @Published var liveTranslation = ""
    @Published var onboardingStep = 1
    let installer = VirtualMicInstaller()
    let sample = SamplePlayer()
    var openOnboarding: (() -> Void)?

    var openMainWindow: (() -> Void)?
    var showPanel: (() -> Void)?

    private var lineForSegment: [Int: String] = [:]
    private var lineCounter = 0

    init() {
        listen.onSubtitle = { [weak self] src, dst in
            self?.liveSource = src
            self?.liveTranslation = dst
            self?.overlay.clearStatus()
            self?.overlay.setSubtitle(source: src, translation: dst)
        }
        listen.onStatus = { [weak self] text in
            self?.status = text
            self?.overlay.setStatus(text)
        }
        listen.onStateChange = { [weak self] in self?.refresh() }
        listen.onFinal = { [weak self] seg, duration in self?.recordHeard(seg, duration: duration) }
        listen.onTranslated = { [weak self] segID, text in
            guard let self, let line = self.lineForSegment[segID] else { return }
            self.store.setTranslation(lineID: line, text)
        }

        speak.translate = { [weak self] text, from, to in
            await self?.listen.translate(text, source: from, target: to)
        }
        speak.roomLanguage = { [weak self] in self?.listen.activeLang?.code }
        speak.onStatus = { [weak self] text in self?.status = text }
        speak.onLive = { [weak self] phase, src, dst in
            guard let self else { return }
            self.speakPhase = phase
            if !self.overlay.isShown { self.overlay.show() }
            if phase == .idle && src.isEmpty {
                self.overlay.setSpeaking(nil)
            } else {
                self.overlay.setSpeaking(.init(phase: phase, source: src, translation: dst))
            }
        }
        speak.onUtterance = { [weak self] src, dst, from, to, ago in
            self?.recordSaid(src, dst, from: from, to: to, secondsAgo: ago)
        }

        hotkey.onDown = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.speak.pressBegan() } }
        }
        hotkey.onUp = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.speak.pressEnded() } }
        }
        overlay.onCollapsed = { [weak self] in
            self?.listen.clearDisplay()
            self?.overlay.setSubtitle(source: "", translation: "")
        }
        overlay.mode = { [weak self] in
            (self?.settings.overlayAuto ?? true, self?.settings.overlayHideAfter ?? 4)
        }
        toggleKey.onDown = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.overlay.toggleManual() } }
        }
        toggleKey.register()
        refreshOutputs()
    }

    func setOverlayAuto(_ on: Bool) {
        settings.overlayAuto = on
        overlay.modeChanged()
        objectWillChange.send()
    }

    func launch() async {
        await listen.refreshInstalledLocales()
        refresh()
        start()
        if settings.speakEnabled { enableSpeaking(true) }
    }

    func refresh() {
        running = listen.isRunning
        systemAudioOK = listen.isRunning
        summary = listen.languageSummary()
        candidates = listen.candidates
        installed = listen.installedLocales
        if running { status = listen.statusText }
    }

    func refreshOutputs() {
        outputs = AudioDevices.outputs()
    }

    var virtualMic: OutputDevice? { outputs.first(where: \.isVirtualMic) }

    // MARK: Permissions (all from the UI, no Terminal)

    func refreshPermissions() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if mic != micStatus { micStatus = mic }
        let devices = AudioDevices.outputs()
        if devices.map(\.uid) != outputs.map(\.uid) { outputs = devices }
        if systemAudioOK != listen.isRunning { systemAudioOK = listen.isRunning }
    }

    /// Starting the tap triggers the system prompt; if it still fails, open the pane.
    func requestSystemAudio() {
        if !listen.isRunning { start() }
        if !listen.isRunning {
            openSettingsPane("Privacy_ScreenCapture")
        }
        refreshPermissions()
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self.refreshPermissions() } }
        }
    }

    func openMicrophoneSettings() { openSettingsPane("Privacy_Microphone") }

    private func openSettingsPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    func ensureListening() {
        if !listen.isRunning { start() }
    }

    func virtualMicInstalled() {
        refreshOutputs()
        // Core Audio restarts during the install; reattach the system-audio tap.
        listen.reconnectAudio()
        objectWillChange.send()
    }

    // MARK: Start / stop

    func start() {
        guard !listen.isRunning else { return }
        let session = store.begin()
        lineForSegment = [:]
        if settings.recordAudio {
            listen.router.setRecording(store.systemAudioURL(session.id))
            speak.setRecording(store.micAudioURL(session.id))
        }
        listen.start()
        if listen.isRunning {
            overlay.show()
        } else {
            store.end()
        }
        refresh()
    }

    func stop() {
        listen.stop()
        listen.router.setRecording(nil)
        speak.setRecording(nil)
        store.end()
        overlay.hide()
        refresh()
    }

    func setRunning(_ on: Bool) { on ? start() : stop() }

    // MARK: Settings actions

    var sourceSelection: String {
        get {
            if case .fixed(let l) = settings.sourceMode { return l.locale }
            return "auto"
        }
        set {
            settings.sourceMode = newValue == "auto" ? .auto
                : .fixed(sourceLanguages.first(where: { $0.locale == newValue }) ?? sourceLanguages[0])
            listen.sourceModeChanged()
            refresh()
            objectWillChange.send()
        }
    }

    var targetSelection: String {
        get { settings.target }
        set {
            settings.target = newValue
            listen.targetChanged()
            refresh()
            objectWillChange.send()
        }
    }

    func enableSpeaking(_ on: Bool) {
        settings.speakEnabled = on
        objectWillChange.send()
        if on {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if !granted { debugLog("microphone permission denied") }
            }
            hotkey.register()
            refreshOutputs()
            Task { await speak.prepare() }
        } else {
            hotkey.unregister()
            Task { await speak.teardownAnalyzer() }
        }
    }

    func speakFromChanged() {
        objectWillChange.send()
        if settings.speakEnabled { Task { await speak.prepare() } }
    }

    // MARK: Meeting record

    private func recordHeard(_ seg: Segment, duration: Double) {
        guard let start = store.liveStart else { return }
        lineCounter += 1
        let id = "h\(lineCounter)-\(seg.id)"
        lineForSegment[seg.id] = id
        let t = max(0, Date().timeIntervalSince(start) - duration)
        store.append(TranscriptLine(id: id, t: t, speaker: "them", src: seg.text, dst: seg.translation,
                                    srcLang: seg.sourceCode, dstLang: listen.resolvedTarget))
    }

    private func recordSaid(_ src: String, _ dst: String, from: String, to: String, secondsAgo: Double) {
        guard let start = store.liveStart else { return }
        lineCounter += 1
        let t = max(0, Date().timeIntervalSince(start) - secondsAgo)
        store.append(TranscriptLine(id: "m\(lineCounter)", t: t, speaker: "me", src: src, dst: dst,
                                    srcLang: from, dstLang: to))
    }

    // MARK: Export

    func export(_ session: Session, kind: String) {
        if kind == "copy" {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(TranscriptExport.markdown(session), forType: .string)
            return
        }
        let panel = NSSavePanel()
        let ext = kind == "word" ? "docx" : kind == "srt" ? "srt" : "md"
        panel.nameFieldStringValue = "\(session.title).\(ext)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeExport(session, kind: kind, to: url)
    }

    @discardableResult
    func writeExport(_ session: Session, kind: String, to url: URL) -> Bool {
        do {
            switch kind {
            case "word": try TranscriptExport.docx(session).write(to: url)
            case "srt": try TranscriptExport.srt(session).write(to: url, atomically: true, encoding: .utf8)
            default: try TranscriptExport.markdown(session).write(to: url, atomically: true, encoding: .utf8)
            }
            return true
        } catch {
            debugLog("export failed: \(error)")
            return false
        }
    }

    // MARK: Debug control (only with `defaults write com.wquguru.cicada debug -bool true`)

    func installDebugControl() {
        guard settings.debug || DevBuild.isDev else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.wquguru.cicada.debug"), object: nil, queue: .main
        ) { [weak self] note in
            let cmd = note.object as? String ?? ""
            MainActor.assumeIsolated { self?.debugCommand(cmd) }
        }
        debugLog("debug control ready")
    }

    private func debugCommand(_ cmd: String) {
        debugLog("debug command: \(cmd)")
        let parts = cmd.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts.first ?? "" {
        case "start": start()
        case "stop": stop()
        case "open": openMainWindow?()
        case "panel": showPanel?()
        case "onboarding": onboardingStep = Int(arg) ?? 1; openOnboarding?()
        case "step": onboardingStep = Int(arg) ?? 1
        case "samplePlay": ensureListening(); sample.play()
        case "micVerify": installer.install(verifyOnly: true)
        case "settings": openMainWindow?(); showSettings = true
        case "speakOn": enableSpeaking(true)
        case "speakOff": enableSpeaking(false)
        case "speakOut": speak.debugOutputURL = arg.isEmpty ? nil : URL(fileURLWithPath: arg)
        case "speakFile": speak.speakFile(URL(fileURLWithPath: arg))
        case "place":
            let n = arg.split(separator: ",").compactMap { Double($0) }
            if n.count == 4 { overlay.place(x: n[0], y: n[1], width: n[2], fontSize: n[3]) }
        case "overlayState": debugLog("overlay \(overlay.stateDescription)")
        case "overlayToggle": overlay.toggleManual()
        case "overlayAuto": setOverlayAuto(arg != "off")
        case "hideAfter": settings.overlayHideAfter = Double(arg) ?? 4
        case "frame":
            debugLog("overlay frame=\(overlay.barFrame) font=\(overlay.currentFontSize)")
        case "export":
            guard let s = store.sessions.first(where: { $0.id != store.liveID }) ?? store.sessions.first else { return }
            let dir = URL(fileURLWithPath: arg)
            for (kind, ext) in [("md", "md"), ("srt", "srt"), ("word", "docx")] {
                let ok = writeExport(s, kind: kind, to: dir.appendingPathComponent("export.\(ext)"))
                debugLog("export \(ext) ok=\(ok)")
            }
        default: break
        }
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var mainWindow: NSWindow?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var deviceWork: DispatchWorkItem?
    private var onboardingWindow: NSWindow?
    private var pollTimer: Timer?
    private var runningObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        model.openMainWindow = { [weak self] in self?.showMainWindow() }
        model.showPanel = { [weak self] in self?.togglePopover() }
        model.openOnboarding = { [weak self] in self?.showOnboarding() }
        runningObserver = model.$running.sink { [weak self] live in
            self?.statusItem.button?.image = BrandImage.menuBar(live: live)
        }
        let poll = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshPermissions() }
        }
        pollTimer = poll
        RunLoop.main.add(poll, forMode: .common)
        if !UserDefaults.standard.bool(forKey: "onboarded") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                MainActor.assumeIsolated { self?.showOnboarding() }
            }
        }
        model.installDebugControl()
        installDeviceListener()
        Task { await model.launch() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = BrandImage.menuBar(live: false)
            if DevBuild.isDev {
                button.imagePosition = .imageLeading
                button.attributedTitle = NSAttributedString(string: " DEV", attributes: [
                    .font: NSFont.systemFont(ofSize: 9, weight: .heavy),
                    .baselineOffset: 1,
                ])
                button.toolTip = "Live Subs Dev · \(DevBuild.label ?? "")"
            }
            button.action = #selector(togglePopover)
            button.target = self
        }
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: MenuPanelView(model: model, settings: model.settings)
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refreshOutputs()
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: Main window

    func showMainWindow() {
        popover.performClose(nil)
        if mainWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = DevBuild.isDev ? "Live Subs Dev" : "Live Subs"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 760, height: 480)
            w.delegate = self
            w.contentView = NSHostingView(rootView: MainWindowView(model: model, store: model.store, settings: model.settings))
            w.center()
            w.setFrameAutosaveName("LiveSubsMain")
            mainWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func showOnboarding() {
        popover.performClose(nil)
        if onboardingWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "欢迎使用 Live Subs"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: OnboardingView(
                model: model, settings: model.settings, installer: model.installer, sample: model.sample,
                onFinish: { [weak self] in
                    UserDefaults.standard.set(true, forKey: "onboarded")
                    self?.onboardingWindow?.close()
                }))
            w.center()
            onboardingWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        let w = notification.object as? NSWindow
        if w == onboardingWindow {
            model.sample.stop()
            UserDefaults.standard.set(true, forKey: "onboarded")
        }
        let otherOpen = [mainWindow, onboardingWindow].contains { $0 != nil && $0 != w && $0!.isVisible }
        if !otherOpen { NSApp.setActivationPolicy(.accessory) }
    }

    // MARK: Output device changes

    private func installDeviceListener() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputDeviceChanged() }
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
    }

    private func outputDeviceChanged() {
        deviceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                debugLog("default output device changed → reconnecting tap")
                self?.model.listen.reconnectAudio()
                self?.model.refreshOutputs()
            }
        }
        deviceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}

@main
struct LiveSubsMain {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-dmg-background"), args.count > i + 1 {
            let scale = args.count > i + 2 ? Int(args[i + 2]) ?? 1 : 1
            do {
                try DMGBackground.render(to: URL(fileURLWithPath: args[i + 1]), scale: scale)
                exit(0)
            } catch {
                FileHandle.standardError.write("render failed: \(error)\n".data(using: .utf8)!)
                exit(1)
            }
        }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}
