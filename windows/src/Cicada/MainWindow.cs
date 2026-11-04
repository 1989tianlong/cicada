using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using static Cicada.Strings;

namespace Cicada.App;

/// 会议记录: the meetings on the left, the chosen one's notes and bilingual transcript on the
/// right, on one white sheet (no cards), as the Mac's main window.
sealed class MainWindow : Window
{
    readonly Controller app;
    readonly ListBox list = new() { BorderThickness = new Thickness(0), Background = Brushes.Transparent, FontFamily = Palette.Font };
    readonly ContentControl detail = new();
    string? selected;
    bool refreshQueued;

    /// A record row: grey ground when selected, a lighter one under the mouse; no Windows blue.
    static readonly Style RowStyle = MakeRowStyle();

    static Style MakeRowStyle()
    {
        var template = new ControlTemplate(typeof(ListBoxItem));
        var border = new FrameworkElementFactory(typeof(Border), "bg");
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(8));
        border.SetValue(Border.BackgroundProperty, Brushes.Transparent);
        border.SetValue(Border.MarginProperty, new Thickness(0, 0, 0, 2));
        border.AppendChild(new FrameworkElementFactory(typeof(ContentPresenter)));
        template.VisualTree = border;
        var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Border.BackgroundProperty, Palette.Ground, "bg"));
        var chosen = new Trigger { Property = ListBoxItem.IsSelectedProperty, Value = true };
        chosen.Setters.Add(new Setter(Border.BackgroundProperty, Palette.Line, "bg"));
        template.Triggers.Add(hover); template.Triggers.Add(chosen);
        var style = new Style(typeof(ListBoxItem));
        style.Setters.Add(new Setter(Control.TemplateProperty, template));
        style.Setters.Add(new Setter(FrameworkElement.FocusVisualStyleProperty, null));
        style.Seal();
        return style;
    }

    public MainWindow(Controller app)
    {
        this.app = app;
        Title = L("会议记录") + " · " + L("知了");
        Width = 1000; Height = 680; MinWidth = 720; MinHeight = 480;
        Background = Palette.Card; FontFamily = Palette.Font; Icon = AppIcon.Image;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(290) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        var left = new DockPanel { Margin = new Thickness(12, 16, 8, 12) };
        var top = Ui.Row(8, Ui.Heading(L("会议记录"), 17));
        top.Margin = new Thickness(8, 0, 0, 12);
        DockPanel.SetDock(top, Dock.Top);
        left.Children.Add(top);
        left.Children.Add(list);
        Grid.SetColumn(left, 0);
        var divider = new Border { Background = Palette.Line };
        Grid.SetColumn(divider, 1);
        var right = new ScrollViewer { Content = detail, Padding = new Thickness(32, 24, 32, 32), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Grid.SetColumn(right, 2);
        grid.Children.Add(left); grid.Children.Add(divider); grid.Children.Add(right);
        Content = grid;

        list.SelectionChanged += (_, _) =>
        {
            if (list.SelectedItem is ListBoxItem { Tag: string id } && id != selected) { selected = id; ShowDetail(); }
        };
        Refresh();
    }

    public void Refresh()
    {
        if (refreshQueued) return;
        refreshQueued = true;
        Dispatcher.BeginInvoke(() => { refreshQueued = false; Fill(); });
    }

    void Fill()
    {
        var sessions = app.Store.All();
        list.Items.Clear();
        foreach (var s in sessions)
        {
            var live = app.Listen.Listening && app.Listen.SessionId == s.Id;
            var row = Ui.Stack(2,
                Ui.Text(SessionStore.DisplayTitle(s), 13, Palette.Ink, FontWeights.SemiBold, wrap: false),
                Ui.Text(live ? L("正在听") : $"{s.StartedAt.ToLocalTime():yyyy-MM-dd HH:mm} · {Languages.Clock(s.Duration.TotalSeconds)}", 11, live ? Palette.Accent : Palette.Tertiary, wrap: false));
            row.Margin = new Thickness(6, 6, 6, 6);
            list.Items.Add(new ListBoxItem { Content = row, Tag = s.Id, Style = RowStyle });
        }
        if (sessions.Count == 0) { selected = null; detail.Content = Empty(); return; }
        selected ??= sessions[0].Id;
        if (sessions.All(s => s.Id != selected)) selected = sessions[0].Id;
        list.SelectedItem = list.Items.Cast<ListBoxItem>().First(i => (string)i.Tag == selected);
        ShowDetail();
    }

    static FrameworkElement Empty() => Ui.Stack(6, Ui.Heading(L("还没有会议记录")), Ui.Helper(L("点“开始听”，电脑里播放的声音会变成双语字幕和纪要")));

    void ShowDetail()
    {
        if (selected is null || app.Store.Get(selected) is not { } s) { detail.Content = Empty(); return; }
        var page = new StackPanel { MaxWidth = 720, HorizontalAlignment = HorizontalAlignment.Left };
        var title = Ui.Text(SessionStore.DisplayTitle(s), 22, Palette.Ink, FontWeights.SemiBold);
        page.Children.Add(title);
        page.Children.Add(Gap(Ui.Helper($"{s.StartedAt.ToLocalTime():yyyy-MM-dd HH:mm} · {Languages.Clock(s.Duration.TotalSeconds)} · {s.Lines.Count} {L("句")}"), 4));

        var actions = Ui.Row(8,
            Ui.Button(L("导出"), () => Export(s)),
            Ui.Button(L("重命名"), () => Rename(s)),
            Ui.Button(L("删除"), () => Delete(s)));
        if (s.Notes is null or { IsEmpty: true } && !(app.Listen.Listening && app.Listen.SessionId == s.Id))
            actions.Children.Insert(0, Ui.Button(L("生成纪要"), () => _ = app.Notes.Generate(s.Id), "primary"));
        page.Children.Add(Gap(actions, 14));

        if (s.Notes is { IsEmpty: false } n)
        {
            page.Children.Add(Gap(Ui.Heading(L("纪要"), 16), 28));
            page.Children.Add(Gap(Ui.Text(n.Summary, 14, Palette.Body), 8));
            foreach (var t in n.Topics)
            {
                page.Children.Add(Gap(Ui.Row(8, Ui.Text(Languages.Clock(t.Start), 12, Palette.Link, FontWeights.SemiBold, wrap: false), Ui.Text(t.Title, 14, Palette.Ink, FontWeights.SemiBold)), 16));
                if (t.Summary.Length > 0) page.Children.Add(Gap(Ui.Text(t.Summary, 13, Palette.Secondary), 4));
                foreach (var p in t.Points) page.Children.Add(Gap(Ui.Text("· " + p, 13, Palette.Body), 4));
            }
            Section(page, L("结论"), n.Conclusions.Select(c => c.Text));
            Section(page, L("待办"), n.Todos.Select(t => "☐ " + t.Text + (t.Owner is null ? "" : $" · {t.Owner}")));
        }

        page.Children.Add(Gap(Ui.Heading(L("文字记录"), 16), 28));
        foreach (var l in s.Lines)
        {
            var row = new Grid { Margin = new Thickness(0, 10, 0, 0) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(56) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            var time = Ui.Text(Languages.Clock(l.T), 12, Palette.Link, FontWeights.SemiBold, wrap: false);
            var text = Ui.Stack(2, Ui.Text(l.Src, 14, Palette.Ink));
            if (!string.IsNullOrEmpty(l.Dst) && l.Dst != l.Src) text.Children.Add(Ui.Text(l.Dst, 13, Palette.Secondary));
            Grid.SetColumn(text, 1);
            row.Children.Add(time); row.Children.Add(text);
            page.Children.Add(row);
        }
        detail.Content = page;
    }

    static FrameworkElement Gap(FrameworkElement e, double top) { e.Margin = new Thickness(0, top, 0, 0); return e; }

    static void Section(StackPanel page, string title, IEnumerable<string> items)
    {
        var list = items.ToList();
        if (list.Count == 0) return;
        page.Children.Add(Gap(Ui.Text(title, 13, Palette.Secondary, FontWeights.SemiBold), 18));
        foreach (var i in list) page.Children.Add(Gap(Ui.Text(i, 13, Palette.Body), 4));
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
        var box = new TextBox { Text = SessionStore.DisplayTitle(s), FontSize = 14, Padding = new Thickness(6), MinWidth = 320 };
        var window = Ui.StyledWindow(L("重命名"), 420, 170);
        window.Owner = this;
        window.ResizeMode = ResizeMode.NoResize;
        window.Content = Ui.Card(Ui.Stack(12, box, Ui.Row(8,
            Ui.Button(L("保存"), () => { if (box.Text.Trim().Length > 0) app.Store.Rename(s.Id, box.Text); window.Close(); }, "primary"),
            Ui.Button(L("取消"), window.Close))), 16);
        window.Loaded += (_, _) => { box.Focus(); box.SelectAll(); };
        window.ShowDialog();
    }

    void Delete(Session s)
    {
        var ok = MessageBox.Show(this, LF("删除“%@”？删除后无法恢复。", SessionStore.DisplayTitle(s)), L("删除"), MessageBoxButton.OKCancel, MessageBoxImage.Warning);
        if (ok == MessageBoxResult.OK) app.Store.Delete(s.Id);
    }
}
