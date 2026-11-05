"""听哪里 on Linux: 会议室 (a microphone in the room) and 电脑和会议室 (both at once), the Mac's
HybridTests / HybridRecordTests case for case where the logic is shared."""
from __future__ import annotations

import threading
import time

from test_core import Base, Fake, client, concat, reply, silence, tone

from cicada.core.audio import PcmAudioSource
from cicada.core.ling import LingClient
from cicada.core.listen import ListenEngine
from cicada.core.notes import NotesEngine
from cicada.core.roommic import Input, VoiceGate, parse_sources, pick
from cicada.core.session_store import SessionStore
from cicada.core.settings import AppSettings
from cicada.core.translator import Translator

PACTL = """Source #47
\tState: SUSPENDED
\tName: alsa_output.pci-0000_00_05.0.analog-stereo.monitor
\tDescription: Monitor of Built-in Audio
\tMonitor of Sink: alsa_output.pci-0000_00_05.0.analog-stereo
\tProperties:
\t\tdevice.api = "alsa"
\t\tdevice.class = "monitor"
\t\tdevice.bus = "pci"
Source #48
\tState: SUSPENDED
\tName: alsa_input.pci-0000_00_05.0.analog-stereo
\tDescription: Built-in Audio Analog Stereo
\tMonitor of Sink: n/a
\tProperties:
\t\tdevice.api = "alsa"
\t\tdevice.class = "sound"
\t\tdevice.bus = "pci"
\t\tdevice.form_factor = "internal"
Source #60
\tName: bluez_input.AA_BB_CC_DD_EE_FF.0
\tDescription: WH-1000XM4
\tMonitor of Sink: n/a
\tProperties:
\t\tdevice.api = "bluez5"
\t\tdevice.bus = "bluetooth"
Source #61
\tName: alsa_input.usb-Jabra_Speak_510-00.mono-fallback
\tDescription: Jabra SPEAK 510 Mono
\tMonitor of Sink: n/a
\tProperties:
\t\tdevice.api = "alsa"
\t\tdevice.bus = "usb"
Source #70
\tName: cicada_mic
\tDescription: 知了 麦克风
\tMonitor of Sink: n/a
\tProperties:
\t\tdevice.class = "filter"
"""


class Microphones(Base):
    def test_reads_the_inputs(self):
        got = {i.name: i for i in parse_sources(PACTL)}
        self.assertEqual(5, len(got))
        self.assertTrue(got["alsa_output.pci-0000_00_05.0.analog-stereo.monitor"].virtual)
        self.assertTrue(got["cicada_mic"].virtual, "知了 麦克风 hears no room")
        built_in = got["alsa_input.pci-0000_00_05.0.analog-stereo"]
        self.assertTrue(built_in.builtin and not built_in.virtual)
        self.assertTrue(got["bluez_input.AA_BB_CC_DD_EE_FF.0"].bluetooth)
        usb = got["alsa_input.usb-Jabra_Speak_510-00.mono-fallback"]
        self.assertFalse(usb.builtin or usb.bluetooth or usb.virtual)
        self.assertEqual("Jabra SPEAK 510 Mono", usb.description)

    def test_picks_like_the_mac(self):
        # RoomMicPlan: the default unless virtual or a Bluetooth headset's, then the built-in one.
        inputs = parse_sources(PACTL)
        usb = "alsa_input.usb-Jabra_Speak_510-00.mono-fallback"
        built_in = "alsa_input.pci-0000_00_05.0.analog-stereo"
        self.assertEqual(usb, pick(usb, inputs))
        self.assertEqual(built_in, pick("bluez_input.AA_BB_CC_DD_EE_FF.0", inputs))
        self.assertEqual(built_in, pick("cicada_mic", inputs))
        self.assertEqual(built_in, pick(None, inputs))
        # Chosen in 设置 › 会议室, while it is plugged in.
        self.assertEqual(usb, pick(built_in, inputs, chosen=usb))
        self.assertEqual(built_in, pick(built_in, inputs, chosen="gone"))
        # Only a headset: better than nothing.
        bt = [Input("bt", bluetooth=True), Input("cicada_mic", virtual=True)]
        self.assertEqual("bt", pick("cicada_mic", bt))
        self.assertIsNone(pick(None, [Input("m", virtual=True)]))

    def test_voice_gate_learns_the_room(self):
        fixed = VoiceGate()
        self.assertFalse(fixed.voiced(0.006))
        g = VoiceGate(adaptive=True)
        self.assertEqual(0.004, g.threshold)
        # Ten seconds of a quiet room (0.001) with talk at 0.006.
        for i in range(100):
            g.voiced(0.001 if i % 10 == 0 else 0.006, 0.1)
        self.assertLess(g.threshold, 0.003)
        self.assertGreaterEqual(g.threshold, VoiceGate.lowest)
        self.assertTrue(g.voiced(0.006))
        # A loud room: the line never goes over the fixed gate.
        for _ in range(400):
            g.voiced(0.05, 0.1)
        self.assertEqual(VoiceGate.fixed, g.threshold)


def engine(store):
    LingClient.spacing = 0.02
    ling = client(Fake(lambda b: reply("LANG: en\nORIGINAL: Hello from the table.\nTRANSLATION: 桌边的人好。")
                       if "Ming-3.0-audio-flash" in b else reply("{}")))
    return ListenEngine(ling, Translator(ling), store, NotesEngine(ling, store), AppSettings(target="zh-CN"))


def run(e, pcm, mic):
    src = PcmAudioSource(lambda: pcm, speed=0)
    ended = threading.Event()
    src.on_ended = lambda why: ended.set()
    e.start(src, "room" if mic else "system", mic=mic)
    ended.wait(10)
    time.sleep(0.3)
    e.stop()


class Room(Base):
    QUIET = concat(silence(3.5), tone(1.0, amp=0.01), silence(1.0))  # a voice across the table, under -40 dBFS

    def test_a_quiet_voice_in_the_room_is_heard(self):
        store = SessionStore()
        e = engine(store)
        run(e, self.QUIET, mic=True)
        s = store.get(e.session_id)
        self.assertEqual(["Hello from the table."], [l.src for l in s.lines])
        self.assertTrue(s.room, "the record says 会议室")
        self.assertIsNone(s.lines[0].via, "会议室 alone: no place on each line, as on the Mac")

    def test_the_computers_audio_keeps_the_fixed_gate(self):
        store = SessionStore()
        e = engine(store)
        run(e, self.QUIET, mic=False)
        self.assertIsNone(store.get(e.session_id), "nothing heard, nothing kept")

    def test_changing_source_mid_meeting_goes_on_in_the_same_meeting(self):
        store = SessionStore()
        e = engine(store)
        first = PcmAudioSource(lambda: silence(0.5), speed=0)
        e.start(first, "system")
        sid = e.session_id
        time.sleep(0.2)
        mic = PcmAudioSource(lambda: self.QUIET, speed=0)
        ended = threading.Event()
        mic.on_ended = lambda why: ended.set()
        e.attach(mic, mic=True)
        ended.wait(10)
        time.sleep(0.3)
        e.stop()
        s = store.get(sid)
        self.assertEqual(1, len(s.lines))
        self.assertTrue(s.room)

    def test_muted_while_i_speak_through_the_same_mic(self):
        store = SessionStore()
        e = engine(store)
        src = PcmAudioSource(lambda: self.QUIET, speed=0)
        ended = threading.Event()
        src.on_ended = lambda why: ended.set()
        # Muted before any audio arrives: the worker replaces it with silence.
        e.start(PcmAudioSource(lambda: silence(0.1), speed=0), "room", mic=True)
        e.set_muted(True)
        e.attach(src, mic=True)
        e.set_muted(True)
        ended.wait(10)
        time.sleep(0.3)
        e.stop()
        self.assertEqual(0, len(store.get(e.session_id).lines) if store.get(e.session_id) else 0)
