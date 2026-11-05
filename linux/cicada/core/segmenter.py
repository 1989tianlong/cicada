"""Cuts the audio into stretches of speech by loudness alone: a pause of 0.6 s ends one, and one that
runs to 8 s is cut at its quietest moment in the last 2 s, so a word is split as rarely as possible
(Ming has no word timings to put it back together). Not thread-safe: fed from the listening worker
only. Same numbers as the Windows and Android Segmenters."""
from __future__ import annotations

from array import array
from collections import deque

from .audio import RATE, Wav

FRAME = 480  # 30 ms
PRE_ROLL = 0.15
TAIL = 0.15
CUT_WINDOW = 2.0


class Segment:
    """A stretch of speech to send to Ming: where it starts (seconds since listening began) and its
    16 kHz mono samples."""

    def __init__(self, index: int, start: float, samples: array):
        self.index = index
        self.start = start
        self.samples = samples

    @property
    def seconds(self) -> float:
        return len(self.samples) / RATE


class Segmenter:
    # The Mac AudioRouter's gate (about -40 dBFS). A room microphone's segmenter has it set by
    # roommic.VoiceGate as the room's noise is learnt.
    threshold = 0.01
    pause = 0.6
    max_length = 8.0
    min_speech = 0.25
    min_word = 0.2  # a word on its own (_isolated): this much over gate / 4 ("Thanks." at -36 dBFS: 0.21 s)
    steady = 2.0  # frames' 90th / 10th percentile below this: not speech…
    dips = 2.5  # …unless the median is this far over the 10th percentile, quiet ones held at gate / 8
    short = 2.0  # a sound up to this long, with real quiet (gate / 4) on both sides…
    swell = 10 ** (10 / 20)  # …that swells and fades by 10 dB is a word: see _isolated

    def __init__(self):
        self.pending = array("h")
        self.current = array("h")
        self.levels: list = []
        self.before: deque = deque()
        self.idle: deque = deque(maxlen=int(self.pause * RATE / FRAME))  # levels of the last quiet frames
        self.lead = None  # the quietest of those when the open segment began (None: it didn't begin in quiet)
        self.consumed = 0
        self.current_start = 0.0
        self.quiet = 0
        self.loud = 0
        self.index = 0
        self.on_segment = None

    def feed(self, samples) -> None:
        self.pending.extend(samples)
        whole = len(self.pending) // FRAME * FRAME
        for i in range(0, whole, FRAME):
            self._step(self.pending[i:i + FRAME])
        del self.pending[:whole]

    def flush(self) -> None:
        """Ends the open segment (listening stopped)."""
        if len(self.current):
            self._close(len(self.current) - self.quiet * FRAME + int(TAIL * RATE))

    def _step(self, frame: array) -> None:
        level = Wav.rms(frame)
        loud = level >= self.threshold
        now = self.consumed / RATE
        self.consumed += len(frame)
        if not len(self.current):
            if not loud:
                self.idle.append(level)
                self.before.append((frame, level))
                while len(self.before) > PRE_ROLL * RATE / FRAME:
                    self.before.popleft()
                return
            self.current_start = now - len(self.before) * FRAME / RATE
            self.lead = min(self.idle) if self.idle else None
            self.idle.clear()
            for f, l in self.before:
                self.current.extend(f)
                self.levels.append(l)
            self.before.clear()
            self.quiet = self.loud = 0
        self.current.extend(frame)
        self.levels.append(level)
        if loud:
            self.quiet = 0
            self.loud += 1
        else:
            self.quiet += 1
        if self.quiet * FRAME >= self.pause * RATE:
            self._close(len(self.current) - self.quiet * FRAME + int(TAIL * RATE))
        elif len(self.current) >= self.max_length * RATE:
            # The quietest frame in the last 2 s; the rest starts the next segment.
            frm = max(1, len(self.levels) - int(CUT_WINDOW * RATE / FRAME))
            cut = frm
            for i in range(frm, len(self.levels)):
                if self.levels[i] < self.levels[cut]:
                    cut = i
            self._close(cut * FRAME)

    def _steady(self, levels) -> bool:
        """Steady sound just over the gate (a fan, hum, hiss) isn't speech: its loud frames barely vary
        (90th / 10th percentile about 1.1; speech, even over such a floor, 3 and up). Given one, Ming
        writes a stock sentence in the hint's language ("I'm going to show you a couple of things").
        Speech buried under steady noise goes too; system audio rarely carries it. Every frame from
        the first loud one to the last counts, the quiet ones held at the gate: counting only the
        loud ones dropped quiet speech (under about -30 dBFS), whose dips fall below the gate.
        A voice so quiet that its loudest frames barely clear the gate (about -38 dBFS: 6 of 6 lines
        lost in testing) still pauses between syllables, its quietest tenth of frames far under its
        median (8 dB and more); noise near the gate stays within about 6 dB of its median. So a flat
        top is steady only when it has no such dips, measured with quiet frames held at gate / 8.
        Very low rumble (brown noise with almost nothing over 20 Hz) can look like that and gets
        through more often than before (about 1 in 3 segments, was 1 in 5); what Ming makes of it
        still meets the hear filter (translator.is_noise)."""
        loud = [i for i, l in enumerate(levels) if l >= self.threshold]
        if len(loud) < 2:
            return False
        body = levels[loud[0]:loud[-1] + 1]
        top = sorted(max(l, self.threshold) for l in body)
        if top[int(0.9 * (len(top) - 1))] >= self.steady * top[int(0.1 * (len(top) - 1))]:
            return False
        low = sorted(max(l, self.threshold / 8) for l in body)
        return low[int(0.5 * (len(low) - 1))] < self.dips * low[int(0.1 * (len(low) - 1))]

    def _isolated(self, levels) -> bool:
        """A short word on its own: a sound up to `short` that rises out of real quiet and falls back
        into it (under gate / 4, about -52 dBFS, in the 0.6 s before it and in the pause after),
        and that swells and fades by 10 dB or more (90th / 10th percentile of its frames over
        gate / 4). Such a word ("Thanks.", "Good morning everyone,") is one smooth syllable or a run
        of voiced ones, so the steady test, which looks for dips inside, dropped it even at
        -26 dBFS; and a quiet one ("Thanks." at -36 dBFS) has under 0.25 s over the gate, so it
        needs `min_word` over gate / 4 instead (a knock with a 150 ms tail has 0.15 s). A fan,
        hum or hiss is there on both sides; a short burst of one in silence stays within about
        9 dB (brown noise), 5 dB (the rest), and Ming makes up a sentence for a hum or fan burst.
        Not for a forced cut, whose end isn't a pause."""
        loud = [i for i, l in enumerate(levels) if l >= self.threshold]
        if not loud or (loud[-1] - loud[0] + 1) * FRAME > self.short * RATE:
            return False
        quiet = self.threshold / 4
        after = levels[loud[-1] + 1:]
        if self.lead is None or self.lead > quiet or not after or min(after) > quiet:
            return False
        sound = [i for i, l in enumerate(levels) if l >= quiet]
        body = sorted(max(l, self.threshold / 8) for l in levels[sound[0]:sound[-1] + 1])
        return body[int(0.9 * (len(body) - 1))] >= self.swell * body[int(0.1 * (len(body) - 1))]

    def _close(self, end_at: int) -> None:
        """Emits current[:end] and keeps what follows as the start of the next segment."""
        end = max(0, min(end_at, len(self.current)))
        samples = self.current[:end]
        rest = self.current[end:]
        rest_levels = self.levels[min(len(self.levels), end // FRAME):]
        start = self.current_start
        sent = self.levels[:end // FRAME]
        if self._isolated(self.levels):
            sound = sum(1 for l in sent if l >= self.threshold / 4)
            speech = sound * FRAME >= self.min_word * RATE
        else:
            speech = self.loud * FRAME >= self.min_speech * RATE and not self._steady(sent)
        self.current = array("h")
        self.levels = []
        self.quiet = self.loud = 0
        if speech and self.on_segment:
            self.index += 1
            self.on_segment(Segment(self.index, round(start * 1000) / 1000.0, samples))
        elif speech:
            self.index += 1
        # A forced cut carries on with the remainder; after a pause the remainder is silence.
        if any(l >= self.threshold for l in rest_levels):
            self.current_start = start + end / RATE
            self.lead = None
            self.current.extend(rest)
            self.levels = list(rest_levels)
            trailing = 0
            for l in reversed(self.levels):
                if l >= self.threshold:
                    break
                trailing += 1
            self.quiet = trailing
            self.loud = sum(1 for l in self.levels if l >= self.threshold)
