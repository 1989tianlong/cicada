package com.wquguru.cicada

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.TextView
import cicada.Languages
import cicada.Log
import cicada.NotesEngine
import cicada.Session
import cicada.SessionStore
import cicada.Strings.L
import cicada.Strings.LF

/// 会议记录: every meeting, newest first, grouped by day; search covers titles, notes and what
/// was said; chips narrow to meetings with notes or to-dos.
class RecordsActivity : Activity() {
    private lateinit var ui: Ui
    private lateinit var list: FrameLayout
    private lateinit var chips: LinearLayout
    private var query = ""
    private var filter = "all"
    private var shown: String? = null
    private var unobserve: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ui = Ui(this)
        filter = savedInstanceState?.getString("filter") ?: "all"
        val search = EditText(this).apply {
            id = R.id.search
            hint = L("搜索会议、人名、词语")
            setSingleLine()
            background = null
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setPadding(0, 0, 0, 0)
            imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
                override fun afterTextChanged(s: Editable?) { query = s.toString().trim(); render() }
            })
        }
        val searchBox = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = ui.rounded(Palette.card, 26)
            minimumHeight = ui.dp(52)
            setPadding(ui.dp(16), 0, ui.dp(16), 0)
            addView(ui.icon(R.drawable.i_search, 20, Palette.secondary))
            addView(search, ui.weight().apply { leftMargin = ui.dp(12) })
        }
        chips = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        list = FrameLayout(this)
        val body = ui.stack(12, searchBox, HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled = false; addView(chips) }, list)
            .apply { setPadding(ui.dp(16), ui.dp(4), ui.dp(16), ui.dp(32)) }
        setContentView(ui.screen(this, L("会议记录"), back = true, ground = Palette.ground, body = body))
    }

    override fun onResume() { super.onResume(); unobserve = cicada.observe(::render); shown = null; render() }
    override fun onPause() { super.onPause(); unobserve?.invoke(); unobserve = null }
    // The search text is kept by the field itself (it has an id); the filter by us.
    override fun onSaveInstanceState(out: Bundle) { super.onSaveInstanceState(out); out.putString("filter", filter) }

    private fun matches(s: Session): Boolean {
        if (filter == "notes" && (s.notes == null || s.notes!!.isEmpty)) return false
        if (filter == "todo" && (s.notes?.todos?.isEmpty() != false)) return false
        if (query.isEmpty()) return true
        val q = query.lowercase()
        return SessionStore.displayTitle(s).lowercase().contains(q) ||
            s.notes?.let { n -> (n.summary + n.topics.joinToString { it.title + it.points.joinToString() } + n.terms.joinToString { it.name }).lowercase().contains(q) } == true ||
            s.lines.any { it.src.lowercase().contains(q) || it.dst?.lowercase()?.contains(q) == true }
    }

    private fun render() {
        val app = cicada
        val sessions = app.store.all().filter(::matches)
        val liveId = if (app.listen.listening) app.listen.sessionId else null
        val key = "$query|$filter|$liveId|" + sessions.joinToString { "${it.id}:${SessionStore.displayTitle(it)}:${it.lines.size}:${it.endedAt}:${it.notes?.todos?.size}" }
        if (key == shown) return
        shown = key
        chips.removeAllViews()
        listOf("all" to L("全部"), "notes" to L("有纪要"), "todo" to L("有待办")).forEachIndexed { i, (v, label) ->
            chips.addView(ui.chip(label, filter == v) { filter = v; render() }, LinearLayout.LayoutParams(-2, -2).apply { if (i > 0) leftMargin = ui.dp(8) })
        }
        list.removeAllViews()
        if (sessions.isEmpty()) {
            list.addView(ui.helper(if (app.store.all().isEmpty()) L("还没有会议记录") else L("没有找到相关会议")).apply { setPadding(ui.dp(4), ui.dp(12), 0, 0) })
            return
        }
        val column = ui.stack(8)
        val days = LinkedHashMap<String, MutableList<Session>>()
        for (s in sessions) days.getOrPut(MainActivity.day(s.startedAt)) { mutableListOf() }.add(s)
        for ((day, items) in days) {
            column.addView(ui.sectionLabel(day))
            column.addView(ui.group(items.map { MainActivity.recordRow(this, ui, it, it.id == liveId) }))
        }
        list.addView(column)
    }
}

/// One meeting: 纪要 (or a way to write them) and the bilingual 文字记录, on one white sheet.
class RecordActivity : Activity() {
    private lateinit var ui: Ui
    private lateinit var id: String
    // A ListView, so a two-hour meeting's 1,500 lines are drawn as they scroll into view
    // rather than all at once (that froze the screen for over a second).
    private lateinit var list: android.widget.ListView
    private lateinit var header: FrameLayout
    private lateinit var footer: FrameLayout
    private val adapter = LinesAdapter()
    private var tab = 0
    private var shown: String? = null
    private var unobserve: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ui = Ui(this)
        id = intent.getStringExtra("id") ?: run { finish(); return }
        tab = savedInstanceState?.getInt("tab") ?: 0
        header = FrameLayout(this); footer = FrameLayout(this)
        list = android.widget.ListView(this).apply {
            divider = null
            selector = android.graphics.drawable.ColorDrawable(0)
            isVerticalScrollBarEnabled = false
            setPadding(ui.dp(20), 0, ui.dp(20), ui.dp(40))
            clipToPadding = false
            addHeaderView(header, null, false)
            addFooterView(footer, null, false)
            adapter = this@RecordActivity.adapter
        }
        lateinit var more: View
        more = ui.iconButton(R.drawable.i_more, L("更多"), Palette.ink) { menu(more) }
        setContentView(ui.screen(this, null, back = true, ground = Palette.card, body = list, scroll = false, actions = listOf(
            ui.iconButton(R.drawable.i_share, L("分享"), Palette.ink) { cicada.store.get(id)?.let(::share) }, more)))
    }

    override fun onResume() { super.onResume(); unobserve = cicada.observe(::render); shown = null; render() }
    override fun onPause() { super.onPause(); unobserve?.invoke(); unobserve = null }

    private fun render() {
        val app = cicada
        val s = app.store.get(id) ?: run { if (app.store.loaded) finish(); return }
        val generating = app.notes.generating == id
        val key = listOf(SessionStore.displayTitle(s), s.lines.size, s.notes?.updatedAt, generating, app.notes.status, tab, s.lines.lastOrNull()?.dst).joinToString("|")
        if (key == shown) return
        shown = key
        val top = ui.stack(0).apply { setPadding(0, ui.dp(4), 0, 0) }
        top.addView(ui.title(SessionStore.displayTitle(s), 24f))
        val meta = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val first = s.lines.firstOrNull()
        listOfNotNull("${MainActivity.day(s.startedAt)} ${MainActivity.time(s.startedAt)}", Languages.clock(s.durationSeconds),
                      first?.let { "${NotesViews.languageName(it.srcLang)} → ${NotesViews.languageName(it.dstLang)}" })
            .forEachIndexed { i, t -> meta.addView(ui.badge(t, Palette.body, Palette.ground, size = 13f), LinearLayout.LayoutParams(-2, -2).apply { if (i > 0) leftMargin = ui.dp(6) }) }
        top.addView(HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled = false; addView(meta) }, ui.lp(top = 12))
        top.addView(ui.tabs(listOf(L("纪要"), "${L("文字记录")} · ${s.lines.size} ${L("句")}"), tab) { tab = it; render() }, ui.lp(top = 18))
        top.addView(ui.divider())
        header.removeAllViews(); header.addView(top)

        val bottom = ui.stack(0)
        if (tab == 0) {
            val n = s.notes
            when {
                n != null && !n.isEmpty ->
                    bottom.addView(NotesViews.notesBody(ui, n, NotesEngine.State.Idle, false).apply { (getChildAt(0) as? LinearLayout)?.visibility = View.GONE }, ui.lp(top = 18))
                generating -> bottom.addView(ui.text(L("正在整理纪要…"), 15f, Palette.secondary), ui.lp(top = 24))
                else -> {
                    if (app.notes.status == NotesEngine.State.Failed) bottom.addView(ui.text(L("纪要没生成出来，稍后再试"), 15f, Palette.link), ui.lp(top = 24))
                    val live = app.listen.listening && app.listen.sessionId == id
                    if (!live) bottom.addView(ui.button(L("生成纪要"), "primary") { app.notes.generate(id) }, ui.lp(top = 20))
                }
            }
        }
        footer.removeAllViews(); footer.addView(bottom)
        adapter.show(if (tab == 1) app.store.lines(id) else emptyList())
    }

    /// One transcript line per row: time, what was said, its translation. Rows are reused.
    private inner class LinesAdapter : android.widget.BaseAdapter() {
        private var lines: List<cicada.TranscriptLine> = emptyList()
        fun show(l: List<cicada.TranscriptLine>) { lines = l; notifyDataSetChanged() }
        override fun getCount() = lines.size
        override fun getItem(i: Int) = lines[i]
        override fun getItemId(i: Int) = i.toLong()

        override fun getView(i: Int, convertView: View?, parent: android.view.ViewGroup?): View {
            val row = convertView as? LinearLayout ?: LinearLayout(this@RecordActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, ui.dp(18), 0, 0)
                addView(ui.text("", 12f, Palette.link, bold = true), LinearLayout.LayoutParams(-2, -2).apply { topMargin = ui.dp(2); rightMargin = ui.dp(12) })
                addView(ui.stack(3, ui.text("", 15f, Palette.ink).apply { setLineSpacing(0f, 1.3f) }, ui.text("", 14f, Palette.secondary).apply { setLineSpacing(0f, 1.3f) }), ui.weight())
            }
            val l = lines[i]
            (row.getChildAt(0) as TextView).text = Languages.clock(l.t)
            val texts = row.getChildAt(1) as LinearLayout
            (texts.getChildAt(0) as TextView).text = l.src
            val dst = texts.getChildAt(1) as TextView
            val translated = !l.dst.isNullOrEmpty() && l.dst != l.src
            dst.visibility = if (translated) View.VISIBLE else View.GONE
            dst.text = l.dst ?: ""
            return row
        }
    }

    override fun onSaveInstanceState(out: Bundle) { super.onSaveInstanceState(out); out.putInt("tab", tab) }

    private fun menu(anchor: View) {
        val s = cicada.store.get(id) ?: return
        PopupMenu(this, anchor).apply {
            menu.add(0, 1, 0, L("重命名")); menu.add(0, 2, 1, L("导出 Markdown")); menu.add(0, 3, 2, L("删除"))
            setOnMenuItemClickListener { when (it.itemId) { 1 -> rename(s); 2 -> export(s); else -> delete(s) }; true }
            show()
        }
    }

    /// The Markdown export through the share sheet (chat apps, notes apps, Files…).
    private fun share(s: Session) {
        val send = Intent(Intent.ACTION_SEND).setType("text/plain")
            .putExtra(Intent.EXTRA_SUBJECT, SessionStore.displayTitle(s))
            .putExtra(Intent.EXTRA_TEXT, SessionStore.markdown(s))
        startActivity(Intent.createChooser(send, L("分享")))
    }

    /// Saves the Markdown as a file where the user picks (the system file picker).
    private fun export(s: Session) {
        val name = SessionStore.displayTitle(s).replace(Regex("[\\\\/:*?\"<>|]"), "-") + ".md"
        @Suppress("DEPRECATION")
        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("text/markdown").putExtra(Intent.EXTRA_TITLE, name), 7)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val uri = data?.data ?: return
        val s = cicada.store.get(id) ?: return
        if (requestCode == 7 && resultCode == RESULT_OK) {
            try { contentResolver.openOutputStream(uri)?.use { it.write(SessionStore.markdown(s).toByteArray()) } }
            catch (e: Exception) { Log.d("export failed ${e.javaClass.simpleName}") }
        }
    }

    private fun rename(s: Session) {
        val box = EditText(this).apply { setText(MainActivity.name(s)); setSelectAllOnFocus(true); setSingleLine() }
        val frame = FrameLayout(this).apply { setPadding(ui.dp(24), ui.dp(8), ui.dp(24), 0); addView(box) }
        AlertDialog.Builder(this).setTitle(L("重命名")).setView(frame)
            .setPositiveButton(L("保存")) { _, _ -> if (box.text.toString().isNotBlank()) cicada.store.rename(s.id, box.text.toString()) }
            .setNegativeButton(L("取消"), null).show()
        box.requestFocus()
    }

    private fun delete(s: Session) {
        AlertDialog.Builder(this).setMessage(LF("删除“%@”？删掉后不能恢复", SessionStore.displayTitle(s)))
            .setPositiveButton(L("删除")) { _, _ -> cicada.store.delete(s.id); finish() }
            .setNegativeButton(L("取消"), null).show()
    }
}
