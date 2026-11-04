using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using static Cicada.Strings;

namespace Cicada.App;

/// Left-click on the tray icon: Cicada's home, the counterpart of the Mac's menu bar panel. It
/// rises above the notification area like Windows' own flyouts and goes away when it loses focus.
sealed class TrayFlyout : Window
{
    readonly Controller app;
    readonly ContentControl body = new();
    readonly DispatcherTimer clock = new() { Interval = TimeSpan.FromSeconds(1) };
    DateTime hiddenAt;

    public TrayFlyout(Controller app)
    {
        this.app = app;
        // The Mac panel's 16-point corners and soft shadow (Ui.Floating), so a transparent window.
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        Topmost = true; ShowInTaskbar = false; ResizeMode = ResizeMode.NoResize;
        Width = 380 + 2 * Ui.ShadowRoom; SizeToContent = SizeToContent.Height; FontFamily = Palette.Font; Title = L("知了");
        Content = Ui.Floating(body, Palette.Page);
        Deactivated += (_, _) => { Hide(); hiddenAt = DateTime.UtcNow; };
        KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Escape) Hide(); };
        SizeChanged += (_, _) => Anchor();
        clock.Tick += (_, _) => { if (app.Listen.Listening) Refresh(); };
        IsVisibleChanged += (_, _) => { if (IsVisible) clock.Start(); else clock.Stop(); };
    }

    /// Opens, or closes when it is already open (a second click on the icon). A click that just
    /// closed it by taking focus away doesn't reopen it straight away.
    public void Toggle()
    {
        if (IsVisible) { Hide(); return; }
        if ((DateTime.UtcNow - hiddenAt).TotalMilliseconds < 300) return;
        Refresh();
        Show();
        Anchor();
        Activate();
    }

    void Anchor()
    {
        var area = SystemParameters.WorkArea;
        Left = area.Right - ActualWidth - 12 + Ui.ShadowRoom;
        Top = area.Bottom - ActualHeight - 12 + Ui.ShadowRoom;
    }

    public void Refresh() => body.Content = Build();

    FrameworkElement Build()
    {
        var listen = app.Listen;
        var stack = new StackPanel();

        // Who and how it is
        var status = listen.Listening && listen.SessionId is { } sid && app.Store.Get(sid) is { } live
            ? Ui.Row(6, Ui.LiveDot(6), Ui.Text($"{L("正在听")} {Languages.Clock((DateTimeOffset.Now - live.StartedAt).TotalSeconds)}", 12, Palette.Secondary, wrap: false))
            : app.AutoEnded
                ? Ui.Row(6, Ui.Dot(Palette.Tertiary, 6), Ui.Text(L("会议已自动结束"), 12, Palette.Secondary, wrap: false))
            : app.Ling.HasKey
                ? Ui.Row(6, Ui.Dot(Palette.Success, 6), Ui.Text(L("就绪 · Ling 已连接"), 12, Palette.Secondary, wrap: false))
                : Ui.Row(6, Ui.Dot(Palette.Tertiary, 6), Ui.Text(L("还没接上 Ling"), 12, Palette.Secondary, wrap: false));
        var title = Ui.Row(12, AppIcon.Small(32), Ui.Stack(2, Ui.Text(L("知了"), 15, Palette.Ink, FontWeights.SemiBold, wrap: false), status));
        var head = Ui.Spread(title, Ui.IconButton(Icons.Gear, L("打开设置"), () => { Hide(); app.ShowSettings(); }, Palette.Body, 40, 18));
        head.Margin = new Thickness(16, 16, 12, 12);
        stack.Children.Add(head);

        // The one thing to do
        var main = new StackPanel { Margin = new Thickness(16, 4, 16, 16) };
        if (listen.Listening && app.Ending is { } p)
        {
            // About to end by itself (MeetingEndingStrip, compact): the panel takes no focus either.
            var strip = Ui.Stack(3, Ui.Text(app.EndingTitle(p), 13, Palette.Ink, FontWeights.Bold),
                                 Ui.Text(LF("%lld 秒后结束会议并整理纪要", Controller.EndingLeft(p)), 12, Palette.Secondary));
            var keep = Ui.Row(8, Ui.Button(L("继续记录"), app.KeepRecording, Ui.Kind.Primary, height: 32),
                              Ui.Button(L("现在结束"), () => { Hide(); _ = app.StopListening(); }, height: 32));
            keep.Margin = new Thickness(0, 8, 0, 0);
            strip.Children.Add(keep);
            main.Children.Add(new Border { Background = Palette.AccentPale, CornerRadius = new CornerRadius(10), Padding = new Thickness(12), Margin = new Thickness(0, 0, 0, 10), Child = strip });
        }
        if (listen.Listening)
        {
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            var end = Ui.Button(L("结束"), () => { Hide(); _ = app.StopListening(); }, Ui.Kind.Pale, Icons.Stop, 44, iconFill: true);
            var show = Ui.Button(L("显示纪要"), () => { Hide(); app.ShowNotes(); }, Ui.Kind.Standard, Icons.Notes, 44);
            Grid.SetColumn(show, 2);
            grid.Children.Add(end); grid.Children.Add(show);
            main.Children.Add(grid);
        }
        else
        {
            main.Children.Add(Ui.Button(L("开始听"), () => { Hide(); _ = app.ToggleListening(); }, Ui.Kind.Accent, Icons.Wave, 52));
            var hint = Ui.Text(app.Settings.Speak ? $"{Hotkey.Label} · {LF("按住%@说话", PushToTalk.Label)}" : $"{L("听电脑播放的声音，不用麦克风")} · {Hotkey.Label}", 12, Palette.Secondary);
            hint.TextAlignment = TextAlignment.Center; hint.Margin = new Thickness(0, 8, 0, 0);
            main.Children.Add(hint);
        }
        stack.Children.Add(main);

        // Two choices people change before a meeting
        var target = Ui.Choice(Ui.TargetOptions(), app.Settings.Target, app.SetTarget, 212);
        var view = Ui.Segmented([("notes", L("纪要")), ("subtitles", L("字幕条"))], app.Settings.View, app.SetView);
        var options = new StackPanel
        {
            Children =
            {
                OptionRow(Icons.Globe, L("翻译成"), target, divider: true),
                OptionRow(Icons.Subtitles, L("听的时候显示"), view, divider: false),
            },
        };
        stack.Children.Add(new Border { Margin = new Thickness(12, 0, 12, 0), Background = Palette.Surface, BorderBrush = Palette.Stroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8), Child = options });

        // Recent meetings
        var recent = app.Store.All().Where(s => !(listen.Listening && s.Id == listen.SessionId)).Take(3).ToList();
        if (recent.Count > 0)
        {
            var label = Ui.Spread(Ui.Text(L("最近的会议"), 13, Palette.Body, FontWeights.SemiBold, wrap: false), Ui.LinkText(L("查看全部"), () => { Hide(); app.ShowRecords(); }));
            label.Margin = new Thickness(16, 18, 16, 6);
            stack.Children.Add(label);
            var list = new StackPanel { Margin = new Thickness(8, 0, 8, 8) };
            foreach (var s in recent)
            {
                var item = new Button
                {
                    Content = Ui.Stack(2, Ui.Text(SessionStore.DisplayTitle(s), 14, Palette.Ink, FontWeights.SemiBold, wrap: false), Ui.Text(Records.Meta(s, app), 12, Palette.Secondary, wrap: false)),
                    HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left, Padding = new Thickness(8, 8, 8, 8), Background = Brushes.Transparent, BorderThickness = new Thickness(0), Cursor = System.Windows.Input.Cursors.Hand,
                };
                item.Template = RowTemplate();
                var id = s.Id;
                item.Click += (_, _) => { Hide(); app.ShowRecords(id); };
                list.Children.Add(item);
            }
            stack.Children.Add(list);
        }

        // Footer
        var records = Ui.Button(L("查看记录"), () => { Hide(); app.ShowRecords(); }, Ui.Kind.Subtle, Icons.List, 40);
        var quit = Ui.Button(L("退出"), () => { Hide(); _ = app.Quit(); }, Ui.Kind.Subtle, Icons.Power, 40);
        records.MinWidth = 0; quit.MinWidth = 0;
        var foot = Ui.Spread(records, quit);
        foot.Margin = new Thickness(8, 6, 8, 6);
        stack.Children.Add(new Border { Background = Palette.Mica, BorderBrush = Palette.Stroke, BorderThickness = new Thickness(0, 1, 0, 0), Child = foot, Margin = new Thickness(0, recent.Count > 0 ? 0 : 16, 0, 0) });
        return stack;
    }

    static FrameworkElement OptionRow(string icon, string label, FrameworkElement control, bool divider)
    {
        var left = Ui.Row(12, Ui.Icon(icon, 18, Palette.Body), Ui.Text(label, 14, Palette.Ink, wrap: false));
        var row = Ui.Spread(left, control);
        row.Margin = new Thickness(12, 8, 12, 8);
        return new Border { BorderBrush = Palette.StrokeSoft, BorderThickness = new Thickness(0, 0, 0, divider ? 1 : 0), Child = row, MinHeight = 52 };
    }

    /// A list row: no fill until the mouse is on it.
    static ControlTemplate RowTemplate()
    {
        var t = new ControlTemplate(typeof(Button));
        var border = new FrameworkElementFactory(typeof(Border), "bg");
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(6));
        border.SetValue(Border.BackgroundProperty, Brushes.Transparent);
        border.SetBinding(Border.PaddingProperty, new System.Windows.Data.Binding("Padding") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        var content = new FrameworkElementFactory(typeof(ContentPresenter));
        border.AppendChild(content);
        t.VisualTree = border;
        var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Border.BackgroundProperty, Palette.Subtle, "bg"));
        t.Triggers.Add(hover);
        return t;
    }
}
