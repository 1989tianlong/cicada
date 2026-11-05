import AVFoundation
import Testing
@testable import Cicada

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

    @Test func translatedInstructionIsDropped() {
        // Ling answered "Translate this into Chinese please." and an empty subtitle with "翻译。":
        // the fixed "Translate." instruction, translated.
        #expect(TranslationService.cleanTranslation("翻译。", target: "zh-CN") == nil)
        #expect(TranslationService.cleanTranslation("Translate.", target: "en-US") == nil)
        #expect(TranslationService.cleanTranslation("翻訳してください。", target: "ja") == nil)
        #expect(TranslationService.cleanTranslation("好的，翻译。", target: "zh-CN") == "好的，翻译。")
        #expect(TranslationService.cleanTranslation("请翻译以下幻灯片。", target: "zh-CN") == "请翻译以下幻灯片。")
    }

    @Test func ordinaryTranslationsAreKept() {
        #expect(TranslationService.cleanTranslation("The text is due on Friday.", target: "en-US") == "The text is due on Friday.")
        #expect(TranslationService.cleanTranslation("There are three points:", target: "en-US") == "There are three points:")
        #expect(TranslationService.cleanTranslation("Note the deadline is Tuesday.", target: "en-US") == "Note the deadline is Tuesday.")
        #expect(TranslationService.cleanTranslation("2026", target: "zh-CN") == "2026")
        #expect(TranslationService.cleanTranslation("我们用 API 和 SDK。", target: "zh-CN") == "我们用 API 和 SDK。")
    }

    /// Replies found in stored meetings.
    @Test func remarksFromRecordedMeetings() {
        let note = "好的。\n\n(Note: The subtitle \"Right.\" is a very short affirmation. In a live meeting context, it can be translated in a few ways:\n- 对。\n- 没错。)"
        #expect(TranslationService.cleanTranslation(note, target: "zh-CN") == "好的。")
        #expect(TranslationService.cleanTranslation("The user wants me to translate the subtitle \"Yes.\" from English into Simplified Chinese. The translation is \"是的。\"", target: "zh-CN") == nil)
        #expect(TranslationService.cleanTranslation("请提供需要翻译的字幕内容。", target: "zh-CN") == nil)
        #expect(TranslationService.cleanTranslation("The user wants a translation of \"Yes.\"\nI must output only the translation.</think>\n是的。", target: "zh-CN") == "是的。")
        #expect(TranslationService.cleanTranslation("您似乎忘记提供需要翻译的字幕内容了。请提供具体的英文字幕文本。", target: "zh-CN") == nil)
        let mixed = "The subtitle appears to be a mix of Chinese and garbled English. The Chinese portion translates to:\n\"Only 500 messages today.\""
        #expect(TranslationService.cleanTranslation(mixed, target: "en-US") == "Only 500 messages today.")
    }

    @Test func quotesInsideTheTextStay() {
        let s = "我想到了一个人，他说：“在这个派对上，永远都是晚上十点。”"
        #expect(TranslationService.cleanTranslation(s, target: "zh-CN") == s)
        #expect(TranslationService.cleanTranslation("He said \"no\" and \"never\"", target: "en-US") == "He said \"no\" and \"never\"")
        #expect(TranslationService.cleanTranslation("我们会把字幕翻译成中文。", target: "zh-CN") == "我们会把字幕翻译成中文。")
    }

    @Test func translationInTheWrongScriptIsDropped() {
        #expect(TranslationService.cleanTranslation("We ship on Friday.", target: "zh-CN") == nil)
        #expect(TranslationService.cleanTranslation("我们周五发布。", target: "en-US") == nil)
    }

    // What you say is spoken into the room only as Ming's translation; anything that is not
    // clearly one sends the press to the on-device path instead.
    @MainActor @Test func interpretationNeedsBothLinesAndARealTranslation() {
        let good = TranslationService.parseInterpretation("ORIGINAL: 我们周五发布。\nTRANSLATION: We ship on Friday.", target: "en-US")
        #expect(good?.original == "我们周五发布。")
        #expect(good?.translation == "We ship on Friday.")
        #expect(TranslationService.parseInterpretation("ORIGINAL: 我们周五发布。", target: "en-US") == nil)
        #expect(TranslationService.parseInterpretation("ORIGINAL: 我们周五发布。\nTRANSLATION:", target: "en-US") == nil)
        #expect(TranslationService.parseInterpretation("We ship on Friday.", target: "en-US") == nil)
    }

    @MainActor @Test func interpretationThatRepeatsTheOriginalIsDropped() {
        #expect(TranslationService.parseInterpretation("ORIGINAL: OK.\nTRANSLATION: OK.", target: "zh-CN") == nil)
        #expect(TranslationService.parseInterpretation("ORIGINAL: 我们周五发布。\nTRANSLATION: 我们周五发布。", target: "en-US") == nil)
        #expect(TranslationService.parseInterpretation("ORIGINAL: We ship on Friday.\nTRANSLATION: We ship on Friday", target: "zh-CN") == nil)
    }

    @Test func cloudHearParsesValidThreeLineReply() {
        let reply = """
        LANG: en
        ORIGINAL: We will ship the update on Friday.
        TRANSLATION: 我们周五发布更新。
        """
        let heard = TranslationService.parseHeard(reply, target: "zh-CN", hint: nil, seconds: 2.5)
        #expect(heard == .init(lang: "en", original: "We will ship the update on Friday.", translation: "我们周五发布更新。"))
    }

    @Test func cloudHearDropsSilenceNoiseAndRefusals() {
        #expect(TranslationService.parseHeard("LANG: en\nORIGINAL: NONE\nTRANSLATION: NONE", target: "zh-CN", hint: nil) == nil)
        #expect(TranslationService.parseHeard("LANG: zh-CN\nORIGINAL: （笑声）\nTRANSLATION: (laughter)", target: "en-US", hint: nil) == nil)
        #expect(TranslationService.parseHeard("LANG: en\nORIGINAL: um uh\nTRANSLATION: 嗯", target: "zh-CN", hint: nil) == nil)
        #expect(TranslationService.parseHeard("根据现有检索证据，无法回答该问题。", target: "zh-CN", hint: nil) == nil)
    }

    @Test func cloudHearSameLanguageAndLanguageNormalization() {
        let reply = """
        LANG: Chinese
        ORIGINAL: 我们周五发布。
        TRANSLATION: 我们周五发布。
        """
        let heard = TranslationService.parseHeard(reply, target: "zh-CN", hint: nil, seconds: 1.5)
        #expect(heard?.lang == "zh-CN")
        #expect(heard?.original == "我们周五发布。")
        #expect(heard?.translation == "我们周五发布。")
        #expect(TranslationService.sameLanguage("zh-CN", "zh-Hans"))
        #expect(TranslationService.sameLanguage("en-US", "en"))
        #expect(!TranslationService.sameLanguage("en", "zh-CN"))
    }

    @Test func cloudSegmenterSplitsOnPauseAndCutsLongSpeech() {
        var out: [Segmenter.Segment] = []
        var seg = Segmenter { out.append($0) }
        let silence = [Int16](repeating: 0, count: Segmenter.frameSamples)
        let loud = [Int16](repeating: 3000, count: Segmenter.frameSamples)

        // Pure silence produces nothing.
        for _ in 0..<30 { seg.feed(silence) }
        #expect(out.isEmpty)

        // 10 frames of speech (300 ms) followed by 20 frames of silence (600 ms) emits 1 segment.
        for _ in 0..<10 { seg.feed(loud) }
        for _ in 0..<20 { seg.feed(silence) }
        #expect(out.count == 1)
        #expect(out[0].seconds > 0.25)
        #expect(out[0].wav.count == 44 + out[0].pcm.count * 2)

        // Continuous speech exceeding maxFrames (266) is cut automatically.
        out.removeAll()
        for _ in 0..<270 { seg.feed(loud) }
        #expect(out.count == 1)
        seg.flush()
    }

    @Test func cloudStreamYieldsPiecesThroughRecognitionStreamProtocol() async throws {
        let oldCloud = Recognition.cloud
        defer { Recognition.cloud = oldCloud }
        Recognition.cloud = { _, _, _, _ in
            Recognition.CloudHeard(text: "Hello from cloud stream.", lang: "en", translation: "来自云端流的问候。")
        }
        let stream = CloudStream(locale: "en-US", speaking: false, background: false)
        let buf = AVAudioPCMBuffer(pcmFormat: stream.format, frameCapacity: 4800)!
        buf.frameLength = 4800
        let ch = buf.int16ChannelData![0]
        for i in 0..<4800 { ch[i] = 3000 }
        stream.append(buf)
        await stream.finish()

        var pieces: [Recognition.Piece] = []
        for try await p in stream.results {
            pieces.append(p)
        }
        #expect(pieces.count == 1)
        #expect(pieces[0].text == "Hello from cloud stream.")
        #expect(pieces[0].lang == "en")
        #expect(pieces[0].translation == "来自云端流的问候。")
    }
}
