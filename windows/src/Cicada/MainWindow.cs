using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using static Cicada.Strings;

namespace Cicada.App;

/// How a meeting is described in lists: "10:03 · 23 分钟 · 待办 2".
static class Records
{
    public static string Meta(Session s, Controller app)
    {
        if (app.Listen.Listening && app.Listen.SessionId == s.Id) return L("正在听");
        var local = s.StartedAt.ToLocalTime();
        var day = local.Date == DateTime.Today || local.Date == DateTime.Today.AddDays(-1)
            ? local.ToString("HH:mm", Culture)
            : local.ToString(L("M月d日"), Culture);
        var parts = new List<string> { day, LF("%@ 分钟", Math.Max(1, (int)Math.Round(s.Duration.TotalMinutes))) };
        if (s.Notes?.Todos.Count is > 0 and var n) parts.Add(LF("待办 %@", n));
        return string.Join(" · ", parts);
    }

    public static string Group(Session s)
    {
        var d = s.StartedAt.ToLocalTime().Date;
        return d == DateTime.Today ? L("今天") : d == DateTime.Today.AddDays(-1) ? L("昨天") : L("更早");
    }
}

/// 会议记录: a list pane on Mica with search and day groups, and the chosen meeting on a white
/// content layer: toolbar, 纪要 / 文字记录 tabs, and a side column for conclusions, to-dos, terms.
sealed class MainWindow : Window
{
    readonly Controller app;
    readonly TextBox search = new() { FontSize = 14, MinHeight = 34, VerticalContentAlignment = VerticalAlignment.Center, Padding = new Thickness(30, 0, 8, 0) };
    readonly StackPanel list = new();
    readonly ContentControl detail = new();
    string? selected;
    string tab = "notes";
    double? jumpTo;
    string? shownKey;
    bool refreshQueued;

    public MainWindow(Controller app, string? select = null)
    {
        this.app = app;
        selected = select;
        Title = L("会议记录") + " · " + L("知了");
        Width = 1200; Height = Math.Min(780, SystemParameters.WorkArea.Height - 24); MinWidth = 960; MinHeight = 520;
        Background = Palette.Mica; FontFamily = Palette.Font; Icon = AppIcon.Image;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(300) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());

        // The search box, with its icon and placeholder drawn over it
        var placeholder = Ui.Text(L("搜索标题、纪要和原话"), 14, Palette.Tertiary, wrap: false);
        placeholder.IsHitTestVisible = false; placeholder.Margin = new Thickness(31, 0, 0, 0); placeholder.VerticalAlignment = VerticalAlignment.Center;
        var glass = Ui.Icon(Icons.Search, 16, Palette.Secondary);
        glass.HorizontalAlignment = HorizontalAlignment.Left; glass.Margin = new Thickness(10, 0, 0, 0); glass.IsHitTestVisible = false;
        System.Windows.Automation.AutomationProperties.SetName(search, L("搜索标题、纪要和原话"));
        search.TextChanged += (_, _) => { placeholder.Visibility = search.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed; Fill(); };
        var searchBox = new Grid { Margin = new Thickness(12, 8, 12, 8), Children = { search, glass, placeholder } };

        var left = new DockPanel();
        DockPanel.SetDock(searchBox, Dock.Top);
        left.Children.Add(searchBox);
        left.Children.Add(new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(8, 0, 8, 12) });

        var right = new Border
        {
            Background = Palette.Surface, BorderBrush = Palette.Stroke, BorderThickness = new Thickness(1, 1, 0, 0),
            CornerRadius = new CornerRadius(8, 0, 0, 0), Child = detail,
        };
        Grid.SetColumn(right, 1);
        grid.Children.Add(left); grid.Children.Add(right);
        Content = grid;
        Refresh();
    }

    public void Select(string id) { selected = id; tab = "notes"; shownKey = null; Fill(); }

    public void Refresh()
    {
        if (refreshQueued) return;
        refreshQueued = true;
        Dispatcher.BeginInvoke(() => { refreshQueued = false; Fill(); });
    }

    static bool Matches(Session s, string q) =>
        q.Length == 0
        || SessionStore.DisplayTitle(s).Contains(q, StringComparison.OrdinalIgnoreCase)
        || (s.Notes?.Summary.Contains(q, StringComparison.OrdinalIgnoreCase) ?? false)
        || s.Lines.Any(l => l.Src.Contains(q, StringComparison.OrdinalIgnoreCase) || (l.Dst?.Contains(q, StringComparison.OrdinalIgnoreCase) ?? false));

    void Fill()
    {
        var all = app.Store.All();
        var q = search.Text.Trim();
        var shown = all.Where(s => Matches(s, q)).ToList();
        list.Children.Clear();
        string? group = null;
        foreach (var s in shown)
        {
            var g = Records.Group(s);
            if (g != group)
            {
                group = g;
                var h = Ui.Text(g, 12, Palette.Secondary, FontWeights.SemiBold, wrap: false);
                h.Margin = new Thickness(10, list.Children.Count == 0 ? 4 : 14, 0, 4);
                list.Children.Add(h);
            }
            list.Children.Add(Item(s));
        }
        if (all.Count == 0) { selected = null; detail.Content = Empty(L("还没有会议记录"), L("点任务栏里的知了图标，开始听第一场会。")); return; }
        if (shown.Count == 0) { detail.Content = Empty(L("没有找到"), ""); return; }
        if (selected is null || shown.All(s => s.Id != selected)) selected = shown[0].Id;
        foreach (var child in list.Children.OfType<Button>()) Paint(child);
        // Store changes come in a burst while a meeting runs; redraw the open page only if it changed.
        var key = app.Store.Get(selected!) is { } cur ? $"{selected}|{SessionStore.DisplayTitle(cur)}|{cur.Lines.Count}|{cur.Notes?.Covered}|{cur.Notes?.Final}|{app.Listen.Listening}" : null;
        if (key == shownKey) return;
        shownKey = key;
        ShowDetail();
    }

    Button Item(Session s)
    {
        var live = app.Listen.Listening && app.Listen.SessionId == s.Id;
        var b = new Button
        {
            Tag = s.Id, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(10, 8, 10, 8), BorderThickness = new Thickness(0),
            Cursor = System.Windows.Input.Cursors.Hand, Margin = new Thickness(0, 0, 0, 2), Background = Brushes.Transparent,
            Content = Ui.Stack(2, Ui.Text(SessionStore.DisplayTitle(s), 14, Palette.Ink, FontWeights.SemiBold, wrap: false),
                                  Ui.Text(Records.Meta(s, app), 12, live ? Palette.AccentText : Palette.Secondary, wrap: false)),
        };
        b.Template = RowTemplate();
        b.Click += (_, _) => { selected = s.Id; tab = "notes"; foreach (var child in list.Children.OfType<Button>()) Paint(child); ShowDetail(); };
        System.Windows.Automation.AutomationProperties.SetName(b, SessionStore.DisplayTitle(s));
        return b;
    }

    void Paint(Button b)
    {
        var on = (string)b.Tag == selected;
        b.Background = on ? Palette.Surface : Brushes.Transparent;
        b.Effect = on ? new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 3, ShadowDepth = 1, Opacity = 0.08 } : null;
    }

    /// A list row: white and raised when chosen, a grey wash under the mouse otherwise.
    static ControlTemplate RowTemplate()
    {
        var t = new ControlTemplate(typeof(Button));
        var border = new FrameworkElementFactory(typeof(Border), "bg");
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(6));
        border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.PaddingProperty, new System.Windows.Data.Binding("Padding") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.AppendChild(new FrameworkElementFactory(typeof(ContentPresenter)));
        t.VisualTree = border;
        var hover = new MultiTrigger();
        hover.Conditions.Add(new Condition(UIElement.IsMouseOverProperty, true));
        hover.Conditions.Add(new Condition(Control.BackgroundProperty, Brushes.Transparent));
        hover.Setters.Add(new Setter(Border.BackgroundProperty, Palette.Selected, "bg"));
        t.Triggers.Add(hover);
        return t;
    }

    static FrameworkElement Empty(string title, string hint)
    {
        var s = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        var t = Ui.Text(title, 16, Palette.Ink, FontWeights.SemiBold); t.TextAlignment = TextAlignment.Center; s.Children.Add(t);
        if (hint.Length > 0) { var h = Ui.Text(hint, 13, Palette.Secondary); h.TextAlignment = TextAlignment.Center; h.Margin = new Thickness(0, 6, 0, 0); s.Children.Add(h); }
        return s;
    }

    void ShowDetail()
    {
        if (selected is null || app.Store.Get(selected) is not { } s) { detail.Content = Empty(L("还没有会议记录"), ""); return; }
        var live = app.Listen.Listening && app.Listen.SessionId == s.Id;
        var top = new StackPanel { Margin = new Thickness(32, 24, 32, 0) };

        var title = Ui.Text(SessionStore.DisplayTitle(s), 26, Palette.Ink, FontWeights.SemiBold);
        top.Children.Add(Ui.Row(6, title, Ui.IconButton(Icons.Pencil, L("重命名"), () => Rename(s), Palette.Secondary, 32, 16)));
        var spoken = s.Lines.Select(l => l.SrcLang).FirstOrDefault(x => x is not null);
        var into = s.Lines.Select(l => l.DstLang).FirstOrDefault(x => x is not null);
        var meta = new List<string> { Records.Meta(s, app), LF("%@ 句", s.Lines.Count) };
        if (spoken is not null && into is not null) meta.Add($"{Ui.SpokenName(spoken)} → {Ui.TargetName(into)}");
        var metaText = Ui.Text(string.Join(" · ", meta), 13, Palette.Secondary);
        metaText.Margin = new Thickness(0, 6, 0, 0);
        top.Children.Add(metaText);

        var tools = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 14, 0, 0) };
        var hasNotes = s.Notes is { IsEmpty: false };
        if (!hasNotes && !live) tools.Children.Add(Ui.Button(L("生成纪要"), () => _ = app.Notes.Generate(s.Id), Ui.Kind.Primary));
        else
        {
            Button? copy = null;
            copy = Ui.Button(L("复制纪要"), () =>
            {
                try { Clipboard.SetText(SessionStore.NotesMarkdown(s)); } catch (Exception e) { Log.Debug($"copy: failed {e.GetType().Name}"); return; }
                Flash(copy!, L("已复制"));
            }, Ui.Kind.Standard, Icons.Copy);
            copy.IsEnabled = hasNotes;
            tools.Children.Add(copy);
        }
        tools.Children.Add(Spaced(Ui.Button(L("导出"), () => Export(s), Ui.Kind.Subtle, Icons.Export), 4));
        var delete = Ui.Button(L("删除"), () => Delete(s), Ui.Kind.Subtle, Icons.Trash);
        delete.IsEnabled = !live;
        tools.Children.Add(Spaced(delete, 4));
        top.Children.Add(tools);

        var tabs = Ui.Tabs([("notes", L("纪要")), ("transcript", L("文字记录"))], tab, t => { tab = t; ShowDetail(); });
        tabs.Margin = new Thickness(-12, 10, 0, 0);
        top.Children.Add(tabs);

        var dock = new DockPanel();
        DockPanel.SetDock(top, Dock.Top);
        dock.Children.Add(top);
        var rule = new Border { Height = 1, Background = Palette.StrokeSoft };
        DockPanel.SetDock(rule, Dock.Top);
        dock.Children.Add(rule);
        var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(32, 20, 24, 32) };
        scroll.Content = tab == "transcript" ? Transcript(s, scroll) : Notes(s, live);
        dock.Children.Add(scroll);
        detail.Content = dock;
    }

    static T Spaced<T>(T e, double left) where T : FrameworkElement { e.Margin = new Thickness(left, 0, 0, 0); return e; }

    FrameworkElement Notes(Session s, bool live)
    {
        if (s.Notes is not { IsEmpty: false } n)
            return Empty(live ? L("纪要会在开会几分钟后出现") : L("生成纪要"), "");
        var article = new StackPanel { MaxWidth = 680, HorizontalAlignment = HorizontalAlignment.Left };
        if (n.Summary.Length > 0) article.Children.Add(Ui.Text(n.Summary, 15, Palette.Body));
        foreach (var t in n.Topics)
        {
            var start = t.Start;
            var time = Ui.LinkText(Languages.Clock(start), () => { tab = "transcript"; jumpTo = start; ShowDetail(); }, 13);
            var head = Ui.Row(10, time, Ui.Text(t.Title, 16, Palette.Ink, FontWeights.SemiBold));
            head.Margin = new Thickness(0, 20, 0, 0);
            article.Children.Add(head);
            if (t.Summary.Length > 0) article.Children.Add(Gap(Ui.Text(t.Summary, 14, Palette.Secondary), 6));
            foreach (var p in t.Points) article.Children.Add(Gap(Ui.Text("· " + p, 14, Palette.Body), 4));
        }

        var rail = new StackPanel();
        if (n.Conclusions.Count > 0) rail.Children.Add(RailCard(L("结论"), n.Conclusions.Select(c => (FrameworkElement)Ui.Text(c.Text, 14, Palette.Ink))));
        if (n.Todos.Count > 0) rail.Children.Add(RailCard($"{L("待办")} · {n.Todos.Count}", n.Todos.Select(NotesWindow.Todo)));
        var terms = NoteTerm.Ordered(n.Terms).Take(8).ToList();
        if (terms.Count > 0) rail.Children.Add(RailCard(L("术语"), terms.Select(t => (FrameworkElement)Ui.Text(t.Note.Length > 0 ? $"{t.Name} · {t.Note}" : t.Name, 13, Palette.Body))));

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(rail.Children.Count > 0 ? 300 : 0) });
        Grid.SetColumn(rail, 1);
        rail.Margin = new Thickness(24, 0, 0, 0);
        grid.Children.Add(article); grid.Children.Add(rail);
        return grid;
    }

    static FrameworkElement RailCard(string title, IEnumerable<FrameworkElement> items)
    {
        var s = new StackPanel();
        s.Children.Add(Ui.Text(title, 13, Palette.Body, FontWeights.SemiBold));
        foreach (var i in items) s.Children.Add(Gap(i, 10));
        return new Border { Background = Palette.SurfaceAlt, BorderBrush = Palette.StrokeSoft, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8), Padding = new Thickness(16, 14, 16, 14), Margin = new Thickness(0, 0, 0, 16), Child = s };
    }

    FrameworkElement Transcript(Session s, ScrollViewer scroll)
    {
        var body = new StackPanel { MaxWidth = 760, HorizontalAlignment = HorizontalAlignment.Left };
        FrameworkElement? target = null;
        // The line nearest the topic's time (older notes may hold a time no line has).
        var nearest = jumpTo is { } t0 && s.Lines.Count > 0 ? s.Lines.MinBy(l => Math.Abs(l.T - t0)) : null;
        foreach (var l in s.Lines)
        {
            var line = NotesWindow.TranscriptRow(l);
            if (ReferenceEquals(l, nearest)) target = line;
            body.Children.Add(line);
        }
        if (target is Panel row)
        {
            // A topic's time opens the transcript at what was said then, marked for a moment.
            row.Background = Palette.AccentPale;
            // Measured once laid out: before that every row is at the top.
            void Jump(object? _, RoutedEventArgs __)
            {
                row.Loaded -= Jump;
                var y = row.TransformToAncestor(body).Transform(new Point(0, 0)).Y;
                scroll.ScrollToVerticalOffset(Math.Max(0, y - 24));
            }
            row.Loaded += Jump;
            var fade = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
            fade.Tick += (_, _) => { row.Background = Brushes.Transparent; fade.Stop(); };
            fade.Start();
        }
        jumpTo = null;
        return body;
    }

    static FrameworkElement Gap(FrameworkElement e, double top) { e.Margin = new Thickness(0, top, 0, 0); return e; }

    static void Flash(Button b, string text)
    {
        var label = ((StackPanel)b.Content).Children.OfType<TextBlock>().Last();
        var was = label.Text;
        label.Text = text;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        timer.Tick += (_, _) => { label.Text = was; timer.Stop(); };
        timer.Start();
    }

    void Export(Session s)
    {
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            FileName = SafeName(SessionStore.DisplayTitle(s)) + ".md", Filter = "Markdown (*.md)|*.md", DefaultExt = ".md",
        };
        if (dialog.ShowDialog(this) == true) File.WriteAllText(dialog.FileName, SessionStore.Markdown(s));
    }

    static string SafeName(string name) => string.Concat(name.Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '-' : c)).Trim();

    void Rename(Session s)
    {
        var notesTitle = s.Notes?.Title;
        var answer = Dialogs.Prompt(this, L("重命名"), SessionStore.DisplayTitle(s), notesTitle is { Length: > 0 } ? LF("清空就用纪要起的名字：%@", notesTitle) : null, L("保存"));
        if (answer is null) return;
        if (answer.Length == 0) app.Store.ResetTitle(s.Id); else app.Store.Rename(s.Id, answer);
    }

    void Delete(Session s)
    {
        if (Dialogs.Confirm(this, L("删除这次会议？"), LF("“%@”的纪要和文字记录都会删掉，没法恢复。", SessionStore.DisplayTitle(s)), L("删除"), danger: true))
            app.Store.Delete(s.Id);
    }
}
