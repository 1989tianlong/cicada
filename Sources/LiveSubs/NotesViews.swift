import AppKit
import SwiftUI

// Notes and transcript views shared by the live notes window and the main window (meeting
// records). The look follows the canvas: white ground, grey blocks for what matters most,
// framed lists with hairlines, orange only for what is happening now.

// MARK: - Notes

struct NotesContentView: View {
    let notes: MeetingNotes
    var fresh: Set<String> = []
    /// The meeting is still going: the last topic is "正在讲".
    var live = false
    /// The main window's page: the summary as a lead paragraph, quiet section labels, rules
    /// between rows instead of cards.
    var document = false
    var updating = false
    var summaryJustChanged = false
    /// The time of the last line the notes cover ("到 03:52").
    var coveredUntil: Double?
    /// Where the last topic ends when the meeting is over (its last line).
    var endedAt: Double?
    var onJump: (Double) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: document ? 32 : 18) {
            if document && !notes.summary.isEmpty {
                Text(notes.summary).font(.system(size: 17)).lineSpacing(7).foregroundStyle(Palette.ink.opacity(0.9))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else if !notes.summary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("总结").font(.system(size: 15, weight: .bold))
                        if summaryJustChanged { Tag(L("刚更新"), live: true) }
                        Spacer()
                        if notes.final { Tag(L("完整版")) } else if live {
                            Tag(coveredUntil.map { L("速记版 · 到 \(NotesEngine.clock($0))") } ?? L("速记版"))
                        }
                    }
                    Text(notes.summary).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(Palette.raised))
            }

            if !notes.topics.isEmpty {
                VStack(alignment: .leading, spacing: document ? 0 : 14) {
                    title(L("议题"))
                    ForEach(Array(notes.topics.enumerated()), id: \.element.id) { i, topic in
                        if document { Divider() }
                        TopicView(topic: topic,
                                  end: i + 1 < notes.topics.count ? notes.topics[i + 1].start : (live ? nil : endedAt),
                                  current: live && i == notes.topics.count - 1,
                                  updating: updating && i == notes.topics.count - 1, fresh: fresh, onJump: onJump)
                            .padding(.vertical, document ? 14 : 0)
                            .id(Self.topicID(topic))
                    }
                }
            }

            if !notes.conclusions.isEmpty || !notes.todos.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    title(notes.todos.isEmpty ? L("结论") : L("结论和待办"))
                    if document {
                        VStack(alignment: .leading, spacing: 0) { items }
                    } else {
                        FramedList { items }
                    }
                }
            }

            if !notes.terms.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    title(L("人名和术语"))
                    FlowLayout(spacing: 6) {
                        ForEach(notes.terms) { t in
                            (Text(t.name).bold() + Text(t.note.isEmpty ? "" : " \(t.note)")
                                + Text(t.heard.isEmpty ? "" : L(" · 原识别 \(t.heard.prefix(2).joined(separator: "、"))"))
                                .foregroundColor(Palette.tertiary))
                                .font(.system(size: 12))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Palette.fill))
                        }
                    }
                }
            }
        }
    }

    /// Scroll target for a topic (the live notes window keeps the current one in view).
    static func topicID(_ topic: NoteTopic) -> String { "topic-\(topic.id)" }

    @ViewBuilder
    private func title(_ text: String) -> some View {
        if document {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.bottom, 2)
        } else {
            SectionTitle(text)
        }
    }

    @ViewBuilder
    private var items: some View {
        let all = notes.conclusions + notes.todos
        ForEach(Array(all.enumerated()), id: \.offset) { i, item in
            let todo = i >= notes.conclusions.count
            if document && i > 0 { Divider() }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if todo {
                    Image(systemName: "circle").font(.system(size: document ? 13 : 11)).foregroundStyle(Palette.tertiary)
                } else if document {
                    Circle().fill(Palette.ink.opacity(0.55)).frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        .frame(width: 13)
                }
                Text(item.text + (item.owner.map { "（\($0)）" } ?? ""))
                    .font(.system(size: 14)).lineSpacing(2)
                    .foregroundStyle(item.support == 0 ? Palette.tertiary : Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.support == 0 {
                    Tag(L("依据较少"))
                } else if let t = item.t {
                    TimeLink(text: L("\(NotesEngine.clock(t)) · \(item.support) 句"), t: t, onJump: onJump)
                } else {
                    Tag(L("依据 \(item.support) 句"))
                }
            }
            .padding(.horizontal, document ? 0 : 16).padding(.vertical, 11)
            if !document && i < all.count - 1 { Divider() }
        }
    }
}

private struct TopicView: View {
    let topic: NoteTopic
    /// The next topic's start, or the meeting's end; nil while it is still being discussed.
    let end: Double?
    let current: Bool
    let updating: Bool
    let fresh: Set<String>
    let onJump: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button { onJump(topic.start) } label: {
                    Text(range)
                        .font(.system(size: 12, weight: current ? .semibold : .regular).monospacedDigit())
                        .foregroundStyle(current ? Palette.accentInk : Palette.tertiary)
                        .frame(width: column, alignment: .leading)
                }
                .buttonStyle(.plain).help("看原话")
                Text(topic.title).font(.system(size: 15, weight: .bold))
                if current { Tag(L("正在讲"), live: true) }
                if fresh.contains(topic.title) && !current { Tag(L("新"), live: true) }
            }
            VStack(alignment: .leading, spacing: 6) {
                if !topic.summary.isEmpty {
                    Text(topic.summary).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(topic.points.enumerated()), id: \.offset) { i, p in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(fresh.contains(p) ? Palette.accent : Palette.ink.opacity(0.55)).frame(width: 4, height: 4)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        Text(p).font(.system(size: 14)).lineSpacing(2).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if fresh.contains(p) { Tag(L("新"), live: true) }
                        Spacer(minLength: 4)
                        if let t = topic.pointTime(i) { TimeLink(text: NotesEngine.clock(t), t: t, onJump: onJump) }
                    }
                    .modifier(FadeIn(active: fresh.contains(p)))
                }
                if let fish = topic.fishbone { FishboneView(fishbone: fish, onJump: onJump).padding(.top, 4) }
                if updating {
                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBar(fraction: 0.82, height: 10, warm: true)
                        SkeletonBar(fraction: 0.56, height: 10, warm: true)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.leading, column + 10)
        }
        .padding(.vertical, current ? 10 : 0).padding(.horizontal, current ? 10 : 0)
        .background(RoundedRectangle(cornerRadius: 14).fill(current ? Palette.accentWash : .clear))
    }

    /// "01:04–02:02", or "02:03 起" for the topic being discussed.
    private var range: String {
        let from = NotesEngine.clock(topic.start)
        guard let end, end > topic.start + 1 else { return current ? L("\(from) 起") : from }
        return "\(from)–\(NotesEngine.clock(end))"
    }

    private var column: CGFloat { (end ?? topic.start) >= 3600 ? 104 : 76 }
}

/// A small time that jumps to that moment in the transcript.
struct TimeLink: View {
    let text: String
    let t: Double
    let onJump: (Double) -> Void
    @State private var hover = false

    var body: some View {
        Button { onJump(t) } label: {
            Text(text).font(.system(size: 12).monospacedDigit())
                .foregroundStyle(hover ? Palette.ink : Palette.tertiary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Palette.fill : .clear))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("回到原话")
    }
}

/// A fishbone drawn upright for a narrow window: the question on top, branches alternating on
/// either side of a spine. A branch no transcript line backs is dashed.
struct FishboneView: View {
    let fishbone: Fishbone
    var onJump: (Double) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text(fishbone.question.isEmpty ? L("为什么") : fishbone.question).font(.system(size: 13, weight: .bold))
                Spacer()
                Text("鱼骨图").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
            }
            VStack(spacing: 6) {
                ForEach(Array(stride(from: 0, to: fishbone.branches.count, by: 2)), id: \.self) { i in
                    HStack(alignment: .center, spacing: 0) {
                        branch(fishbone.branches[i])
                        spine
                        if i + 1 < fishbone.branches.count {
                            branch(fishbone.branches[i + 1])
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("点击分支跳回原话").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
    }

    private var spine: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(white: 0.84)).frame(width: 2)
            Circle().fill(Palette.ink).frame(width: 7, height: 7)
            Rectangle().fill(Color(white: 0.84)).frame(width: 2)
        }
        .frame(width: 18)
    }

    private func branch(_ b: FishboneBranch) -> some View {
        let weak = b.support == 0
        return Button { if let t = b.t { onJump(t) } } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(b.label).font(.system(size: 12, weight: .bold)).foregroundStyle(weak ? Palette.tertiary : Palette.ink)
                if !b.detail.isEmpty {
                    Text(b.detail).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(weak ? Color.clear : Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(weak ? Color(white: 0.8) : .clear, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(weak ? L("依据较少，仅供参考") : L("看原话"))
    }
}

// MARK: - Transcript

/// When the user last turned a scroll wheel or swiped the trackpad in this app. SwiftUI also moves
/// a scroll view by itself (rows measured late, text rewrapping after a resize), so only a recent
/// real scroll may pause following.
@MainActor
enum UserScroll {
    private static var last = Date.distantPast
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            last = Date()
            return event
        }
    }

    static var recent: Bool { Date().timeIntervalSince(last) < 0.6 }
}

/// The transcript grouped under the notes' topics, oldest first. While live it follows the
/// newest line; scrolling up pauses that and collects new lines into a "↓ N 句新内容" button.
/// A search highlights matches in place instead of hiding the lines around them.
struct TranscriptListView: View {
    let lines: [TranscriptLine]
    let topics: [NoteTopic]
    /// Spellings to highlight: the query, plus the notes' misrecognised forms of a name.
    var terms: [String] = []
    var currentMatch: String?
    var bilingual = true
    var live = false
    /// What is being said right now, not yet a finished line.
    var partial = ""
    var partialTime: Double?
    var jumpTo: Double?

    @State private var following = true
    @State private var seenCount = 0

    private var searching: Bool { !terms.isEmpty }
    /// The caption keeps the last sentence after it is finished: only show text not yet a line.
    private var showsPartial: Bool {
        let p = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard live, !p.isEmpty else { return false }
        guard let last = lines.last?.src else { return true }
        return !last.contains(p) && !p.contains(last)
    }

    private var groups: [(title: String, start: Double, lines: [TranscriptLine])] {
        guard !topics.isEmpty else { return [("", 0, lines)] }
        var out: [(String, Double, [TranscriptLine])] = []
        for (i, t) in topics.enumerated() {
            let end = i + 1 < topics.count ? topics[i + 1].start : .infinity
            let first = i == 0 ? -Double.infinity : t.start
            let ls = lines.filter { $0.t >= first && $0.t < end }
            if !ls.isEmpty { out.append((t.title, t.start, ls)) }
        }
        return out
    }

    private struct Edge: Equatable {
        var distance: CGFloat
        var height: CGFloat
        var container: CGFloat
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        let gs = groups
                        ForEach(Array(gs.enumerated()), id: \.element.start) { gi, g in
                            // One lazy child per topic group, with an id to scroll to before it is drawn.
                            VStack(alignment: .leading, spacing: 10) {
                                if !g.title.isEmpty {
                                    Text("\(NotesEngine.clock(g.start)) · \(g.title)")
                                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.secondary).padding(.top, 6)
                                }
                                FramedList {
                                    ForEach(Array(g.lines.enumerated()), id: \.element.id) { i, l in
                                        row(l).id(l.id)
                                        if i < g.lines.count - 1 { Divider() }
                                    }
                                    if gi == gs.count - 1, showsPartial {
                                        Divider()
                                        partialRow
                                    }
                                }
                            }
                            .id(groupID(g.start))
                        }
                        if lines.isEmpty && !showsPartial {
                            Text("说话的内容会出现在这里").font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                                .frame(maxWidth: .infinity).padding(.top, 40)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.bottom, 12)
                }
                .onScrollGeometryChange(for: Edge.self) { g in
                    Edge(distance: g.contentSize.height - g.contentOffset.y - g.containerSize.height,
                         height: g.contentSize.height, container: g.containerSize.height)
                } action: { old, new in
                    if new.height != old.height || new.container != old.container {
                        // Not only new lines move the bottom: a translation arriving under its line,
                        // topic headers from a notes update, rows the lazy stack only now measured,
                        // the window resizing. Following means staying on the newest line through all of them.
                        if new.distance > 1 { follow(proxy) }
                    } else if new.distance < 40 {
                        if !following { following = true }
                    } else if following, new.distance > 60, UserScroll.recent {
                        // The reader scrolled up (content growing or reflowing never pauses following).
                        following = false
                        seenCount = lines.count
                    }
                }
                .onChange(of: lines.count) { _, _ in follow(proxy) }
                .onChange(of: partial) { _, _ in follow(proxy) }
                .onChange(of: currentMatch) { _, id in
                    guard let id, let line = lines.first(where: { $0.id == id }) else { return }
                    reveal(line, anchor: .center, proxy)
                }
                .onChange(of: jumpTo) { _, t in
                    guard let t, let target = lines.first(where: { $0.t >= t - 1 }) ?? lines.last else { return }
                    following = false
                    seenCount = lines.count
                    reveal(target, anchor: .top, proxy)
                }
                .onAppear {
                    UserScroll.install()
                    seenCount = lines.count
                    if let t = jumpTo, let target = lines.first(where: { $0.t >= t - 1 }) {
                        following = false
                        reveal(target, anchor: .top, proxy)
                    } else if live {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }

                if live, !following, !searching, lines.count > seenCount {
                    newLinesButton { following = true; proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }

    private func groupID(_ start: Double) -> String { "group-\(start)" }

    /// Rows inside a topic group that the lazy stack hasn't drawn yet can't be scrolled to:
    /// bring the group in first, then the line.
    private func reveal(_ line: TranscriptLine, anchor: UnitPoint, _ proxy: ScrollViewProxy) {
        if let g = groups.last(where: { $0.lines.contains { $0.id == line.id } }) {
            proxy.scrollTo(groupID(g.start), anchor: .top)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation { proxy.scrollTo(line.id, anchor: anchor) }
        }
    }

    private func follow(_ proxy: ScrollViewProxy) {
        guard live, following, !searching else { return }
        proxy.scrollTo("bottom", anchor: .bottom)
    }

    private func newLinesButton(_ action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom).frame(height: 40)
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down").font(.system(size: 12, weight: .bold))
                    Text("\(lines.count - seenCount) 句新内容").font(.system(size: 13, weight: .semibold))
                    if let last = lines.last {
                        Text(last.src).font(.system(size: 13)).foregroundStyle(Color(white: 0.74)).lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(.leading, 14).padding(.trailing, 18).frame(height: 40)
                .background(Capsule().fill(Palette.ink).shadow(color: .black.opacity(0.18), radius: 12, y: 6))
                .frame(maxWidth: 380)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background(Color.white)
        }
        .transition(.opacity)
    }

    private func matches(_ l: TranscriptLine) -> Bool {
        terms.contains { l.src.localizedCaseInsensitiveContains($0) || (l.dst ?? "").localizedCaseInsensitiveContains($0) }
    }

    private func highlighted(_ text: String, current: Bool) -> AttributedString {
        var a = AttributedString(text)
        for term in terms where !term.isEmpty {
            var from = a.startIndex
            while from < a.endIndex, let r = a[from...].range(of: term, options: .caseInsensitive) {
                a[r].backgroundColor = current ? Palette.accent : Palette.accentPale
                a[r].foregroundColor = current ? .white : Palette.accentInk
                from = r.upperBound
            }
        }
        return a
    }

    private func row(_ l: TranscriptLine) -> some View {
        let isMatch = l.id == currentMatch
        let latest = live && l.id == lines.last?.id
        let dim = searching && !matches(l)
        return HStack(alignment: .top, spacing: 12) {
            Text(NotesEngine.clock(l.t)).font(.system(size: 12, weight: isMatch ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(latest || isMatch ? Palette.accentInk : Palette.tertiary)
                .frame(width: l.t >= 3600 ? 56 : 40, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if l.speaker == "me" { Text("你").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accentInk) }
                Text(highlighted(l.src, current: isMatch)).font(.system(size: 14)).lineSpacing(2).textSelection(.enabled)
                if bilingual, let d = l.dst, d != l.src {
                    Text(highlighted(d, current: isMatch)).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        .lineSpacing(2).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(latest || isMatch ? Palette.accentWash : Color.clear)
        .opacity(dim ? 0.5 : 1)
    }

    private var partialRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(partialTime.map(NotesEngine.clock) ?? "").font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Palette.accentInk)
                .frame(width: (partialTime ?? 0) >= 3600 ? 56 : 40, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(partial).font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(2)
                    AnimatedDots().font(.system(size: 14)).foregroundStyle(Palette.secondary)
                }
                Text("正在说").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Palette.accentWash)
        .id("partial")
    }
}

// MARK: - Small parts

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.secondary)
    }
}

struct Tag: View {
    let text: String
    var live = false
    init(_ text: String, live: Bool = false) {
        self.text = text
        self.live = live
    }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(live ? Palette.accentInk : Palette.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(live ? Palette.accentPale : Palette.fill))
            .fixedSize()
    }
}

struct FramedList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
    }
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}

// MARK: - Motion (notes in progress)
// One moving thing at a time says the app is working. Driven by TimelineView rather than
// repeatForever animations, which the window's once-a-second redraw would restart.

func phase(_ date: Date, period: Double, delay: Double = 0) -> Double {
    let t = date.timeIntervalSinceReferenceDate - delay
    return (t.truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period) / period
}

/// Listening, nobody has spoken yet: five sound bars with a soft ring pulsing behind them.
struct ListeningMark: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let ring = phase(ctx.date, period: 2)
            ZStack {
                Circle().fill(Palette.accentPale)
                    .scaleEffect(0.8 + 0.8 * ring).opacity(0.55 * (1 - ring))
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        let p = phase(ctx.date, period: 1.1, delay: Double(i) * 0.15)
                        Capsule().fill(Palette.accent).frame(width: 6, height: 44)
                            .scaleEffect(x: 1, y: 0.25 + 0.75 * (0.5 - 0.5 * cos(p * 2 * .pi)))
                    }
                }
            }
            .frame(width: 120, height: 120)
        }
        .accessibilityHidden(true)
    }
}

/// A small orange ring spinner.
struct Spinner: View {
    var size: CGFloat = 16
    var track = Palette.accentPale

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            ZStack {
                Circle().stroke(track, lineWidth: 2)
                Circle().trim(from: 0, to: 0.25)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(phase(ctx.date, period: 0.9) * 360))
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

/// "…" whose dots light up one after another.
struct AnimatedDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { ctx in
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    Text(".").opacity(0.3 + 0.7 * (0.5 - 0.5 * cos(phase(ctx.date, period: 1.2, delay: Double(i) * 0.2) * 2 * .pi)))
                }
            }
        }
    }
}

/// The live dot beside "正在记录", breathing slowly.
struct LiveDot: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { ctx in
            Circle().fill(Palette.accent).frame(width: 7, height: 7)
                .opacity(0.35 + 0.65 * (0.5 + 0.5 * cos(phase(ctx.date, period: 1.4) * 2 * .pi)))
        }
    }
}

/// A placeholder line with a light sweeping across it. `warm` is the pale orange used inside
/// the topic being updated.
struct SkeletonBar: View {
    var fraction: CGFloat = 1
    var height: CGFloat = 12
    var warm = false

    var body: some View {
        let base = warm ? Color(red: 0.965, green: 0.89, blue: 0.86) : Color(red: 0.933, green: 0.941, blue: 0.953)
        let light = warm ? Color(red: 0.992, green: 0.953, blue: 0.933) : Color(red: 0.969, green: 0.973, blue: 0.98)
        GeometryReader { g in
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                let x = phase(ctx.date, period: 1.4) * 2 - 0.5
                RoundedRectangle(cornerRadius: min(6, height / 2))
                    .fill(LinearGradient(stops: [.init(color: base, location: 0), .init(color: light, location: 0.5),
                                                 .init(color: base, location: 1)],
                                         startPoint: UnitPoint(x: x - 0.6, y: 0.5), endPoint: UnitPoint(x: x + 0.6, y: 0.5)))
                    .frame(width: g.size.width * fraction)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Listening, nothing said yet.
struct NotesListeningView: View {
    var body: some View {
        VStack(spacing: 22) {
            ListeningMark()
            VStack(spacing: 8) {
                Text("正在听").font(.system(size: 17, weight: .bold))
                Text("有人说话时，会自动开始写纪要").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The first version of the notes is being written: a spinner, how much has been heard, and
/// the shape of the notes shimmering where they will appear.
struct NotesGeneratingView: View {
    var heard: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Spinner()
                HStack(spacing: 0) {
                    Text("正在生成纪要")
                    AnimatedDots()
                }
                .font(.system(size: 15, weight: .bold))
                Spacer()
                if let heard, heard > 0 {
                    Text("已听到 \(heard) 句").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("总结").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.placeholder)
                SkeletonBar()
                SkeletonBar(fraction: 0.92)
                SkeletonBar(fraction: 0.64)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Palette.raised))
            VStack(alignment: .leading, spacing: 14) {
                Text("议题").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.placeholder)
                topicRow(lines: [0.55, 0.88, 0.72])
                topicRow(lines: [0.42, 0.8]).opacity(0.6)
            }
        }
    }

    private func topicRow(lines: [CGFloat]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SkeletonBar(height: 12).frame(width: 36)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, f in
                    SkeletonBar(fraction: f, height: i == 0 ? 14 : 10)
                }
            }
        }
    }
}

/// "正在更新" pill in the header while notes that already exist are being updated.
struct UpdatingPill: View {
    var body: some View {
        HStack(spacing: 7) {
            Spinner(size: 12, track: Color(red: 0.965, green: 0.847, blue: 0.796))
            Text("正在更新").font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Palette.accentInk)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(Palette.accentPale))
        .fixedSize()
    }
}

/// A point that just arrived fades in from slightly below.
struct FadeIn: ViewModifier {
    let active: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(!active || shown ? 1 : 0)
            .offset(y: !active || shown ? 0 : 4)
            .onAppear { if active { withAnimation(.easeOut(duration: 0.6)) { shown = true } } }
    }
}

/// "已经 10 分钟没人说话 · 60 秒后结束": the meeting is about to end by itself. In the notes window
/// and the menu panel; neither takes focus, so a click lands on the buttons at once.
struct MeetingEndingStrip: View {
    @ObservedObject var model: AppModel
    let pending: MeetingEndWatch.Pending
    var compact = false
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.endingTitle(pending)).font(.system(size: compact ? 13 : 14, weight: .bold)).lineLimit(2)
                Text(model.endingDetail(pending, now: now)).font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Palette.secondary).lineLimit(2)
            }
            HStack(spacing: 8) {
                SoftButton(L("继续记录"), dark: true) { model.keepRecording() }
                SoftButton(L("现在结束")) { model.stop() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.accentPale))
        .onReceive(tick) { now = $0 }
    }
}
