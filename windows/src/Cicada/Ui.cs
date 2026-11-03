using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using static Cicada.Strings;

namespace Cicada.App;

/// The Mac's palette (Views.swift › Palette) and a few builders, so every window is made the same
/// way in code: ground #F3F4F6, white cards, ink #15171C, one accent #E8552B for "live".
static class Palette
{
    static SolidColorBrush B(byte r, byte g, byte b) { var x = new SolidColorBrush(Color.FromRgb(r, g, b)); x.Freeze(); return x; }
    public static readonly SolidColorBrush Ground = B(0xF3, 0xF4, 0xF6);
    public static readonly SolidColorBrush Card = B(0xFF, 0xFF, 0xFF);
    public static readonly SolidColorBrush Ink = B(0x15, 0x17, 0x1C);
    public static readonly SolidColorBrush Body = B(0x3D, 0x41, 0x4A);
    public static readonly SolidColorBrush Secondary = B(0x5A, 0x5F, 0x6B);
    public static readonly SolidColorBrush Tertiary = B(0x6B, 0x70, 0x80);
    public static readonly SolidColorBrush Line = B(0xE4, 0xE6, 0xEA);
    public static readonly SolidColorBrush Accent = B(0xE8, 0x55, 0x2B);
    public static readonly SolidColorBrush AccentPale = B(0xFD, 0xEB, 0xE4);
    public static readonly SolidColorBrush Link = B(0xB3, 0x3B, 0x14);
    public static readonly SolidColorBrush ErrorPale = B(0xFD, 0xEC, 0xEC);
    public static readonly FontFamily Font = new("Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI, Yu Gothic UI, Malgun Gothic");
}

static class Ui
{
    public static TextBlock Text(string text, double size = 13, Brush? color = null, FontWeight? weight = null, bool wrap = true) => new()
    {
        Text = text, FontSize = size, Foreground = color ?? Palette.Ink, FontWeight = weight ?? FontWeights.Normal,
        TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap, TextTrimming = wrap ? TextTrimming.None : TextTrimming.CharacterEllipsis,
        FontFamily = Palette.Font,
    };

    public static TextBlock Heading(string text, double size = 15) => Text(text, size, Palette.Ink, FontWeights.SemiBold);
    public static TextBlock Helper(string text) => Text(text, 12, Palette.Tertiary);

    public static Border Card(UIElement child, double padding = 16, double radius = 12) => new()
    {
        Background = Palette.Card, CornerRadius = new CornerRadius(radius), Padding = new Thickness(padding), Child = child,
    };

    public static StackPanel Stack(double gap, params UIElement[] children)
    {
        var s = new StackPanel();
        foreach (var c in children)
        {
            if (c is FrameworkElement f && s.Children.Count > 0) f.Margin = new Thickness(f.Margin.Left, f.Margin.Top + gap, f.Margin.Right, f.Margin.Bottom);
            s.Children.Add(c);
        }
        return s;
    }

    public static StackPanel Row(double gap, params UIElement[] children)
    {
        var s = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var c in children)
        {
            if (c is FrameworkElement f && s.Children.Count > 0) f.Margin = new Thickness(f.Margin.Left + gap, f.Margin.Top, f.Margin.Right, f.Margin.Bottom);
            if (c is FrameworkElement v) v.VerticalAlignment = VerticalAlignment.Center;
            s.Children.Add(c);
        }
        return s;
    }

    /// A flat button: filled ink (primary), filled accent (live) or a quiet grey one.
    public static Button Button(string label, Action onClick, string kind = "quiet")
    {
        var (bg, fg) = kind switch
        {
            "primary" => (Palette.Ink, Brushes.White),
            "accent" => (Palette.Accent, Brushes.White),
            _ => (Palette.Ground, Palette.Ink),
        };
        var b = new Button
        {
            Content = new TextBlock { Text = label, FontSize = 13, FontWeight = FontWeights.SemiBold, FontFamily = Palette.Font },
            Foreground = fg, Background = bg, BorderThickness = new Thickness(0), Padding = new Thickness(14, 7, 14, 7),
            Cursor = Cursors.Hand, Focusable = false,
        };
        b.Template = RoundedTemplate(8);
        b.Click += (_, _) => onClick();
        return b;
    }

    /// A button with rounded corners and no Windows chrome.
    static ControlTemplate RoundedTemplate(double radius)
    {
        var t = new ControlTemplate(typeof(Button));
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(radius));
        border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.PaddingProperty, new System.Windows.Data.Binding("Padding") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        var content = new FrameworkElementFactory(typeof(ContentPresenter));
        content.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        content.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(content);
        t.VisualTree = border;
        var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(UIElement.OpacityProperty, 0.85));
        t.Triggers.Add(hover);
        return t;
    }

    /// A text link in the link colour.
    public static TextBlock LinkText(string label, Action onClick)
    {
        var t = Text(label, 12, Palette.Link, FontWeights.SemiBold, wrap: false);
        t.Cursor = Cursors.Hand;
        // On press, and handled, so the notes window doesn't start dragging instead.
        t.MouseLeftButtonDown += (_, e) => { e.Handled = true; onClick(); };
        return t;
    }

    /// The small round "live" dot.
    public static FrameworkElement Dot(Brush color, double size = 8) => new System.Windows.Shapes.Ellipse { Width = size, Height = size, Fill = color };

    /// The badge shown when the window is visible in screen sharing (共享屏幕时让对方看到).
    public static Border Badge(string text) => new()
    {
        Background = Palette.AccentPale, CornerRadius = new CornerRadius(8), Padding = new Thickness(7, 2, 7, 2),
        Child = Text(text, 10, Palette.Link, FontWeights.SemiBold, wrap: false),
    };

    public static ComboBox Choice(IEnumerable<(string value, string label)> options, string selected, Action<string> changed)
    {
        var box = new ComboBox { MinWidth = 180, FontFamily = Palette.Font, FontSize = 13 };
        foreach (var (value, label) in options)
        {
            var item = new ComboBoxItem { Content = label, Tag = value };
            box.Items.Add(item);
            if (value == selected) box.SelectedItem = item;
        }
        box.SelectionChanged += (_, _) => { if (box.SelectedItem is ComboBoxItem { Tag: string v }) changed(v); };
        return box;
    }

    public static IEnumerable<(string, string)> TargetOptions() =>
        [("system", L("跟随系统")), .. Languages.Targets.Select(t => (t.Code, t.Name))];

    public static Window StyledWindow(string title, double width, double height) => new()
    {
        Title = title, Width = width, Height = height, Background = Palette.Ground, FontFamily = Palette.Font,
        WindowStartupLocation = WindowStartupLocation.CenterScreen, Icon = AppIcon.Image,
    };
}

static class AppIcon
{
    public static readonly System.Windows.Media.Imaging.BitmapFrame? Image = Load();

    static System.Windows.Media.Imaging.BitmapFrame? Load()
    {
        try { return System.Windows.Media.Imaging.BitmapFrame.Create(new Uri("pack://application:,,,/cicada.ico")); }
        catch { return null; }
    }
}
