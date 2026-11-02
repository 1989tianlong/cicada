import Testing
@testable import LiveSubs

@Suite struct LanguageTests {
    @Test(arguments: [
        ("zh-Hans-CN", "zh-CN"), ("zh-Hans-CA", "zh-CN"), ("zh-Hant-TW", "zh-TW"),
        ("zh-TW", "zh-TW"), ("zh-HK", "zh-TW"), ("zh-CN", "zh-CN"),
        ("en-CA", "en"), ("ja-JP", "ja"), ("pt-BR", "pt"),
    ])
    func systemLanguageMapsToTranslationCode(id: String, code: String) {
        #expect(translationCode(forSystemLanguage: id) == code)
    }

    @Test func cjkJoinsWithoutSpaces() {
        #expect(joiner(for: "zh-CN") == "")
        #expect(joiner(for: "ja") == "")
        #expect(joiner(for: "en") == " ")
    }

    private let english = sourceLanguages.first { $0.code == "en" }!
    private let japanese = sourceLanguages.first { $0.code == "ja" }!

    @Test func detectionScoreFollowsConfidence() {
        let text = "hello there everyone"
        #expect(LanguageDetector.score(conf: 0.9, chars: text.count, text: text, lang: english) == 0.9)
        #expect(LanguageDetector.score(conf: 0.9, chars: 0, text: "", lang: english) == 0)
    }

    @Test func shortOutputCountsAsNoise() {
        #expect(LanguageDetector.score(conf: 0.9, chars: 3, text: "abc", lang: english) == 0.45)
    }

    @Test func cjkModelWritingLatinIsPenalised() {
        let latin = "hello there everyone"
        let native = "こんにちは皆さん"
        #expect(LanguageDetector.score(conf: 0.8, chars: latin.count, text: latin, lang: japanese) == 0.8 * 0.75)
        #expect(LanguageDetector.score(conf: 0.8, chars: native.count, text: native, lang: japanese) == 0.8)
    }
}
