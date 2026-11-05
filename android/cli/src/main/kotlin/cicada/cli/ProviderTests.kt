// AI 服务: the services other than Ling (Providers.kt), the same cases as the Linux port's
// tests/test_providers.py. No network: LingClient runs against a fake transport.
package cicada.cli

import cicada.*
import java.io.ByteArrayInputStream
import java.util.Base64

object ProviderTests {
    val tests: List<Pair<String, () -> Unit>> = listOf(
        "aiDefaultsAreTheRecommendedModels" to ::defaults,
        "aiChosenModelsAndACustomService" to ::chosenAndCustom,
        "aiCustomAddress" to ::customAddress,
        "aiSettingsKeepTheServiceAcrossARestart" to ::settingsRoundTrip,
        "aiEachServiceTurnsThinkingOffItsOwnWay" to ::shape,
        "aiAudioGoesInTheFormEachModelTakes" to ::audioPart,
        "aiCatalogListsChatModelsAndThoseThatHear" to ::catalog,
        "aiOneKeyFilePerService" to ::oneKeyFilePerService,
        "aiALocalCustomServiceNeedsNoKey" to ::localNeedsNoKey,
        "aiRequestsGoToTheServiceInItsShape" to ::requestShape,
        "aiLingStillDropsRepliesWithoutAFinishReason" to ::lingDropsNoFinish,
        "aiCheckFindsAHearModelThatRefusesAudio" to ::checkFindsDeafModel,
        "aiCheckSaysWhy" to ::checkSaysWhy,
        "aiSpeechFromEachService" to ::speech,
        "aiNoVoiceModelNoSpeech" to ::noVoiceNoSpeech,
        "aiHearingUsesTheHearModel" to ::hearingUsesHearModel,
        "aiProblemsNameTheService" to ::problemsNameTheService,
        "aiAClockIsNotSpeech" to ::clockIsNotSpeech,
        "aiFinalNotesKeepRetryingForAboutAMinute" to ::finalNotesRetry,
    )

    private fun check(ok: Boolean, what: String) { if (!ok) throw AssertionError(what) }
    private fun <T> equal(expected: T, actual: T, what: String) { if (expected != actual) throw AssertionError("$what: expected «$expected», got «$actual»") }

    /// Answers by URL and body; records what was sent and streamed.
    private class Fake(
        val respond: (String, String) -> Transport.Response,
        val streams: ((String, String) -> Transport.Stream)? = null,
    ) : Transport {
        val sent = mutableListOf<Pair<String, String>>()
        val streamed = mutableListOf<Pair<String, String>>()
        override fun send(url: String, method: String, body: String?, headers: Map<String, String>, timeoutMs: Int): Transport.Response {
            synchronized(sent) { sent.add(url to (body ?: "")) }
            return respond(url, body ?: "")
        }
        override fun stream(url: String, body: String, headers: Map<String, String>, timeoutMs: Int): Transport.Stream {
            streamed.add(url to body)
            return streams!!(url, body)
        }
    }

    private fun reply(content: String, finish: String? = "stop") = Transport.Response(200, Json.write(mapOf(
        "choices" to listOf(mapOf("message" to mapOf("content" to content), "finish_reason" to finish)),
    ), pretty = false))

    private fun client(fake: Transport, s: AppSettings, key: String? = "sk-test-0000000000"): LingClient {
        val k = AIKey(PlainProtector, service = { s.aiProvider })
        k.remove()
        if (key != null) k.save(key)
        return LingClient(k, fake, config = s::aiConfig)
    }

    private fun body(s: String) = Json.parse(s).obj()!!

    fun defaults() {
        val c = AppSettings(aiProvider = "zenmux").aiConfig()
        equal("https://zenmux.ai/api/v1/", c.base, "base")
        equal("qwen/qwen3.8-omni-flash", c.hearModel, "hear")
        equal("inclusionai/ling-3.0-flash", c.textModel, "text")
        equal("google/gemini-3.8-flash-tts", c.voiceModel, "voice")
        val ling = AppSettings().aiConfig()
        equal("Ming-3.0-audio-flash" to "Ling-3.1-flash", ling.hearModel to ling.textModel, "Ling")
        // Ling keeps its own key ("model"); a service never named falls back to Ling.
        equal("Ling-3.0-flash", AppSettings(model = "Ling-3.0-flash").aiConfig().textModel, "Ling's model")
        equal("ling", Providers.named("openai").id, "no OpenAI")
    }

    fun chosenAndCustom() {
        var s = AppSettings(aiProvider = "openrouter", aiHearModels = mutableMapOf("openrouter" to "google/gemini-3.1-flash-lite"))
        equal("google/gemini-3.1-flash-lite", s.aiConfig().hearModel, "chosen hear model")
        s = AppSettings(aiProvider = "custom", aiCustomBase = "localhost:11434/v1", aiModels = mutableMapOf("custom" to "qwen3:14b"))
        val c = s.aiConfig()
        equal("http://localhost:11434/v1/", c.base, "local base")
        equal("", c.hearModel, "no hear model yet")
        check(!c.hasVoices, "no voices without a speech model")
        s.aiVoiceModels["custom"] = "kokoro"; s.aiCustomVoice = "af_heart"
        equal("kokoro" to "http://localhost:11434/v1/", s.aiConfig().voiceModel to s.aiConfig().voiceBase, "custom voice")
        equal(listOf("af_heart"), s.aiConfig().voices.map { it.id }, "custom voice name")
    }

    fun customAddress() {
        equal("https://api.example.com/v1/", Providers.customBase("api.example.com/v1"), "https added")
        equal("http://127.0.0.1:1234/v1/", Providers.customBase("127.0.0.1:1234/v1"), "http on this device")
        equal(null, Providers.customBase("http://api.example.com/v1"), "http only on this device")
        equal(null, Providers.customBase(" "), "empty")
    }

    fun settingsRoundTrip() {
        try {
            AppSettings(aiProvider = "zenmux", aiHearModels = mutableMapOf("zenmux" to "bytedance/doubao-seed-2.0-mini")).save()
            val back = AppSettings.load()
            equal("zenmux", back.aiProvider, "service")
            equal("bytedance/doubao-seed-2.0-mini", back.aiConfig().hearModel, "hear model")
        } finally { Paths.settings.delete() }
    }

    fun shape() {
        for ((id, field, value) in listOf(Triple("ling", "thinking", mapOf("type" to "disabled")),
                                          Triple("zenmux", "reasoning", mapOf("enabled" to false)),
                                          Triple("openrouter", "reasoning", mapOf("enabled" to false)))) {
            val b = mutableMapOf<String, Any?>()
            AppSettings(aiProvider = id).aiConfig().shape(b, 100)
            equal(value, b[field], "$id turns thinking off")
            equal(100, b["max_tokens"], "max_tokens")
            equal(0.2, b["temperature"], "temperature")
        }
        val b = mutableMapOf<String, Any?>()
        AppSettings(aiProvider = "custom", aiCustomBase = "https://x.example/v1").aiConfig().shape(b, 5)
        check("reasoning" !in b && "thinking" !in b, "a custom service gets neither")
    }

    fun audioPart() {
        val wav = byteArrayOf(1, 2, 3)
        equal(mapOf("type" to "audio_url", "audio_url" to mapOf("url" to "data:audio/wav;base64,AQID")),
              AppSettings().aiConfig().audioPart(wav, "Ming-3.0-audio-flash"), "Ming: a data URL")
        val zen = AppSettings(aiProvider = "zenmux").aiConfig()
        equal(mapOf("type" to "input_audio", "input_audio" to mapOf("data" to "AQID", "format" to "wav")),
              zen.audioPart(wav, "google/gemini-3.1-flash-lite"), "input_audio")
        equal("data:audio/wav;base64,AQID", zen.audioPart(wav, "qwen/qwen3.8-omni-flash")["input_audio"].obj()!!["data"], "Qwen: a data URL inside")
    }

    fun catalog() {
        val data = Json.write(mapOf("data" to listOf(
            mapOf("id" to "qwen/qwen3.8-omni-flash", "input_modalities" to listOf("text", "image", "audio", "video"), "output_modalities" to listOf("text")),
            mapOf("id" to "x/asr-only", "input_modalities" to listOf("audio"), "output_modalities" to listOf("text")),
            mapOf("id" to "x/text-model", "architecture" to mapOf("input_modalities" to listOf("text"), "output_modalities" to listOf("text"))),
            mapOf("id" to "x/tts", "input_modalities" to listOf("text"), "output_modalities" to listOf("audio")),
            mapOf("id" to "x/embed-1"),
            mapOf("id" to "google/gemini-3.1-flash-lite:batch", "input_modalities" to listOf("audio", "text"), "output_modalities" to listOf("text")),
        )), pretty = false)
        equal(listOf("rec/one", "qwen/qwen3.8-omni-flash"), Providers.catalog(data, listOf("rec/one"), hears = true), "hear models")
        equal(listOf("qwen/qwen3.8-omni-flash", "x/text-model"), Providers.catalog(data, emptyList(), hears = false), "chat models")
    }

    fun oneKeyFilePerService() {
        val s = AppSettings()
        val k = AIKey(PlainProtector, service = { s.aiProvider })
        k.save("sk-ling-000000000")
        s.aiProvider = "zenmux"
        equal(null, k.read(), "ZenMux has its own")
        check(k.save("sk-zen-0000000000"), "saved")
        equal("ai-key-zenmux", k.path.name, "named as on the Mac")
        val mode = java.nio.file.Files.getPosixFilePermissions(k.path.toPath())
        equal("rw-------", java.nio.file.attribute.PosixFilePermissions.toString(mode), "0600")
        s.aiProvider = "ling"
        equal("sk-ling-000000000", k.read(), "Ling's kept")
        check(!Paths.settings.exists() || !Paths.settings.readText().contains("sk-"), "never in settings")
        k.remove(); s.aiProvider = "zenmux"; k.remove()
    }

    fun localNeedsNoKey() {
        val s = AppSettings(aiProvider = "custom", aiCustomBase = "localhost:11434/v1", aiModels = mutableMapOf("custom" to "qwen3:14b"))
        val ling = client(Fake({ _, _ -> reply("ok") }), s, key = null)
        equal("", ling.currentKey(), "no key needed")
        check(ling.hasKey, "counts as having one")
        s.aiCustomBase = "https://api.example.com/v1"
        check(!ling.hasKey, "a remote one needs a key")
    }

    fun requestShape() {
        val fake = Fake({ _, _ -> reply("LANG: en\nORIGINAL: Hi.\nTRANSLATION: 嗨。", finish = null) })
        val ling = client(fake, AppSettings(aiProvider = "zenmux"))
        // No finish reason: Ling's search essays come without one, other services may just omit it.
        val r = ling.chat("c", "i", Priority.Translate, model = "qwen/qwen3.8-omni-flash", audio = byteArrayOf(1))
        check(r.contains("ORIGINAL: Hi."), "accepted without a finish reason")
        equal("https://zenmux.ai/api/v1/chat/completions", fake.sent[0].first, "url")
        val b = body(fake.sent[0].second)
        equal(mapOf("enabled" to false), b["reasoning"], "reasoning off")
        check("thinking" !in b, "no Ling field")
        equal("input_audio", b["messages"].arr()[1].obj()!!["content"].arr()[0].obj()!!["type"], "input_audio")
        // Text calls use the service's text model.
        ling.chat("c", "i", Priority.Translate)
        equal("inclusionai/ling-3.0-flash", body(fake.sent[1].second)["model"], "text model")
    }

    fun lingDropsNoFinish() {
        val ling = client(Fake({ _, _ -> reply("fine", finish = null) }), AppSettings())
        try { ling.chat("c", "i", Priority.Translate); throw AssertionError("accepted") }
        catch (e: LingException) { equal(LingException.Kind.Hijacked, e.kind, "dropped") }
    }

    fun checkFindsDeafModel() {
        val s = AppSettings(aiProvider = "zenmux", aiHearModels = mutableMapOf("zenmux" to "x/text-only"))
        val ling = client(Fake({ url, b ->
            when {
                url.endsWith("models") -> Transport.Response(200, Json.write(mapOf("data" to listOf(
                    mapOf("id" to "a/b", "input_modalities" to listOf("text"), "output_modalities" to listOf("text")))), pretty = false))
                "input_audio" in b -> Transport.Response(400, "{}")
                else -> reply("OK")
            }
        }), s)
        equal(KeyState.Ok, ling.check(), "the key works")
        equal(false, ling.hears, "the hear model refuses audio")
        equal(AICheck.State.Fail(AICheck.Reason.Deaf, 400), ling.aiCheck[AICheck.StepID.Hear], "deaf at the hear step")
        check(AICheck.isOk(ling.aiCheck[AICheck.StepID.Text]), "the text model still answers")
        check(!ling.canHear, "can't hear")
        check(ling.usable, "notes and translation still work")
        s.aiHearModels.clear()
        ling.keyChanged()
        equal(null, ling.hears, "forgotten")
    }

    fun checkSaysWhy() {
        val bad = client(Fake({ _, _ -> Transport.Response(401, "") }), AppSettings(aiProvider = "zenmux"))
        equal(KeyState.Invalid, bad.check(), "401")
        equal("reach=ok key=fail(invalidKey) text=skipped hear=skipped", bad.aiCheck.summary, "stops at the key")
        val ling = client(Fake({ _, _ -> Transport.Response(404, "") }), AppSettings(aiProvider = "zenmux"))
        ling.check()
        equal(AICheck.Failure(AICheck.StepID.Text, AICheck.Reason.NoModel, 404), ling.aiCheck.failure, "404 is the text model")
        check(ling.checkMessage()!!.contains("inclusionai/ling-3.0-flash"), "names the model")
        equal(KeyState.None, client(Fake({ _, _ -> reply("ok") }), AppSettings(aiProvider = "openrouter"), key = null).keyState, "no key")
    }

    private fun sse(vararg lines: String) = Transport.Stream(200, "text/event-stream", ByteArrayInputStream(lines.joinToString("\n").toByteArray()))

    fun speech() {
        val b64 = Base64.getEncoder()
        val chunk = b64.encodeToString(byteArrayOf(1, 0, 2, 0))
        val fake = Fake({ _, _ -> reply("ok") }, { _, _ -> sse("data: {\"audio\": \"$chunk\"}", "data: {\"type\": \"speech.audio.done\"}") })
        var ling = client(fake, AppSettings(aiProvider = "zenmux"))
        val got = mutableListOf<List<Byte>>()
        ling.speech("Hello", voice = "Puck", language = "ja") { got.add(it.toList()) }
        equal(listOf(listOf<Byte>(1, 0, 2, 0)), got, "SSE base64 chunks")
        val b = body(fake.streamed[0].second)
        equal("https://zenmux.ai/api/v1/audio/speech", fake.streamed[0].first, "url")
        equal(Triple("google/gemini-3.8-flash-tts", "Puck", true), Triple(b["model"], b["voice"], b["stream"]), "body")
        check("language_id" !in b, "language_id is Ling's")
        // A voice that isn't this service's (a Ming name) becomes its first one.
        ling.speech("Hello", voice = "US_Emma") {}
        equal("Kore", body(fake.streamed[1].second)["voice"], "first voice")
        // OpenRouter streams the PCM bytes themselves, without `stream`.
        val raw = Fake({ _, _ -> reply("ok") }, { _, _ -> Transport.Stream(200, "audio/pcm", ByteArrayInputStream(byteArrayOf(5, 0, 6, 0))) })
        ling = client(raw, AppSettings(aiProvider = "openrouter"))
        val pcm = java.io.ByteArrayOutputStream()
        ling.speech("Hi") { pcm.write(it) }
        equal(listOf<Byte>(5, 0, 6, 0), pcm.toByteArray().toList(), "raw PCM")
        check("stream" !in body(raw.streamed[0].second), "no stream for OpenRouter")
        // One JSON with a WAV in it.
        val wav = Wav.bytes(shortArrayOf(7, 8), 24000)
        val one = Fake({ _, _ -> reply("ok") }, { _, _ ->
            Transport.Stream(200, "application/json", ByteArrayInputStream(Json.write(mapOf("audio" to b64.encodeToString(wav))).toByteArray())) })
        ling = client(one, AppSettings(aiProvider = "custom", aiCustomBase = "https://x.example/v1", aiVoiceModels = mutableMapOf("custom" to "kokoro"), aiCustomVoice = "af_heart"))
        val out = java.io.ByteArrayOutputStream()
        ling.speech("Hi", voice = "af_heart") { out.write(it) }
        equal(listOf<Byte>(7, 0, 8, 0), out.toByteArray().toList(), "a WAV in JSON")
        equal(listOf<Byte>(7, 0, 8, 0), LingClient.pcmFromWav(wav).toList(), "pcmFromWav")
    }

    fun noVoiceNoSpeech() {
        val ling = client(Fake({ _, _ -> reply("ok") }), AppSettings(aiProvider = "custom", aiCustomBase = "https://x.example/v1", aiModels = mutableMapOf("custom" to "m")))
        check(!ling.speaks, "no voice model")
        try { ling.speech("Hi") {}; throw AssertionError("spoke") } catch (_: LingException) {}
    }

    fun hearingUsesHearModel() {
        val fake = Fake({ _, _ -> reply("LANG: en\nORIGINAL: We ship on Friday.\nTRANSLATION: 我们周五发布。") })
        val ling = client(fake, AppSettings(aiProvider = "zenmux", aiHearModels = mutableMapOf("zenmux" to "bytedance/doubao-seed-2.0-mini")))
        val heard = Translator(ling).hear(Clip.wav(ShortArray(16000)), "zh-CN", null)
        equal("我们周五发布。", heard?.translation, "translated")
        equal("bytedance/doubao-seed-2.0-mini", body(fake.sent[0].second)["model"], "hear model")
        equal(20.0, Translator.hearTimeout(ling), "slower services get longer")
    }

    fun problemsNameTheService() {
        equal("key", ListenEngine.problem(LingException(LingException.Kind.Http, 400), "ZenMux").first, "a deaf model is a settings problem")
        check(ListenEngine.problem(LingException(LingException.Kind.Network), "ZenMux").second!!.contains("ZenMux"), "named")
        equal("network" to "连不上 Ling，检查网络", ListenEngine.problem(LingException(LingException.Kind.Timeout), "Ling"), "Ling's own words")
        equal(null, ListenEngine.problem(LingException(LingException.Kind.Http, 400), "Ling").first, "Ling's 400 is not the model")
    }

    fun finalNotesRetry() {
        check(LingClient.retryWaits(Priority.Translate).isEmpty(), "translation fails fast")
        equal(listOf(1.0), LingClient.retryWaits(Priority.Translate, audio = true), "heard audio retries once")
        equal(listOf(1.0, 2.0, 4.0), LingClient.retryWaits(Priority.Notes), "live notes as before")
        val sum = LingClient.retryWaits(Priority.Notes, patient = true).sum()
        check(sum in 50.0..70.0, "final notes wait about a minute ($sum s)")
    }

    fun clockIsNotSpeech() {
        for (madeUp in listOf("00:00", "00:00.", "1:02:03")) check(Translator.isNoise(madeUp, 1.2), "noise: $madeUp")
        for (said in listOf("Hello.", "3 点", "15%", "好的")) check(!Translator.isNoise(said, 1.2), "kept: $said")
    }
}
