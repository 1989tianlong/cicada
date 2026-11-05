"""会议室: listening to the people in the room through a real microphone instead of what the computer
plays (the Mac's RoomMic.swift). Pure: which microphone, and when a block of it counts as speech.
The capture itself is app/capture.py's SystemAudio on a source instead of a monitor."""
from __future__ import annotations

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
