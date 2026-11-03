using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using static Cicada.Strings;

namespace Cicada.App;

/// 设置: the Ling key, languages, how listening shows, and the model.
sealed class SettingsWindow : Window
{
    readonly Controller app;
    readonly TextBlock keyStatus = Ui.Text("", 13, Palette.Secondary);
    readonly PasswordBox keyBox = new() { FontSize = 13, Padding = new Thickness(6), MinWidth = 280 };

    public SettingsWindow(Controller app)
    {
        this.app = app;
        Title = L("设置") + " · " + L("知了");
        Width = 560; Height = 640; Background = Palette.Ground; FontFamily = Palette.Font; Icon = AppIcon.Image;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var s = app.Settings;

        var key = Ui.Card(Ui.Stack(10,
            Ui.Heading(L("Ling key")),
            keyStatus,
            Ui.Row(8, keyBox, Ui.Button(L("保存"), SaveKey, "primary")),
            Ui.Row(16, Ui.LinkText(L("获取 Ling key ↗"), OpenLing), Ui.LinkText(L("删除 key"), RemoveKey)),
            Ui.Helper(L("只存在这台电脑上（只有你的 Windows 账户能读），只发给 Ling（ant-ling.com）"))));

        var languages = Ui.Card(Ui.Stack(12,
            Ui.Heading(L("语言")),
            Field(L("翻译成"), Ui.Choice(Ui.TargetOptions(), s.Target, v => { s.Target = v; Save(); })),
            Field(L("纪要语言"), Ui.Choice([("system", L("和字幕一样")), .. Languages.Targets.Select(t => (t.Code, t.Name))], s.NotesLanguage, v => { s.NotesLanguage = v; Save(); })),
            Field(L("界面语言"), Ui.Choice([("system", L("跟随系统")), ("zh-Hans", "简体中文"), ("en", "English"), ("ja", "日本語"), ("ko", "한국어")], s.UiLanguage,
                v => { s.UiLanguage = v; Save(); MessageBox.Show(this, L("重新打开知了后生效"), L("知了")); }))));

        var capture = new CheckBox { Content = Ui.Text(L("共享屏幕时让对方看到"), 13), IsChecked = s.ShowInCapture, FocusVisualStyle = null };
        capture.Click += (_, _) => { s.ShowInCapture = capture.IsChecked == true; Save(); app.CaptureSettingChanged(); };
        var display = Ui.Card(Ui.Stack(12,
            Ui.Heading(L("显示")),
            Field(L("听的时候显示"), Ui.Choice([("notes", L("实时纪要")), ("subtitles", L("字幕条"))], s.View, v => app.SetView(v))),
            capture,
            Ui.Helper(L("关着时，截图和屏幕共享里看不到纪要窗口和字幕"))));

        var model = Ui.Card(Ui.Stack(12,
            Ui.Heading(L("模型")),
            Field(L("纪要和翻译"), Ui.Choice([("Ling-3.1-flash", "Ling-3.1-flash"), ("Ling-3.0-flash", "Ling-3.0-flash")], s.Model,
                v => { s.Model = v; app.Ling.Model = v; Save(); })),
            Ui.Helper(L("3.1 更准；3.0 更快、更省")),
            Ui.Helper(L("语音识别用 Ming（云端），一次请求同时返回原文和译文"))));

        var about = Ui.Card(Ui.Stack(8,
            Ui.Heading(L("关于")),
            Ui.Helper($"{L("知了")} {typeof(SettingsWindow).Assembly.GetName().Version?.ToString(3)} · Windows"),
            Ui.Row(16, Ui.LinkText(L("打开记录所在文件夹"), () => OpenFolder(Paths.Sessions)), Ui.LinkText(L("打开日志"), () => OpenFolder(Path.GetDirectoryName(Paths.Log)!)))));

        Content = new ScrollViewer
        {
            Content = Ui.Stack(12, key, languages, display, model, about),
            Padding = new Thickness(20), VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        };
        app.Ling.Changed += OnLingChanged;
        Closed += (_, _) => app.Ling.Changed -= OnLingChanged;
        ShowKeyState();
    }

    static FrameworkElement Field(string label, FrameworkElement control)
    {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(140) });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        var t = Ui.Text(label, 13, Palette.Secondary);
        t.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(control, 1);
        control.HorizontalAlignment = HorizontalAlignment.Left;
        g.Children.Add(t); g.Children.Add(control);
        return g;
    }

    void Save() { app.Settings.Save(); app.SettingsChanged(); }

    void OnLingChanged() => Dispatcher.BeginInvoke(ShowKeyState);

    void ShowKeyState()
    {
        var key = app.Key.Read();
        keyStatus.Text = app.Ling.KeyState switch
        {
            KeyState.None => L("还没填 API key"),
            KeyState.Checking => L("正在检查…"),
            KeyState.Invalid => L("这个 key 无效，请检查是否复制完整，或重新创建一个"),
            KeyState.Unreachable => L("连不上 Ling，检查网络"),
            KeyState.Ok => AIKey.Masked(key ?? "") + " · " + L("可以用"),
            _ => AIKey.Masked(key ?? ""),
        };
    }

    async void SaveKey()
    {
        var text = keyBox.Password.Trim();
        if (!text.StartsWith("sk-")) { keyStatus.Text = L("复制 sk- 开头的 key，回来粘贴"); return; }
        if (!app.Key.Save(text)) { keyStatus.Text = L("保存失败"); return; }
        keyBox.Clear();
        app.Ling.KeyChanged();
        await app.Ling.Check();
    }

    void RemoveKey()
    {
        app.Key.Remove();
        app.Ling.KeyChanged();
    }

    static void OpenLing() => Process.Start(new ProcessStartInfo("https://chat.ant-ling.com/platform/api") { UseShellExecute = true });

    static void OpenFolder(string path)
    {
        Directory.CreateDirectory(path);
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
    }
}
