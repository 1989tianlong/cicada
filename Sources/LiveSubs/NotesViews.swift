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
    var updating = false
    var summaryJustChanged = false
    var onJump: (Double) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !notes.summary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("总结").font(.system(size: 15, weight: .bold))
                        if summaryJustChanged { Tag("刚更新", live: true) }
                        Spacer()
                        if notes.final { Tag("完整版") } else if live { Tag("速记版") }
                    }
                    Text(notes.summary).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(Palette.raised))
            }

            if !notes.topics.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("议题")
                    ForEach(Array(notes.topics.enumerated()), id: \.element.id) { i, topic in
                        TopicView(topic: topic, current: live && i == notes.topics.count - 1,
                                  updating: updating && i == notes.topics.count - 1, fresh: fresh, onJump: onJump)
                    }
                }
            }

            if !notes.conclusions.isEmpty || !notes.todos.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(notes.todos.isEmpty ? "结论" : "结论和待办")
                    FramedList {
                        ForEach(Array((notes.conclusions + notes.todos).enumerated()), id: \.offset) { i, item in
                            let todo = i >= notes.conclusions.count
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                if todo {
                                    Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                                }
                                Text(item.text + (item.owner.map { "（\($0)）" } ?? ""))
                                    .font(.system(size: 14)).lineSpacing(2)
                                    .foregroundStyle(item.support == 0 ? Palette.tertiary : Palette.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Tag(item.support == 0 ? "依据少" : "依据 \(item.support) 句")
                            }
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            if i < notes.conclusions.count + notes.todos.count - 1 { Divider() }
                        }
                    }
                }
            }

            if !notes.terms.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("人名和术语")
                    FlowLayout(spacing: 6) {
                        ForEach(notes.terms) { t in
                            (Text(t.name).bold() + Text(t.note.isEmpty ? "" : " \(t.note)")
                                + Text(t.heard.isEmpty ? "" : " · 原识别 \(t.heard.prefix(2).joined(separator: "、"))")
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
}

private struct TopicView: View {
    let topic: NoteTopic
    let current: Bool
    let updating: Bool
    let fresh: Set<String>
    let onJump: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button { onJump(topic.start) } label: {
                    Text(NotesEngine.clock(topic.start))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(current ? Palette.accentInk : Palette.tertiary)
                        .frame(width: topic.start >= 3600 ? 56 : 40, alignment: .leading)
                }
                .buttonStyle(.plain).help("看原话")
                Text(topic.title).font(.system(size: 15, weight: .bold))
                if current { Tag("正在讲", live: true) }
                if fresh.contains(topic.title) && !current { Tag("新", live: true) }
            }
            VStack(alignment: .leading, spacing: 6) {
                if !topic.summary.isEmpty {
                    Text(topic.summary).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(topic.points, id: \.self) { p in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(fresh.contains(p) ? Palette.accent : Palette.ink.opacity(0.55)).frame(width: 4, height: 4)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        Text(p).font(.system(size: 14)).lineSpacing(2).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if fresh.contains(p) { Tag("新", live: true) }
                    }
                }
                if let fish = topic.fishbone { FishboneView(fishbone: fish, onJump: onJump).padding(.top, 4) }
                if updating {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Palette.fill).frame(height: 9).frame(maxWidth: 260)
                        RoundedRectangle(cornerRadius: 4).fill(Palette.fill).frame(width: 160, height: 9)
                        Text("正在整理这一段…").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.leading, topic.start >= 3600 ? 66 : 50)
        }
        .padding(.vertical, current ? 10 : 0).padding(.horizontal, current ? 10 : 0)
        .background(RoundedRectangle(cornerRadius: 14).fill(current ? Palette.accentWash : .clear))
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
                Text(fishbone.question.isEmpty ? "为什么" : fishbone.question).font(.system(size: 13, weight: .bold))
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
            Text("点分支回到原话").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
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
        .help(weak ? "依据少，仅供参考" : "看原话")
    }
}

// MARK: - Transcript

/// The transcript grouped under the notes' topics, newest at the bottom.
struct TranscriptListView: View {
    let lines: [TranscriptLine]
    let topics: [NoteTopic]
    var query = ""
    var bilingual = true
    var live = false
    var jumpTo: Double?

    private var groups: [(title: String, start: Double, lines: [TranscriptLine])] {
        let shown = query.isEmpty ? lines : lines.filter {
            $0.src.localizedCaseInsensitiveContains(query) || ($0.dst ?? "").localizedCaseInsensitiveContains(query)
        }
        guard !topics.isEmpty else { return [("", 0, shown)] }
        var out: [(String, Double, [TranscriptLine])] = []
        for (i, t) in topics.enumerated() {
            let end = i + 1 < topics.count ? topics[i + 1].start : .infinity
            let first = i == 0 ? -Double.infinity : t.start
            let ls = shown.filter { $0.t >= first && $0.t < end }
            if !ls.isEmpty { out.append((t.title, t.start, ls)) }
        }
        return out
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(groups, id: \.start) { g in
                        if !g.title.isEmpty { SectionTitle(g.title).padding(.top, 6) }
                        FramedList {
                            ForEach(Array(g.lines.enumerated()), id: \.element.id) { i, l in
                                row(l, current: live && l.id == lines.last?.id).id(l.id)
                                if i < g.lines.count - 1 { Divider() }
                            }
                        }
                    }
                    if lines.isEmpty {
                        Text("说话的内容会出现在这里").font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.bottom, 12)
            }
            .onChange(of: lines.count) { _, _ in
                if live, query.isEmpty, let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: jumpTo) { _, t in
                guard let t, let target = lines.first(where: { $0.t >= t - 1 }) ?? lines.last else { return }
                withAnimation { proxy.scrollTo(target.id, anchor: .top) }
            }
            .onAppear {
                if let t = jumpTo, let target = lines.first(where: { $0.t >= t - 1 }) {
                    proxy.scrollTo(target.id, anchor: .top)
                } else if live, let last = lines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func row(_ l: TranscriptLine, current: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(NotesEngine.clock(l.t)).font(.system(size: 12).monospacedDigit())
                .foregroundStyle(current ? Palette.accentInk : Palette.tertiary)
                .frame(width: l.t >= 3600 ? 56 : 40, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if l.speaker == "me" { Text("你").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accentInk) }
                Text(l.src).font(.system(size: 14)).lineSpacing(2).textSelection(.enabled)
                if bilingual, let d = l.dst, d != l.src {
                    Text(d).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(2).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(current ? Palette.accentWash : Color.clear)
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
