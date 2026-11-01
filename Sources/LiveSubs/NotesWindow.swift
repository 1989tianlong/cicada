import AppKit
import SwiftUI

/// The live notes window: floats over the meeting app, can be dragged and resized anywhere,
/// stays out of screen sharing, and remembers its frame. Three layouts by width: a small card
/// (< 360), a sidebar with 纪要 / 文字记录 tabs, and notes beside the transcript (≥ 760).
@MainActor
final class NotesWindowController {
    private var panel: NSPanel?
    private weak var model: AppModel?

    init(model: AppModel) { self.model = model }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        guard let model else { return }
        if panel == nil {
            let p = NSPanel(contentRect: defaultFrame(), styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                            backing: .buffered, defer: false)
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.isFloatingPanel = true
            p.level = .floating
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
                setWidth: { [weak self] w, h in self?.resize(width: w, height: h) }))
            p.setFrameAutosaveName("LiveSubsNotes")
            if !p.setFrameUsingName("LiveSubsNotes") { p.setFrame(defaultFrame(), display: false) }
            panel = p
        }
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

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
    let setWidth: (CGFloat, CGFloat?) -> Void

    @State private var tab = "notes"
    @State private var query = ""
    @State private var jumpTo: Double?
    @State private var keyDraft = ""
    /// Session time when the window was collapsed to the card: "what did I miss" starts there.
    @State private var collapsedAt: Double = 0
    @State private var catchUp = false
    @State private var now = Date()

    private var session: Session? { store.session(store.liveID ?? engine.shownID) }
    private var live: Bool { store.liveID != nil }
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
                                notesScroll.frame(maxWidth: .infinity)
                                Divider()
                                transcript.padding(.horizontal, 20).padding(.top, 12).frame(maxWidth: .infinity)
                            }
                        } else if tab == "notes" {
                            notesScroll
                        } else {
                            transcript.padding(.horizontal, 24).padding(.top, 12)
                        }
                        caption
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.white)
        .foregroundStyle(Palette.ink)
        .onReceive(tick) { now = $0 }
    }

    // MARK: Header

    private func header(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("实时纪要").font(.system(size: 24, weight: .bold))
                    HStack(spacing: 6) {
                        if live { Circle().fill(Palette.accent).frame(width: 7, height: 7) }
                        Text(statusLine).font(.system(size: 12)).foregroundStyle(Palette.tertiary).lineLimit(1)
                    }
                }
                Spacer()
                iconButton(wide ? "rectangle.split.2x1.fill" : "rectangle.split.2x1", help: wide ? "收窄" : "纪要和原话并排") {
                    setWidth(wide ? 460 : 820, nil)
                }
                iconButton("minus", help: "收成小卡") {
                    collapsedAt = elapsed
                    catchUp = false
                    setWidth(320, 230)
                }
            }
            if !wide {
                HStack(spacing: 0) {
                    segment("纪要", "notes")
                    segment("文字记录", "transcript")
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.fill))
            }
            if wide || tab == "transcript" {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                    TextField("搜索文字记录", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                }
                .padding(.horizontal, 12).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.fill))
            }
        }
        .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 12)
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
        let clock = live ? "正在记录 · \(NotesEngine.clock(elapsed))" : (session.map { TranscriptExport.header($0) } ?? "没有进行中的会议")
        guard let at = engine.notes.updatedAt else { return clock }
        let ago = Int(now.timeIntervalSince(at))
        if engine.state == .updating { return clock + " · 正在更新" }
        return clock + " · " + (ago < 10 ? "刚刚更新" : ago < 60 ? "\(ago) 秒前更新" : "\(ago / 60) 分钟前更新")
    }

    // MARK: Banners (key and service states)

    @ViewBuilder
    private var banner: some View {
        switch engine.state {
        case .noKey where session?.lines.isEmpty == false || live:
            keyEntry
        case .invalidKey:
            notice("key 失效了（令牌被删除，或免费额度用完），纪要停在 \(NotesEngine.clock(lastCovered))。", tint: Palette.errorPale) {
                SoftButton("换一个 key", dark: true) { model.openSettings(.ai) }
            }
        case .rateLimited:
            notice("请求太多，Ling 让等一下，过一会儿自动再试。纪要停在 \(NotesEngine.clock(lastCovered))。", tint: Palette.fill) { EmptyView() }
        case .failed:
            notice("这次没整理好，下一轮会再试。", tint: Palette.fill) { EmptyView() }
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
            Text("纪要需要一个 API key").font(.system(size: 15, weight: .bold))
            Text("文字记录照常在记。填上 Ling 的 key 后，从这场会已经说过的内容开始整理。")
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
            Button("去 Ling 拿 key ↗") {
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

    private var notesScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if engine.notes.isEmpty {
                    emptyNotes
                } else {
                    NotesContentView(notes: engine.notes, fresh: engine.fresh, live: live,
                                     updating: engine.state == .updating,
                                     summaryJustChanged: engine.summaryChangedAt.map { now.timeIntervalSince($0) < 20 } ?? false,
                                     onJump: { t in jumpTo = t; tab = "transcript" })
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var emptyNotes: some View {
        if engine.state == .noKey { EmptyView() } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(engine.state == .updating ? "正在整理第一版纪要…" : "开始说话后，大约半分钟出第一版纪要")
                    .font(.system(size: 14, weight: .semibold))
                Text("之后每 45 秒更新一次；会议结束时再整理一遍完整版。")
                    .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Palette.raised))
        }
    }

    private var transcript: some View {
        TranscriptListView(lines: session?.lines ?? [], topics: engine.notes.topics, query: query,
                           live: live, jumpTo: jumpTo)
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
                if live { Circle().fill(Palette.accent).frame(width: 7, height: 7) }
                Text(currentTopic.map { (live ? "正在讲 · " : "最后一个议题 · ") + "\(NotesEngine.clock($0.start)) 起" } ?? (live ? "正在记录" : "实时纪要"))
                    .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                Spacer()
                iconButton("arrow.up.left.and.arrow.down.right", help: "展开纪要") { setWidth(460, 760) }
            }
            if catchUp {
                Text("你错过的 \(missedSpan)").font(.system(size: 15, weight: .bold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(missed, id: \.self) { p in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Circle().fill(Palette.ink.opacity(0.55)).frame(width: 4, height: 4)
                                Text(p).font(.system(size: 13)).lineSpacing(2)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    SoftButton("展开完整纪要", dark: true) { setWidth(460, 760) }
                    SoftButton("知道了") { catchUp = false; collapsedAt = elapsed }
                }
            } else {
                Text(currentTopic?.title ?? "还没有纪要").font(.system(size: 17, weight: .bold)).lineLimit(2)
                if let last = currentTopic?.points.last {
                    Text(last).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                SoftButton("我刚走神了，错过什么？", dark: true) { catchUp = true }
            }
        }
        .padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 16)
    }

    private var currentTopic: NoteTopic? { engine.notes.topics.last }

    private var missed: [String] {
        let topics = engine.notes.topics
        let since = topics.filter { $0.start >= collapsedAt - 5 }
        let pool = since.isEmpty ? Array(topics.suffix(1)) : since
        let items = pool.flatMap { t in ["\(t.title)：\(t.summary.isEmpty ? t.points.first ?? "" : t.summary)"] + t.points.prefix(2) }
        return items.isEmpty ? ["这段时间还没有新的纪要"] : items
    }

    private var missedSpan: String {
        let s = max(0, Int(elapsed - collapsedAt))
        return s < 60 ? "\(s) 秒" : "\(s / 60) 分 \(s % 60) 秒"
    }
}
