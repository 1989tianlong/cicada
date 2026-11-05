"""会议室: listening to the people in the room through a real microphone instead of what the computer
plays (the Mac's RoomMic.swift). Pure: which microphone, and when a block of it counts as speech.
The capture itself is app/capture.py's SystemAudio on a source instead of a monitor."""
from __future__ import annotations

import threading

# Sources Cicada makes itself (app/room.py's 知了 麦克风), never a room microphone.
OURS = ("cicada_mic",)


class Input:
    def __init__(self, name: str, description: str = "", builtin: bool = False, bluetooth: bool = False,
                 virtual: bool = False):
        self.name = name
        self.description = description or name
        self.builtin = builtin
        self.bluetooth = bluetooth
        self.virtual = virtual

    def __repr__(self):
        return "Input(%s%s%s%s)" % (self.name, " builtin" if self.builtin else "", " bt" if self.bluetooth else "",
                                     " virtual" if self.virtual else "")


def parse_sources(text: str) -> list:
    """The inputs in `LC_ALL=C pactl list sources`. A monitor of an output, a source a module made
    (no device.api: 知了 麦克风, an echo canceller, a remap) or one of ours is virtual: it hears no room."""
    out = []
    block: dict = {}
    props: dict = {}

    def close():
        name = block.get("Name")
        if not name:
            return
        monitor = block.get("Monitor of Sink", "n/a") not in ("n/a", "")
        api = props.get("device.api", "")
        virtual = monitor or not api or name in OURS or name.startswith("cicada_") or props.get("device.class") == "monitor"
        bluetooth = api == "bluez5" or props.get("device.bus") == "bluetooth"
        builtin = not bluetooth and (props.get("device.form_factor") == "internal" or
                                     (api == "alsa" and props.get("device.bus") == "pci"))
        out.append(Input(name, block.get("Description", ""), builtin, bluetooth, virtual))

    for raw in text.splitlines():
        line = raw.strip()
        if raw.startswith("Source #"):
            close()
            block, props = {}, {}
            continue
        if raw.startswith("\t\t") and " = " in line:
            k, _, v = line.partition(" = ")
            props[k.strip()] = v.strip().strip('"')
        elif ":" in line and raw.startswith("\t") and not raw.startswith("\t\t"):
            k, _, v = line.partition(":")
            block[k.strip()] = v.strip()
    close()
    return out


def pick(default: str | None, inputs: list, chosen: str = "") -> str | None:
    """The microphone that hears the room (RoomMicPlan.pick): the one chosen in 设置 › 会议室 while it
    is there; else the default input, unless it is virtual (同声传译 makes 知了 麦克风 the default) or a
    Bluetooth headset's (it hears the wearer, not the table, and drops to call quality while open);
    then the computer's own microphone, then any real one."""
    real = [i for i in inputs if not i.virtual]
    if chosen and any(i.name == chosen for i in real):
        return chosen
    d = next((i for i in real if i.name == default), None)
    if d is not None and not d.bluetooth:
        return d.name
    for want in (lambda i: i.builtin, lambda i: not i.bluetooth, lambda i: True):
        found = next((i for i in real if want(i)), None)
        if found is not None:
            return found.name
    return None


class VoiceGate:
    """When a block of audio counts as speech (the Mac's VoiceGate). The computer's own audio is
    digital silence between words, so a fixed -40 dBFS works there. A room mic always hears the room
    (a fan, the street), and a voice across the table can be quieter than -40 dBFS: there the line
    sits at twice the room's own noise. The noise is the quietest moment of each second (the gaps
    between words, even while people talk on and on), taken low over the last half minute."""
    fixed = 0.01
    lowest = 0.0015

    def __init__(self, adaptive: bool = False):
        self.adaptive = adaptive
        self._quietest: list = []
        self._second = float("inf")
        self._elapsed = 0.0

    @property
    def threshold(self) -> float:
        if not self.adaptive:
            return self.fixed
        if len(self._quietest) < 3:
            return 0.004
        floor = sorted(self._quietest)[len(self._quietest) // 5]
        return min(self.fixed, max(self.lowest, floor * 2))

    def voiced(self, rms: float, seconds: float = 0.1) -> bool:
        on = rms >= self.threshold
        if not self.adaptive:
            return on
        self._second = min(self._second, rms)
        self._elapsed += seconds
        if self._elapsed >= 1 - 1e-9:
            self._quietest.append(self._second)
            if len(self._quietest) > 30:
                self._quietest.pop(0)
            self._second = float("inf")
            self._elapsed = 0.0
        return on


# 电脑和会议室: the computer's audio and the room microphone at once, each heard on its own.

def heard_both(lines) -> bool:
    """The room mic and the computer's audio both brought in the other side's lines, so each one says
    where it was heard (the Mac's RecordList.heardBoth). Read from the lines, not stored."""
    room = online = False
    for l in lines:
        if l.speaker != "them":
            continue
        if l.via == "room":
            room = True
        else:
            online = True
        if room and online:
            return True
    return False


def place_starts(lines) -> set:
    """Lines of the other side's where the place changes from the line before: their label shows again."""
    out, last, first = set(), None, True
    for l in lines:
        key = "me" if l.speaker == "me" else l.via
        if l.speaker != "me" and (first or key != last):
            out.add(l.id)
        last, first = key, False
    return out


def asks_online(room_only: bool, answered: bool, in_call: bool) -> bool:
    """线上也有人？: listening to the room alone while a meeting app here is in a call, so people online
    are likely speaking through it. Once a meeting (the Mac's RoomPrompt.asksOnline)."""
    return room_only and not answered and in_call


def hybrid_note(room_running: bool, echo_cancelled: bool, headphones: bool, headset_default: bool):
    """The grey line under 听哪里 in 电脑和会议室, when the room isn't heard the plain way (the Mac's
    HybridNote): without echo cancellation the room pauses while the computer plays speech; with a
    Bluetooth headset as the default input the computer's own mic hears the room. The string's key."""
    if not room_running:
        return None
    if not echo_cancelled and not headphones:
        return "线上有人说话时，先不听会议室"
    if headset_default:
        return "用电脑自带的麦克风听会议室"
    return None


class EchoGate:
    """电脑和会议室 without echo cancellation: while the computer plays speech, the room mic hears it
    again from the speakers. Listening `hold`s the gate on every loud block of the computer's audio;
    the room mic hears silence until `hang` after the last one (the speakers' tail, the room's echo)."""
    hang = 0.4

    def __init__(self):
        self._lock = threading.Lock()
        self._until = 0.0

    def hold(self, now: float) -> None:
        with self._lock:
            self._until = max(self._until, now + self.hang)

    def closed(self, now: float) -> bool:
        with self._lock:
            return now < self._until


class Heard:
    def __init__(self, text: str, start: float, end: float):
        self.text = text
        self.start = start
        self.end = end


class EchoMatch:
    """电脑和会议室's last line of defence against hearing an online sentence twice: once from the
    computer's audio, once more from the speakers into the room mic (the Mac's EchoMatch). A room line
    made mostly of what the computer played around the same time is dropped, matched by containment
    in word pairs (characters for Chinese, Japanese and Korean)."""
    window = 3.0     # seconds around the room line where the computer's lines count
    hold = 2.5       # how long a room line waits for the computer's line it may echo
    contained = 0.6  # share of the room line found in the computer's lines that makes it an echo

    @classmethod
    def is_echo(cls, room: Heard, online: list) -> bool:
        near = [o for o in online if o.end >= room.start - cls.window and o.start <= room.end + cls.window]
        if not near:
            return False
        r = units(room.text)
        if not r:
            return False
        o = [units(x.text) for x in near]
        if len(r) <= 2:  # a word or two ("OK", "对"): the very same words near it
            return any(x == r for x in o)
        mine = set(_pairs(r))
        theirs = set(p for x in o for p in _pairs(x))
        return len(mine & theirs) / len(mine) >= cls.contained


def _cjk(c: str) -> bool:
    v = ord(c)
    return (0x3040 <= v <= 0x30FF or 0x3400 <= v <= 0x4DBF or 0x4E00 <= v <= 0x9FFF or 0xAC00 <= v <= 0xD7AF
            or 0xF900 <= v <= 0xFAFF)


def units(text: str) -> list:
    """Lower-case words, each CJK character on its own; punctuation and spacing don't count."""
    out, word = [], ""
    for c in text.lower():
        if _cjk(c):
            if word:
                out.append(word)
                word = ""
            out.append(c)
        elif c.isalnum():
            word += c
        elif word:
            out.append(word)
            word = ""
    if word:
        out.append(word)
    return out


def _pairs(u: list) -> list:
    return u if len(u) < 2 else [u[i - 1] + " " + u[i] for i in range(1, len(u))]
