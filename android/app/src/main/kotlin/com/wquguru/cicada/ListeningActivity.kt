package com.wquguru.cicada

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import cicada.Strings.L

/// 正在听: the meeting as it happens. Subtitles stream in (newest large, at the bottom) or the
/// live notes; 在视频上看 goes back to the other app, where the floating window takes over; 结束
/// ends it and opens the record.
class ListeningActivity : Activity() {
    private lateinit var ui: Ui
    private lateinit var tabsHost: FrameLayout
    private lateinit var content: LinearLayout
    private lateinit var scroll: ScrollView
    private lateinit var badgeText: TextView
    private lateinit var sourceText: TextView
    private var tab = 0
    private var shown: String? = null
    private var unobserve: (() -> Unit)? = null
    private val tick = object : Runnable {
        // The clock, and states that come without an event (20 s of silence): render() is keyed.
        override fun run() { badgeText.text = NotesViews.status(cicada); render(); cicada.main.postDelayed(this, 1000) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ui = Ui(this)
        tab = savedInstanceState?.getInt("tab") ?: 0
        badgeText = ui.text(NotesViews.status(cicada), 14f, Palette.link, bold = true, lines = 1)
        val badge = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
            background = ui.rounded(Palette.accentPale, 16)
            setPadding(ui.dp(14), ui.dp(7), ui.dp(14), ui.dp(7))
            addView(ui.dot(Palette.accent, 8))
            addView(badgeText, LinearLayout.LayoutParams(-2, -2).apply { leftMargin = ui.dp(8) })
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_NONE
        }
        sourceText = ui.helper("").apply { gravity = android.view.Gravity.CENTER }
        tabsHost = FrameLayout(this)
        content = ui.stack(12).apply { setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(16)) }
        scroll = ScrollView(this).apply { isVerticalScrollBarEnabled = false; addView(content); isFillViewport = true }
        val body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(sourceText, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = ui.dp(6) })
            addView(tabsHost, LinearLayout.LayoutParams(-1, -2).apply { leftMargin = ui.dp(16); rightMargin = ui.dp(16) })
            addView(ui.divider(), LinearLayout.LayoutParams(-1, 1).apply { leftMargin = ui.dp(16); rightMargin = ui.dp(16) })
            addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        }
        val bottom = ui.bottomBar(
            ui.button(L("在视频上看"), "quiet", R.drawable.i_pip) { watchOver() },
            ui.button(L("结束"), "primary", R.drawable.i_stop) { end() })
        setContentView(ui.screen(this, null, back = true, ground = Palette.ground, center = badge, bottom = bottom, scroll = false, body = body))
    }

    override fun onSaveInstanceState(out: Bundle) { super.onSaveInstanceState(out); out.putInt("tab", tab) }

    override fun onResume() {
        super.onResume()
        if (!cicada.listen.listening && cicada.listen.pending == 0) { finish(); return }
        unobserve = cicada.observe(::render)
        shown = null
        render()
        cicada.main.postDelayed(tick, 1000)
    }

    override fun onPause() {
        super.onPause()
        unobserve?.invoke(); unobserve = null
        cicada.main.removeCallbacks(tick)
    }

    private fun render() {
        val app = cicada
        // Ended elsewhere (the notification, the floating window, Android's "stop sharing").
        if (!app.listen.listening && app.listen.pending == 0) { openRecord(); return }
        badgeText.text = NotesViews.status(app)
        sourceText.text = NotesViews.sourceLine(app)
        val key = NotesViews.liveKey(app) + tab + app.listen.spoken
        if (key == shown) return
        shown = key
        tabsHost.removeAllViews()
        tabsHost.addView(ui.tabs(listOf(L("字幕"), L("实时纪要")), tab) { tab = it; render() })
        content.removeAllViews()
        NotesViews.banner(ui, app) { switchToMic() }?.let { content.addView(it) }
        if (tab == 0) {
            content.addView(ui.spacer(), LinearLayout.LayoutParams(-1, 0, 1f))
            content.addView(NotesViews.stream(ui, app, 6))
            scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
        } else {
            val card = NotesViews.notesBody(ui, app.notes.notes, app.notes.status, app.listen.listening).apply {
                background = ui.rounded(Palette.card, 20)
                setPadding(ui.dp(18), ui.dp(18), ui.dp(18), ui.dp(18))
            }
            content.addView(card)
        }
    }

    /// Back to the app underneath (the video): the floating window shows there. Without the
    /// permission for it, say where to turn it on first.
    private fun watchOver() {
        val app = cicada
        if (!app.canOverlay) {
            AlertDialog.Builder(this).setTitle(L("在视频上直接看字幕")).setMessage(L("开启“显示在其他应用上层”"))
                .setPositiveButton(L("去开启")) { _, _ -> startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))) }
                .setNegativeButton(L("取消"), null).show()
            return
        }
        // Asked for now: show it for this meeting even if 悬浮窗 is off in 设置, without changing that.
        app.overlayThisMeeting = true
        app.overlayClosed = false
        moveTaskToBack(true)
    }

    private fun end() {
        val id = cicada.listen.sessionId
        cicada.stopListening {
            if (id != null && cicada.store.get(id) != null) startActivity(Intent(this, RecordActivity::class.java).putExtra("id", id))
            finish()
        }
    }

    private fun openRecord() {
        val id = cicada.listen.sessionId
        if (id != null && cicada.store.get(id) != null && !isFinishing) startActivity(Intent(this, RecordActivity::class.java).putExtra("id", id))
        finish()
    }

    /// Nothing heard from the phone: start again from the microphone.
    private fun switchToMic() {
        val app = cicada
        app.settings.source = "mic"; app.saveSettings()
        app.stopListening { app.startListening(app, "mic") }
    }
}
