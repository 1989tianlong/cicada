import AppKit
import SwiftUI

/// 分享…: a meeting as a link on cicada.indaloop.app. Settings, then the server's review, then the
/// link (and its password) or what the review stopped. A meeting already shared opens on its link.
struct ShareSheet: View {
    let session: Session
    let onClose: () -> Void

    private enum Step: Equatable {
        case settings, working, blocked([ShareHit], kept: [Int]), done(ShareRecord), failed(String)
    }

    @State private var step: Step = .settings
    @State private var scope: ShareScope = .notes
    @State private var days = 7
    @State private var names = false
    @State private var usePassword = false
    @State private var password = SharePassword.make()
    @State private var summaryInPreview = false
    @State private var removed: Set<Int> = []
    @State private var dropNotes = false
    @State private var views: Int?
    @State private var confirmRevoke = false
    @State private var copied: String?

    private var hasNotes: Bool { !(session.notes?.isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case .settings: settings
            case .working: working
            case .blocked(let hits, let kept): blocked(hits, kept: kept)
            case .done(let r): done(r)
            case .failed(let message): failed(message)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            if !hasNotes { scope = .full }
            if let r = ShareStore.read(session.id), r.expiresAt > Date() { step = .done(r); loadViews(r) }
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(L("分享这场会议"), session.displayTitle)
            VStack(alignment: .leading, spacing: 8) {
                Text("内容").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                Picker("", selection: $scope) {
                    Text("只分享纪要").tag(ShareScope.notes).disabled(!hasNotes)
                    Text("纪要和双语全文").tag(ShareScope.full)
                }
                .pickerStyle(.radioGroup).labelsHidden()
            }
            row(L("有效期")) {
                Picker("", selection: $days) {
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                    Text("1 年").tag(365)
                }
                .labelsHidden().fixedSize()
            }
            row(L("显示说话人名字")) { Toggle("", isOn: $names).toggleStyle(.switch).controlSize(.small).labelsHidden() }
            row(L("用密码保护")) { Toggle("", isOn: $usePassword).toggleStyle(.switch).controlSize(.small).labelsHidden() }
            if usePassword {
                HStack(spacing: 8) {
                    TextField("", text: $password).textFieldStyle(.roundedBorder).font(.system(size: 13, design: .monospaced))
                    Button("换一个") { password = SharePassword.make() }.controlSize(.small)
                }
            } else if hasNotes {
                row(L("预览卡显示摘要")) { Toggle("", isOn: $summaryInPreview).toggleStyle(.switch).controlSize(.small).labelsHidden() }
            }
            Text(usePassword ? L("建议把链接和密码分两条消息发送。") : L("内容将上传至 cicada.indaloop.app，拿到链接的人都能看。"))
                .font(.system(size: 12)).foregroundStyle(Palette.tertiary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("取消", action: onClose).keyboardShortcut(.cancelAction)
                Button("生成链接") { go() }.keyboardShortcut(.defaultAction)
                    .disabled(usePassword && password.count < 6)
            }
        }
    }

    private func go() {
        step = .working
        var o = ShareClient.Options()
        o.scope = scope
        o.days = days
        o.names = names
        o.password = usePassword ? password : nil
        o.summaryInPreview = !usePassword && summaryInPreview
        o.removed = removed
        o.dropNotes = dropNotes
        Task {
            switch await ShareClient.shared.share(session, o) {
            case .shared(let r):
                copy(r.url, as: "link")
                step = .done(r)
                views = 0
            case .blocked(let hits, let kept): step = .blocked(hits, kept: kept)
            case .failed(let code, let retry): step = .failed(Self.message(code, retry))
            }
        }
    }

    private var working: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(L("分享这场会议"), session.displayTitle)
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在检查有没有敏感内容…").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    // MARK: Blocked

    private func blocked(_ hits: [ShareHit], kept: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.accentInk)
                Text("检测到潜在敏感内容").font(.system(size: 15, weight: .semibold))
            }
            Text("链接尚未生成。请先核对以下内容：").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            // A plain stack, not a ScrollView: in a sheet that sizes itself, a ScrollView gets no height.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(hits.prefix(5).enumerated()), id: \.offset) { _, h in hitRow(h, kept: kept) }
                if hits.count > 5 {
                    Text("还有 \(hits.count - 5) 处").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }
            let leftover = leftAfterRemoving(hits, kept: kept)
            Text(leftover ? L("去掉后再检查一次；你的记录不会改动。") : L("去掉这些内容后就没有可分享的了。"))
                .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            HStack {
                Spacer()
                Button("返回修改") { step = .settings }.keyboardShortcut(.cancelAction)
                if leftover {
                    Button("去掉这些内容后分享") {
                        removed.formUnion(ShareHit.recordLines(hits, kept: kept))
                        if hits.contains(where: { $0.part == "notes" }) { dropNotes = true }
                        go()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    /// Would anything be left to share once the flagged parts are out? (A notes-only share whose
    /// notes were flagged has nothing; the server would refuse an empty document.)
    private func leftAfterRemoving(_ hits: [ShareHit], kept: [Int]) -> Bool {
        let notesLeft = hasNotes && !dropNotes && !hits.contains { $0.part == "notes" }
        guard scope == .full else { return notesLeft }
        let out = removed.union(ShareHit.recordLines(hits, kept: kept))
        let linesLeft = session.lines.indices.contains { !out.contains($0) && !session.lines[$0].src.isEmpty }
        return notesLeft || linesLeft
    }

    private func hitRow(_ h: ShareHit, kept: [Int]) -> some View {
        let what = h.questions.map(Self.category).joined(separator: "、")
        let quote: String
        let place: String
        if h.part == "notes" {
            place = L("纪要")
            quote = session.notes?.summary ?? ""
        } else {
            let lines = ShareHit.recordLines([h], kept: kept).sorted()
            let a = lines.first.map { TranscriptExport.clock(session.lines[$0].t) } ?? ""
            let b = lines.last.map { TranscriptExport.clock(session.lines[$0].t) } ?? ""
            place = a == b ? a : "\(a)–\(b)"
            quote = lines.first.map { session.lines[$0].src } ?? ""
        }
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(what) · \(place)").font(.system(size: 12, weight: .semibold))
            Text(quote).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(2)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.accentPale))
    }

    static func category(_ q: String) -> String {
        switch q {
        case "credential": return L("密码或密钥")
        case "confidential": return L("未公开的公司信息")
        case "crossborder": return L("不宜跨境传输的信息")
        case "personal": return L("个人身份信息")
        case "harmful": return L("违法或危险内容")
        default: return q
        }
    }

    // MARK: Done

    private func done(_ r: ShareRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(copied == "link" ? L("链接已复制") : L("已分享"), session.displayTitle)
            HStack(spacing: 8) {
                Text(r.url).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Palette.fill))
                Button(copied == "link" ? L("已复制") : L("复制链接")) { copy(r.url, as: "link") }
            }
            if let pw = r.password {
                HStack(spacing: 8) {
                    Text(pw).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.fill))
                    Button(copied == "password" ? L("已复制") : L("复制密码")) { copy(pw, as: "password") }
                }
            }
            Text(status(r)).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            Divider()
            if confirmRevoke {
                VStack(alignment: .leading, spacing: 6) {
                    Text("取消后链接立即失效").font(.system(size: 13, weight: .semibold))
                    Text("已查看过的人可能留有副本。").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                    HStack {
                        Spacer()
                        Button("暂不取消") { confirmRevoke = false }
                        Button("取消分享") {
                            Task {
                                if await ShareClient.shared.revoke(r, sessionID: session.id) { onClose() }
                                else { step = .failed(Self.message("network", nil)) }
                            }
                        }
                    }
                }
            } else {
                HStack {
                    Button("取消分享") { confirmRevoke = true }
                    Spacer()
                    Button("在浏览器中打开") { if let u = URL(string: r.url) { NSWorkspace.shared.open(u) } }
                    Button("完成", action: onClose).keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func status(_ r: ShareRecord) -> String {
        let left = max(1, Int(ceil(r.expiresAt.timeIntervalSinceNow / 86400)))
        let expiry = L("\(left) 天后失效")
        guard let views else { return expiry }
        return expiry + " · " + L("打开 \(views) 次")
    }

    private func loadViews(_ r: ShareRecord) {
        Task {
            let s = await ShareClient.shared.stats([r.id])[r.id]
            if let s {
                if s.state != "live" { ShareStore.remove(session.id); step = .settings } else { views = s.views }
            }
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(L("没有分享出去"), session.displayTitle)
            Text(message).font(.system(size: 13)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("关闭", action: onClose).keyboardShortcut(.cancelAction)
                Button("重试") { go() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    static func message(_ code: String, _ retry: Int?) -> String {
        switch code {
        case "rate_limited", "too_many_shares": return L("分享得太频繁了，请稍后再试。")
        case "review_unavailable": return L("敏感内容检查暂时不可用，没有检查就不会分享。请稍后再试。")
        case "sharing_off": return L("分享功能暂时关闭了。")
        case "update_required": return L("请先更新知了。")
        case "too_large": return L("这场会议太长，可以只分享纪要。")
        case "bad_document": return L("这场会议没有可分享的内容。")
        case "network": return L("连不上 cicada.indaloop.app，请检查网络。")
        default: return L("服务器出了问题，请稍后再试。")
        }
    }

    // MARK: Parts

    private func header(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(sub).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(1)
        }
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            control()
        }
    }

    private func copy(_ text: String, as what: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = what
    }
}
