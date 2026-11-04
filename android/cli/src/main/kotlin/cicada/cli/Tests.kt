// Unit tests for the engines: `scripts/test.sh` (cicada-cli test). The Windows suite's cases, plus
// byte-for-byte checks of the Mac's JSON format. A failed check throws and the runner reports it.
// No network: LingClient runs against a fake transport.
package cicada.cli

import cicada.*
import java.io.File
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

object Tests {
    fun run(): Int {
        val home = File(System.getProperty("java.io.tmpdir"), "cicada-tests-${ProcessHandle.current().pid()}")
        Paths.root = home
        Paths.log = File(home, "debug.log")
        home.mkdirs()
        val tests: List<Pair<String, () -> Unit>> = listOf(
            "sessionJsonMatchesTheMac" to ::sessionJsonMatchesTheMac,
            "readsAMacRecordAndWritesItBackByteForByte" to ::readsAMacRecord,
            "jsonEdgeCases" to ::jsonEdgeCases,
            "storeSavesAndDropsEmptyMeetings" to ::storeSavesAndDropsEmptyMeetings,
            "closesInterruptedMeetings" to ::closesInterruptedMeetings,
            "displayTitle" to ::displayTitle,
            "parsesMingReplies" to ::parsesMingReplies,
            "normalizesLanguages" to ::normalizesLanguages,
            "cleansTranslations" to ::cleansTranslations,
            "joinsCutSentences" to ::joinsCutSentences,
            "segmentsOnPauses" to ::segmentsOnPauses,
            "cutsLongSpeechAtItsQuietestMoment" to ::cutsLongSpeech,
            "ignoresClicks" to ::ignoresClicks,
            "wavRoundTrip" to ::wavRoundTrip,
            "parsesNotes" to ::parsesNotes,
            "keepsEarliestTimes" to ::keepsEarliestTimes,
            "notesPromptIsTheMacs" to ::notesPromptIsTheMacs,
            "loadsTheMacsTranslations" to ::loadsTheMacsTranslations,
            "keyFileIsPrivate" to ::keyFileIsPrivate,
            "lingRequestShape" to ::lingRequestShape,
            "lingDropsHijackedAndRefusedReplies" to ::lingDropsHijacked,
            "lingRetriesAudioOnceWhenBusy" to ::lingRetriesAudioOnce,
            "lingMarksABadKey" to ::lingMarksABadKey,
            "lingGateSpacesStartsAndServesPriorityFirst" to ::lingGate,
            "listenEngineEndToEndWithAFakeMing" to ::listenEndToEnd,
        )
        var passed = 0; var failed = 0
        for ((name, test) in tests) {
            try { test(); passed++ } catch (e: Throwable) { failed++; println("FAIL $name: ${e.message ?: e.javaClass.simpleName}") }
        }
        home.deleteRecursively()
        println("$passed passed, $failed failed")
        return if (failed == 0) 0 else 1
    }

    private fun check(ok: Boolean, what: String) { if (!ok) throw AssertionError(what) }
    private fun <T> equal(expected: T, actual: T, what: String) { if (expected != actual) throw AssertionError("$what: expected «$expected», got «$actual»") }

    // MARK: Records

    fun sessionJsonMatchesTheMac() {
        val s = Session(id = "20261103-101611", title = "会议 11月3日 10:16", startedAt = Instant.parse("2026-11-03T15:16:11Z"),
                        lines = mutableListOf(TranscriptLine(id = "h1-1", t = 2.7636849899291995, src = "你好/世界", srcLang = "zh-CN", dstLang = "en")))
        val json = Json.write(s.toJson())
        check(json.contains("\"startedAt\" : \"2026-11-03T15:16:11Z\""), "dates are whole-second ISO-8601 UTC")
        check(json.contains("你好\\/世界"), "Chinese as it is, slashes escaped like JSONEncoder")
        check(!json.contains("\"dst\""), "nil optionals are left out")
        check(!json.contains("endedAt") && !json.contains("notes"), "absent fields stay absent")
        check(json.contains("2.7636849899291995"), "doubles keep full precision")
        check(json.startsWith("{\n  \"hasAudio\" : false,\n  \"id\" : "), "sorted keys, Swift's spacing")
    }

    private val MAC = """
{
  "endedAt" : "2026-11-02T15:24:12Z",
  "hasAudio" : true,
  "id" : "20261102-101639",
  "lines" : [
    {
      "dst" : "Hello \/ \"hi\"",
      "dstLang" : "en",
      "id" : "h1-1",
      "speaker" : "them",
      "src" : "你好",
      "srcLang" : "zh-CN",
      "t" : 2.5,
      "voice" : 1
    }
  ],
  "notes" : {
    "conclusions" : [

    ],
    "covered" : 1,
    "final" : true,
    "summary" : "总结",
    "terms" : [
      {
        "heard" : [

        ],
        "name" : "鸟哥",
        "note" : "分享者"
      }
    ],
    "title" : "标题",
    "todos" : [
      {
        "owner" : "你",
        "support" : 3,
        "t" : 202.4,
        "text" : "记录"
      }
    ],
    "topics" : [
      {
        "pointTimes" : [
          12.4,
          null
        ],
        "points" : [
          "a",
          "b"
        ],
        "start" : 0,
        "summary" : "s",
        "title" : "t"
      }
    ],
    "updatedAt" : "2026-11-02T15:24:40Z"
  },
  "startedAt" : "2026-11-02T15:16:39Z",
  "title" : "会议 11月2日 10:16",
  "voiceNames" : {
    "1" : "Emma"
  }
}""".trimStart()

    fun readsAMacRecord() {
        val s = Session.read(MAC)!!
        equal(1, s.lines.size, "lines")
        equal(1, s.lines[0].voice, "voice")
        equal("Hello / \"hi\"", s.lines[0].dst, "escapes read")
        equal("Emma", s.voiceNames!!["1"], "voice names")
        equal(12.4, s.notes!!.topics[0].pointTime(0), "point time")
        equal(null, s.notes!!.topics[0].pointTime(1), "missing point time")
        equal(MAC, Json.write(s.toJson()), "written back byte for byte")
    }

    fun jsonEdgeCases() {
        equal("3", Json.number(3.0), "whole doubles without .0")
        equal("0.0001", Json.number(0.0001), "small doubles without an exponent")
        equal("-1.5", Json.number(-1.5), "negative")
        val parsed = Json.parse("""{"a":[1,2.5,"x中\n",true,null,{}],"b":-3e2}""").obj()!!
        equal(2.5, parsed["a"].arr()[1], "double")
        equal(1L, parsed["a"].arr()[0], "integer")
        equal("x中\n", parsed["a"].arr()[2], "unicode and newline escapes")
        equal(-300.0, parsed["b"], "exponent")
        equal("{\"a\":[1,2.5,\"x中\\n\",true,null,{}],\"b\":-300}", Json.write(parsed, pretty = false), "compact")
        check(try { Json.parse("{\"a\":1,}"); false } catch (_: Json.ParseException) { true }, "trailing comma rejected")
        equal(null, Json.parseObject("not json"), "garbage")
    }

    fun storeSavesAndDropsEmptyMeetings() {
        val store = SessionStore()
        val empty = store.begin(Instant.parse("2026-01-01T01:00:00Z"))
        store.end(empty.id)
        check(store.get(empty.id) == null && !File(Paths.sessions, empty.id).exists(), "an empty meeting is removed")
        val s = store.begin(Instant.parse("2026-01-01T02:00:00Z"))
        store.append(s.id, TranscriptLine(id = "h1-1", src = "hi", srcLang = "en", dstLang = "zh-CN"))
        store.end(s.id)
        val file = File(Paths.sessions, "${s.id}/session.json")
        check(file.isFile, "record written on end")
        equal(1, Session.read(file.readText())!!.lines.size, "line saved")
        check(SessionStore().get(s.id) != null, "loaded again")
        check(s.title.startsWith("会议 "), "default title is the Mac's Chinese form")
        val md = SessionStore.markdown(store.get(s.id)!!)
        check(md.contains("## 文字记录") && md.contains("hi"), "markdown export")
    }

    fun closesInterruptedMeetings() {
        val s = Session(id = "20260102-030405", title = "会议 1月2日 03:04", startedAt = Instant.parse("2026-01-02T03:04:05Z"),
                        lines = mutableListOf(TranscriptLine(id = "h1-1", t = 12.0, src = "hi", srcLang = "en", dstLang = "zh-CN")))
        File(Paths.sessions, s.id).mkdirs()
        File(Paths.sessions, "${s.id}/session.json").writeText(Json.write(s.toJson()))
        val loaded = SessionStore().get(s.id)!!
        equal(Instant.parse("2026-01-02T03:04:22Z"), loaded.endedAt, "ends 5 s after its last line")
        check(File(Paths.sessions, "${s.id}/session.json").readText().contains("\"endedAt\""), "saved")
    }

    fun displayTitle() {
        val s = Session(title = "会议 1月1日 10:00", startedAt = Instant.now(), notes = MeetingNotes(title = "路线评审", summary = "x"))
        check(SessionStore.displayTitle(s).endsWith(" 路线评审"), "notes' name after the date")
        s.renamed = true; s.title = "我的会"
        equal("我的会", SessionStore.displayTitle(s), "the user's title wins")
    }

    // MARK: Hearing

    fun parsesMingReplies() {
        val h = Translator.parseHeard("LANG: en\nORIGINAL: Hello there.\nTRANSLATION: 你好。", "zh-CN", null)!!
        equal("en", h.lang, "lang"); equal("Hello there.", h.original, "original"); equal("你好。", h.translation, "translation")
        equal(null, Translator.parseHeard("作为一个人工智能语言模型，这个问题超出我目前的学习范围了", "zh-CN", null), "no labelled lines")
        equal(null, Translator.parseHeard("LANG: en\nORIGINAL: NONE\nTRANSLATION: 无", "zh-CN", null), "no speech")
        equal(null, Translator.parseHeard("LANG: en\nORIGINAL: ...\nTRANSLATION: …", "zh-CN", null), "punctuation only")
        val same = Translator.parseHeard("LANG: zh\nORIGINAL: 好的\nTRANSLATION: OK", "zh-CN", "en")!!
        equal("zh-CN", same.lang, "zh normalized"); equal("好的", same.translation, "already in the target: kept as is")
        val wrong = Translator.parseHeard("LANG: en\nORIGINAL: Hi\nTRANSLATION: Hi again", "zh-CN", null)!!
        equal(null, wrong.translation, "a translation not in Chinese is dropped for the text translator")
        equal("ja", Translator.parseHeard("lang: ja-JP\noriginal: はい\ntranslation: 是", "zh-CN", null)!!.lang, "labels in any case")
    }

    fun normalizesLanguages() {
        equal("zh-CN", Languages.normalize("zh-Hans", "en"), "zh-Hans")
        equal("zh-TW", Languages.normalize("zh-TW", "en"), "zh-TW")
        equal("zh-CN", Languages.normalize("cmn", "en"), "cmn")
        equal("en", Languages.normalize("en-US", "ja"), "en-US")
        equal("ja", Languages.normalize("", "ja"), "empty falls back")
        equal("zh-TW", Languages.fromSystem("zh-Hant-HK"), "system zh-Hant")
        equal("zh-CN", Languages.fromSystem("zh-CN"), "system zh-CN")
        equal("en", Languages.fromSystem("en-GB"), "system en")
        equal("Simplified Chinese", Languages.englishName("zh-CN"), "english name")
        equal("Japanese", Languages.englishName("ja"), "english name ja")
        equal("01:05", Languages.clock(65.9), "clock"); equal("1:00:01", Languages.clock(3601.0), "clock hours")
    }

    fun cleansTranslations() {
        equal("你好", Translator.cleanTranslation("Translation: 你好", "zh-CN"), "label stripped")
        equal("你好", Translator.cleanTranslation("“你好”", "zh-CN"), "wrapping quotes")
        equal("Hello", Translator.cleanTranslation("Here is the translation:\nHello", "en"), "remark line dropped")
        equal(null, Translator.cleanTranslation("请提供需要翻译的字幕内容", "en"), "a request for input is not a translation")
        equal(null, Translator.cleanTranslation("Hello", "zh-CN"), "wrong script")
        equal("Done.", Translator.cleanTranslation("<think>x</think>Done.", "en"), "leaked reasoning")
    }

    fun joinsCutSentences() {
        val last = TranscriptLine(src = "We finished the migration and", srcLang = "en")
        check(ListenEngine.continues(last, 0.2, Heard("en", "the error rate dropped.", null)), "mid-sentence cut joins")
        check(!ListenEngine.continues(last, 1.5, Heard("en", "next", null)), "a long gap doesn't")
        check(!ListenEngine.continues(TranscriptLine(src = "Done.", srcLang = "en"), 0.1, Heard("en", "Next", null)), "after a full stop doesn't")
        check(!ListenEngine.continues(last, 0.1, Heard("ja", "はい", null)), "another language doesn't")
        equal("我们完成了迁移", ListenEngine.join("我们完成了", "迁移", "zh-CN"), "CJK joins without a space")
        equal("a b", ListenEngine.join("a ", " b", "en"), "others with one space")
    }

    // MARK: Segmenter

    private fun tone(seconds: Double, amp: Double = 0.3) = ShortArray((seconds * 16000).toInt()) { (sin(2 * PI * 300 * it / 16000) * amp * 32767).toInt().toShort() }
    private fun silence(seconds: Double) = ShortArray((seconds * 16000).toInt())
    private fun concat(vararg parts: ShortArray): ShortArray = parts.fold(ShortArray(0)) { a, b -> a + b }

    private fun cut(vararg parts: ShortArray): List<Segment> {
        val list = mutableListOf<Segment>()
        val seg = Segmenter().apply { onSegment = { list.add(it) } }
        for (p in parts) { var i = 0; while (i < p.size) { seg.feed(p.copyOfRange(i, minOf(p.size, i + 1600))); i += 1600 } }
        seg.flush()
        return list
    }

    fun segmentsOnPauses() {
        val list = cut(silence(0.5), tone(2.0), silence(1.0), tone(1.5), silence(1.0))
        equal(2, list.size, "two stretches")
        check(abs(list[0].start - 0.35) < 0.05, "starts just before the speech (pre-roll), got ${list[0].start}")
        check(abs(list[1].start - 3.35) < 0.05, "second start, got ${list[1].start}")
        check(list[0].seconds in 2.1..2.4, "length with lead-in and tail, got ${list[0].seconds}")
    }

    fun cutsLongSpeech() {
        // 7 s of speech, a 0.3 s dip (shorter than a pause), 4 s more: one cut, at the dip.
        val list = cut(tone(7.0), tone(0.3, 0.004), tone(4.0), silence(1.0))
        equal(2, list.size, "split in two")
        check(list[0].seconds in 6.9..7.4, "cut inside the dip, got ${list[0].seconds}")
        check(list.all { it.seconds <= 8.0 }, "no segment over 8 s")
        check(abs(list[1].start - (list[0].start + list[0].seconds)) < 0.001, "the rest carries on without a gap")
    }

    fun ignoresClicks() {
        equal(0, cut(silence(1.0), tone(0.1), silence(1.0)).size, "under 0.25 s of sound is not speech")
        equal(0, cut(tone(3.0, 0.002)).size, "below the gate is silence")
    }

    fun wavRoundTrip() {
        val pcm = tone(0.5)
        check(Wav.read(Wav.bytes(pcm).inputStream()).contentEquals(pcm), "16 kHz mono reads back exactly")
        equal(16000, Wav.resample(DoubleArray(48000), 48000).size, "48 kHz to 16 kHz")
    }

    // MARK: Notes

    fun parsesNotes() {
        val reply = """
        ```json
        {"title": "“发布评审”", "summary": "讨论发布。",
         "topics": [{"start": 0, "title": "进展", "summary": "一句", "points": [{"text": "迁移完成", "evidence": ["L2"]}, "旧格式要点", {"text": "", "evidence": []}],
                     "fishbone": {"question": "为何延期", "branches": [{"label": "测试", "detail": "x", "t": 3, "evidence": ["L1"]}, {"label": "设计", "detail": "y", "evidence": ["L9"]}]}}],
         "conclusions": [{"text": "周五上线", "evidence": ["L1", "L2", "L99"]}],
         "todos": [{"text": "发说明", "owner": "", "evidence": ["L2"]}],
         "terms": [{"name": "Stripe", "note": "支付", "heard": ["Stripe", "Strip"]}]}
        ```
        """
        val n = NotesEngine.parse(reply, listOf(1.0, 5.0), 0.0)!!
        equal("发布评审", n.title, "title quotes trimmed")
        equal(2, n.topics[0].points.size, "empty points dropped, plain strings kept")
        equal(5.0, n.topics[0].pointTime(0), "point time from evidence")
        equal(null, n.topics[0].pointTime(1), "no evidence, no time")
        equal(2, n.topics[0].fishbone!!.branches.size, "fishbone kept")
        equal(0, n.topics[0].fishbone!!.branches[1].support, "evidence beyond the transcript doesn't count")
        equal(2, n.conclusions[0].support, "support counts real lines")
        equal(null, n.todos[0].owner, "empty owner is none")
        equal("Strip", n.terms[0].heard.joinToString(","), "the correct spelling isn't a mishearing")
        equal(null, NotesEngine.parse("not json", emptyList(), 0.0), "garbage")
        equal(null, NotesEngine.parse("{}", emptyList(), 0.0), "empty notes")
    }

    fun keepsEarliestTimes() {
        val old = MeetingNotes(topics = mutableListOf(NoteTopic(title = "t", points = mutableListOf("a"), pointTimes = mutableListOf(3.0))),
                               todos = mutableListOf(NoteItem(text = "x", t = 2.0)))
        val next = MeetingNotes(topics = mutableListOf(NoteTopic(title = "t", points = mutableListOf("a", "b"), pointTimes = mutableListOf(9.0, null))),
                                todos = mutableListOf(NoteItem(text = "x", t = 8.0)))
        NotesEngine.carryTimes(old, next)
        equal(3.0, next.topics[0].pointTime(0), "a point keeps when it was first heard")
        equal(2.0, next.todos[0].t, "to-dos too")
    }

    fun notesPromptIsTheMacs() {
        val lines = listOf(TranscriptLine(t = 1.0, src = "你好", speaker = "them"), TranscriptLine(t = 65.0, src = "我来说", speaker = "me"))
        val p = NotesEngine.prompt(MeetingNotes(), lines, 0, "Simplified Chinese", final = false)
        check(p.startsWith("You keep notes for a meeting that is still going on. Update them with the new lines.\nWrite the notes in Simplified Chinese. Return JSON only.\n"), "opening")
        check(p.contains("[L1 00:01 对方] 你好\n[L2 01:05 你] 我来说"), "transcript lines")
        check(p.contains("These are the first lines: make one topic."), "first update")
        check(p.endsWith("No markdown, no text outside the JSON."), "ending")
        val f = NotesEngine.prompt(MeetingNotes(), lines, 0, "English", final = true)
        check(f.contains("This meeting ran 01:04: use at most 1 topic."), "final topic limit")
        check(NotesEngine.written(MeetingNotes(summary = "讨论发布 Stripe"), "Simplified Chinese"), "Chinese notes")
        check(!NotesEngine.written(MeetingNotes(summary = "We talked"), "Simplified Chinese"), "English isn't Chinese")
    }

    // MARK: Strings

    fun loadsTheMacsTranslations() {
        loadStrings("en")
        equal("Live notes", Strings.L("实时纪要"), "an English string")
        equal("没有这条", Strings.L("没有这条"), "missing keys show the Chinese")
        loadStrings("zh-Hans")
        equal("实时纪要", Strings.L("实时纪要"), "Chinese is the key")
        val t = Strings.parse("/* c */\n\"a \\\"b\\\"\" = \"x\\ny\";\n// line\n\"%@ 分钟\" = \"%@ min\";")
        equal("x\ny", t["a \"b\""], "escapes")
        equal("%@ min", t["%@ 分钟"], "placeholders kept")
        equal("3 分钟", Strings.LF("%@ 分钟", 3), "LF fills %@")
    }

    fun keyFileIsPrivate() {
        val key = AIKey(PlainProtector)
        check(key.save("sk-test-0000000000"), "saved")
        val mode = java.nio.file.Files.getPosixFilePermissions(Paths.keyFile.toPath())
        equal("rw-------", java.nio.file.attribute.PosixFilePermissions.toString(mode), "0600")
        check(!Paths.settings.exists() || !Paths.settings.readText().contains("sk-"), "never in settings")
        equal("sk-••••••••••••0000", AIKey.masked("sk-test-0000000000"), "masked")
    }

    // MARK: Ling

    private class Fake(val respond: (String) -> Transport.Response) : Transport {
        val calls = mutableListOf<Pair<Long, String>>()
        override fun send(url: String, method: String, body: String?, headers: Map<String, String>, timeoutMs: Int): Transport.Response {
            synchronized(calls) { calls.add(System.currentTimeMillis() to (body ?: "")) }
            return respond(body ?: "")
        }
    }

    private fun reply(content: String, finish: String? = "stop") = Transport.Response(200, Json.write(mapOf(
        "choices" to listOf(mapOf("message" to mapOf("content" to content), "finish_reason" to finish)),
        "usage" to mapOf("prompt_tokens" to 1, "completion_tokens" to 1),
    ), pretty = false))

    private fun client(fake: Fake): LingClient {
        val key = AIKey(PlainProtector)
        key.save("sk-test-0000000000")
        return LingClient(key, fake)
    }

    private fun content(body: String, i: Int) = Json.parse(body).obj()!!["messages"].arr()[i].obj()!!["content"]

    fun lingRequestShape() {
        val fake = Fake { reply("ok") }
        client(fake).chat("the content", "Translate.", Priority.Translate, model = LingClient.AUDIO_MODEL, audio = byteArrayOf(1, 2, 3))
        val body = Json.parse(fake.calls[0].second).obj()!!
        equal("disabled", body["thinking"].obj()!!["type"], "thinking disabled")
        equal("system", body["messages"].arr()[0].obj()!!["role"], "content in the system message")
        equal("the content", content(fake.calls[0].second, 0), "content")
        val user = content(fake.calls[0].second, 1).arr()
        equal("audio_url", user[0].obj()!!["type"], "audio first")
        equal("data:audio/wav;base64,AQID", user[0].obj()!!["audio_url"].obj()!!["url"], "WAV as a data URL")
        equal("Translate.", user[1].obj()!!["text"], "fixed instruction last")
        client(fake).chat("c", "i", Priority.Translate, model = LingClient.AUDIO_MODEL, audio = byteArrayOf(1, 2, 3), audioType = "audio/aac")
        equal("data:audio/aac;base64,AQID", content(fake.calls[1].second, 1).arr()[0].obj()!!["audio_url"].obj()!!["url"], "AAC keeps its type")
    }

    fun lingDropsHijacked() {
        for ((r, finish) in listOf("根据现有检索证据，……" to "stop", "作为一个人工智能语言模型，这个问题超出……" to "stop", "fine" to null)) {
            val ling = client(Fake { reply(r, finish) })
            try { ling.chat("c", "i", Priority.Translate); throw AssertionError("accepted «$r»") }
            catch (e: LingException) { equal(LingException.Kind.Hijacked, e.kind, "dropped as hijacked") }
        }
    }

    fun lingRetriesAudioOnce() {
        val calls = AtomicInteger()
        val ling = client(Fake { if (calls.incrementAndGet() == 1) Transport.Response(429, "") else reply("LANG: en\nORIGINAL: Hi.\nTRANSLATION: 嗨。") })
        val r = ling.chat("c", "i", Priority.Translate, model = LingClient.AUDIO_MODEL, audio = byteArrayOf(1))
        check(r.contains("ORIGINAL: Hi."), "second attempt answered")
        equal(2, calls.get(), "one retry")
        val text = client(Fake { Transport.Response(429, "") })
        try { text.chat("c", "i", Priority.Translate); throw AssertionError("text translation retried") }
        catch (e: LingException) { equal(LingException.Kind.RateLimited, e.kind, "text fails fast") }
    }

    fun lingMarksABadKey() {
        val ling = client(Fake { Transport.Response(401, "") })
        try { ling.chat("c", "i", Priority.Translate) } catch (e: LingException) { equal(LingException.Kind.InvalidKey, e.kind, "401") }
        equal(KeyState.Invalid, ling.keyState, "key state")
        check(!ling.usable, "no longer usable")
    }

    fun lingGate() {
        val old = LingClient.spacing
        LingClient.spacing = 0.2
        try {
            val fake = Fake { reply("ok") }
            val ling = client(fake)
            val a = thread { ling.chat("first", "i", Priority.Notes) }
            Thread.sleep(20)
            // Queued while the gate is closed: the translation goes before the earlier notes call.
            val b = thread { ling.chat("notes", "i", Priority.Notes) }
            Thread.sleep(20)
            val c = thread { ling.chat("translate", "i", Priority.Translate) }
            a.join(); b.join(); c.join()
            val order = fake.calls.map { content(it.second, 0) }
            equal("first,translate,notes", order.joinToString(","), "priority order")
            for (i in 1 until fake.calls.size) check(fake.calls[i].first - fake.calls[i - 1].first >= 180, "starts spaced")
        } finally { LingClient.spacing = old }
    }

    fun listenEndToEnd() {
        // Two stretches of "speech", told apart by length (1 s, then 1.6 s); the fake Ming answers
        // the first one slower, and lines still come out in order.
        val fake = Fake { body ->
            if (body.contains("Ming-3.0-audio-flash")) {
                val url = content(body, 1).arr()[0].obj()!!["audio_url"].obj()!!["url"] as String
                val first = url.length < 60_000
                if (first) Thread.sleep(400)
                reply(if (first) "LANG: en\nORIGINAL: First one.\nTRANSLATION: 第一句。" else "LANG: en\nORIGINAL: Second one.\nTRANSLATION: 第二句。")
            } else reply("{}")
        }
        val old = LingClient.spacing
        LingClient.spacing = 0.05
        try {
            val ling = client(fake)
            val store = SessionStore()
            val notes = NotesEngine(ling, store)
            val engine = ListenEngine(ling, Translator(ling), store, notes, AppSettings(target = "zh-CN"))
            val src = PcmAudioSource({ concat(tone(1.0), silence(1.0), tone(1.6), silence(1.0)) }, speed = 0.0)
            val ended = CountDownLatch(1)
            src.onEnded = { ended.countDown() }
            engine.start(src, "file")
            ended.await()
            Thread.sleep(100)
            engine.stop()
            val s = store.get(engine.sessionId!!)!!
            equal("First one.|Second one.", s.lines.joinToString("|") { it.src }, "in segment order")
            equal("第一句。", s.lines[0].dst, "translation from the same call")
            equal("h1-1", s.lines[0].id, "Mac-style ids")
            check(s.endedAt != null, "ended")
        } finally { LingClient.spacing = old }
    }

}
