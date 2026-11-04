"""The app's settings, in settings.json beside the key (never the key itself: it has its own file)."""
from __future__ import annotations

import os

from . import jsonfmt
from .support import Log, Paths, follow_system_target, my_language, system_language, system_languages

DEFAULT_MODEL = "Ling-3.1-flash"


class AppSettings:
    FIELDS = {
        "target": "system",          # what subtitles translate into; "system" follows the desktop language
        "notesLanguage": "system",   # 纪要语言; "system" is the same as the subtitles'
        "model": DEFAULT_MODEL,
        "view": "notes",             # "notes" (the notes window, default) or "subtitles" (the subtitle bar)
        "showInCapture": False,      # 共享屏幕时让对方看到 (Linux can't hide it; see NotesWindow)
        "onboarded": False,
        "uiLanguage": "system",      # "system", "zh-Hans", "en", "ja" or "ko"
        # 同声传译: what I say is interpreted and spoken into 知了 麦克风 (the Mac's speakEnabled etc.).
        "speakerVoices": True,       # 说话人识别: tell the other side's voices apart (说话人 1、2…), as on the Mac
        "speakEnabled": False,
        "speakFrom": "system",       # the language I speak; "system" = the subtitles' language
        "speakTo": "room",           # what the room hears; "room" = the language they have been speaking
        "speakVoices": {},           # Ming voice per language key ("en": "US_Emma")
        "speakHeadphones": False,    # 戴着耳机: skip the echo guard, talking over them is fine
        # 结束会议 (meeting_end.py), the Mac's keys: end when the meeting app hangs up; when nobody
        # speaks, "prompt" (count down, then end), "end" or "off", after silenceMinutes.
        "endWithApp": True,
        "silenceEnd": "prompt",
        "silenceMinutes": 10,
    }

    def __init__(self, **kw):
        for k, v in self.FIELDS.items():
            v = kw.get(k, v)
            setattr(self, k, dict(v) if isinstance(v, dict) else v)

    @property
    def target_code(self) -> str:
        """My language: the translate-to choice, or under "follow system" the Mac's myLanguage."""
        return my_language(system_languages()) if self.target == "system" else self.target

    def resolved_target(self, source: str | None) -> str:
        """What lines in `source` translate into: under "follow system", the next system language when
        they speak mine (the Mac's resolvedTarget)."""
        return follow_system_target(source, system_languages()) if self.target == "system" else self.target

    @property
    def notes_code(self) -> str:
        return self.target_code if self.notesLanguage == "system" else self.notesLanguage

    @property
    def speak_from_code(self) -> str:
        return self.target_code if self.speakFrom == "system" else self.speakFrom

    @property
    def ui_code(self) -> str:
        return system_language() if self.uiLanguage == "system" else self.uiLanguage

    def to_json(self) -> dict:
        return {k: getattr(self, k) for k in self.FIELDS}

    def save(self) -> None:
        try:
            os.makedirs(Paths.config(), exist_ok=True)
            with open(Paths.settings(), "w", encoding="utf-8") as f:
                f.write(jsonfmt.write(self.to_json()))
        except OSError as e:
            Log.d("settings: save failed %s" % type(e).__name__)

    @staticmethod
    def load() -> "AppSettings":
        try:
            if os.path.isfile(Paths.settings()):
                with open(Paths.settings(), encoding="utf-8") as f:
                    o = jsonfmt.parse_object(f.read())
                if o is not None:
                    kw = {k: o[k] for k, d in AppSettings.FIELDS.items() if k in o and type(o[k]) is type(d)}
                    return AppSettings(**kw)
        except OSError as e:
            Log.d("settings: unreadable, defaults used (%s)" % type(e).__name__)
        return AppSettings()
