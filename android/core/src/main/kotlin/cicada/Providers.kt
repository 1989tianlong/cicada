package cicada

import java.net.URI
import java.util.Base64

/// The AI services the port can use (AIProviders.swift, plus what hears audio; the Linux port's
/// providers.py is the same table). Ling is the reference: Ming hears each stretch of audio and
/// answers language, original and translation in one call, and only Ling clones the user's voice.
/// The others are OpenAI-compatible and hear through an audio-input chat model with the same
/// prompt (tools/audio-probe, 2026-11: about as accurate, 0.5–2 s slower). OpenAI itself is left
/// out: a port needs a model that hears, and its audio models are untested.
///
/// Recommended models come first in every menu and are the defaults. For hearing, the first is the
/// one that wrote nothing for a clip without speech: a made-up line ends up in the notes and, in
/// 面对面, read aloud to the other side.
data class Model(val id: String, /** Why it is recommended: a Chinese UI key, localized where shown. */ val note: String = "")

data class CloudVoice(val id: String, /** "女" / "男", a Chinese UI key. */ val gender: String)

class Provider(
    val id: String,
    val name: String,
    /** Null for "custom": the user's address. */
    val base: String?,
    /** Where to create a key. */
    val site: String?,
    val textModels: List<Model> = emptyList(),
    val hearModels: List<Model> = emptyList(),
    /** Empty: this service can't speak to the other side here. */
    val voiceModels: List<Model> = emptyList(),
    /** Of `voiceModels` (Gemini TTS: the same names in every language). */
    val voices: List<CloudVoice> = emptyList(),
    val clones: Boolean = false,
    /** Ling allows ~2 request starts a second; the aggregators far more. */
    val spacing: Double = 0.1,
) {
    val hasVoices get() = voiceModels.isNotEmpty()
}

object Providers {
    val GEMINI_VOICES = listOf(CloudVoice("Kore", "女"), CloudVoice("Aoede", "女"), CloudVoice("Charon", "男"), CloudVoice("Puck", "男"))

    val LING = Provider("ling", "Ling", "https://api.ant-ling.com/v1/", "https://chat.ant-ling.com/platform/api",
        textModels = listOf(Model("Ling-3.1-flash", "更准"), Model("Ling-3.0-flash", "更快、更省")),
        hearModels = listOf(Model("Ming-3.0-audio-flash")),
        voiceModels = listOf(Model("Ming-3.0-tts-0.5B")), clones = true, spacing = 0.6)

    val OPENROUTER = Provider("openrouter", "OpenRouter", "https://openrouter.ai/api/v1/", "https://openrouter.ai/settings/keys",
        textModels = listOf(Model("inclusionai/ling-3.1-flash", "和 Ling 同款"), Model("qwen/qwen3.8-flash", "中文好")),
        hearModels = listOf(Model("qwen/qwen3.8-omni-flash", "没人说话时不乱写"), Model("google/gemini-3.1-flash-lite", "最快，偶尔把杂音写成字")),
        voiceModels = listOf(Model("google/gemini-3.8-flash-tts", "效果和价格最均衡"), Model("google/gemini-3.8-flash-lite-tts", "更省")),
        voices = GEMINI_VOICES)

    val ZENMUX = Provider("zenmux", "ZenMux", "https://zenmux.ai/api/v1/", "https://zenmux.ai/settings/keys",
        textModels = listOf(Model("inclusionai/ling-3.0-flash", "和 Ling 同款"), Model("qwen/qwen3.8-flash", "中文好")),
        hearModels = listOf(Model("qwen/qwen3.8-omni-flash", "没人说话时不乱写"), Model("bytedance/doubao-seed-2.0-mini", "更快"),
                            Model("google/gemini-3.1-flash-lite", "最快，偶尔把杂音写成字")),
        voiceModels = listOf(Model("google/gemini-3.8-flash-tts", "效果和价格最均衡"), Model("google/gemini-3.8-flash-lite-tts", "更省")),
        voices = GEMINI_VOICES)

    /// Any OpenAI-compatible address (a company gateway, Ollama…). Its hear model must take audio
    /// in; voices only when the user names a speech model.
    val CUSTOM = Provider("custom", "其他（兼容 OpenAI）", null, null)

    val ALL = listOf(LING, OPENROUTER, ZENMUX, CUSTOM)

    fun named(raw: String?): Provider = ALL.firstOrNull { it.id == raw } ?: LING

    fun isLocal(hostOrUrl: String): Boolean {
        val u = if ("://" in hostOrUrl) hostOrUrl else "http://$hostOrUrl"
        val host = try { URI(u).host } catch (_: Exception) { null } ?: hostOrUrl
        return host in listOf("localhost", "127.0.0.1", "::1", "[::1]")
    }

    /// The address as typed, normalized: https, or http only on this device; ends in "/". On a
    /// phone "localhost" is the phone itself (a model running in Termux, say).
    fun customBase(raw: String?): String? {
        var s = raw?.trim() ?: return null
        if (s.isEmpty()) return null
        if ("://" !in s) s = (if (isLocal(s)) "http://" else "https://") + s
        if (!s.endsWith("/")) s += "/"
        val uri = try { URI(s) } catch (_: Exception) { return null }
        val host = uri.host ?: return null
        return when (uri.scheme) {
            "https" -> s
            "http" -> if (isLocal(host)) s else null
            else -> null
        }
    }

    /// The service, its address and models from the app's settings (Settings.swift › aiConfig).
    fun configFrom(s: AppSettings): AIConfig {
        val p = named(s.aiProvider)
        if (p.id == "ling") {
            val text = if (p.textModels.any { it.id == s.model }) s.model else p.textModels[0].id
            return AIConfig(p, p.base, text, p.hearModels[0].id, p.voiceModels[0].id, p.base)
        }
        if (p.id == "custom") {
            val base = customBase(s.aiCustomBase)
            val voice = s.aiVoiceModels["custom"]?.trim().orEmpty()
            val voiceBase = if (s.aiCustomVoiceBase.isNotBlank()) customBase(s.aiCustomVoiceBase) else base
            val name = s.aiCustomVoice.trim()
            return AIConfig(p, base, s.aiModels["custom"]?.trim().orEmpty(), s.aiHearModels["custom"]?.trim().orEmpty(),
                            voice.ifEmpty { null }, if (voice.isNotEmpty()) voiceBase else null, name.ifEmpty { null })
        }
        return AIConfig(p, p.base, s.aiModels[p.id]?.ifBlank { null } ?: p.textModels[0].id,
                        s.aiHearModels[p.id]?.ifBlank { null } ?: p.hearModels[0].id,
                        s.aiVoiceModels[p.id]?.ifBlank { null } ?: p.voiceModels[0].id, p.base)
    }

    private val NOT_CHAT = Regex("(embed|whisper|tts|transcribe|dall-e|image|moderation|realtime|sora|search|video|seedance|wan\\d)")

    /// Model ids from a `/models` reply, recommended ones first: those that answer in text, and for
    /// `hears` only those that take audio in. ZenMux lists modalities at the top level, OpenRouter
    /// under `architecture`; a service that says nothing keeps everything but obvious non-chat names.
    fun catalog(body: String, recommended: List<String>, hears: Boolean): List<String> {
        val root = Json.parseObject(body) ?: return recommended
        val ids = mutableListOf<String>()
        for (raw in root["data"].arr()) {
            val m = raw.obj() ?: continue
            val id = m["id"].str() ?: continue
            if (id.isEmpty() || id.endsWith(":batch")) continue
            val a = m["architecture"].obj()
            val ins = (m["input_modalities"] ?: a?.get("input_modalities")).arr().mapNotNull { it.str() }
            val outs = (m["output_modalities"] ?: a?.get("output_modalities")).arr().mapNotNull { it.str() }
            if (outs.isNotEmpty() && "text" !in outs) continue
            if (ins == listOf("audio")) continue // speech-to-text only: no prompt, no translation
            if (hears && "audio" !in ins) continue
            if (outs.isEmpty() && NOT_CHAT.containsMatchIn(id)) continue
            ids.add(id)
        }
        return recommended + ids.filter { it !in recommended }.distinct().sorted()
    }
}

/// What one call needs to know about the service in use, resolved from settings each time.
class AIConfig(
    val provider: Provider,
    /** Null: a custom service without a valid address yet. */
    val base: String?,
    val textModel: String,
    val hearModel: String,
    /** Null: no voices with this service. */
    val voiceModel: String? = null,
    val voiceBase: String? = null,
    val customVoice: String? = null,
) {
    val isLing get() = provider.id == "ling"
    val hasVoices get() = voiceModel != null && voiceBase != null

    /// The voices the other side can be read to in with this service (Ling's are Ming's own).
    val voices: List<CloudVoice> get() = when {
        !hasVoices || isLing -> emptyList()
        provider.id == "custom" -> customVoice?.let { listOf(CloudVoice(it, "")) } ?: emptyList()
        else -> provider.voices
    }

    /// Each service turns thinking off its own way (AIConfig.shape on the Mac).
    fun shape(body: MutableMap<String, Any?>, maxTokens: Int) {
        body["max_tokens"] = maxTokens
        body["temperature"] = 0.2
        if (isLing) body["thinking"] = mapOf("type" to "disabled")
        else if (provider.id == "openrouter" || provider.id == "zenmux") body["reasoning"] = mapOf("enabled" to false)
    }

    /// One clip in a user message: Ming takes a data URL (of any type: the app sends AAC); the
    /// others the standard `input_audio` WAV, except that Qwen's omni models want the data URL
    /// inside it (DashScope's form).
    fun audioPart(audio: ByteArray, model: String, type: String = "audio/wav"): Map<String, Any?> {
        val b64 = Base64.getEncoder().encodeToString(audio)
        if (isLing) return mapOf("type" to "audio_url", "audio_url" to mapOf("url" to "data:$type;base64,$b64"))
        val data = if (model.substringAfterLast('/').startsWith("qwen")) "data:audio/wav;base64,$b64" else b64
        return mapOf("type" to "input_audio", "input_audio" to mapOf("data" to data, "format" to "wav"))
    }
}
