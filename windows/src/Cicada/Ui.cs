using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using static Cicada.Strings;

namespace Cicada.App;

/// Cicada's palette on Windows 11 shapes: the Mac's ground, ink and one orange for "live", plus the
/// Fluent roles (strokes, subtle fills, info bars). Orange text and fills use darker shades of the
/// accent so they pass 4.5:1; #E8552B itself is only for the live dot.
static class Palette
{
    static SolidColorBrush B(uint rgb) { var x = new SolidColorBrush(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb)); x.Freeze(); return x; }
    public static readonly SolidColorBrush Mica = B(0xF3F4F6);
    public static readonly SolidColorBrush Surface = B(0xFFFFFF);
    public static readonly SolidColorBrush SurfaceAlt = B(0xF7F8FA);
    public static readonly SolidColorBrush Subtle = B(0xF0F1F3);
    public static readonly SolidColorBrush Selected = B(0xE6E8EB);
    public static readonly SolidColorBrush Stroke = B(0xE3E5E8);
    public static readonly SolidColorBrush StrokeSoft = B(0xEEF0F2);
    public static readonly SolidColorBrush ControlStroke = B(0xD5D8DD);
    public static readonly SolidColorBrush Ink = B(0x15171C);
    public static readonly SolidColorBrush Body = B(0x3D414A);
    public static readonly SolidColorBrush Secondary = B(0x5A5F6B);
    public static readonly SolidColorBrush Tertiary = B(0x6B7080);
    public static readonly SolidColorBrush Live = B(0xE8552B);
    public static readonly SolidColorBrush AccentFill = B(0xC9441D);
    public static readonly SolidColorBrush AccentPale = B(0xFDEBE4);
    public static readonly SolidColorBrush AccentText = B(0xA8370F);
    public static readonly SolidColorBrush Success = B(0x0F7B3F);
    public static readonly SolidColorBrush Danger = B(0xC42B1C);
    public static readonly SolidColorBrush ErrorBg = B(0xFDF0EE);
    public static readonly SolidColorBrush ErrorStroke = B(0xF3CBC4);
    public static readonly SolidColorBrush WarnBg = B(0xFFF6E5);
    public static readonly SolidColorBrush WarnStroke = B(0xF1DDB0);
    public static readonly SolidColorBrush WarnIcon = B(0x9D5D00);
    public static readonly SolidColorBrush Night = B(0x15171C);
    public static readonly SolidColorBrush NightText = B(0xB4B9C2);
    public static readonly FontFamily Font = new("Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI, Yu Gothic UI, Malgun Gothic");
}

/// Stroke icons on a 20×20 grid (Fluent's outline style), drawn with Ui.Icon.
static class Icons
{
    public const string Close = "M5,5 L15,15 M15,5 L5,15";
    public const string Subtitles = "M4.5,4.5 H15.5 A2,2 0 0 1 17.5,6.5 V13.5 A2,2 0 0 1 15.5,15.5 H4.5 A2,2 0 0 1 2.5,13.5 V6.5 A2,2 0 0 1 4.5,4.5 Z M6,11.5 H9 M11,11.5 H14 M6,8.5 H14";
    public const string Notes = "M5.5,2.5 H11.5 L15,6 V17.5 H5.5 Z M11.5,2.5 V6 H15 M8,10 H13 M8,13 H13";
    public const string Stop = "M6.5,4 H13.5 A2.5,2.5 0 0 1 16,6.5 V13.5 A2.5,2.5 0 0 1 13.5,16 H6.5 A2.5,2.5 0 0 1 4,13.5 V6.5 A2.5,2.5 0 0 1 6.5,4 Z";
    public const string Play = "M6.5,4.5 L15.5,10 L6.5,15.5 Z";
    public const string Gear = "M12.5,10 A2.5,2.5 0 1 1 7.5,10 A2.5,2.5 0 1 1 12.5,10 Z M10,2.5 V4.5 M10,15.5 V17.5 M2.5,10 H4.5 M15.5,10 H17.5 M4.7,4.7 L6.1,6.1 M13.9,13.9 L15.3,15.3 M4.7,15.3 L6.1,13.9 M13.9,6.1 L15.3,4.7";
    public const string Search = "M14.5,9 A5.5,5.5 0 1 1 3.5,9 A5.5,5.5 0 1 1 14.5,9 Z M13,13 L17,17";
    public const string Export = "M10,3 V13 M6,7 L10,3 L14,7 M4,12 V16.5 H16 V12";
    public const string Pencil = "M13.5,3.5 L16.5,6.5 L7,16 H4 V13 Z";
    public const string Trash = "M4,6 H16 M8,6 V4 H12 V6 M5.5,6 L6.5,17 H13.5 L14.5,6";
    public const string Copy = "M8.5,7 H14.5 A1.5,1.5 0 0 1 16,8.5 V14.5 A1.5,1.5 0 0 1 14.5,16 H8.5 A1.5,1.5 0 0 1 7,14.5 V8.5 A1.5,1.5 0 0 1 8.5,7 Z M4,13 V5.5 A1.5,1.5 0 0 1 5.5,4 H13";
    public const string EyeOff = "M3,3 L17,17 M6.5,6.6 C4.6,7.8 3,10 3,10 C3,10 5.8,15 10,15 C11.3,15 12.5,14.6 13.5,14 M9,5.1 C9.3,5.1 9.7,5 10,5 C14.2,5 17,10 17,10 C17,10 16.4,11.1 15.3,12.3";
    public const string Eye = "M2.5,10 C2.5,10 5.3,5 10,5 C14.7,5 17.5,10 17.5,10 C17.5,10 14.7,15 10,15 C5.3,15 2.5,10 2.5,10 Z M12.2,10 A2.2,2.2 0 1 1 7.8,10 A2.2,2.2 0 1 1 12.2,10 Z";
    public const string Key = "M10.5,12 A3.5,3.5 0 1 1 3.5,12 A3.5,3.5 0 1 1 10.5,12 Z M9.5,9.5 L16,3 M13.5,5.5 L15.5,7.5";
    public const string Speaker = "M3.5,8 H6.5 L10.5,4.5 V15.5 L6.5,12 H3.5 Z M13.5,7.5 A3.5,3.5 0 0 1 13.5,12.5 M15.5,5.5 A6,6 0 0 1 15.5,14.5";
    public const string Globe = "M17,10 A7,7 0 1 1 3,10 A7,7 0 1 1 17,10 Z M3,10 H17 M10,3 C12,5 12.8,7.5 12.8,10 C12.8,12.5 12,15 10,17 C8,15 7.2,12.5 7.2,10 C7.2,7.5 8,5 10,3 Z";
    public const string Power = "M10,3 V10 M6,5.5 A6,6 0 1 0 14,5.5";
    public const string List = "M7,5.5 H16 M7,10 H16 M7,14.5 H16 M3.5,5.5 H4 M3.5,10 H4 M3.5,14.5 H4";
    public const string Wave = "M3,10 H4 M6,7 V13 M9,4.5 V15.5 M12,7 V13 M15,8.5 V11.5 M17,10 H17.5";
    public const string Shield = "M10,2.5 L16,5 V9.5 C16,13.5 13.3,16.2 10,17.5 C6.7,16.2 4,13.5 4,9.5 V5 Z";
    public const string Folder = "M2.5,5.5 H7.5 L9,7.5 H17.5 V16 H2.5 Z";
    public const string Keyboard = "M4,5.5 H16 A1.5,1.5 0 0 1 17.5,7 V13 A1.5,1.5 0 0 1 16,14.5 H4 A1.5,1.5 0 0 1 2.5,13 V7 A1.5,1.5 0 0 1 4,5.5 Z M5.5,8.5 H6.5 M8.5,8.5 H9.5 M11.5,8.5 H12.5 M6.5,11.5 H13.5";
    public const string Chevron = "M6,8 L10,12 L14,8";
    public const string Check = "M4.5,10.5 L8,14 L15.5,6";
    public const string Info = "M17,10 A7,7 0 1 1 3,10 A7,7 0 1 1 17,10 Z M10,9 V14 M10,6.5 V7";
    public const string OpenExternal = "M8,4 H4.5 V15.5 H16 V12 M11,3.5 H16.5 V9 M16.5,3.5 L9,11";
}

static class Ui
{
    public static TextBlock Text(string text, double size = 14, Brush? color = null, FontWeight? weight = null, bool wrap = true) => new()
    {
        Text = text, FontSize = size, Foreground = color ?? Palette.Ink, FontWeight = weight ?? FontWeights.Normal,
        TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap, TextTrimming = wrap ? TextTrimming.None : TextTrimming.CharacterEllipsis,
        FontFamily = Palette.Font,
    };

    public static TextBlock Heading(string text, double size = 15) => Text(text, size, Palette.Ink, FontWeights.SemiBold);
    public static TextBlock Helper(string text) => Text(text, 12, Palette.Secondary);

    /// A 20×20 stroke icon, or a filled one, scaled to `size`.
    public static FrameworkElement Icon(string data, double size = 16, Brush? color = null, bool fill = false, double stroke = 1.5)
    {
        var path = new System.Windows.Shapes.Path { Data = Geometry.Parse(data), StrokeLineJoin = PenLineJoin.Round, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
        if (fill) path.Fill = color ?? Palette.Ink;
        else { path.Stroke = color ?? Palette.Ink; path.StrokeThickness = stroke; }
        var canvas = new Canvas { Width = 20, Height = 20 };
        canvas.Children.Add(path);
        return new Viewbox { Width = size, Height = size, Child = canvas, VerticalAlignment = VerticalAlignment.Center };
    }

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

    /// A row whose last child sits at the right edge: [left…] ··· [right].
    public static DockPanel Spread(UIElement left, UIElement right)
    {
        var d = new DockPanel { LastChildFill = false };
        DockPanel.SetDock(left, Dock.Left); DockPanel.SetDock(right, Dock.Right);
        d.Children.Add(left); d.Children.Add(right);
        return d;
    }

    public enum Kind { Standard, Primary, Accent, Subtle, Danger, Pale }

    /// Windows 11 buttons: Standard (white, hairline), Primary (ink), Accent (live orange, for
    /// 开始听 only), Subtle (no fill until hover), Danger (red, for delete), Pale (the 结束 pill).
    public static Button Button(string label, Action onClick, Kind kind = Kind.Standard, string? icon = null, double height = 36, bool iconFill = false)
    {
        var (bg, fg, border) = kind switch
        {
            Kind.Primary => (Palette.Ink, Brushes.White, Brushes.Transparent),
            Kind.Accent => (Palette.AccentFill, Brushes.White, Brushes.Transparent),
            Kind.Danger => (Palette.Danger, Brushes.White, Brushes.Transparent),
            Kind.Pale => (Palette.AccentPale, Palette.AccentText, Brushes.Transparent),
            Kind.Subtle => ((Brush)Brushes.Transparent, (Brush)Palette.Ink, (Brush)Brushes.Transparent),
            _ => (Palette.Surface, Palette.Ink, Palette.ControlStroke),
        };
        var content = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
        if (icon is not null) content.Children.Add(Icon(icon, kind == Kind.Accent && height >= 48 ? 20 : 16, fg, iconFill));
        var text = new TextBlock { Text = label, FontSize = height >= 48 ? 16 : 14, FontWeight = kind is Kind.Standard or Kind.Subtle ? FontWeights.Normal : FontWeights.SemiBold, FontFamily = Palette.Font, VerticalAlignment = VerticalAlignment.Center, Foreground = fg };
        if (icon is not null) text.Margin = new Thickness(8, 0, 0, 0);
        content.Children.Add(text);
        var b = new Button
        {
            Content = content, Foreground = fg, Background = bg, BorderBrush = border, BorderThickness = new Thickness(kind == Kind.Standard ? 1 : 0),
            Height = height, Padding = new Thickness(14, 0, 14, 0), Cursor = Cursors.Hand, MinWidth = height >= 36 ? 80 : 0,
            // The Fluent theme left-aligns buttons; ours fill their slot unless a caller says otherwise.
            HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Center,
        };
        b.Template = Template(kind is Kind.Standard or Kind.Subtle);
        b.Click += (_, _) => onClick();
        AutomationName(b, label);
        return b;
    }

    /// A square icon-only button with a tooltip and an accessible name.
    public static Button IconButton(string icon, string name, Action onClick, Brush? color = null, double size = 40, double iconSize = 16, bool fill = false, bool onDark = false)
    {
        var b = new Button
        {
            Content = Icon(icon, iconSize, color ?? Palette.Body, fill), Width = size, Height = size, Background = Brushes.Transparent,
            BorderThickness = new Thickness(0), Cursor = Cursors.Hand, ToolTip = name,
        };
        b.Template = Template(plain: true, onDark: onDark);
        b.Click += (_, _) => onClick();
        AutomationName(b, name);
        return b;
    }

    static void AutomationName(UIElement e, string name) => System.Windows.Automation.AutomationProperties.SetName(e, name);

    /// Rounded, no Windows 7 chrome. Plain buttons get a grey wash on hover; filled ones dim a little.
    static ControlTemplate Template(bool plain, bool onDark = false, Type? target = null)
    {
        var t = new ControlTemplate(target ?? typeof(Button));
        var border = new FrameworkElementFactory(typeof(Border), "bg");
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(4));
        border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.BorderBrushProperty, new System.Windows.Data.Binding("BorderBrush") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.BorderThicknessProperty, new System.Windows.Data.Binding("BorderThickness") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.PaddingProperty, new System.Windows.Data.Binding("Padding") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        var content = new FrameworkElementFactory(typeof(ContentPresenter));
        content.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        content.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(content);
        t.VisualTree = border;
        var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        var pressed = new Trigger { Property = ButtonBase.IsPressedProperty, Value = true };
        if (plain)
        {
            var wash = onDark ? new SolidColorBrush(Color.FromArgb(0x26, 0xFF, 0xFF, 0xFF)) : (Brush)Palette.Subtle;
            hover.Setters.Add(new Setter(Border.BackgroundProperty, wash, "bg"));
            pressed.Setters.Add(new Setter(Border.BackgroundProperty, onDark ? new SolidColorBrush(Color.FromArgb(0x40, 0xFF, 0xFF, 0xFF)) : Palette.Selected, "bg"));
        }
        else
        {
            hover.Setters.Add(new Setter(UIElement.OpacityProperty, 0.9));
            pressed.Setters.Add(new Setter(UIElement.OpacityProperty, 0.8));
        }
        var disabled = new Trigger { Property = UIElement.IsEnabledProperty, Value = false };
        disabled.Setters.Add(new Setter(UIElement.OpacityProperty, 0.45));
        t.Triggers.Add(hover); t.Triggers.Add(pressed); t.Triggers.Add(disabled);
        return t;
    }

    /// A text link in the accent's text shade. Acts on press and marks it handled, so the notes
    /// window doesn't start a drag instead.
    public static TextBlock LinkText(string label, Action onClick, double size = 13)
    {
        var t = Text(label, size, Palette.AccentText, FontWeights.SemiBold, wrap: false);
        t.Cursor = Cursors.Hand;
        t.MouseLeftButtonDown += (_, e) => { e.Handled = true; onClick(); };
        t.MouseEnter += (_, _) => t.TextDecorations = TextDecorations.Underline;
        t.MouseLeave += (_, _) => t.TextDecorations = null;
        return t;
    }

    public static FrameworkElement Dot(Brush color, double size = 8) => new Ellipse { Width = size, Height = size, Fill = color, VerticalAlignment = VerticalAlignment.Center };

    /// The live dot, breathing while listening.
    public static FrameworkElement LiveDot(double size = 8)
    {
        var dot = new Ellipse { Width = size, Height = size, Fill = Palette.Live, VerticalAlignment = VerticalAlignment.Center };
        var pulse = new System.Windows.Media.Animation.DoubleAnimation(1, 0.35, TimeSpan.FromSeconds(0.9)) { AutoReverse = true, RepeatBehavior = System.Windows.Media.Animation.RepeatBehavior.Forever };
        dot.Loaded += (_, _) => dot.BeginAnimation(UIElement.OpacityProperty, pulse);
        return dot;
    }

    /// A small pill: 对方可见 and the like.
    public static Border Badge(string text, Brush? bg = null, Brush? fg = null) => new()
    {
        Background = bg ?? Palette.AccentPale, CornerRadius = new CornerRadius(10), Padding = new Thickness(8, 2, 8, 3), VerticalAlignment = VerticalAlignment.Center,
        Child = Text(text, 12, fg ?? Palette.AccentText, FontWeights.SemiBold, wrap: false),
    };

    public static Border Card(UIElement child, Thickness? padding = null, Brush? bg = null) => new()
    {
        Background = bg ?? Palette.Surface, BorderBrush = Palette.Stroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8),
        Padding = padding ?? new Thickness(16), Child = child,
    };

    public enum Severity { Error, Warning }

    /// Fluent's InfoBar: an icon, a bold title, one line of body, and up to one action.
    public static Border InfoBar(Severity severity, string? title, string body, UIElement? action = null)
    {
        var error = severity == Severity.Error;
        var icon = new Grid { Width = 18, Height = 18, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 1, 0, 0) };
        icon.Children.Add(new Ellipse { Fill = error ? Palette.Danger : Palette.WarnIcon });
        icon.Children.Add(Icon(error ? "M7,7 L13,13 M13,7 L7,13" : "M10,5.5 V11 M10,14 V14.5", 18, Brushes.White, stroke: 1.8));
        var text = new StackPanel { Margin = new Thickness(10, 0, 8, 0) };
        if (title is not null) text.Children.Add(Text(title, 14, Palette.Ink, FontWeights.SemiBold));
        var bodyText = Text(body, 13, Palette.Body);
        if (title is not null) bodyText.Margin = new Thickness(0, 2, 0, 0);
        text.Children.Add(bodyText);
        var dock = new DockPanel();
        DockPanel.SetDock(icon, Dock.Left);
        dock.Children.Add(icon);
        if (action is TextBlock link) { link.Margin = new Thickness(0, 6, 0, 0); link.HorizontalAlignment = HorizontalAlignment.Left; text.Children.Add(link); }
        else if (action is FrameworkElement a) { DockPanel.SetDock(a, Dock.Right); a.VerticalAlignment = VerticalAlignment.Top; dock.Children.Add(a); }
        dock.Children.Add(text);
        return new Border
        {
            Background = error ? Palette.ErrorBg : Palette.WarnBg, BorderBrush = error ? Palette.ErrorStroke : Palette.WarnStroke,
            BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(6), Padding = new Thickness(14, 12, 12, 12), Child = dock,
        };
    }

    /// The Windows 11 toggle switch (role switch), with 开/关 beside it as Settings does.
    public static FrameworkElement Switch(bool on, Action<bool> changed, string name)
    {
        var state = Text(on ? L("开") : L("关"), 13, Palette.Body, wrap: false);
        var knob = new Ellipse { Width = 12, Height = 12 };
        var track = new Border { Width = 40, Height = 20, CornerRadius = new CornerRadius(10), BorderThickness = new Thickness(1), Child = knob, Padding = new Thickness(3, 0, 3, 0) };
        void Paint(bool v)
        {
            track.Background = v ? Palette.Ink : Palette.Surface;
            track.BorderBrush = v ? Palette.Ink : Palette.Secondary;
            knob.Fill = v ? Brushes.White : Palette.Secondary;
            knob.HorizontalAlignment = v ? HorizontalAlignment.Right : HorizontalAlignment.Left;
            state.Text = v ? L("开") : L("关");
        }
        Paint(on);
        var toggle = new ToggleButton { IsChecked = on, Content = track, Background = Brushes.Transparent, BorderThickness = new Thickness(0), Cursor = Cursors.Hand, Padding = new Thickness(0) };
        toggle.Template = Template(plain: false, target: typeof(ToggleButton));
        toggle.Click += (_, _) => { var v = toggle.IsChecked == true; Paint(v); changed(v); };
        AutomationName(toggle, name);
        return Row(12, state, toggle);
    }

    /// A segmented control: one choice of a few, the chosen one raised on a grey track.
    public static FrameworkElement Segmented(IEnumerable<(string value, string label)> options, string selected, Action<string> changed)
    {
        var track = new Border { Background = Palette.Subtle, CornerRadius = new CornerRadius(6), Padding = new Thickness(2) };
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        track.Child = row;
        var buttons = new List<(Button b, string v)>();
        void Paint(string v)
        {
            foreach (var (b, value) in buttons)
            {
                var on = value == v;
                b.Background = on ? Palette.Surface : Brushes.Transparent;
                b.Effect = on ? new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 3, ShadowDepth = 1, Opacity = 0.15 } : null;
                ((TextBlock)b.Content).FontWeight = on ? FontWeights.SemiBold : FontWeights.Normal;
                ((TextBlock)b.Content).Foreground = on ? Palette.Ink : Palette.Body;
            }
        }
        foreach (var (value, label) in options)
        {
            var b = new Button { Content = Text(label, 13, Palette.Body, wrap: false), Height = 30, Padding = new Thickness(12, 0, 12, 0), BorderThickness = new Thickness(0), Cursor = Cursors.Hand };
            b.Template = Template(plain: false);
            b.Click += (_, _) => { Paint(value); changed(value); };
            buttons.Add((b, value));
            row.Children.Add(b);
        }
        Paint(selected);
        return track;
    }

    /// Pivot-style tabs: text with an ink underline on the chosen one.
    public static FrameworkElement Tabs(IEnumerable<(string value, string label)> options, string selected, Action<string> changed, double size = 14)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var (value, label) in options)
        {
            var on = value == selected;
            var text = Text(label, size, on ? Palette.Ink : Palette.Secondary, on ? FontWeights.SemiBold : FontWeights.Normal, wrap: false);
            var underline = new Border { Height = 3, CornerRadius = new CornerRadius(2), Background = on ? Palette.Ink : Brushes.Transparent, Margin = new Thickness(0, 6, 0, 0) };
            var stack = new StackPanel { Children = { text, underline } };
            var b = new Button { Content = stack, Padding = new Thickness(12, 8, 12, 0), Background = Brushes.Transparent, BorderThickness = new Thickness(0), Cursor = Cursors.Hand };
            b.Template = Template(plain: true);
            b.Click += (_, _) => changed(value);
            row.Children.Add(b);
        }
        return row;
    }

    public static ComboBox Choice(IEnumerable<(string value, string label)> options, string selected, Action<string> changed, double width = 200)
    {
        var box = new ComboBox { Width = width, FontFamily = Palette.Font, FontSize = 13, VerticalAlignment = VerticalAlignment.Center };
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
        [("system", LF("跟随系统（%@）", Languages.Targets.FirstOrDefault(t => t.Code == Languages.FromSystem(System.Globalization.CultureInfo.CurrentUICulture.Name))?.Name ?? "")),
         .. Languages.Targets.Select(t => (t.Code, t.Name))];

    public static string TargetName(string code) => Languages.Targets.FirstOrDefault(t => t.Code == code)?.Name ?? code;

    /// The name of a spoken language as people write it ("English", "日本語").
    public static string SpokenName(string? code)
    {
        if (code is null) return "";
        var head = code.Split('-')[0];
        return Languages.Sources.FirstOrDefault(s => s.Code.Split('-')[0] == head)?.Name ?? code;
    }
}

static class AppIcon
{
    public static readonly System.Windows.Media.Imaging.BitmapFrame? Image = Load();

    static System.Windows.Media.Imaging.BitmapFrame? Load()
    {
        try { return System.Windows.Media.Imaging.BitmapFrame.Create(new Uri("pack://application:,,,/cicada.ico")); }
        catch { return null; }
    }

    public static Image Small(double size = 16) => new() { Source = Image, Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center };
}
