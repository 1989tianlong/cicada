package com.wquguru.cicada

import android.app.Application
import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import cicada.AIKey
import cicada.AppSettings
import cicada.AudioSource
import cicada.LingClient
import cicada.ListenEngine
import cicada.Log
import cicada.NotesEngine
import cicada.Paths
import cicada.PcmAudioSource
import cicada.SessionStore
import cicada.Strings
import cicada.Translator
import cicada.Wav
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors

/// The process: wires the engines together (AppModel on the Mac, Controller on Windows) and tells
/// the screens when something changed. Engine events arrive on worker threads; `observe`
/// callbacks run on the main thread, coalesced to one per frame.
class CicadaApp : Application() {
    lateinit var settings: AppSettings
    lateinit var key: AIKey
    lateinit var ling: LingClient
    lateinit var store: SessionStore
    lateinit var notes: NotesEngine
    lateinit var translator: Translator
    lateinit var listen: ListenEngine
    lateinit var overlay: Overlay
    val main = Handler(Looper.getMainLooper())
    val background = Executors.newCachedThreadPool { r -> Thread(r, "App").apply { isDaemon = true } }
    private val observers = LinkedHashSet<() -> Unit>()
    private var refreshQueued = false
    private var tileListening = false
    private var samplePlayer: MediaPlayer? = null
    /// Why the last listening couldn't start or ended early, shown on the main screen.
    @Volatile var startProblem: String? = null
    /// Cicada's own screens in front: the floating window is for other apps, so it waits.
    private var resumed = 0
    /// Android silenced our recording: a phone call, or another app holding the microphone.
    @Volatile var micSilenced = false
    /// The user closed the floating window (×) for this meeting.
    var overlayClosed = false
    /// 在视频上看 asked for it in this meeting, whatever 悬浮窗 is set to.
    var overlayThisMeeting = false

    override fun onCreate() {
        super.onCreate()
        shared = this
        Paths.root = filesDir
        Paths.log = File(cacheDir, if (BuildConfig.DEBUG) "cicada-dev-debug.log" else "cicada-debug.log")
        if (BuildConfig.DEBUG) Log.sink = { android.util.Log.d("Cicada", it) }
        settings = AppSettings.load()
        loadStrings()
        key = AIKey(KeystoreProtector)
        ling = LingClient(key).apply { model = settings.model }
        store = SessionStore(loadNow = false)
        background.execute { val t = System.currentTimeMillis(); store.load(); Log.d("store: loaded ${store.all().size} in ${System.currentTimeMillis() - t} ms") }
        notes = NotesEngine(ling, store)
        translator = Translator(ling)
        listen = ListenEngine(ling, translator, store, notes, settings)
        overlay = Overlay(this)
        listen.onChange(::changed)
        notes.onChange(::changed)
        store.onChange { changed() }
        ling.onChange(::changed)
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            // Meetings are private: the recent-apps preview shows a blank card, not the transcript
            // (Android 13+). Screenshots of the app itself still work.
            override fun onActivityPreCreated(a: android.app.Activity, b: android.os.Bundle?) {
                if (Build.VERSION.SDK_INT >= 33 && a !is ProjectionActivity) a.setRecentsScreenshotEnabled(false)
            }
            override fun onActivityResumed(a: android.app.Activity) { resumed++; updateOverlay() }
            // Moving between Cicada's own screens pauses one before resuming the next: wait a beat.
            override fun onActivityPaused(a: android.app.Activity) { resumed--; main.postDelayed(::updateOverlay, 400) }
            override fun onActivityCreated(a: android.app.Activity, b: android.os.Bundle?) {}
            override fun onActivityStarted(a: android.app.Activity) {}
            override fun onActivityStopped(a: android.app.Activity) {}
            override fun onActivitySaveInstanceState(a: android.app.Activity, b: android.os.Bundle) {}
            override fun onActivityDestroyed(a: android.app.Activity) {}
        })
        Log.d("app: launch ${if (BuildConfig.DEBUG) "dev" else "release"} sdk=${Build.VERSION.SDK_INT}")
        if (ling.hasKey) background.execute { ling.check() }
    }

    fun loadStrings() {
        val ui = if (settings.uiLanguage == "system") Locale.getDefault().toLanguageTag() else settings.uiLanguage
        Strings.load(ui) { rel -> try { assets.open("Resources/$rel").use { it.readBytes().toString(Charsets.UTF_8) } } catch (_: Exception) { null } }
    }

    // MARK: Changes

    fun observe(observer: () -> Unit): () -> Unit {
        observers.add(observer)
        return { observers.remove(observer) }
    }

    fun changed() {
        main.post {
            if (refreshQueued) return@post
            refreshQueued = true
            main.postDelayed({
                refreshQueued = false
                updateOverlay()
                overlay.refresh()
                if (listen.listening != tileListening) { tileListening = listen.listening; ListenTile.refresh(this) }
                ListenService.refresh(this)
                observers.toList().forEach { it() }
            }, 16)
        }
    }

    // MARK: Listening

    val canOverlay get() = Settings.canDrawOverlays(this)

    /// Playback capture needs the projection consent first: ProjectionActivity asks, then hands
    /// the result to ListenService. The microphone and files start straight away.
    /// Between 开始听 and the service starting (permissions, the consent dialog): further taps wait.
    @Volatile var starting = 0L

    fun startListening(context: Context, kind: String) {
        startIntent(context, kind)?.let { context.startActivity(it) }
    }

    /// What starting takes: the permissions and consent screen, or onboarding without a key. Null
    /// while already listening or starting (a second tap). The Quick Settings tile opens it itself.
    fun startIntent(context: Context, kind: String): Intent? {
        if (listen.listening) return null
        if (System.currentTimeMillis() - starting < 60_000) return null
        startProblem = null
        if (!ling.hasKey) return Intent(context, OnboardingActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        starting = System.currentTimeMillis()
        return Intent(context, ProjectionActivity::class.java).putExtra("kind", kind).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    /// Called by ListenService once it is in the foreground, with the source it made.
    fun began(source: AudioSource, kind: String) {
        starting = 0
        micSilenced = false
        (source as? RecordSource)?.onSilenced = { silenced -> if (silenced != micSilenced) { micSilenced = silenced; changed() } }
        source.onEnded = { reason ->
            if (reason != null) {
                Log.d("listen: source ended $reason")
                startProblem = Strings.L("声音来源停了")
                stopListening()
            }
        }
        overlayClosed = false
        overlayThisMeeting = false
        overlay.collapsed = false
        listen.start(source, kind)
        openLive()
    }

    /// The 正在听 screen, brought to the front.
    fun openLive() {
        startActivity(Intent(this, ListeningActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
    }

    fun stopListening(then: (() -> Unit)? = null) {
        background.execute {
            listen.stop()
            main.post {
                starting = 0
                micSilenced = false
                stopService(Intent(this, ListenService::class.java))
                samplePlayer?.release(); samplePlayer = null
                changed()
                then?.invoke()
            }
        }
    }

    /// A WAV (16 kHz or any PCM16) heard as if it were playing: the sample meeting and `feed`.
    fun listenToFile(file: File?, play: Boolean, showLive: Boolean = !play) {
        if (listen.listening) return
        if (!ling.hasKey) { startProblem = Strings.L("需要 Ling key 才能听"); changed(); return }
        val source = if (file != null) PcmAudioSource(file) else PcmAudioSource({ assets.open("sample.wav").use { Wav.read(it) } })
        source.onEnded = { reason ->
            // A file that finished: give the last segment's reply a moment, then end the meeting.
            main.postDelayed({ if (listen.listening && listen.sourceKind == "file") stopListening() }, if (reason == null) 3000 else 0)
        }
        overlayClosed = false
        overlayThisMeeting = false
        overlay.collapsed = false
        listen.start(source, "file")
        if (showLive) openLive()
        if (play) {
            try {
                val fd = assets.openFd("sample.wav")
                samplePlayer = MediaPlayer().apply {
                    setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                    prepare(); start()
                }
            } catch (e: Exception) { Log.d("sample: play failed ${e.javaClass.simpleName}") }
        }
        changed()
    }

    /// The floating window shows while listening with another app in front (unless turned off
    /// or closed), and goes when listening ends: inside Cicada the screens show the same.
    fun updateOverlay() {
        val want = listen.listening && (settings.overlay || overlayThisMeeting) && canOverlay && resumed == 0 && !overlayClosed
        if (want) overlay.show() else if (!overlay.forced) overlay.hide()
    }

    fun setView(view: String) {
        settings.view = view; settings.save()
        overlay.rebuild()
        changed()
    }

    fun saveSettings() { settings.save(); ling.model = settings.model; changed() }

    /// The system language, or this app's own in Settings › App languages (Android 13+), changed:
    /// the screens are recreated, and they read the new table.
    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        if (settings.uiLanguage == "system") { loadStrings(); changed() }
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        store.flush()
    }

    companion object {
        lateinit var shared: CicadaApp
    }
}

val Context.cicada: CicadaApp get() = applicationContext as CicadaApp
