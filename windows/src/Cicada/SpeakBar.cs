using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using static Cicada.Strings;

namespace Cicada.App;

/// The bar while I speak: 正在听你说 while the key is held, then what I said and what the room
/// heard, or why nothing went out. Like the notes panel it never takes focus and stays out of
/// screen captures; it sits above the taskbar (above the subtitle bar when that is showing).
sealed class SpeakBar : Window
{
    readonly Controller app;
    readonly ContentControl body = new();
    readonly DispatcherTimer hide = new() { Interval = TimeSpan.FromSeconds(4) };

    public SpeakBar(Controller app)
    {
        this.app = app;
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent; Topmost = true; ShowInTaskbar = false; ShowActivated = false;
        ResizeMode = ResizeMode.NoResize; SizeToContent = SizeToContent.Height; Width = 560 + 2 * Ui.ShadowRoom; FontFamily = Palette.Font; Title = L("知了");
        SourceInitialized += (_, _) =>
        {
            Native.MakeNonActivating(this);
            Native.SetCaptureVisible(this, app.Settings.ShowInCapture);
        };
        Content = Ui.Floating(new Border { Padding = new Thickness(18, 12, 18, 14), Child = body }, new SolidColorBrush(Color.FromArgb(0xF0, 0x15, 0x17, 0x1C)), 14, dark: true);
        SizeChanged += (_, _) => Place();
        hide.Tick += (_, _) => { hide.Stop(); Hide(); };
    }

    void Place()
    {
        var area = SystemParameters.WorkArea;
        Left = area.Left + (area.Width - ActualWidth) / 2;
        var above = app.Settings.View == "subtitles" && app.NotesVisible ? 150 : 16;
        Top = area.Bottom - ActualHeight - above + Ui.ShadowRoom;
    }

    public void Refresh()
    {
        var s = app.Speak;
        hide.Stop();
        var stack = new StackPanel();
        switch (s.State)
        {
            case SpeakEngine.Phase.Recording:
                stack.Children.Add(Ui.Row(10, Ui.LiveDot(10), Ui.Text(L("正在听你说 · 松开发送"), 15, Brushes.White, FontWeights.SemiBold, wrap: false)));
                stack.Children.Add(Gap(Ui.Text(LF("对方会听到%@", Ui.TargetName(s.Target)), 12, Palette.NightText), 4));
                break;
            case SpeakEngine.Phase.Translating:
                stack.Children.Add(Ui.Text(L("正在翻译…"), 15, Brushes.White, FontWeights.SemiBold, wrap: false));
                break;
            case SpeakEngine.Phase.Speaking or SpeakEngine.Phase.Idle when s.Heard is not null:
                if (s.Said is not null) stack.Children.Add(Ui.Text(s.Said, 13, Palette.NightText));
                stack.Children.Add(Gap(Ui.Text(s.Heard!, 18, Brushes.White, FontWeights.SemiBold), 4));
                stack.Children.Add(Gap(Ui.Text(s.State == SpeakEngine.Phase.Speaking ? L("正在说给对方听…") : L("对方已听到"), 12, Palette.NightText), 6));
                if (s.State == SpeakEngine.Phase.Idle) hide.Start();
                break;
            case SpeakEngine.Phase.Failed:
                if (s.Said is not null) stack.Children.Add(Ui.Text(s.Said, 13, Palette.NightText));
                stack.Children.Add(Gap(Ui.Text(s.Problem ?? L("没翻译成功，没有发出去"), 15, new SolidColorBrush(Color.FromRgb(0xFF, 0x9B, 0x78)), FontWeights.SemiBold), 4));
                hide.Start();
                break;
            default:
                Hide();
                return;
        }
        body.Content = stack;
        if (!IsVisible) Show();
        Place();
    }

    static FrameworkElement Gap(FrameworkElement e, double top) { e.Margin = new Thickness(0, top, 0, 0); return e; }
}
