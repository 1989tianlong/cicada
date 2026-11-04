using System.IO.Pipes;
using System.Media;
using System.Text.Json.Nodes;
using System.Windows;
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
    NotesWindow? notesWindow;
    MainWindow? mainWindow;
    SettingsWindow? settingsWindow;
    Dispatcher Ui => application.Dispatcher;

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
        DebugServer.Start(this);
        if (!Settings.Onboarded) new Onboarding(this).Show();
        else if (Ling.HasKey) _ = Ling.Check();
    }

    void Changed() => Ui.BeginInvoke(() =>
    {
        notesWindow?.Refresh();
        mainWindow?.Refresh();
        UpdateTray();
    });

    // MARK: Tray (the Mac's menu bar panel)

    void SetUpTray()
    {
        tray.Icon = LoadIcon();
        tray.Text = L("知了");
        tray.Visible = true;
        tray.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) Ui.BeginInvoke(ShowNotes); };
        UpdateTray();
    }

    static System.Drawing.Icon LoadIcon()
    {
        try
        {
            var info = Application.GetResourceStream(new Uri("pack://application:,,,/cicada.ico"));
            return new System.Drawing.Icon(info!.Stream);
        }
        catch { return System.Drawing.SystemIcons.Application; }
    }

    void UpdateTray()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add(Listen.Listening ? L("结束") : L("开始听"), null, (_, _) => Ui.BeginInvoke(() => _ = ToggleListening()));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(L("显示纪要"), null, (_, _) => Ui.BeginInvoke(ShowNotes));
        menu.Items.Add(L("会议记录"), null, (_, _) => Ui.BeginInvoke(ShowRecords));
        menu.Items.Add(L("设置"), null, (_, _) => Ui.BeginInvoke(ShowSettings));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(L("退出"), null, (_, _) => Ui.BeginInvoke(() => _ = Quit()));
        var old = tray.ContextMenuStrip;
        tray.ContextMenuStrip = menu;
        old?.Dispose();
        tray.Text = Listen.Listening ? L("知了") + " · " + L("正在听") : L("知了");
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
            Ui.BeginInvoke(() => _ = StopListening());
        };
        Listen.Start(source);
        ShowNotes();
    }

    public async Task StopListening()
    {
        await Listen.Stop();
        Changed();
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

    public void ShowRecords()
    {
        if (mainWindow is null) { mainWindow = new MainWindow(this); mainWindow.Closed += (_, _) => mainWindow = null; }
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
    public void SettingsChanged() => Changed();

    public async Task Quit()
    {
        if (Listen.Listening) await StopListening();
        Store.Flush();
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
        ["problem"] = Listen.Problem,
        ["notes"] = Notes.Status.ToString(),
        ["topics"] = Notes.Notes.Topics.Count,
        ["key"] = Ling.KeyState.ToString(),
        ["view"] = Settings.View,
        ["showInCapture"] = Settings.ShowInCapture,
        ["sessions"] = Store.All().Count,
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
                if (arg == "records") app.ShowRecords(); else if (arg == "settings") app.ShowSettings(); else app.ShowNotes();
                break;
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
