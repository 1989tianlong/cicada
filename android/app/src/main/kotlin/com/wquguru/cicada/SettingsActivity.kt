package com.wquguru.cicada

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipboardManager
import android.content.Intent
import android.content.res.ColorStateList
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.Switch
import cicada.AIKey
import cicada.KeyState
import cicada.Languages
import cicada.Log
import cicada.Strings
import cicada.Strings.L

/// 设置: grouped list rows (56dp), each a value that opens its choices, or a switch whose effect is
/// said under it.
class SettingsActivity : Activity() {
    private lateinit var ui: Ui
    private lateinit var page: LinearLayout
    private var unobserve: (() -> Unit)? = null
    private var shown: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ui = Ui(this)
        page = ui.stack(8).apply { setPadding(ui.dp(16), ui.dp(4), ui.dp(16), ui.dp(32)) }
        setContentView(ui.screen(this, L("设置"), back = true, ground = Palette.ground, body = page))
    }

    override fun onResume() { super.onResume(); unobserve = cicada.observe(::build); shown = null; build() }
    override fun onPause() { super.onPause(); unobserve?.invoke(); unobserve = null }

    private fun value(text: String) = ui.text(text, 15f, Palette.secondary, lines = 1)

    private fun build() {
        val app = cicada
        val s = app.settings
        val key = listOf(app.ling.keyState, app.key.read()?.takeLast(4), s.toJson(), app.canOverlay, Strings.language).joinToString("|")
        if (key == shown) return
        shown = key
        page.removeAllViews()

        page.addView(ui.sectionLabel("Ling"))
        val k = app.key.read()
        val keyStatus = when (app.ling.keyState) {
            KeyState.None -> L("还没填 API key")
            KeyState.Checking -> L("正在检查…")
            KeyState.Invalid -> L("这个 Ling key 无效，看看有没有复制全，或换一个新的")
            KeyState.Unreachable -> L("连不上 Ling，检查一下网络")
            KeyState.Ok -> AIKey.masked(k ?: "") + " · " + L("正常")
            else -> AIKey.masked(k ?: "")
        }
        page.addView(ui.group(listOf(ui.listRow(L("Ling key"), keyStatus, leading = ui.icon(R.drawable.i_lock, 22, Palette.body)) { editKey() })))

        page.addView(ui.sectionLabel(L("语言")))
        val targets = listOf("system" to L("跟随系统")) + Languages.targets.map { it.code to it.name }
        page.addView(ui.group(listOf(
            choiceRow(L("翻译成"), targets, s.target) { s.target = it; app.saveSettings() },
            choiceRow(L("纪要语言"), listOf("system" to L("和字幕一样")) + Languages.targets.map { it.code to it.name }, s.notesLanguage) { s.notesLanguage = it; app.saveSettings() },
            choiceRow(L("界面语言"), listOf("system" to L("跟随系统"), "zh-Hans" to "简体中文", "en" to "English", "ja" to "日本語", "ko" to "한국어"), s.uiLanguage) {
                s.uiLanguage = it; app.saveSettings(); app.loadStrings(); shown = null; recreate()
            })))

        page.addView(ui.sectionLabel(L("在其他应用上")))
        val rows = mutableListOf<View>(
            switchRow(L("悬浮窗"), L("切到其他应用时，在上面显示字幕或纪要"), s.overlay) { s.overlay = it; app.saveSettings(); if (!it) app.overlay.hide() },
            choiceRow(L("样式"), listOf("notes" to L("实时纪要"), "subtitles" to L("字幕条")), s.view) { app.setView(it) },
            switchRow(L("共享屏幕时让对方看到"), L("关闭时，截图和录屏里看不到悬浮窗"), s.showInCapture) { s.showInCapture = it; app.saveSettings(); app.overlay.rebuild() })
        if (!app.canOverlay) rows.add(0, ui.listRow(L("开启“显示在其他应用上层”"), null, leading = ui.icon(R.drawable.i_pip, 22, Palette.link)) {
            OverlayGuideActivity.open(this, direct = true)
        })
        page.addView(ui.group(rows))

        page.addView(ui.sectionLabel(L("其他")))
        page.addView(ui.group(listOf(
            choiceRow(L("纪要和翻译模型"), listOf("Ling-3.1-flash" to "Ling-3.1-flash", "Ling-3.0-flash" to "Ling-3.0-flash"), s.model) { s.model = it; app.saveSettings() },
            ui.listRow(L("重看新手引导")) { startActivity(Intent(this, OnboardingActivity::class.java)) }) +
            // Android 13+ can add the tile from here; older versions edit Quick Settings by hand.
            if (android.os.Build.VERSION.SDK_INT >= 33) listOf(ui.listRow(L("添加到快捷设置"), L("下拉通知栏，一键开始或结束听")) { addTile() }) else emptyList()))
        val version = packageManager.getPackageInfo(packageName, 0).versionName
        page.addView(ui.helper("${L("知了")} $version · Android").apply { gravity = Gravity.CENTER; setPadding(0, ui.dp(12), 0, 0) })
    }

    private fun addTile() {
        if (android.os.Build.VERSION.SDK_INT < 33) return
        getSystemService(android.app.StatusBarManager::class.java).requestAddTileService(
            android.content.ComponentName(this, ListenTile::class.java), L("知了"),
            android.graphics.drawable.Icon.createWithResource(this, R.drawable.ic_notification), mainExecutor) { result ->
            Log.d("tile: add request result $result")
        }
    }

    /// A row showing its current value; tapping lists the choices.
    private fun choiceRow(label: String, options: List<Pair<String, String>>, selected: String, changed: (String) -> Unit) =
        ui.listRow(label, trailing = value(options.firstOrNull { it.first == selected }?.second ?: selected)) {
            AlertDialog.Builder(this).setTitle(label)
                .setSingleChoiceItems(options.map { it.second }.toTypedArray(), options.indexOfFirst { it.first == selected }) { d, i ->
                    d.dismiss(); changed(options[i].first); shown = null; build()
                }.setNegativeButton(L("取消"), null).show()
        }

    /// A row with a switch; the whole row toggles it.
    private fun switchRow(label: String, helper: String, on: Boolean, changed: (Boolean) -> Unit): LinearLayout {
        val sw = Switch(this).apply {
            isChecked = on
            val states = arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf())
            thumbTintList = ColorStateList(states, intArrayOf(android.graphics.Color.WHITE, Palette.secondary))
            trackTintList = ColorStateList(states, intArrayOf(Palette.ink, Palette.outline))
            // The framework track is drawn faded; SRC paints the tint at full strength.
            trackTintMode = android.graphics.PorterDuff.Mode.SRC
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            isClickable = false
        }
        lateinit var row: LinearLayout
        row = ui.listRow(label, helper, trailing = sw, chevron = false) {
            sw.isChecked = !sw.isChecked
            changed(sw.isChecked)
            row.stateDescription = if (sw.isChecked) L("已开启") else L("已关闭")
        }
        row.stateDescription = if (on) L("已开启") else L("已关闭")
        row.accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(host: View, info: android.view.accessibility.AccessibilityNodeInfo) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = "android.widget.Switch"; info.isCheckable = true; info.isChecked = sw.isChecked
            }
        }
        return row
    }

    /// Change or remove the key: a dialog with the field, 粘贴, and 删除 Ling key.
    private fun editKey() {
        val app = cicada
        val status = ui.helper("")
        lateinit var dialog: AlertDialog
        lateinit var submit: () -> Unit
        val box = ui.keyField { submit() }
        val field = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = ui.rounded(Palette.card, 14, Palette.outline, 2)
            setPadding(ui.dp(14), ui.dp(4), ui.dp(4), ui.dp(4))
            addView(box, ui.weight())
            addView(ui.button(L("粘贴"), "quiet", R.drawable.i_clipboard, height = 44) { paste(box) })
        }
        submit = submit@{
            val text = box.text.toString().trim()
            if (!text.startsWith("sk-")) { status.text = L("要粘贴 sk- 开头的 Ling key"); status.setTextColor(Palette.link); return@submit }
            if (!app.key.save(text)) { status.text = L("保存失败"); return@submit }
            app.ling.keyChanged()
            app.background.execute { app.ling.check() }
            dialog.dismiss()
        }
        val body = ui.stack(10, field, status).apply { setPadding(ui.dp(24), ui.dp(8), ui.dp(24), 0) }
        dialog = AlertDialog.Builder(this).setTitle(L("更换 Ling key")).setView(body)
            .setPositiveButton(L("保存"), null)
            .setNegativeButton(L("取消"), null)
            .setNeutralButton(L("删除 Ling key")) { _, _ -> app.key.remove(); app.ling.keyChanged() }
            .create()
        dialog.setOnShowListener { dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { submit() } }
        dialog.show()
        box.requestFocus()
    }

    companion object {
        fun paste(box: android.widget.EditText) {
            val clip = box.context.getSystemService(ClipboardManager::class.java).primaryClip
            val text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(box.context)?.toString()?.trim()
            if (!text.isNullOrEmpty()) {
                box.setText(text); box.setSelection(text.length)
                // A secret: don't leave it on the clipboard for the next app (or the keyboard's history).
                if (text.startsWith("sk-")) try { box.context.getSystemService(ClipboardManager::class.java).clearPrimaryClip() } catch (_: Exception) {}
            }
        }
    }
}
