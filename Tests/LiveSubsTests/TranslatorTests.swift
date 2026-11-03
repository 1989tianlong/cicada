import Testing
@testable import LiveSubs

@Suite struct TranslatorTests {
    @Test func remarkInsteadOfTranslationIsDropped() {
        // Issue #2: Ling commented on a garbled line and the remark became the subtitle.
        let reply = "The subtitle appears to be a mix of Chinese and heavily garbled English (likely from poor audio or ASR errors). Here is the best-effort translation:"
        #expect(TranslationService.cleanTranslation(reply, target: "en-US") == nil)
        #expect(TranslationService.cleanTranslation(reply, target: "zh-CN") == nil)
    }

    @Test func remarkLinesAroundATranslationAreStripped() {
        let reply = "Here is the best-effort translation:\n我们周五前把落地页文案定下来。"
        #expect(TranslationService.cleanTranslation(reply, target: "zh-CN") == "我们周五前把落地页文案定下来。")
        #expect(TranslationService.cleanTranslation("Translation: We ship on Friday.", target: "en-US") == "We ship on Friday.")
        #expect(TranslationService.cleanTranslation("“我们周五发布。”", target: "zh-CN") == "我们周五发布。")
    }

    @Test func ordinaryTranslationsAreKept() {
        #expect(TranslationService.cleanTranslation("The text is due on Friday.", target: "en-US") == "The text is due on Friday.")
        #expect(TranslationService.cleanTranslation("There are three points:", target: "en-US") == "There are three points:")
        #expect(TranslationService.cleanTranslation("Note the deadline is Tuesday.", target: "en-US") == "Note the deadline is Tuesday.")
        #expect(TranslationService.cleanTranslation("2026", target: "zh-CN") == "2026")
        #expect(TranslationService.cleanTranslation("我们用 API 和 SDK。", target: "zh-CN") == "我们用 API 和 SDK。")
    }

    @Test func translationInTheWrongScriptIsDropped() {
        #expect(TranslationService.cleanTranslation("We ship on Friday.", target: "zh-CN") == nil)
        #expect(TranslationService.cleanTranslation("我们周五发布。", target: "en-US") == nil)
    }
}
