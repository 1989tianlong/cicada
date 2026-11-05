package cicada

import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.util.Base64

/// Turns the key into bytes on disk and back. Android wraps it with a Keystore key (this app
/// only); the plain one is for the CLI and tests.
interface KeyProtector {
    val tag: String
    fun protect(data: ByteArray): ByteArray
    fun unprotect(data: ByteArray): ByteArray
}

object PlainProtector : KeyProtector {
    override val tag = "plain"
    override fun protect(data: ByteArray) = data
    override fun unprotect(data: ByteArray) = data
}

/// The user's AI keys, one file per service in the app's private folder (`ling-api-key`,
/// `ai-key-<service>`, as on the Mac): never in settings, logs or exports. `service` says which
/// one is in use; switching services keeps the others' keys. On Android each file holds
/// "keystore:" + base64 of the Keystore-sealed bytes. `file` pins one file (the CLI reads the Mac's).
class AIKey(private val protector: KeyProtector, private val file: File? = null, var service: () -> String = { "ling" }) {
    val path: File get() = file ?: Paths.keyFile(service())
    private val cache = HashMap<String, String?>()

    @Synchronized fun read(): String? {
        val p = path
        if (cache.containsKey(p.path)) return cache[p.path]
        val value = try {
            if (!p.isFile) null else {
                var text = p.readText().trim()
                if (text.startsWith("keystore:"))
                    text = String(protector.unprotect(Base64.getDecoder().decode(text.removePrefix("keystore:"))), Charsets.UTF_8)
                text.trim().ifEmpty { null }
            }
        } catch (e: Exception) {
            Log.d("ai key: read failed ${e.javaClass.simpleName}")
            null
        }
        cache[p.path] = value
        return value
    }

    @Synchronized fun save(key: String): Boolean {
        val k = key.trim()
        val p = path
        return try {
            p.parentFile?.mkdirs()
            val body = if (protector.tag == "plain") k else "keystore:" + Base64.getEncoder().encodeToString(protector.protect(k.toByteArray()))
            p.writeText(body)
            p.setReadable(false, false); p.setReadable(true, true)
            p.setWritable(false, false); p.setWritable(true, true)
            cache[p.path] = k
            true
        } catch (e: Exception) {
            Log.d("ai key: save failed ${e.javaClass.simpleName}")
            false
        }
    }

    @Synchronized fun remove() {
        val p = path
        p.delete()
        cache[p.path] = null
    }

    /// Reads the files again (a dev build's key pushed in with adb).
    @Synchronized fun reload() { cache.clear() }

    companion object {
        /// "sk-••••••••••••3f9a" for display.
        fun masked(key: String) = if (key.length <= 8) "sk-…" else key.take(3) + "•".repeat(12) + key.takeLast(4)
    }
}

enum class Priority { Speak, Translate, Notes }

enum class KeyState { None, Unchecked, Checking, Ok, Invalid, Unreachable }

class LingException(val kind: Kind, val status: Int = 0) : Exception(if (kind == Kind.Http) "http$status" else kind.name) {
    enum class Kind { NoKey, InvalidKey, RateLimited, Hijacked, Timeout, Http, Network, Parse }
}

/// How requests leave the app: HttpURLConnection, or a fake in tests.
interface Transport {
    class Response(val status: Int, val body: String)
    /// A reply read as it arrives (speech): its type and the open body, which the caller closes.
    class Stream(val status: Int, val contentType: String, val body: InputStream)
    /// Throws SocketTimeoutException on a timeout and IOException when the network fails.
    fun send(url: String, method: String, body: String?, headers: Map<String, String>, timeoutMs: Int): Response
    fun stream(url: String, body: String, headers: Map<String, String>, timeoutMs: Int): Stream =
        send(url, "POST", body, headers, timeoutMs).let { Stream(it.status, "application/json", it.body.byteInputStream()) }
}

object UrlTransport : Transport {
    override fun send(url: String, method: String, body: String?, headers: Map<String, String>, timeoutMs: Int): Transport.Response {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.requestMethod = method
            c.connectTimeout = minOf(timeoutMs, 10_000)
            c.readTimeout = timeoutMs
            headers.forEach { (k, v) -> c.setRequestProperty(k, v) }
            if (body != null) {
                c.doOutput = true
                c.outputStream.use { it.write(body.toByteArray()) }
            }
            val status = c.responseCode
            val stream = if (status in 200..299) c.inputStream else c.errorStream
            val text = stream?.use { it.readBytes().toString(Charsets.UTF_8) } ?: ""
            return Transport.Response(status, text)
        } finally { c.disconnect() }
    }

    override fun stream(url: String, body: String, headers: Map<String, String>, timeoutMs: Int): Transport.Stream {
        val c = URL(url).openConnection() as HttpURLConnection
        c.requestMethod = "POST"
        c.connectTimeout = minOf(timeoutMs, 10_000)
        c.readTimeout = timeoutMs
        headers.forEach { (k, v) -> c.setRequestProperty(k, v) }
        c.doOutput = true
        c.outputStream.use { it.write(body.toByteArray()) }
        val status = c.responseCode
        if (status !in 200..299) { c.errorStream?.close(); c.disconnect(); return Transport.Stream(status, "", ByteArray(0).inputStream()) }
        val input = c.inputStream
        return Transport.Stream(status, c.contentType ?: "", object : java.io.FilterInputStream(input) {
            override fun close() { try { super.close() } finally { c.disconnect() } }
        })
    }
}

/// One instance for the app, for whichever AI service the settings name (`config`, read on every
/// call). Request *starts* go through one gate in priority order: Ling allows about 2 a second
/// across every model (≥ 0.6 s apart, overlapping is fine), the aggregators far more. Ling's
/// gateway shapes every call (see Ling.swift): thinking is always disabled, and the content goes in
/// the system message with a fixed user instruction, because a question-like user message gets a
/// search essay back; such replies are dropped. The other services get the same messages.
/// Calls block: run them off the main thread.
class LingClient(
    private val key: AIKey,
    private val transport: Transport = UrlTransport,
    val config: () -> AIConfig = { Providers.configFrom(AppSettings()) },
) {
    companion object {
        val BASE = Providers.LING.base!!
        val DEFAULT_MODEL = Providers.LING.textModels[0].id
        val AUDIO_MODEL = Providers.LING.hearModels[0].id

        /// Seconds before each retry of a 429 (Ling.swift › retryWaits). Notes retry a few times, heard
        /// audio once; the rest fail fast so the caller can fall back. `patient` (the final notes) keeps
        /// at it for about a minute: a model limited upstream (OpenRouter's Ling 3.1 by DeepInfra,
        /// 2026-11) came back after ~15 s, and a meeting left without its notes is worse than notes a
        /// little late.
        fun retryWaits(priority: Priority, audio: Boolean = false, patient: Boolean = false): List<Double> = when {
            priority == Priority.Notes -> if (patient) listOf(1.0, 2.0, 4.0, 8.0, 16.0, 30.0) else listOf(1.0, 2.0, 4.0)
            audio -> listOf(1.0)
            else -> emptyList()
        }
        /// Ming, Gemini TTS and Kokoro all speak 24 kHz mono 16-bit.
        const val TTS_RATE = 24000
        /// Failures of a model rather than of the service or the key: the key still works.
        val MODEL_REASONS = setOf(AICheck.Reason.Busy, AICheck.Reason.Deaf, AICheck.Reason.NoModel, AICheck.Reason.NoJSON)
        // Search essays (Ling.swift), and the canned refusal some audio prompts get.
        private val HIJACK_PREFIXES = listOf("根据现有检索证据", "暂未找到足够可靠的信息", "根据检索", "作为一个人工智能语言模型")
        /// Tests only: overrides the service's spacing.
        @Volatile var spacing: Double? = null

        /// A short quiet WAV (16 kHz mono 16-bit), to ask a model whether it takes audio at all.
        fun silenceWav(seconds: Double = 0.5): ByteArray = Wav.bytes(ShortArray((16000 * seconds).toInt()))

        /// The samples of a WAV (its `data` chunk); the bytes themselves when there's no header.
        fun pcmFromWav(wav: ByteArray): ByteArray {
            if (wav.size < 12 || String(wav, 0, 4, Charsets.US_ASCII) != "RIFF") return wav
            var at = 12
            while (at + 8 <= wav.size) {
                val size = (wav[at + 4].toInt() and 0xff) or ((wav[at + 5].toInt() and 0xff) shl 8) or
                    ((wav[at + 6].toInt() and 0xff) shl 16) or ((wav[at + 7].toInt() and 0xff) shl 24)
                if (String(wav, at, 4, Charsets.US_ASCII) == "data") return wav.copyOfRange(at + 8, minOf(wav.size, at + 8 + size))
                at += 8 + size + (size and 1)
            }
            return ByteArray(0)
        }
    }

    @Volatile var keyState = if (currentKey() == null) KeyState.None else KeyState.Unchecked; private set
    @Volatile var rateLimitedAt: Long? = null; private set
    /// Step by step, where the service stands (`keyState` is its short form for older callers).
    @Volatile var aiCheck = AICheck(); private set
    /// The last time the service's voice spoke (or failed to) for 我说: (ok, epoch ms).
    @Volatile var lastVoice: Pair<Boolean, Long>? = null; private set
    @Volatile var textCatalog: List<String> = emptyList(); private set
    @Volatile var hearCatalog: List<String> = emptyList(); private set
    /// Reads this phone's proxy settings to word the "can't reach" hint (never used to connect).
    @Volatile var proxyHint: (() -> AICheck.ProxyHint)? = null
    /// Debug control only: the next checks end this way (for screenshots of every state).
    @Volatile var simulateCheck: AICheck.Reason? = null
    /// Debug control only: report this OpenRouter balance instead of the real one.
    @Volatile var simulateBalance: Double? = null
    private val checkLock = Any()
    private val listeners = mutableListOf<() -> Unit>()

    fun onChange(listener: () -> Unit) { synchronized(listeners) { listeners.add(listener) } }
    private fun changed() { synchronized(listeners) { listeners.toList() }.forEach { it() } }

    val provider: Provider get() = config().provider

    /// The key for the service in use. A custom service on this phone may need none: "".
    fun currentKey(): String? {
        val c = config()
        val k = key.read()
        if (k == null && c.provider.id == "custom" && c.base != null && Providers.isLocal(c.base)) return ""
        return k
    }

    val hasKey get() = currentKey() != null
    val usable get() = hasKey && keyState != KeyState.Invalid
    /// The service's own voice reads my words to the other side (otherwise the phone's voice).
    val speaks get() = usable && config().hasVoices
    /// Whether the hear model takes audio: false once it refused (a check or a meeting), true once
    /// it heard, null until then (always true on Ling: Ming).
    val hears: Boolean? get() = when (val s = aiCheck[AICheck.StepID.Hear]) {
        is AICheck.State.Ok, AICheck.State.Busy -> true
        is AICheck.State.Fail -> if (s.reason == AICheck.Reason.Deaf) false else null
        else -> if (config().isLing) true else null
    }
    /// How long the last good check's newest request took, in seconds.
    val seconds: Double? get() = aiCheck.steps.mapNotNull { (it.state as? AICheck.State.Ok)?.seconds }.lastOrNull()
    /// Listening and 我说 can work: the hear model wasn't found to refuse audio.
    val canHear get() = usable && hears != false && config().hearModel.isNotEmpty()

    /// The service's name for messages ("这个服务" for a custom address, localized) and its host.
    val serviceName: String get() = provider.let { if (it.id == "custom") Strings.L("这个服务") else it.name }
    val serviceHost: String get() = (config().base ?: provider.base)?.let { try { java.net.URI(it).host } catch (_: Exception) { null } } ?: ""

    /// The failed (or busy) step's sentence, for the screens.
    fun checkMessage(): String? = config().let { aiCheck.message(serviceName, serviceHost, it.textModel, it.hearModel) }

    /// The key, the service or its models changed: forget what the last check found.
    fun keyChanged() {
        key.reload()
        keyState = if (currentKey() == null) KeyState.None else KeyState.Unchecked
        synchronized(checkLock) { aiCheck = AICheck() }
        lastVoice = null
        textCatalog = emptyList(); hearCatalog = emptyList()
        changed()
    }

    /// The cheapest requests that prove each step: Ling's tiny model, else one token from the text
    /// model (OpenRouter also reads its key info and credits, for the balance). A custom service
    /// must also return JSON (the notes need it). Another service's hear model must take audio
    /// (half a second of silence), and the model list then tells whether both models still exist.
    fun check(): KeyState {
        // One at a time (a service change and a key import come close together), and the probes'
        // own replies are not passive results.
        synchronized(checkRun) {
            checking++
            try { return runCheck() } finally { checking-- }
        }
    }

    private val checkRun = Any()
    @Volatile private var checking = 0

    private fun runCheck(): KeyState {
        val c = config()
        val k = currentKey()
        if (k == null) { keyState = KeyState.None; synchronized(checkLock) { aiCheck = AICheck() }; changed(); return keyState }
        keyState = KeyState.Checking
        var r = AICheck().with(AICheck.StepID.Reach, AICheck.State.Running)
        synchronized(checkLock) { aiCheck = r }
        changed()
        simulateCheck?.let { return finishCheck(AICheck.simulated(it), c) }
        if (c.provider.id == "custom" && c.base == null)
            return finishCheck(r.fail(AICheck.StepID.Reach, AICheck.Reason.BadAddress, reached = false), c)
        if (AICheck.owner(k)?.second == true)
            return finishCheck(r.fail(AICheck.StepID.Key, AICheck.Reason.MgmtKey, reached = false), c)
        // The probes below go through chat(), which reports to observe(): it waits while running.
        var step = AICheck.StepID.Text
        try {
            var started = System.nanoTime()
            if (c.isLing) {
                chat("Reply with OK.", "Reply.", Priority.Speak, maxTokens = 5, timeout = 10.0, model = "Ling-3.0-tiny")
                // Ming hears on every Ling key: nothing to probe.
                r = r.pass(AICheck.StepID.Text, (System.nanoTime() - started) / 1e9).pass(AICheck.StepID.Hear, null)
            } else {
                if (c.textModel.isEmpty()) throw LingException(LingException.Kind.Http, 404)
                chat("Reply with OK.", "Reply.", Priority.Speak, maxTokens = 5, timeout = 20.0)
                r = r.pass(AICheck.StepID.Text, (System.nanoTime() - started) / 1e9)
                if (c.provider.id == "openrouter") r = r.copy(balance = openRouterBalance(c, k))
                if (c.provider.id == "custom") {
                    try {
                        chat("Reply with the JSON object {\"ok\": true}.", "Reply.", Priority.Speak, json = true, maxTokens = 20, timeout = 20.0)
                    } catch (e: LingException) {
                        if (e.kind == LingException.Kind.Http) r = r.fail(AICheck.StepID.Text, AICheck.Reason.NoJSON, e.status) else throw e
                    }
                }
                if (r.failure == null) {
                    step = AICheck.StepID.Hear
                    started = System.nanoTime()
                    if (c.hearModel.isEmpty()) throw LingException(LingException.Kind.Http, 404)
                    try {
                        chat("Transcribe the audio.", "Reply with what is said, or NONE.", Priority.Speak, maxTokens = 10, timeout = 20.0,
                             model = c.hearModel, audio = silenceWav())
                    } catch (e: LingException) {
                        // Heard, and answered with something we drop anyway: it takes audio.
                        if (e.kind != LingException.Kind.Hijacked && e.kind != LingException.Kind.Parse) throw e
                    }
                    r = r.pass(AICheck.StepID.Hear, (System.nanoTime() - started) / 1e9)
                }
            }
        } catch (e: LingException) {
            val f = AICheck.classify(e, step)
            if (f != null) {
                r = if (f.reason == AICheck.Reason.Busy) r.pass(f.step, null).with(f.step, AICheck.State.Busy) else r.fail(f.step, f.reason, f.code)
            } else if (e.kind == LingException.Kind.Hijacked || e.kind == LingException.Kind.Parse) {
                // A reply came back: the service and key are fine, the words just weren't usable.
                r = r.pass(step, null)
            }
        } catch (e: InterruptedException) {
            throw e
        } catch (e: Exception) {
            r = r.fail(AICheck.StepID.Reach, AICheck.Reason.Unreachable)
        }
        if (r.failure == null && !c.isLing) {
            val listed = fetchCatalog()
            if (listed != null) {
                // A model the service no longer lists fails here, before a meeting finds out.
                val hearing = listed.second
                if (c.textModel !in listed.first) r = r.fail(AICheck.StepID.Text, AICheck.Reason.NoModel)
                else if (hearing != null && c.hearModel !in hearing) r = r.fail(AICheck.StepID.Hear, AICheck.Reason.Deaf)
            }
        }
        return finishCheck(r, c)
    }

    private fun finishCheck(result: AICheck, c: AIConfig): KeyState {
        var r = result
        if (r.failure?.reason == AICheck.Reason.Unreachable && r.proxy == null) r = r.copy(proxy = proxyHint?.invoke())
        simulateBalance?.let { r = r.copy(balance = it) }
        r = r.copy(at = System.currentTimeMillis())
        synchronized(checkLock) { aiCheck = r }
        syncKeyState()
        Log.d("ai ${c.provider.id}: check -> ${r.summary}")
        changed()
        return keyState
    }

    /// OpenRouter's dollars left; null when it can't tell (never fails the check).
    private fun openRouterBalance(c: AIConfig, k: String): Double? {
        val base = c.base ?: return null
        fun get(path: String) = try {
            transport.send(base + path, "GET", null, headers(k), 10_000).takeIf { it.status == 200 }?.let { Json.parseObject(it.body) }
        } catch (_: Exception) { null }
        return AICheck.balance(get("key"), get("credits"))
    }

    /// The short form older callers read: Invalid stops every request; Unreachable is any failure
    /// of the service itself. A missing or deaf model is a model problem: the key still works.
    private fun syncKeyState() {
        if (!hasKey) { keyState = KeyState.None; return }
        val c = aiCheck
        val f = c.failure
        keyState = when {
            f != null && (f.reason == AICheck.Reason.InvalidKey || f.reason == AICheck.Reason.MgmtKey) -> KeyState.Invalid
            f != null && f.reason !in MODEL_REASONS -> KeyState.Unreachable
            c.running -> KeyState.Checking
            else -> KeyState.Ok
        }
    }

    /// A real request (hearing, notes, translation) came back: keep the steps current without a
    /// check. One server error in a meeting isn't worth repainting the settings for.
    private fun observe(failure: LingException?, seconds: Double = 0.0, audio: Boolean = false) {
        if (!hasKey || simulateCheck != null) return
        val step = if (audio) AICheck.StepID.Hear else AICheck.StepID.Text
        val now: AICheck
        val wasUnreachable: Boolean
        synchronized(checkLock) {
            val before = aiCheck
            if (before.running || checking > 0) return
            var r = before
            if (failure != null) {
                val f = AICheck.classify(failure, step) ?: return
                if (f.reason == AICheck.Reason.ServerError) return
                r = if (f.reason == AICheck.Reason.Busy) r.pass(AICheck.StepID.Key, null).with(f.step, AICheck.State.Busy) else r.fail(f.step, f.reason, f.code)
            } else {
                r = r.pass(step, seconds)
            }
            r = r.copy(at = System.currentTimeMillis(), passive = true)
            if (r.failure?.reason != AICheck.Reason.Unreachable) r = r.copy(proxy = null)
            wasUnreachable = before.failure?.reason == AICheck.Reason.Unreachable
            if (r.steps == before.steps && before.passive) { aiCheck = before.copy(at = r.at); return }
            aiCheck = r
            now = r
        }
        syncKeyState()
        Log.d("ai: from a real request -> ${now.summary}")
        changed()
        val hint = proxyHint
        if (now.failure?.reason == AICheck.Reason.Unreachable && !wasUnreachable && hint != null) {
            val p = hint()
            synchronized(checkLock) { if (aiCheck.failure?.reason == AICheck.Reason.Unreachable) aiCheck = aiCheck.copy(proxy = p) }
            changed()
        }
    }

    /// The network came back (or changed) while the service was unreachable: look again. Blocks.
    fun networkChanged() {
        if (!hasKey || aiCheck.failure?.reason != AICheck.Reason.Unreachable || aiCheck.running) return
        Log.d("ai: network changed while unreachable, checking again")
        check()
    }

    /// The service's models, for the model pickers: those that chat, and those that hear. Quietly
    /// just the recommended ones when the service has no `/models`. Returns every listed id and,
    /// when the reply says which take audio, those (to tell whether the chosen models exist).
    fun fetchCatalog(): Pair<Set<String>, Set<String>?>? {
        val c = config()
        val k = currentKey() ?: return null
        if (c.isLing || c.base == null) return null
        val res = try { transport.send(c.base + "models", "GET", null, headers(k), 20_000) } catch (_: Exception) { return null }
        if (res.status != 200) return null
        textCatalog = Providers.catalog(res.body, c.provider.textModels.map { it.id }, hears = false)
        hearCatalog = Providers.catalog(res.body, c.provider.hearModels.map { it.id }, hears = true)
        Log.d("ai ${c.provider.id}: ${textCatalog.size} models, ${hearCatalog.size} hear")
        changed()
        val listed = AICheck.listedModels(res.body) ?: return null
        return listed to AICheck.listedHearing(res.body)
    }

    /// One chat completion. `content` goes in the system message, `instruction` is the fixed user
    /// message, `audio` (of `audioType`) goes before it for the hear model. Notes retry 429s with
    /// backoff; heard audio gets one retry (a lost reply loses the words); the rest fail fast so
    /// the caller can fall back. `patient` (the final notes) keeps retrying for about a minute (retryWaits).
    fun chat(
        content: String, instruction: String, priority: Priority, json: Boolean = false,
        maxTokens: Int = 1024, timeout: Double = 30.0, model: String? = null, audio: ByteArray? = null,
        audioType: String = "audio/wav", patient: Boolean = false,
    ): String {
        val k = currentKey() ?: throw LingException(LingException.Kind.NoKey)
        if (keyState == KeyState.Invalid) throw LingException(LingException.Kind.InvalidKey)
        val c = config()
        val base = c.base ?: throw LingException(LingException.Kind.NoKey)
        val m = model ?: c.textModel
        val user: Any = if (audio == null) instruction else listOf(c.audioPart(audio, m, audioType), mapOf("type" to "text", "text" to instruction))
        val body = linkedMapOf<String, Any?>(
            "model" to m,
            "messages" to listOf(mapOf("role" to "system", "content" to content), mapOf("role" to "user", "content" to user)),
            "stream" to false,
        )
        c.shape(body, maxTokens)
        if (json) body["response_format"] = mapOf("type" to "json_object")
        val payload = Json.write(body, pretty = false)

        val waits = retryWaits(priority, audio != null, patient)
        var attempt = 1
        while (true) {
            acquire(priority, c.provider.spacing)
            val started = System.nanoTime()
            try {
                val root = post(base + "chat/completions", payload, k, timeout)
                val choice = root["choices"].arr().firstOrNull().obj()
                val text = choice?.get("message").obj()?.get("content").str() ?: throw LingException(LingException.Kind.Parse)
                val finish = choice?.get("finish_reason").str()
                val trimmed = text.trim()
                // Ling's search essays come without a finish reason; other services may simply omit it.
                if ((finish == null && c.isLing) || HIJACK_PREFIXES.any { trimmed.startsWith(it) }) {
                    Log.d("ling: $priority search-style reply dropped")
                    throw LingException(LingException.Kind.Hijacked)
                }
                val usage = root["usage"].obj()
                Log.d("ai ${c.provider.id}: $priority ok ${(System.nanoTime() - started) / 1_000_000} ms tokens=${usage?.get("prompt_tokens")}/${usage?.get("completion_tokens")}")
                if (rateLimitedAt != null) { rateLimitedAt = null; changed() }
                observe(null, (System.nanoTime() - started) / 1e9, audio = audio != null)
                return trimmed
            } catch (e: LingException) {
                // A reply we drop (a search essay) still proves the service answers.
                observe(e.takeIf { it.kind != LingException.Kind.Hijacked }, audio = audio != null)
                if (e.kind != LingException.Kind.RateLimited) throw e
                if (attempt > waits.size) { rateLimitedAt = System.currentTimeMillis(); changed(); throw e }
                val wait = waits[attempt - 1] + Math.random() * 0.5
                Log.d("ling: $priority 429, retry in ${"%.1f".format(wait)} s")
                Thread.sleep((wait * 1000).toLong())
                attempt++
            }
        }
    }

    /// The service's voice for `text`, handed to `onPcm` as raw 24 kHz mono 16-bit PCM while it
    /// arrives. `voice` is one of the service's (another, e.g. a Ming name, becomes its first);
    /// `language` is Ming's language_id, Ling only. Replies come three ways and all are read:
    /// server-sent base64 chunks (Ling, ZenMux), raw PCM (OpenRouter), or one JSON `{"audio": <WAV>}`.
    fun speech(text: String, voice: String? = null, language: String? = null, timeout: Double = 20.0, onPcm: (ByteArray) -> Unit) {
        // The voice isn't part of a check (it costs money): its real outcome is what 现在能用的 says.
        try {
            speak(text, voice, language, timeout, onPcm)
            lastVoice = true to System.currentTimeMillis(); changed()
        } catch (e: LingException) {
            lastVoice = false to System.currentTimeMillis(); changed()
            throw e
        }
        // Anything else came from onPcm: the phone stopped it on purpose, not a failure.
    }

    private fun speak(text: String, voice: String?, language: String?, timeout: Double, onPcm: (ByteArray) -> Unit) {
        val k = currentKey() ?: throw LingException(LingException.Kind.NoKey)
        val c = config()
        val voiceBase = c.voiceBase
        if (!c.hasVoices || voiceBase == null) throw LingException(LingException.Kind.NoKey)
        val body = linkedMapOf<String, Any?>("model" to c.voiceModel, "input" to text, "response_format" to "pcm")
        if (c.isLing) {
            body.putAll(mapOf("sample_rate" to TTS_RATE, "stream" to true, "stream_format" to "sse", "voice" to (voice ?: "UK_Charlotte")))
            if (language != null) body["language_id"] = language
        } else {
            // OpenRouter documents no `stream` (it streams the bytes anyway); ZenMux needs it.
            if (c.provider.id != "openrouter") body["stream"] = true
            val ids = c.voices.map { it.id }
            body["voice"] = if (voice in ids) voice else ids.firstOrNull() ?: c.customVoice ?: "Kore"
        }
        acquire(Priority.Speak, c.provider.spacing)
        val started = System.nanoTime()
        val res = try {
            transport.stream(voiceBase + "audio/speech", Json.write(body, pretty = false), headers(k), (timeout * 1000).toInt())
        } catch (_: SocketTimeoutException) {
            throw LingException(LingException.Kind.Timeout)
        } catch (_: java.io.IOException) {
            throw LingException(LingException.Kind.Network)
        }
        res.body.use { input ->
            when (res.status) {
                200 -> {}
                401, 403 -> { keyState = KeyState.Invalid; changed(); throw LingException(LingException.Kind.InvalidKey) }
                429 -> throw LingException(LingException.Kind.RateLimited)
                else -> { Log.d("ai ${c.provider.id}: speech HTTP ${res.status}"); throw LingException(LingException.Kind.Http, res.status) }
            }
            var bytes = 0L
            try {
                when {
                    "event-stream" in res.contentType -> {
                        for (line in input.bufferedReader().lineSequence()) {
                            if (!line.startsWith("data:")) continue
                            val o = Json.parseObject(line.substring(5).trim()) ?: continue
                            if (o["type"] == "speech.audio.done") break
                            val audio = o["audio"].str()
                            if (!audio.isNullOrEmpty()) { val pcm = Base64.getDecoder().decode(audio); bytes += pcm.size; onPcm(pcm) }
                        }
                    }
                    "json" in res.contentType -> {
                        val o = Json.parseObject(input.readBytes().toString(Charsets.UTF_8))
                        val audio = o?.get("audio").str() ?: throw LingException(LingException.Kind.Parse)
                        val pcm = pcmFromWav(Base64.getDecoder().decode(audio)); bytes += pcm.size; onPcm(pcm)
                    }
                    else -> {
                        val buf = ByteArray(4800) // 0.1 s at 24 kHz: playback starts early
                        var odd: Byte? = null
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            if (n == 0) continue
                            // Whole samples only: a chunk can end mid-sample.
                            var chunk = if (odd != null) byteArrayOf(odd) + buf.copyOf(n) else buf.copyOf(n)
                            odd = if (chunk.size % 2 == 1) chunk.last() else null
                            if (odd != null) chunk = chunk.copyOf(chunk.size - 1)
                            if (chunk.isNotEmpty()) { bytes += chunk.size; onPcm(chunk) }
                        }
                    }
                }
            } catch (_: SocketTimeoutException) {
                throw LingException(LingException.Kind.Timeout)
            } catch (e: java.io.IOException) {
                throw LingException(LingException.Kind.Network)
            }
            Log.d("ai ${c.provider.id}: speech ${"%.1f".format(bytes / (TTS_RATE * 2.0))} s in ${(System.nanoTime() - started) / 1_000_000} ms")
        }
    }

    private fun headers(k: String): Map<String, String> {
        val h = linkedMapOf("Content-Type" to "application/json", "User-Agent" to "Cicada-Android/0.1")
        if (k.isNotEmpty()) h["Authorization"] = "Bearer $k"
        return h
    }

    private fun post(url: String, payload: String, k: String, timeout: Double): Map<String, Any?> {
        val res = try {
            transport.send(url, "POST", payload, headers(k), (timeout * 1000).toInt())
        } catch (_: SocketTimeoutException) {
            throw LingException(LingException.Kind.Timeout)
        } catch (e: java.io.IOException) {
            Log.d("ling: network error ${e.javaClass.simpleName}")
            throw LingException(LingException.Kind.Network)
        }
        when (res.status) {
            200 -> {}
            401, 403 -> {
                if (keyState != KeyState.Invalid) { keyState = KeyState.Invalid; changed() }
                throw LingException(LingException.Kind.InvalidKey)
            }
            429 -> throw LingException(LingException.Kind.RateLimited)
            else -> {
                Log.d("ling: HTTP ${res.status}")
                throw LingException(LingException.Kind.Http, res.status)
            }
        }
        return try { Json.parse(res.body).obj() } catch (_: Json.ParseException) { null } ?: throw LingException(LingException.Kind.Parse)
    }

    // Start gate: request starts ≥ `spacing` apart, the most urgent waiting one first.

    private class Ticket(val priority: Priority, val seq: Long)
    private val gate = Object()
    private val waiting = mutableListOf<Ticket>()
    private var lastStart = 0L
    private var seq = 0L

    private fun acquire(priority: Priority, serviceSpacing: Double) {
        val spacing = LingClient.spacing ?: serviceSpacing
        synchronized(gate) {
            val me = Ticket(priority, ++seq)
            waiting.add(me)
            try {
                while (true) {
                    val head = waiting.minWith(compareBy<Ticket>({ it.priority.ordinal }, { it.seq }))
                    val wait = (spacing * 1000).toLong() - (System.currentTimeMillis() - lastStart)
                    if (head === me && wait <= 0) {
                        waiting.remove(me)
                        lastStart = System.currentTimeMillis()
                        gate.notifyAll()
                        return
                    }
                    gate.wait(if (head === me) wait else 0)
                }
            } catch (e: InterruptedException) {
                waiting.remove(me); gate.notifyAll(); throw e
            }
        }
    }
}
