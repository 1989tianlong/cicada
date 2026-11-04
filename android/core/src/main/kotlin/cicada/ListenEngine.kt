package cicada

import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/// Listening end to end: audio → segments → Ming (language, original, translation in one call) →
/// lines in the record, plus live notes. UI-free; the app shows the record and listens to
/// `onChange` (called on worker threads: post to the main thread).
///
/// Ming takes ~2.2 s whatever the segment's length, so segments overlap in flight: request starts
/// still go through LingClient's gate, and lines are delivered in segment order.
class ListenEngine(
    private val ling: LingClient,
    private val translator: Translator,
    private val store: SessionStore,
    private val notes: NotesEngine,
    private val settings: AppSettings,
) {
    private val gate = Any()
    private val pool = Executors.newCachedThreadPool { r -> Thread(r, "Listen").apply { isDaemon = true } }
    private var source: AudioSource? = null
    private var audio: LinkedBlockingQueue<ShortArray>? = null
    private var worker: Thread? = null
    private val done = HashMap<Int, Heard?>()
    private val segments = HashMap<Int, Segment>()
    private val inFlight = mutableListOf<Future<*>>()
    private var nextToDeliver = 1
    private var lineCount = 0
    private var last: TranscriptLine? = null
    private var lastEnd = 0.0
    private var hint: String? = null
    private var candidate: String? = null
    private var candidateVotes = 0
    private val listeners = mutableListOf<() -> Unit>()

    @Volatile var listening = false; private set
    @Volatile var sessionId: String? = null; private set
    /// What this meeting is heard from ("playback", "mic", "file").
    @Volatile var sourceKind: String? = null; private set
    /// The meeting's language so far (null until Ming has heard something).
    val spoken: String? get() = synchronized(gate) { hint }
    /// Segments sent and not yet back: the UI shows "…" while this is above zero.
    val pending: Int get() = synchronized(gate) { segments.size }
    /// The last error worth showing ("Ling key 无效", "连不上 Ling"), cleared by the next good reply.
    @Volatile var problem: String? = null; private set
    @Volatile var level = 0.0; private set
    /// Seconds of audio heard this meeting (the capture is alive while this grows).
    @Volatile var heardSeconds = 0.0; private set
    /// The loudest recent level: 0 for a while means the source is silent (e.g. an app that blocks capture).
    @Volatile var peak = 0.0; private set

    init { translator.glossary = { notes.glossary() } }

    fun onChange(listener: () -> Unit) { synchronized(listeners) { listeners.add(listener) } }
    private fun changed() { synchronized(listeners) { listeners.toList() }.forEach { it() } }

    val target: String get() = settings.targetCode

    private val END = ShortArray(0)

    fun start(from: AudioSource, kind: String) {
        if (listening) return
        val session = store.begin()
        sessionId = session.id
        sourceKind = kind
        synchronized(gate) {
            done.clear(); segments.clear(); inFlight.clear()
            nextToDeliver = 1; lineCount = 0; last = null; lastEnd = 0.0
            hint = null; candidate = null; candidateVotes = 0; problem = null
        }
        heardSeconds = 0.0; peak = 0.0
        notes.language = { Languages.englishName(settings.notesCode) }
        notes.begin(session.id)
        val segmenter = Segmenter()
        segmenter.onSegment = ::send
        val queue = LinkedBlockingQueue<ShortArray>()
        audio = queue
        // One worker owns the segmenter: audio callbacks only queue buffers.
        worker = Thread({
            while (true) {
                val buf = queue.take()
                if (buf === END) break
                segmenter.feed(buf)
                level = Wav.rms(buf)
                peak = maxOf(peak * 0.995, level)
                heardSeconds += buf.size / Segmenter.RATE.toDouble()
            }
            segmenter.flush()
        }, "ListenWorker").apply { isDaemon = true; start() }
        source = from
        from.onSamples = { queue.offer(it) }
        // Listening before the source starts: a source that fails at once calls onEnded → stop(),
        // which must see this meeting as running to end it.
        listening = true
        from.start()
        Log.d("listen: started ${session.id} source=$kind target=$target")
        changed()
    }

    /// Stops listening, waits (briefly) for segments still at Ming, ends the record and starts the
    /// final notes. Blocks until the record is saved: call off the main thread.
    fun stop() {
        if (!listening) return
        listening = false
        source?.let { it.onSamples = null; it.stop() }
        audio?.offer(END)
        worker?.join(5000)
        val waiting = synchronized(gate) { inFlight.toList() }
        val deadline = System.currentTimeMillis() + 15_000
        for (f in waiting) {
            try { f.get(maxOf(1, deadline - System.currentTimeMillis()), TimeUnit.MILLISECONDS) } catch (_: Exception) {}
        }
        val id = sessionId ?: return
        store.end(id)
        Log.d("listen: stopped $id, $lineCount lines")
        changed()
        pool.execute { notes.finish() }
    }

    private fun send(seg: Segment) {
        val wav = Wav.bytes(seg.samples)
        val lang = synchronized(gate) { segments[seg.index] = seg; hint }
        changed()
        val future = pool.submit {
            var heard: Heard? = null
            val started = System.currentTimeMillis()
            try {
                heard = translator.hear(wav, target, lang)
                problem = null
            } catch (e: LingException) {
                problem = when (e.kind) {
                    LingException.Kind.NoKey -> Strings.L("需要 Ling key 才能听")
                    LingException.Kind.InvalidKey -> Strings.L("Ling key 无效")
                    LingException.Kind.RateLimited -> Strings.L("Ling 太忙，稍后再试")
                    LingException.Kind.Network, LingException.Kind.Timeout -> Strings.L("连不上 Ling，检查网络")
                    else -> null
                }
                Log.d("listen: segment ${seg.index} failed ${e.message}")
            } catch (e: Exception) {
                Log.d("listen: segment ${seg.index} failed ${e.javaClass.simpleName}")
            }
            Log.d("listen: segment ${seg.index} ${"%.1f".format(seg.seconds)}s -> ${heard?.lang ?: "nothing"} in ${System.currentTimeMillis() - started} ms")
            synchronized(gate) { done[seg.index] = heard }
            deliver()
        }
        synchronized(gate) { inFlight.add(future); inFlight.removeAll { it.isDone } }
    }

    /// Hands finished segments on in order: one slow reply holds back those after it.
    private fun deliver() {
        val ready = mutableListOf<Pair<Segment, Heard?>>()
        synchronized(gate) {
            while (done.containsKey(nextToDeliver)) {
                val heard = done.remove(nextToDeliver)
                ready.add(segments.remove(nextToDeliver)!! to heard)
                nextToDeliver++
            }
        }
        for ((seg, heard) in ready) if (heard != null) record(seg, heard)
        if (ready.isNotEmpty()) changed()
    }

    private fun record(seg: Segment, heard: Heard) {
        val id = sessionId ?: return
        val target = target
        // The meeting's language moves only after two segments agree, so one misheard stretch
        // doesn't flip the hint (the Mac waits for confidence the same way).
        synchronized(gate) {
            val h = hint
            if (h == null) hint = heard.lang
            else if (heard.lang != h) {
                if (candidate == heard.lang) candidateVotes++ else { candidate = heard.lang; candidateVotes = 1 }
                if (candidateVotes >= 2) { hint = candidate; candidate = null; candidateVotes = 0 }
            } else { candidate = null; candidateVotes = 0 }
        }

        val line: TranscriptLine
        var joined = false
        synchronized(gate) {
            val prev = last
            if (prev != null && continues(prev, seg.start - lastEnd, heard)) {
                prev.src = join(prev.src, heard.original, heard.lang)
                prev.dst = if (prev.dst == null || heard.translation == null) null else join(prev.dst!!, heard.translation, target)
                line = prev
                joined = true
            } else {
                line = TranscriptLine(id = "h${++lineCount}-${seg.index}", t = seg.start, speaker = "them",
                                      src = heard.original, dst = heard.translation, srcLang = heard.lang, dstLang = target)
                last = line
            }
            lastEnd = seg.start + seg.seconds
        }
        val copy = synchronized(gate) { line.copy() }
        if (joined) store.replace(id, copy) else store.append(id, copy)

        // A joined sentence is translated again as a whole; a line Ming didn't translate gets text translation.
        if ((joined || line.dst == null) && line.srcLang != target) {
            val src = line.src
            pool.execute {
                val dst = translator.translate(src, line.srcLang, target, Translator.Kind.Sentence)
                val updated = synchronized(gate) {
                    if (dst == null || line.src != src) return@execute
                    line.dst = dst
                    line.copy()
                }
                store.replace(id, updated)
                changed()
            }
        }
    }

    companion object {
        /// A segment continues the last line when the cut came mid-sentence: no sentence end on the
        /// last line, a short gap, the same language, and the joined line not too long to read.
        fun continues(last: TranscriptLine, gap: Double, next: Heard): Boolean {
            if (gap > 0.8 || last.srcLang != next.lang) return false
            val text = last.src.trimEnd()
            if (text.isEmpty() || ".!?。！？…".contains(text.last())) return false
            val cjk = Languages.isCjkLanguage(next.lang)
            val size = if (cjk) text.length + next.original.length else "$text ${next.original}".split(' ').count { it.isNotEmpty() }
            return size <= if (cjk) 80 else 45
        }

        fun join(a: String, b: String, lang: String): String {
            val cjk = lang.startsWith("zh") || lang.startsWith("ja")
            return if (cjk) a.trimEnd() + b.trimStart() else a.trimEnd() + " " + b.trimStart()
        }
    }
}
