import AppKit
import Combine
import SwiftUI

/// The live notes window: floats over the meeting app, can be dragged and resized anywhere,
/// stays out of screen sharing, and remembers its frame. Three layouts by width: a small card
/// (< 360), a sidebar with 纪要 / 文字记录 tabs, and notes beside the transcript (≥ 760).
@MainActor
final class NotesWindowController: NSObject, NSWindowDelegate {
    enum Layout: CaseIterable { case card, sidebar, wide }
    /// Menu commands that change the view's own state.
    enum Command { case catchUp, search, layout(Layout) }

    private var panel: NSPanel?
    private weak var model: AppModel?
    let commands = PassthroughSubject<Command, Never>()
    /// Shown or hidden: the app is a regular app (menus, Dock) while any of its windows is open.
    var onVisibilityChange: () -> Void = {}

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    var layout: Layout {
        let w = panel?.frame.width ?? 460
        return w < 360 ? .card : w >= 760 ? .wide : .sidebar
    }

    /// "浮在最上层" (`notesOnTop`, on by default).
    var onTop: Bool {
        get { UserDefaults.standard.object(forKey: "notesOnTop") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "notesOnTop")
            panel?.level = newValue ? .floating : .normal
            panel?.isFloatingPanel = newValue
        }
    }

    func send(_ command: Command) {
        if case .search = command { panel?.makeKey() }
        commands.send(command)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.onVisibilityChange() }
    }

    func show() {
        guard let model else { return }
        if panel == nil {
            let p = NSPanel(contentRect: defaultFrame(), styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                            backing: .buffered, defer: false)
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.isFloatingPanel = onTop
            p.level = onTop ? .floating : .normal
            p.delegate = self
            p.hidesOnDeactivate = false
            p.becomesKeyOnlyIfNeeded = true
            p.isReleasedWhenClosed = false
            // Others never see it when you share your screen.
            p.sharingType = .none
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.minSize = NSSize(width: 300, height: 180)
            p.backgroundColor = .white
            p.contentView = NSHostingView(rootView: NotesWindowView(
                model: model, engine: model.notes, store: model.store, settings: model.settings,
                commands: commands.eraseToAnyPublisher(),
                setWidth: { [weak self] w, h in self?.resize(width: w, height: h) }))
            p.setFrameAutosaveName("LiveSubsNotes")
            if !p.setFrameUsingName("LiveSubsNotes") { p.setFrame(defaultFrame(), display: false) }
            panel = p
        }
        panel?.orderFrontRegardless()
        onVisibilityChange()
    }

    func hide() {
        panel?.orderOut(nil)
        onVisibilityChange()
    }

    var frame: NSRect? { panel?.frame }

    /// Card ⇄ sidebar ⇄ wide, keeping the window's top-right corner where it is.
    func resize(width: CGFloat, height: CGFloat? = nil) {
        guard let p = panel, let screen = p.screen ?? NSScreen.main else { return }
        var f = p.frame
        let top = f.maxY, right = f.maxX
        f.size.width = width
        if let height { f.size.height = min(height, screen.visibleFrame.height - 24) }
        f.origin.x = min(max(screen.visibleFrame.minX, right - width), screen.visibleFrame.maxX - width)
        f.origin.y = top - f.size.height
        p.setFrame(f, display: true, animate: true)
    }

    func place(_ r: NSRect) { panel?.setFrame(r, display: true) }

    /// Debug control only: let screenshots capture the window.
    func setCapturable(_ on: Bool) { panel?.sharingType = on ? .readOnly : .none }

    /// The sidebar: docked to the right edge, nearly full height.
    private func defaultFrame() -> NSRect {
        let v = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSRect(x: v.maxX - 460 - 16, y: v.minY + 16, width: 460, height: v.height - 32)
    }
}

// MARK: - Views

struct NotesWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: NotesEngine
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings
    let commands: AnyPublisher<NotesWindowController.Command, Never>
    let setWidth: (CGFloat, CGFloat?) -> Void

    @State private var tab = "notes"
    @State private var query = ""
    @State private var jumpTo: Double?
    @State private var keyDraft = ""
    /// Session time when the window was collapsed to the card, and the topics and points the
    /// notes had then: the card offers what was added since.
    @State private var collapsedAt: Double = 0
    @State private var seenItems: Set<String> = []
    @State private var catchUp = false
    @State private var matchIndex = 0
    @State private var now = Date()
    @State private var width: CGFloat = 460
    @FocusState private var searchFocused: Bool

    private var session: Session? { store.session(store.liveID ?? engine.shownID) }
    private var live: Bool { store.liveID != nil }
    private var heard: Int { session?.lines.count ?? 0 }
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            Group {
                if geo.size.width < 360 {
                    card
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        header(wide: geo.size.width >= 760)
                        banner.padding(.horizontal, 24).padding(.bottom, 4)
                        if geo.size.width >= 760 {
                            HStack(alignment: .top, spacing: 0) {
                                notesPane.frame(maxWidth: .infinity)
                                Divider()
                                transcript.padding(.horizontal, 20).padding(.top, 12).frame(maxWidth: .infinity)
                            }
                        } else if tab == "notes" {
                            notesPane
                        } else {
                            transcript.padding(.horizontal, 24).padding(.top, 12)
                        }
                        // The transcript shows what is being said in place; the caption is for the notes tab.
                        if geo.size.width < 760 && tab == "notes" { caption }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { width = geo.size.width }
            .onChange(of: geo.size.width) { _, w in width = w }
        }
        .background(Color.white)
        .foregroundStyle(Palette.ink)
        .onReceive(tick) { now = $0 }
        .onReceive(commands) { run($0) }
    }

    /// Commands from the app menu (纪要 / 显示 / 编辑).
    private func run(_ command: NotesWindowController.Command) {
        let card = width < 360
        switch command {
        case .catchUp:
            // From the full window: what was added in the last three minutes.
            if !card {
                collapsedAt = max(0, elapsed - 180)
                seenItems = items(before: collapsedAt)
            }
            catchUp = true
            setWidth(320, 420)
        case .search:
            if card { setWidth(460, 760) }
            tab = "transcript"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { searchFocused = true }
        case .layout(.card):
            guard !card else { return }
            collapse()
        case .layout(.sidebar):
            setWidth(460, card ? 760 : nil)
        case .layout(.wide):
            setWidth(820, card ? 760 : nil)
        }
    }

    private func collapse() {
        collapsedAt = elapsed
        seenItems = items(before: .infinity)
        catchUp = false
        setWidth(320, 230)
    }

    /// Topic titles and points of the current notes said before a time (all of them for `.infinity`).
    private func items(before t: Double) -> Set<String> {
        var out: Set<String> = []
        for topic in engine.notes.topics {
            if topic.start < t { out.insert(topic.title) }
            for (i, p) in topic.points.enumerated() where (topic.pointTime(i) ?? topic.start) < t { out.insert(p) }
        }
        return out
    }

    // MARK: Header

    private func header(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("实时纪要").font(.system(size: 24, weight: .bold))
                    HStack(spacing: 6) {
                        if live { LiveDot() }
                        Text(statusLine).font(.system(size: 12)).foregroundStyle(Palette.tertiary).lineLimit(1)
                    }
                }
                Spacer()
                if engine.state == .updating, !engine.notes.isEmpty {
                    UpdatingPill().padding(.top, 4).padding(.trailing, 4)
                }
                iconButton(wide ? "rectangle.split.2x1.fill" : "rectangle.split.2x1", help: wide ? "收窄" : "纪要和原话并排") {
                    setWidth(wide ? 460 : 820, nil)
                }
                iconButton("minus", help: "收成小卡") { collapse() }
            }
            if !wide {
                HStack(spacing: 0) {
                    segment("纪要", "notes")
                    segment(engine.notes.isEmpty && heard > 0 ? "文字记录 · \(heard)" : "文字记录", "transcript")
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.fill))
            }
            if wide || tab == "transcript" {
                searchField
            }
        }
        .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Palette.tertiary)
            TextField("在文字记录中搜索  ⌘F", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { step(1) }
                .onChange(of: query) { _, _ in matchIndex = 0 }
            if !query.isEmpty {
                Text(matches.isEmpty ? "无结果" : "\(currentIndex + 1) / \(matches.count)")
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.tertiary)
                iconButton("chevron.up", help: "上一个") { step(-1) }.disabled(matches.isEmpty)
                iconButton("chevron.down", help: "下一个") { step(1) }.disabled(matches.isEmpty)
                iconButton("xmark", help: "清除") { query = "" }
            }
        }
        .padding(.leading, 12).padding(.trailing, 2).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10).fill(searchFocused ? Color.white : Palette.fill))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(searchFocused ? Palette.accent : .clear, lineWidth: 1.5))
    }

    /// The query, plus every way the notes say that name was heard (江充 also finds 江松).
    private var searchTerms: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var out = [q]
        for t in engine.notes.terms {
            let forms = [t.name] + t.heard
            if forms.contains(where: { $0.localizedCaseInsensitiveContains(q) || q.localizedCaseInsensitiveContains($0) }) {
                out += forms.filter { !out.contains($0) }
            }
        }
        return out
    }

    private var matches: [String] {
        let terms = searchTerms
        guard !terms.isEmpty else { return [] }
        return (session?.lines ?? []).filter { l in
            terms.contains { l.src.localizedCaseInsensitiveContains($0) || (l.dst ?? "").localizedCaseInsensitiveContains($0) }
        }.map(\.id)
    }

    private var currentIndex: Int { matches.isEmpty ? 0 : min(matchIndex, matches.count - 1) }

    private func step(_ d: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (currentIndex + d + matches.count) % matches.count
    }

    private func segment(_ title: String, _ id: String) -> some View {
        Button { tab = id } label: {
            Text(title).font(.system(size: 13, weight: tab == id ? .semibold : .regular))
                .foregroundStyle(tab == id ? Palette.ink : Palette.secondary)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9).fill(tab == id ? Color.white : .clear)
                    .shadow(color: .black.opacity(tab == id ? 0.08 : 0), radius: 1.5, y: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private var elapsed: Double { store.liveStart.map { now.timeIntervalSince($0) } ?? 0 }

    private var statusLine: String {
        if live {
            var parts = [(heard == 0 ? "正在听 · " : "正在记录 · ") + NotesEngine.clock(elapsed)]
            if heard > 0 { parts.append("\(heard) 句") }
            if !engine.notes.isEmpty, lastCovered > 0 { parts.append("纪要已更新至 \(NotesEngine.clock(lastCovered))") }
            return parts.joined(separator: " · ")
        }
        let clock = session.map { TranscriptExport.header($0) } ?? "没有进行中的会议"
        guard let at = engine.notes.updatedAt, engine.state != .updating else { return clock }
        let ago = Int(now.timeIntervalSince(at))
        return clock + " · " + (ago < 10 ? "刚刚更新" : ago < 60 ? "\(ago) 秒前更新" : "\(ago / 60) 分钟前更新")
    }

    // MARK: Banners (key and service states)

    @ViewBuilder
    private var banner: some View {
        switch engine.state {
        case .noKey where session?.lines.isEmpty == false || live:
            keyEntry
        case .invalidKey:
            notice("key 已失效（令牌被删或免费额度用尽），纪要停留在 \(NotesEngine.clock(lastCovered))。", tint: Palette.errorPale) {
                SoftButton("更换 key", dark: true) { model.openSettings(.ai) }
            }
        case .rateLimited:
            notice("请求过于频繁，稍后会自动重试。纪要停留在 \(NotesEngine.clock(lastCovered))。", tint: Palette.fill) { EmptyView() }
        case .failed:
            notice("这轮没整理好，下一轮会自动重试。", tint: Palette.fill) { EmptyView() }
        default:
            EmptyView()
        }
    }

    private var lastCovered: Double {
        guard let s = session, engine.notes.covered > 0, engine.notes.covered <= s.lines.count else { return 0 }
        return s.lines[engine.notes.covered - 1].t
    }

    private func notice<Trailing: View>(_ text: String, tint: Color, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(text).font(.system(size: 12)).lineSpacing(2).frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint))
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("生成纪要需要 API key").font(.system(size: 15, weight: .bold))
            Text("文字记录仍在正常保存。填入 Ling 的 key 后，会从头开始整理整场会议的内容。")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(2)
            HStack(spacing: 8) {
                SecureField("sk-…", text: $keyDraft)
                    .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line, lineWidth: 1))
                    .onSubmit(saveKey)
                SoftButton("保存并开始", dark: true, action: saveKey)
            }
            Button("获取 Ling key ↗") {
                if let url = URL(string: "https://chat.ant-ling.com/open") { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.raised))
    }

    private func saveKey() {
        let k = keyDraft
        keyDraft = ""
        Task {
            await model.ling.setKey(k)
            if model.ling.usable { model.notes.updateNow() }
        }
    }

    // MARK: Content

    /// Notes, or what is happening before there are any: listening, writing the first version.
    @ViewBuilder
    private var notesPane: some View {
        if !engine.notes.isEmpty {
            notesScroll
        } else if engine.state == .noKey || engine.state == .invalidKey {
            Spacer()
        } else if live && heard == 0 {
            VStack {
                Spacer()
                NotesListeningView()
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if live || engine.generatingID == session?.id {
            ScrollView {
                NotesGeneratingView(heard: heard).padding(.horizontal, 24).padding(.vertical, 12)
            }
        } else {
            VStack {
                Spacer()
                Text(session == nil ? "没有进行中的会议" : "这场会议还没有纪要")
                    .font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var notesScroll: some View {
        ScrollView {
            NotesContentView(notes: engine.notes, fresh: engine.fresh, live: live,
                             updating: engine.state == .updating,
                             summaryJustChanged: engine.summaryChangedAt.map { now.timeIntervalSince($0) < 20 } ?? false,
                             coveredUntil: lastCovered > 0 ? lastCovered : nil,
                             endedAt: session?.lines.last?.t,
                             onJump: { t in jumpTo = t; tab = "transcript" })
                .padding(.horizontal, 24).padding(.vertical, 12)
        }
    }

    private var transcript: some View {
        let ms = matches
        return TranscriptListView(lines: session?.lines ?? [], topics: engine.notes.topics, terms: searchTerms,
                                  currentMatch: ms.isEmpty ? nil : ms[currentIndex], live: live,
                                  partial: model.liveSource, partialTime: elapsed, jumpTo: jumpTo)
    }

    @ViewBuilder
    private var caption: some View {
        if live, !model.liveSource.isEmpty || !model.liveTranslation.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                if !model.liveSource.isEmpty {
                    Text(model.liveSource).font(.system(size: 12)).foregroundStyle(Color(white: 0.74)).lineLimit(2)
                }
                if !model.liveTranslation.isEmpty {
                    Text(model.liveTranslation).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.ink))
            .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 8)
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if catchUp {
                    Text("收起之后 · \(NotesEngine.clock(collapsedAt)) – \(NotesEngine.clock(elapsed))")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.tertiary)
                } else {
                    if live { LiveDot() }
                    Text(currentTopic.map { (live ? "正在讲 · " : "最后一个议题 · ") + "\(NotesEngine.clock($0.start)) 起" } ?? (live ? "正在记录" : "实时纪要"))
                        .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                }
                Spacer()
                iconButton("arrow.up.left.and.arrow.down.right", help: "展开纪要") { setWidth(460, 760) }
            }
            if catchUp {
                Text("这 \(span) 讲了").font(.system(size: 17, weight: .bold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(added, id: \.topic.id) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(NotesEngine.clock(item.topic.start)).font(.system(size: 12).monospacedDigit())
                                        .foregroundStyle(Palette.tertiary).frame(width: 38, alignment: .leading)
                                    Text(item.topic.title).font(.system(size: 14, weight: .bold))
                                }
                                if !item.points.isEmpty {
                                    Text(item.points.joined(separator: "；")).font(.system(size: 13))
                                        .foregroundStyle(Palette.secondary).lineSpacing(2).padding(.leading, 46)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        if added.isEmpty {
                            Text("纪要里还没有新内容").font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    SoftButton("展开纪要", dark: true) { setWidth(460, 760) }
                    SoftButton("看过了") {
                        catchUp = false
                        collapsedAt = elapsed
                        seenItems = items(before: .infinity)
                        setWidth(320, 230)
                    }
                }
            } else {
                Text(currentTopic?.title ?? (!live ? "还没有纪要" : heard == 0 ? "正在听" : "正在生成纪要…"))
                    .font(.system(size: 17, weight: .bold)).lineLimit(2)
                if addedCount.points == 0 && addedCount.topics == 0, let last = currentTopic?.points.last {
                    Text(last).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if addedCount.topics + addedCount.points > 0 {
                    // Only says something when there is something new.
                    Button { catchUp = true; setWidth(320, 420) } label: {
                        HStack {
                            Text(addedLabel).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Palette.accentInk)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.accentPale))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if collapsedAt > 0 || live {
                    Text("收起 \(span) · " + (live ? "还在讲这个" : "没有新内容"))
                        .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 16)
    }

    private var currentTopic: NoteTopic? { engine.notes.topics.last }

    /// Topics with what was added to them since the card was collapsed.
    private var added: [(topic: NoteTopic, points: [String])] {
        engine.notes.topics.compactMap { t in
            let points = t.points.filter { !seenItems.contains($0) }
            return seenItems.contains(t.title) && points.isEmpty ? nil : (t, points)
        }
    }

    private var addedCount: (topics: Int, points: Int) {
        let a = added
        return (a.filter { !seenItems.contains($0.topic.title) }.count, a.reduce(0) { $0 + $1.points.count })
    }

    private var addedLabel: String {
        let c = addedCount
        var parts: [String] = []
        if c.topics > 0 { parts.append("\(c.topics) 个议题") }
        if c.points > 0 { parts.append("\(c.points) 条要点") }
        return "收起后新增 " + parts.joined(separator: "、")
    }

    private var span: String {
        let s = max(0, Int(elapsed - collapsedAt))
        return s < 60 ? "\(s) 秒" : "\(s / 60) 分钟"
    }
}
