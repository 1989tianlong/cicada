package com.wquguru.cicada

import android.app.Activity
import android.content.Intent
import android.graphics.Typeface
import android.net.Uri
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import cicada.Languages
import cicada.Session
import cicada.SessionStore
import cicada.ShareClient
import cicada.ShareHit
import cicada.SharePassword
import cicada.ShareRecord
import cicada.ShareScope
import cicada.ShareStore
import cicada.Strings.L
import cicada.Strings.LF
import java.time.Instant

/// 分享…: a meeting as a link on cicada.indaloop.app (ShareViews.swift). Settings, then the server's
/// review, then the link (and its password) or what the review stopped. A meeting already shared
/// opens on its link. A bottom sheet whose content follows the step.
class ShareSheet(private val activity: Activity, private val ui: Ui, private val sessionId: String) {
    private val app = activity.cicada
    private sealed class Step {
        object Settings : Step()
        object Working : Step()
        class Blocked(val hits: List<ShareHit>, val kept: List<Int>) : Step()
        class Done(val record: ShareRecord) : Step()
        class Failed(val message: String) : Step()
    }

    // A copy: the record is read while the request runs.
    private val session: Session = Session.from(app.store.get(sessionId)!!.toJson())
    private val hasNotes = session.notes?.isEmpty == false
    private var step: Step = Step.Settings
    private var scope = if (hasNotes) ShareScope.Notes else ShareScope.Full
    private var days = 7
    private var names = false
    private var usePassword = false
    private var password = SharePassword.make()
    private var summaryInPreview = false
    private val removed = HashSet<Int>()
    private var dropNotes = false
    private var views: Int? = null
    private var confirmRevoke = false
    private var copied: String? = null
    private val box = ui.stack(0).apply { setPadding(ui.dp(8), 0, ui.dp(8), 0) }
    private lateinit var dialog: android.app.Dialog

    fun dismiss() { if (::dialog.isInitialized) dialog.dismiss() }

    fun show() {
        ShareStore.read(sessionId)?.takeIf { it.expiresAt.isAfter(Instant.now()) }?.let { step = Step.Done(it); loadViews(it) }
        dialog = ui.sheet(activity, null, ScrollView(activity).apply { addView(box); isVerticalScrollBarEnabled = false })
        render()
        dialog.setOnDismissListener { if (open === this) open = null }
        dialog.show()
        open = this
    }

    private fun set(s: Step) { step = s; confirmRevoke = false; render() }

    private fun render() {
        box.removeAllViews()
        when (val s = step) {
            Step.Settings -> settings()
            Step.Working -> working()
            is Step.Blocked -> blocked(s.hits, s.kept)
            is Step.Done -> done(s.record)
            is Step.Failed -> failed(s.message)
        }
    }

    private fun header(title: String) {
        box.addView(ui.heading(title))
        box.addView(ui.text(SessionStore.displayTitle(session), 13f, Palette.secondary, lines = 1), ui.lp(top = 2))
    }

    private fun label(text: String) = ui.text(text, 13f, Palette.secondary, medium = true)

    private fun buttons(vararg b: View) = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        b.forEachIndexed { i, v -> addView(v, ui.weight().apply { if (i > 0) leftMargin = ui.dp(10) }) }
    }

    // MARK: Settings

    private fun settings() {
        header(L("分享这场会议"))
        box.addView(label(L("内容")), ui.lp(top = 18))
        for ((value, text) in listOf(ShareScope.Notes to L("只分享纪要"), ShareScope.Full to L("纪要和双语全文"))) {
            val on = scope == value
            val enabled = value == ShareScope.Full || hasNotes
            box.addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                minimumHeight = ui.dp(48)
                setPadding(ui.dp(12), 0, ui.dp(12), 0)
                addView(ui.text(text, 16f, Palette.ink, bold = on, lines = 2), ui.weight())
                if (on) addView(ui.icon(R.drawable.i_check, 20, Palette.ink), LinearLayout.LayoutParams(ui.dp(20), ui.dp(20)))
                contentDescription = text
                isSelected = on
                accessibilityDelegate = object : View.AccessibilityDelegate() {
                    override fun onInitializeAccessibilityNodeInfo(host: View, info: android.view.accessibility.AccessibilityNodeInfo) {
                        super.onInitializeAccessibilityNodeInfo(host, info)
                        info.className = "android.widget.RadioButton"; info.isCheckable = true; info.isChecked = on
                    }
                }
                if (enabled) ui.tappable(this, 14, if (on) ui.rounded(Palette.ground, 14) else null) { scope = value; render() }
                else { alpha = 0.4f; isEnabled = false }
            }, ui.lp(top = 4))
        }
        box.addView(label(L("有效期")), ui.lp(top = 16))
        box.addView(ui.segmented(listOf("7" to L("7 天"), "30" to L("30 天"), "365" to L("1 年")), days.toString()) { days = it.toInt(); render() }, ui.lp(top = 8))
        val toggles = ui.stack(0).apply { setPadding(0, ui.dp(8), 0, 0) }
        toggles.addView(ui.switchRow(L("显示说话人名字"), null, names, titleLines = 2) { names = it }.apply { setPadding(ui.dp(4), paddingTop, ui.dp(4), paddingBottom) })
        toggles.addView(ui.switchRow(L("用密码保护"), null, usePassword, titleLines = 2) { usePassword = it; render() }.apply { setPadding(ui.dp(4), paddingTop, ui.dp(4), paddingBottom) })
        box.addView(toggles)
        lateinit var go: View
        if (usePassword) {
            val field = EditText(activity).apply {
                setText(password)
                setSingleLine()
                typeface = Typeface.MONOSPACE
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                background = ui.rounded(Palette.ground, 14)
                setPadding(ui.dp(14), 0, ui.dp(14), 0)
                minHeight = ui.dp(48)
                addTextChangedListener(object : TextWatcher {
                    override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
                    override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
                    override fun afterTextChanged(s: Editable?) {
                        password = s.toString()
                        go.alpha = if (password.length < 6) 0.4f else 1f
                        go.isEnabled = password.length >= 6
                    }
                })
            }
            box.addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(field, ui.weight())
                addView(ui.textButton(L("换一个")) { password = SharePassword.make(); field.setText(password) })
            }, ui.lp(top = 4))
        } else if (hasNotes) {
            box.addView(ui.switchRow(L("预览卡显示摘要"), null, summaryInPreview, titleLines = 2) { summaryInPreview = it }.apply { setPadding(ui.dp(4), paddingTop, ui.dp(4), paddingBottom) })
        }
        box.addView(ui.text(if (usePassword) L("建议把链接和密码分两条消息发送。") else L("内容将上传至 cicada.indaloop.app，拿到链接的人都能看。"), 13f, Palette.tertiary), ui.lp(top = 10))
        go = ui.button(L("生成链接"), "primary") { if (!usePassword || password.length >= 6) go() }
        if (usePassword && password.length < 6) { go.alpha = 0.4f; go.isEnabled = false }
        box.addView(buttons(ui.button(L("取消"), "quiet") { dialog.dismiss() }, go), ui.lp(top = 18))
    }

    private fun options() = ShareClient.Options(
        scope = scope, days = days, names = names, password = if (usePassword) password.trim() else null,
        summaryInPreview = !usePassword && summaryInPreview, removed = removed.toSet(), dropNotes = dropNotes)

    private fun go() {
        set(Step.Working)
        val o = options()
        app.background.execute {
            val out = app.share.share(session, o)
            app.main.post {
                when (out) {
                    is ShareClient.Outcome.Shared -> { copy(out.record.url, "link"); views = 0; set(Step.Done(out.record)) }
                    is ShareClient.Outcome.Blocked -> set(Step.Blocked(out.hits, out.kept))
                    is ShareClient.Outcome.Failed -> set(Step.Failed(message(out.code)))
                }
            }
        }
    }

    private fun working() {
        header(L("分享这场会议"))
        box.addView(LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            minimumHeight = ui.dp(120)
            addView(ProgressBar(activity).apply { isIndeterminate = true; indeterminateTintList = android.content.res.ColorStateList.valueOf(Palette.secondary) }, LinearLayout.LayoutParams(ui.dp(24), ui.dp(24)))
            addView(ui.text(L("正在检查有没有敏感内容…"), 15f, Palette.secondary), LinearLayout.LayoutParams(-2, -2).apply { leftMargin = ui.dp(12) })
        })
    }

    // MARK: Blocked

    private fun blocked(hits: List<ShareHit>, kept: List<Int>) {
        box.addView(LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(ui.icon(R.drawable.i_info, 20, Palette.link), LinearLayout.LayoutParams(ui.dp(20), ui.dp(20)).apply { rightMargin = ui.dp(8) })
            addView(ui.heading(L("检测到潜在敏感内容")), ui.weight())
        })
        box.addView(ui.text(L("链接尚未生成。请先核对以下内容："), 13f, Palette.secondary), ui.lp(top = 6))
        for (h in hits.take(5)) box.addView(hitRow(h, kept), ui.lp(top = 8))
        if (hits.size > 5) box.addView(ui.text(LF("还有 %lld 处", hits.size - 5), 13f, Palette.secondary), ui.lp(top = 8))
        val leftover = leftAfterRemoving(hits, kept)
        box.addView(ui.text(if (leftover) L("去掉后再检查一次；你的记录不会改动。") else L("去掉这些内容后就没有可分享的了。"), 13f, Palette.tertiary), ui.lp(top = 12))
        val back = ui.button(L("返回修改"), "quiet") { set(Step.Settings) }
        box.addView(if (leftover) buttons(back, ui.button(L("去掉这些内容后分享"), "primary") {
            removed.addAll(ShareHit.recordLines(hits, kept))
            if (hits.any { it.part == "notes" }) dropNotes = true
            go()
        }) else buttons(back), ui.lp(top = 18))
    }

    /// Would anything be left to share once the flagged parts are out? (A notes-only share whose
    /// notes were flagged has nothing; the server would refuse an empty document.)
    private fun leftAfterRemoving(hits: List<ShareHit>, kept: List<Int>): Boolean {
        val notesLeft = hasNotes && !dropNotes && hits.none { it.part == "notes" }
        if (scope != ShareScope.Full) return notesLeft
        val out = removed + ShareHit.recordLines(hits, kept)
        return notesLeft || session.lines.indices.any { it !in out && session.lines[it].src.isNotEmpty() }
    }

    private fun hitRow(h: ShareHit, kept: List<Int>): View {
        val what = h.questions.joinToString("、") { category(it) }
        val place: String
        val quote: String
        if (h.part == "notes") {
            place = L("纪要")
            quote = session.notes?.summary ?: ""
        } else {
            val lines = ShareHit.recordLines(listOf(h), kept).sorted()
            val a = lines.firstOrNull()?.let { Languages.clock(session.lines[it].t) } ?: ""
            val b = lines.lastOrNull()?.let { Languages.clock(session.lines[it].t) } ?: ""
            place = if (a == b) a else "$a–$b"
            quote = lines.firstOrNull()?.let { session.lines[it].src } ?: ""
        }
        return ui.stack(3, ui.text("$what · $place", 13f, Palette.ink, bold = true), ui.text(quote, 13f, Palette.secondary, lines = 2)).apply {
            background = ui.rounded(Palette.accentPale, 12)
            setPadding(ui.dp(12), ui.dp(10), ui.dp(12), ui.dp(10))
        }
    }

    // MARK: Done

    private fun done(r: ShareRecord) {
        header(if (copied == "link") L("链接已复制") else L("已分享"))
        box.addView(field(r.url), ui.lp(top = 16))
        box.addView(buttons(
            ui.button(if (copied == "link") L("已复制") else L("复制链接"), "quiet", height = 48) { copy(r.url, "link"); render() },
            ui.button(L("分享"), "primary", height = 48) {
                // The link alone: the password goes in a message of its own.
                activity.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
                    .putExtra(Intent.EXTRA_SUBJECT, SessionStore.displayTitle(session)).putExtra(Intent.EXTRA_TEXT, r.url), L("分享")))
            }), ui.lp(top = 10))
        r.password?.let { pw ->
            box.addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(field(pw), ui.weight())
                addView(ui.textButton(if (copied == "password") L("已复制") else L("复制密码")) { copy(pw, "password"); render() })
            }, ui.lp(top = 12))
        }
        box.addView(ui.text(status(r), 13f, Palette.secondary), ui.lp(top = 12))
        box.addView(View(activity).apply { setBackgroundColor(Palette.divider) }, LinearLayout.LayoutParams(-1, 1).apply { topMargin = ui.dp(14) })
        if (confirmRevoke) {
            box.addView(ui.text(L("取消后链接立即失效"), 15f, Palette.ink, bold = true), ui.lp(top = 14))
            box.addView(ui.text(L("已查看过的人可能留有副本。"), 13f, Palette.tertiary), ui.lp(top = 2))
            val stop = ui.button(L("取消分享"), "primary") {
                app.background.execute {
                    val ok = app.share.revoke(r, sessionId)
                    app.main.post { if (ok) dialog.dismiss() else set(Step.Failed(message("network"))) }
                }
            }
            stop.background = ui.ripple(ui.rounded(android.graphics.Color.parseColor("#B3261E"), 28), 28, dark = true)
            box.addView(buttons(ui.button(L("暂不取消"), "quiet") { confirmRevoke = false; render() }, stop), ui.lp(top = 14))
        } else {
            box.addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(ui.textButton(L("取消分享"), android.graphics.Color.parseColor("#B3261E")) { confirmRevoke = true; render() })
                addView(ui.spacer())
                addView(ui.textButton(L("在浏览器中打开")) {
                    try { activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(r.url))) } catch (_: Exception) {}
                })
            }, ui.lp(top = 6))
        }
    }

    // One line, the middle left out when long (selectable text would wrap instead); 复制 copies it whole.
    private fun field(text: String) = ui.text(text, 14f, Palette.ink).apply {
        typeface = Typeface.MONOSPACE
        isSingleLine = true
        ellipsize = android.text.TextUtils.TruncateAt.MIDDLE
        background = ui.rounded(Palette.ground, 12)
        setPadding(ui.dp(12), ui.dp(10), ui.dp(12), ui.dp(10))
    }

    private fun status(r: ShareRecord): String {
        // Ten minutes of slack: the server's clock, not the phone's, set the expiry.
        val left = maxOf(1L, Math.ceil((r.expiresAt.epochSecond - Instant.now().epochSecond - 600) / 86400.0).toLong())
        val expiry = LF("%lld 天后失效", left)
        return views?.let { expiry + " · " + LF("打开 %lld 次", it) } ?: expiry
    }

    private fun loadViews(r: ShareRecord) {
        app.background.execute {
            val s = app.share.stats(listOf(r.id))[r.id] ?: return@execute
            app.main.post {
                if (s.state != "live") { ShareStore.remove(sessionId); set(Step.Settings) }
                else { views = s.views; if (step is Step.Done) render() }
            }
        }
    }

    private fun failed(message: String) {
        header(L("没有分享出去"))
        box.addView(ui.text(message, 15f, Palette.ink), ui.lp(top = 14))
        box.addView(buttons(ui.button(L("关闭"), "quiet") { dialog.dismiss() }, ui.button(L("重试"), "primary") { go() }), ui.lp(top = 18))
    }

    private fun copy(text: String, what: String) {
        activity.getSystemService(android.content.ClipboardManager::class.java)
            .setPrimaryClip(android.content.ClipData.newPlainText(if (what == "link") "link" else "password", text))
        copied = what
    }

    companion object {
        /// The sheet on screen, for the debug commands.
        var open: ShareSheet? = null

        /// Not while the meeting is still going, nor before an import has its text.
        fun canShare(app: CicadaApp, s: Session) =
            !(s.lines.isEmpty() && (s.notes?.isEmpty ?: true)) && app.store.liveId != s.id && s.importing != true

        fun category(q: String) = when (q) {
            "credential" -> L("密码或密钥")
            "confidential" -> L("未公开的公司信息")
            "crossborder" -> L("不宜跨境传输的信息")
            "personal" -> L("个人身份信息")
            "harmful" -> L("违法或危险内容")
            else -> q
        }

        fun message(code: String) = when (code) {
            "rate_limited", "too_many_shares" -> L("分享得太频繁了，请稍后再试。")
            "review_unavailable" -> L("敏感内容检查暂时不可用，没有检查就不会分享。请稍后再试。")
            "sharing_off" -> L("分享功能暂时关闭了。")
            "update_required" -> L("请先更新知了。")
            "too_large" -> L("这场会议太长，可以只分享纪要。")
            "bad_document" -> L("这场会议没有可分享的内容。")
            "network" -> L("连不上 cicada.indaloop.app，请检查网络。")
            else -> L("服务器出了问题，请稍后再试。")
        }
    }
}
