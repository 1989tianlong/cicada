"""The AI service (Ling by default, or another OpenAI-compatible one: providers.py) and the user's keys."""
from __future__ import annotations

import io
import os
import random
import socket
import threading
import time
import urllib.error
import urllib.request
import wave

from . import jsonfmt
from .jsonfmt import arr, obj, string
from .providers import LING, AIConfig, catalog, is_local
from .support import Log, Paths


class AIKey:
    """The user's AI keys, one file per service (`ling-api-key`, `ai-key-<service>`), mode 0600, in
    ~/.config/cicada (as on the Mac): never in settings, logs or exports. `service` says which one
    is in use; `path` pins one file (cli.py reads the Mac's)."""

    def __init__(self, path: str | None = None, service=None):
        self._path = path
        self.service = service or (lambda: "ling")
        self._cache: dict = {}
        self._lock = threading.Lock()

    @property
    def path(self) -> str:
        return self._path or Paths.key_file(self.service())

    def read(self) -> str | None:
        path = self.path
        with self._lock:
            if path in self._cache:
                return self._cache[path]
            value = None
            try:
                if os.path.isfile(path):
                    with open(path, encoding="utf-8") as f:
                        value = f.read().strip() or None
            except OSError as e:
                Log.d("ai key: read failed %s" % type(e).__name__)
            self._cache[path] = value
            return value

    def save(self, key: str) -> bool:
        k = key.strip()
        path = self.path
        with self._lock:
            try:
                os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
                # Created 0600 from the start: the key is never readable by others, even briefly.
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    f.write(k)
                os.chmod(path, 0o600)
                self._cache[path] = k
                return True
            except OSError as e:
                Log.d("ai key: save failed %s" % type(e).__name__)
                return False

    def remove(self) -> None:
        path = self.path
        with self._lock:
            try:
                os.remove(path)
            except OSError:
                pass
            self._cache[path] = None

    def reload(self) -> None:
        with self._lock:
            self._cache.clear()

    @staticmethod
    def masked(key: str) -> str:
        """"sk-••••••••••••3f9a" for display."""
        return "sk-…" if len(key) <= 8 else key[:3] + "•" * 12 + key[-4:]


# Priorities, most urgent first.
SPEAK, TRANSLATE, NOTES = 0, 1, 2
PRIORITY_NAMES = {SPEAK: "speak", TRANSLATE: "translate", NOTES: "notes"}

# Key states.
NONE, UNCHECKED, CHECKING, OK, INVALID, UNREACHABLE = "none", "unchecked", "checking", "ok", "invalid", "unreachable"


class LingError(Exception):
    NO_KEY, INVALID_KEY, RATE_LIMITED, HIJACKED, TIMEOUT, HTTP, NETWORK, PARSE = (
        "NoKey", "InvalidKey", "RateLimited", "Hijacked", "Timeout", "Http", "Network", "Parse")

    def __init__(self, kind: str, status: int = 0):
        super().__init__("http%d" % status if kind == self.HTTP else kind)
        self.kind = kind
        self.status = status


class Response:
    def __init__(self, status: int, body: str):
        self.status = status
        self.body = body


class StreamResponse:
    """A reply read as it arrives: `lines` (server-sent events) or, for raw audio, `chunks` (bytes)."""

    def __init__(self, status: int, lines, content_type: str = "text/event-stream", chunks=None):
        self.status = status
        self.lines = lines
        self.content_type = content_type
        self.chunks = chunks


class UrlTransport:
    """How requests leave the app: urllib (which honours http_proxy / https_proxy), or a fake in tests.
    Raises TimeoutError on a timeout and OSError when the network fails."""

    @staticmethod
    def send(url: str, method: str, body: str | None, headers: dict, timeout: float) -> Response:
        req = urllib.request.Request(url, data=body.encode() if body is not None else None, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return Response(r.status, r.read().decode("utf-8", "replace"))
        except urllib.error.HTTPError as e:
            return Response(e.code, e.read().decode("utf-8", "replace") if e.fp else "")
        except socket.timeout as e:
            raise TimeoutError() from e
        except urllib.error.URLError as e:
            if isinstance(e.reason, socket.timeout):
                raise TimeoutError() from e
            raise OSError(str(e.reason)) from e

    @staticmethod
    def stream(url: str, body: str, headers: dict, timeout: float) -> StreamResponse:
        """A POST whose reply is read as it arrives (speech): by line for server-sent events, else in
        raw pieces (OpenRouter's speech streams the PCM bytes themselves)."""
        req = urllib.request.Request(url, data=body.encode(), method="POST", headers=headers)
        try:
            r = urllib.request.urlopen(req, timeout=timeout)
        except urllib.error.HTTPError as e:
            return StreamResponse(e.code, iter(()))
        except socket.timeout as e:
            raise TimeoutError() from e
        except urllib.error.URLError as e:
            raise OSError(str(e.reason)) from e

        def lines():
            with r:
                for raw in r:
                    yield raw.decode("utf-8", "replace").rstrip("\r\n")

        def chunks():
            with r:
                while True:
                    b = r.read(4800)  # 0.1 s at 24 kHz: playback starts early
                    if not b:
                        return
                    yield b
        return StreamResponse(r.status, lines(), r.headers.get("Content-Type") or "", chunks())


BASE = LING.base
TTS_MODEL = LING.voice_models[0].id
TTS_RATE = 24000  # Ming, Gemini TTS and Kokoro all speak 24 kHz
AUDIO_MODEL = LING.hear_models[0].id
# Search essays (Ling.swift), and the canned refusal some audio prompts get.
HIJACK_PREFIXES = ("根据现有检索证据", "暂未找到足够可靠的信息", "根据检索", "作为一个人工智能语言模型")


def silence_wav(seconds: float = 0.5) -> bytes:
    """A short quiet WAV (16 kHz mono 16-bit), to ask a model whether it takes audio at all."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"\x00\x00" * int(16000 * seconds))
    return buf.getvalue()


def _ling_config() -> AIConfig:
    return AIConfig(LING, LING.base, LING.text_models[0].id, LING.hear_models[0].id, LING.voice_models[0].id, LING.base)


class LingClient:
    """One instance for the app, for whichever AI service the settings name (`config`). Request
    *starts* go through one gate in priority order: Ling allows about 2 a second across every model
    (≥ 0.6 s apart, overlapping is fine), the aggregators far more. Ling's gateway shapes every call
    (see Ling.swift): thinking is always disabled, and the content goes in the system message with
    a fixed user instruction, because a question-like user message gets a search essay back; such
    replies are dropped. The other services get the same messages. Calls block: run them off the
    UI thread."""
    spacing: float | None = None  # tests only: overrides the service's

    def __init__(self, key: AIKey, transport=UrlTransport, config=None):
        self.key = key
        self.transport = transport
        self.config = config or _ling_config
        self.key_state = NONE if self.current_key() is None else UNCHECKED
        # Why the last check failed, shown under the key: a Mac string key and its arguments for LF()
        # ("连不上 %@，请检查网络或代理", "ZenMux"); None when it didn't.
        self.problem: tuple | None = None
        self.seconds: float | None = None   # how long the last good check took
        # Whether the hear model takes audio: None until a check asked (always True on Ling).
        self.hears: bool | None = None
        self.text_catalog: list = []
        self.hear_catalog: list = []
        self.rate_limited_at = None
        self._listeners = []
        self._gate = threading.Condition()
        self._waiting = []
        self._last_start = 0.0
        self._seq = 0

    def on_change(self, listener) -> None:
        self._listeners.append(listener)

    def _changed(self) -> None:
        for l in list(self._listeners):
            l()

    @property
    def provider(self):
        return self.config().provider

    def current_key(self) -> str | None:
        """The key for the service in use. A custom service on this computer may need none: ""."""
        c = self.config()
        k = self.key.read()
        if k is None and c.provider.id == "custom" and c.base and is_local(c.base):
            return ""
        return k

    @property
    def has_key(self) -> bool:
        return self.current_key() is not None

    @property
    def usable(self) -> bool:
        return self.has_key and self.key_state != INVALID

    @property
    def speaks(self) -> bool:
        """Voices in the room from this service. Linux has no system voice to fall back on."""
        return self.usable and self.config().has_voices

    @property
    def can_hear(self) -> bool:
        """Listening and 同声传译 can work: the hear model wasn't found to refuse audio."""
        return self.usable and self.hears is not False and bool(self.config().hear_model)

    def key_changed(self) -> None:
        """The key, the service or its models changed: forget what the last check found."""
        self.key.reload()
        self.key_state = NONE if self.current_key() is None else UNCHECKED
        self.problem = None
        self.hears = True if self.config().is_ling else None
        self.text_catalog, self.hear_catalog = [], []
        self._changed()

    def check(self) -> str:
        """The cheapest request that proves the key: Ling's tiny model, else one token from the text
        model. The others' hear model must also take audio (half a second of silence), and a custom
        service must return JSON (the notes need it)."""
        self.key_state = CHECKING
        self.problem = None
        self._changed()
        c = self.config()
        name = c.provider.name if c.provider.id != "custom" else "这个服务"
        started = time.monotonic()
        state = UNREACHABLE
        try:
            if c.is_ling:
                self.chat("Reply with OK.", "Reply.", SPEAK, max_tokens=5, timeout=10.0, model="Ling-3.0-tiny")
                self.seconds = time.monotonic() - started
                self.hears = True
            else:
                if c.base is None or not c.text_model:
                    raise LingError(LingError.NO_KEY)
                self.chat("Reply with OK.", "Reply.", SPEAK, max_tokens=5, timeout=20.0)
                self.seconds = time.monotonic() - started
                if c.provider.id == "custom":
                    try:
                        self.chat("Reply with the JSON object {\"ok\": true}.", "Reply.", SPEAK, json=True, max_tokens=20, timeout=20.0)
                    except LingError as e:
                        if e.kind == LingError.HTTP:
                            self.problem = ("这个服务不支持 JSON（HTTP %lld），纪要用不了", e.status)
                        else:
                            raise
                self.hears = self._hears(c)
            state = OK
        except LingError as e:
            state = {LingError.NO_KEY: NONE, LingError.INVALID_KEY: INVALID,
                     LingError.RATE_LIMITED: OK}.get(e.kind, UNREACHABLE)  # a busy key is still a good key
            if e.kind == LingError.HTTP and e.status in (400, 404):
                self.problem = (("找不到模型，或地址不对（HTTP %lld）", e.status) if c.provider.id == "custom"
                                else ("%@ 拒绝了请求（HTTP %lld），请检查模型名", name, e.status))
            elif state == UNREACHABLE:
                self.problem = ("连不上 %@，请检查网络或代理", name)
        except Exception:  # noqa: BLE001
            state = UNREACHABLE
            self.problem = ("连不上 %@，请检查网络或代理", name)
        self.key_state = state
        Log.d("ai %s: key check -> %s%s" % (c.provider.id, state, "" if self.hears is not False else " (hear model refuses audio)"))
        self._changed()
        if state == OK and not c.is_ling:
            self.fetch_catalog()
        return state

    def _hears(self, c: AIConfig) -> bool | None:
        """Whether the hear model takes audio: a 400 or 404 says no; anything else can't tell."""
        if not c.hear_model:
            return False
        try:
            self.chat("Transcribe the audio.", "Reply with what is said, or NONE.", SPEAK, max_tokens=10, timeout=20.0,
                      model=c.hear_model, audio=silence_wav())
            return True
        except LingError as e:
            if e.kind == LingError.HTTP and e.status in (400, 404, 415, 422):
                return False
            if e.kind == LingError.HIJACKED:
                return True
            return None

    def fetch_catalog(self) -> None:
        """The service's models, for the model menus: those that chat, and those that hear. Quietly
        just the recommended ones when the service has no `/models`."""
        c = self.config()
        k = self.current_key()
        if c.is_ling or k is None or c.base is None:
            return
        try:
            res = self.transport.send(c.base + "models", "GET", None, self._headers(k), 20.0)
        except (OSError, TimeoutError):
            return
        if res.status != 200:
            return
        self.text_catalog = catalog(res.body, [m.id for m in c.provider.text_models], hears=False)
        self.hear_catalog = catalog(res.body, [m.id for m in c.provider.hear_models], hears=True)
        Log.d("ai %s: %d models, %d hear" % (c.provider.id, len(self.text_catalog), len(self.hear_catalog)))
        self._changed()

    def chat(self, content: str, instruction: str, priority: int, json: bool = False, max_tokens: int = 1024,
             timeout: float = 30.0, model: str | None = None, audio: bytes | None = None, patient: bool = False) -> str:
        """One chat completion. `content` goes in the system message, `instruction` is the fixed user
        message, `audio` (a WAV) goes before it for the hear model. Notes retry 429s with backoff;
        heard audio gets one retry (a lost reply loses the words); the rest fail fast so the caller
        can fall back. `patient` (the final notes) keeps retrying for about a minute (retry_waits)."""
        k = self.current_key()
        if k is None:
            raise LingError(LingError.NO_KEY)
        if self.key_state == INVALID:
            raise LingError(LingError.INVALID_KEY)
        c = self.config()
        if c.base is None:
            raise LingError(LingError.NO_KEY)
        model = model or c.text_model
        user = instruction if audio is None else [c.audio_part(audio, model), {"type": "text", "text": instruction}]
        body = {"model": model,
                "messages": [{"role": "system", "content": content}, {"role": "user", "content": user}],
                "stream": False}
        c.shape(body, max_tokens)
        if json:
            body["response_format"] = {"type": "json_object"}
        payload = jsonfmt.write(body, pretty=False)
        waits = retry_waits(priority, audio is not None, patient)
        attempt = 1
        name = PRIORITY_NAMES[priority]
        while True:
            self._acquire(priority, c.provider.spacing)
            started = time.monotonic()
            try:
                root = self._post(c.base + "chat/completions", payload, k, timeout)
                choices = arr(root.get("choices"))
                choice = obj(choices[0]) if choices else None
                text = string((obj(choice.get("message")) or {}).get("content")) if choice else None
                if text is None:
                    raise LingError(LingError.PARSE)
                finish = string(choice.get("finish_reason"))
                trimmed = text.strip()
                # Ling's search essays come without a finish reason; other services may simply omit it.
                if (finish is None and c.is_ling) or trimmed.startswith(HIJACK_PREFIXES):
                    Log.d("ling: %s search-style reply dropped" % name)
                    raise LingError(LingError.HIJACKED)
                usage = obj(root.get("usage")) or {}
                Log.d("ai %s: %s ok %d ms tokens=%s/%s" % (c.provider.id, name, (time.monotonic() - started) * 1000,
                                                           usage.get("prompt_tokens"), usage.get("completion_tokens")))
                if self.rate_limited_at is not None:
                    self.rate_limited_at = None
                    self._changed()
                return trimmed
            except LingError as e:
                if e.kind != LingError.RATE_LIMITED:
                    raise
                if attempt > len(waits):
                    self.rate_limited_at = time.time()
                    self._changed()
                    raise
                wait = waits[attempt - 1] + random.random() * 0.5
                Log.d("ling: %s 429, retry in %.1f s" % (name, wait))
                time.sleep(wait)
                attempt += 1

    def speech(self, text: str, voice: str | None = "UK_Charlotte", language: str | None = None, timeout: float = 20.0):
        """The service's voice for `text`, as raw 24 kHz mono 16-bit PCM chunks while they arrive (a
        generator). On Ling, `voice` is Ming's and `language` its language_id, needed for Japanese,
        Korean, German, French and Spanish (Ling.swift › speech); elsewhere the configured speech
        model and `voice`. Replies come three ways and all are read: server-sent base64 chunks (Ling,
        ZenMux), raw PCM (OpenRouter), or one JSON `{"audio": <WAV>}`."""
        k = self.current_key()
        if k is None:
            raise LingError(LingError.NO_KEY)
        c = self.config()
        if not c.has_voices:
            raise LingError(LingError.NO_KEY)
        body = {"model": c.voice_model, "input": text, "response_format": "pcm"}
        if c.is_ling:
            body.update({"sample_rate": TTS_RATE, "stream": True, "stream_format": "sse", "voice": voice or "UK_Charlotte"})
            if language:
                body["language_id"] = language
        else:
            # OpenRouter documents no `stream` (it streams the bytes anyway); ZenMux needs it.
            if c.provider.id != "openrouter":
                body["stream"] = True
            ids = [v.id for v in c.voices]
            body["voice"] = voice if voice in ids else (ids[0] if ids else (c.custom_voice or "Kore"))
        self._acquire(SPEAK, c.provider.spacing)
        try:
            res = self.transport.stream(c.voice_base + "audio/speech", jsonfmt.write(body, pretty=False), self._headers(k), timeout)
        except TimeoutError:
            raise LingError(LingError.TIMEOUT) from None
        except OSError:
            raise LingError(LingError.NETWORK) from None
        if res.status in (401, 403):
            self.key_state = INVALID
            self._changed()
            raise LingError(LingError.INVALID_KEY)
        if res.status == 429:
            raise LingError(LingError.RATE_LIMITED)
        if res.status != 200:
            Log.d("ai %s: speech HTTP %d" % (c.provider.id, res.status))
            raise LingError(LingError.HTTP, res.status)
        kind = res.content_type or ""
        if "event-stream" in kind or res.chunks is None:
            for line in res.lines:
                if not line.startswith("data:"):
                    continue
                o = jsonfmt.parse_object(line[5:].strip())
                if o is None:
                    continue
                if o.get("type") == "speech.audio.done":
                    break
                audio = o.get("audio")
                if isinstance(audio, str) and audio:
                    yield _b64(audio)
        elif "json" in kind:
            o = jsonfmt.parse_object(b"".join(res.chunks).decode("utf-8", "replace"))
            audio = (o or {}).get("audio")
            if not isinstance(audio, str):
                raise LingError(LingError.PARSE)
            yield pcm_from_wav(_b64(audio))
        else:
            for b in res.chunks:
                yield b

    def _headers(self, k: str) -> dict:
        h = {"Content-Type": "application/json", "User-Agent": "Cicada-Linux/0.1"}
        if k:
            h["Authorization"] = "Bearer " + k
        return h

    def _post(self, url: str, payload: str, k: str, timeout: float) -> dict:
        try:
            res = self.transport.send(url, "POST", payload, self._headers(k), timeout)
        except TimeoutError:
            raise LingError(LingError.TIMEOUT) from None
        except OSError as e:
            Log.d("ling: network error %s" % type(e).__name__)
            raise LingError(LingError.NETWORK) from None
        if res.status in (401, 403):
            if self.key_state != INVALID:
                self.key_state = INVALID
                self._changed()
            raise LingError(LingError.INVALID_KEY)
        if res.status == 429:
            raise LingError(LingError.RATE_LIMITED)
        if res.status != 200:
            Log.d("ling: HTTP %d" % res.status)
            raise LingError(LingError.HTTP, res.status)
        root = jsonfmt.parse_object(res.body)
        if root is None:
            raise LingError(LingError.PARSE)
        return root

    # Start gate: request starts ≥ `spacing` apart, the most urgent waiting one first.

    def _acquire(self, priority: int, spacing: float = 0.6) -> None:
        spacing = LingClient.spacing if LingClient.spacing is not None else spacing
        with self._gate:
            self._seq += 1
            me = (priority, self._seq)
            self._waiting.append(me)
            try:
                while True:
                    head = min(self._waiting)
                    wait = spacing - (time.monotonic() - self._last_start)
                    if head == me and wait <= 0:
                        self._waiting.remove(me)
                        self._last_start = time.monotonic()
                        self._gate.notify_all()
                        return
                    self._gate.wait(wait if head == me else None)
            except BaseException:
                if me in self._waiting:
                    self._waiting.remove(me)
                self._gate.notify_all()
                raise


def retry_waits(priority: int, audio: bool = False, patient: bool = False) -> list:
    """Seconds before each retry of a 429 (Ling.swift › retryWaits). Notes retry a few times, heard
    audio once; the rest fail fast so the caller can fall back. `patient` (the final notes) keeps at
    it for about a minute: a model limited upstream (OpenRouter's Ling 3.1 by DeepInfra, 2026-11)
    came back after ~15 s, and a meeting left without its notes is worse than notes a little late."""
    if priority == NOTES:
        return [1, 2, 4, 8, 16, 30] if patient else [1, 2, 4]
    return [1] if audio else []


def _b64(s: str) -> bytes:
    import base64
    return base64.b64decode(s)


def pcm_from_wav(wav: bytes) -> bytes:
    """The samples of a WAV (its `data` chunk); the bytes themselves when there's no header."""
    if wav[:4] != b"RIFF":
        return wav
    at = 12
    while at + 8 <= len(wav):
        size = int.from_bytes(wav[at + 4:at + 8], "little")
        if wav[at:at + 4] == b"data":
            return wav[at + 8:at + 8 + size]
        at += 8 + size + (size & 1)
    return b""
