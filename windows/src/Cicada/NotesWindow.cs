using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using static Cicada.Strings;

namespace Cicada.App;

/// The window shown while listening: live notes (default) or the subtitle bar. Like the Mac's
/// notes panel it never takes focus (the user keeps typing in their meeting app) and stays out of
/// screen captures unless 共享屏幕时让对方看到 is on, which shows a badge.
sealed class NotesWindow : Window
{
    readonly Controller app;
    readonly DispatcherTimer clock = new() { Interval = TimeSpan.FromSeconds(1) };
    // Kept across renders: the clock only redraws the header, and the notes keep their scroll position.
    ContentControl header = new(), live = new();
    ScrollViewer scroll = new();
    string? builtFor;
    bool renderQueued;

    public NotesWindow(Controller app)
    {
        this.app = app;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.CanResizeWithGrip;
        FontFamily = Palette.Font;
        Title = L("知了");
        SourceInitialized += (_, _) =>
        {
            Native.MakeNonActivating(this);
            ApplyCaptureSetting();
        };
        // Drag from anywhere that isn't a link, button or scroll bar (those mark the click handled).
        MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) try { DragMove(); } catch { } };
        clock.Tick += (_, _) => header.Content = Header();
        IsVisibleChanged += (_, _) => { if (IsVisible) clock.Start(); else clock.Stop(); };
        Place();
        Render();
    }

    bool Subtitles => app.Settings.View == "subtitles";

    /// Notes at the right edge, subtitles along the bottom, on the primary screen's work area.
    public void Place()
    {
        var area = SystemParameters.WorkArea;
        if (Subtitles)
        {
            Width = Math.Min(820, area.Width - 40); Height = 128;
            Left = area.Left + (area.Width - Width) / 2; Top = area.Bottom - Height - 24;
        }
        else
        {
            Width = 380; Height = Math.Min(620, area.Height - 48);
            Left = area.Right - Width - 20; Top = area.Top + 24;
        }
    }

    public void ApplyCaptureSetting()
    {
        if (!Native.SetCaptureVisible(this, app.Settings.ShowInCapture) && !app.Settings.ShowInCapture)
            Log.Debug("notes window: could not hide from capture (needs Windows 10 2004+)");
        Render();
    }

    /// Changes come from engine threads: coalesce them into one render on the UI thread.
    public void Refresh()
    {
        if (renderQueued) return;
        renderQueued = true;
        Dispatcher.BeginInvoke(DispatcherPriority.Background, () => { renderQueued = false; Render(); });
    }

    void Render()
    {
        var mode = Subtitles ? "subtitles" : "notes";
        if (builtFor != mode)
        {
            builtFor = mode;
            // New hosts for a new layout: an element can't move between parents.
            header = new ContentControl(); live = new ContentControl();
            scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(0, 12, 0, 0) };
            FrameworkElement layout;
            if (Subtitles) layout = Ui.Stack(8, header, live);
            else
            {
                var dock = new DockPanel();
                DockPanel.SetDock(header, Dock.Top);
                var liveCard = new Border { Background = Palette.Ground, CornerRadius = new CornerRadius(10), Padding = new Thickness(12, 10, 12, 10), Child = live, Margin = new Thickness(0, 12, 0, 0) };
                DockPanel.SetDock(liveCard, Dock.Top);
                dock.Children.Add(header); dock.Children.Add(liveCard); dock.Children.Add(scroll);
                layout = dock;
            }
            Content = new Border
            {
                Background = Palette.Card, CornerRadius = new CornerRadius(14), BorderBrush = Palette.Line, BorderThickness = new Thickness(1),
                Padding = new Thickness(16, 12, 16, 14), Child = layout,
                Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 18, ShadowDepth = 2, Opacity = 0.12 },
                Margin = new Thickness(8),
            };
        }
        header.Content = Header();
        live.Content = LiveLine(Subtitles ? 20 : 15);
        if (!Subtitles)
        {
            var offset = scroll.VerticalOffset;
            scroll.Content = NotesBody();
            scroll.ScrollToVerticalOffset(offset);
        }
    }

    FrameworkElement Header()
    {
        var listen = app.Listen;
        var session = listen.SessionId is { } id ? app.Store.Get(id) : null;
        string status = listen.Listening && session is not null
            ? L("正在听 · ") + Languages.Clock((DateTimeOffset.Now - session.StartedAt).TotalSeconds)
            : L("知了");
        var left = Ui.Row(8, Ui.Dot(listen.Listening ? Palette.Accent : Palette.Line), Ui.Text(status, 13, Palette.Ink, FontWeights.SemiBold, wrap: false));
        if (app.Settings.ShowInCapture) left.Children.Add(WithMargin(Ui.Badge(L("对方可见")), 8));
        var right = Ui.Row(12,
            Ui.LinkText(listen.Listening ? L("结束") : L("开始听"), () => _ = app.ToggleListening()),
            Ui.LinkText(Subtitles ? L("纪要") : L("字幕"), () => app.SetView(Subtitles ? "notes" : "subtitles")),
            Ui.LinkText("×", Hide));
        var grid = new DockPanel { LastChildFill = false };
        DockPanel.SetDock(left, Dock.Left); DockPanel.SetDock(right, Dock.Right);
        grid.Children.Add(left); grid.Children.Add(right);
        return grid;
    }

    static T WithMargin<T>(T e, double left) where T : FrameworkElement { e.Margin = new Thickness(left, 0, 0, 0); return e; }

    /// The newest line, translation large, original small above it; "…" while Ming is still on one.
    FrameworkElement LiveLine(double big)
    {
        var listen = app.Listen;
        var line = listen.SessionId is { } id ? app.Store.Get(id)?.Lines.LastOrDefault() : null;
        var stack = new StackPanel();
        if (line is null)
        {
            var hint = listen.Problem ?? (listen.Listening ? (listen.Pending > 0 ? L("正在听…") : L("等有人说话")) : L("点“开始听”，电脑里播放的声音会变成双语字幕和纪要"));
            stack.Children.Add(Ui.Text(hint, 13, listen.Problem is null ? Palette.Tertiary : Palette.Accent));
            return stack;
        }
        if (line.Dst is not null && line.Dst != line.Src) stack.Children.Add(Ui.Text(line.Src, 12, Palette.Secondary));
        var main = Ui.Text(line.Dst ?? line.Src, big, Palette.Ink, FontWeights.SemiBold);
        main.Margin = new Thickness(0, 2, 0, 0);
        stack.Children.Add(main);
        var foot = listen.Problem ?? (listen.Pending > 0 ? L("正在听…") : null);
        if (foot is not null) { var f = Ui.Helper(foot); f.Margin = new Thickness(0, 4, 0, 0); stack.Children.Add(f); }
        return stack;
    }

    FrameworkElement NotesBody()
    {
        var notes = app.Notes.Notes;
        var body = new StackPanel();
        if (notes.IsEmpty)
        {
            var hint = app.Notes.Status switch
            {
                NotesEngine.State.NoKey => L("生成纪要需要 API key"),
                NotesEngine.State.InvalidKey => L("这个 key 无效，请检查是否复制完整，或重新创建一个"),
                NotesEngine.State.RateLimited => L("请求过于频繁，稍后会自动重试。"),
                NotesEngine.State.Updating => L("正在整理纪要…"),
                _ => app.Listen.Listening ? L("会中每 45 秒更新") : "",
            };
            if (hint.Length > 0) body.Children.Add(Spaced(Ui.Helper(hint), 2));
            return body;
        }
        if (notes.Title is { Length: > 0 } t) body.Children.Add(Spaced(Ui.Heading(t, 16), 4));
        if (notes.Summary.Length > 0) body.Children.Add(Spaced(Ui.Text(notes.Summary, 13, Palette.Body), 6));
        foreach (var topic in notes.Topics)
        {
            body.Children.Add(Spaced(Ui.Row(8, Ui.Text(Languages.Clock(topic.Start), 11, Palette.Link, FontWeights.SemiBold, wrap: false),
                                            Ui.Text(topic.Title, 13, Palette.Ink, FontWeights.SemiBold)), 14));
            foreach (var p in topic.Points) body.Children.Add(Spaced(Bullet(p), 4));
        }
        if (notes.Conclusions.Count > 0)
        {
            body.Children.Add(Spaced(Ui.Text(L("结论"), 12, Palette.Secondary, FontWeights.SemiBold), 16));
            foreach (var c in notes.Conclusions) body.Children.Add(Spaced(Bullet(c.Text), 4));
        }
        if (notes.Todos.Count > 0)
        {
            body.Children.Add(Spaced(Ui.Text(L("待办"), 12, Palette.Secondary, FontWeights.SemiBold), 16));
            foreach (var todo in notes.Todos) body.Children.Add(Spaced(Bullet("☐ " + todo.Text + (todo.Owner is null ? "" : $" · {todo.Owner}"), bullet: false), 4));
        }
        if (app.Notes.Status == NotesEngine.State.Updating) body.Children.Add(Spaced(Ui.Helper(L("正在整理纪要…")), 12));
        return body;
    }

    static FrameworkElement Spaced(FrameworkElement e, double top) { e.Margin = new Thickness(0, top, 0, 0); return e; }

    static FrameworkElement Bullet(string text, bool bullet = true)
    {
        var t = Ui.Text((bullet ? "· " : "") + text, 13, Palette.Body);
        t.Margin = new Thickness(bullet ? 2 : 0, 0, 0, 0);
        return t;
    }
}
