import AppKit

/// What the panel, the app menu and settings show about updates: a newer release, a manual
/// check's result, download progress, and why installing in place failed.
@MainActor
final class Updates: ObservableObject {
    enum Check { case idle, checking, upToDate, failed }

    @Published private(set) var update: UpdateChecker.Update?
    @Published private(set) var check = Check.idle
    /// Download progress (0...1) while an update installs; the app quits and reopens when done.
    @Published private(set) var progress: Double?
    /// Why the last in-place update failed (the release page was opened instead).
    @Published var failure: String?
    /// Set once installing has started: quitting then must not stop to ask about the meeting,
    /// or the swap script would wait for a quit that the user cancelled.
    private(set) var installing = false

    private(set) lazy var checker = UpdateChecker { [weak self] in self?.update = $0 }

    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    /// Daily checks. A dev build has its own bundle id, so a release can't replace it: it checks
    /// only when pointed at a test feed.
    func start() {
        guard !DevBuild.isDev || ProcessInfo.processInfo.environment["CICADA_UPDATE_FEED"] != nil else { return }
        checker.start()
    }

    func checkNow() {
        guard check != .checking else { return }
        check = .checking
        Task {
            let reached = await checker.check()
            check = update != nil ? .idle : reached ? .upToDate : .failed
            try? await Task.sleep(for: .seconds(4))
            if check != .checking { check = .idle }
        }
    }

    /// Installs in place; a meeting being recorded is ended first, after asking.
    /// If installing can't be done, says why and opens the release page.
    func install(model: AppModel) {
        guard let update, progress == nil else { return }
        if model.running, let id = model.store.liveID, !(model.store.session(id)?.lines.isEmpty ?? true) {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = L("正在记录会议")
            alert.informativeText = L("安装更新会结束这场记录，已记下的内容会保存。")
            alert.addButton(withTitle: L("结束并更新"))
            alert.addButton(withTitle: L("取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            model.stop()
        }
        progress = 0
        failure = nil
        installing = true
        Task {
            do {
                try await Updater.install(update) { [weak self] in self?.progress = $0 }
            } catch {
                debugLog("update install failed: \(error.localizedDescription)")
                installing = false
                progress = nil
                failure = error.localizedDescription
                NSWorkspace.shared.open(update.url)
            }
        }
    }
}
