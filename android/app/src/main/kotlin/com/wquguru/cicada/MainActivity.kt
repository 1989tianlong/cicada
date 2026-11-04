package com.wquguru.cicada

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import cicada.Languages
import cicada.Session
import cicada.SessionStore
import cicada.Strings.L
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/// 首页: start listening (what the phone plays, or 面对面), the meeting going on if any, and the
/// last few meetings. One job per area, the main action a 56dp button.
class MainActivity : Activity() {
    private lateinit var ui: Ui
    private lateinit var top: FrameLayout
    private lateinit var recent: FrameLayout
    private var shownTop: String? = null
    private var shownRecent: String? = null
    private var clockText: TextView? = null
    private var unobserve: (() -> Unit)? = null
    private val tick = object : Runnable {
        override fun run() { clockText?.text = NotesViews.status(cicada); renderTop(); cicada.main.postDelayed(this, 1000) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ui = Ui(this)
        if (!cicada.settings.onboarded) startActivity(Intent(this, OnboardingActivity::class.java))
        top = FrameLayout(this); recent = FrameLayout(this)
        val body = ui.stack(16, top, recent).apply { setPadding(ui.dp(16), ui.dp(4), ui.dp(16), ui.dp(32)) }
        setContentView(ui.screen(this, L("知了"), back = false, ground = Palette.ground, body = body,
            actions = listOf(ui.iconButton(R.drawable.i_settings, L("设置"), Palette.body) { startActivity(Intent(this, SettingsActivity::class.java)) })))
    }

    override fun onResume() {
        super.onResume()
        unobserve = cicada.observe(::render)
        shownTop = null; shownRecent = null
        render()
        cicada.main.postDelayed(tick, 1000)
    }

    override fun onPause() {
        super.onPause()
        unobserve?.invoke(); unobserve = null
        cicada.main.removeCallbacks(tick)
    }

    private fun render() { renderTop(); renderRecent() }

    private val micDenied get() = checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED

    private fun renderTop() {
        val app = cicada
        val key = listOf(NotesViews.liveKey(app), app.settings.source, app.settings.target, app.canOverlay, app.settings.overlay, micDenied, app.listen.spoken).joinToString("|")
        if (key == shownTop) return
        shownTop = key
        top.removeAllViews()
        val column = ui.stack(16)
        column.addView(if (app.listen.listening) liveCard() else startCard())
        if (app.settings.overlay && !app.canOverlay) column.addView(tipCard())
        top.addView(column)
    }

    /// A meeting is going on: where it is and a way back to it.
    private fun liveCard(): LinearLayout {
        val app = cicada
        val status = ui.text(NotesViews.status(app), 15f, Palette.link, bold = true)
        clockText = status
        val card = ui.card(ui.row(8, ui.dot(Palette.accent), status), gap = 12)
        card.addView(ui.helper(NotesViews.sourceLine(app)), ui.lp(top = 4))
        NotesViews.currentLines(app).lastOrNull()?.let { l -> card.addView(ui.text(l.dst ?: l.src, 18f, Palette.ink, bold = true, lines = 3), ui.lp(top = 12)) }
        card.addView(ui.button(L("回到正在听"), "primary", R.drawable.i_waves) { app.openLive() }, ui.lp(top = 16))
        return card
    }

    private fun startCard(): LinearLayout {
        val app = cicada
        val pb = app.settings.source != "mic"
        clockText = null
        val card = ui.card(gap = 16)
        card.addView(ui.segmented(listOf("playback" to L("手机里的声音"), "mic" to L("面对面")), app.settings.source) {
            app.settings.source = it; app.saveSettings(); shownTop = null; renderTop()
        })
        val desc = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(ui.tile(if (pb) R.drawable.i_speaker else R.drawable.i_mic))
            addView(ui.stack(2,
                ui.text(if (pb) L("视频、直播、网课里的声音") else L("用麦克风听身边的人"), 15f, Palette.ink, medium = true),
                ui.helper(if (pb) L("通话和会议 app 的声音系统不让录，改用“面对面”") else L("线下开会，或会议 app 开外放"))), ui.weight().apply { leftMargin = ui.dp(12) })
        }
        card.addView(desc, ui.lp(top = 16))
        // The language pair: what is heard (found by itself) → what subtitles read in.
        val lang = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = ui.dp(52)
            setPadding(ui.dp(16), 0, ui.dp(12), 0)
            addView(ui.text(L("自动识别"), 15f, Palette.secondary))
            addView(ui.icon(R.drawable.i_arrow_right, 18, Palette.secondary), LinearLayout.LayoutParams(ui.dp(18), ui.dp(18)).apply { leftMargin = ui.dp(10); rightMargin = ui.dp(10) })
            addView(ui.text(NotesViews.languageName(app.settings.targetCode), 15f, Palette.ink, medium = true), ui.weight())
            addView(ui.icon(R.drawable.i_chevron_right, 20, Palette.tertiary))
            contentDescription = L("翻译成") + " " + NotesViews.languageName(app.settings.targetCode)
            ui.tappable(this, 14, ui.rounded(Palette.ground, 14)) { chooseTarget() }
        }
        card.addView(lang, ui.lp(top = 16))
        app.startProblem?.let { card.addView(ui.text(it, 14f, Palette.link).apply { accessibilityLiveRegion = 1 }, ui.lp(top = 16)) }
        if (micDenied && app.startProblem != null)
            card.addView(ui.textButton(L("去系统设置开启麦克风权限")) {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
            }.apply { gravity = Gravity.START or Gravity.CENTER_VERTICAL; setPadding(ui.dp(4), 0, ui.dp(4), 0) }, ui.lp(top = 4, width = -2))
        card.addView(ui.button(L("开始听"), "primary", R.drawable.i_waves) { app.startListening(this, app.settings.source) }, ui.lp(top = 16))
        return card
    }

    private fun tipCard() = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        background = ui.rounded(Palette.card, 20)
        setPadding(ui.dp(16), ui.dp(12), ui.dp(8), ui.dp(12))
        addView(ui.tile(R.drawable.i_pip, 40, Palette.accentPale, Palette.link).apply { background = ui.rounded(Palette.accentPale, 20) })
        addView(ui.stack(2, ui.text(L("在视频上直接看字幕"), 15f, Palette.ink, medium = true), ui.helper(L("开启“显示在其他应用上层”"))),
                ui.weight().apply { leftMargin = ui.dp(12) })
        addView(ui.textButton(L("去开启")) { OverlayGuideActivity.open(this@MainActivity, direct = true) })
    }

    private fun renderRecent() {
        val app = cicada
        val sessions = app.store.all()
        val liveId = if (app.listen.listening) app.listen.sessionId else null
        val key = sessions.take(3).joinToString { "${it.id}:${SessionStore.displayTitle(it)}:${it.lines.size}:${it.endedAt}" } + liveId + app.store.loaded
        if (key == shownRecent) return
        shownRecent = key
        recent.removeAllViews()
        val column = ui.stack(8)
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(ui.dp(4), 0, 0, 0)
            addView(ui.heading(L("最近的会议"), 16f), ui.weight())
            if (sessions.isNotEmpty()) addView(ui.textButton(L("全部")) { startActivity(Intent(this@MainActivity, RecordsActivity::class.java)) })
        }
        column.addView(header)
        if (sessions.isEmpty() && !app.store.loaded) column.addView(android.widget.ProgressBar(this).apply { isIndeterminate = true; contentDescription = L("正在加载…") }, ui.lp(top = 8, width = ui.dp(32), height = ui.dp(32)))
        else if (sessions.isEmpty()) column.addView(ui.helper(L("还没有会议记录")).apply { setPadding(ui.dp(4), ui.dp(4), 0, 0) })
        else column.addView(ui.group(sessions.take(3).map { recordRow(this, ui, it, it.id == liveId) }))
        recent.addView(column)
    }

    private fun chooseTarget() {
        val app = cicada
        val options = listOf("system" to L("跟随系统")) + Languages.targets.map { it.code to it.name }
        AlertDialog.Builder(this).setTitle(L("翻译成"))
            .setSingleChoiceItems(options.map { it.second }.toTypedArray(), options.indexOfFirst { it.first == app.settings.target }) { d, i ->
                d.dismiss(); app.settings.target = options[i].first; app.saveSettings(); shownTop = null; renderTop()
            }.setNegativeButton(L("取消"), null).show()
    }

    companion object {
        /// "今天 20:54" / "昨天 09:02" / "11月1日 15:30".
        fun day(at: Instant): String {
            val local = at.atZone(ZoneId.systemDefault())
            val d = local.toLocalDate()
            val today = LocalDate.now()
            val label = when (d) {
                today -> L("今天")
                today.minusDays(1) -> L("昨天")
                else -> DateTimeFormatter.ofPattern(L("M月d日"), cicada.Strings.locale).format(local)
            }
            return label
        }

        fun time(at: Instant): String = DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneId.systemDefault()).format(at)

        /// The meeting's name without its date (lists and rename show the date apart).
        fun name(s: Session): String =
            if (s.renamed ?: !s.title.startsWith("会议 ")) s.title else s.notes?.title?.takeIf { it.isNotEmpty() } ?: SessionStore.displayTitle(s)

        /// One meeting in a list: title (and 正在听), when, how long, how many lines, to-dos.
        fun recordRow(activity: Activity, ui: Ui, s: Session, live: Boolean): LinearLayout {
            // The line under it says when: the title is just the meeting's name.
            val title = name(s)
            val titleView = LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                if (live) addView(ui.badge(L("正在听"), dot = true), LinearLayout.LayoutParams(-2, -2).apply { rightMargin = ui.dp(8) })
                addView(ui.text(title, 16f, Palette.ink, medium = true, lines = 1), ui.weight())
            }
            val meta = if (live) "${time(s.startedAt)} · ${Languages.clock(s.durationSeconds)}"
                       else "${day(s.startedAt)} ${time(s.startedAt)} · ${Languages.clock(s.durationSeconds)} · ${s.lines.size} ${L("句")}"
            val todos = s.notes?.todos?.size ?: 0
            val trailing = if (todos > 0) ui.badge(cicada.Strings.LF("%@ 个待办", todos), Palette.body, Palette.ground) else null
            return ui.listRow(title, meta, trailing = trailing, titleView = titleView) {
                activity.startActivity(Intent(activity, if (live) ListeningActivity::class.java else RecordActivity::class.java).putExtra("id", s.id))
            }
        }
    }
}
