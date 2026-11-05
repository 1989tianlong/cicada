using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Cicada;

/// A model a service recommends, and why: `Note` is a Chinese UI key, localized where shown.
public sealed record AIModel(string Id, string Note = "");

/// One of a service's speech voices; `Gender` is "女" / "男" (a UI key) or "".
public sealed record CloudVoice(string Id, string Gender);

/// The AI services the port can use (the Mac's AIProviders.swift, plus what hears audio). Ling is
/// the reference: Ming hears each stretch of audio and answers language, original and translation
/// in one call, and only Ling clones the user's voice. The others are OpenAI-compatible and hear
/// through an audio-input chat model with the same prompt (tools/audio-probe measured them against
/// Ming, 2026-11: about as accurate, 0.5–2 s slower). OpenAI itself is left out: a port needs a
/// model that hears, and its audio models are untested.
///
/// Recommended models come first in every menu and are the defaults. For hearing, the first is the
/// one that wrote nothing for a clip without speech: a made-up line ends up in the notes and, when
/// interpreting, in the room.
public sealed record AIProvider(string Id, string Name, string? Base, string? Site,
    AIModel[] TextModels, AIModel[] HearModels, AIModel[] VoiceModels, CloudVoice[] Voices, bool Clones = false, double Spacing = 0.1)
{
    public bool HasVoices => VoiceModels.Length > 0;

    static readonly CloudVoice[] Gemini = [new("Kore", "女"), new("Aoede", "女"), new("Charon", "男"), new("Puck", "男")];

    // Ling allows ~2 request starts a second; the aggregators far more.
    public static readonly AIProvider Ling = new("ling", "Ling", "https://api.ant-ling.com/v1/", "https://chat.ant-ling.com/platform/api",
        [new("Ling-3.1-flash", "更准"), new("Ling-3.0-flash", "更快、更省")], [new("Ming-3.0-audio-flash")], [new("Ming-3.0-tts-0.5B")], [],
        Clones: true, Spacing: 0.6);

    public static readonly AIProvider OpenRouter = new("openrouter", "OpenRouter", "https://openrouter.ai/api/v1/", "https://openrouter.ai/settings/keys",
        [new("inclusionai/ling-3.1-flash", "和 Ling 同款"), new("qwen/qwen3.8-flash", "中文好")],
        [new("qwen/qwen3.8-omni-flash", "没人说话时不乱写"), new("google/gemini-3.1-flash-lite", "最快，偶尔把杂音写成字")],
        [new("google/gemini-3.8-flash-tts", "效果和价格最均衡"), new("google/gemini-3.8-flash-lite-tts", "更省")], Gemini);

    public static readonly AIProvider ZenMux = new("zenmux", "ZenMux", "https://zenmux.ai/api/v1/", "https://zenmux.ai/settings/keys",
        [new("inclusionai/ling-3.0-flash", "和 Ling 同款"), new("qwen/qwen3.8-flash", "中文好")],
        [new("qwen/qwen3.8-omni-flash", "没人说话时不乱写"), new("bytedance/doubao-seed-2.0-mini", "更快"), new("google/gemini-3.1-flash-lite", "最快，偶尔把杂音写成字")],
        [new("google/gemini-3.8-flash-tts", "效果和价格最均衡"), new("google/gemini-3.8-flash-lite-tts", "更省")], Gemini);

    /// Any OpenAI-compatible address (a company gateway, Ollama…). Its hear model must take audio
    /// in; voices only when the user names a speech model, else Windows speaks.
    public static readonly AIProvider Custom = new("custom", "其他（兼容 OpenAI）", null, null, [], [], [], []);

    public static readonly AIProvider[] All = [Ling, OpenRouter, ZenMux, Custom];

    /// A service never named (or OpenAI, which the ports don't offer) is Ling.
    public static AIProvider Named(string? id) => All.FirstOrDefault(p => p.Id == id) ?? Ling;

    public static bool IsLocal(string hostOrUrl)
    {
        var u = hostOrUrl.Contains("://") ? hostOrUrl : "http://" + hostOrUrl;
        var host = Uri.TryCreate(u, UriKind.Absolute, out var uri) ? uri.Host.Trim('[', ']') : hostOrUrl;
        return host is "localhost" or "127.0.0.1" or "::1";
    }

    /// The address as typed, normalized: https, or http only on this computer; ends in "/".
    public static string? CustomBase(string? raw)
    {
        var s = (raw ?? "").Trim();
        if (s.Length == 0) return null;
        if (!s.Contains("://")) s = (IsLocal(s) ? "http://" : "https://") + s;
        if (!s.EndsWith('/')) s += "/";
        if (!Uri.TryCreate(s, UriKind.Absolute, out var u) || u.Host.Length == 0) return null;
        if (u.Scheme == "https") return s;
        return u.Scheme == "http" && IsLocal(u.Host) ? s : null;
    }

    static readonly Regex NotChat = new(@"(embed|whisper|tts|transcribe|dall-e|image|moderation|realtime|sora|search|video|seedance|wan\d)");

    /// Model ids from a `/models` reply, recommended ones first: those that answer in text, and for
    /// `hears` only those that take audio in. ZenMux lists modalities at the top level, OpenRouter
    /// under `architecture`; a service that says nothing keeps everything but obvious non-chat names.
    public static List<string> Catalog(string json, IEnumerable<string> recommended, bool hears)
    {
        JsonNode? root;
        try { root = JsonNode.Parse(json); } catch (System.Text.Json.JsonException) { root = null; }
        var ids = new List<string>();
        if (root is JsonObject o && o["data"] is JsonArray data)
            foreach (var m in data.OfType<JsonObject>())
            {
                if (Str(m["id"]) is not { Length: > 0 } id || id.EndsWith(":batch")) continue;
                var arch = m["architecture"] as JsonObject;
                var ins = Strs(m["input_modalities"] ?? arch?["input_modalities"]);
                var outs = Strs(m["output_modalities"] ?? arch?["output_modalities"]);
                if (outs.Count > 0 && !outs.Contains("text")) continue;
                if (ins is ["audio"]) continue; // speech-to-text only: no prompt, no translation
                if (hears && !ins.Contains("audio")) continue;
                if (outs.Count == 0 && NotChat.IsMatch(id)) continue;
                ids.Add(id);
            }
        var rec = recommended.ToList();
        return [.. rec, .. ids.Where(i => !rec.Contains(i)).Distinct().Order(StringComparer.Ordinal)];
    }

    static string? Str(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;
    static List<string> Strs(JsonNode? n) => n is JsonArray a ? a.Select(Str).OfType<string>().ToList() : [];
}

/// What one call needs to know about the service in use, resolved from settings each time
/// (Settings.swift › aiConfig). `Base` is null for a custom service without a valid address yet;
/// `VoiceModel` null when the service can't speak here.
public sealed record AIConfig(AIProvider Provider, string? Base, string TextModel, string HearModel,
    string? VoiceModel = null, string? VoiceBase = null, string? CustomVoice = null)
{
    public bool IsLing => Provider.Id == "ling";
    public bool HasVoices => VoiceModel is not null && VoiceBase is not null;
    /// What the UI and errors call it ("其他（兼容 OpenAI）" is a UI key, localized by the caller).
    public string Name => Provider.Id == "custom" ? Strings.L(Provider.Name) : Provider.Name;

    /// The voices the room can pick from with this service (Ling's are Ming's, in VoiceCatalog).
    public IReadOnlyList<CloudVoice> Voices =>
        !HasVoices || IsLing ? [] : Provider.Id == "custom" ? (CustomVoice is { } v ? [new CloudVoice(v, "")] : []) : Provider.Voices;

    public static AIConfig Default => From(new AppSettings());

    /// Each service turns thinking off its own way (AIConfig.shape on the Mac).
    public void Shape(JsonObject body, int maxTokens)
    {
        body["max_tokens"] = maxTokens;
        body["temperature"] = 0.2;
        if (IsLing) body["thinking"] = new JsonObject { ["type"] = "disabled" };
        else if (Provider.Id is "openrouter" or "zenmux") body["reasoning"] = new JsonObject { ["enabled"] = false };
    }

    /// One WAV in a user message: Ming takes a data URL; the others the standard `input_audio`,
    /// except that Qwen's omni models want the data URL inside it (DashScope's form).
    public JsonObject AudioPart(byte[] wav, string model)
    {
        var b64 = Convert.ToBase64String(wav);
        if (IsLing) return new JsonObject { ["type"] = "audio_url", ["audio_url"] = new JsonObject { ["url"] = "data:audio/wav;base64," + b64 } };
        if (model.Split('/')[^1].StartsWith("qwen")) b64 = "data:audio/wav;base64," + b64;
        return new JsonObject { ["type"] = "input_audio", ["input_audio"] = new JsonObject { ["data"] = b64, ["format"] = "wav" } };
    }

    /// The service, its address and models from the app's settings.
    public static AIConfig From(AppSettings s)
    {
        var p = AIProvider.Named(s.AiProvider);
        if (p.Id == "ling")
        {
            var text = p.TextModels.Any(m => m.Id == s.Model) ? s.Model : p.TextModels[0].Id;
            return new(p, p.Base, text, p.HearModels[0].Id, p.VoiceModels[0].Id, p.Base);
        }
        string Pick(Dictionary<string, string> table) => table.TryGetValue(p.Id, out var v) ? v.Trim() : "";
        if (p.Id == "custom")
        {
            var b = AIProvider.CustomBase(s.AiCustomBase);
            var voice = Pick(s.AiVoiceModels);
            var voiceBase = s.AiCustomVoiceBase.Trim().Length > 0 ? AIProvider.CustomBase(s.AiCustomVoiceBase) : b;
            var name = s.AiCustomVoice.Trim();
            return new(p, b, Pick(s.AiModels), Pick(s.AiHearModels), voice.Length > 0 ? voice : null,
                voice.Length > 0 ? voiceBase : null, name.Length > 0 ? name : null);
        }
        static string Or(string v, AIModel[] rec) => v.Length > 0 ? v : rec[0].Id;
        return new(p, p.Base, Or(Pick(s.AiModels), p.TextModels), Or(Pick(s.AiHearModels), p.HearModels), Or(Pick(s.AiVoiceModels), p.VoiceModels), p.Base);
    }
}
