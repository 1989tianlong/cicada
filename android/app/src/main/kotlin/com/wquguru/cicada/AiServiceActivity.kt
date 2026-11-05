package com.wquguru.cicada

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import cicada.AICheck
import cicada.AIConfig
import cicada.AIKey
import cicada.Model
import cicada.Provider
import cicada.Providers
import cicada.Strings
import cicada.Strings.L
import cicada.Strings.LF

/// 设置 › AI 服务 (AISettings.swift, the design's Android page): which service, its key and how
/// the check went, what works with it (现在能用的, with 听对方 first: on the ports the service
/// hears), and the models, each a row that opens its choices. The recommended ones are already
/// chosen, so most people never open those.
class AiServiceActivity : Activity() {
    private lateinit var ui: Ui
    private lateinit var page: LinearLayout
    private var unobserve: (() -> Unit)? = null
    private var shown: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ui = Ui(this)
        page = ui.stack(0).apply { setPadding(ui.dp(16), ui.dp(4), ui.dp(16), ui.dp(24)) }
        setContentView(ui.screen(this, L("AI 服务"), back = true, ground = Palette.ground, body = page))
    }

    override fun onResume() { super.onResume(); unobserve = cicada.observe(::build); shown = null; build() }
    override fun onPause() { super.onPause(); unobserve?.invoke(); unobserve = null }

    private fun value(text: String) = ui.text(text, 15f, Palette.secondary, lines = 1)

    private fun build() {
        val app = cicada
        val ling = app.ling
        val c = ling.config()
        val p = c.provider
        val key = listOf(ling.keyState, ling.currentKey()?.takeLast(4), ling.aiCheck.summary, ling.aiCheck.at?.let { it / 60_000 }, ling.lastVoice?.first,
                         ling.textCatalog.size, ling.hearCatalog.size, app.settings.toJson(), Strings.language).joinToString("|")
        if (key == shown) return
        shown = key
        page.removeAllViews()
        val name = name(p)

        // The service, its key (and a custom service's address).
        page.addView(ui.sectionLabel(L("服务")))
        val rows = mutableListOf<View>(choiceRow(L("服务"), Providers.ALL.map { it.id to label(it) }, p.id) { app.setAiProvider(it) })
        if (p.id == "custom") rows.add(fieldRow(L("地址"), app.settings.aiCustomBase, "https://api.example.com/v1", null) {
            app.settings.aiCustomBase = it; app.settings.save(); app.aiChanged()
        })
        val k = ling.currentKey()
        val title = when {
            k == null -> if (p.id == "custom") L("还没填好") else L("还没填 API key")
            k.isEmpty() -> L("本机服务，不用 key")
            else -> AIKey.masked(k)
        }
        val trailing = if (!k.isNullOrEmpty()) ui.text(L("更换"), 15f, Palette.link, bold = true, lines = 1) else null
        rows.add(ui.listRow(title, status(app), leading = ui.icon(R.drawable.i_lock, 22, Palette.body), trailing = trailing, chevron = k == null) {
            editKey(this, ui)
        })
        if (k == null && p.site != null) rows.add(ui.listRow(LF("打开 %@", name), null, trailing = ui.icon(R.drawable.i_external, 18, Palette.link), chevron = false) {
            try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(p.site))) } catch (_: Exception) {}
        })
        // Where it broke and the one thing that fixes it; all passed folds into the key's line.
        val check = ling.aiCheck
        if (k != null && AiCheckViews.showSteps(check)) rows.add(AiCheckViews.steps(this, ui, recheck = false) { editKey(this, ui) })
        check.balanceLine(name)?.let { low ->
            // Wraps: English runs two lines.
            rows.add(LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                minimumHeight = ui.dp(56)
                setPadding(ui.dp(16), ui.dp(8), ui.dp(8), ui.dp(8))
                setBackgroundColor(AiCheckViews.warnPale)
                addView(ui.text(low, 15f, AiCheckViews.warn), ui.weight())
                addView(ui.textButton(L("去充值")) { AiCheckViews.open(this@AiServiceActivity, AiCheckViews.topUp(p)) })
            })
        }
        if (k != null) rows.add(ui.listRow(if (check.running) L("正在检查…") else L("重新检查"), null,
            leading = ui.icon(R.drawable.i_restore, 22, if (check.running) Palette.tertiary else Palette.body), chevron = false,
            onClick = if (check.running) null else ({ app.recheck() })))
        page.addView(ui.group(rows))
        val host = c.base?.let { Uri.parse(it).host } ?: L("你填的地址")
        page.addView(ui.helper(LF("加密存在这台手机上，只发给 %@（%@）", name, host)).apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), 0) })

        page.addView(ui.sectionLabel(L("现在能用的")))
        page.addView(ui.group(usesRows(app, c, name)))

        page.addView(ui.sectionLabel(L("自己选模型")))
        page.addView(ui.group(modelRows(app, c)))
        val sent = if (p.id == "custom") host else name
        val foot = (if (c.isLing) "" else L("按所选模型计费。")) + LF("听的时候，声音会发给 %@。", sent)
        page.addView(ui.helper(foot).apply { setPadding(ui.dp(16), ui.dp(12), ui.dp(16), 0) })
    }

    /// 现在能用的 (AISettings.swift › usage): what each part of the app uses with this service.
    private fun usesRows(app: CicadaApp, c: AIConfig, name: String): List<View> {
        val ling = app.ling
        // Only what the last result supports: when the service can't be reached (or the key
        // fails) nothing says "用 ZenMux"; a deaf hear model greys only what hears.
        val reason = ling.aiCheck.failure?.reason
        val down = ling.hasKey && reason in listOf(AICheck.Reason.Unreachable, AICheck.Reason.BadAddress, AICheck.Reason.InvalidKey,
                                                   AICheck.Reason.MgmtKey, AICheck.Reason.NoCredit)
        val on = ling.usable && !down
        val uses = LF("用 %@", name)
        val needKey = Triple(L("需要 key"), 0, L("填好 key 后可用"))
        val off = Triple(L("暂不可用"), 0, if (reason == AICheck.Reason.Unreachable) LF("连上 %@ 后可用", name) else L("换好 key 后可用"))
        val notReady = if (down) off else needKey
        val deaf = Triple(L("还不能用"), 0, LF("%@ 听不了声音。", short(c.hearModel)))
        val hear = when {
            !on -> notReady
            ling.hears == false -> deaf
            c.isLing -> Triple(uses, 1, L("Ming 一次识别并翻译"))
            else -> Triple(uses, 1, short(c.hearModel) + " · " + L("比 Ling 晚 1–2 秒出字"))
        }
        val notes = when {
            !on -> notReady
            reason == AICheck.Reason.NoModel -> Triple(L("暂不可用"), 0, L("换一个模型后可用"))
            reason == AICheck.Reason.NoJSON -> Triple(L("暂不可用"), 0, L("这个服务不支持 JSON"))
            ling.aiCheck.busy -> Triple(L("很忙"), 2, L("会自动重试，纪要可能晚一点"))
            else -> Triple(uses, 1, L("会中每 45 秒更新"))
        }
        val voice = cloudVoice(app)
        val say = when {
            !on -> notReady
            ling.hears == false -> deaf
            voice != null && ling.lastVoice?.first == false -> Triple(uses, 1, L("上次同传没出声，用了手机的声音"))
            voice != null && ling.lastVoice?.first == true -> Triple(uses, 1, LF("%@ 的声音读给对方", voice) + " · " + L("上次同传时正常"))
            else -> Triple(uses, 1, if (voice != null) LF("%@ 的声音读给对方", voice) else L("手机的声音读给对方"))
        }
        val rows = mutableListOf(L("听对方") to hear, L("实时纪要") to notes, L("我说 · 面对面") to say)
        if (!c.isLing) rows.add(L("你自己的声音") to Triple(L("只有 Ling"), 0, L("换用 Ling 才有")))
        return rows.map { (title, u) ->
            val (tag, style, note) = u
            val (fg, bg) = when (style) { 1 -> Palette.ink to Palette.selected; 2 -> AiCheckViews.warn to AiCheckViews.warnPale; else -> Palette.secondary to Palette.ground }
            ui.listRow(title, note, trailing = ui.badge(tag, fg = fg, bg = bg), chevron = false)
        }
    }

    /// 自己选模型: the hear, text and voice models; Ling's hear model is Ming, always.
    private fun modelRows(app: CicadaApp, c: AIConfig): List<View> {
        val p = c.provider
        val s = app.settings
        if (p.id == "ling") return listOf(
            choiceRow(L("文字模型"), p.textModels.map { it.id to it.id }, c.textModel, helper = L("3.1 更准；3.0 更快、更省")) { app.setAiModel("text", it) },
            ui.listRow(L("听的模型"), L("Ming 一次识别并翻译"), trailing = value(c.hearModel), chevron = false))
        if (p.id == "custom") return listOf(
            fieldRow(L("文字模型"), s.aiModels["custom"].orEmpty(), L("例如 qwen3:14b"), L("纪要和整句翻译")) { app.setAiModel("text", it) },
            fieldRow(L("听的模型"), s.aiHearModels["custom"].orEmpty(), L("例如 qwen3-omni"), L("要能输入音频：听对方和“我说”都用它")) { app.setAiModel("hear", it) },
            fieldRow(L("声音模型"), s.aiVoiceModels["custom"].orEmpty(), L("例如 kokoro"), L("需支持 /audio/speech；不填就用手机的声音")) { app.setAiModel("voice", it) },
            fieldRow(L("声音"), s.aiCustomVoice, L("例如 af_heart"), null) { s.aiCustomVoice = it; s.save(); app.aiChanged(check = false) })
        val rows = mutableListOf(
            modelRow(L("听的模型"), L("听对方和“我说”都用它"), p.hearModels, app.ling.hearCatalog, c.hearModel) { app.setAiModel("hear", it) },
            modelRow(L("文字模型"), L("纪要和整句翻译"), p.textModels, app.ling.textCatalog, c.textModel) { app.setAiModel("text", it) })
        if (p.hasVoices) rows.add(modelRow(L("声音模型"), L("面对面时读给对方"), p.voiceModels, emptyList(), c.voiceModel ?: "") { app.setAiModel("voice", it) })
        return rows
    }

    /// Recommended models first, with why, then everything else the service lists.
    private fun modelRow(label: String, helper: String, recommended: List<Model>, listed: List<String>, current: String, pick: (String) -> Unit): View {
        val options = recommended.map { it.id to (it.id + if (it.note.isNotEmpty()) " · " + L(it.note) else "") }.toMutableList()
        for (id in listed) if (options.none { it.first == id }) options.add(id to id)
        if (current.isNotEmpty() && options.none { it.first == current }) options.add(current to current)
        return ui.listRow(label, helper, trailing = value(short(current))) {
            ui.choose(this, label, options, current) { pick(it) }
        }
    }

    private fun choiceRow(label: String, options: List<Pair<String, String>>, selected: String, helper: String? = null, changed: (String) -> Unit) =
        ui.listRow(label, helper, trailing = value(options.firstOrNull { it.first == selected }?.second ?: selected)) {
            ui.choose(this, label, options, selected) { changed(it) }
        }

    /// A typed value (a custom service's address and models): the row shows it, tapping edits it.
    private fun fieldRow(label: String, current: String, hint: String, helper: String?, save: (String) -> Unit) =
        ui.listRow(label, helper, trailing = value(current.ifEmpty { L("未填") }.let(::short))) {
            ui.input(this, label, current, helper = helper, hint = hint) { if (it != current) save(it) }
        }

    companion object {
        fun name(p: Provider) = if (p.id == "custom") L(p.name) else p.name
        fun label(p: Provider) = if (p.id == "ling") "Ling" + L("（推荐）") else name(p)

        /// A model id without its vendor ("qwen3.8-omni-flash"): the rows are narrow.
        fun short(id: String) = id.substringAfterLast('/')

        /// The service's own voice for 我说 (Gemini on OpenRouter and ZenMux), or null: the phone's.
        fun cloudVoice(app: CicadaApp): String? {
            val c = app.ling.config()
            if (!app.ling.speaks || c.isLing) return null
            val m = c.voiceModel ?: return null
            return if ("gemini" in m.lowercase()) "Gemini" else short(m)
        }

        /// How the service is doing, under its key; null when there's nothing to say.
        fun status(app: CicadaApp): String? {
            val ling = app.ling
            val check = ling.aiCheck
            if (!ling.hasKey) return null
            if (check.running) return L("正在检查…")
            // Named after the step that failed: a missing model is not a connection problem.
            check.failure?.takeIf { it.reason != AICheck.Reason.Busy }?.let {
                return when (it.step) {
                    AICheck.StepID.Reach -> L("暂时连不上")
                    AICheck.StepID.Key -> L("这个 key 用不了")
                    AICheck.StepID.Text, AICheck.StepID.Hear -> L("模型用不了")
                }
            }
            if (check.busy) return LF("%@ 现在很忙", ling.serviceName)
            return AiCheckViews.summary(check)
        }

        /// The 设置 row's line: connected (and what that costs in delay), or what's wrong.
        fun summary(app: CicadaApp): String {
            val ling = app.ling
            val k = ling.currentKey() ?: return L("还没填 API key")
            val check = ling.aiCheck
            if (check.failure != null || check.busy) return ling.checkMessage() ?: status(app) ?: AIKey.masked(k)
            if (ling.config().isLing) return AIKey.masked(k) + " · " + L("正常")
            return status(app) ?: L("已连接")
        }

        /// The prefix says whose key it is: a management key can't call models, and another
        /// service's key goes there with one tap (改用 %@ into `into`), never a silent switch.
        /// True when the key isn't for `service`: don't save it here.
        fun keyHint(ui: Ui, key: String, service: String, status: android.widget.TextView, into: LinearLayout, switched: () -> Unit): Boolean {
            val (owner, management) = AICheck.owner(key) ?: return false
            if (management) {
                status.text = L("这是 ZenMux 的管理 key，不能用来调用模型。请粘贴 sk-payg 开头的 key。")
            } else if (owner != service) {
                val name = Providers.named(owner).name
                status.text = LF("这是 %@ 的 key。", name)
                into.addView(ui.button(LF("改用 %@", name), "primary", height = 44) {
                    into.removeAllViews()
                    ui.context.cicada.switchService(owner, key)
                    switched()
                })
            } else return false
            status.setTextColor(Palette.link)
            status.setCompoundDrawablesRelative(null, null, null, null)
            status.announceForAccessibility(status.text)
            return true
        }

        /// Change or remove the key of the service in use: a sheet with the field, 粘贴, and 删除.
        fun editKey(activity: Activity, ui: Ui) {
            val app = activity.cicada
            val p = app.ling.provider
            val isLing = p.id == "ling"
            val status = ui.helper("")
            lateinit var dialog: android.app.Dialog
            lateinit var submit: () -> Unit
            val box = ui.keyField { submit() }
            val field = LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                background = ui.rounded(Palette.ground, 16)
                setPadding(ui.dp(16), ui.dp(4), ui.dp(4), ui.dp(4))
                addView(box, ui.weight())
                addView(ui.button(L("粘贴"), "white", R.drawable.i_clipboard, height = 44) { SettingsActivity.paste(box) })
            }
            val other = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_HORIZONTAL }
            submit = submit@{
                val text = box.text.toString().trim()
                other.removeAllViews()
                if (keyHint(ui, text, p.id, status, other) { dialog.dismiss() }) return@submit
                if (isLing && !text.startsWith("sk-")) { status.text = L("要粘贴 sk- 开头的 Ling key"); status.setTextColor(Palette.link); return@submit }
                if (text.isEmpty()) return@submit
                if (!app.key.save(text)) { status.text = L("保存失败"); return@submit }
                app.aiChanged()
                dialog.dismiss()
            }
            val body = ui.stack(10, field, status, other,
                LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    addView(ui.button(L("取消"), "quiet") { dialog.dismiss() }, ui.weight())
                    addView(ui.button(L("保存"), "primary") { submit() }, ui.weight().apply { leftMargin = ui.dp(10) })
                })
            if (app.key.read() != null)
                body.addView(ui.textButton(if (isLing) L("删除 Ling key") else L("删除"), Palette.link) { app.key.remove(); app.aiChanged(); dialog.dismiss() })
            dialog = ui.sheet(activity, if (isLing) L("更换 Ling key") else LF("粘贴 %@ 的 key", name(p)), body)
            dialog.window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE or android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            dialog.show()
            box.requestFocus()
        }
    }
}
