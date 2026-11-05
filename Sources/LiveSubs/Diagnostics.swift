import AppKit
import SwiftUI

// MARK: - Records

/// One provider tried for one translation, and why it fell through.
struct TranslateAttempt: Codable {
    let provider: String   // the AI service (ling, zenmux…) / ming / google / apple
    let seconds: Double
    let failure: String?   // nil = this one answered
}

/// Filled in by `TranslationService` as it walks the AI service → Google → Apple.
@MainActor
final class TranslateTrace {
    var attempts: [TranslateAttempt] = []
    var lingQueue: Double = 0
    var failedSeconds: Double { attempts.filter { $0.failure != nil }.reduce(0) { $0 + $1.seconds } }
    var via: String { attempts.first(where: { $0.failure == nil })?.provider ?? "none" }
    var fallbacks: [String] { attempts.compactMap { a in a.failure.map { "\(a.provider):\($0)" } } }
}

/// Timings for one sentence, heard ("them") or said ("me"). Never the text itself.
struct SentenceTiming: Codable, Identifiable {
    var id = UUID()
    let at: Date
    let side: String
    let chars: Int
    /// them: last word spoken → final transcript (audio clock); me: key released → transcript.
    let recognize: Double?
    /// Waiting at Ling's start gate (part of `translate`).
    let queue: Double
    /// Final transcript → translation, the whole chain.
    let translate: Double
    /// me: translation → the voice finished.
    let voice: Double?
    /// Time spent on providers that failed before the one that answered (part of `translate`).
    let failed: Double
    let via: String
    let fallbacks: [String]
    /// me: translation → the first sound in the room (what the other side waits for).
    var firstAudio: Double? = nil
    var total: Double { (recognize ?? 0) + translate }
}

/// One request to the AI service (any provider, any model), written as `"type":"call"`.
struct AICall: Codable {
    let at: Date
    /// `AIProvider.ID` raw value: ling / openrouter / zenmux / openai / custom.
    let provider: String
    let model: String
    /// What it was for: translate / notes / voice / heard-me / speakers / test.
    let role: String
    /// The gate's lane (speak / translate / notes), not the use: speak-back translation is "translate".
    let priority: String
    let queue: Double
    let seconds: Double
    let outcome: String    // ok / rateLimited / hijacked / timeout / …
    let promptTokens: Int
    let completionTokens: Int
    /// voice: characters spoken.
    var chars = 0
    /// voice: request start → first audio chunk.
    var firstAudio: Double?
}

// MARK: - Recorder

/// Keeps the current meeting's timings in memory and appends them to `metrics.jsonl` in the meeting
/// folder. UI-free; everything is on the main actor like the engines that report into it.
@MainActor
final class Diagnostics: ObservableObject {
    @Published private(set) var sentences: [SentenceTiming] = []
    @Published private(set) var calls: [AICall] = []
    /// Partial translations, refreshed about every second while someone talks: counted, not listed.
    @Published private(set) var drafts = Drafts()
    @Published private(set) var startedAt: Date?
    /// When the meeting stopped: the header stops counting minutes.
    @Published private(set) var endedAt: Date?

    var enabled: () -> Bool = { false }
    /// The live meeting's folder, nil when not listening.
    var folder: () -> URL? = { nil }

    func begin() {
        sentences = []
        calls = []
        drafts = Drafts()
        startedAt = Date()
        endedAt = nil
    }

    func end() { if startedAt != nil, endedAt == nil { endedAt = Date() } }

    func record(_ s: SentenceTiming) {
        guard enabled() else { return }
        sentences.append(s)
        if sentences.count > 500 { sentences.removeFirst(sentences.count - 500) }
        write("sentence", s)
        debugLog(String(format: "diag: %@ recognize=%@ translate=%.2f queue=%.2f via=%@%@", s.side,
                        s.recognize.map { String(format: "%.2f", $0) } ?? "-", s.translate, s.queue, s.via,
                        s.fallbacks.isEmpty ? "" : " fallbacks=" + s.fallbacks.joined(separator: ",")))
    }

    func record(_ c: AICall) {
        guard enabled() else { return }
        calls.append(c)
        if calls.count > 1000 { calls.removeFirst(calls.count - 1000) }
        write("call", c)
    }

    struct Drafts: Equatable {
        var n = 0
        var failed = 0
        var seconds: [Double] = []
    }

    /// Memory only: a line per refresh would bury the sentences in metrics.jsonl.
    func recordDraft(seconds: Double, ok: Bool) {
        guard enabled() else { return }
        drafts.n += 1
        if ok {
            drafts.seconds.append(seconds)
            if drafts.seconds.count > 2000 { drafts.seconds.removeFirst(drafts.seconds.count - 2000) }
        } else {
            drafts.failed += 1
        }
    }

    private func write<T: Encodable>(_ type: String, _ value: T) {
        guard let dir = folder() else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(value), var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        obj["type"] = type
        obj.removeValue(forKey: "id")
        guard var line = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        let url = dir.appendingPathComponent("metrics.jsonl")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(line)
            try? h.close()
        } else {
            try? line.write(to: url)
        }
    }

    // MARK: Summary

    struct Stat { let p50: Double; let p95: Double; let n: Int }

    static func stat(_ xs: [Double]) -> Stat? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let pick = { (q: Double) in s[min(s.count - 1, Int((q * Double(s.count - 1)).rounded()))] }
        return Stat(p50: pick(0.5), p95: pick(0.95), n: s.count)
    }

    var heard: [SentenceTiming] { sentences.filter { $0.side == "them" } }
    var said: [SentenceTiming] { sentences.filter { $0.side == "me" } }
    var endToEnd: Stat? { Self.stat(heard.map(\.total)) }
    var recognize: Stat? { Self.stat(heard.compactMap(\.recognize)) }
    var translate: Stat? { Self.stat(heard.map(\.translate)) }
    var speakBack: Stat? { Self.stat(said.map { ($0.recognize ?? 0) + $0.translate }) }
    var notesRounds: Stat? { Self.stat(calls.filter { $0.role == "notes" && $0.outcome == "ok" }.map(\.seconds)) }
    /// Key released → the first sound in the room.
    var toRoom: Stat? { Self.stat(said.compactMap { s in s.firstAudio.map { (s.recognize ?? 0) + s.translate + $0 } }) }
    /// What I said, recognized on this Mac (Ming hears it on the service instead: that's a call).
    var recognizeMine: Stat? { Self.stat(said.filter { $0.via != "ming" }.compactMap(\.recognize)) }
    var draftStat: Stat? { Self.stat(drafts.seconds) }

    /// One row of the diagnostics list: a use with the service and model it went to.
    struct Use: Identifiable {
        let role: String
        let provider: String
        let model: String
        var id: String { "\(role)|\(provider)|\(model)" }
        let n: Int
        let failed: Int
        /// ok requests; voice: to the first audio, not the whole clip.
        let latency: Stat?
        let tokens: Int
        let chars: Int
        /// Why the failed ones failed, most first.
        let reasons: [(String, Int)]
    }

    /// The uses shown, in this order; test scores and file imports only count in the totals.
    static let roles = ["translate", "heard-me", "voice", "notes", "speakers"]

    var uses: [Use] {
        Dictionary(grouping: calls.filter { Self.roles.contains($0.role) }) { "\($0.role)|\($0.provider)|\($0.model)" }
            .values.compactMap { xs -> Use? in
                guard let c = xs.first else { return nil }
                let ok = xs.filter { $0.outcome == "ok" }
                // A voice cut short on purpose (stop, a new press) isn't a failure.
                let failed = xs.filter { $0.outcome != "ok" && $0.outcome != "cancelled" }
                var reasons: [String: Int] = [:]
                for f in failed { reasons[f.outcome, default: 0] += 1 }
                return Use(role: c.role, provider: c.provider, model: c.model, n: xs.count, failed: failed.count,
                           latency: Self.stat(c.role == "voice" ? ok.compactMap(\.firstAudio) : ok.map(\.seconds)),
                           tokens: xs.reduce(0) { $0 + $1.promptTokens + $1.completionTokens },
                           chars: xs.reduce(0) { $0 + $1.chars },
                           reasons: reasons.sorted { $0.value > $1.value }.map { ($0.key, $0.value) })
            }
            .sorted { a, b in
                let (i, j) = (Self.roles.firstIndex(of: a.role) ?? 99, Self.roles.firstIndex(of: b.role) ?? 99)
                return i != j ? i < j : a.n > b.n
            }
    }

    /// Sentences the AI service gave up on, by who answered instead (google / apple / none), most first.
    var retreats: [(String, Int)] {
        let services = Set(AIProvider.all.map(\.id.rawValue))
        let xs = sentences.filter { s in s.fallbacks.contains { services.contains(String($0.split(separator: ":").first ?? "")) } }
        return Dictionary(grouping: xs, by: \.via).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    }
    var voiceChars: Int { calls.filter { $0.role == "voice" }.reduce(0) { $0 + $1.chars } }

    /// How many sentences each provider answered, most first.
    var viaCounts: [(String, Int, Double)] {
        Dictionary(grouping: sentences, by: \.via).map { via, xs in
            (via, xs.count, Self.stat(xs.map(\.translate))?.p50 ?? 0)
        }.sorted { $0.1 > $1.1 }
    }

    /// Why the AI service (or Google) was passed over: hijacked, rateLimited, timeout…
    var fallbackCounts: [(String, Int)] {
        var counts: [String: Int] = [:]
        for s in sentences { for f in s.fallbacks { counts[f, default: 0] += 1 } }
        for c in calls where c.outcome == "rateLimited" && c.role == "notes" { counts["notes:rateLimited", default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    /// Requests started in the last 10 s, per second (a Ling account allows about 2).
    var lingRate: Double {
        let since = Date().addingTimeInterval(-10)
        return Double(calls.filter { $0.at > since }.count) / 10
    }
    var maxQueue: Double { calls.map(\.queue).max() ?? 0 }
    var tokens: (Int, Int) { calls.reduce((0, 0)) { ($0.0 + $1.promptTokens, $0.1 + $1.completionTokens) } }

    /// Plain text for "复制诊断信息": numbers only, safe to paste anywhere. Full model names live
    /// here, the page shortens them.
    func report(version: String, service: AIConfig) -> String {
        func f(_ s: Stat?) -> String { s.map { String(format: "p50 %.2fs p95 %.2fs n=%d", $0.p50, $0.p95, $0.n) } ?? "-" }
        var lines = [L("\(appDisplayName) \(version) 诊断  \(Date())"),
                     "AI: \(service.provider.id.rawValue) · \(service.textModel)" + (service.voiceModel.map { " · " + $0 } ?? "")]
        if let startedAt { lines.append(String(format: L("本场 %.0f 分钟"), (endedAt ?? Date()).timeIntervalSince(startedAt) / 60)) }
        lines.append(L("说完到出字幕 ") + f(endToEnd))
        lines.append(L("识别定稿 ") + f(recognize))
        lines.append(L("翻译 ") + f(translate))
        lines.append(L("同声传译（松开到对方听到）") + f(toRoom))
        for u in uses {
            var line = "\(u.role) \(u.provider) \(u.model) \(f(u.latency)) calls=\(u.n) failed=\(u.failed)"
            if !u.reasons.isEmpty { line += " (" + u.reasons.map { "\($0.0) \($0.1)" }.joined(separator: ", ") + ")" }
            if u.tokens > 0 { line += " tokens=\(u.tokens)" }
            if u.chars > 0 { line += " chars=\(u.chars)" }
            lines.append(line)
        }
        if drafts.n > 0 { lines.append("draft google \(f(draftStat)) calls=\(drafts.n) failed=\(drafts.failed)") }
        lines.append(L("翻译来源 ") + viaCounts.map { String(format: "%@ %d (p50 %.2fs)", $0.0, $0.1, $0.2) }.joined(separator: " · "))
        lines.append(L("换后备 ") + (fallbackCounts.isEmpty ? L("无") : fallbackCounts.map { "\($0.0) \($0.1)" }.joined(separator: " · ")))
        let t = tokens
        lines.append(String(format: L("AI 请求 %d 次 · 排队最久 %.2fs · token %d/%d"), calls.count, maxQueue, t.0, t.1))
        return lines.joined(separator: "\n")
    }
}

// MARK: - View (settings › 诊断)

struct DiagnosticsView: View {
    @ObservedObject var diagnostics: Diagnostics
    /// The service in settings: names the group, and the empty page before any request.
    var service: AIConfig
    @State private var copied = false
    @State private var tick = Date()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.top, -8)
            if empty {
                // Nothing measured yet: four dashes, a grey bar and zeros read as broken. Show
                // what each stage is and the shape a sentence will take instead.
                pipeline
                emptyChannels
                emptyRecent
            } else {
                // What people feel; each step's time is in the list below.
                HStack(spacing: 8) {
                    tile(L("对方说完 → 你看到字幕"), diagnostics.endToEnd, dark: true)
                    tile(L("你说完 → 对方听到"), diagnostics.toRoom)
                }
                uses
                totals
                recent
            }
            HStack(spacing: 8) {
                SoftButton(copied ? L("已复制") : L("复制诊断信息"), dark: !empty) { copy() }
                    .disabled(empty)
                // The meeting folder holds metrics.jsonl; the log only exists in dev builds or with `debug` on.
                SoftButton(diagnostics.folder() == nil ? L("打开日志") : L("打开本场数据")) {
                    NSWorkspace.shared.open(diagnostics.folder() ?? URL(fileURLWithPath: DevBuild.logPath))
                }
                Spacer()
                Text("只记时间和次数，不存字幕原文").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
            }
        }
        .onReceive(timer) { tick = $0 }
    }

    private var empty: Bool { diagnostics.sentences.isEmpty && diagnostics.calls.isEmpty }

    private var subtitle: String {
        guard let s = diagnostics.startedAt else { return L("开始聆听后，这里会显示每句话的耗时明细") }
        if empty { return L("有人说话后，这里会显示每句话的耗时明细") }
        let m = Int((diagnostics.endedAt ?? tick).timeIntervalSince(s) / 60)
        return L("这场会议 · \(m) 分钟 · \(diagnostics.heard.count) 句 · 同声传译 \(diagnostics.said.count) 次")
    }

    private func tile(_ title: String, _ s: Diagnostics.Stat?, dark: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(dark ? Color.white.opacity(0.75) : Palette.secondary)
            Text(s.map { String(format: "%.1fs", $0.p50) } ?? "—").font(.system(size: 20, weight: .bold).monospacedDigit())
                .foregroundStyle(dark ? Color.white : Palette.ink)
            Text(s.map { String(format: "p95 %.1fs · %d", $0.p95, $0.n) } ?? L("暂无数据"))
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(dark ? Color.white.opacity(0.75) : Palette.tertiary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(dark ? Palette.ink : Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(dark ? .clear : Palette.line, lineWidth: 1))
    }

    // MARK: Before any sentence

    private var pipeline: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("一句话的路").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text("还没有句子").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.fill).frame(height: 4)
                        Circle().fill(Palette.accent).frame(width: 10, height: 10)
                            .offset(x: phase(ctx.date, period: 2.4) * (g.size.width - 10))
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(height: 10).padding(.horizontal, 14).accessibilityHidden(true)
            HStack(alignment: .top, spacing: 8) {
                stage(L("识别定稿"), L("听清这句话"))
                stage(L("翻译"), L("译成目标语言"))
                stage(L("说完到上屏"), L("你感到的延迟"))
                stage(L("纪要一轮"), L("更新一次纪要"))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }

    private func stage(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.system(size: 11)).foregroundStyle(Palette.tertiary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("– s").font(.system(size: 18, weight: .bold).monospacedDigit()).foregroundStyle(Palette.placeholder)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
    }

    private var emptyChannels: some View {
        SettingsCard {
            SettingsRow(title: L("AI 服务"), detail: service.provider.id == .ling ? L("账号上限约每秒 2 次") : nil) {
                Text("\(service.provider.name) · \(Self.short(service.textModel))").font(.system(size: 12))
                    .foregroundStyle(Palette.secondary).lineLimit(1)
            }
            SettingsRow(title: L("本场用量"), divider: false) {
                Text("本场还没调用").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
        }
    }

    private var emptyRecent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近的句子").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
            HStack(spacing: 10) {
                Text("示例 · 对方").font(.system(size: 12)).foregroundStyle(Palette.tertiary).frame(width: 150, alignment: .leading)
                HStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.42, green: 0.44, blue: 0.50)).frame(width: 70)
                    RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.96, green: 0.78, blue: 0.71)).frame(width: 18)
                    RoundedRectangle(cornerRadius: 2).fill(Palette.ink).frame(width: 46)
                }
                .frame(height: 10)
                Spacer(minLength: 0)
                Text("2.4s").font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            .opacity(0.5)
            HStack(spacing: 14) {
                legend(Color(red: 0.42, green: 0.44, blue: 0.50), L("识别"))
                legend(Color(red: 0.96, green: 0.78, blue: 0.71), L("排队"))
                legend(Palette.ink, L("翻译"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
        }
    }

    /// The service's own ids (ling, zenmux…), as recorded in `via` and the fallbacks.
    private static func serviceName(_ id: String) -> String? { AIProvider.all.first { $0.id.rawValue == id }?.name }

    private static func color(_ via: String) -> Color {
        switch via {
        case "google": Palette.accent
        case "ming": Palette.accentInk
        default: serviceName(via) != nil ? Palette.ink : Color(red: 0.72, green: 0.74, blue: 0.78)
        }
    }

    private static func name(_ via: String) -> String {
        switch via {
        case "google": "Google"
        case "apple": L("本机")
        case "ming": L("Ming 语音")
        default: serviceName(via) ?? L("没译出")
        }
    }

    private static func reason(_ key: String) -> String {
        let parts = key.split(separator: ":").map(String.init)
        let who = parts.count < 2 ? "" : parts.first.map { $0 == "google" ? "Google" : $0 == "notes" ? L("纪要") : $0 == "ming" ? L("Ming 语音") : serviceName($0) ?? L("本机") } ?? ""
        let why: String
        switch parts.last ?? "" {
        case "hijacked": why = L("被搜索劫持")
        case "rateLimited", "429": why = L("限流")
        case "timeout": why = L("超时")
        case "unparsed": why = L("回复格式不对")
        case "network": why = L("网络错误")
        case "unavailable": why = L("未安装语言包")
        default: why = parts.last ?? ""
        }
        return who.isEmpty ? why : "\(who) \(why)"
    }

    /// "inclusionai/ling-3.0-flash" → "ling-3.0-flash": the vendor is in the group name already.
    static func short(_ model: String) -> String { model.split(separator: "/").last.map(String.init) ?? model }

    private static func seconds(_ x: Double) -> String { String(format: "%.1fs", x) }

    private static func count(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)" }

    private static func title(_ role: String) -> String {
        switch role {
        case "translate": L("整句翻译")
        case "heard-me": L("听懂你说的")
        case "voice": L("同传声音")
        case "notes": L("实时纪要")
        case "speakers": L("认出说话人")
        default: role
        }
    }

    /// 1A: one row per use, a single big number (p50) with p95 under it. Uses that follow the AI
    /// service come first; the ones fixed on this Mac or Google come after, so switching service
    /// visibly changes only the first group.
    private var uses: some View {
        let uses = diagnostics.uses
        let retreats = diagnostics.retreats
        let current = service.provider.id.rawValue
        return VStack(alignment: .leading, spacing: 0) {
            group(L("跟着 AI 服务走 · \(service.provider.name)"))
            if uses.isEmpty {
                Text("本场还没调用").font(.system(size: 12)).foregroundStyle(Palette.tertiary).padding(.vertical, 9)
            }
            ForEach(Array(uses.enumerated()), id: \.element.id) { i, u in
                let model = (u.provider == current ? "" : (Self.serviceName(u.provider) ?? u.provider) + " · ") + Self.short(u.model)
                var foot = [L("\(u.n) 次")]
                if u.tokens > 0 { foot.append("\(Self.count(u.tokens)) token") }
                if u.chars > 0 { foot.append(L("\(u.chars) 字")) }
                var pill: String?
                let why = u.reasons.prefix(2).map { "\(Self.reason($0.0)) \($0.1)" }.joined(separator: "、")
                if u.role == "translate", let top = retreats.first {
                    let n = retreats.reduce(0) { $0 + $1.1 }
                    pill = L("\(n) 句退回 \(Self.name(top.0))") + (why.isEmpty ? "" : " · " + why)
                } else if u.failed > 0 {
                    pill = L("失败 \(u.failed)") + (why.isEmpty ? "" : " · " + why)
                } else {
                    foot.append(L("没有失败"))
                }
                return useRow(Self.title(u.role), u.role == "voice" ? model + " · " + L("到开始出声") : model,
                              u.latency, foot: foot, pill: pill, divider: i > 0)
            }
            let fixed = fixedRows
            if !fixed.isEmpty {
                group(L("不受换服务影响")).padding(.top, 12)
                ForEach(Array(fixed.enumerated()), id: \.offset) { i, r in
                    useRow(r.title, r.detail, r.stat, foot: r.foot, dim: true, divider: i > 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }

    private var fixedRows: [(title: String, detail: String, stat: Diagnostics.Stat?, foot: [String])] {
        var rows: [(title: String, detail: String, stat: Diagnostics.Stat?, foot: [String])] = []
        if let r = diagnostics.recognize { rows.append((L("识别对方"), L("本机识别"), r, [L("\(r.n) 句")])) }
        if let r = diagnostics.recognizeMine { rows.append((L("识别你说的"), L("本机识别"), r, [L("\(r.n) 句")])) }
        let d = diagnostics.drafts
        if d.n > 0 {
            rows.append((L("半句翻译"), "Google", diagnostics.draftStat,
                         [L("\(d.n) 次"), d.failed > 0 ? L("失败 \(d.failed)") : L("没有失败")]))
        }
        return rows
    }

    private func group(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.tertiary).padding(.bottom, 2)
    }

    private func useRow(_ title: String, _ detail: String, _ s: Diagnostics.Stat?, foot: [String] = [], pill: String? = nil,
                        dim: Bool = false, divider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: dim ? .medium : .semibold)).foregroundStyle(Palette.ink)
                    Text(detail).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(s.map { Self.seconds($0.p50) } ?? "—")
                        .font(.system(size: dim ? 15 : 18, weight: .bold).monospacedDigit()).foregroundStyle(Palette.ink)
                    if let s { Text("p95 " + Self.seconds(s.p95)).font(.system(size: 10).monospacedDigit()).foregroundStyle(Palette.tertiary) }
                }
            }
            if pill != nil || !foot.isEmpty {
                HStack(spacing: 6) {
                    if let pill {
                        Text(pill).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.accentInk).lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 1.5)
                            .background(Capsule().fill(Palette.accentPale))
                    }
                    Text(foot.joined(separator: " · ")).font(.system(size: 11).monospacedDigit()).foregroundStyle(Palette.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { if divider { Rectangle().fill(Palette.line).frame(height: 1) } }
    }

    private var totals: some View {
        let _ = tick
        let t = diagnostics.tokens
        let n = diagnostics.calls.count
        let chars = diagnostics.voiceChars
        return SettingsCard {
            if service.provider.id == .ling {
                SettingsRow(title: L("Ling 请求速度"), detail: L("账号上限约每秒 2 次")) {
                    Text(String(format: L("%.1f / 2 次每秒"), diagnostics.lingRate)).font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
            }
            SettingsRow(title: L("排队最久"), detail: L("请求太密时，纪要让翻译先走")) {
                Text(String(format: "%.1fs", diagnostics.maxQueue)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.secondary)
            }
            SettingsRow(title: L("本场用量"), detail: L("服务返回的数，以服务的账单为准"), divider: false) {
                Text(chars > 0 ? L("\(n) 次 · \(t.0 + t.1) token · \(chars) 字语音") : L("\(n) 次 · \(t.0 + t.1) token"))
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.secondary)
            }
        }
    }

    /// The last few sentences as stacked bars: recognise · queue · translate (· voice).
    private var recent: some View {
        let rows = Array(diagnostics.sentences.suffix(6).reversed())
        return VStack(alignment: .leading, spacing: 0) {
            Text("最近的句子").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink).padding(.bottom, 8)
            if rows.isEmpty {
                Text("还没有").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
            ForEach(rows) { s in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Self.clock.string(from: s.at)) \(s.side == "me" ? L("你") : L("对方"))").font(.system(size: 12).monospacedDigit())
                        Text(s.fallbacks.isEmpty ? L("\(Self.name(s.via)) · \(s.chars) 字") : s.fallbacks.map(Self.reason).joined(separator: "、") + " → " + Self.name(s.via))
                            .font(.system(size: 10)).foregroundStyle(s.fallbacks.isEmpty ? Palette.tertiary : Palette.accentInk).lineLimit(1)
                    }
                    .frame(width: 150, alignment: .leading)
                    bar(s)
                    Spacer(minLength: 0)
                    Text(String(format: "%.1fs", s.total + (s.firstAudio ?? s.voice ?? 0))).font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
                .frame(height: 34)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }

    private func bar(_ s: SentenceTiming) -> some View {
        let scale: CGFloat = 50   // points per second; 4 s ≈ 200 pt
        let fallback = s.failed
        return HStack(spacing: 1) {
            if let r = s.recognize { seg(r, Color(red: 0.42, green: 0.44, blue: 0.50), scale) }
            if s.queue > 0.05 { seg(s.queue, Color(red: 0.96, green: 0.78, blue: 0.71), scale) }
            if fallback > 0.05 { seg(fallback, Palette.accent, scale) }
            seg(max(0.02, s.translate - s.queue - fallback), Palette.ink, scale)
            // Speak-back counts to the first sound, not the whole clip: that's what the other side waits for.
            if let v = s.firstAudio ?? s.voice { seg(v, Color(red: 0.60, green: 0.63, blue: 0.67), scale) }
        }
        .frame(width: 200, alignment: .leading).clipped()
    }

    private func seg(_ seconds: Double, _ color: Color, _ scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: max(2, CGFloat(seconds) * scale), height: 10)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func copy() {
        let text = diagnostics.report(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                                      service: service)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

