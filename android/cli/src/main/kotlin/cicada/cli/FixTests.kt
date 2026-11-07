// 改正听错的词: the Mac's CorrectionTests, VocabularyTests and LiveFixesTests (cases from a
// 21-minute meeting recording), and records with fixes read and written as the Mac does.
package cicada.cli

import cicada.*

object FixTests {
    val tests: List<Pair<String, () -> Unit>> = listOf(
        "fixesReadAndWrittenLikeTheMac" to ::recordWithFixes,
        "recordFormatUnchangedWithoutFixes" to ::recordFormatUnchangedWithoutFixes,
        "exportsShowTheFixedText" to ::exportsShowTheFixedText,
        "applyReplacesAndMarks" to ::applyReplacesAndMarks,
        "applyKeepsEarlierMarksWhenLaterFixesShift" to ::applyKeepsEarlierMarks,
        "fixWhoseWordsWentAwayIsSkipped" to ::fixWhoseWordsWentAwayIsSkipped,
    )

    private fun check(ok: Boolean, what: String) { if (!ok) throw AssertionError(what) }
    private fun <T> equal(expected: T, actual: T, what: String) { if (expected != actual) throw AssertionError("$what: expected «$expected», got «$actual»") }

    // MARK: Records

    /// As the Mac writes a line with fixes (JSONEncoder, sorted keys, nil left out).
    val MAC_WITH_FIXES = """
{
  "endedAt" : "2026-11-07T08:24:12Z",
  "hasAudio" : false,
  "id" : "20261107-031639",
  "lines" : [
    {
      "dst" : "I explained Morpho, and Curve.",
      "dstLang" : "en",
      "fixes" : [
        {
          "from" : "莫拉",
          "to" : "Morpho",
          "user" : true
        },
        {
          "ask" : true,
          "from" : "开布特",
          "to" : "Curve"
        },
        {
          "from" : "质压",
          "off" : true,
          "to" : "质押"
        }
      ],
      "id" : "h1-1",
      "speaker" : "them",
      "src" : "解释这个莫拉的，质压和开布特",
      "srcLang" : "zh-CN",
      "t" : 2.5
    },
    {
      "dst" : "Fine.",
      "dstLang" : "en",
      "id" : "h2-2",
      "speaker" : "them",
      "src" : "好的。",
      "srcLang" : "zh-CN",
      "t" : 6
    }
  ],
  "startedAt" : "2026-11-07T08:16:39Z",
  "title" : "会议 11月7日 03:16"
}""".trimStart()

    fun recordWithFixes() {
        val s = Session.read(MAC_WITH_FIXES)!!
        val l = s.lines[0]
        equal(3, l.fixes!!.size, "fixes read")
        equal(LineFix("开布特", "Curve", ask = true), l.fixes!![1], "a waiting fix")
        equal("解释这个莫拉的，质压和开布特", l.src, "src stays what was heard")
        equal("解释这个Morpho的，质压和开布特", l.shown, "shown: applied fixes only")
        equal(null, s.lines[1].fixes, "a line without fixes has none")
        equal(MAC_WITH_FIXES, Json.write(s.toJson()), "written back byte for byte")
        // A copy (what the screens read) keeps them, apart from the record's own.
        val c = l.copy(); c.fixes!![0].off = true
        equal(null, l.fixes!![0].off, "copies are deep")
    }

    fun recordFormatUnchangedWithoutFixes() {
        val line = TranscriptLine(id = "1", src = "a", srcLang = "zh", dstLang = "en")
        check(!Json.write(line.toJson()).contains("fixes"), "no fixes key")
        line.fixes = mutableListOf(LineFix("a", "b"))
        val back = TranscriptLine.from(Json.parseObject(Json.write(line.toJson()))!!)
        equal("b", back.shown, "shown")
        equal("a", back.src, "src")
    }

    fun exportsShowTheFixedText() {
        val s = Session.read(MAC_WITH_FIXES)!!
        check(TranscriptExport.markdown(s).contains("解释这个Morpho的，质压和开布特\n> I explained Morpho, and Curve.\n"), "markdown")
        check(TranscriptExport.srt(s).contains("解释这个Morpho的，质压和开布特\nI explained"), "srt")
    }

    fun applyReplacesAndMarks() {
        val fixes = listOf(LineFix("莫拉", "Morpho"), LineFix("质压", "质押"), LineFix("开布特", "Curve", ask = true), LineFix("ropax", "RoPax", off = true))
        val a = Correction.apply(fixes, "解释这个莫拉的，质压和开布特，ropax")
        equal("解释这个Morpho的，质押和开布特，ropax", a.text, "text")
        equal(listOf("Morpho", "质押"), a.marks.map { a.text.substring(it.first, it.last + 1) }, "marks")
    }

    fun applyKeepsEarlierMarks() {
        val a = Correction.apply(listOf(LineFix("质压", "质押"), LineFix("莫拉", "Morpho")), "莫拉说质压")
        equal("Morpho说质押", a.text, "text")
        equal(listOf("Morpho", "质押"), a.marks.map { a.text.substring(it.first, it.last + 1) }, "marks")
    }

    fun fixWhoseWordsWentAwayIsSkipped() {
        equal("解释这个摩托的", Correction.apply(listOf(LineFix("莫拉", "Morpho")), "解释这个摩托的").text, "skipped")
    }
}
