using System.Globalization;
using System.Text.Json.Serialization;

namespace Cicada;

/// The app's settings, in settings.json beside the records (never the Ling key: that has its own file).
public sealed class AppSettings
{
    /// What subtitles translate into; "system" follows the Windows display language.
    [JsonPropertyName("target")] public string Target { get; set; } = "system";
    /// 纪要语言: the notes' language code; "system" is the same as the subtitles'.
    [JsonPropertyName("notesLanguage")] public string NotesLanguage { get; set; } = "system";
    [JsonPropertyName("model")] public string Model { get; set; } = LingClient.DefaultModel;
    /// "notes" (the notes window, default) or "subtitles" (the subtitle bar).
    [JsonPropertyName("view")] public string View { get; set; } = "notes";
    /// 共享屏幕时让对方看到: let the notes window and subtitles show up in screen sharing.
    [JsonPropertyName("showInCapture")] public bool ShowInCapture { get; set; }
    [JsonPropertyName("onboarded")] public bool Onboarded { get; set; }
    /// The UI language: "system", "zh-Hans", "en", "ja" or "ko".
    [JsonPropertyName("uiLanguage")] public string UiLanguage { get; set; } = "system";

    [JsonIgnore] public string TargetCode => Target == "system" ? Languages.FromSystem(CultureInfo.CurrentUICulture.Name) : Target;
    [JsonIgnore] public string NotesCode => NotesLanguage == "system" ? TargetCode : NotesLanguage;

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(Paths.Settings) && Json.Read<AppSettings>(File.ReadAllText(Paths.Settings)) is { } s) return s;
        }
        catch (Exception e) { Log.Debug($"settings: unreadable, defaults used ({e.GetType().Name})"); }
        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Paths.Root);
            File.WriteAllText(Paths.Settings, Json.Write(this));
        }
        catch (Exception e) { Log.Debug($"settings: save failed {e.GetType().Name}"); }
    }
}
