import AVFoundation
import AudioToolbox
import CoreMedia
import Speech
import Translation

// MARK: - Translation

enum TranslateFailure: Error {
    case badURL
    case badResponse(Int)
    case parse
    case empty
}

struct GoogleTranslator {
    static func translate(_ text: String, source: String, target: String) async throws -> String {
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]
        guard let url = comps.url else { throw TranslateFailure.badURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Cicada/1.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw TranslateFailure.parse }
        guard http.statusCode == 200 else { throw TranslateFailure.badResponse(http.statusCode) }
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [Any],
            let segments = root.first as? [Any]
        else { throw TranslateFailure.parse }
        let result = segments.compactMap { seg -> String? in
            guard let arr = seg as? [Any], let s = arr.first as? String else { return nil }
            return s
        }.joined()
        guard !result.isEmpty else { throw TranslateFailure.empty }
        return result
    }
}


// MARK: - Translation chain

/// Ling (with a key) → Google → Apple's on-device translation.
/// Finished sentences and speak-back go to Ling, which keeps names consistent through a glossary
/// taken from the meeting notes. Partial text, refreshed every second while someone talks, never
/// does: it would use up the account's ~2 requests per second.
@MainActor
final class TranslationService {
    /// `file`: a line of an imported recording, sent to Ling behind everything live.
    enum Kind { case draft, sentence, speak, file }

    let ling: LingClient
    /// Names and terms the notes have settled on, e.g. "江充 (Jiang Chong)".
    var glossary: () -> [String] = { [] }
    private var googleBackoffUntil = Date.distantPast

    init(ling: LingClient) { self.ling = ling }

    /// `trace`, when given, collects which providers were tried, how long each took and why it
    /// fell through (diagnostics; never the text).
    /// Debug (`translateFail:<n>`): the next n sentences fail on every provider, to test the retry.
    var failNext = 0

    /// Partial text (`.draft`) has no trace: each one reports here instead (seconds, answered), so
    /// diagnostics can count them without a line per refresh.
    var onDraft: ((Double, Bool) -> Void)?

    func translate(_ text: String, source: String, target: String, kind: Kind, trace: TranslateTrace? = nil) async -> String? {
        if source == target { return text }
        if kind == .draft, let onDraft {
            let started = Date()
            let out = await chain(text, source: source, target: target, kind: kind, trace: trace)
            onDraft(Date().timeIntervalSince(started), out != nil)
            return out
        }
        return await chain(text, source: source, target: target, kind: kind, trace: trace)
    }

    private func chain(_ text: String, source: String, target: String, kind: Kind, trace: TranslateTrace?) async -> String? {
        if kind == .sentence, failNext > 0 {
            failNext -= 1
            trace?.attempts.append(.init(provider: ling.provider.id.rawValue, seconds: 0, failure: "simulated"))
            return nil
        }
        if kind != .draft, ling.usable {
            let started = Date()
            let (out, failure) = await viaLing(text, source: source, target: target, kind: kind, trace: trace)
            trace?.attempts.append(.init(provider: ling.provider.id.rawValue, seconds: Date().timeIntervalSince(started),
                                         failure: out == nil ? failure : nil))
            if let out {
                debugLog("translate via=\(ling.provider.id.rawValue) kind=\(kind)")
                return out
            }
        }
        if Date() >= googleBackoffUntil {
            let started = Date()
            do {
                let out = try await GoogleTranslator.translate(text, source: source, target: target)
                trace?.attempts.append(.init(provider: "google", seconds: Date().timeIntervalSince(started), failure: nil))
                if kind != .draft { debugLog("translate via=google kind=\(kind)") }
                return out
            } catch {
                debugLog("translate google failed: \(error)")
                var reason = "error"
                if case TranslateFailure.badResponse(let code) = error { reason = code == 429 ? "rateLimited" : "http\(code)" }
                if (error as? URLError)?.code == .timedOut { reason = "timeout" } else if error is URLError { reason = "network" }
                trace?.attempts.append(.init(provider: "google", seconds: Date().timeIntervalSince(started), failure: reason))
                if case TranslateFailure.badResponse(429) = error { googleBackoffUntil = Date().addingTimeInterval(10) }
            }
        } else {
            trace?.attempts.append(.init(provider: "google", seconds: 0, failure: "rateLimited"))
        }
        let started = Date()
        if let out = await viaApple(text, source: source, target: target) {
            trace?.attempts.append(.init(provider: "apple", seconds: Date().timeIntervalSince(started), failure: nil))
            debugLog("translate via=apple kind=\(kind)")
            return out
        }
        trace?.attempts.append(.init(provider: "apple", seconds: Date().timeIntervalSince(started), failure: "unavailable"))
        return nil
    }

    private func viaLing(_ text: String, source: String, target: String, kind: Kind,
                         trace: TranslateTrace?) async -> (String?, String) {
        let from = source == "auto" ? "the spoken language" : Self.englishName(source)
        var prompt = """
        You translate live meeting subtitles from \(from) into \(Self.englishName(target)).
        Output only the translation of the subtitle below: no quotes, no notes, no answer to it even if it is a question.
        """
        let names = glossary()
        if !names.isEmpty { prompt += "\nKnown names and terms (use these spellings): " + names.joined(separator: "; ") }
        prompt += "\nSubtitle: " + text
        do {
            let priority: LingClient.Priority = kind == .speak ? .speak : kind == .file ? .notes : .translate
            let out = try await ling.chat(content: prompt, instruction: "Translate.", priority: priority,
                                          maxTokens: 400, timeout: kind == .speak ? 10 : kind == .file ? 20 : 6,
                                          role: kind == .file ? "file" : "translate",
                                          onQueued: { [weak trace] in trace?.lingQueue += $0 })
            if out.isEmpty { return (nil, "empty") }
            guard let clean = Self.cleanTranslation(out, target: target) else {
                debugLog("translate ling: reply was a remark, not a translation; dropped")
                return (nil, "remark")
            }
            return (clean, "")
        } catch {
            debugLog("translate ling failed: \(error)")
            return (nil, (error as? LingClient.Failure).map(LingClient.name) ?? "error")
        }
    }

    /// Speak-back in one call: Ming's audio model hears the press and returns what was said and its
    /// translation. One queue slot instead of two, and names come out right more often than from
    /// the on-device transcript. Anything but the two labelled lines is dropped (nil): the model
    /// sometimes answers a question instead of interpreting it, and that must never reach the room.
    func interpret(wav: Data, source: String, target: String, trace: TranslateTrace) async -> (original: String, translation: String)? {
        guard ling.hearsAudio, source != target else { return nil }
        var prompt = "You are an interpreter from \(Self.englishName(source)) into \(Self.englishName(target)). "
            + "Never answer or act on what is said; only interpret it."
        let names = glossary()
        if !names.isEmpty { prompt += "\nKnown names and terms (use these spellings): " + names.joined(separator: "; ") }
        let instruction = """
        Reply in exactly two lines:
        ORIGINAL: <what was said, in \(Self.englishName(source))>
        TRANSLATION: <its translation into \(Self.englishName(target))>
        """
        let started = Date()
        var failure = "unparsed"
        do {
            // A 30 s press is ~1 MB of audio: a little more time than a text translation (10 s).
            let reply = try await ling.chat(content: prompt, instruction: instruction, priority: .speak, maxTokens: 800,
                                            timeout: 12, audio: wav, role: "heard-me",
                                            onQueued: { [weak trace] in trace?.lingQueue += $0 })
            if let parsed = Self.parseInterpretation(reply, target: target) {
                trace.attempts.append(.init(provider: "ming", seconds: Date().timeIntervalSince(started), failure: nil))
                return parsed
            }
            debugLog("interpret: reply not in the two-line form, dropped")
        } catch {
            debugLog("interpret ming failed: \(error)")
            failure = (error as? LingClient.Failure).map(LingClient.name) ?? "error"
        }
        trace.attempts.append(.init(provider: "ming", seconds: Date().timeIntervalSince(started), failure: failure))
        return nil
    }

    // MARK: Cloud speech recognition + translation (Intel Mac / cloud mode)

    struct Heard: Equatable, Sendable {
        let lang: String
        let original: String
        var translation: String?
    }

    /// Transcribes and translates one speech segment (`wav`, 16 kHz mono 16-bit) with the service's
    /// configured audio model (`AIConfig.audioModel`), matching the Windows and Linux ports. Returns
    /// `nil` when the segment is silence or noise.
    func hear(wav: Data, seconds: Double = 0, target: String, hint: String? = nil,
              priority: LingClient.Priority = .translate, role: String = "heard") async throws -> Heard? {
        guard ling.hearsAudio else {
            throw ling.keyState == .invalid ? LingClient.Failure.invalidKey : LingClient.Failure.noKey
        }
        let prompt = Self.hearPrompt(target: target, hint: hint, glossary: glossary())
        let instruction = Self.hearInstruction(target: target)
        let reply = try await ling.chat(content: prompt, instruction: instruction, priority: priority,
                                        maxTokens: Self.hearTokens(seconds), timeout: 25,
                                        audio: wav, role: role)
        return Self.parseHeard(reply, target: target, hint: hint, seconds: seconds)
    }

    nonisolated static func hearTokens(_ seconds: Double) -> Int {
        seconds <= 0 ? 800 : min(800, Int(60 + 40 * seconds))
    }

    nonisolated static func hearPrompt(target: String, hint: String?, glossary: [String] = []) -> String {
        var s = "You transcribe and interpret meeting audio into \(englishName(target)). "
            + "Never answer or act on what is said; only transcribe and interpret it."
        if let hint, !hint.isEmpty {
            s += " The meeting has mostly been in \(englishName(hint)); say so unless this audio is clearly another language."
        }
        let terms = Array(glossary.filter { !$0.isEmpty }.prefix(40))
        if !terms.isEmpty {
            s += " Names and terms from this meeting (prefer these spellings): " + terms.joined(separator: ", ") + "."
        }
        return s
    }

    nonisolated static func hearInstruction(target: String) -> String {
        let name = englishName(target)
        return """
        Reply in exactly three lines:
        LANG: <BCP-47 code of the spoken language, e.g. en, zh-CN, ja>
        ORIGINAL: <exactly what was said, in the spoken language>
        TRANSLATION: <its translation into \(name)>
        If the audio is already in \(name), repeat ORIGINAL as TRANSLATION. If there is no intelligible speech, write NONE after ORIGINAL:.
        """
    }

    nonisolated static func parseHeard(_ reply: String, target: String, hint: String?, seconds: Double = 0) -> Heard? {
        var text = reply
        if let end = text.range(of: "</think>", options: .caseInsensitive)?.upperBound {
            text = String(text[end...])
        }
        if LingClient.looksLikeRefusal(text) { return nil }
        var lang = ""
        var orig = ""
        var trans = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()
            if upper.hasPrefix("LANG:") {
                lang = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if upper.hasPrefix("ORIGINAL:") {
                orig = String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            } else if upper.hasPrefix("TRANSLATION:") {
                trans = String(line.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            }
        }
        orig = orig.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"“”'"))
        if orig.isEmpty || ["none", "null", "n/a", "[silence]", "(silence)"].contains(orig.lowercased()) {
            return nil
        }
        if !orig.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) || isNoise(orig, seconds: seconds) {
            return nil
        }
        let normLang = normalizeHeardLang(lang, fallback: hint ?? "en")
        if sameLanguage(normLang, target) {
            return Heard(lang: normLang, original: orig, translation: orig)
        }
        var cleaned = cleanTranslation(trans, target: target)
        let trimSet = CharacterSet(charactersIn: " \t.。!！?？…\"")
        if let c = cleaned, c.trimmingCharacters(in: trimSet).caseInsensitiveCompare(orig.trimmingCharacters(in: trimSet)) == .orderedSame {
            cleaned = nil
        }
        return Heard(lang: normLang, original: orig, translation: cleaned)
    }

    private nonisolated static let noiseCues = [
        "无语音", "没有语音", "没有说话", "空白", "静音", "噪音", "杂音", "音乐", "笑声", "掌声", "咳嗽", "叹气", "呼吸", "背景", "无法识别", "听不清",
        "no speech", "silence", "music", "applause", "laughter", "inaudible", "noise", "cough", "sigh", "breathing", "unintelligible", "blank_audio",
    ]

    private nonisolated static let noiseStarts = [
        "这段音频", "音频中", "没有听到", "未检测到", "there is no speech", "no speech detected", "the audio contains", "this audio is",
    ]

    private nonisolated static let noiseFillers: Set<String> = [
        "嗯", "啊", "哦", "呃", "额", "唉", "噢", "唔", "哈", "嘿", "喂", "欸",
        "mm", "hmm", "uh", "um", "ah", "oh", "eh", "er", "hm", "mhm", "uh-huh", "aha", "huh",
        "うん", "ええ", "ああ", "えー", "あー", "うーん",
        "음", "어", "아", "응", "네",
    ]

    private nonisolated static let noisePunct: Set<UnicodeScalar> = Set(".,!?;:…~-—–'\"“”‘’。，！？、；：（）()[]【】<>《》♪♫ ".unicodeScalars)

    /// True when Ming turned a non-speech sound (a cough, a keyboard tap, music, silence) into a
    /// filler or a description of the sound, or fell into a repetition loop.
    nonisolated static func isNoise(_ original: String, seconds: Double = 0) -> Bool {
        let s = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return true }
        let lower = s.lowercased()
        for (open, close) in [("(", ")"), ("（", "）"), ("[", "]"), ("【", "】"), ("<", ">")] {
            if lower.hasPrefix(open) && lower.hasSuffix(close) && s.count <= 40 {
                return true
            }
        }
        if noiseCues.contains(where: { lower.contains($0) }) &&
            (s.contains("（") || s.contains("(") || s.contains("[") || s.contains("【") || s.count <= 24) {
            return true
        }
        if noiseStarts.contains(where: { lower.hasPrefix($0) }) { return true }

        let bareScalars = lower.unicodeScalars.filter { !noisePunct.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) }
        if bareScalars.isEmpty { return true }
        let bare = String(String.UnicodeScalarView(bareScalars))
        if noiseFillers.contains(bare) { return true }
        if Set(bareScalars).count == 1 && (bareScalars.count >= 5 || noiseFillers.contains(String(bareScalars.first!))) {
            return true
        }

        // Split into words or CJK characters.
        var units: [String] = []
        var word = ""
        for u in lower.unicodeScalars {
            if noisePunct.contains(u) || CharacterSet.whitespacesAndNewlines.contains(u) {
                if !word.isEmpty { units.append(word); word = "" }
            } else if (0x3040...0x9FFF).contains(u.value) || (0xAC00...0xD7AF).contains(u.value) {
                if !word.isEmpty { units.append(word); word = "" }
                units.append(String(u))
            } else {
                word.unicodeScalars.append(u)
            }
        }
        if !word.isEmpty { units.append(word) }
        if units.isEmpty { return true }
        if units.count <= 4 && units.allSatisfy({ noiseFillers.contains($0) }) { return true }

        var run = 1
        for i in 1..<units.count {
            run = units[i] == units[i - 1] ? run + 1 : 1
            if run >= 6 || (run >= 3 && noiseFillers.contains(units[i])) { return true }
        }
        if units.count >= 12 {
            var counts: [String: Int] = [:]
            for u in units { counts[u, default: 0] += 1 }
            let top = counts.values.max() ?? 0
            if top * 2 >= units.count || Set(units).count <= 2 { return true }
        }
        if seconds > 0 && units.count > max(12, Int(ceil(seconds * 12))) { return true }
        return false
    }

    nonisolated static func normalizeHeardLang(_ raw: String, fallback: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-").lowercased()
        if s.isEmpty { return fallback }
        if s.hasPrefix("zh-tw") || s.hasPrefix("zh-hk") || s.hasPrefix("zh-hant") || s.contains("traditional") { return "zh-TW" }
        if s.hasPrefix("zh") || s.contains("chinese") || s == "cmn" || s == "yue" { return "zh-CN" }
        let table: [(String, String)] = [
            ("en", "en"), ("english", "en"),
            ("ja", "ja"), ("jp", "ja"), ("japanese", "ja"),
            ("ko", "ko"), ("kr", "ko"), ("korean", "ko"),
            ("es", "es"), ("spanish", "es"),
            ("fr", "fr"), ("french", "fr"),
            ("de", "de"), ("german", "de"),
            ("ru", "ru"), ("russian", "ru"),
            ("pt", "pt"), ("portuguese", "pt"),
            ("it", "it"), ("italian", "it"),
            ("ar", "ar"), ("arabic", "ar"),
            ("vi", "vi"), ("vietnamese", "vi"),
            ("th", "th"), ("thai", "th"),
            ("id", "id"), ("indonesian", "id"),
        ]
        for (prefix, code) in table {
            if s == prefix || s.hasPrefix(prefix + "-") { return code }
        }
        return fallback
    }

    nonisolated static func sameLanguage(_ a: String, _ b: String) -> Bool {
        let na = normalizeHeardLang(a, fallback: a)
        let nb = normalizeHeardLang(b, fallback: b)
        if na.caseInsensitiveCompare(nb) == .orderedSame { return true }
        if na.hasPrefix("zh") || nb.hasPrefix("zh") { return na.caseInsensitiveCompare(nb) == .orderedSame }
        let ba = na.split(separator: "-").first.map(String.init) ?? na
        let bb = nb.split(separator: "-").first.map(String.init) ?? nb
        return ba.caseInsensitiveCompare(bb) == .orderedSame
    }

    /// `ORIGINAL: …` then `TRANSLATION: …`, both non-empty, and the translation in the target's
    /// script (Chinese/Japanese targets need CJK, others must not be mostly CJK).
    static func parseInterpretation(_ reply: String, target: String) -> (original: String, translation: String)? {
        var original: String?, translation: String?
        for raw in reply.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.uppercased().hasPrefix("ORIGINAL:") {
                original = String(line.dropFirst("ORIGINAL:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.uppercased().hasPrefix("TRANSLATION:") {
                translation = String(line.dropFirst("TRANSLATION:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        guard let o = original, let t = translation, !o.isEmpty, !t.isEmpty, o != t else { return nil }
        let letters = t.unicodeScalars.filter { $0.properties.isAlphabetic }
        let cjk = letters.filter { (0x3040...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }.count
        let wantsCJK = ["zh", "ja", "ko"].contains(where: { target.hasPrefix($0) })
        if wantsCJK ? cjk == 0 : cjk * 2 > letters.count { return nil }
        return (o, t)
    }

    /// "Translate." in each target language, letters only and lowercased.
    nonisolated static let instructionEchoes: Set<String> = [
        "翻译", "翻譯", "translate", "翻訳", "翻訳して", "翻訳する", "翻訳してください", "번역", "번역해", "번역하세요", "번역해주세요",
        "traducir", "traduce", "traduzca", "traduire", "traduisez", "traduis", "übersetzen", "übersetze", "traduzir", "traduza",
    ]

    /// Ling sometimes comments on a garbled subtitle ("The subtitle appears to be… Here is the
    /// best-effort translation:") instead of translating it, and that would land in the subtitles and
    /// the record. Remark lines are dropped, a "Translation:" label is stripped, and what is left must
    /// be in the target's script; nil means the next provider translates it.
    nonisolated static func cleanTranslation(_ reply: String, target: String) -> String? {
        // A line is a remark only when it opens or ends like one and talks about the job itself,
        // so a subtitle that happens to start with "The text…" is kept.
        let opener = ["here is", "here's", "the subtitle", "this subtitle", "the text", "this text", "the original",
                      "the user", "note", "(note", "i'm sorry", "i am sorry", "sorry", "it seems", "it appears", "this appears"]
        let about = ["translat", "subtitle", "garbled", "transcri", "asr", "speech recognition", "best-effort"]
        // The same in Chinese: "请提供需要翻译的字幕内容", "您似乎忘记提供……".
        let zhAbout = ["字幕", "翻译"], zhRemark = ["请提供", "似乎", "看起来", "无法", "乱码", "没有附上", "您只发送"]
        // Reasoning that leaked into the reply ("…</think>") goes; the answer follows it.
        let answer = reply.components(separatedBy: "</think>").last ?? reply
        var kept: [String] = []
        for raw in answer.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let lower = line.lowercased()
            let remark = (opener.contains(where: { lower.hasPrefix($0) }) || line.hasSuffix(":") || line.hasSuffix("："))
                && about.contains(where: { lower.contains($0) })
                || zhAbout.contains(where: { line.contains($0) }) && zhRemark.contains(where: { line.contains($0) })
            if lower.hasPrefix("translation:") {
                line = String(line.dropFirst("translation:".count)).trimmingCharacters(in: .whitespaces)
            } else if remark {
                // A note after the translation ("(Note: …" and its list of other wordings) ends it.
                if !kept.isEmpty { break }
                continue
            }
            if !line.isEmpty { kept.append(line) }
        }
        var out = kept.joined(separator: " ")
        // Quotes come off only when they wrap the whole reply; a closing ” inside it belongs to the text.
        for (open, close) in [("\"", "\""), ("“", "”"), ("「", "」")]
        where out.count >= 2 && out.hasPrefix(open) && out.hasSuffix(close) && out.dropFirst().dropLast().contains(open) == false {
            out = String(out.dropFirst().dropLast())
        }
        out = out.trimmingCharacters(in: .whitespaces)
        guard !out.isEmpty else { return nil }
        // Ling translated the fixed "Translate." instruction instead of the subtitle ("翻译。" for an
        // empty subtitle, or for "Translate this into Chinese please."). A subtitle that really is
        // just "翻译一下" loses Ling's answer too, and the next provider translates it.
        if Self.instructionEchoes.contains(String(out.lowercased().unicodeScalars.filter { $0.properties.isAlphabetic })) { return nil }
        let letters = out.unicodeScalars.filter { $0.properties.isAlphabetic }
        let cjk = letters.filter { (0x3040...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }.count
        let wantsCJK = ["zh", "ja", "ko"].contains(where: { target.hasPrefix($0) })
        if !letters.isEmpty, wantsCJK ? cjk == 0 : cjk * 2 > letters.count { return nil }
        return out
    }

    /// Apple's on-device translation, made outside a SwiftUI view: only on macOS 26.
    private func viaApple(_ text: String, source: String, target: String) async -> String? {
        guard Recognition.hasOnDeviceTranslation, #available(macOS 26, *) else { return nil }
        guard source != "auto" else { return nil }
        let from = Locale.Language(identifier: Self.appleCode(source))
        let to = Locale.Language(identifier: Self.appleCode(target))
        guard await LanguageAvailability().status(from: from, to: to) == .installed else { return nil }
        do {
            let session = TranslationSession(installedSource: from, target: to)
            return try await session.translate(text).targetText
        } catch {
            debugLog("translate apple failed: \(error)")
            return nil
        }
    }

    private static func appleCode(_ code: String) -> String {
        switch code {
        case "zh-CN": "zh-Hans"
        case "zh-TW": "zh-Hant"
        default: code
        }
    }

    nonisolated static func englishName(_ code: String) -> String {
        switch code {
        case "zh-CN": "Simplified Chinese"
        case "zh-TW": "Traditional Chinese"
        default: Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
        }
    }
}
