using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using static Cicada.Strings;

namespace Cicada.App;

/// First run, three steps. Windows needs no permission for system audio, and listening needs the
/// Ling key (recognition is Ming's), so the key comes first: Ling key → system audio → sample meeting.
sealed class Onboarding : Window
{
    readonly Controller app;
    readonly ContentControl page = new();
    int step;
    SystemAudioTap? tap;
    readonly DispatcherTimer meter = new() { Interval = TimeSpan.FromMilliseconds(100) };
    double level, peak;

    public Onboarding(Controller app)
    {
        this.app = app;
        Title = L("知了");
        Width = 520; Height = 460; ResizeMode = ResizeMode.NoResize;
        Background = Palette.Ground; FontFamily = Palette.Font; Icon = AppIcon.Image;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Content = new Border { Padding = new Thickness(24), Child = page };
        meter.Tick += (_, _) => { if (step == 1) Render(); };
        Closed += (_, _) => StopTap();
        step = app.Ling.HasKey ? 1 : 0;
        Render();
    }

    void Next()
    {
        StopTap();
        step++;
        if (step > 2) { app.Settings.Onboarded = true; app.Settings.Save(); Close(); return; }
        Render();
    }

    void Render() => page.Content = step switch { 0 => KeyStep(), 1 => AudioStep(), _ => SampleStep() };

    FrameworkElement Frame(string title, string helper, FrameworkElement body, FrameworkElement buttons)
    {
        var dots = Ui.Row(6, Enumerable.Range(0, 3).Select(i => Ui.Dot(i == step ? Palette.Accent : Palette.Line, 7)).ToArray());
        var dock = new DockPanel();
        DockPanel.SetDock(buttons, Dock.Bottom);
        buttons.HorizontalAlignment = HorizontalAlignment.Right;
        dock.Children.Add(buttons);
        dock.Children.Add(Ui.Card(Ui.Stack(12, dots, Ui.Heading(title, 18), Ui.Helper(helper), body), 24));
        return dock;
    }

    FrameworkElement KeyStep()
    {
        var box = new PasswordBox { FontSize = 13, Padding = new Thickness(6) };
        var status = Ui.Helper("");
        async void Save()
        {
            var text = box.Password.Trim();
            if (!text.StartsWith("sk-")) { status.Text = L("复制 sk- 开头的 key，回来粘贴"); return; }
            app.Key.Save(text);
            app.Ling.KeyChanged();
            status.Text = L("正在检查…");
            var (state, _) = await app.Ling.Check();
            if (state == KeyState.Ok) Next();
            else status.Text = state == KeyState.Invalid ? L("这个 key 无效，请检查是否复制完整，或重新创建一个") : L("连不上 Ling，检查网络");
        }
        var body = Ui.Stack(10,
            Ui.LinkText(L("在 Ling 开放平台创建 key"), () => Process.Start(new ProcessStartInfo("https://chat.ant-ling.com/platform/api") { UseShellExecute = true })),
            Ui.Helper(L("在 Ling 开放平台点“创建令牌”，复制以 sk- 开头的那串。")),
            box, status);
        return Frame(L("接上 Ling，用上完整的知了"), L("识别、翻译和纪要都靠它，约 1 分钟。"), body, Ui.Row(8, Ui.Button(L("继续"), Save, "primary")));
    }

    FrameworkElement AudioStep()
    {
        if (tap is null)
        {
            tap = new SystemAudioTap();
            tap.Samples += buf =>
            {
                double sum = 0;
                foreach (var s in buf) sum += (double)s * s;
                level = buf.Length == 0 ? 0 : Math.Sqrt(sum / buf.Length) / 32768;
                peak = Math.Max(peak, level);
            };
            tap.Start();
            meter.Start();
        }
        var bar = new ProgressBar { Minimum = 0, Maximum = 1, Value = Loudness(level), Height = 8, Foreground = Palette.Accent, Background = Palette.Ground, BorderThickness = new Thickness(0) };
        var heard = peak >= 0.01;
        var body = Ui.Stack(12, bar, Ui.Text(heard ? L("听到了") : L("放一段视频或音乐，看这条有没有跳动"), 13, heard ? Palette.Ink : Palette.Secondary));
        return Frame(L("系统声音"), L("知了听的是电脑播放出来的声音，不用麦克风，也不用授权。"), body,
            Ui.Row(8, Ui.Button(L("继续"), Next, heard ? "primary" : "quiet")));
    }

    /// -50 dBFS (a quiet room) to 0 dBFS on a log scale, so speech sits mid-bar instead of pinning it.
    static double Loudness(double rms) => rms <= 0 ? 0 : Math.Clamp((20 * Math.Log10(rms) + 50) / 50, 0, 1);

    FrameworkElement SampleStep()
    {
        var body = Ui.Stack(10, Ui.Text(L("播放一段约 9 秒的示例会议，看字幕和纪要怎么出现。"), 13, Palette.Secondary));
        return Frame(L("示例会议"), L("纪要窗口不会抢走焦点，也不会出现在屏幕共享里。"), body,
            Ui.Row(8, Ui.Button(L("播放示例"), () => _ = app.PlaySample(), "accent"), Ui.Button(L("完成"), Next, "primary")));
    }

    void StopTap()
    {
        meter.Stop();
        tap?.Stop();
        tap = null;
    }
}
