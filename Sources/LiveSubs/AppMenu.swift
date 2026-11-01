import AppKit

/// The menus in the top-left of the screen. They show while the main, settings or onboarding
/// window is in front (the app is a regular app then; the notes window never activates it).
/// The Edit menu also makes ⌘C / ⌘V / ⌘A work in text fields.
@MainActor
final class AppMenu: NSObject, NSMenuItemValidation {
    private weak var model: AppModel?
    var showMainWindow: () -> Void = {}
    var showOnboarding: () -> Void = {}

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func install() {
        let name = appDisplayName
        let main = NSMenu()

        let app = NSMenu(title: name)
        app.addItem(item("关于 \(name)", #selector(about)))
        app.addItem(.separator())
        app.addItem(item("设置…", #selector(openSettings), ","))
        app.addItem(item("AI 服务…", #selector(openAI)))
        app.addItem(.separator())
        app.addItem(item("隐藏 \(name)", #selector(NSApplication.hide(_:)), "h", target: NSApp))
        app.addItem(item("隐藏其他", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], target: NSApp))
        app.addItem(item("全部显示", #selector(NSApplication.unhideAllApplications(_:)), target: NSApp))
        app.addItem(.separator())
        app.addItem(item("退出 \(name)", #selector(NSApplication.terminate(_:)), "q", target: NSApp))
        add(app, to: main)

        let notes = NSMenu(title: "纪要")
        notes.addItem(item("停止记录", #selector(toggleRecording), "r"))
        notes.addItem(item("立即更新纪要", #selector(updateNotes), "u"))
        notes.addItem(item("收起后的新内容", #selector(catchUp), "j"))
        notes.addItem(.separator())
        notes.addItem(item("复制纪要", #selector(copyNotes), "c", [.command, .shift]))
        let export = NSMenu(title: "导出")
        export.addItem(item("Markdown…", #selector(exportNotes(_:)), "e", tag: 0))
        export.addItem(item("Word…", #selector(exportNotes(_:)), tag: 1))
        export.addItem(item("SRT 字幕…", #selector(exportNotes(_:)), tag: 2))
        let exportItem = NSMenuItem(title: "导出", action: nil, keyEquivalent: "")
        exportItem.submenu = export
        notes.addItem(exportItem)
        notes.addItem(.separator())
        notes.addItem(item("会议记录", #selector(openRecords), "0"))
        add(notes, to: main)

        let display = NSMenu(title: "显示")
        display.addItem(item("实时纪要", #selector(setDisplay(_:)), tag: 0))
        display.addItem(item("字幕条", #selector(setDisplay(_:)), tag: 1))
        display.addItem(item("不显示", #selector(setDisplay(_:)), tag: 2))
        display.addItem(.separator())
        display.addItem(item("小卡", #selector(setSize(_:)), "1", tag: 0))
        display.addItem(item("侧栏", #selector(setSize(_:)), "2", tag: 1))
        display.addItem(item("纪要和原话并排", #selector(setSize(_:)), "3", tag: 2))
        display.addItem(.separator())
        display.addItem(item("始终置顶", #selector(toggleOnTop)))
        add(display, to: main)

        // Standard actions with no target go down the responder chain (text fields, selectable text).
        let edit = NSMenu(title: "编辑")
        edit.addItem(item("撤销", Selector(("undo:")), "z", chain: true))
        edit.addItem(item("重做", Selector(("redo:")), "z", [.command, .shift], chain: true))
        edit.addItem(.separator())
        edit.addItem(item("剪切", #selector(NSText.cut(_:)), "x", chain: true))
        edit.addItem(item("拷贝", #selector(NSText.copy(_:)), "c", chain: true))
        edit.addItem(item("粘贴", #selector(NSText.paste(_:)), "v", chain: true))
        edit.addItem(item("全选", #selector(NSText.selectAll(_:)), "a", chain: true))
        edit.addItem(.separator())
        edit.addItem(item("搜索文字记录", #selector(search), "f"))
        add(edit, to: main)

        let window = NSMenu(title: "窗口")
        window.addItem(item("最小化", #selector(NSWindow.performMiniaturize(_:)), "m", chain: true))
        window.addItem(item("关闭", #selector(NSWindow.performClose(_:)), "w", chain: true))
        window.addItem(.separator())
        window.addItem(item("实时纪要", #selector(openNotes)))
        window.addItem(item("会议记录", #selector(openRecords)))
        add(window, to: main)

        let help = NSMenu(title: "帮助")
        help.addItem(item("新手引导", #selector(onboarding)))
        add(help, to: main)

        NSApp.mainMenu = main
        NSApp.windowsMenu = window
        NSApp.helpMenu = help
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0,
                      target: AnyObject? = nil, chain: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.tag = tag
        i.target = chain ? nil : (target ?? self)
        return i
    }

    private func add(_ menu: NSMenu, to main: NSMenu) {
        let top = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        top.submenu = menu
        main.addItem(top)
    }

    // MARK: State

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let model else { return false }
        let notesWindow = model.notesWindow
        let session = model.store.session(model.store.liveID ?? model.notes.shownID)
        switch item.action {
        case #selector(toggleRecording):
            item.title = model.running ? "停止记录" : "开始记录"
            return true
        case #selector(updateNotes):
            return model.store.liveID != nil && model.ling.hasKey && model.notes.state != .updating
        case #selector(catchUp):
            return notesWindow.isVisible && !model.notes.notes.isEmpty
        case #selector(copyNotes):
            return !model.notes.notes.isEmpty
        case #selector(exportNotes(_:)):
            return session.map { !$0.lines.isEmpty } ?? false
        case #selector(setDisplay(_:)):
            item.state = ["notes", "bar", "none"][item.tag] == model.settings.displayMode ? .on : .off
            return true
        case #selector(setSize(_:)):
            item.state = notesWindow.isVisible && notesWindow.layout == NotesWindowController.Layout.allCases[item.tag] ? .on : .off
            return true
        case #selector(toggleOnTop):
            item.state = notesWindow.onTop ? .on : .off
            return true
        case #selector(search):
            return notesWindow.isVisible
        default:
            return true
        }
    }

    // MARK: Actions

    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openSettings() { model?.openSettings() }
    @objc private func openAI() { model?.openSettings(.ai) }
    @objc private func openRecords() { showMainWindow() }
    @objc private func onboarding() { showOnboarding() }
    @objc private func openNotes() { model?.openNotesWindow() }

    @objc private func toggleRecording() {
        guard let model else { return }
        model.setRunning(!model.running)
    }

    @objc private func updateNotes() { model?.notes.updateNow() }

    @objc private func catchUp() { model?.notesWindow.send(.catchUp) }

    @objc private func copyNotes() {
        guard let model else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TranscriptExport.notesMarkdown(model.notes.notes), forType: .string)
    }

    @objc private func exportNotes(_ sender: NSMenuItem) {
        guard let model, let s = model.store.session(model.store.liveID ?? model.notes.shownID) else { return }
        model.export(s, kind: ["md", "word", "srt"][sender.tag])
    }

    @objc private func setDisplay(_ sender: NSMenuItem) { model?.setDisplayMode(["notes", "bar", "none"][sender.tag]) }

    @objc private func setSize(_ sender: NSMenuItem) {
        guard let model else { return }
        model.openNotesWindow()
        model.notesWindow.send(.layout(NotesWindowController.Layout.allCases[sender.tag]))
    }

    @objc private func toggleOnTop() {
        guard let w = model?.notesWindow else { return }
        w.onTop.toggle()
    }

    @objc private func search() { model?.notesWindow.send(.search) }
}
