package com.wquguru.cicada

import android.app.Activity
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/// The palette (AGENTS.md, Views.swift › Palette): ground #F3F4F6, white surfaces, ink #15171C,
/// one accent #E8552B kept for "live" (the red dot, the timer, progress). Primary buttons are ink:
/// white on the accent is under 4.5:1.
object Palette {
    val ground = Color.parseColor("#F3F4F6")
    val card = Color.WHITE
    val ink = Color.parseColor("#15171C")
    val body = Color.parseColor("#3D414A")
    val secondary = Color.parseColor("#5A5F6B")
    val tertiary = Color.parseColor("#6B7080")
    val line = Color.parseColor("#E4E6EA")
    val divider = Color.parseColor("#EEF0F2")
    val outline = Color.parseColor("#C9CCD3")
    val selected = Color.parseColor("#E9EAED")
    val accent = Color.parseColor("#E8552B")
    val accentPale = Color.parseColor("#FDEBE4")
    val link = Color.parseColor("#B33B14")
    val scrim = Color.parseColor("#EB15171C")
    val onScrim = Color.parseColor("#D7D9DE")
}

/// View builders in code (no XML layouts), Material-sized: 48dp touch targets, 56dp rows and main
/// buttons, ripples on everything tappable.
class Ui(val context: Context) {
    fun dp(v: Number): Int = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), context.resources.displayMetrics).toInt()

    fun text(text: CharSequence, size: Float = 15f, color: Int = Palette.ink, bold: Boolean = false, lines: Int = 0, medium: Boolean = false) = TextView(context).apply {
        this.text = text
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
        setTextColor(color)
        typeface = when {
            bold -> Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            medium -> Typeface.create("sans-serif-medium", Typeface.NORMAL)
            else -> Typeface.DEFAULT
        }
        if (lines > 0) { maxLines = lines; ellipsize = TextUtils.TruncateAt.END }
        setLineSpacing(0f, 1.2f)
    }

    fun title(text: String, size: Float = 28f) = text(text, size, Palette.ink, bold = true).apply { setLineSpacing(0f, 1.1f); isAccessibilityHeading = true }
    fun heading(text: String, size: Float = 17f) = text(text, size, Palette.ink, bold = true).apply { isAccessibilityHeading = true }
    fun helper(text: String, color: Int = Palette.secondary) = text(text, 13f, color)
    fun sectionLabel(text: String) = text(text, 13f, Palette.secondary, bold = true).apply { setPadding(dp(4), dp(12), 0, dp(2)); isAccessibilityHeading = true }

    fun rounded(color: Int, radius: Number, stroke: Int? = null, strokeDp: Number = 1) = GradientDrawable().apply {
        setColor(color); cornerRadius = dp(radius).toFloat()
        if (stroke != null) setStroke(dp(strokeDp), stroke)
    }

    /// Touch feedback that keeps the shape: a ripple over `base`, clipped to it.
    fun ripple(base: Drawable?, radius: Number = 0, dark: Boolean = false): Drawable {
        val mask = GradientDrawable().apply { setColor(Color.WHITE); cornerRadius = dp(radius).toFloat() }
        val tint = if (dark) 0x33FFFFFF else 0x1F15171C
        return RippleDrawable(ColorStateList.valueOf(tint), base, mask)
    }

    fun <T : View> tappable(v: T, radius: Number, base: Drawable? = null, dark: Boolean = false, onClick: () -> Unit): T = v.apply {
        background = ripple(base, radius, dark)
        isClickable = true; isFocusable = true
        setOnClickListener { onClick() }
    }

    fun card(vararg children: View, padding: Int = 20, gap: Int = 14, radius: Int = 24) = stack(gap, *children).apply {
        background = rounded(Palette.card, radius)
        setPadding(dp(padding), dp(padding), dp(padding), dp(padding))
    }

    /// A white group of rows with thin dividers (lists, settings).
    fun group(rows: List<View>, radius: Int = 20) = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        background = rounded(Palette.card, radius)
        clipToOutline = true
        rows.forEachIndexed { i, r ->
            if (i > 0) addView(View(context).apply { setBackgroundColor(Palette.divider) }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1).apply { leftMargin = dp(16) })
            addView(r, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
    }

    fun stack(gap: Int, vararg children: View) = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        children.forEachIndexed { i, c ->
            val own = c.layoutParams
            addView(c, LinearLayout.LayoutParams(own?.width ?: ViewGroup.LayoutParams.MATCH_PARENT, own?.height ?: ViewGroup.LayoutParams.WRAP_CONTENT)
                .apply { topMargin = if (i == 0) 0 else dp(gap) })
        }
    }

    fun row(gap: Int, vararg children: View) = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        children.forEachIndexed { i, c ->
            val own = c.layoutParams
            val p = if (own is LinearLayout.LayoutParams && own.weight > 0) LinearLayout.LayoutParams(own.width, own.height, own.weight)
                    else LinearLayout.LayoutParams(own?.width ?: ViewGroup.LayoutParams.WRAP_CONTENT, own?.height ?: ViewGroup.LayoutParams.WRAP_CONTENT)
            addView(c, p.apply { if (i > 0) leftMargin = dp(gap) })
        }
    }

    fun lp(top: Int = 0, width: Int = ViewGroup.LayoutParams.MATCH_PARENT, height: Int = ViewGroup.LayoutParams.WRAP_CONTENT) =
        LinearLayout.LayoutParams(width, height).apply { topMargin = dp(top) }

    fun weight(w: Float = 1f) = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, w)

    fun spacer() = View(context).apply { layoutParams = LinearLayout.LayoutParams(0, 1, 1f) }

    fun drawable(res: Int, color: Int): Drawable = context.getDrawable(res)!!.mutate().apply { setTint(color) }

    fun icon(res: Int, size: Int = 24, color: Int = Palette.body) = ImageView(context).apply {
        setImageDrawable(drawable(res, color))
        layoutParams = LinearLayout.LayoutParams(dp(size), dp(size))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    /// A 48dp round icon button with a label for TalkBack.
    fun iconButton(res: Int, label: String, color: Int = Palette.ink, size: Int = 24, dark: Boolean = false, onClick: () -> Unit) = FrameLayout(context).apply {
        contentDescription = label
        addView(ImageView(context).apply {
            setImageDrawable(drawable(res, color))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, FrameLayout.LayoutParams(dp(size), dp(size), Gravity.CENTER))
        layoutParams = LinearLayout.LayoutParams(dp(48), dp(48))
        tappable(this, 24, dark = dark, onClick = onClick)
    }

    /// Main buttons: ink (primary), a quiet grey one, or the pale accent (tonal).
    fun button(label: String, kind: String = "primary", iconRes: Int? = null, height: Int = 56, onClick: () -> Unit): LinearLayout {
        val (bg, fg) = when (kind) {
            "primary" -> Palette.ink to Color.WHITE
            "tonal" -> Palette.accentPale to Palette.link
            else -> Palette.ground to Palette.ink
        }
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            minimumHeight = dp(height)
            setPadding(dp(16), 0, dp(16), 0)
            if (iconRes != null) addView(icon(iconRes, 20, fg), LinearLayout.LayoutParams(dp(20), dp(20)).apply { rightMargin = dp(8) })
            addView(text(label, if (height >= 56) 17f else 15f, fg, bold = true, lines = 2).apply { gravity = Gravity.CENTER })
            setPadding(dp(16), dp(6), dp(16), dp(6))
            contentDescription = label
            tappable(this, 16, rounded(bg, 16), dark = kind == "primary", onClick = onClick)
        }
    }

    /// A text button (dialog-style): dark-accent text, 48dp tall.
    fun textButton(label: String, color: Int = Palette.link, onClick: () -> Unit) = text(label, 15f, color, bold = true).apply {
        gravity = Gravity.CENTER
        minHeight = dp(48)
        setPadding(dp(12), 0, dp(12), 0)
        tappable(this, 24, onClick = onClick)
    }

    fun dot(color: Int, size: Int = 8) = View(context).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(color); setSize(dp(size), dp(size)) }
        layoutParams = LinearLayout.LayoutParams(dp(size), dp(size))
    }

    /// A small rounded label (meta chips, "对方可见", "正在听").
    fun badge(label: String, fg: Int = Palette.link, bg: Int = Palette.accentPale, dot: Boolean = false, size: Float = 12f) = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        background = rounded(bg, 10)
        setPadding(dp(8), dp(3), dp(8), dp(3))
        if (dot) addView(this@Ui.dot(Palette.accent, 6), LinearLayout.LayoutParams(dp(6), dp(6)).apply { rightMargin = dp(5) })
        addView(text(label, size, fg, bold = true, lines = 1))
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
    }

    /// A square icon tile (leading icon in rows and descriptions).
    fun tile(res: Int, size: Int = 40, bg: Int = Palette.ground, fg: Int = Palette.body) = FrameLayout(context).apply {
        background = rounded(bg, size * 0.3)
        addView(ImageView(context).apply {
            setImageDrawable(drawable(res, fg))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, FrameLayout.LayoutParams(dp(size * 0.52), dp(size * 0.52), Gravity.CENTER))
        layoutParams = LinearLayout.LayoutParams(dp(size), dp(size))
    }

    /// A list row: optional leading view, title and supporting text, optional trailing view, chevron.
    fun listRow(title: CharSequence, supporting: CharSequence? = null, leading: View? = null, trailing: View? = null, chevron: Boolean = true,
                titleView: View? = null, onClick: (() -> Unit)? = null) = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(56)
        setPadding(dp(16), dp(12), dp(if (chevron) 12 else 16), dp(12))
        if (leading != null) addView(leading, LinearLayout.LayoutParams(leading.layoutParams?.width ?: ViewGroup.LayoutParams.WRAP_CONTENT, leading.layoutParams?.height ?: ViewGroup.LayoutParams.WRAP_CONTENT).apply { rightMargin = dp(14) })
        val texts = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(titleView ?: text(title, 16f, Palette.ink, lines = 1))
            if (supporting != null) addView(text(supporting, 13f, Palette.secondary), lp(top = 3))
        }
        addView(texts, weight())
        if (trailing != null) addView(trailing, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { leftMargin = dp(10) })
        if (chevron) addView(icon(R.drawable.i_chevron_right, 20, Palette.tertiary), LinearLayout.LayoutParams(dp(20), dp(20)).apply { leftMargin = dp(6) })
        contentDescription = listOfNotNull(title, supporting).joinToString("，")
        if (onClick != null) tappable(this, 0, onClick = onClick)
    }

    /// Material segmented button: choices in one outlined pill; the chosen one filled and checked.
    fun segmented(options: List<Pair<String, String>>, selected: String, onPick: (String) -> Unit) = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        background = rounded(Color.TRANSPARENT, 24, Palette.outline)
        clipToOutline = true
        options.forEachIndexed { i, (value, label) ->
            if (i > 0) addView(View(context).apply { setBackgroundColor(Palette.outline) }, LinearLayout.LayoutParams(dp(1), ViewGroup.LayoutParams.MATCH_PARENT))
            val on = value == selected
            val seg = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                if (on) addView(icon(R.drawable.i_check, 18, Palette.ink), LinearLayout.LayoutParams(dp(18), dp(18)).apply { rightMargin = dp(6) })
                addView(text(label, 15f, Palette.ink, bold = on, medium = !on, lines = 2).apply { gravity = Gravity.CENTER })
                minimumHeight = dp(48)
                setPadding(dp(8), dp(6), dp(8), dp(6))
                contentDescription = label
                accessibilityDelegate = object : View.AccessibilityDelegate() {
                    override fun onInitializeAccessibilityNodeInfo(host: View, info: android.view.accessibility.AccessibilityNodeInfo) {
                        super.onInitializeAccessibilityNodeInfo(host, info)
                        info.isCheckable = true; info.isChecked = on; info.className = "android.widget.RadioButton"
                    }
                }
                tappable(this, 0, if (on) ColorDrawable(Palette.selected) else null) { onPick(value) }
            }
            addView(seg, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
        }
    }

    /// A filter chip: outlined, or filled ink when on.
    fun chip(label: String, on: Boolean, onClick: () -> Unit) = text(label, 14f, if (on) Color.WHITE else Palette.ink, bold = on, medium = !on, lines = 1).apply {
        gravity = Gravity.CENTER
        minHeight = dp(40)
        setPadding(dp(14), 0, dp(14), 0)
        isSelected = on
        tappable(this, 10, rounded(if (on) Palette.ink else Palette.card, 10, if (on) Palette.ink else Palette.outline), dark = on, onClick = onClick)
    }

    /// Tabs with an ink underline on the chosen one.
    fun tabs(labels: List<String>, selected: Int, onPick: (Int) -> Unit) = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        labels.forEachIndexed { i, l ->
            val on = i == selected
            val tab = FrameLayout(context).apply {
                addView(text(l, 15f, if (on) Palette.ink else Palette.secondary, bold = on, medium = !on, lines = 1).apply { setPadding(0, dp(12), 0, dp(14)) },
                        FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
                addView(View(context).apply { background = rounded(if (on) Palette.ink else Color.TRANSPARENT, 2) },
                        FrameLayout.LayoutParams(dp(64), dp(3), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL))
                isSelected = on
                contentDescription = l
                tappable(this, 0) { onPick(i) }
            }
            tab.minimumHeight = dp(48)
            addView(tab, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }
    }

    /// The app icon, rounded like the launcher shows it.
    fun logo(size: Int = 64) = ImageView(context).apply {
        setImageDrawable(context.getDrawable(R.mipmap.ic_launcher))
        layoutParams = LinearLayout.LayoutParams(dp(size), dp(size))
        background = rounded(Palette.card, size * 0.23)
        clipToOutline = true
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    /// A password-style field whose keyboard "done" key does `done`.
    fun keyField(done: () -> Unit) = android.widget.EditText(context).apply {
        hint = "sk-…"; setSingleLine()
        inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
        imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_DONE
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        background = null
        setPadding(0, dp(8), 0, dp(8))
        setOnEditorActionListener { _, action, _ -> if (action == android.view.inputmethod.EditorInfo.IME_ACTION_DONE) { done(); true } else false }
    }

    fun divider() = View(context).apply {
        setBackgroundColor(Palette.line)
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1))
    }

    /// An Activity's frame: top bar (back arrow when `back`, title, actions), a body that scrolls,
    /// an optional bottom bar pinned above the gesture area. Edge-to-edge via fitsSystemWindows.
    fun screen(activity: Activity, title: String?, back: Boolean, ground: Int, actions: List<View> = emptyList(),
               bottom: View? = null, scroll: Boolean = true, body: View, center: View? = null): LinearLayout {
        activity.window.statusBarColor = ground
        activity.window.navigationBarColor = if (bottom != null) Palette.card else ground
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(ground)
            fitsSystemWindows = true
        }
        val bar = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(64)
            setPadding(dp(if (back) 4 else 20), 0, dp(4), 0)
            if (back) addView(iconButton(R.drawable.i_back, cicada.Strings.L("返回")) { activity.finish() })
            when {
                center != null -> addView(FrameLayout(context).apply { addView(center, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER)) }, weight())
                title != null -> addView(text(title, if (back) 22f else 26f, Palette.ink, bold = true, lines = 1).apply { isAccessibilityHeading = true },
                                         weight().apply { leftMargin = dp(if (back) 4 else 0) })
                else -> addView(spacer())
            }
            actions.forEach { addView(it) }
            if (back && center != null && actions.isEmpty()) addView(View(context), LinearLayout.LayoutParams(dp(48), dp(48)))
        }
        root.addView(bar)
        val content = if (scroll) ScrollView(context).apply { isVerticalScrollBarEnabled = false; addView(readable(body)) } else readable(body)
        root.addView(content, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        if (bottom != null) {
            val side = sideInset()
            if (side > 0) bottom.setPadding(bottom.paddingLeft + side, bottom.paddingTop, bottom.paddingRight + side, bottom.paddingBottom)
            root.addView(bottom)
        }
        val side = sideInset()
        if (side > 0) bar.setPadding(bar.paddingLeft + side, 0, bar.paddingRight + side, 0)
        return root
    }

    /// On a tablet or a wide window, the gutter that keeps content at a readable 640dp.
    fun sideInset(): Int {
        val w = context.resources.configuration.screenWidthDp
        return if (w > 700) dp((w - 640) / 2) else 0
    }

    private fun readable(body: View): View {
        val side = sideInset()
        if (side == 0) return body
        return FrameLayout(context).apply {
            setPadding(side, 0, side, 0)
            addView(body, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, if (body is ScrollView) ViewGroup.LayoutParams.MATCH_PARENT else ViewGroup.LayoutParams.WRAP_CONTENT))
        }
    }

    /// The pinned bottom area: white, rounded top, one or two main buttons side by side.
    fun bottomBar(vararg buttons: View) = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        background = GradientDrawable().apply { setColor(Palette.card); cornerRadii = floatArrayOf(dp(24).toFloat(), dp(24).toFloat(), dp(24).toFloat(), dp(24).toFloat(), 0f, 0f, 0f, 0f) }
        elevation = dp(8).toFloat()
        setPadding(dp(16), dp(14), dp(16), dp(14))
        buttons.forEachIndexed { i, b -> addView(b, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { if (i > 0) leftMargin = dp(12) }) }
    }
}
