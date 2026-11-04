package cicada

import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/// The meeting records: one folder per meeting under Sessions/<yyyyMMdd-HHmmss>/ with
/// session.json, as on the Mac. Saves are debounced by 1.5 s; a meeting with no lines is removed
/// when it ends. Thread-safe; `changed` fires on whichever thread made the change.
class SessionStore(loadNow: Boolean = true) {
    private val gate = Any()
    private val sessions = HashMap<String, Session>()
    private val dirty = HashSet<String>()
    private val saver = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "SessionStore").apply { isDaemon = true } }
    private var pendingSave: ScheduledFuture<*>? = null
    private val listeners = mutableListOf<(String) -> Unit>()

    /// Whether the records on disk have been read (the app reads them off the main thread).
    @Volatile var loaded = false; private set

    init { if (loadNow) load() }

    fun onChange(listener: (String) -> Unit) { synchronized(listeners) { listeners.add(listener) } }
    private fun fire(id: String) { synchronized(listeners) { listeners.toList() }.forEach { it(id) } }

    private fun folder(id: String) = File(Paths.sessions, id)
    private fun fileOf(id: String) = File(folder(id), "session.json")

    /// Reads every record on disk; the app calls this on a background thread at launch (hundreds of
    /// records take seconds), so a meeting begun meanwhile is kept, not overwritten.
    fun load() {
        val dirs = Paths.sessions.listFiles() ?: run { loaded = true; fire(""); return }
        for (dir in dirs) {
            val file = File(dir, "session.json")
            if (!file.isFile) continue
            try {
                val s = Session.read(file.readText()) ?: continue
                // A meeting the app was killed in (a phone does that) never ended: it ends at its
                // last line, so its length doesn't keep growing with the clock.
                if (s.endedAt == null) {
                    s.endedAt = s.startedAt.plusMillis((((s.lines.lastOrNull()?.t ?: 0.0) + 5) * 1000).toLong())
                    synchronized(gate) { dirty.add(s.id) }
                    Log.d("store: closed interrupted ${s.id}")
                }
                synchronized(gate) { sessions.putIfAbsent(s.id, s) }
            } catch (e: Exception) { Log.d("store: skipped ${dir.name}: ${e.javaClass.simpleName}") }
        }
        loaded = true
        flush()
        fire("")
    }

    /// Newest first.
    fun all(): List<Session> = synchronized(gate) { sessions.values.sortedByDescending { it.startedAt } }

    fun get(id: String): Session? = synchronized(gate) { sessions[id] }

    /// A copy of a record's lines, safe to read while listening adds to them.
    fun lines(id: String): List<TranscriptLine> = synchronized(gate) { sessions[id]?.lines?.map { it.copy() } ?: emptyList() }

    fun begin(at: Instant = Instant.now()): Session {
        val id = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss").withZone(ZoneId.systemDefault()).format(at)
        val s = Session(id = id, title = defaultTitle(at), startedAt = at.truncatedTo(java.time.temporal.ChronoUnit.SECONDS))
        synchronized(gate) { sessions[id] = s }
        return s
    }

    fun append(id: String, line: TranscriptLine) = mutate(id) { it.lines.add(line) }

    fun replace(id: String, line: TranscriptLine) = mutate(id) { s ->
        val i = s.lines.indexOfFirst { it.id == line.id }
        if (i >= 0) s.lines[i] = line
    }

    fun setNotes(id: String, notes: MeetingNotes) = mutate(id) { it.notes = notes }

    fun rename(id: String, title: String) = mutate(id) { it.title = title.trim(); it.renamed = true }

    /// The meeting ended: kept if anything was said, removed otherwise.
    fun end(id: String) {
        val empty = synchronized(gate) {
            val s = sessions[id] ?: return
            s.endedAt = Instant.now()
            s.lines.isEmpty()
        }
        if (empty) delete(id) else { markDirty(id); flush() }
    }

    fun delete(id: String) {
        synchronized(gate) { sessions.remove(id); dirty.remove(id) }
        try { folder(id).deleteRecursively() } catch (e: Exception) { Log.d("store: delete failed ${e.javaClass.simpleName}") }
        fire(id)
    }

    /// A record from elsewhere (a Mac's session.json): added as it is, saved now.
    fun import(session: Session) {
        synchronized(gate) { sessions[session.id] = session }
        markDirty(session.id); flush(); fire(session.id)
    }

    private fun mutate(id: String, change: (Session) -> Unit) {
        synchronized(gate) { change(sessions[id] ?: return) }
        markDirty(id)
        fire(id)
    }

    private fun markDirty(id: String) {
        synchronized(gate) {
            dirty.add(id)
            pendingSave?.cancel(false)
            pendingSave = saver.schedule({ flush() }, 1500, TimeUnit.MILLISECONDS)
        }
    }

    /// Writes every changed record now (also when the app goes to the background).
    fun flush() {
        val writes = synchronized(gate) {
            val list = dirty.mapNotNull { id -> sessions[id]?.let { id to Json.write(it.toJson()) } }
            dirty.clear()
            list
        }
        for ((id, json) in writes) {
            try {
                folder(id).mkdirs()
                val tmp = File(folder(id), "session.json.tmp")
                tmp.writeText(json)
                if (!tmp.renameTo(fileOf(id))) { fileOf(id).delete(); tmp.renameTo(fileOf(id)) }
            } catch (e: Exception) { Log.d("store: save failed ${e.javaClass.simpleName}") }
        }
    }

    companion object {
        /// The stored default title is always Chinese ("会议 11月1日 14:30"), as on the Mac; the UI
        /// shows displayTitle instead.
        fun defaultTitle(at: Instant): String =
            "会议 " + DateTimeFormatter.ofPattern("M月d日 HH:mm", Locale.ROOT).withZone(ZoneId.systemDefault()).format(at)

        private fun localDate(at: Instant, pattern: String): String =
            DateTimeFormatter.ofPattern(pattern, Strings.locale).withZone(ZoneId.systemDefault()).format(at)

        /// The user's own title, else the date and the name the notes gave the meeting, else the
        /// default title in the UI language (Session.displayTitle).
        fun displayTitle(s: Session): String {
            if (s.renamed ?: !s.title.startsWith("会议 ")) return s.title
            val name = s.notes?.title
            if (name.isNullOrEmpty()) return Strings.L("会议") + " " + localDate(s.startedAt, Strings.L("M月d日 HH:mm"))
            val thisYear = s.startedAt.atZone(ZoneId.systemDefault()).year == Instant.now().atZone(ZoneId.systemDefault()).year
            return localDate(s.startedAt, Strings.L(if (thisYear) "M月d日" else "yyyy年M月d日")) + " " + name
        }

        fun stamp(at: Instant): String = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm").withZone(ZoneId.systemDefault()).format(at)

        /// The record as Markdown: notes, then the bilingual transcript (the Windows export).
        fun markdown(s: Session): String {
            val b = StringBuilder()
            b.append("# ${s.notes?.title ?: s.title}\n\n")
            b.append(stamp(s.startedAt)).append("\n\n")
            val n = s.notes
            if (n != null && !n.isEmpty) {
                b.append("## ${Strings.L("纪要")}\n\n${n.summary}\n\n")
                for (t in n.topics) {
                    b.append("### ${Languages.clock(t.start)} ${t.title}\n\n")
                    if (t.summary.isNotEmpty()) b.append(t.summary).append("\n\n")
                    for (p in t.points) b.append("- $p\n")
                    b.append("\n")
                }
                if (n.conclusions.isNotEmpty()) {
                    b.append("### ${Strings.L("结论")}\n\n")
                    for (c in n.conclusions) b.append("- ${c.text}\n")
                    b.append("\n")
                }
                if (n.todos.isNotEmpty()) {
                    b.append("### ${Strings.L("待办")}\n\n")
                    for (t in n.todos) b.append("- [ ] ${t.text}${t.owner?.let { "（$it）" } ?: ""}\n")
                    b.append("\n")
                }
            }
            b.append("## ${Strings.L("文字记录")}\n\n")
            for (l in s.lines) {
                val who = if (l.speaker == "me") Strings.L("你") + " · " else ""
                b.append("**${Languages.clock(l.t)}** $who${l.src}  \n")
                if (!l.dst.isNullOrEmpty() && l.dst != l.src) b.append(l.dst).append("\n")
                b.append("\n")
            }
            return b.toString()
        }
    }
}
