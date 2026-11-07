package cicada

/// A word the AI service said speech recognition got wrong in a finished line ("莫拉" → "Morpho"),
/// field for field the Mac's LineFix. The line keeps what was heard (`src`) and carries its fixes,
/// so a record moves between the platforms unchanged.
data class LineFix(
    var from: String,
    var to: String,
    /// Waiting for the user (a name sound can't check): not applied until confirmed.
    var ask: Boolean? = null,
    /// The user said no (改回 or 不对): kept so the same line isn't fixed that way again.
    var off: Boolean? = null,
    /// The user's own: said 对, or wrote it (改这句…). A later pass never drops or overrides it.
    var user: Boolean? = null,
) {
    val applied: Boolean get() = ask != true && off != true

    fun toJson(): Map<String, Any?> = mapOf("from" to from, "to" to to, "ask" to ask, "off" to off, "user" to user)

    companion object {
        fun from(o: Map<String, Any?>) = LineFix(o["from"].str() ?: "", o["to"].str() ?: "", o["ask"].bool(), o["off"].bool(), o["user"].bool())
    }
}

/// 改正听错的词 (the Mac's Correction.swift): which of the service's proposed fixes to take, and
/// the line as shown once they are in.
object Correction {
    /// The line as shown: each applied fix replaces its words where they still are. `marks` are
    /// the replaced words (start, end in UTF-16 units), for the dotted underline.
    class Applied(val text: String, val marks: List<IntRange>)

    fun apply(fixes: List<LineFix>, src: String): Applied {
        var text = src
        val spans = mutableListOf<Pair<String, Int>>()   // replacement and its offset, kept valid as text changes
        // The user's own last: written against the line as it was shown, other fixes in.
        val ordered = fixes.filter { it.user != true } + fixes.filter { it.user == true }
        for (f in ordered) {
            if (!f.applied || f.from.isEmpty()) continue
            val start = text.indexOf(f.from)
            if (start < 0) continue
            val delta = f.to.length - f.from.length
            for (k in spans.indices) if (spans[k].second > start) spans[k] = spans[k].first to spans[k].second + delta
            text = text.substring(0, start) + f.to + text.substring(start + f.from.length)
            spans.add(f.to to start)
        }
        val marks = spans.filter { (w, o) -> o + w.length <= text.length && w.isNotEmpty() }
            .map { (w, o) -> o until o + w.length }.sortedBy { it.first }
        return Applied(text, marks)
    }
}
