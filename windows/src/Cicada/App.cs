using System.IO.Pipes;
using System.Media;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using static Cicada.Strings;
using Forms = System.Windows.Forms;

namespace Cicada.App;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        Paths.Dev = Paths.Dev || args.Contains("--dev");
        // One Cicada per user: a second launch just opens the records of the running one.
        using var single = new Mutex(true, Paths.Dev ? "com.wquguru.cicada.dev" : "com.wquguru.cicada", out bool first);
        if (!first) { Native.LetOthersTakeForeground(); DebugServer.Send("show records"); return 0; }
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        // WPF's own Windows 11 (Fluent) look for the stock controls: menus, combo boxes, text boxes,
        // check boxes and scroll bars. Light only for now; Cicada draws its own surfaces on top.
#pragma warning disable WPF0001
        app.ThemeMode = ThemeMode.Light;
#pragma warning restore WPF0001
        app.DispatcherUnhandledException += (_, e) => { Log.Debug($"ui: unhandled {e.Exception.GetType().Name}: {e.Exception.Message}"); e.Handled = true; };
        var controller = new Controller(app);
        app.Startup += (_, _) => controller.Launch();
        return app.Run();
    }
}

/// Wires the engines to the windows, as AppModel does on the Mac. Engine events arrive on worker
/// threads; everything here that touches UI runs on the dispatcher.
sealed class Controller
{
    readonly Application application;
    public readonly AppSettings Settings = AppSettings.Load();
    public readonly AIKey Key = new(new DpapiProtector());
    public readonly LingClient Ling;
    public readonly SessionStore Store = new();
    public readonly NotesEngine Notes;
    public readonly Translator Translator;
    public readonly ListenEngine Listen;
    readonly Forms.NotifyIcon tray = new();
    System.Drawing.Icon? idleIcon, liveIcon;
    Action? balloonClicked;
    Hotkey? hotkey;
    TrayFlyout? flyout;
    Window? menuHost;
    NotesWindow? notesWindow;
    MainWindow? mainWindow;
    SettingsWindow? settingsWindow;
    Dispatcher Dispatch => application.Dispatcher;

    public Controller(Application application)
    {
        this.application = application;
        var ui = Settings.UiLanguage == "system" ? null : Settings.UiLanguage;
        Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), ui);
        Ling = new LingClient(Key) { Model = Settings.Model };
        Notes = new NotesEngine(Ling, Store);
        Translator = new Translator(Ling);
        Listen = new ListenEngine(Ling, Translator, Store, Notes, Settings);
        Listen.Changed += Changed;
        Notes.Changed += Changed;
        Store.Changed += _ => Changed();
    }

    public void Launch()
    {
        // Process loopback and capture exclusion both arrived in Windows 10 2004 (build 19041).
        if (Environment.OSVersion.Version.Build < 19041)
        {
            MessageBox.Show(L("知了需要 Windows 10 2004 或更新的版本。"), L("知了"));
            application.Shutdown();
            return;
        }
        Log.Debug($"app: launch {(Paths.Dev ? "dev" : "release")} {Environment.OSVersion.Version}");
        SetUpTray();
        hotkey = new Hotkey(() => Dispatch.BeginInvoke(() => _ = ToggleListening()));
        DebugServer.Start(this);
        if (!Settings.Onboarded) new Onboarding(this).Show();
        else if (Ling.HasKey) _ = Ling.Check();
    }

    void Changed() => Dispatch.BeginInvoke(() =>
    {
        notesWindow?.Refresh();
        mainWindow?.Refresh();
        if (flyout?.IsVisible == true) flyout.Refresh();
        UpdateTray();
    });

    // MARK: Tray (the Mac's menu bar panel)

    void SetUpTray()
    {
        idleIcon = LoadIcon();
        liveIcon = WithDot(idleIcon);
        tray.Icon = idleIcon;
        tray.Text = L("知了");
        tray.Visible = true;
        // Left click: the flyout. Right click: the menu. Both are WPF, so they look like Windows 11.
        tray.MouseUp += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left) Dispatch.BeginInvoke(ShowFlyout);
            else if (e.Button == Forms.MouseButtons.Right) Dispatch.BeginInvoke(ShowMenu);
        };
        tray.BalloonTipClicked += (_, _) => Dispatch.BeginInvoke(() => { balloonClicked?.Invoke(); balloonClicked = null; });
        UpdateTray();
    }

    static System.Drawing.Icon LoadIcon()
    {
        try
        {
            var info = Application.GetResourceStream(new Uri("pack://application:,,,/cicada.ico"));
            return new System.Drawing.Icon(info!.Stream, 32, 32);
        }
        catch { return System.Drawing.SystemIcons.Application; }
    }

    /// The tray icon while listening: the logo with the live dot on its corner.
    static System.Drawing.Icon WithDot(System.Drawing.Icon icon)
    {
        using var bmp = new System.Drawing.Bitmap(32, 32);
        using (var g = System.Drawing.Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.DrawIcon(icon, new System.Drawing.Rectangle(0, 0, 32, 32));
            using var ring = new System.Drawing.SolidBrush(System.Drawing.Color.White);
            using var dot = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(0xE8, 0x55, 0x2B));
            g.FillEllipse(ring, 16, 16, 16, 16);
            g.FillEllipse(dot, 19, 19, 10, 10);
        }
        return System.Drawing.Icon.FromHandle(bmp.GetHicon());
    }

    void UpdateTray()
    {
        tray.Icon = Listen.Listening ? liveIcon : idleIcon;
        tray.Text = Listen.Listening ? L("知了") + " · " + L("正在听") : L("知了");
    }

    public void ShowFlyout()
    {
        flyout ??= new TrayFlyout(this);
        flyout.Toggle();
    }

    /// The right-click menu needs a window of ours in front, or it won't close on an outside click.
    public void ShowMenu()
    {
        menuHost ??= new Window { WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = System.Windows.Media.Brushes.Transparent, ShowInTaskbar = false, Width = 1, Height = 1, Left = -10000, Top = -10000, Topmost = true };
        menuHost.Show();
        menuHost.Activate();
        var menu = new ContextMenu { Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint, FontFamily = Palette.Font };
        MenuItem Item(string label, string? icon, Action act, string? keys = null, bool fill = false)
        {
            var item = new MenuItem { Header = label, InputGestureText = keys ?? "" };
            if (icon is not null) item.Icon = Ui.Icon(icon, 16, Palette.Ink, fill);
            item.Click += (_, _) => act();
            return item;
        }
        menu.Items.Add(Listen.Listening
            ? Item(L("结束"), Icons.Stop, () => _ = StopListening(), Hotkey.Label, fill: true)
            : Item(L("开始听"), Icons.Wave, () => _ = ToggleListening(), Hotkey.Label));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L("显示纪要"), Icons.Notes, ShowNotes));
        menu.Items.Add(Settings.View == "subtitles" ? Item(L("换成纪要"), Icons.Notes, () => SetView("notes")) : Item(L("换成字幕条"), Icons.Subtitles, () => SetView("subtitles")));
        var share = new MenuItem { Header = L("共享屏幕时让对方看到"), IsCheckable = true, IsChecked = Settings.ShowInCapture, Icon = Ui.Icon(Icons.Eye, 16, Palette.Ink) };
        share.Click += (_, _) => SetShowInCapture(share.IsChecked);
        menu.Items.Add(share);
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L("查看记录"), Icons.List, () => ShowRecords()));
        menu.Items.Add(Item(L("打开设置"), Icons.Gear, ShowSettings));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L("退出"), Icons.Power, () => _ = Quit()));
        menu.Closed += (_, _) => menuHost.Hide();
        menu.IsOpen = true;
    }

    /// A Windows notification from the tray icon; a click on it runs `clicked`.
    public void Toast(string title, string body, Action? clicked = null)
    {
        balloonClicked = clicked;
        tray.ShowBalloonTip(6000, title, body, Forms.ToolTipIcon.None);
        Log.Debug("toast: shown");
    }

    // MARK: Listening

    public async Task ToggleListening()
    {
        if (Listen.Listening) await StopListening();
        else StartListening(new SystemAudioTap());
    }

    public void StartListening(IAudioSource source)
    {
        if (Listen.Listening) return;
        if (!Ling.HasKey) { new Onboarding(this).Show(); return; }
        source.Ended += reason =>
        {
            if (reason is null) return;
            Log.Debug($"listen: source ended {reason}");
            Dispatch.BeginInvoke(() => _ = StopListening());
        };
        Listen.Start(source);
        ShowNotes();
    }

    public async Task StopListening()
    {
        var id = Listen.SessionId;
        await Listen.Stop();
        Changed();
        if (id is not null) _ = TellWhenNotesReady(id);
    }

    /// The final notes take a few seconds after 结束; say so once they're written.
    async Task TellWhenNotesReady(string id)
    {
        for (int i = 0; i < 120; i++)
        {
            await Task.Delay(1000);
            var s = Store.Get(id);
            if (s is null || Listen.SessionId == id && Listen.Listening) return;
            if (s.Notes is { Final: true, IsEmpty: false })
            {
                Dispatch.Invoke(() => Toast(L("纪要整理好了"), LF("%@ · 点这里打开", SessionStore.DisplayTitle(s)), () => ShowRecords(id)));
                return;
            }
        }
    }

    /// The panel was closed while listening: the first time, say that listening goes on.
    public void CollapsedWhileListening()
    {
        if (!Listen.Listening || Settings.ToldStillListening) return;
        Settings.ToldStillListening = true; Settings.Save();
        Toast(L("知了还在听"), L("点任务栏右下角的知了图标再打开纪要。"), ShowNotes);
    }

    /// The onboarding sample: heard straight from the file (Cicada's own sound is left out of
    /// the system capture) while it plays aloud for the user.
    public async Task PlaySample()
    {
        var wav = Path.Combine(AppContext.BaseDirectory, "Resources", "sample.wav");
        if (!File.Exists(wav) || Listen.Listening) return;
        var source = new FileAudioSource(wav);
        var done = new TaskCompletionSource();
        source.Ended += _ => done.TrySetResult();
        StartListening(source);
        try { new SoundPlayer(wav).Play(); } catch (Exception e) { Log.Debug($"sample: play failed {e.GetType().Name}"); }
        await done.Task;
        await Task.Delay(3000); // the last segment's reply
        await StopListening();
    }

    // MARK: Windows

    public void ShowNotes()
    {
        notesWindow ??= new NotesWindow(this);
        notesWindow.Show();
        notesWindow.Refresh();
    }

    public void ShowRecords() => ShowRecords(null);

    public void ShowRecords(string? id)
    {
        if (mainWindow is null) { mainWindow = new MainWindow(this, id); mainWindow.Closed += (_, _) => mainWindow = null; }
        else if (id is not null) mainWindow.Select(id);
        if (mainWindow.WindowState == WindowState.Minimized) mainWindow.WindowState = WindowState.Normal;
        mainWindow.Show();
        mainWindow.Activate();
    }

    public void ShowSettings()
    {
        if (settingsWindow is null) { settingsWindow = new SettingsWindow(this); settingsWindow.Closed += (_, _) => settingsWindow = null; }
        settingsWindow.Show();
        settingsWindow.Activate();
    }

    public void SetView(string view)
    {
        Settings.View = view;
        Settings.Save();
        if (notesWindow is null) return;
        notesWindow.Place();
        notesWindow.Refresh();
    }

    public void CaptureSettingChanged() => notesWindow?.ApplyCaptureSetting();

    public void SetShowInCapture(bool on)
    {
        Settings.ShowInCapture = on;
        Settings.Save();
        CaptureSettingChanged();
        Changed();
    }

    public void SetTarget(string target)
    {
        Settings.Target = target;
        Settings.Save();
        Changed();
    }

    public bool HotkeyRegistered => hotkey?.Registered ?? false;
    public void SettingsChanged() => Changed();

    public async Task Quit()
    {
        if (Listen.Listening) await StopListening();
        Store.Flush();
        hotkey?.Dispose();
        tray.Visible = false;
        tray.Dispose();
        application.Shutdown();
    }

    /// For the debug pipe: what a test needs to see (never meeting text).
    public JsonObject State() => new()
    {
        ["listening"] = Listen.Listening,
        ["session"] = Listen.SessionId,
        ["lines"] = Listen.SessionId is { } id ? Store.Get(id)?.Lines.Count ?? 0 : 0,
        ["pending"] = Listen.Pending,
        ["spoken"] = Listen.Spoken,
        ["target"] = Listen.Target,
        ["problem"] = Listen.Problem?.ToString(),
        ["notes"] = Notes.Status.ToString(),
        ["topics"] = Notes.Notes.Topics.Count,
        ["key"] = Ling.KeyState.ToString(),
        ["view"] = Settings.View,
        ["showInCapture"] = Settings.ShowInCapture,
        ["sessions"] = Store.All().Count,
        ["hotkey"] = HotkeyRegistered,
        ["autostart"] = AutoStart.Enabled,
    };
}

/// Debug commands over a named pipe (\\.\pipe\cicada-dev), dev builds only: the Windows
/// counterpart of the Mac's `tools/lsctl`. One command per connection, one JSON line back.
///   state | start | stop | feed <wav> | sample | view notes|subtitles | capture on|off
///   show notes|records|settings | quit
static class DebugServer
{
    static string Pipe => Paths.Dev ? "cicada-dev" : "cicada";

    public static void Start(Controller app)
    {
        new Thread(() =>
        {
            while (true)
            {
                try
                {
                    using var server = new NamedPipeServerStream(Pipe, PipeDirection.InOut, 1);
                    server.WaitForConnection();
                    using var reader = new StreamReader(server);
                    using var writer = new StreamWriter(server) { AutoFlush = true };
                    var line = reader.ReadLine() ?? "";
                    // A release build only takes "show records" (a second launch); the rest is for dev builds.
                    if (!Paths.Dev && line != "show records") { writer.WriteLine("{\"error\":\"dev builds only\"}"); continue; }
                    var reply = app.Dispatcher().Invoke(() => Run(app, line));
                    writer.WriteLine(reply.ToJsonString());
                }
                catch (Exception e) { Log.Debug($"debug: {e.GetType().Name}"); Thread.Sleep(200); }
            }
        }) { IsBackground = true, Name = "DebugServer" }.Start();
    }

    static Dispatcher Dispatcher(this Controller _) => Application.Current.Dispatcher;

    static JsonObject Run(Controller app, string line)
    {
        var parts = line.Trim().Split(' ', 2);
        var arg = parts.Length > 1 ? parts[1].Trim() : "";
        Log.Debug($"debug: {parts[0]}");
        switch (parts[0])
        {
            case "start": app.StartListening(new SystemAudioTap()); break;
            case "stop": _ = app.StopListening(); break;
            case "feed": app.StartListening(new FileAudioSource(arg)); break;
            case "sample": _ = app.PlaySample(); break;
            case "view": app.SetView(arg == "subtitles" ? "subtitles" : "notes"); break;
            case "capture": app.Settings.ShowInCapture = arg == "on"; app.Settings.Save(); app.CaptureSettingChanged(); break;
            case "show":
                if (arg == "records") app.ShowRecords();
                else if (arg == "settings") app.ShowSettings();
                else if (arg == "flyout") app.ShowFlyout();
                else if (arg == "menu") app.ShowMenu();
                else if (arg == "onboarding") new Onboarding(app).Show();
                else app.ShowNotes();
                break;
            case "toast": app.Toast(L("纪要整理好了"), LF("%@ · 点这里打开", "Test"), () => app.ShowRecords()); break;
            case "problem": app.Listen.SimulateProblem(arg); break;
            case "quit": _ = app.Quit(); break;
            case "state": break;
            default: return new JsonObject { ["error"] = $"unknown command {parts[0]}" };
        }
        return app.State();
    }

    /// Sends one command to the running app (a second launch uses it to bring records forward).
    public static string? Send(string command)
    {
        try
        {
            using var client = new NamedPipeClientStream(".", Pipe, PipeDirection.InOut);
            client.Connect(2000);
            using var writer = new StreamWriter(client) { AutoFlush = true };
            using var reader = new StreamReader(client);
            writer.WriteLine(command);
            return reader.ReadLine();
        }
        catch { return null; }
    }
}
