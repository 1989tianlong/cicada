using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using static Cicada.Strings;

namespace Cicada.App;

/// 设置, laid out as Windows 11 Settings: categories on the left, one card per setting with its
/// control on the right, switches for on/off.
sealed class SettingsWindow : Window
{
    readonly Controller app;
    readonly ScrollViewer scroll = new() { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(16, 0, 32, 32) };
    readonly StackPanel nav = new() { Margin = new Thickness(12, 8, 12, 12) };
    readonly Dictionary<string, FrameworkElement> sections = [];
    readonly PasswordBox keyBox = new() { FontSize = 14, MinHeight = 32, Width = 300, VerticalContentAlignment = VerticalAlignment.Center };
    bool editingKey;
    string current = "ling";

    public SettingsWindow(Controller app)
    {
        this.app = app;
        Title = L("设置") + " · " + L("知了");
        Width = 1000; Height = Math.Min(760, SystemParameters.WorkArea.Height - 24); MinWidth = 760; MinHeight = 480;
        Background = Palette.Mica; FontFamily = Palette.Font; Icon = AppIcon.Image;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        System.Windows.Automation.AutomationProperties.SetName(keyBox, L("Ling key"));
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(240) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        Grid.SetColumn(scroll, 1);
        grid.Children.Add(nav); grid.Children.Add(scroll);
        Content = grid;
        app.Ling.Changed += OnLingChanged;
        Closed += (_, _) => app.Ling.Changed -= OnLingChanged;
        Render();
    }

    void OnLingChanged() => Dispatcher.BeginInvoke(Render);

    void Render()
    {
        var offset = scroll.VerticalOffset;
        sections.Clear();
        var page = new StackPanel { MaxWidth = 860, HorizontalAlignment = HorizontalAlignment.Stretch };
        var title = Ui.Text(L("设置"), 28, Palette.Ink, FontWeights.SemiBold);
        title.Margin = new Thickness(0, 4, 0, 8);
        page.Children.Add(title);
        Section(page, "ling", L("Ling"), KeyCard(), Group(Card(Icons.Notes, L("纪要和翻译用的模型"), L("3.1 更准；3.0 更快、更省。语音识别固定用 Ming。"),
            Ui.Choice([("Ling-3.1-flash", "Ling-3.1-flash"), ("Ling-3.0-flash", "Ling-3.0-flash")], app.Settings.Model, v => { app.Settings.Model = v; app.Ling.Model = v; Save(); }))));
        Section(page, "lang", L("语言"), Group(
            Card(Icons.Globe, L("翻译成"), null, Ui.Choice(Ui.TargetOptions(), app.Settings.Target, app.SetTarget)),
            Card(null, L("纪要语言"), null, Ui.Choice([("system", L("和字幕一样")), .. Languages.Targets.Select(t => (t.Code, t.Name))], app.Settings.NotesLanguage, v => { app.Settings.NotesLanguage = v; Save(); })),
            Card(null, L("界面语言"), L("重新打开知了后生效"), Ui.Choice([("system", L("跟随系统")), ("zh-Hans", "简体中文"), ("en", "English"), ("ja", "日本語"), ("ko", "한국어")], app.Settings.UiLanguage, v => { app.Settings.UiLanguage = v; Save(); }))));
        var size = new Slider { Minimum = 18, Maximum = 32, Value = app.Settings.SubtitleSize, Width = 200, IsSnapToTickEnabled = true, TickFrequency = 1, VerticalAlignment = VerticalAlignment.Center };
        System.Windows.Automation.AutomationProperties.SetName(size, L("字幕文字大小"));
        size.ValueChanged += (_, e) => { app.Settings.SubtitleSize = (int)e.NewValue; Save(); };
        Section(page, "listen", L("听的时候"), Group(
            Card(Icons.Subtitles, L("听的时候显示"), null, Ui.Segmented([("notes", L("纪要")), ("subtitles", L("字幕条"))], app.Settings.View, app.SetView)),
            Card(null, L("字幕文字大小"), null, size),
            Card(Icons.Keyboard, L("开始或结束"), app.HotkeyRegistered ? L("在任何程序里都能按") : L("这个快捷键被别的程序占用了"), Keys(Hotkey.Label))));
        Section(page, "privacy", L("隐私与启动"), Group(
            Card(Icons.Eye, L("共享屏幕时让对方看到"), L("关着时，截图和屏幕共享里看不到纪要和字幕"), Ui.Switch(app.Settings.ShowInCapture, app.SetShowInCapture, L("共享屏幕时让对方看到"))),
            Card(Icons.Power, L("开机时启动知了"), null, Ui.Switch(AutoStart.Enabled, v => AutoStart.Enabled = v, L("开机时启动知了"))),
            Card(Icons.Folder, L("会议记录存放位置"), $"{Paths.Sessions} · {L("和 Mac 版格式相同")}", Ui.Button(L("打开文件夹"), () => OpenFolder(Paths.Sessions), height: 32))));
        var version = typeof(SettingsWindow).Assembly.GetName().Version?.ToString(3) ?? "";
        Section(page, "about", L("关于"), Group(Card(null, LF("知了 %@", version), null, Ui.LinkText(L("打开日志"), () => OpenFolder(Path.GetDirectoryName(Paths.Log)!)), AppIcon.Small(24))));
        scroll.Content = page;
        scroll.ScrollToVerticalOffset(offset);
        Nav();
    }

    void Nav()
    {
        nav.Children.Clear();
        (string id, string icon, string label)[] items =
        [
            ("ling", Icons.Key, L("Ling")), ("lang", Icons.Globe, L("语言")), ("listen", Icons.Wave, L("听的时候")),
            ("privacy", Icons.Shield, L("隐私与启动")), ("about", Icons.Info, L("关于")),
        ];
        foreach (var (id, icon, label) in items)
        {
            var on = id == current;
            var content = new Grid();
            var mark = new Border { Width = 3, Height = 16, CornerRadius = new CornerRadius(2), Background = on ? Palette.Ink : Brushes.Transparent, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(-12, 0, 0, 0) };
            content.Children.Add(mark);
            content.Children.Add(Ui.Row(12, Ui.Icon(icon, 18, Palette.Ink), Ui.Text(label, 14, Palette.Ink, on ? FontWeights.SemiBold : FontWeights.Normal, wrap: false)));
            var b = new Button { HorizontalAlignment = HorizontalAlignment.Stretch, Content = content, Height = 40, Padding = new Thickness(12, 0, 12, 0), HorizontalContentAlignment = HorizontalAlignment.Left, Background = on ? Palette.Selected : Brushes.Transparent, BorderThickness = new Thickness(0), Cursor = System.Windows.Input.Cursors.Hand, Margin = new Thickness(0, 0, 0, 2) };
            b.Template = NavTemplate();
            b.Click += (_, _) =>
            {
                current = id; Nav();
                if (sections.TryGetValue(id, out var target))
                    scroll.ScrollToVerticalOffset(target.TransformToAncestor((Visual)scroll.Content).Transform(new Point(0, 0)).Y - 8);
            };
            System.Windows.Automation.AutomationProperties.SetName(b, label);
            nav.Children.Add(b);
        }
    }

    static ControlTemplate NavTemplate()
    {
        var t = new ControlTemplate(typeof(Button));
        var border = new FrameworkElementFactory(typeof(Border), "bg");
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(6));
        border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.PaddingProperty, new System.Windows.Data.Binding("Padding") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        var content = new FrameworkElementFactory(typeof(ContentPresenter));
        content.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(content);
        t.VisualTree = border;
        var hover = new MultiTrigger();
        hover.Conditions.Add(new Condition(UIElement.IsMouseOverProperty, true));
        hover.Conditions.Add(new Condition(Control.BackgroundProperty, Brushes.Transparent));
        hover.Setters.Add(new Setter(Border.BackgroundProperty, Palette.Subtle, "bg"));
        t.Triggers.Add(hover);
        return t;
    }

    void Section(StackPanel page, string id, string title, params FrameworkElement[] groups)
    {
        var h = Ui.Text(title, 14, Palette.Ink, FontWeights.SemiBold);
        h.Margin = new Thickness(0, 20, 0, 8);
        sections[id] = h;
        page.Children.Add(h);
        foreach (var g in groups) { g.Margin = new Thickness(0, 0, 0, 6); page.Children.Add(g); }
    }

    /// Cards that belong together share one border, with hairlines between them.
    static FrameworkElement Group(params FrameworkElement[] cards)
    {
        var s = new StackPanel();
        for (int i = 0; i < cards.Length; i++)
            s.Children.Add(new Border { BorderBrush = Palette.StrokeSoft, BorderThickness = new Thickness(0, i == 0 ? 0 : 1, 0, 0), Child = cards[i] });
        return new Border { Background = Palette.Surface, BorderBrush = Palette.Stroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(6), Child = s };
    }

    /// One setting: icon, name, one grey line, and its control on the right.
    static FrameworkElement Card(string? icon, string title, string? description, FrameworkElement control, FrameworkElement? image = null)
    {
        var dock = new DockPanel { MinHeight = 48, Margin = new Thickness(16, 10, 16, 10) };
        var lead = image ?? (icon is null ? new Border { Width = 20 } : Ui.Icon(icon, 20, Palette.Body));
        lead.Margin = new Thickness(0, 0, 16, 0);
        DockPanel.SetDock(lead, Dock.Left);
        dock.Children.Add(lead);
        control.VerticalAlignment = VerticalAlignment.Center;
        control.Margin = new Thickness(16, 0, 0, 0);
        DockPanel.SetDock(control, Dock.Right);
        dock.Children.Add(control);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Ui.Text(title, 14, Palette.Ink));
        if (description is not null) { var d = Ui.Helper(description); d.Margin = new Thickness(0, 2, 0, 0); text.Children.Add(d); }
        dock.Children.Add(text);
        return dock;
    }

    FrameworkElement KeyCard()
    {
        var state = app.Ling.KeyState;
        var key = app.Key.Read();
        string desc = state switch
        {
            KeyState.None => L("还没填 key"),
            KeyState.Checking => L("正在检查…"),
            KeyState.Invalid => L("这个 key 不能用，检查是否复制完整，或重新创建一个"),
            KeyState.Unreachable => L("连不上 Ling，检查网络"),
            _ => $"{AIKey.Masked(key ?? "")} · {L("可以用 · 只加密存在这台电脑上")}",
        };
        FrameworkElement control;
        if (editingKey)
        {
            if (keyBox.Parent is Panel p) p.Children.Remove(keyBox);
            control = Ui.Row(8, keyBox, Ui.Button(L("保存"), () => _ = SaveKey(), Ui.Kind.Primary, height: 32), Ui.Button(L("取消"), () => { editingKey = false; Render(); }, height: 32));
        }
        else
        {
            var change = Ui.Button(key is null ? L("填写") : L("更换"), () => { editingKey = true; keyBox.Clear(); Render(); keyBox.Focus(); }, height: 32);
            control = key is null ? change : Ui.Row(8, change, Ui.Button(L("删除"), () => { app.Key.Remove(); app.Ling.KeyChanged(); }, height: 32));
        }
        var card = Card(Icons.Key, L("Ling key"), desc, control);
        return Group(card);
    }

    async Task SaveKey()
    {
        var text = keyBox.Password.Trim();
        if (!text.StartsWith("sk-")) return;
        if (!app.Key.Save(text)) return;
        editingKey = false;
        app.Ling.KeyChanged();
        Render();
        await app.Ling.Check();
    }

    static FrameworkElement Keys(string combo)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var k in combo.Split('+'))
            row.Children.Add(new Border
            {
                Background = Palette.SurfaceAlt, BorderBrush = Palette.ControlStroke, BorderThickness = new Thickness(1, 1, 1, 2), CornerRadius = new CornerRadius(4),
                Padding = new Thickness(8, 3, 8, 3), Margin = new Thickness(4, 0, 0, 0), Child = Ui.Text(k, 12, Palette.Ink, wrap: false),
            });
        return row;
    }

    void Save() { app.Settings.Save(); app.SettingsChanged(); }

    static void OpenFolder(string path)
    {
        Directory.CreateDirectory(path);
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
    }
}
