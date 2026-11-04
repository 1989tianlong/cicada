package com.wquguru.cicada

import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import cicada.Languages
import cicada.MeetingNotes
import cicada.NotesEngine
import cicada.Strings.L
import cicada.Strings.LF
import cicada.TranscriptLine
import java.time.Instant

/// What the live screens show, built the same way for 正在听 and the floating window.
object NotesViews {
    /// This meeting's lines while it runs (or until its last reply lands).
    fun currentLines(app: CicadaApp): List<TranscriptLine> {
        val listen = app.listen
        if (!listen.listening && listen.pending == 0) return emptyList()
        return listen.sessionId?.let { app.store.lines(it) } ?: emptyList()
    }

    /// No sound for 20 s from what the phone plays: most likely an app that can't be captured.
    fun silent(app: CicadaApp) = app.listen.let { it.listening && it.sourceKind == "playback" && it.heardSeconds > 20 && it.peak < 0.002 }

    /// Everything the live views show, so they are rebuilt only when it changes: a view replaced
    /// under a finger loses the tap.
    fun liveKey(app: CicadaApp): String {
        val listen = app.listen
        val line = listen.sessionId?.let { app.store.lines(it).lastOrNull() }
        return listOf(listen.listening, listen.sourceKind, listen.sessionId, listen.pending > 0, listen.problem, app.startProblem, silent(app), app.micSilenced,
                      line?.id, line?.src, line?.dst, app.notes.status, app.notes.notes.updatedAt, app.notes.notes.covered).joinToString("|")
    }

    /// "正在听 · 03:12" / "面对面 · 03:12".
    fun status(app: CicadaApp): String {
        val head = if (app.listen.sourceKind == "mic") L("面对面") else L("正在听")
        return head + " · " + clock(app)
    }

    fun clock(app: CicadaApp): String = app.listen.sessionId?.let { app.store.get(it) }?.let { Languages.clock(it.durationSeconds) } ?: "00:00"

    /// "手机里的声音 · English → 简体中文".
    fun sourceLine(app: CicadaApp): String {
        val source = if (app.listen.sourceKind == "mic") L("面对面") else L("手机里的声音")
        val from = app.listen.spoken?.let { languageName(it) } ?: L("自动识别")
        return "$source · $from → ${languageName(app.settings.targetCode)}"
    }

    fun languageName(code: String) = Languages.targets.firstOrNull { it.code == code }?.name
        ?: Languages.sources.firstOrNull { it.code == code }?.name ?: code

    /// "刚刚更新" / "3 分钟前更新".
    fun updated(at: Instant?): String? {
        at ?: return null
        val minutes = (Instant.now().epochSecond - at.epochSecond) / 60
        return if (minutes < 1) L("刚刚更新") else LF("%@ 分钟前更新", minutes)
    }

    /// The problem banner of the live screens, or null. `onMic` offers 面对面 when nothing is heard.
    fun banner(ui: Ui, app: CicadaApp, onMic: (() -> Unit)?): View? {
        val problem = app.listen.problem
        val (iconRes, text) = when {
            problem == L("连不上 Ling，检查网络") -> R.drawable.i_wifi_off to L("连不上 Ling，联网后继续出字幕")
            app.micSilenced && app.listen.listening -> R.drawable.i_mic to L("麦克风正被通话或其他 app 占用，用完后接着听")
            problem != null -> R.drawable.i_info to problem
            silent(app) -> R.drawable.i_speaker_off to L("20 秒没听到声音。通话和会议 app 的声音系统不让录")
            else -> return null
        }
        return LinearLayout(ui.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = ui.rounded(Palette.card, 16)
            setPadding(ui.dp(14), ui.dp(10), ui.dp(6), ui.dp(10))
            minimumHeight = ui.dp(56)
            addView(ui.icon(R.drawable.i_info, 22, Palette.link).apply { setImageDrawable(ui.drawable(iconRes, Palette.link)) })
            addView(ui.text(text, 14f, Palette.ink), ui.weight().apply { leftMargin = ui.dp(12) })
            if (silent(app) && onMic != null) addView(ui.textButton(L("换成面对面"), onClick = onMic))
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
    }

    /// The subtitle stream: earlier lines small, the newest as a large card at the bottom.
    fun stream(ui: Ui, app: CicadaApp, earlier: Int): LinearLayout {
        val lines = currentLines(app)
        val box = ui.stack(18)
        if (lines.isEmpty()) {
            box.addView(LinearLayout(ui.context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(0, ui.dp(64), 0, ui.dp(48))
                addView(ui.icon(R.drawable.i_waves, 36, Palette.outline))
                addView(ui.text(if (app.listen.pending > 0) L("正在听下一句…") else L("等有人说话…"), 15f, Palette.secondary), ui.lp(top = 14, width = -2))
            })
            return box
        }
        for (l in lines.dropLast(1).takeLast(earlier)) {
            val texts = ui.stack(2, ui.text(said(l), 13f, Palette.secondary))
            if (!l.dst.isNullOrEmpty() && l.dst != l.src) texts.addView(ui.text(l.dst!!, 16f, Palette.ink), ui.lp(top = 2))
            box.addView(LinearLayout(ui.context).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(ui.text(Languages.clock(l.t), 12f, Palette.secondary, bold = true), LinearLayout.LayoutParams(-2, -2).apply { topMargin = ui.dp(1); rightMargin = ui.dp(10) })
                addView(texts, ui.weight())
            })
        }
        box.addView(liveCard(ui, app, lines.last(), 23f))
        return box
    }

    /// The newest line as a card, with the "still listening" dots under it.
    /// The original as shown above its translation: mine is marked, so it's clear who said it.
    fun said(l: TranscriptLine) = if (l.speaker == "me") L("你") + " · " + l.src else l.src

    fun liveCard(ui: Ui, app: CicadaApp, line: TranscriptLine, big: Float, bg: Int = Palette.card, lines: Int = 0, dots: Boolean = true): LinearLayout {
        val card = ui.stack(0)
        card.background = ui.rounded(bg, 20)
        card.setPadding(ui.dp(18), ui.dp(16), ui.dp(18), ui.dp(16))
        card.accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        val translated = !line.dst.isNullOrEmpty() && line.dst != line.src
        if (!translated && line.speaker == "me") card.addView(ui.text(L("你"), 14f, Palette.secondary))
        if (translated) card.addView(ui.text(said(line), 14f, Palette.secondary, lines = if (lines > 0) lines - 1 else 0))
        card.addView(ui.text(line.dst ?: line.src, big, Palette.ink, bold = true, lines = lines).apply { setLineSpacing(0f, 1.25f) }, ui.lp(top = if (translated || line.speaker == "me") 8 else 0))
        if (dots && app.listen.listening) card.addView(LinearLayout(ui.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            listOf(1f, 0.6f, 0.3f).forEach { a -> addView(ui.dot(Palette.accent, 6).apply { alpha = a }, LinearLayout.LayoutParams(ui.dp(6), ui.dp(6)).apply { rightMargin = ui.dp(5) }) }
            addView(ui.text(L("正在听下一句…"), 13f, Palette.secondary), LinearLayout.LayoutParams(-2, -2).apply { leftMargin = ui.dp(4) })
        }, ui.lp(top = 12))
        return card
    }

    /// The notes: name and freshness, summary, topics, conclusions, to-dos. `compact` (the
    /// floating window) keeps the current topic only.
    fun notesBody(ui: Ui, notes: MeetingNotes, status: NotesEngine.State, listening: Boolean, compact: Boolean = false): LinearLayout {
        val body = ui.stack(0)
        if (notes.isEmpty) {
            val hint = when (status) {
                NotesEngine.State.NoKey -> L("需要 Ling key 才能听")
                NotesEngine.State.InvalidKey -> L("这个 Ling key 无效，看看有没有复制全，或换一个新的")
                NotesEngine.State.RateLimited -> L("请求过于频繁，稍后会自动重试。")
                NotesEngine.State.Updating -> L("正在整理纪要…")
                else -> if (listening) L("说几句后生成纪要，之后每 45 秒更新") else ""
            }
            if (hint.isNotEmpty()) body.addView(ui.text(hint, 14f, Palette.secondary))
            return body
        }
        if (!compact) {
            val head = LinearLayout(ui.context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(ui.heading(notes.title ?: L("纪要"), 19f).apply { maxLines = 2 }, ui.weight())
                val fresh = if (status == NotesEngine.State.Updating) L("正在整理纪要…") else updated(notes.updatedAt)
                if (fresh != null) addView(ui.text(fresh, 12f, Palette.secondary), LinearLayout.LayoutParams(-2, -2).apply { leftMargin = ui.dp(8) })
            }
            body.addView(head)
            if (notes.summary.isNotEmpty()) body.addView(ui.text(notes.summary, 15f, Palette.body).apply { setLineSpacing(0f, 1.35f) }, ui.lp(top = 10))
        }
        val topics = if (compact) notes.topics.takeLast(1) else notes.topics
        topics.forEachIndexed { i, t ->
            body.addView(ui.row(10, ui.text(Languages.clock(t.start), 12f, Palette.link, bold = true), ui.text(t.title, 15f, Palette.ink, bold = true).apply { layoutParams = ui.weight() }),
                         ui.lp(top = if (compact && i == 0) 0 else 18))
            for (p in if (compact) t.points.takeLast(3) else t.points) body.addView(bullet(ui, p, if (compact) 14f else 15f), ui.lp(top = 6))
        }
        if (!compact && notes.conclusions.isNotEmpty()) {
            body.addView(ui.text(L("结论"), 13f, Palette.secondary, bold = true), ui.lp(top = 20))
            for (c in notes.conclusions) body.addView(bullet(ui, c.text, 15f), ui.lp(top = 6))
        }
        if (!compact && notes.todos.isNotEmpty()) {
            body.addView(ui.text(L("待办"), 13f, Palette.secondary, bold = true), ui.lp(top = 20))
            for (t in notes.todos) body.addView(todo(ui, t.text, t.owner), ui.lp(top = 8))
        }
        return body
    }

    fun bullet(ui: Ui, text: String, size: Float) = LinearLayout(ui.context).apply {
        orientation = LinearLayout.HORIZONTAL
        addView(ui.dot(Palette.tertiary, 5), LinearLayout.LayoutParams(ui.dp(5), ui.dp(5)).apply { topMargin = ui.dp((size * 0.6).toInt()); rightMargin = ui.dp(10); leftMargin = ui.dp(2) })
        addView(ui.text(text, size, Palette.body).apply { setLineSpacing(0f, 1.3f) }, ui.weight())
    }

    fun todo(ui: Ui, text: String, owner: String?) = LinearLayout(ui.context).apply {
        orientation = LinearLayout.HORIZONTAL
        addView(View(ui.context).apply { background = ui.rounded(0, 4, Palette.outline, 2) }, LinearLayout.LayoutParams(ui.dp(16), ui.dp(16)).apply { topMargin = ui.dp(3); rightMargin = ui.dp(10) })
        addView(ui.text(text + (owner?.let { " · $it" } ?: ""), 15f, Palette.body), ui.weight())
    }
}
