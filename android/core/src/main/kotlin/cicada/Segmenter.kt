package cicada

/// A stretch of speech to send to Ming: where it starts (seconds since listening began) and its
/// 16 kHz mono samples.
class Segment(val index: Int, val start: Double, val samples: ShortArray) {
    val seconds get() = samples.size / Segmenter.RATE.toDouble()
}

/// Cuts the audio into stretches of speech by loudness alone: a pause of 0.6 s ends one, and one
/// that runs to 8 s is cut at its quietest moment in the last 2 s, so a word is split as rarely as
/// possible (Ming has no word timings to put it back together). Not thread-safe: fed from the
/// listening worker only. Same numbers as the Windows Segmenter. (A meeting's first stretch was once
/// cut at 4 s to show a line sooner: Ming then finished the cut sentence by itself, and the rest
/// came back as a second, duplicate line.)
class Segmenter {
    companion object {
        const val RATE = 16000
        private const val FRAME = 480 // 30 ms
        private const val STEP = 160 // 10 ms: a key click is judged in these, as the Mac's VoiceActivity does
        private const val ONSET = 3 // steps of sound before it counts as speech
        @Volatile var threshold = 0.01 // the Mac AudioRouter's gate (about -40 dBFS)
        @Volatile var pause = 0.6
        @Volatile var maxLength = 8.0
        @Volatile var minSpeech = 0.25
        @Volatile var minWord = 0.2 // a word on its own (isWord): this much over gate / 4
        @Volatile var steady = 2.0 // frames' 90th / 10th percentile below this: not speech…
        @Volatile var dips = 2.5 // …unless the median is this far over the 10th, quiet ones held at gate / 8
        @Volatile var short = 2.0 // a sound up to this long, with real quiet (gate / 4) on both sides…
        @Volatile var swell = Math.pow(10.0, 10 / 20.0) // …that swells and fades by 10 dB is a word: see isWord
        private const val PRE_ROLL = 0.15
        private const val TAIL = 0.15
        private const val CUT_WINDOW = 2.0
        @Volatile var above = 0.25 // under this share of its loud frames' energy over 100 Hz: rumble, not speech
        // A first-order high-pass at 100 Hz, for how much of a sound is above it (isRumble).
        private val HIGH_PASS = 1.0 / (1.0 + 2.0 * Math.PI * 100.0 / RATE)
    }

    private val pending = ShortList()            // samples not yet a whole frame
    private val current = ShortList()            // the open segment
    private val levels = ArrayList<Double>()     // per frame of `current`
    private val highs = ArrayList<Double>()      // per frame of `current`: its level over 100 Hz
    private val speech = ArrayList<Boolean>()    // per frame of `current`: whether it held speech (isSpeech)
    private var sounding = 0                     // 10 ms steps of sound in a row so far
    private var carried = false                  // the sound that made the last frame speech began in the frame before
    private var hx = 0.0                         // the high-pass's last input and output, carried from frame to frame
    private var hy = 0.0
    private val before = ArrayDeque<Triple<ShortArray, Double, Double>>() // recent quiet frames and their levels, for the pre-roll
    private val idle = ArrayDeque<Double>()      // levels of the last 0.6 s of quiet frames
    private var lead: Double? = null             // the quietest of those when the open segment began
    private var consumed = 0L                    // samples seen, for timestamps
    private var currentStart = 0.0
    private var quietFrames = 0
    private var loudFrames = 0
    private var index = 0

    var onSegment: ((Segment) -> Unit)? = null

    fun feed(samples: ShortArray) {
        pending.addAll(samples, 0, samples.size)
        val whole = pending.size / FRAME * FRAME
        var i = 0
        while (i < whole) { step(pending.slice(i, i + FRAME)); i += FRAME }
        pending.removeFirst(whole)
    }

    /// Ends the open segment (listening stopped).
    fun flush() {
        if (current.size > 0) close(current.size - quietFrames * FRAME + (TAIL * RATE).toInt())
    }

    /// Whether the frame holds speech: sound that has lasted 30 ms, judged in 10 ms steps against the
    /// line, so a lone key click (a few ms) neither opens a segment nor breaks the pause that ends one
    /// (VoiceActivity.swift's onset); the pre-roll then reaches back to where that sound began.
    private fun isSpeech(frame: ShortArray): Boolean {
        val line = threshold
        var said = false
        var early = sounding > 0
        var i = 0
        while (i < frame.size) {
            val end = minOf(frame.size, i + STEP)
            var sum = 0.0
            for (k in i until end) sum += frame[k].toDouble() * frame[k]
            if (Math.sqrt(sum / (end - i)) / 32768 >= line) {
                if (++sounding >= ONSET && !said) { said = true; carried = early }
            } else { sounding = 0; early = false }
            i = end
        }
        return said
    }

    private fun step(frame: ShortArray) {
        val level = Wav.rms(frame)
        val high = high(frame)
        val loud = isSpeech(frame)
        val now = consumed / RATE.toDouble()
        consumed += frame.size

        if (current.size == 0) {
            if (!loud) {
                idle.addLast(level)
                while (idle.size > (pause * RATE / FRAME).toInt()) idle.removeFirst()
                before.addLast(Triple(frame, level, high))
                while (before.size > PRE_ROLL * RATE / FRAME + 1) before.removeFirst()
                return
            }
            // One frame more when the sound began in the last quiet one.
            while (before.size > PRE_ROLL * RATE / FRAME + (if (carried) 1 else 0)) before.removeFirst()
            currentStart = now - before.size * FRAME / RATE.toDouble()
            lead = idle.minOrNull()
            idle.clear()
            for ((f, l, h) in before) { current.addAll(f, 0, f.size); levels.add(l); highs.add(h); speech.add(false) }
            before.clear()
            quietFrames = 0; loudFrames = 0
        }

        current.addAll(frame, 0, frame.size)
        levels.add(level)
        highs.add(high)
        speech.add(loud)
        if (loud) { quietFrames = 0; loudFrames++ } else quietFrames++

        if (quietFrames * FRAME >= pause * RATE) {
            close(current.size - quietFrames * FRAME + (TAIL * RATE).toInt())
        } else if (current.size >= maxLength * RATE) {
            // The quietest frame in the last 2 s; the rest starts the next segment.
            val from = maxOf(1, levels.size - (CUT_WINDOW * RATE / FRAME).toInt())
            var cut = from
            for (i in from until levels.size) if (levels[i] < levels[cut]) cut = i
            close(cut * FRAME)
        }
    }

    /// Steady sound just over the gate (a fan, hum, hiss) isn't speech: its frames barely vary
    /// (90th / 10th percentile about 1.1; speech, even over such a floor, 3 and up). Given one, Ming
    /// writes a stock sentence in the hint's language ("I'm going to show you a couple of things").
    /// Speech buried under steady noise goes too; system audio rarely carries it. Every frame from
    /// the first loud one to the last counts, the quiet ones held at the gate: counting only the
    /// loud ones dropped quiet speech (under about -30 dBFS), whose dips fall below the gate.
    /// A voice so quiet that its loudest frames barely clear the gate (about -38 dBFS: 6 of 6 lines
    /// lost in testing) still pauses between syllables, its quietest tenth of frames far under its
    /// median (8 dB and more); noise near the gate stays within about 6 dB of its median. So a flat
    /// top is steady only when it has no such dips, measured with quiet frames held at gate / 8.
    /// Very low rumble (brown noise with almost nothing over 20 Hz) can look like that and gets
    /// through more often than before (about 1 in 3 segments, was 1 in 5); what Ming makes of it
    /// still meets the hear filter (Translator.isNoise).
    internal fun isSteady(frameLevels: List<Double>): Boolean {
        val first = frameLevels.indexOfFirst { it >= threshold }
        val last = frameLevels.indexOfLast { it >= threshold }
        if (first < 0 || last <= first) return false
        val body = frameLevels.subList(first, last + 1)
        val top = body.map { maxOf(it, threshold) }.sorted()
        if (top[(0.9 * (top.size - 1)).toInt()] >= steady * top[(0.1 * (top.size - 1)).toInt()]) return false
        val low = body.map { maxOf(it, threshold / 8) }.sorted()
        return low[(0.5 * (low.size - 1)).toInt()] < dips * low[(0.1 * (low.size - 1)).toInt()]
    }

    /// A short word on its own: a sound up to `short` that rises out of real quiet and falls back
    /// into it (under gate / 4, about -52 dBFS, in the 0.6 s before it and in the pause after), and
    /// that swells and fades by 10 dB or more (90th / 10th percentile of its frames over gate / 4).
    /// Such a word ("Thanks.", "Good morning everyone,") is one smooth syllable or a run of voiced
    /// ones, so the steady test, which looks for dips inside, dropped it even at -26 dBFS; and a
    /// quiet one ("Thanks." at -36 dBFS) has under 0.25 s over the gate, so it needs `minWord` over
    /// gate / 4 instead (a knock with a 150 ms tail has 0.15 s). A fan, hum or hiss is there on
    /// both sides; a short burst of one in silence stays within about 9 dB (brown noise), 5 dB (the
    /// rest), and Ming makes up a sentence for a hum or fan burst. Not for a forced cut, whose end
    /// isn't a pause.
    internal fun isWord(frameLevels: List<Double>): Boolean {
        val first = frameLevels.indexOfFirst { it >= threshold }
        val last = frameLevels.indexOfLast { it >= threshold }
        if (first < 0 || (last - first + 1) * FRAME > short * RATE) return false
        val quiet = threshold / 4
        val q = lead ?: return false
        if (q > quiet || last + 1 >= frameLevels.size || frameLevels.subList(last + 1, frameLevels.size).minOrNull()!! > quiet) return false
        val from = frameLevels.indexOfFirst { it >= quiet }
        val to = frameLevels.indexOfLast { it >= quiet }
        val body = frameLevels.subList(from, to + 1).map { maxOf(it, threshold / 8) }.sorted()
        return body[(0.9 * (body.size - 1)).toInt()] >= swell * body[(0.1 * (body.size - 1)).toInt()]
    }

    /// The frame's level over 100 Hz (RMS after the high-pass), the filter running on across frames.
    private fun high(frame: ShortArray): Double {
        val a = HIGH_PASS
        var x0 = hx; var y = hy; var total = 0.0
        for (s in frame) {
            val x = s.toDouble()
            y = a * (y + x - x0)
            x0 = x
            total += y * y
        }
        hx = x0; hy = y
        return if (frame.isEmpty()) 0.0 else Math.sqrt(total / frame.size) / 32768
    }

    /// Rumble, not speech: under a quarter of the loud frames' energy is over 100 Hz. Speech keeps
    /// nearly all of it there (-0.3 to -1 dB in testing, the low male voices included); brown noise
    /// with almost nothing over 20 Hz keeps -20 to -28 dB, and Ming made a sentence of 15 of 17 such
    /// segments ("I'm going to go ahead and start the meeting."), which the loudness rules can't
    /// tell from a voice. Brown noise up to about 12 Hz keeps -10 dB and goes too; a 50 Hz hum or a
    /// fan keeps about -5 dB and is left to the steady test.
    internal fun isRumble(frameLevels: List<Double>, frameHighs: List<Double>): Boolean {
        var full = 0.0; var above = 0.0
        for (i in 0 until minOf(frameLevels.size, frameHighs.size)) {
            if (frameLevels[i] < threshold) continue
            full += frameLevels[i] * frameLevels[i]
            above += frameHighs[i] * frameHighs[i]
        }
        return above < Segmenter.above * full
    }

    /// Emits `current[0 until end]` and keeps what follows as the start of the next segment.
    private fun close(endAt: Int) {
        val end = endAt.coerceIn(0, current.size)
        val samples = current.slice(0, end)
        val rest = current.slice(end, current.size)
        val restLevels = ArrayList(levels.subList(minOf(levels.size, end / FRAME), levels.size))
        val restHighs = ArrayList(highs.subList(minOf(highs.size, end / FRAME), highs.size))
        val restSpeech = ArrayList(speech.subList(minOf(speech.size, end / FRAME), speech.size))
        val start = currentStart
        val sent = ArrayList(levels.subList(0, minOf(levels.size, end / FRAME)))
        val said = if (isWord(levels)) sent.count { it >= threshold / 4 } * FRAME >= minWord * RATE
            else loudFrames * FRAME >= minSpeech * RATE && !isSteady(sent)
        val heard = said && !isRumble(sent, ArrayList(highs.subList(0, sent.size)))
        current.clear(); levels.clear(); highs.clear(); speech.clear()
        quietFrames = 0; loudFrames = 0
        if (heard) onSegment?.invoke(Segment(++index, Math.round(start * 1000) / 1000.0, samples))

        // A forced cut carries on with the remainder; after a pause the remainder is silence.
        if (restSpeech.any { it }) {
            currentStart = start + end / RATE.toDouble()
            lead = null
            current.addAll(rest, 0, rest.size)
            levels.addAll(restLevels)
            highs.addAll(restHighs)
            speech.addAll(restSpeech)
            var trailing = 0
            for (i in speech.indices.reversed()) { if (speech[i]) break; trailing++ }
            quietFrames = trailing
            loudFrames = speech.count { it }
        }
    }
}

/// A growable ShortArray (no boxing on the audio path).
internal class ShortList {
    private var a = ShortArray(RATE_HINT)
    var size = 0; private set

    fun addAll(src: ShortArray, from: Int, to: Int) {
        val n = to - from
        if (size + n > a.size) a = a.copyOf(maxOf(a.size * 2, size + n))
        System.arraycopy(src, from, a, size, n)
        size += n
    }

    fun slice(from: Int, to: Int): ShortArray = a.copyOfRange(from, to)

    fun removeFirst(n: Int) {
        System.arraycopy(a, n, a, 0, size - n)
        size -= n
    }

    fun clear() { size = 0 }

    private companion object { const val RATE_HINT = 16000 }
}
