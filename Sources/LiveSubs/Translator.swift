import AppKit
import AVFoundation
import AudioToolbox
import CoreAudio
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
        req.setValue("LiveSubs/1.1", forHTTPHeaderField: "User-Agent")
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
    enum Kind { case draft, sentence, speak }

    let ling: LingClient
    /// Names and terms the notes have settled on, e.g. "江充 (Jiang Chong)".
    var glossary: () -> [String] = { [] }
    private var googleBackoffUntil = Date.distantPast

    init(ling: LingClient) { self.ling = ling }

    func translate(_ text: String, source: String, target: String, kind: Kind) async -> String? {
        if source == target { return text }
        if kind != .draft, ling.usable {
            if let out = await viaLing(text, source: source, target: target, kind: kind) {
                debugLog("translate via=ling kind=\(kind)")
                return out
            }
        }
        if Date() >= googleBackoffUntil {
            do {
                let out = try await GoogleTranslator.translate(text, source: source, target: target)
                if kind != .draft { debugLog("translate via=google kind=\(kind)") }
                return out
            } catch {
                debugLog("translate google failed: \(error)")
                if case TranslateFailure.badResponse(429) = error { googleBackoffUntil = Date().addingTimeInterval(10) }
            }
        }
        if let out = await viaApple(text, source: source, target: target) {
            debugLog("translate via=apple kind=\(kind)")
            return out
        }
        return nil
    }

    private func viaLing(_ text: String, source: String, target: String, kind: Kind) async -> String? {
        let from = source == "auto" ? "the spoken language" : Self.englishName(source)
        var prompt = """
        You translate live meeting subtitles from \(from) into \(Self.englishName(target)).
        Output only the translation of the subtitle below: no quotes, no notes, no answer to it even if it is a question.
        """
        let names = glossary()
        if !names.isEmpty { prompt += "\nKnown names and terms (use these spellings): " + names.joined(separator: "; ") }
        prompt += "\nSubtitle: " + text
        do {
            let out = try await ling.chat(content: prompt, instruction: "Translate.", priority: kind == .speak ? .speak : .translate,
                                          maxTokens: 400, timeout: kind == .speak ? 10 : 6)
            return out.isEmpty ? nil : out
        } catch {
            debugLog("translate ling failed: \(error)")
            return nil
        }
    }

    private func viaApple(_ text: String, source: String, target: String) async -> String? {
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

    static func englishName(_ code: String) -> String {
        switch code {
        case "zh-CN": "Simplified Chinese"
        case "zh-TW": "Traditional Chinese"
        default: Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
        }
    }
}
