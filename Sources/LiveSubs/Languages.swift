import AppKit
import AVFoundation
import AudioToolbox
import CoreAudio
import CoreMedia
import Speech

// MARK: - Languages

struct Lang: Equatable {
    let name: String
    /// Locale used by SpeechTranscriber.
    let locale: String
    /// Language code used by the translation endpoint.
    let code: String
}

let sourceLanguages: [Lang] = [
    .init(name: "English", locale: "en-US", code: "en"),
    .init(name: "日本語", locale: "ja-JP", code: "ja"),
    .init(name: "中文", locale: "zh-CN", code: "zh-CN"),
    .init(name: "한국어", locale: "ko-KR", code: "ko"),
    .init(name: "Español", locale: "es-ES", code: "es"),
    .init(name: "Français", locale: "fr-FR", code: "fr"),
    .init(name: "Deutsch", locale: "de-DE", code: "de"),
    .init(name: "Português", locale: "pt-BR", code: "pt"),
]

let targetLanguages: [Lang] = [
    .init(name: "简体中文", locale: "zh-Hans", code: "zh-CN"),
    .init(name: "繁體中文", locale: "zh-Hant", code: "zh-TW"),
    .init(name: "English", locale: "en", code: "en"),
    .init(name: "日本語", locale: "ja", code: "ja"),
    .init(name: "한국어", locale: "ko", code: "ko"),
    .init(name: "Español", locale: "es", code: "es"),
    .init(name: "Français", locale: "fr", code: "fr"),
    .init(name: "Deutsch", locale: "de", code: "de"),
    .init(name: "Português", locale: "pt", code: "pt"),
]

/// Maps a system language identifier ("zh-Hans-CA", "en-CA", "zh-TW") to a translation code.
func translationCode(forSystemLanguage id: String) -> String {
    let locale = Locale(identifier: id)
    let lang = locale.language.languageCode?.identifier ?? "en"
    guard lang == "zh" else { return lang }
    let script = locale.language.script?.identifier
    let region = locale.region?.identifier
    if script == "Hant" { return "zh-TW" }
    if script == nil, let region, ["TW", "HK", "MO"].contains(region) { return "zh-TW" }
    return "zh-CN"
}

func targetName(_ code: String) -> String {
    targetLanguages.first(where: { $0.code == code })?.name
        ?? Locale.current.localizedString(forIdentifier: code) ?? code
}

/// CJK text is joined without spaces.
func joiner(for code: String) -> String {
    (code.hasPrefix("zh") || code == "ja") ? "" : " "
}

