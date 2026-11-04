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
    readonly double[] levels = new double[32];
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
        Width = 720; Height = 560; ResizeMode = ResizeMode.NoResize;
        Background = Palette.SurfaceAlt; FontFamily = Palette.Font; Icon = AppIcon.Image;
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

    FrameworkElement Stepper()
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(40, 20, 40, 0) };
        string[] names = [L("接上 Ling"), L("系统声音"), L("试一下")];
        for (int i = 0; i < names.Length; i++)
        {
            if (i > 0) row.Children.Add(new Border { Width = 32, Height = 1, Background = Palette.ControlStroke, Margin = new Thickness(10, 0, 10, 0), VerticalAlignment = VerticalAlignment.Center });
            var done = i < step; var now = i == step;
            var badge = new Grid { Width = 22, Height = 22 };
            badge.Children.Add(new Ellipse { Fill = done ? Palette.Success : now ? Palette.Ink : Brushes.Transparent, Stroke = done || now ? null : Palette.Tertiary, StrokeThickness = 1 });
            if (done) badge.Children.Add(Ui.Icon(Icons.Check, 12, Brushes.White, stroke: 2.4));
            else { var n = Ui.Text($"{i + 1}", 12, now ? Brushes.White : Palette.Secondary, FontWeights.SemiBold, wrap: false); n.HorizontalAlignment = HorizontalAlignment.Center; n.VerticalAlignment = VerticalAlignment.Center; badge.Children.Add(n); }
            row.Children.Add(Ui.Row(8, badge, Ui.Text(names[i], 13, now ? Palette.Ink : Palette.Secondary, now ? FontWeights.SemiBold : FontWeights.Normal, wrap: false)));
        }
        return row;
    }

    FrameworkElement Page(string title, string text, params UIElement[] body)
    {
        var s = new StackPanel { Margin = new Thickness(40, 28, 40, 0) };
        s.Children.Add(Ui.Text(title, 26, Palette.Ink, FontWeights.SemiBold));
        var p = Ui.Text(text, 14, Palette.Body);
        p.Margin = new Thickness(0, 8, 0, 0); p.LineHeight = 22;
        s.Children.Add(p);
        foreach (var b in body) { if (b is FrameworkElement f) f.Margin = new Thickness(f.Margin.Left, f.Margin.Top + 18, f.Margin.Right, f.Margin.Bottom); s.Children.Add(b); }
        return s;
    }

    FrameworkElement Footer()
    {
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        var back = Ui.Button(L("上一步"), () => Go(step - 1));
        back.IsEnabled = step > 0;
        buttons.Children.Add(back);
        var next = step switch
        {
            0 => Ui.Button(L("继续"), () => _ = SaveKey(), Ui.Kind.Primary),
            1 => Ui.Button(L("继续"), () => Go(2), peak >= 0.01 ? Ui.Kind.Primary : Ui.Kind.Standard),
            _ => Ui.Button(L("完成"), () => Go(3), Ui.Kind.Primary),
        };
        next.Margin = new Thickness(8, 0, 0, 0);
        next.IsEnabled = !checking;
        buttons.Children.Add(next);
        UIElement left = step == 1 ? Ui.Text(L("没有声音？先确认电脑没静音"), 13, Palette.Secondary, wrap: false) : new Border();
        var row = Ui.Spread(left, buttons);
        ((FrameworkElement)left).VerticalAlignment = VerticalAlignment.Center;
        row.Margin = new Thickness(24, 18, 24, 18);
        return new Border { Background = Palette.Subtle, BorderBrush = Palette.Stroke, BorderThickness = new Thickness(0, 1, 0, 0), Child = row };
    }

    // MARK: 1 · Ling key

    FrameworkElement KeyStep()
    {
        var open = Ui.Button(L("打开 Ling 开放平台"), () => Process.Start(new ProcessStartInfo("https://chat.ant-ling.com/platform/api") { UseShellExecute = true }), Ui.Kind.Standard, Icons.OpenExternal);
        open.HorizontalAlignment = HorizontalAlignment.Left;
        var reveal = Ui.IconButton(Icons.Eye, L("显示 key"), () =>
        {
            var show = keyText.Visibility != Visibility.Visible;
            keyText.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
            keyBox.Visibility = show ? Visibility.Collapsed : Visibility.Visible;
        }, Palette.Body, 36, 16);
        reveal.Margin = new Thickness(4, 0, 0, 0);
        Detach(keyBox); Detach(keyText); Detach(keyStatus);
        var field = new Grid { Children = { keyBox, keyText } };
        var paste = Ui.Button(L("粘贴"), () =>
        {
            try { if (Clipboard.ContainsText()) keyText.Text = Clipboard.GetText().Trim(); } catch { }
            _ = SaveKey();
        });
        var row = new DockPanel();
        DockPanel.SetDock(paste, Dock.Right);
        DockPanel.SetDock(reveal, Dock.Right);
        paste.Margin = new Thickness(4, 0, 0, 0);
        row.Children.Add(paste); row.Children.Add(reveal); row.Children.Add(field);
        var keyLabel = Ui.Text(L("Ling key"), 14, Palette.Ink, FontWeights.SemiBold);
        if (app.Ling.HasKey && keyBox.Password.Length == 0) Status(true, AIKey.Masked(app.Key.Read() ?? "") + " · " + L("可以用"));
        var privacy = Ui.Row(8, Ui.Icon(Icons.Shield, 16, Palette.Secondary), Ui.Text(L("只加密存在这台电脑上，只发给 Ling"), 13, Palette.Secondary));
        return Page(L("接上 Ling"), L("识别、翻译和纪要都靠它。到 Ling 开放平台点“创建令牌”，复制 sk- 开头的那串，粘贴到下面。"),
            open, Ui.Stack(6, keyLabel, row, keyStatus), privacy);
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
        var card = Ui.Card(Ui.Stack(14, Ui.Row(14, Ui.Icon(Icons.Speaker, 22, Palette.Body), meterHost), heardHost), new Thickness(20, 18, 20, 18));
        var lines = new StackPanel();
        if (AudioDevice.DefaultName() is { } device) lines.Children.Add(Ui.Text(LF("正在听：%@", device), 13, Palette.Secondary));
        lines.Children.Add(Ui.Text(L("换成耳机或蓝牙音箱也能接着听。"), 13, Palette.Secondary));
        return Page(L("系统声音"), L("知了听的是电脑播放出来的声音，不用麦克风，也不用授权。放一段视频或音乐试试。"), card, lines);
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
            bars.Children.Add(new Rectangle { Width = 12, Height = 4 + v * 36, RadiusX = 2, RadiusY = 2, Margin = new Thickness(0, 0, 3, 0), VerticalAlignment = VerticalAlignment.Center, Fill = v > 0.08 ? Palette.Live : Palette.Stroke });
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
        var play = Ui.Button(playing ? L("正在播放…") : L("播放示例"), () => _ = PlaySample(), Ui.Kind.Accent, Icons.Play, 52, iconFill: true);
        play.IsEnabled = !playing;
        play.HorizontalAlignment = HorizontalAlignment.Left;
        var startup = new CheckBox { IsChecked = autoStart, Content = Ui.Text(L("开机时启动知了（在任务栏右下角待命）"), 14, Palette.Ink) };
        startup.Click += (_, _) => autoStart = startup.IsChecked == true;
        var howto = Ui.Text(LF("开会时点任务栏里的知了图标，或按 %@ 开始。", Hotkey.Label), 13, Palette.Secondary);
        howto.Margin = new Thickness(28, 6, 0, 0);
        return Page(L("试一下"), L("放一段 9 秒的英文示例会议，看字幕和纪要怎么出现。纪要窗口不会抢走焦点，也不会出现在屏幕共享里。"),
            play, new StackPanel { Children = { startup, howto } });
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
