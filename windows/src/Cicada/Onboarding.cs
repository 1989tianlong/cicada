using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using static Cicada.Strings;

namespace Cicada.App;

/// First run, as a Windows setup window: a stepper, one task per step, Back / Continue at the
/// bottom right. Windows needs no permission for system audio and listening needs the Ling key
/// (recognition is Ming's), so: 接上 Ling → 系统声音 → 试一下.
sealed class Onboarding : Window
{
    readonly Controller app;
    readonly ContentControl stepper = new(), page = new(), footer = new();
    int step;
    SystemAudioTap? tap;
    readonly DispatcherTimer meter = new() { Interval = TimeSpan.FromMilliseconds(80) };
    readonly double[] levels = new double[44];
    double level, peak;
    bool autoStart = true, playing;
    // Step 1: the key field and what we know about it
    readonly PasswordBox keyBox = new() { FontSize = 14, MinHeight = 34, VerticalContentAlignment = VerticalAlignment.Center };
    readonly TextBox keyText = new() { FontSize = 14, MinHeight = 34, VerticalContentAlignment = VerticalAlignment.Center, Visibility = Visibility.Collapsed };
    readonly ContentControl keyStatus = new();
    bool checking;

    public Onboarding(Controller app)
    {
        this.app = app;
        Title = L("设置知了");
        Width = 760; Height = 640; ResizeMode = ResizeMode.NoResize;
        Background = Palette.Page; FontFamily = Palette.Font; Icon = AppIcon.Image;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var dock = new DockPanel();
        DockPanel.SetDock(stepper, Dock.Top);
        DockPanel.SetDock(footer, Dock.Bottom);
        dock.Children.Add(stepper); dock.Children.Add(footer); dock.Children.Add(page);
        Content = dock;
        meter.Tick += (_, _) => { if (step == 1) Meter(); };
        Closed += (_, _) => StopTap();
        System.Windows.Automation.AutomationProperties.SetName(keyBox, L("Ling key"));
        System.Windows.Automation.AutomationProperties.SetName(keyText, L("Ling key"));
        keyBox.PasswordChanged += (_, _) => { if (keyText.Text != keyBox.Password) keyText.Text = keyBox.Password; };
        keyText.TextChanged += (_, _) => { if (keyBox.Password != keyText.Text) keyBox.Password = keyText.Text; };
        step = app.Ling.HasKey ? 1 : 0;
        Render();
    }

    void Go(int to)
    {
        StopTap();
        if (to > 2)
        {
            AutoStart.Enabled = autoStart;
            app.Settings.Onboarded = true; app.Settings.Save();
            Close();
            app.ShowFlyout();
            return;
        }
        step = Math.Max(0, to);
        Render();
    }

    void Render()
    {
        stepper.Content = Stepper();
        page.Content = step switch { 0 => KeyStep(), 1 => AudioStep(), _ => SampleStep() };
        footer.Content = Footer();
    }

    // The Mac's setup layout (Onboarding.swift): the logo and a bar per step along the top, a big
    // bold heading with one grey line, the task in one white card, Back and Continue at the bottom.
    FrameworkElement Stepper()
    {
        var grid = new Grid { Margin = new Thickness(40, 28, 40, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        string[] names = [L("接上 Ling"), L("系统声音"), L("试一下")];
        for (int i = 0; i < names.Length; i++) grid.ColumnDefinitions.Add(new ColumnDefinition());
        var logo = AppIcon.Small(40);
        logo.Margin = new Thickness(0, 0, 18, 0);
        grid.Children.Add(logo);
        for (int i = 0; i < names.Length; i++)
        {
            var reached = i <= step;
            var bar = new Border { Height = 4, CornerRadius = new CornerRadius(2), Background = reached ? Palette.Ink : Palette.Line };
            var name = Ui.Text(names[i], 13, i == step ? Palette.Ink : Palette.Secondary, i == step ? FontWeights.Bold : FontWeights.Normal, wrap: false);
            name.Margin = new Thickness(0, 9, 0, 0);
            var col = new StackPanel { Margin = new Thickness(i == 0 ? 0 : 6, 6, 0, 0), Children = { bar, name } };
            Grid.SetColumn(col, i + 1);
            grid.Children.Add(col);
        }
        return grid;
    }

    FrameworkElement Page(string title, string text, params UIElement[] body)
    {
        var s = new StackPanel { Margin = new Thickness(40, 36, 40, 0) };
        s.Children.Add(Ui.Text(title, 28, Palette.Ink, FontWeights.Bold));
        var p = Ui.Text(text, 15, Palette.Secondary);
        p.Margin = new Thickness(0, 10, 0, 0); p.LineHeight = 22;
        s.Children.Add(p);
        foreach (var b in body) { if (b is FrameworkElement f) f.Margin = new Thickness(f.Margin.Left, f.Margin.Top + 24, f.Margin.Right, f.Margin.Bottom); s.Children.Add(b); }
        return s;
    }

    /// The Mac's white step card: 18-point corners and a hairline.
    static Border StepCard(UIElement child) => new()
    {
        Background = Brushes.White, BorderBrush = Palette.Line, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(18),
        Padding = new Thickness(28, 24, 28, 24), Child = child,
    };

    /// A numbered row in a step card: a grey disc with the number, a bold line, a grey line.
    static FrameworkElement Numbered(int n, string title, string? detail, UIElement? right = null, UIElement? below = null)
    {
        var disc = new Grid { Width = 32, Height = 32, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 0, 16, 0) };
        disc.Children.Add(new Ellipse { Fill = Palette.Mica });
        var num = Ui.Text($"{n}", 15, Palette.Ink, FontWeights.Bold, wrap: false); num.HorizontalAlignment = HorizontalAlignment.Center; num.VerticalAlignment = VerticalAlignment.Center;
        disc.Children.Add(num);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Ui.Text(title, 17, Palette.Ink, FontWeights.Bold));
        if (detail is not null) { var d = Ui.Text(detail, 13, Palette.Secondary); d.Margin = new Thickness(0, 3, 0, 0); text.Children.Add(d); }
        if (below is FrameworkElement b) { b.Margin = new Thickness(0, 12, 0, 0); text.Children.Add(b); }
        var dock = new DockPanel();
        DockPanel.SetDock(disc, Dock.Left);
        dock.Children.Add(disc);
        if (right is FrameworkElement r) { DockPanel.SetDock(r, Dock.Right); r.VerticalAlignment = VerticalAlignment.Center; r.Margin = new Thickness(16, 0, 0, 0); dock.Children.Add(r); }
        dock.Children.Add(text);
        return dock;
    }

    static FrameworkElement Divider() => new Border { Height = 1, Background = Palette.Line, Margin = new Thickness(0, 20, 0, 20) };

    FrameworkElement Footer()
    {
        var back = Ui.Button(L("上一步"), () => Go(step - 1), Ui.Kind.Subtle, height: 48);
        back.MinWidth = 0; back.HorizontalAlignment = HorizontalAlignment.Left;
        back.Visibility = step > 0 ? Visibility.Visible : Visibility.Hidden;
        var next = step switch
        {
            0 => Ui.Button(L("继续"), () => _ = SaveKey(), Ui.Kind.Primary, height: 48),
            1 => Ui.Button(L("继续"), () => Go(2), peak >= 0.01 ? Ui.Kind.Primary : Ui.Kind.Standard, height: 48),
            _ => Ui.Button(L("完成"), () => Go(3), Ui.Kind.Primary, height: 48),
        };
        next.MinWidth = 150; next.HorizontalAlignment = HorizontalAlignment.Right;
        next.IsEnabled = !checking;
        var right = new StackPanel { Orientation = Orientation.Horizontal };
        if (step == 1)
        {
            var hint = Ui.Text(L("没有声音？先确认电脑没静音"), 13, Palette.Secondary, wrap: false);
            hint.VerticalAlignment = VerticalAlignment.Center; hint.Margin = new Thickness(0, 0, 16, 0);
            right.Children.Add(hint);
        }
        right.Children.Add(next);
        var row = Ui.Spread(back, right);
        row.Margin = new Thickness(28, 16, 40, 28);
        return row;
    }

    // MARK: 1 · Ling key

    FrameworkElement KeyStep()
    {
        var open = Ui.Button(L("打开 Ling 开放平台 ↗"), () => Process.Start(new ProcessStartInfo("https://chat.ant-ling.com/platform/api") { UseShellExecute = true }));
        open.HorizontalAlignment = HorizontalAlignment.Right;
        var reveal = Ui.IconButton(Icons.Eye, L("显示 key"), () =>
        {
            var show = keyText.Visibility != Visibility.Visible;
            keyText.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
            keyBox.Visibility = show ? Visibility.Collapsed : Visibility.Visible;
        }, Palette.Secondary, 32, 16);
        Detach(keyBox); Detach(keyText); Detach(keyStatus);
        var hint = Ui.Text("sk-…", 14, Palette.Tertiary, wrap: false);
        hint.IsHitTestVisible = false; hint.VerticalAlignment = VerticalAlignment.Center;
        void Hint() => hint.Visibility = keyBox.Password.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        keyBox.PasswordChanged += (_, _) => Hint();
        Hint();
        var boxes = new Grid { Children = { keyBox, keyText, hint } };
        var inner = new DockPanel();
        DockPanel.SetDock(reveal, Dock.Right);
        inner.Children.Add(reveal); inner.Children.Add(boxes);
        Ui.StyleField(keyBox); Ui.StyleField(keyText);
        var field = Ui.FieldFrame(inner, keyBox);
        field.Padding = new Thickness(12, 0, 4, 0);
        var paste = Ui.Button(L("粘贴并检查"), () =>
        {
            try { if (Clipboard.ContainsText()) keyText.Text = Clipboard.GetText().Trim(); } catch { }
            _ = SaveKey();
        }, Ui.Kind.Primary, Icons.Copy, height: 40);
        var row = new DockPanel();
        DockPanel.SetDock(paste, Dock.Right);
        paste.Margin = new Thickness(10, 0, 0, 0);
        row.Children.Add(paste); row.Children.Add(field);
        if (app.Ling.HasKey && keyBox.Password.Length == 0) Status(true, AIKey.Masked(app.Key.Read() ?? "") + " · " + L("可以用"));
        var privacy = Ui.Row(8, Ui.Icon(Icons.Shield, 15, Palette.Secondary), Ui.Text(L("只加密存在这台电脑上，只发给 Ling"), 13, Palette.Secondary));
        keyStatus.Margin = new Thickness(0, 8, 0, 0);
        var second = new StackPanel { Children = { row, keyStatus, privacy } };
        privacy.Margin = new Thickness(0, 10, 0, 0);
        var card = StepCard(new StackPanel
        {
            Children =
            {
                Numbered(1, L("在 Ling 开放平台创建 key"), L("注册或登录后点“创建令牌”"), open),
                Divider(),
                Numbered(2, L("复制 sk- 开头的 key，回来粘贴"), null, below: second),
            },
        });
        return Page(L("接上 Ling，用上完整的知了"), L("识别、翻译和纪要都靠它，约 1 分钟。"), card);
    }

    static void Detach(FrameworkElement e) { if (e.Parent is Panel p) p.Children.Remove(e); else if (e.Parent is ContentControl c) c.Content = null; else if (e.Parent is Decorator d) d.Child = null; }

    void Status(bool? ok, string text)
    {
        var color = ok == true ? Palette.Success : ok == false ? Palette.Danger : Palette.Secondary;
        var icon = ok == true ? (FrameworkElement)new Grid { Width = 16, Height = 16, Children = { new Ellipse { Fill = Palette.Success }, Ui.Icon(Icons.Check, 16, Brushes.White, stroke: 2) } } : new Border();
        keyStatus.Content = Ui.Row(6, icon, Ui.Text(text, 13, color));
    }

    async Task SaveKey()
    {
        var text = keyBox.Password.Trim();
        if (text.Length == 0 && app.Ling.HasKey) { Go(1); return; }
        if (!text.StartsWith("sk-")) { Status(false, L("要粘贴 sk- 开头的那串")); return; }
        checking = true; footer.Content = Footer();
        Status(null, L("正在检查…"));
        var previous = app.Key.Read();
        app.Key.Save(text);
        app.Ling.KeyChanged();
        var (state, _) = await app.Ling.Check();
        checking = false; footer.Content = Footer();
        if (state == KeyState.Ok) { Status(true, L("可以用")); await Task.Delay(400); Go(1); return; }
        // A key Ling turned down isn't kept: the one that worked before, if any, comes back.
        if (state == KeyState.Invalid)
        {
            if (previous is not null) app.Key.Save(previous); else app.Key.Remove();
            app.Ling.KeyChanged();
        }
        Status(false, state == KeyState.Invalid ? L("这个 key 不能用，检查是否复制完整，或重新创建一个") : L("连不上 Ling，检查网络"));
    }

    // MARK: 2 · System audio

    readonly ContentControl meterHost = new(), heardHost = new();

    FrameworkElement AudioStep()
    {
        if (tap is null)
        {
            tap = new SystemAudioTap();
            tap.Samples += buf =>
            {
                double sum = 0;
                foreach (var s in buf) sum += (double)s * s;
                var rms = buf.Length == 0 ? 0 : Math.Sqrt(sum / buf.Length) / 32768;
                // The loudest buffer since the last bar, not the last one (often a silent fill).
                level = Math.Max(level, rms);
                peak = Math.Max(peak, rms);
            };
            tap.Start();
            meter.Start();
        }
        Detach(meterHost); Detach(heardHost);
        Meter();
        var device = AudioDevice.DefaultName();
        var card = StepCard(new StackPanel
        {
            Children =
            {
                Ui.Row(14, Ui.Icon(Icons.Speaker, 22, Palette.Body), meterHost),
                new Border { Height = 14 }, heardHost,
                Divider(),
                Ui.Text(device is null ? L("换成耳机或蓝牙音箱也能接着听。") : $"{LF("正在听：%@", device)} · {L("换成耳机或蓝牙音箱也能接着听。")}", 13, Palette.Secondary),
            },
        });
        return Page(L("系统声音"), L("知了听的是电脑播放出来的声音，不用麦克风，也不用授权。放一段视频或音乐试试。"), card);
    }

    /// 32 bars of the last few seconds of loudness, newest on the right.
    void Meter()
    {
        // A rolling history of the loudness, eased so a word reads as a rise and fall, not one spike.
        Array.Copy(levels, 1, levels, 0, levels.Length - 1);
        levels[^1] = Math.Max(Loudness(level), levels[^2] * 0.7);
        level = 0;
        var bars = new StackPanel { Orientation = Orientation.Horizontal, Height = 40 };
        foreach (var v in levels)
            bars.Children.Add(new Rectangle { Width = 3, Height = 4 + v * 36, RadiusX = 1.5, RadiusY = 1.5, Margin = new Thickness(0, 0, 9, 0), VerticalAlignment = VerticalAlignment.Center, Fill = v > 0.08 ? Palette.Live : Palette.Line });
        System.Windows.Automation.AutomationProperties.SetName(bars, L("系统声音"));
        meterHost.Content = bars;
        var heard = peak >= 0.01;
        var was = heardHost.Tag as bool?;
        if (was != heard)
        {
            heardHost.Tag = heard;
            heardHost.Content = heard
                ? Ui.Row(8, new Grid { Width = 18, Height = 18, Children = { new Ellipse { Fill = Palette.Success }, Ui.Icon(Icons.Check, 18, Brushes.White, stroke: 2) } }, Ui.Text(L("听到了"), 14, Palette.Success, FontWeights.SemiBold, wrap: false))
                : Ui.Text(L("还没听到声音"), 14, Palette.Secondary, wrap: false);
            footer.Content = Footer();
        }
    }

    /// -50 dBFS (a quiet room) to 0 dBFS on a log scale, so speech sits mid-bar instead of pinning it.
    static double Loudness(double rms) => rms <= 0 ? 0 : Math.Clamp((20 * Math.Log10(rms) + 50) / 50, 0, 1);

    // MARK: 3 · Try it

    FrameworkElement SampleStep()
    {
        var play = Ui.Button(playing ? L("正在播放…") : L("播放示例"), () => _ = PlaySample(), Ui.Kind.Accent, Icons.Play, 48, iconFill: true);
        play.IsEnabled = !playing;
        play.MinWidth = 160;
        var startup = Ui.Switch(autoStart, v => autoStart = v, L("开机时启动知了"));
        var card = StepCard(new StackPanel
        {
            Children =
            {
                Numbered(1, L("播放示例"), L("一段 9 秒的英文会议"), play),
                Divider(),
                Numbered(2, L("开机时启动知了"), LF("开会时点任务栏里的知了图标，或按 %@ 开始。", Hotkey.Label), startup),
            },
        });
        return Page(L("试一下"), L("看字幕和纪要怎么出现。纪要窗口不会抢走焦点，也不会出现在屏幕共享里。"), card);
    }

    async Task PlaySample()
    {
        // The notes panel opens along the right edge; keep the wizard's buttons clear of it.
        var area = SystemParameters.WorkArea;
        var room = area.Right - 440 - area.Left;
        Left = Math.Max(area.Left + 8, Math.Min(Left, room - Width));
        playing = true; Render();
        try { await app.PlaySample(); }
        finally { playing = false; if (IsLoaded) Render(); }
    }

    void StopTap()
    {
        meter.Stop();
        tap?.Stop();
        tap = null;
    }
}
