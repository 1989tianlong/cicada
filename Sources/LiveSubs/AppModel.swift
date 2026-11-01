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
    let talkCombo = HotKey(id: 1, shortcut: .defaultTalk)
    let talkRight = RightOptionKey()
    let toggleKey = HotKey(id: 2, shortcut: .defaultToggle)
    lazy var listen = ListenEngine(settings: settings)
    lazy var speak = SpeakEngine(settings: settings)

    @Published var running = false
    @Published var status = "准备就绪"
    @Published var summary = ""
    @Published var installed: Set<String> = []
    @Published var candidates: [Lang] = []
    @Published var outputs: [OutputDevice] = []
    @Published var speakPhase: SpeakEngine.Phase = .idle
    @Published var settingsSection: SettingsSection = .speak
    @Published var systemAudioOK = false
    @Published var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var liveSource = ""
    @Published var liveTranslation = ""
    @Published var onboardingStep = 1
    /// Hold right ⌥ is chosen but "输入监控" isn't allowed yet.
    @Published var talkNeedsPermission = false
    @Published var toggleKeyTaken = false
    private var permissionPoll: Timer?
    private var shortcutsSuspended = false
    let installer = VirtualMicInstaller()
    let ling = LingClient()
    lazy var translator = TranslationService(ling: ling)
    lazy var notes = NotesEngine(ling: ling, store: store)
    lazy var notesWindow = NotesWindowController(model: self)
    let sample = SamplePlayer()
    var openOnboarding: (() -> Void)?

    var openMainWindow: (() -> Void)?
    var openSettingsWindow: (() -> Void)?
    var showPanel: (() -> Void)?

    private var lineForSegment: [Int: String] = [:]
    private var lineCounter = 0

    init() {
        listen.onSubtitle = { [weak self] src, dst in
            self?.liveSource = src
            self?.liveTranslation = dst
            guard self?.settings.displayMode == "bar" else { return }
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

        ling.model = { [weak self] in self?.settings.aiModel ?? "Ling-3.1-flash" }
        listen.translator = translator
        translator.glossary = { [weak self] in self?.notes.glossary ?? [] }
        notes.language = {
            // The app speaks Chinese, so notes do too when Chinese is among the system languages.
            let prefs = Locale.preferredLanguages
            let pick = prefs.first(where: { $0.hasPrefix("zh") }) ?? prefs.first ?? "zh-Hans"
            return TranslationService.englishName(translationCode(forSystemLanguage: pick))
        }
        if ling.hasKey { Task { await ling.check() } }

        installer.speakThrough = { [weak self] text, lang, device in
            await self?.speak.speak(text, language: lang, device: device)
        }
        installer.onLoaded = { [weak self] in self?.virtualMicInstalled() }

        speak.translate = { [weak self] text, from, to in
            await self?.listen.translate(text, source: from, target: to, kind: .speak)
        }
        speak.roomLanguage = { [weak self] in self?.listen.activeLang?.code }
        speak.mingVoice = nil
        applyVoice()
        speak.onStatus = { [weak self] text in self?.status = text }
        speak.onLive = { [weak self] phase, src, dst in
            guard let self else { return }
            self.speakPhase = phase
            guard self.settings.displayMode == "bar" else {
                // The notes window's caption line shows what you are saying.
                if phase != .idle || !src.isEmpty {
                    self.liveSource = src.isEmpty ? "你正在说…" : "你：\(src)"
                    self.liveTranslation = dst
                }
                return
            }
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

        let began: () -> Void = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.speak.pressBegan() } }
        }
        let ended: () -> Void = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.speak.pressEnded() } }
        }
        talkCombo.onDown = began
        talkCombo.onUp = ended
        talkRight.onDown = began
        talkRight.onUp = ended
        talkRight.onCancel = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.speak.pressCancelled() } }
        }
        overlay.onCollapsed = { [weak self] in
            self?.listen.clearDisplay()
            self?.overlay.setSubtitle(source: "", translation: "")
        }
        overlay.mode = { [weak self] in
            (self?.settings.overlayAuto ?? true, self?.settings.overlayHideAfter ?? 4)
        }
        toggleKey.onDown = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.cycleDisplay() } }
        }
        applyToggleKey()
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

    func openSettings(_ section: SettingsSection? = nil) {
        if let section { settingsSection = section }
        openSettingsWindow?()
    }

    func ensureListening() {
        if !listen.isRunning { start() }
    }

    func virtualMicInstalled() {
        refreshOutputs()
        // Core Audio restarted to load the driver: device IDs changed, reattach the
        // system-audio tap and rebuild the voice output.
        speak.resetOutput()
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
        notes.begin(session.id)
        if listen.isRunning {
            showDisplay()
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
        notes.finish()
        overlay.hide()
        refresh()
    }

    func setRunning(_ on: Bool) { on ? start() : stop() }

    // MARK: Display (live notes / subtitle bar / nothing)

    func setDisplayMode(_ mode: String) {
        settings.displayMode = mode
        objectWillChange.send()
        showDisplay()
    }

    /// ⌃⌥S: notes → subtitle bar → nothing → notes.
    func cycleDisplay() {
        let order = ["notes", "bar", "none"]
        let i = order.firstIndex(of: settings.displayMode) ?? 0
        setDisplayMode(order[(i + 1) % order.count])
    }

    private func showDisplay() {
        switch settings.displayMode {
        case "bar":
            notesWindow.hide()
            if listen.isRunning { overlay.show() }
        case "none":
            notesWindow.hide()
            overlay.hide()
        default:
            overlay.hide()
            if listen.isRunning { notesWindow.show() }
        }
    }

    func openNotesWindow() {
        if settings.displayMode != "notes" { setDisplayMode("notes") }
        notesWindow.show()
    }

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
            if settings.talkKey.isRightOption && !RightOptionKey.allowed { RightOptionKey.requestAccess() }
            applyTalkKey()
            refreshOutputs()
            Task { await speak.prepare() }
        } else {
            applyTalkKey()
            Task { await speak.teardownAnalyzer() }
        }
    }

    // MARK: Shortcuts

    enum ShortcutRole { case talk, toggle }

    /// Arms the talk key for the current setting. Right ⌥ waits for "输入监控" and
    /// arms itself as soon as it's allowed (no relaunch).
    func applyTalkKey() {
        talkCombo.unregister()
        talkRight.stop()
        var needsPermission = false
        if settings.speakEnabled && !shortcutsSuspended {
            if settings.talkKey.isRightOption {
                needsPermission = !talkRight.start()
            } else {
                talkCombo.register(settings.talkKey)
            }
        }
        if talkNeedsPermission != needsPermission { talkNeedsPermission = needsPermission }
        if needsPermission, permissionPoll == nil {
            permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if RightOptionKey.allowed || !self.settings.speakEnabled || !self.settings.talkKey.isRightOption {
                        self.permissionPoll?.invalidate()
                        self.permissionPoll = nil
                        self.applyTalkKey()
                    }
                }
            }
        }
    }

    func applyToggleKey() {
        toggleKey.unregister()
        guard !shortcutsSuspended else { return }
        let ok = toggleKey.register(settings.toggleKey)
        if toggleKeyTaken == ok { toggleKeyTaken = !ok }
    }

    func allowTalkKey() {
        RightOptionKey.requestAccess()
        RightOptionKey.openSystemSettings()
    }

    /// While a shortcut field is recording, our own shortcuts must not swallow the keys.
    func suspendShortcuts(_ on: Bool) {
        shortcutsSuspended = on
        applyTalkKey()
        applyToggleKey()
    }

    /// Validates and saves a new shortcut. Returns why it was refused, or nil.
    func setShortcut(_ s: Shortcut, for role: ShortcutRole) -> String? {
        if role == .toggle && s.isRightOption { return "右 ⌥ 只能用来按住说话" }
        if let p = s.typingProblem { return p }
        let other = role == .talk ? settings.toggleKey : settings.talkKey
        if s == other { return "和另一个快捷键重复了" }
        if s.isSystemShortcut { return "\(s.display) 是系统快捷键，换一个吧" }
        if !s.isRightOption {
            // Probe: Carbon refuses a combo another app already registered.
            let probe = HotKey(id: 9, shortcut: s)
            let free = probe.register()
            probe.unregister()
            if !free { return "\(s.display) 已被其他应用占用，换一个吧" }
        }
        switch role {
        case .talk:
            settings.talkKey = s
            if s.isRightOption && settings.speakEnabled && !RightOptionKey.allowed { RightOptionKey.requestAccess() }
        case .toggle:
            settings.toggleKey = s
        }
        applyTalkKey()
        applyToggleKey()
        objectWillChange.send()
        return nil
    }

    /// Ming's voice when chosen and a key works; otherwise the system voice.
    func applyVoice() {
        speak.mingVoice = settings.speakVoice == "ming" ? { [weak self] text in
            guard let self, self.ling.usable else {
                return AsyncThrowingStream { $0.finish(throwing: LingClient.Failure.noKey) }
            }
            return self.ling.speech(text)
        } : nil
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
        case "settings":
            settingsSection = SettingsSection(rawValue: arg) ?? settingsSection
            openSettings(settingsSection)
        case "micTest": installer.runTest()
        case "micNext": installer.next()
        case "talkKey", "toggleKey":
            let s = arg == "right" ? Shortcut.rightOption : Shortcut(stored: arg)
            let refusal = s.map { setShortcut($0, for: parts[0] == "talkKey" ? .talk : .toggle) } ?? "bad shortcut"
            debugLog("\(parts[0]) \(arg): \(refusal ?? "ok")")
        case "shortcuts":
            debugLog("shortcuts talk=\(settings.talkKey.display) armed=\(talkRight.isRunning || talkCombo.isRegistered) needsPermission=\(talkNeedsPermission) inputMonitoring=\(RightOptionKey.allowed) toggle=\(settings.toggleKey.display) taken=\(toggleKeyTaken)")
        case "aiKeyFile":
            // Dev testing: the key comes from a file so it never passes through the log.
            if let k = try? String(contentsOfFile: arg, encoding: .utf8) { Task { await ling.setKey(k) } }
        case "aiCheck": Task { await ling.check() }
        case "voice":
            settings.speakVoice = arg == "ming" ? "ming" : "system"
            applyVoice()
        case "notesNow": notes.updateNow()
        case "display": setDisplayMode(arg)
        case "notesWindow":
            let v = arg.split(separator: ",").compactMap { Double($0) }
            openNotesWindow()
            if v.count == 4 { notesWindow.place(NSRect(x: v[0], y: v[1], width: v[2], height: v[3])) }
        case "notesFrame": debugLog("notes window frame=\(String(describing: notesWindow.frame)) visible=\(notesWindow.isVisible)")
        case "notesReplay": Task { await notes.replay(arg) }
        case "notesShow": notes.show(arg)
        case "notesCapturable": notesWindow.setCapturable(arg != "off")
        case "notesRender":
            // The whole notes column as a PNG, for checking what is below the fold.
            let view = NotesContentView(notes: notes.notes, fresh: notes.fresh, live: store.liveID != nil)
                .padding(24).frame(width: 460).background(Color.white)
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: arg))
            }
        case "notesState": debugLog("notes state=\(notes.state) topics=\(notes.notes.topics.count) covered=\(notes.notes.covered) glossary=\(notes.glossary.count)")
        case "lingSimulate":
            ling.simulate = ["429": .rateLimited, "hijack": .hijacked, "timeout": .timeout][arg]
            debugLog("ling simulate=\(String(describing: ling.simulate))")
        case "aiRemove": ling.removeKey()
        case "aiState": debugLog("ai state=\(ling.keyState) hasKey=\(ling.hasKey) model=\(settings.aiModel)")
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
    private var settingsWindow: NSWindow?
    private var pollTimer: Timer?
    private var runningObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        model.openMainWindow = { [weak self] in self?.showMainWindow() }
        model.openSettingsWindow = { [weak self] in self?.showSettingsWindow() }
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

    func showSettingsWindow() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "设置"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: SettingsView(model: model, settings: model.settings, installer: model.installer))
            w.center()
            settingsWindow = w
        }
        model.refreshOutputs()
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
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
        let otherOpen = [mainWindow, onboardingWindow, settingsWindow].contains { $0 != nil && $0 != w && $0!.isVisible }
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
