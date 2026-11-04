package cicada

import java.util.Locale

/// The app's settings, in settings.json beside the records (never the Ling key: that has its own file).
class AppSettings(
    /// What subtitles translate into; "system" follows the phone's language.
    var target: String = "system",
    /// 纪要语言: the notes' language code; "system" is the same as the subtitles'.
    var notesLanguage: String = "system",
    var model: String = LingClient.DEFAULT_MODEL,
    /// "notes" (live notes, default) or "subtitles" (the subtitle bar), for the floating window.
    var view: String = "notes",
    /// 共享屏幕时让对方看到: let the floating window show up in screenshots and screen recording.
    var showInCapture: Boolean = false,
    var onboarded: Boolean = false,
    /// The UI language: "system", "zh-Hans", "en", "ja" or "ko".
    var uiLanguage: String = "system",
    /// Where listening hears from: "playback" (what the phone plays) or "mic" (面对面).
    var source: String = "playback",
    /// Whether the floating window shows while listening (it needs 显示在其他应用上层).
    var overlay: Boolean = true,
) {
    val targetCode: String get() = if (target == "system") Languages.fromSystem(Locale.getDefault().toLanguageTag()) else target
    val notesCode: String get() = if (notesLanguage == "system") targetCode else notesLanguage

    fun toJson(): Map<String, Any?> = mapOf(
        "target" to target, "notesLanguage" to notesLanguage, "model" to model, "view" to view,
        "showInCapture" to showInCapture, "onboarded" to onboarded, "uiLanguage" to uiLanguage,
        "source" to source, "overlay" to overlay,
    )

    fun save() {
        try {
            Paths.root.mkdirs()
            Paths.settings.writeText(Json.write(toJson()))
        } catch (e: Exception) { Log.d("settings: save failed ${e.javaClass.simpleName}") }
    }

    companion object {
        fun load(): AppSettings {
            try {
                if (Paths.settings.isFile) {
                    val o = Json.parseObject(Paths.settings.readText())
                    if (o != null) {
                        val d = AppSettings()
                        return AppSettings(
                            target = o["target"].str() ?: d.target, notesLanguage = o["notesLanguage"].str() ?: d.notesLanguage,
                            model = o["model"].str() ?: d.model, view = o["view"].str() ?: d.view,
                            showInCapture = o["showInCapture"].bool() ?: false, onboarded = o["onboarded"].bool() ?: false,
                            uiLanguage = o["uiLanguage"].str() ?: d.uiLanguage, source = o["source"].str() ?: d.source,
                            overlay = o["overlay"].bool() ?: true,
                        )
                    }
                }
            } catch (e: Exception) { Log.d("settings: unreadable, defaults used (${e.javaClass.simpleName})") }
            return AppSettings()
        }
    }
}
