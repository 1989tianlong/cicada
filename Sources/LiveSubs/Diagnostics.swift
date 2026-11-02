import AppKit
import SwiftUI

// MARK: - Records

/// One provider tried for one translation, and why it fell through.
struct TranslateAttempt: Codable {
    let provider: String   // ling / google / apple
    let seconds: Double
    let failure: String?   // nil = this one answered
}

/// Filled in by `TranslationService` as it walks Ling → Google → Apple.
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
    var total: Double { (recognize ?? 0) + translate }
}

/// One Ling request.
struct LingCall: Codable {
    let at: Date
    let priority: String
    let queue: Double
    let seconds: Double
    let outcome: String    // ok / rateLimited / hijacked / timeout / …
    let promptTokens: Int
    let completionTokens: Int
}

// MARK: - Recorder

/// Keeps the current meeting's timings in memory and appends them to `metrics.jsonl` in the meeting
/// folder. UI-free; everything is on the main actor like the engines that report into it.
@MainActor
final class Diagnostics: ObservableObject {
    @Published private(set) var sentences: [SentenceTiming] = []
    @Published private(set) var calls: [LingCall] = []
    @Published private(set) var startedAt: Date?

    var enabled: () -> Bool = { false }
    /// The live meeting's folder, nil when not listening.
    var folder: () -> URL? = { nil }

    func begin() {
        sentences = []
        calls = []
        startedAt = Date()
    }

    func record(_ s: SentenceTiming) {
        guard enabled() else { return }
        sentences.append(s)
        if sentences.count > 500 { sentences.removeFirst(sentences.count - 500) }
        write("sentence", s)
        debugLog(String(format: "diag: %@ recognize=%@ translate=%.2f queue=%.2f via=%@%@", s.side,
                        s.recognize.map { String(format: "%.2f", $0) } ?? "-", s.translate, s.queue, s.via,
                        s.fallbacks.isEmpty ? "" : " fallbacks=" + s.fallbacks.joined(separator: ",")))
    }

    func record(_ c: LingCall) {
        guard enabled() else { return }
        calls.append(c)
        if calls.count > 1000 { calls.removeFirst(calls.count - 1000) }
        write("ling", c)
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
    var notesRounds: Stat? { Self.stat(calls.filter { $0.priority == "notes" && $0.outcome == "ok" }.map(\.seconds)) }

    /// How many sentences each provider answered, most first.
    var viaCounts: [(String, Int, Double)] {
        Dictionary(grouping: sentences, by: \.via).map { via, xs in
            (via, xs.count, Self.stat(xs.map(\.translate))?.p50 ?? 0)
        }.sorted { $0.1 > $1.1 }
    }

    /// Why Ling (or Google) was passed over: hijacked, rateLimited, timeout…
    var fallbackCounts: [(String, Int)] {
        var counts: [String: Int] = [:]
        for s in sentences { for f in s.fallbacks { counts[f, default: 0] += 1 } }
        for c in calls where c.outcome == "rateLimited" && c.priority == "notes" { counts["notes:rateLimited", default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    /// Ling requests started in the last 10 s, per second (the account allows about 2).
    var lingRate: Double {
        let since = Date().addingTimeInterval(-10)
        return Double(calls.filter { $0.at > since }.count) / 10
    }
    var maxQueue: Double { calls.map(\.queue).max() ?? 0 }
    var tokens: (Int, Int) { calls.reduce((0, 0)) { ($0.0 + $1.promptTokens, $0.1 + $1.completionTokens) } }

    /// Plain text for "复制诊断信息": numbers only, safe to paste anywhere.
    func report(version: String, model: String) -> String {
        func f(_ s: Stat?) -> String { s.map { String(format: "p50 %.2fs p95 %.2fs n=%d", $0.p50, $0.p95, $0.n) } ?? "-" }
        var lines = ["\(appDisplayName) \(version) 诊断  \(Date())", "模型 \(model)"]
        if let startedAt { lines.append(String(format: "本场 %.0f 分钟", Date().timeIntervalSince(startedAt) / 60)) }
        lines.append("说完到出字幕 " + f(endToEnd))
        lines.append("识别定稿 " + f(recognize))
        lines.append("翻译 " + f(translate))
        lines.append("同声传译（松开到译好）" + f(speakBack))
        lines.append("单轮纪要耗时 " + f(notesRounds))
        lines.append("翻译来源 " + viaCounts.map { String(format: "%@ %d (p50 %.2fs)", $0.0, $0.1, $0.2) }.joined(separator: " · "))
        lines.append("换后备 " + (fallbackCounts.isEmpty ? "无" : fallbackCounts.map { "\($0.0) \($0.1)" }.joined(separator: " · ")))
        let t = tokens
        lines.append(String(format: "Ling 请求 %d 次 · 排队最久 %.2fs · token %d/%d", calls.count, maxQueue, t.0, t.1))
        return lines.joined(separator: "\n")
    }
}

// MARK: - View (settings › 诊断)

struct DiagnosticsView: View {
    @ObservedObject var diagnostics: Diagnostics
    var model: String = ""
    @State private var copied = false
    @State private var tick = Date()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.top, -8)
            HStack(spacing: 8) {
                tile("说完到上屏", diagnostics.endToEnd, dark: true)
                tile("识别定稿", diagnostics.recognize)
                tile("翻译", diagnostics.translate)
                tile("纪要一轮", diagnostics.notesRounds)
            }
            providers
            lingCard
            recent
            HStack(spacing: 8) {
                SoftButton(copied ? "已复制" : "复制诊断信息", dark: true) { copy() }
                // The meeting folder holds metrics.jsonl; the log only exists in dev builds or with `debug` on.
                SoftButton(diagnostics.folder() == nil ? "打开日志" : "打开本场数据") {
                    NSWorkspace.shared.open(diagnostics.folder() ?? URL(fileURLWithPath: DevBuild.logPath))
                }
                Spacer()
                Text("只记时间和次数，不存字幕原文").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
            }
        }
        .onReceive(timer) { tick = $0 }
    }

    private var subtitle: String {
        guard let s = diagnostics.startedAt else { return "开始聆听后，这里会显示每句话的耗时明细" }
        let m = Int(tick.timeIntervalSince(s) / 60)
        return "这场会议 · \(m) 分钟 · \(diagnostics.heard.count) 句 · 同声传译 \(diagnostics.said.count) 次"
    }

    private func tile(_ title: String, _ s: Diagnostics.Stat?, dark: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(dark ? Color.white.opacity(0.75) : Palette.secondary)
            Text(s.map { String(format: "%.1fs", $0.p50) } ?? "—").font(.system(size: 20, weight: .bold).monospacedDigit())
                .foregroundStyle(dark ? Color.white : Palette.ink)
            Text(s.map { String(format: "p95 %.1fs · %d", $0.p95, $0.n) } ?? "暂无数据")
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(dark ? Color.white.opacity(0.75) : Palette.tertiary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(dark ? Palette.ink : Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(dark ? .clear : Palette.line, lineWidth: 1))
    }

    private static func color(_ via: String) -> Color {
        switch via {
        case "ling": Palette.ink
        case "google": Palette.accent
        case "ming": Palette.accentInk
        default: Color(red: 0.72, green: 0.74, blue: 0.78)
        }
    }

    private static func name(_ via: String) -> String {
        switch via {
        case "ling": "Ling"
        case "google": "Google"
        case "apple": "本机"
        case "ming": "Ming 语音"
        default: "没译出"
        }
    }

    private static func reason(_ key: String) -> String {
        let parts = key.split(separator: ":").map(String.init)
        let who = parts.first.map { $0 == "ling" ? "Ling" : $0 == "google" ? "Google" : $0 == "notes" ? "纪要" : $0 == "ming" ? "Ming 语音" : "本机" } ?? ""
        let why: String
        switch parts.last ?? "" {
        case "hijacked": why = "被搜索劫持"
        case "rateLimited", "429": why = "限流"
        case "timeout": why = "超时"
        case "unparsed": why = "回复格式不对"
        case "network": why = "网络错误"
        case "unavailable": why = "未安装语言包"
        default: why = parts.last ?? ""
        }
        return "\(who) \(why)"
    }

    private var providers: some View {
        let counts = diagnostics.viaCounts
        let total = max(1, counts.reduce(0) { $0 + $1.1 })
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("翻译通道分布").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text("共 \(diagnostics.sentences.count) 句").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(counts, id: \.0) { c in
                        Rectangle().fill(Self.color(c.0)).frame(width: max(2, geo.size.width * CGFloat(c.1) / CGFloat(total) - 2))
                    }
                    if counts.isEmpty { Rectangle().fill(Palette.fill) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 10)
            HStack(spacing: 14) {
                ForEach(counts, id: \.0) { c in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Self.color(c.0)).frame(width: 8, height: 8)
                        Text(String(format: "%@ %d · %.1fs", Self.name(c.0), c.1, c.2)).font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
            if !diagnostics.fallbackCounts.isEmpty {
                HStack(spacing: 6) {
                    ForEach(diagnostics.fallbackCounts.prefix(4), id: \.0) { f in
                        Text("\(Self.reason(f.0)) \(f.1)").font(.system(size: 12))
                            .foregroundStyle(f.0.hasSuffix("hijacked") ? Palette.accentInk : Palette.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(f.0.hasSuffix("hijacked") ? Palette.accentPale : Palette.fill))
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }

    private var lingCard: some View {
        let _ = tick
        let t = diagnostics.tokens
        return SettingsCard {
            SettingsRow(title: "Ling 请求速度", detail: "账号上限约每秒 2 次") {
                Text(String(format: "%.1f / 2 次每秒", diagnostics.lingRate)).font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Palette.secondary)
            }
            SettingsRow(title: "排队最久") {
                Text(String(format: "%.1fs", diagnostics.maxQueue)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.secondary)
            }
            SettingsRow(title: "本场用量", divider: false) {
                Text("\(diagnostics.calls.count) 次 · \(t.0 + t.1) token").font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Palette.secondary)
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
                        Text("\(Self.clock.string(from: s.at)) \(s.side == "me" ? "你" : "对方")").font(.system(size: 12).monospacedDigit())
                        Text(s.fallbacks.isEmpty ? "\(Self.name(s.via)) · \(s.chars) 字" : s.fallbacks.map(Self.reason).joined(separator: "、") + " → " + Self.name(s.via))
                            .font(.system(size: 10)).foregroundStyle(s.fallbacks.isEmpty ? Palette.tertiary : Palette.accentInk).lineLimit(1)
                    }
                    .frame(width: 150, alignment: .leading)
                    bar(s)
                    Spacer(minLength: 0)
                    Text(String(format: "%.1fs", s.total + (s.voice ?? 0))).font(.system(size: 12, weight: .semibold).monospacedDigit())
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
            if let v = s.voice { seg(v, Color(red: 0.60, green: 0.63, blue: 0.67), scale) }
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
                                      model: model)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

