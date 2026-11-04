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
        var monday = DateTime.Today.AddDays(-(((int)DateTime.Today.DayOfWeek + 6) % 7));
        return d == DateTime.Today ? L("今天") : d == DateTime.Today.AddDays(-1) ? L("昨天") : d >= monday ? L("本周") : L("更早");
    }
}

/// 会议记录, as the Mac's main window with no title bar: a grey list of one-line titles grouped by
/// day, the chosen one on a white pill, and the meeting set out like a document on one white
/// sheet: when and how long over a big title, 纪要 / 文字记录, the conclusions and to-dos in one
/// grey block, the summary, then the numbered topics.
sealed class MainWindow : Window
{
    readonly Controller app;
    readonly TextBox search = new();
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
        Width = 1180; Height = Math.Min(780, SystemParameters.WorkArea.Height - 24); MinWidth = 860; MinHeight = 520;
        // One white sheet, as the Mac's main window: no cards, no second layer.
        Background = Palette.Surface; FontFamily = Palette.Font; Icon = AppIcon.Image;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());

        // The search box, with its icon and placeholder drawn over it
        var placeholder = Ui.Text(L("搜索标题、纪要和原话"), 13, Palette.Secondary, wrap: false);
        placeholder.IsHitTestVisible = false; placeholder.Margin = new Thickness(31, 0, 0, 0); placeholder.VerticalAlignment = VerticalAlignment.Center;
        var glass = Ui.Icon(Icons.Search, 16, Palette.Secondary);
        glass.HorizontalAlignment = HorizontalAlignment.Left; glass.Margin = new Thickness(10, 0, 0, 0); glass.IsHitTestVisible = false;
        System.Windows.Automation.AutomationProperties.SetName(search, L("搜索标题、纪要和原话"));
        search.TextChanged += (_, _) => { placeholder.Visibility = search.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed; Fill(); };
        Ui.StyleField(search);
        search.Margin = new Thickness(22, 0, 0, 0);
        placeholder.Margin = new Thickness(22, 0, 0, 0);
        glass.Margin = new Thickness(0);
        var ctrlF = Ui.Keycap("Ctrl F");
        ctrlF.HorizontalAlignment = HorizontalAlignment.Right; ctrlF.IsHitTestVisible = false;
        search.Margin = new Thickness(22, 0, 52, 0);
        var inside = new Grid { Children = { glass, search, placeholder, ctrlF } };
        search.TextChanged += (_, _) => ctrlF.Visibility = search.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        var searchBox = Ui.FieldFrame(inside, search);
        searchBox.Background = Palette.Selected; searchBox.BorderThickness = new Thickness(0); searchBox.Height = 36; searchBox.Padding = new Thickness(12, 0, 6, 0);
        searchBox.Margin = new Thickness(10, 6, 10, 8);
        System.Windows.Shell.WindowChrome.SetIsHitTestVisibleInChrome(searchBox, true);
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.F && System.Windows.Input.Keyboard.Modifiers == System.Windows.Input.ModifierKeys.Control) { search.Focus(); search.SelectAll(); e.Handled = true; }
            else if (e.Key == System.Windows.Input.Key.Escape && search.IsKeyboardFocused) { search.Text = ""; e.Handled = true; }
        };

        // The list pane on the ground's grey, the logo where the title bar was.
        var logo = AppIcon.Small(20);
        logo.HorizontalAlignment = HorizontalAlignment.Left; logo.Margin = new Thickness(18, 14, 0, 6);
        var left = new DockPanel { Background = Palette.Mica };
        DockPanel.SetDock(logo, Dock.Top);
        DockPanel.SetDock(searchBox, Dock.Top);
        left.Children.Add(logo);
        left.Children.Add(searchBox);
        left.Children.Add(new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(10, 0, 10, 12) });

        var right = new Border { Background = Palette.Surface, Child = detail };
        Grid.SetColumn(right, 1);
        grid.Children.Add(left); grid.Children.Add(right);
        Content = Ui.Frameless(this, grid);
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
                var h = Ui.Text(g, 12, Palette.Secondary, wrap: false);
                h.Margin = new Thickness(12, list.Children.Count == 0 ? 8 : 18, 0, 6);
                list.Children.Add(h);
            }
            list.Children.Add(Item(s));
        }
        // An empty page replaces the meeting, so the next real one must draw again.
        if (all.Count == 0) { selected = null; shownKey = null; detail.Content = Empty(L("还没有会议记录"), L("点任务栏里的知了图标，开始听第一场会。")); return; }
        if (shown.Count == 0) { shownKey = null; detail.Content = Empty(L("没有找到"), ""); return; }
        if (selected is null || shown.All(s => s.Id != selected)) selected = shown[0].Id;
        foreach (var child in list.Children.OfType<Button>()) Paint(child);
        // Store changes come in a burst while a meeting runs; redraw the open page only if it changed.
        if (PageKey() == shownKey) return;
        ShowDetail();
    }

    Button Item(Session s)
    {
        var live = app.Listen.Listening && app.Listen.SessionId == s.Id;
        var b = new Button
        {
            Tag = s.Id, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(12, 11, 12, 11), BorderThickness = new Thickness(0),
            Cursor = System.Windows.Input.Cursors.Hand, Margin = new Thickness(0, 0, 0, 2), Background = Brushes.Transparent,
            Content = live ? Ui.Row(8, Ui.LiveDot(6), Ui.Text(SessionStore.DisplayTitle(s), 14, Palette.Ink, wrap: false)) : Ui.Text(SessionStore.DisplayTitle(s), 14, Palette.Ink, wrap: false),
            ToolTip = Records.Meta(s, app),
        };
        b.Template = RowTemplate();
        b.Click += (_, _) => { selected = s.Id; tab = "notes"; foreach (var child in list.Children.OfType<Button>()) Paint(child); ShowDetail(); };
        System.Windows.Automation.AutomationProperties.SetName(b, SessionStore.DisplayTitle(s));
        return b;
    }

    void Paint(Button b)
    {
        var on = (string)b.Tag == selected;
        // The Mac's list: the chosen meeting on a white pill on the grey pane.
        b.Background = on ? Palette.Surface : Brushes.Transparent;
        var label = b.Content as TextBlock ?? (b.Content as Panel)?.Children.OfType<TextBlock>().FirstOrDefault();
        if (label is not null) label.FontWeight = on ? FontWeights.Bold : FontWeights.Normal;
    }

    /// A list row: white and raised when chosen, a grey wash under the mouse otherwise.
    static ControlTemplate RowTemplate()
    {
        var t = new ControlTemplate(typeof(Button));
        var border = new FrameworkElementFactory(typeof(Border), "bg");
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(10));
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
        var t = Ui.Text(title, 16, Palette.Ink); t.TextAlignment = TextAlignment.Center; s.Children.Add(t);
        if (hint.Length > 0) { var h = Ui.Text(hint, 13, Palette.Secondary); h.TextAlignment = TextAlignment.Center; h.Margin = new Thickness(0, 6, 0, 0); s.Children.Add(h); }
        return s;
    }

    /// What the open page shows; a store change that leaves it the same doesn't redraw it.
    string? PageKey() => selected is not null && app.Store.Get(selected) is { } cur
        ? $"{selected}|{tab}|{SessionStore.DisplayTitle(cur)}|{cur.Lines.Count}|{cur.Notes?.Covered}|{cur.Notes?.Final}|{app.Listen.Listening}"
        : null;

    void ShowDetail()
    {
        shownKey = PageKey();
        if (selected is null || app.Store.Get(selected) is not { } s) { detail.Content = Empty(L("还没有会议记录"), ""); return; }
        var live = app.Listen.Listening && app.Listen.SessionId == s.Id;
        var top = new StackPanel();

        // When, how long, and from what into what, above the title.
        var local = s.StartedAt.ToLocalTime();
        var spoken = s.Lines.Select(l => l.SrcLang).FirstOrDefault(x => x is not null);
        var into = s.Lines.Select(l => l.DstLang).FirstOrDefault(x => x is not null);
        var meta = new List<string> { local.ToString(L("M月d日"), Culture) + " " + local.ToString("HH:mm", Culture) };
        meta.Add(live ? L("正在听") : LF("%@ 分钟", Math.Max(1, (int)Math.Round(s.Duration.TotalMinutes))));
        if (spoken is not null && into is not null) meta.Add($"{Ui.SpokenName(spoken)} → {Ui.TargetName(into)}");
        top.Children.Add(Ui.Text(string.Join(" · ", meta), 13, live ? Palette.AccentText : Palette.Secondary));

        var title = Ui.Text(SessionStore.DisplayTitle(s), 28, Palette.Ink, FontWeights.Bold);
        var rename = Ui.IconButton(Icons.Pencil, L("重命名"), () => Rename(s), Palette.Tertiary, 30, 15);
        var titleRow = Ui.Row(6, title, rename);
        titleRow.Margin = new Thickness(0, 6, 0, 0);
        // As the Mac's context menu: only when the notes have a name to go back to.
        if ((s.Renamed ?? !s.Title.StartsWith("会议 ")) && !string.IsNullOrEmpty(s.Notes?.Title))
        {
            var reset = Ui.LinkText(L("恢复自动标题"), () => app.Store.ResetTitle(s.Id));
            reset.VerticalAlignment = VerticalAlignment.Center;
            reset.Margin = new Thickness(6, 0, 0, 0);
            titleRow.Children.Add(reset);
        }
        top.Children.Add(titleRow);

        // 纪要 / 文字记录 on the left, what to do with it on the right, one hairline under both.
        var tabs = Ui.Tabs([("notes", L("纪要")), ("transcript", s.Lines.Count > 0 ? $"{L("文字记录")} {s.Lines.Count}" : L("文字记录"))], tab, t => { tab = t; ShowDetail(); }, 15);
        var tools = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top };
        var hasNotes = s.Notes is { IsEmpty: false };
        if (!hasNotes && !live) tools.Children.Add(Small(Ui.Button(L("生成纪要"), () => _ = app.Notes.Generate(s.Id), Ui.Kind.Primary, height: 32)));
        else
        {
            Button? copy = null;
            copy = Small(Ui.Button(L("复制纪要"), () =>
            {
                try { Clipboard.SetText(SessionStore.NotesMarkdown(s)); } catch (Exception e) { Log.Debug($"copy: failed {e.GetType().Name}"); return; }
                Flash(copy!, L("已复制"));
            }, Ui.Kind.Standard, height: 32));
            copy.IsEnabled = hasNotes;
            tools.Children.Add(copy);
        }
        tools.Children.Add(Spaced(Small(Ui.Button(L("导出…"), () => Export(s), Ui.Kind.Standard, height: 32)), 8));
        Button? more = null;
        more = Ui.Button("···", () =>
        {
            var menu = new ContextMenu { PlacementTarget = more, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom, FontFamily = Palette.Font };
            var r = new MenuItem { Header = L("重命名") }; r.Click += (_, _) => Rename(s); menu.Items.Add(r);
            var d = new MenuItem { Header = L("删除"), IsEnabled = !live, Foreground = Palette.Danger }; d.Click += (_, _) => Delete(s); menu.Items.Add(d);
            menu.IsOpen = true;
        }, Ui.Kind.Standard, height: 32);
        more.MinWidth = 0; more.Width = 36; more.Padding = new Thickness(0);
        tools.Children.Add(Spaced(more, 8));
        var bar = Ui.Spread(tabs, tools);
        bar.Margin = new Thickness(0, 18, 0, 0);
        top.Children.Add(bar);
        top.Children.Add(new Border { Height = 1, Background = Palette.Line });

        // One centred column, like a page: content runs into the old title bar's height.
        var page = new StackPanel { MaxWidth = 700, Margin = new Thickness(48, 56, 48, 48) };
        page.Children.Add(top);
        var body = tab == "transcript" ? Transcript(s) : Notes(s, live);
        body.Margin = new Thickness(0, 28, 0, 0);
        page.Children.Add(body);
        var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = page };
        if (pendingJump is { } jump) { pendingJump = null; jump(scroll); }
        detail.Content = scroll;
    }

    static Button Small(Button b) { b.MinWidth = 0; b.Padding = new Thickness(12, 0, 12, 0); return b; }

    Action<ScrollViewer>? pendingJump;

    static T Spaced<T>(T e, double left) where T : FrameworkElement { e.Margin = new Thickness(left, 0, 0, 0); return e; }

    FrameworkElement Notes(Session s, bool live)
    {
        if (s.Notes is not { IsEmpty: false } n)
            return Empty(live ? L("纪要会在会议进行中自动生成") : L("生成纪要"), "");
        var article = new StackPanel();
        void Jump(double t) { tab = "transcript"; jumpTo = t; ShowDetail(); }

        // The conclusions first, in one quiet grey block; to-dos with an open circle.
        var items = n.Conclusions.Select(c => (c, todo: false)).Concat(n.Todos.Select(t => (c: t, todo: true))).ToList();
        if (items.Count > 0)
        {
            var block = new StackPanel();
            block.Children.Add(Ui.Text(n.Todos.Count == 0 ? L("结论") : L("结论和待办"), 13, Palette.Secondary));
            foreach (var (item, todo) in items)
            {
                var row = new DockPanel { Margin = new Thickness(0, 12, 0, 0) };
                FrameworkElement mark = todo
                    ? new System.Windows.Shapes.Ellipse { Width = 11, Height = 11, Stroke = Palette.Live, StrokeThickness = 1.5 }
                    : new System.Windows.Shapes.Ellipse { Width = 5, Height = 5, Fill = Palette.Body };
                var markBox = new Border { Width = 26, Height = 20, Child = mark, VerticalAlignment = VerticalAlignment.Top };
                mark.HorizontalAlignment = HorizontalAlignment.Left; mark.VerticalAlignment = VerticalAlignment.Center;
                DockPanel.SetDock(markBox, Dock.Left);
                row.Children.Add(markBox);
                if (item.T is { } t)
                {
                    var at = Ui.LinkText(Languages.Clock(t), () => Jump(t), 13);
                    at.VerticalAlignment = VerticalAlignment.Top; at.Margin = new Thickness(16, 1, 0, 0);
                    DockPanel.SetDock(at, Dock.Right);
                    row.Children.Add(at);
                }
                row.Children.Add(Ui.Text(item.Text + (item.Owner is { Length: > 0 } o ? $"（{o}）" : ""), 15, item.Support == 0 ? Palette.Tertiary : Palette.Ink));
                block.Children.Add(row);
            }
            article.Children.Add(new Border { Background = Palette.Mica, CornerRadius = new CornerRadius(16), Padding = new Thickness(26, 22, 26, 22), Child = block, Margin = new Thickness(0, 0, 0, 32) });
        }

        if (n.Summary.Length > 0)
        {
            var sum = Ui.Text(n.Summary, 15, Palette.Body);
            sum.LineHeight = 28;
            article.Children.Add(sum);
        }

        // The topics as numbered rows between hairlines.
        if (n.Topics.Count > 0)
        {
            var label = Ui.Text(L("议题"), 13, Palette.Secondary);
            label.Margin = new Thickness(0, 36, 0, 10);
            article.Children.Add(label);
            for (int i = 0; i < n.Topics.Count; i++)
            {
                var t = n.Topics[i];
                article.Children.Add(new Border { Height = 1, Background = Palette.Line });
                var num = Ui.Text($"{i + 1:00}", 14, Palette.AccentText, wrap: false);
                num.Width = 40; num.VerticalAlignment = VerticalAlignment.Top; num.Margin = new Thickness(0, 2, 0, 0);
                var start = t.Start;
                var at = Ui.LinkText(Languages.Clock(start), () => Jump(start), 13);
                at.VerticalAlignment = VerticalAlignment.Top; at.Margin = new Thickness(16, 2, 0, 0);
                var text = new StackPanel();
                var head = Ui.Row(8, Ui.Text(t.Title, 17, Palette.Ink, FontWeights.Bold));
                if (live && i == n.Topics.Count - 1) head.Children.Add(Spaced(Ui.Badge(L("正在讲")), 8));
                text.Children.Add(head);
                if (t.Summary.Length > 0) text.Children.Add(Gap(Ui.Text(t.Summary, 14, Palette.Body), 8));
                foreach (var p in t.Points) text.Children.Add(Gap(Ui.Text("· " + p, 14, Palette.Secondary), 4));
                var row = new DockPanel { Margin = new Thickness(0, 18, 0, 20) };
                DockPanel.SetDock(num, Dock.Left); DockPanel.SetDock(at, Dock.Right);
                row.Children.Add(num); row.Children.Add(at); row.Children.Add(text);
                article.Children.Add(row);
            }
            article.Children.Add(new Border { Height = 1, Background = Palette.Line });
        }

        var terms = NoteTerm.Ordered(n.Terms).Take(12).ToList();
        if (terms.Count > 0)
        {
            var label = Ui.Text(L("人名和术语"), 13, Palette.Secondary);
            label.Margin = new Thickness(0, 36, 0, 10);
            article.Children.Add(label);
            var chips = new WrapPanel();
            foreach (var t in terms)
                chips.Children.Add(new Border { Background = Palette.Mica, CornerRadius = new CornerRadius(8), Padding = new Thickness(10, 5, 10, 6), Margin = new Thickness(0, 0, 8, 8), Child = Ui.Text(t.Note.Length > 0 ? $"{t.Name} · {t.Note}" : t.Name, 13, Palette.Body, wrap: false) });
            article.Children.Add(chips);
        }
        return article;
    }

    FrameworkElement Transcript(Session s)
    {
        var body = new StackPanel();
        FrameworkElement? target = null;
        // The line nearest the topic's time (older notes may hold a time no line has).
        var nearest = jumpTo is { } t0 && s.Lines.Count > 0 ? s.Lines.MinBy(l => Math.Abs(l.T - t0)) : null;
        foreach (var (l, who, ink) in NotesWindow.Speakers(s.Lines, app.Settings.SpeakerVoices))
        {
            var line = NotesWindow.TranscriptRow(l, who, ink);
            if (ReferenceEquals(l, nearest)) target = line;
            body.Children.Add(line);
        }
        if (target is Panel row)
        {
            // A topic's time opens the transcript at what was said then, marked for a moment.
            row.Background = Palette.AccentPale;
            // Measured once laid out: before that every row is at the top.
            pendingJump = scroll =>
            {
                void Jump(object? _, RoutedEventArgs __)
                {
                    row.Loaded -= Jump;
                    var y = row.TransformToAncestor(scroll).Transform(new Point(0, 0)).Y;
                    scroll.ScrollToVerticalOffset(Math.Max(0, scroll.VerticalOffset + y - 24));
                }
                row.Loaded += Jump;
            };
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
