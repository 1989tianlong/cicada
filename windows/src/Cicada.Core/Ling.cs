using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Cicada;

/// Turns the key into bytes on disk and back. Windows uses DPAPI (the current user only); the
/// plain one is for the Mac-side CLI and tests.
public interface IKeyProtector
{
    string Tag { get; }
    byte[] Protect(byte[] data);
    byte[] Unprotect(byte[] data);
}

public sealed class PlainProtector : IKeyProtector
{
    public string Tag => "plain";
    public byte[] Protect(byte[] data) => data;
    public byte[] Unprotect(byte[] data) => data;
}

/// The user's AI keys, one file per service under the app folder, named as on the Mac
/// (`ling-api-key`, `ai-key-<service>`): never in settings, the registry, logs or exports. On
/// Windows each file holds DPAPI-sealed bytes, "dpapi:" + base64, readable only by this Windows
/// user. `service` says which one is in use, so switching services never deletes another's key;
/// `file` pins one file (the CLI reads the Mac app's in place).
public sealed class AIKey(IKeyProtector protector, string? file = null, Func<string>? service = null)
{
    readonly Func<string> service = service ?? (() => "ling");
    public string File_ => file ?? Paths.KeyFile(service());

    readonly Dictionary<string, string?> cache = [];
    readonly object gate = new();

    public string? Read()
    {
        var path = File_;
        lock (gate)
        {
            if (cache.TryGetValue(path, out var cached)) return cached;
            string? value = null;
            try
            {
                if (File.Exists(path))
                {
                    var text = File.ReadAllText(path).Trim();
                    if (text.StartsWith("dpapi:"))
                        text = Encoding.UTF8.GetString(protector.Unprotect(Convert.FromBase64String(text["dpapi:".Length..])));
                    value = text.Trim().Length == 0 ? null : text.Trim();
                }
            }
            catch (Exception e) { Log.Debug($"ai key: read failed {e.GetType().Name}"); }
            return cache[path] = value;
        }
    }

    public bool Save(string key)
    {
        key = key.Trim();
        var path = File_;
        lock (gate)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                var body = protector.Tag == "plain" ? key
                    : "dpapi:" + Convert.ToBase64String(protector.Protect(Encoding.UTF8.GetBytes(key)));
                File.WriteAllText(path, body);
                if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
                cache[path] = key;
                return true;
            }
            catch (Exception e)
            {
                Log.Debug($"ai key: save failed {e.GetType().Name}");
                return false;
            }
        }
    }

    /// Removes the key of the service in use only.
    public void Remove()
    {
        var path = File_;
        lock (gate)
        {
            try { File.Delete(path); } catch { }
            cache[path] = null;
        }
    }

    /// Forget what was read: a file may have changed behind the app.
    public void Reload() { lock (gate) cache.Clear(); }

    /// "sk-••••••••••••3f9a" for display.
    public static string Masked(string key) => key.Length <= 8 ? "sk-…" : key[..3] + new string('•', 12) + key[^4..];
}

public enum Priority { Speak = 0, Translate = 1, Notes = 2 }

public enum KeyState { None, Unchecked, Checking, Ok, Invalid, Unreachable }

public sealed class LingException(LingException.Kind kind, int status = 0) : Exception(kind == Kind.Http ? $"http{status}" : kind.ToString())
{
    public enum Kind { NoKey, InvalidKey, RateLimited, Hijacked, Timeout, Http, Network, Parse }
    public Kind Failure { get; } = kind;
    /// The HTTP status for Kind.Http.
    public int Status { get; } = status;
}

/// The AI service: Ling (ant-ling.com) by default, or another OpenAI-compatible one (AIProviders.cs),
/// read from `config` on every call. One instance for the app. Request *starts* go through one gate
/// in priority order: Ling allows about 2 a second across every model (≥ 0.6 s apart, overlapping
/// is fine), the aggregators far more. Ling's gateway shapes every call (see Ling.swift): thinking
/// is always disabled, and the content goes in the system message with a fixed user instruction,
/// because a question-like user message gets a search essay back; such replies are dropped. The
/// other services get the same messages.
public sealed class LingClient
{
    public static readonly Uri Base = new(AIProvider.Ling.Base!);
    public const string DefaultModel = "Ling-3.1-flash";
    public const string AudioModel = "Ming-3.0-audio-flash";
    public const string VoiceModel = "Ming-3.0-tts-0.5B";
    // Search essays (Ling.swift), and the canned refusal some audio prompts get.
    static readonly string[] HijackPrefixes = ["根据现有检索证据", "暂未找到足够可靠的信息", "根据检索", "作为一个人工智能语言模型"];

    readonly AIKey key;
    readonly HttpClient http;
    readonly Func<AIConfig> config;
    public KeyState KeyState { get; private set; }
    public DateTimeOffset? RateLimitedAt { get; private set; }
    /// Why the last check failed, shown under the key: a Mac string key and its arguments for LF()
    /// ("连不上 %@，请检查网络或代理", "ZenMux"); null when it didn't.
    public (string Key, object[] Args)? Problem { get; private set; }
    /// How long the last good check took.
    public double? Seconds { get; private set; }
    /// Whether the hear model takes audio: null until a check asked (always true on Ling).
    public bool? Hears { get; private set; }
    /// The service's models from `/models`, recommended first: all that chat, and those that hear.
    public IReadOnlyList<string> TextCatalog { get; private set; } = [];
    public IReadOnlyList<string> HearCatalog { get; private set; } = [];
    public event Action? Changed;

    public LingClient(AIKey key, HttpMessageHandler? handler = null, Func<AIConfig>? config = null)
    {
        this.key = key;
        this.config = config ?? (() => AIConfig.Default);
        http = handler is null ? new HttpClient() : new HttpClient(handler);
        http.Timeout = Timeout.InfiniteTimeSpan; // per request below
        http.DefaultRequestHeaders.UserAgent.ParseAdd("Cicada-Windows/0.1");
        KeyState = CurrentKey() is null ? KeyState.None : KeyState.Unchecked;
        Hears = Config.IsLing ? true : null;
    }

    public AIConfig Config => config();
    public AIProvider Provider => Config.Provider;

    /// The key for the service in use. A custom service on this computer may need none: "".
    public string? CurrentKey()
    {
        var c = Config;
        var k = key.Read();
        if (k is null && c.Provider.Id == "custom" && c.Base is { } b && AIProvider.IsLocal(b)) return "";
        return k;
    }

    public bool HasKey => CurrentKey() is not null;
    public bool Usable => HasKey && KeyState != KeyState.Invalid;
    /// Voices in the room from this service (else Windows' own voice speaks).
    public bool Speaks => Usable && Config.HasVoices;
    /// Listening and 同声传译 can work: the hear model wasn't found to refuse audio.
    public bool CanHear => Usable && Hears != false && Config.HearModel.Length > 0;

    /// The key, the service or its models changed: forget what the last check found.
    public void KeyChanged()
    {
        key.Reload();
        KeyState = CurrentKey() is null ? KeyState.None : KeyState.Unchecked;
        Problem = null;
        Hears = Config.IsLing ? true : null;
        TextCatalog = HearCatalog = [];
        Changed?.Invoke();
    }

    /// The cheapest request that proves the key: Ling's tiny model, else one token from the text
    /// model. The others' hear model must also take audio (half a second of silence), and a custom
    /// service must return JSON (the notes need it).
    public async Task<(KeyState state, double seconds)> Check()
    {
        KeyState = KeyState.Checking; Problem = null; Changed?.Invoke();
        var c = Config;
        var name = c.Provider.Id == "custom" ? "这个服务" : c.Name;
        var started = DateTime.UtcNow;
        var state = KeyState.Unreachable;
        try
        {
            if (c.IsLing)
            {
                await Chat("Reply with OK.", "Reply.", Priority.Speak, maxTokens: 5, timeout: 10, model: "Ling-3.0-tiny");
                Seconds = (DateTime.UtcNow - started).TotalSeconds;
                Hears = true;
            }
            else
            {
                if (c.Base is null || c.TextModel.Length == 0) throw new LingException(LingException.Kind.NoKey);
                await Chat("Reply with OK.", "Reply.", Priority.Speak, maxTokens: 5, timeout: 20);
                Seconds = (DateTime.UtcNow - started).TotalSeconds;
                if (c.Provider.Id == "custom")
                {
                    try { await Chat("Reply with the JSON object {\"ok\": true}.", "Reply.", Priority.Speak, json: true, maxTokens: 20, timeout: 20); }
                    catch (LingException e) when (e.Failure == LingException.Kind.Http) { Problem = ("这个服务不支持 JSON（HTTP %lld），纪要用不了", [e.Status]); }
                }
                Hears = await HearsAudio(c);
            }
            state = KeyState.Ok;
        }
        catch (LingException e)
        {
            // A busy key is still a good key.
            state = e.Failure switch { LingException.Kind.NoKey => KeyState.None, LingException.Kind.InvalidKey => KeyState.Invalid, LingException.Kind.RateLimited => KeyState.Ok, _ => KeyState.Unreachable };
            if (e.Failure == LingException.Kind.Http && e.Status is 400 or 404)
                Problem = c.Provider.Id == "custom" ? ("找不到模型，或地址不对（HTTP %lld）", [e.Status]) : ("%@ 拒绝了请求（HTTP %lld），请检查模型名", [name, e.Status]);
            else if (state == KeyState.Unreachable) Problem = ("连不上 %@，请检查网络或代理", [name]);
        }
        catch (Exception)
        {
            state = KeyState.Unreachable;
            Problem = ("连不上 %@，请检查网络或代理", [name]);
        }
        KeyState = state;
        Log.Debug($"ai {c.Provider.Id}: key check -> {state}{(Hears == false ? " (hear model refuses audio)" : "")}");
        Changed?.Invoke();
        if (state == KeyState.Ok && !c.IsLing) await FetchCatalog();
        return (KeyState, (DateTime.UtcNow - started).TotalSeconds);
    }

    /// Whether the hear model takes audio: a 400, 404, 415 or 422 says no; anything else can't tell.
    async Task<bool?> HearsAudio(AIConfig c)
    {
        if (c.HearModel.Length == 0) return false;
        try
        {
            await Chat("Transcribe the audio.", "Reply with what is said, or NONE.", Priority.Speak, maxTokens: 10, timeout: 20,
                model: c.HearModel, audio: Wav.Bytes(new short[8000]));
            return true;
        }
        catch (LingException e) when (e.Failure == LingException.Kind.Http && e.Status is 400 or 404 or 415 or 422) { return false; }
        catch (LingException e) when (e.Failure == LingException.Kind.Hijacked) { return true; }
        catch (LingException) { return null; }
    }

    /// The service's models, for the model menus. Quietly just the recommended ones when the
    /// service has no `/models`.
    public async Task FetchCatalog()
    {
        var c = Config;
        if (c.IsLing || CurrentKey() is not { } k || c.Base is null) return;
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, new Uri(new Uri(c.Base), "models"));
            if (k.Length > 0) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", k);
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(20));
            using var res = await http.SendAsync(req, cts.Token);
            if (res.StatusCode != HttpStatusCode.OK) return;
            var body = await res.Content.ReadAsStringAsync(cts.Token);
            TextCatalog = AIProvider.Catalog(body, c.Provider.TextModels.Select(m => m.Id), hears: false);
            HearCatalog = AIProvider.Catalog(body, c.Provider.HearModels.Select(m => m.Id), hears: true);
            Log.Debug($"ai {c.Provider.Id}: {TextCatalog.Count} models, {HearCatalog.Count} hear");
            Changed?.Invoke();
        }
        catch (Exception e) when (e is HttpRequestException or OperationCanceledException) { }
    }

    /// One chat completion. `content` goes in the system message, `instruction` is the fixed user
    /// message, `audio` (a WAV) goes before it for the hear model. Notes retry 429s with backoff;
    /// the rest fail fast so the caller can fall back. `model` defaults to the service's text model.
    public async Task<string> Chat(string content, string instruction, Priority priority, bool json = false,
        int maxTokens = 1024, double timeout = 30, string? model = null, byte[]? audio = null, CancellationToken cancel = default)
    {
        var k = CurrentKey() ?? throw new LingException(LingException.Kind.NoKey);
        if (KeyState == KeyState.Invalid) throw new LingException(LingException.Kind.InvalidKey);
        var c = Config;
        if (c.Base is null) throw new LingException(LingException.Kind.NoKey);
        model ??= c.TextModel;
        JsonNode user = audio is null ? JsonValue.Create(instruction)! : new JsonArray(c.AudioPart(audio, model), new JsonObject { ["type"] = "text", ["text"] = instruction });
        var body = new JsonObject
        {
            ["model"] = model,
            ["messages"] = new JsonArray(
                new JsonObject { ["role"] = "system", ["content"] = content },
                new JsonObject { ["role"] = "user", ["content"] = user }),
            ["stream"] = false,
        };
        c.Shape(body, maxTokens);
        if (json) body["response_format"] = new JsonObject { ["type"] = "json_object" };
        var payload = body.ToJsonString();
        var url = new Uri(new Uri(c.Base), "chat/completions");

        // Notes can wait; heard audio gets one retry, since on Windows a lost reply loses the words
        // (on the Mac recognition is local and only the translation is lost); the rest fail fast.
        int attempts = priority == Priority.Notes ? 4 : audio is not null ? 2 : 1;
        double delay = 1;
        for (int attempt = 1; ; attempt++)
        {
            var queued = DateTime.UtcNow;
            await Acquire(priority, c.Provider.Spacing, cancel);
            var started = DateTime.UtcNow;
            if ((started - queued).TotalSeconds > 1) Log.Debug($"ling: {priority} waited {(started - queued).TotalMilliseconds:F0} ms at the gate");
            try
            {
                var root = await Post(url, payload, k, timeout, cancel);
                var choice = root["choices"]?[0];
                var text = Str(choice?["message"]?["content"]) ?? throw new LingException(LingException.Kind.Parse);
                var finish = Str(choice?["finish_reason"]);
                var trimmed = text.Trim();
                // Ling's search essays come without a finish reason; other services may simply omit it.
                if (finish is null && c.IsLing || HijackPrefixes.Any(trimmed.StartsWith))
                {
                    Log.Debug($"ling: {priority} search-style reply dropped");
                    throw new LingException(LingException.Kind.Hijacked);
                }
                var usage = root["usage"];
                Log.Debug($"ai {c.Provider.Id}: {priority} ok {(int)(DateTime.UtcNow - started).TotalMilliseconds} ms tokens={usage?["prompt_tokens"]}/{usage?["completion_tokens"]}");
                if (RateLimitedAt is not null) { RateLimitedAt = null; Changed?.Invoke(); }
                return trimmed;
            }
            catch (LingException e) when (e.Failure == LingException.Kind.RateLimited)
            {
                if (attempt >= attempts) { RateLimitedAt = DateTimeOffset.Now; Changed?.Invoke(); throw; }
                var wait = delay + Random.Shared.NextDouble() * 0.5;
                Log.Debug($"ling: {priority} 429, retry in {wait:F1} s");
                await Task.Delay(TimeSpan.FromSeconds(wait), cancel);
                delay *= 2;
            }
        }
    }

    /// The service's voice for `text`: raw 24 kHz mono 16-bit PCM, chunk by chunk as it arrives.
    /// On Ling, `voice` is Ming's and `languageId` its `language_id`, needed for ja, ko, de, fr and
    /// es (Ling.swift › speech); elsewhere the configured speech model, and a voice not in the
    /// service's list becomes its first. Replies come three ways and all are read: server-sent
    /// base64 chunks (Ling, ZenMux), raw PCM (OpenRouter), or one JSON `{"audio": <WAV>}`.
    public async IAsyncEnumerable<byte[]> Speech(string text, string? voice, string? languageId = null,
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancel = default)
    {
        var k = CurrentKey() ?? throw new LingException(LingException.Kind.NoKey);
        if (KeyState == KeyState.Invalid) throw new LingException(LingException.Kind.InvalidKey);
        var c = Config;
        if (!c.HasVoices) throw new LingException(LingException.Kind.NoKey);
        var body = new JsonObject { ["model"] = c.VoiceModel, ["input"] = text, ["response_format"] = "pcm" };
        if (c.IsLing)
        {
            body["voice"] = voice ?? "UK_Charlotte";
            body["sample_rate"] = 24000; body["stream"] = true; body["stream_format"] = "sse";
            if (languageId is not null) body["language_id"] = languageId;
        }
        else
        {
            // OpenRouter documents no `stream` (it streams the bytes anyway); ZenMux needs it.
            if (c.Provider.Id != "openrouter") body["stream"] = true;
            var ids = c.Voices.Select(v => v.Id).ToList();
            body["voice"] = voice is not null && ids.Contains(voice) ? voice : ids.FirstOrDefault() ?? c.CustomVoice ?? "Kore";
        }
        await Acquire(Priority.Speak, c.Provider.Spacing, cancel);
        var started = DateTime.UtcNow;
        using var req = new HttpRequestMessage(HttpMethod.Post, new Uri(new Uri(c.VoiceBase!), "audio/speech"))
        {
            Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json"),
        };
        if (k.Length > 0) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", k);
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        cts.CancelAfter(TimeSpan.FromSeconds(20));
        HttpResponseMessage res;
        try { res = await http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, cts.Token); }
        catch (OperationCanceledException) when (!cancel.IsCancellationRequested) { throw new LingException(LingException.Kind.Timeout); }
        catch (HttpRequestException e) { Log.Debug($"ling: voice network error {e.HttpRequestError}"); throw new LingException(LingException.Kind.Network); }
        using (res)
        {
            switch (res.StatusCode)
            {
                case HttpStatusCode.OK: break;
                case HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden:
                    if (KeyState != KeyState.Invalid) { KeyState = KeyState.Invalid; Changed?.Invoke(); }
                    throw new LingException(LingException.Kind.InvalidKey);
                case HttpStatusCode.TooManyRequests: throw new LingException(LingException.Kind.RateLimited);
                default: Log.Debug($"ai {c.Provider.Id}: voice HTTP {(int)res.StatusCode}"); throw new LingException(LingException.Kind.Http, (int)res.StatusCode);
            }
            var kind = res.Content.Headers.ContentType?.MediaType ?? "";
            var stream = await res.Content.ReadAsStreamAsync(cts.Token);
            int chunks = 0;
            if (kind.Contains("event-stream") || c.IsLing)
            {
                using var reader = new StreamReader(stream);
                while (true)
                {
                    string? line;
                    try { line = await reader.ReadLineAsync(cts.Token); }
                    catch (OperationCanceledException) when (!cancel.IsCancellationRequested) { throw new LingException(LingException.Kind.Timeout); }
                    if (line is null) break;
                    var pcm = SpeechChunk(line, out var done);
                    if (done) break;
                    if (pcm is null) continue;
                    if (chunks++ == 0) Log.Debug($"ai {c.Provider.Id}: Speak first audio {(int)(DateTime.UtcNow - started).TotalMilliseconds} ms");
                    yield return pcm;
                }
            }
            else if (kind.Contains("json"))
            {
                string all;
                try { all = await new StreamReader(stream).ReadToEndAsync(cts.Token); }
                catch (OperationCanceledException) when (!cancel.IsCancellationRequested) { throw new LingException(LingException.Kind.Timeout); }
                byte[] wav;
                try { wav = Convert.FromBase64String(JsonNode.Parse(all)?["audio"]?.GetValue<string>() ?? throw new LingException(LingException.Kind.Parse)); }
                catch (Exception e) when (e is JsonException or FormatException or InvalidOperationException) { throw new LingException(LingException.Kind.Parse); }
                Log.Debug($"ai {c.Provider.Id}: Speak audio {(int)(DateTime.UtcNow - started).TotalMilliseconds} ms");
                yield return PcmFromWav(wav);
            }
            else
            {
                // Raw PCM: handed on in 0.1 s pieces at 24 kHz, so playback starts early.
                var buffer = new byte[4800];
                while (true)
                {
                    int n;
                    try { n = await stream.ReadAsync(buffer, cts.Token); }
                    catch (OperationCanceledException) when (!cancel.IsCancellationRequested) { throw new LingException(LingException.Kind.Timeout); }
                    if (n == 0) break;
                    if (chunks++ == 0) Log.Debug($"ai {c.Provider.Id}: Speak first audio {(int)(DateTime.UtcNow - started).TotalMilliseconds} ms");
                    yield return buffer[..n];
                }
            }
        }
    }

    /// One SSE line of a voice stream: the PCM it carries, or `done` at the end.
    public static byte[]? SpeechChunk(string line, out bool done)
    {
        done = false;
        if (!line.StartsWith("data:")) return null;
        JsonNode? obj;
        try { obj = JsonNode.Parse(line[5..]); } catch (JsonException) { return null; }
        if (obj is not JsonObject) return null;
        if (Str(obj["type"]) == "speech.audio.done") { done = true; return null; }
        if (Str(obj["audio"]) is not { Length: > 0 } b64) return null;
        try { return Convert.FromBase64String(b64); } catch (FormatException) { return null; }
    }

    static string? Str(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    /// The samples of a WAV (its `data` chunk); the bytes themselves when there's no header.
    public static byte[] PcmFromWav(byte[] wav)
    {
        if (wav.Length < 12 || Encoding.ASCII.GetString(wav, 0, 4) != "RIFF") return wav;
        int at = 12;
        while (at + 8 <= wav.Length)
        {
            int size = BitConverter.ToInt32(wav, at + 4);
            if (Encoding.ASCII.GetString(wav, at, 4) == "data") return wav[(at + 8)..Math.Min(wav.Length, at + 8 + size)];
            at += 8 + size + (size & 1);
        }
        return [];
    }

    async Task<JsonNode> Post(Uri url, string payload, string k, double timeout, CancellationToken cancel)
    {
        using var req = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(payload, Encoding.UTF8, "application/json"),
        };
        if (k.Length > 0) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", k);
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        cts.CancelAfter(TimeSpan.FromSeconds(timeout));
        HttpResponseMessage res;
        try { res = await http.SendAsync(req, cts.Token); }
        catch (OperationCanceledException) when (!cancel.IsCancellationRequested) { throw new LingException(LingException.Kind.Timeout); }
        catch (HttpRequestException e)
        {
            Log.Debug($"ling: network error {e.HttpRequestError}");
            throw new LingException(LingException.Kind.Network);
        }
        using (res)
        {
            switch (res.StatusCode)
            {
                case HttpStatusCode.OK: break;
                case HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden:
                    if (KeyState != KeyState.Invalid) { KeyState = KeyState.Invalid; Changed?.Invoke(); }
                    throw new LingException(LingException.Kind.InvalidKey);
                case HttpStatusCode.TooManyRequests: throw new LingException(LingException.Kind.RateLimited);
                default:
                    Log.Debug($"ling: HTTP {(int)res.StatusCode}");
                    throw new LingException(LingException.Kind.Http, (int)res.StatusCode);
            }
            try
            {
                var text = await res.Content.ReadAsStringAsync(cts.Token);
                return JsonNode.Parse(text) ?? throw new LingException(LingException.Kind.Parse);
            }
            catch (OperationCanceledException) when (!cancel.IsCancellationRequested) { throw new LingException(LingException.Kind.Timeout); }
            catch (JsonException) { throw new LingException(LingException.Kind.Parse); }
        }
    }

    // Start gate: request starts ≥ the service's spacing apart, the most urgent waiting one first.

    /// Tests only: overrides the service's spacing.
    public static double? Spacing { get; set; }
    readonly object gate = new();
    DateTime lastStart = DateTime.MinValue;
    readonly List<(Priority priority, long seq, TaskCompletionSource ready)> waiting = [];
    long seq;
    bool pumping;
    double spacing = 0.6;

    Task Acquire(Priority priority, double serviceSpacing, CancellationToken cancel)
    {
        lock (gate)
        {
            spacing = Spacing ?? serviceSpacing;
            if (waiting.Count == 0 && (DateTime.UtcNow - lastStart).TotalSeconds >= spacing)
            {
                lastStart = DateTime.UtcNow;
                return Task.CompletedTask;
            }
            var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            waiting.Add((priority, ++seq, ready));
            if (!pumping) { pumping = true; _ = Pump(); }
            return ready.Task.WaitAsync(cancel);
        }
    }

    async Task Pump()
    {
        while (true)
        {
            double wait;
            lock (gate) wait = Math.Max(0, spacing - (DateTime.UtcNow - lastStart).TotalSeconds);
            if (wait > 0) await Task.Delay(TimeSpan.FromSeconds(wait));
            lock (gate)
            {
                if (waiting.Count == 0) { pumping = false; return; }
                var next = waiting.MinBy(w => ((int)w.priority, w.seq));
                waiting.Remove(next);
                lastStart = DateTime.UtcNow;
                next.ready.TrySetResult();
            }
        }
    }
}
