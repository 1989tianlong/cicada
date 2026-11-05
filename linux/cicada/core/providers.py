"""The AI services the port can use (AIProviders.swift, plus what hears audio). Ling is the
reference: Ming hears each stretch of audio and answers language, original and translation in one
call, and only Ling clones the user's voice. The others are OpenAI-compatible and hear through an
audio-input chat model with the same prompt (tools/audio-probe measured them against Ming, 2026-11:
about as accurate, 0.5–2 s slower). OpenAI itself is left out: a port needs a model that hears,
and its audio models are untested.

Recommended models come first in every menu and are the defaults. For hearing, the first is the one
that wrote nothing for a clip without speech: a made-up line ends up in the notes and, when
interpreting, in the room."""
from __future__ import annotations

import base64
import re
import urllib.parse
from dataclasses import dataclass, field

from .jsonfmt import arr, obj, string


@dataclass(frozen=True)
class Model:
    id: str
    note: str = ""  # why it is recommended: a Chinese UI key, localized where shown


@dataclass(frozen=True)
class CloudVoice:
    id: str
    gender: str  # "女" / "男", a Chinese UI key


@dataclass(frozen=True)
class Provider:
    id: str
    name: str
    base: str | None            # None for "custom": the user's address
    site: str | None            # where to create a key
    text_models: tuple = ()
    hear_models: tuple = ()
    voice_models: tuple = ()    # empty: this service can't speak into the room here
    voices: tuple = ()          # of `voice_models` (Gemini TTS: the same names in every language)
    clones: bool = False
    spacing: float = 0.1        # Ling allows ~2 request starts a second; the aggregators far more

    @property
    def has_voices(self) -> bool:
        return bool(self.voice_models)


GEMINI_VOICES = (CloudVoice("Kore", "女"), CloudVoice("Aoede", "女"), CloudVoice("Charon", "男"), CloudVoice("Puck", "男"))

LING = Provider(
    "ling", "Ling", "https://api.ant-ling.com/v1/", "https://chat.ant-ling.com/platform/api",
    text_models=(Model("Ling-3.1-flash", "更准"), Model("Ling-3.0-flash", "更快、更省")),
    hear_models=(Model("Ming-3.0-audio-flash"),),
    voice_models=(Model("Ming-3.0-tts-0.5B"),), clones=True, spacing=0.6)

OPENROUTER = Provider(
    "openrouter", "OpenRouter", "https://openrouter.ai/api/v1/", "https://openrouter.ai/settings/keys",
    text_models=(Model("inclusionai/ling-3.1-flash", "和 Ling 同款"), Model("qwen/qwen3.8-flash", "中文好")),
    hear_models=(Model("qwen/qwen3.8-omni-flash", "没人说话时不乱写"), Model("google/gemini-3.1-flash-lite", "最快，偶尔把杂音写成字")),
    voice_models=(Model("google/gemini-3.8-flash-tts", "效果和价格最均衡"), Model("google/gemini-3.8-flash-lite-tts", "更省")),
    voices=GEMINI_VOICES)

ZENMUX = Provider(
    "zenmux", "ZenMux", "https://zenmux.ai/api/v1/", "https://zenmux.ai/settings/keys",
    text_models=(Model("inclusionai/ling-3.0-flash", "和 Ling 同款"), Model("qwen/qwen3.8-flash", "中文好")),
    hear_models=(Model("qwen/qwen3.8-omni-flash", "没人说话时不乱写"), Model("bytedance/doubao-seed-2.0-mini", "更快"),
                 Model("google/gemini-3.1-flash-lite", "最快，偶尔把杂音写成字")),
    voice_models=(Model("google/gemini-3.8-flash-tts", "效果和价格最均衡"), Model("google/gemini-3.8-flash-lite-tts", "更省")),
    voices=GEMINI_VOICES)

# Any OpenAI-compatible address (a company gateway, Ollama…). Its hear model must take audio in;
# voices only when the user names a speech model.
CUSTOM = Provider("custom", "其他（兼容 OpenAI）", None, None)

ALL = (LING, OPENROUTER, ZENMUX, CUSTOM)


def named(raw: str) -> Provider:
    return next((p for p in ALL if p.id == raw), LING)


def is_local(host_or_url: str) -> bool:
    u = host_or_url if "://" in host_or_url else "http://" + host_or_url
    host = urllib.parse.urlsplit(u).hostname or host_or_url
    return host in ("localhost", "127.0.0.1", "::1")


def custom_base(raw: str) -> str | None:
    """The address as typed, normalized: https, or http only on this computer; ends in "/"."""
    s = (raw or "").strip()
    if not s:
        return None
    if "://" not in s:
        s = ("http://" if is_local(s) else "https://") + s
    if not s.endswith("/"):
        s += "/"
    parts = urllib.parse.urlsplit(s)
    if not parts.hostname:
        return None
    if parts.scheme == "https":
        return s
    return s if parts.scheme == "http" and is_local(parts.hostname) else None


@dataclass
class AIConfig:
    """What one call needs to know about the service in use, resolved from settings each time."""
    provider: Provider
    base: str | None            # None: a custom service without a valid address yet
    text_model: str
    hear_model: str
    voice_model: str | None = None   # None: no voices with this service
    voice_base: str | None = None
    custom_voice: str | None = None
    extra: dict = field(default_factory=dict)

    @property
    def is_ling(self) -> bool:
        return self.provider.id == "ling"

    @property
    def has_voices(self) -> bool:
        return self.voice_model is not None and self.voice_base is not None

    @property
    def voices(self) -> tuple:
        """The voices the room can pick from with this service (Ling's are in voices.py)."""
        if not self.has_voices or self.is_ling:
            return ()
        if self.provider.id == "custom":
            return (CloudVoice(self.custom_voice, ""),) if self.custom_voice else ()
        return self.provider.voices

    def shape(self, body: dict, max_tokens: int) -> None:
        """Each service turns thinking off its own way (AIConfig.shape on the Mac)."""
        body["max_tokens"] = max_tokens
        body["temperature"] = 0.2
        if self.is_ling:
            body["thinking"] = {"type": "disabled"}
        elif self.provider.id in ("openrouter", "zenmux"):
            body["reasoning"] = {"enabled": False}

    def audio_part(self, wav: bytes, model: str) -> dict:
        """One WAV in a user message: Ming takes a data URL; the others the standard `input_audio`,
        except that Qwen's omni models want the data URL inside it (DashScope's form)."""
        b64 = base64.b64encode(wav).decode()
        if self.is_ling:
            return {"type": "audio_url", "audio_url": {"url": "data:audio/wav;base64," + b64}}
        if model.split("/")[-1].startswith("qwen"):
            b64 = "data:audio/wav;base64," + b64
        return {"type": "input_audio", "input_audio": {"data": b64, "format": "wav"}}


def config_from(settings) -> AIConfig:
    """The service, its address and models from the app's settings (Settings.swift › aiConfig)."""
    p = named(settings.aiProvider)
    models, hears, voices = settings.aiModels, settings.aiHearModels, settings.aiVoiceModels
    if p.id == "ling":
        text = settings.model if settings.model in [m.id for m in p.text_models] else p.text_models[0].id
        return AIConfig(p, p.base, text, p.hear_models[0].id, p.voice_models[0].id, p.base)
    if p.id == "custom":
        base = custom_base(settings.aiCustomBase)
        voice = (voices.get("custom") or "").strip()
        voice_base = custom_base(settings.aiCustomVoiceBase) if settings.aiCustomVoiceBase.strip() else base
        name = settings.aiCustomVoice.strip()
        return AIConfig(p, base, (models.get("custom") or "").strip(), (hears.get("custom") or "").strip(),
                        voice or None, voice_base if voice else None, name or None)
    return AIConfig(p, p.base, models.get(p.id) or p.text_models[0].id, hears.get(p.id) or p.hear_models[0].id,
                    voices.get(p.id) or p.voice_models[0].id, p.base)


_NOT_CHAT = re.compile(r"(embed|whisper|tts|transcribe|dall-e|image|moderation|realtime|sora|search|video|seedance|wan\d)")


def catalog(data: str | dict, recommended: list, hears: bool) -> list:
    """Model ids from a `/models` reply, recommended ones first: those that answer in text, and for
    `hears` only those that take audio in. ZenMux lists modalities at the top level, OpenRouter under
    `architecture`; a service that says nothing keeps everything but obvious non-chat names."""
    from .jsonfmt import parse_object
    root = parse_object(data) if isinstance(data, str) else data
    ids = []
    for m in arr((root or {}).get("data")):
        m = obj(m) or {}
        mid = string(m.get("id"))
        if not mid or mid.endswith(":batch"):
            continue
        a = obj(m.get("architecture")) or {}
        ins = arr(m.get("input_modalities") or a.get("input_modalities"))
        outs = arr(m.get("output_modalities") or a.get("output_modalities"))
        if outs and "text" not in outs:
            continue
        if ins and ins == ["audio"]:
            continue  # speech-to-text only: no prompt, no translation
        if hears and "audio" not in ins:
            continue
        if not outs and _NOT_CHAT.search(mid):
            continue
        ids.append(mid)
    rest = sorted(i for i in ids if i not in recommended)
    return list(recommended) + rest
