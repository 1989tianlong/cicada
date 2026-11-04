using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using static Cicada.Strings;

namespace Cicada.App;

/// The window shown while listening: the live notes panel (default) or the subtitle bar. Like the
/// Mac's it never takes focus (the user keeps typing in their meeting app) and stays out of screen
/// captures unless 共享屏幕时让对方看到 is on, which it then says plainly.
sealed class NotesWindow : Window
{
    readonly Controller app;
    readonly DispatcherTimer clock = new() { Interval = TimeSpan.FromSeconds(1) };
    // Hosts kept between renders: the clock redraws only the header, and the body keeps its scroll.
    ContentControl header = new(), bars = new(), live = new(), tabs = new(), footer = new();
    ScrollViewer scroll = new();
    string? builtFor;
    string tab = "notes";
    /// Whether Windows agreed to keep the window out of captures; if not, it says it may be seen.
    bool hiddenFromCapture;
    bool renderQueued, placedSubtitles;
    // Rebuilt only when what they show changes, so a click never lands on a button that a
    // re-render just replaced; the clock and the countdown are text updated in place.
    string? headerKey, tabsKey, barsKey;
    readonly TextBlock clockText = Ui.Text("", 13, Palette.Secondary, wrap: false), dueText = Ui.Text("", 12, Palette.Tertiary, wrap: false);

    public NotesWindow(Controller app)
    {
        this.app = app;
        // A plain frameless window, framed by DWM (UseSystemFrame), not a transparent one: those are
        // redrawn in software, and with a shadow that cost most of a CPU core while listening.
        WindowStyle = WindowStyle.None;
        System.Windows.Shell.WindowChrome.SetWindowChrome(this, new System.Windows.Shell.WindowChrome
        {
            CaptionHeight = 0, ResizeBorderThickness = new Thickness(6), GlassFrameThickness = new Thickness(0, 1, 0, 0), UseAeroCaptionButtons = false,
        });
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.CanResize;
        FontFamily = Palette.Font;
        Title = L("知了");
        SourceInitialized += (_, _) =>
        {
            Native.MakeNonActivating(this);
            Native.UseSystemFrame(this, Subtitles);
            ApplyCaptureSetting();
        };
        // Drag from anywhere that isn't a control (buttons and links mark the press handled).
        MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) try { DragMove(); } catch { } };
        clock.Tick += (_, _) => Tick();
        IsVisibleChanged += (_, _) => { if (IsVisible) clock.Start(); else clock.Stop(); };
        // The subtitle bar fits its text and grows upward, so its bottom edge stays put.
        SizeChanged += (_, e) =>
        {
            if (!Subtitles || !e.HeightChanged) return;
            if (e.PreviousSize.Height <= 0 || !placedSubtitles) { Top = SystemParameters.WorkArea.Bottom - e.NewSize.Height - 16; placedSubtitles = true; }
            else Top -= e.NewSize.Height - e.PreviousSize.Height;
        };
        Place();
        Render();
    }

    bool Subtitles => app.Settings.View == "subtitles";

    /// The panel along the right edge, the subtitle bar along the bottom, on the primary work area.
    public void Place()
    {
        var area = SystemParameters.WorkArea;
        if (Subtitles)
        {
            SizeToContent = SizeToContent.Height; MinHeight = 80; MinWidth = 480;
            Width = Math.Min(900, area.Width - 48);
            Left = area.Left + (area.Width - Width) / 2; Top = area.Bottom - Math.Max(ActualHeight, MinHeight) - 16;
            placedSubtitles = ActualHeight > 0;
        }
        else
        {
            SizeToContent = SizeToContent.Manual; MinHeight = 360; MinWidth = 340;
            Width = 400; Height = Math.Min(820, area.Height - 32);
            Left = area.Right - Width - 16; Top = area.Top + 16;
        }
    }

    public void ApplyCaptureSetting()
    {
        var ok = Native.SetCaptureVisible(this, app.Settings.ShowInCapture);
        hiddenFromCapture = ok && !app.Settings.ShowInCapture;
        if (!ok && !app.Settings.ShowInCapture) Log.Debug("notes window: could not hide from capture, shown as visible");
        Render();
    }

    /// Changes come from engine threads: coalesce them into one render on the UI thread.
    public void Refresh()
    {
        if (renderQueued) return;
        renderQueued = true;
        Dispatcher.BeginInvoke(DispatcherPriority.Background, () => { renderQueued = false; Render(); });
    }

    void Collapse()
    {
        Hide();
        app.CollapsedWhileListening();
    }

    void Tick()
    {
        var session = app.Listen.SessionId is { } id ? app.Store.Get(id) : null;
        clockText.Text = app.Listen.Listening && session is not null ? Languages.Clock((DateTimeOffset.Now - session.StartedAt).TotalSeconds) : "";
        dueText.Text = Due() ?? "";
    }

    static void Detach(FrameworkElement e) { if (e.Parent is Panel p) p.Children.Remove(e); }

    void Render()
    {
        var mode = Subtitles ? "subtitles" : "notes";
        if (builtFor != mode)
        {
            builtFor = mode; headerKey = tabsKey = barsKey = null;
            header = new ContentControl(); bars = new ContentControl(); live = new ContentControl(); tabs = new ContentControl(); footer = new ContentControl();
            scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(16, 14, 12, 16) };
            Background = Subtitles ? Palette.Night : Palette.Surface;
            if (IsLoaded) Native.UseSystemFrame(this, Subtitles);
            Content = Subtitles ? SubtitleFrame() : PanelFrame();
        }
        var key = $"{app.Listen.Listening}|{app.Settings.ShowInCapture}|{hiddenFromCapture}";
        if (key != headerKey) { headerKey = key; header.Content = Header(); }
        Tick();
        if (Subtitles) { live.Content = SubtitleLine(); return; }
        var bk = $"{app.Listen.Problem}|{app.Settings.ShowInCapture}|{hiddenFromCapture}";
        if (bk != barsKey) { barsKey = bk; bars.Content = Bars(); }
        live.Content = LiveCard();
        var count = app.Listen.SessionId is { } sid ? app.Store.Get(sid)?.Lines.Count ?? 0 : 0;
        if ($"{tab}|{count}" != tabsKey) { tabsKey = $"{tab}|{count}"; tabs.Content = TabRow(); }
        footer.Content = Footer();
        var atBottom = scroll.VerticalOffset >= scroll.ScrollableHeight - 4;
        var offset = scroll.VerticalOffset;
        scroll.Content = tab == "transcript" ? Transcript() : NotesBody();
        // The transcript follows new lines while the reader is at its end; otherwise nothing jumps.
        if (tab == "transcript" && atBottom) scroll.ScrollToEnd(); else scroll.ScrollToVerticalOffset(offset);
    }

    // MARK: The panel

    FrameworkElement PanelFrame()
    {
        var dock = new DockPanel();
        void Top(UIElement e) { DockPanel.SetDock(e, Dock.Top); dock.Children.Add(e); }
        Top(header);
        Top(bars);
        Top(live);
        tabs.Margin = new Thickness(12, 10, 12, 0);
        Top(tabs);
        Top(new Border { Height = 1, Background = Palette.StrokeSoft, Margin = new Thickness(0, 4, 0, 0) });
        DockPanel.SetDock(footer, Dock.Bottom);
        dock.Children.Add(footer);
        dock.Children.Add(scroll);
        return dock;
    }

    FrameworkElement Header()
    {
        var listen = app.Listen;
        var session = listen.SessionId is { } id ? app.Store.Get(id) : null;
        if (Subtitles)
        {
            var buttons = new StackPanel { Orientation = Orientation.Horizontal };
            buttons.Children.Add(Ui.IconButton(Icons.Notes, L("换成纪要"), () => app.SetView("notes"), Brushes.White, 40, 18, onDark: true));
            if (listen.Listening) buttons.Children.Add(Ui.IconButton(Icons.Stop, L("结束"), () => _ = app.StopListening(), new SolidColorBrush(Color.FromRgb(0xFF, 0x9B, 0x78)), 40, 16, fill: true, onDark: true));
            buttons.Children.Add(Ui.IconButton(Icons.Close, L("收起（继续听）"), Collapse, Brushes.White, 40, 14, onDark: true));
            return buttons;
        }
        var left = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        if (listen.Listening && session is not null)
        {
            left.Children.Add(Ui.LiveDot());
            left.Children.Add(Gap(Ui.Text(L("正在听"), 14, Palette.Ink, FontWeights.SemiBold, wrap: false), 8));
            Detach(clockText);
            clockText.FontSize = 13; clockText.Foreground = Palette.Secondary; clockText.HorizontalAlignment = HorizontalAlignment.Left;
            left.Children.Add(Gap(clockText, 8));
        }
        else
        {
            left.Children.Add(AppIcon.Small(18));
            left.Children.Add(Gap(Ui.Text(L("知了"), 14, Palette.Ink, FontWeights.SemiBold, wrap: false), 8));
        }
        if (app.Settings.ShowInCapture) left.Children.Add(Gap(Ui.Badge(L("对方可见")), 8));

        var right = new StackPanel { Orientation = Orientation.Horizontal };
        right.Children.Add(Ui.IconButton(Icons.Subtitles, L("换成字幕条"), () => app.SetView("subtitles"), Palette.Body, 40, 18));
        right.Children.Add(listen.Listening
            ? Gap(Ui.Button(L("结束"), () => _ = app.StopListening(), Ui.Kind.Pale, Icons.Stop, 36, iconFill: true), 2)
            : Gap(Ui.Button(L("开始听"), () => _ = app.ToggleListening(), Ui.Kind.Accent, Icons.Wave, 36), 2));
        right.Children.Add(Gap(Ui.IconButton(Icons.Close, L("收起（继续听）"), Collapse, Palette.Body, 40, 14), 2));
        var row = Ui.Spread(left, right);
        row.Height = 56;
        row.Margin = new Thickness(16, 0, 8, 0);
        return row;
    }

    /// What needs the user: Ling failing, or the window being visible to others.
    FrameworkElement Bars()
    {
        var stack = new StackPanel { Margin = new Thickness(12, 0, 12, 0) };
        void Add(FrameworkElement bar) { bar.Margin = new Thickness(0, 0, 0, 8); stack.Children.Add(bar); }
        switch (app.Listen.Problem)
        {
            case LingException.Kind.Network or LingException.Kind.Timeout or LingException.Kind.Http:
                Add(Ui.InfoBar(Ui.Severity.Error, L("连不上 Ling"), L("这段时间的话没能识别。检查网络后点重试。"),
                    Ui.Button(L("重试"), () => { app.Listen.ClearProblem(); _ = app.Ling.Check(); }, height: 32)));
                break;
            case LingException.Kind.RateLimited:
                Add(Ui.InfoBar(Ui.Severity.Warning, L("Ling 太忙"), L("稍后会自动重试。")));
                break;
            case LingException.Kind.InvalidKey or LingException.Kind.NoKey:
                Add(Ui.InfoBar(Ui.Severity.Error, L("Ling key 无效"), L("去设置里换一个 key。"), Ui.Button(L("打开设置"), app.ShowSettings, height: 32)));
                break;
        }
        if (app.Settings.ShowInCapture)
            Add(Ui.InfoBar(Ui.Severity.Warning, null, L("共享屏幕时，对方能看到这个窗口。"),
                Ui.LinkText(L("改回只有我看得到"), () => app.SetShowInCapture(false))));
        else if (!hiddenFromCapture)
            Add(Ui.InfoBar(Ui.Severity.Warning, null, L("Windows 没能把这个窗口从屏幕共享里藏起来，对方可能看得到。")));
        return stack;
    }

    /// The newest line: the original small, its translation large, then "在听下一句" while Ming works.
    FrameworkElement LiveCard()
    {
        var listen = app.Listen;
        var line = listen.SessionId is { } id ? app.Store.Get(id)?.Lines.LastOrDefault() : null;
        var stack = new StackPanel();
        if (line is null)
        {
            if (listen.Listening)
                stack.Children.Add(Ui.Row(12, Ui.Icon(Icons.Wave, 22, Palette.Secondary, stroke: 1.6),
                    Ui.Stack(2, Ui.Text(L("等有人说话"), 14, Palette.Ink, FontWeights.SemiBold), Ui.Helper(L("电脑里一有人声，字幕就出来")))));
            else stack.Children.Add(Ui.Text(L("点“开始听”，电脑里播放的声音会变成双语字幕和纪要"), 13, Palette.Secondary));
        }
        else
        {
            stack.Children.Add(Ui.Text($"{Ui.SpokenName(line.SrcLang)} · {Languages.Clock(line.T)}", 12, Palette.Tertiary, wrap: false));
            if (line.Dst is not null && line.Dst != line.Src) stack.Children.Add(Gap(Ui.Text(line.Src, 13, Palette.Secondary), 4, top: true));
            stack.Children.Add(Gap(Ui.Text(line.Dst ?? line.Src, 17, Palette.Ink, FontWeights.SemiBold), 2, top: true));
            if (listen.Listening && listen.Pending > 0)
                stack.Children.Add(Gap(Ui.Row(6, Ui.LiveDot(4), Ui.Text(L("在听下一句"), 12, Palette.Tertiary, wrap: false)), 6, top: true));
        }
        // Room for a two-line translation, so the tabs below don't jump as lines come and go.
        return new Border { Background = Palette.Mica, CornerRadius = new CornerRadius(8), Padding = new Thickness(14, 12, 14, 12), Margin = new Thickness(12, 0, 12, 0), Child = stack, MinHeight = 126 };
    }

    FrameworkElement TabRow()
    {
        var count = app.Listen.SessionId is { } id ? app.Store.Get(id)?.Lines.Count ?? 0 : 0;
        var tabsRow = Ui.Tabs([("notes", L("纪要")), ("transcript", count > 0 ? $"{L("文字记录")} {count}" : L("文字记录"))], tab, t => { tab = t; Render(); });
        Detach(dueText);
        dueText.VerticalAlignment = VerticalAlignment.Center;
        return Ui.Spread(tabsRow, dueText);
    }

    string? Due()
    {
        if (app.Notes.Status == NotesEngine.State.Updating && !app.Notes.Notes.IsEmpty) return L("正在整理纪要…");
        if (app.Notes.NextUpdate is { } next && app.Listen.Listening)
            return LF("%@ 秒后更新", Math.Max(1, (int)Math.Ceiling((next - DateTime.UtcNow).TotalSeconds)));
        return null;
    }

    FrameworkElement NotesBody()
    {
        var notes = app.Notes.Notes;
        var body = new StackPanel();
        if (notes.IsEmpty)
        {
            var (title, hint) = app.Notes.Status switch
            {
                NotesEngine.State.Updating => (L("正在整理纪要…"), ""),
                NotesEngine.State.NoKey => (L("生成纪要需要 API key"), ""),
                NotesEngine.State.InvalidKey => (L("这个 key 无效，请检查是否复制完整，或重新创建一个"), ""),
                _ => app.Listen.Listening ? (L("纪要会在开会几分钟后出现"), L("之后每 45 秒更新一次")) : ("", ""),
            };
            var empty = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 48, 0, 0) };
            if (title.Length > 0) { var t = Ui.Text(title, 14, Palette.Body, FontWeights.SemiBold); t.TextAlignment = TextAlignment.Center; empty.Children.Add(t); }
            if (hint.Length > 0) { var h = Ui.Text(hint, 13, Palette.Secondary); h.TextAlignment = TextAlignment.Center; empty.Children.Add(Gap(h, 4, top: true)); }
            body.Children.Add(empty);
            return body;
        }
        if (notes.Title is { Length: > 0 } title2) body.Children.Add(Ui.Text(title2, 18, Palette.Ink, FontWeights.SemiBold));
        if (notes.Summary.Length > 0) body.Children.Add(Gap(Ui.Text(notes.Summary, 14, Palette.Body), 6, top: true));
        foreach (var topic in notes.Topics)
        {
            body.Children.Add(Gap(Ui.Row(8, Ui.Text(Languages.Clock(topic.Start), 12, Palette.AccentText, FontWeights.SemiBold, wrap: false),
                                          Ui.Text(topic.Title, 14, Palette.Ink, FontWeights.SemiBold)), 18, top: true));
            foreach (var p in topic.Points) body.Children.Add(Gap(Bullet(p), 4, top: true));
        }
        if (notes.Conclusions.Count > 0)
        {
            body.Children.Add(Gap(Ui.Text(L("结论"), 13, Palette.Secondary, FontWeights.SemiBold), 18, top: true));
            foreach (var c in notes.Conclusions) body.Children.Add(Gap(Bullet(c.Text), 4, top: true));
        }
        if (notes.Todos.Count > 0)
        {
            body.Children.Add(Gap(Ui.Text(L("待办"), 13, Palette.Secondary, FontWeights.SemiBold), 18, top: true));
            foreach (var todo in notes.Todos) body.Children.Add(Gap(Todo(todo), 6, top: true));
        }
        return body;
    }

    FrameworkElement Transcript()
    {
        var lines = app.Listen.SessionId is { } id ? app.Store.Get(id)?.Lines ?? [] : [];
        var body = new StackPanel();
        foreach (var l in lines) body.Children.Add(TranscriptRow(l));
        return body;
    }

    internal static FrameworkElement TranscriptRow(TranscriptLine l)
    {
        var row = new DockPanel { Margin = new Thickness(0, 0, 0, 12) };
        var time = Ui.Text(Languages.Clock(l.T), 12, Palette.AccentText, FontWeights.SemiBold, wrap: false);
        time.Width = 48; time.VerticalAlignment = VerticalAlignment.Top; time.Margin = new Thickness(0, 2, 0, 0);
        DockPanel.SetDock(time, Dock.Left);
        row.Children.Add(time);
        var text = new StackPanel();
        text.Children.Add(Ui.Text(l.Src, 14, Palette.Ink));
        if (!string.IsNullOrEmpty(l.Dst) && l.Dst != l.Src) text.Children.Add(Gap(Ui.Text(l.Dst, 13, Palette.Secondary), 2, top: true));
        row.Children.Add(text);
        return row;
    }

    FrameworkElement Footer()
    {
        var visible = app.Settings.ShowInCapture || !hiddenFromCapture;
        var left = Ui.Row(6, Ui.Icon(visible ? Icons.Eye : Icons.EyeOff, 16, visible ? Palette.AccentText : Palette.Secondary),
            Ui.Text(visible ? L("对方可见") : L("屏幕共享里看不到"), 12, visible ? Palette.AccentText : Palette.Secondary, wrap: false));
        Button? targetButton = null;
        targetButton = Ui.Button($"{L("翻译成")} {Ui.TargetName(app.Settings.TargetCode)}", () =>
        {
            var menu = new ContextMenu { PlacementTarget = targetButton, Placement = System.Windows.Controls.Primitives.PlacementMode.Top };
            foreach (var (value, label) in Ui.TargetOptions())
            {
                var item = new MenuItem { Header = label, IsCheckable = true, IsChecked = value == app.Settings.Target };
                item.Click += (_, _) => app.SetTarget(value);
                menu.Items.Add(item);
            }
            menu.IsOpen = true;
        }, Ui.Kind.Subtle, Icons.Globe, height: 32);
        targetButton.MinWidth = 0;
        targetButton.Padding = new Thickness(10, 0, 10, 0);
        var row = Ui.Spread(left, targetButton);
        row.Height = 44;
        row.Margin = new Thickness(14, 0, 8, 0);
        return new Border { BorderBrush = Palette.StrokeSoft, BorderThickness = new Thickness(0, 1, 0, 0), Child = row };
    }

    // MARK: The subtitle bar

    FrameworkElement SubtitleFrame()
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(header, 1);
        header.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(live);
        grid.Children.Add(header);
        var handle = new Border { Width = 36, Height = 4, CornerRadius = new CornerRadius(2), Background = new SolidColorBrush(Color.FromArgb(0x38, 0xFF, 0xFF, 0xFF)), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 6) };
        return new Border { Padding = new Thickness(16, 6, 10, 14), Child = new StackPanel { Children = { handle, grid } } };
    }

    FrameworkElement SubtitleLine()
    {
        var listen = app.Listen;
        var session = listen.SessionId is { } id ? app.Store.Get(id) : null;
        var line = session?.Lines.LastOrDefault();
        var left = new StackPanel { Width = 52, VerticalAlignment = VerticalAlignment.Center };
        if (listen.Listening && session is not null)
        {
            var dot = Ui.LiveDot(10);
            dot.HorizontalAlignment = HorizontalAlignment.Center;
            left.Children.Add(dot);
            Detach(clockText);
            clockText.FontSize = 11; clockText.Foreground = Palette.NightText;
            clockText.HorizontalAlignment = HorizontalAlignment.Center; clockText.Margin = new Thickness(0, 6, 0, 0);
            left.Children.Add(clockText);
        }
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 12, 0) };
        if (line is null)
            text.Children.Add(Ui.Text(listen.Listening ? L("等有人说话") : L("点“开始听”，电脑里播放的声音会变成双语字幕和纪要"), 15, Palette.NightText));
        else
        {
            if (line.Dst is not null && line.Dst != line.Src) text.Children.Add(Ui.Text(line.Src, 14, Palette.NightText));
            text.Children.Add(Gap(Ui.Text(line.Dst ?? line.Src, app.Settings.SubtitleSize, Brushes.White, FontWeights.SemiBold), 4, top: true));
        }
        var row = new DockPanel();
        DockPanel.SetDock(left, Dock.Left);
        row.Children.Add(left);
        row.Children.Add(text);
        return row;
    }

    // MARK: Bits

    static T Gap<T>(T e, double size, bool top = false) where T : FrameworkElement
    {
        e.Margin = top ? new Thickness(0, size, 0, 0) : new Thickness(size, 0, 0, 0);
        return e;
    }

    static FrameworkElement Bullet(string text)
    {
        var dock = new DockPanel();
        var dot = Ui.Text("·", 14, Palette.Body, wrap: false);
        dot.Width = 12;
        DockPanel.SetDock(dot, Dock.Left);
        dock.Children.Add(dot);
        dock.Children.Add(Ui.Text(text, 14, Palette.Body));
        return dock;
    }

    /// A to-do: an empty box (notes are read-only here), the task, and who has it.
    internal static FrameworkElement Todo(NoteItem todo)
    {
        var dock = new DockPanel();
        var box = new Border { Width = 16, Height = 16, BorderBrush = Palette.Secondary, BorderThickness = new Thickness(1.5), CornerRadius = new CornerRadius(3), Margin = new Thickness(0, 2, 10, 0), VerticalAlignment = VerticalAlignment.Top };
        DockPanel.SetDock(box, Dock.Left);
        dock.Children.Add(box);
        var text = new TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = 14, FontFamily = Palette.Font, Foreground = Palette.Ink };
        text.Inlines.Add(new System.Windows.Documents.Run(todo.Text));
        if (todo.Owner is { Length: > 0 } owner) text.Inlines.Add(new System.Windows.Documents.Run($" · {owner}") { Foreground = Palette.Secondary });
        dock.Children.Add(text);
        return dock;
    }
}
