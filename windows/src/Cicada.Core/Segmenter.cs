namespace Cicada;

/// A stretch of speech to send to Ming: where it starts (seconds since listening began) and its
/// 16 kHz mono samples.
public sealed record Segment(int Index, double Start, short[] Samples)
{
    public double Seconds => Samples.Length / (double)Segmenter.Rate;
}

/// Cuts the system audio into stretches of speech by loudness alone: a pause of 0.6 s ends one,
/// and one that runs to 8 s is cut at its quietest moment in the last 2 s, so a word is split as
/// rarely as possible (Ming has no word timings to put it back together). Not thread-safe: fed
/// from the audio queue only.
public sealed class Segmenter
{
    public const int Rate = 16000;
    const int Frame = 480;                       // 30 ms
    public static double Threshold = 0.01;       // the Mac AudioRouter's gate (about -40 dBFS)
    public static double Pause = 0.6, MaxLength = 8.0, MinSpeech = 0.25;
    public static double MinWord = 0.2;          // a word on its own (IsWord): this much over gate / 4
    public static double Steady = 2.0;           // frames' 90th / 10th percentile below this: not speech…
    public static double Dips = 2.5;             // …unless the median is this far over the 10th, quiet ones held at gate / 8
    public static double Short = 2.0;            // a sound up to this long, with real quiet (gate / 4) on both sides…
    public static double Swell = Math.Pow(10, 10 / 20.0); // …that swells and fades by 10 dB is a word: see IsWord
    const double PreRoll = 0.15, Tail = 0.15, CutWindow = 2.0;

    readonly List<short> pending = [];           // samples not yet a whole frame
    readonly List<short> current = [];           // the open segment
    readonly List<double> levels = [];           // per frame of `current`
    readonly Queue<(short[] frame, double level)> before = new(); // recent quiet frames, for the pre-roll
    readonly Queue<double> idle = new();         // levels of the last 0.6 s of quiet frames
    double? lead;                                // the quietest of those when the open segment began
    long consumed;                               // samples seen, for timestamps
    double currentStart;
    int quietFrames, loudFrames, index;
    /// 会议室: a microphone's line follows the room's noise (VoiceGate); null keeps the fixed one.
    /// Swapped when 听哪里 changes mid-meeting (read once per frame on the audio thread).
    public VoiceGate? Gate { get => gate; set => gate = value; }
    volatile VoiceGate? gate;
    double line = Threshold;

    public Segmenter(VoiceGate? gate = null) { this.gate = gate; }

    /// The level that counts as speech right now.
    public double Line => line;

    public event Action<Segment>? Emitted;

    public void Feed(ReadOnlySpan<short> samples)
    {
        foreach (var s in samples) pending.Add(s);
        int whole = pending.Count / Frame * Frame;
        for (int i = 0; i < whole; i += Frame)
        {
            var frame = pending.GetRange(i, Frame).ToArray();
            Step(frame);
        }
        pending.RemoveRange(0, whole);
    }

    /// Ends the open segment (listening stopped).
    public void Flush()
    {
        if (current.Count > 0) Close(current.Count - quietFrames * Frame + (int)(Tail * Rate));
    }

    static double Rms(short[] frame)
    {
        double sum = 0;
        foreach (var s in frame) sum += (double)s * s;
        return Math.Sqrt(sum / frame.Length) / 32768;
    }

    void Step(short[] frame)
    {
        double level = Rms(frame);
        var g = gate;
        line = g?.Threshold ?? Threshold;
        bool loud = g?.Voiced(level, Frame / (double)Rate) ?? level >= line;
        double now = consumed / (double)Rate;
        consumed += frame.Length;

        if (current.Count == 0)
        {
            if (!loud)
            {
                idle.Enqueue(level);
                while (idle.Count > (int)(Pause * Rate / Frame)) idle.Dequeue();
                before.Enqueue((frame, level));
                while (before.Count > PreRoll * Rate / Frame) before.Dequeue();
                return;
            }
            currentStart = now - before.Count * Frame / (double)Rate;
            lead = idle.Count > 0 ? idle.Min() : null;
            idle.Clear();
            foreach (var (f, l) in before) { current.AddRange(f); levels.Add(l); }
            before.Clear();
            quietFrames = 0; loudFrames = 0;
        }

        current.AddRange(frame);
        levels.Add(level);
        if (loud) { quietFrames = 0; loudFrames++; } else quietFrames++;

        if (quietFrames * Frame >= Pause * Rate)
        {
            Close(current.Count - quietFrames * Frame + (int)(Tail * Rate));
        }
        else if (current.Count >= MaxLength * Rate)
        {
            // The quietest frame in the last 2 s; the rest starts the next segment.
            int from = Math.Max(1, levels.Count - (int)(CutWindow * Rate / Frame));
            int cut = from;
            for (int i = from; i < levels.Count; i++) if (levels[i] < levels[cut]) cut = i;
            Close(cut * Frame);
        }
    }

    /// Steady sound just over the gate (a fan, hum, hiss) isn't speech: its frames barely vary
    /// (90th / 10th percentile about 1.1; speech, even over such a floor, 3 and up). Given one, Ming
    /// writes a stock sentence in the hint's language ("I'm going to show you a couple of things").
    /// Speech buried under steady noise goes too; system audio rarely carries it. Every frame from
    /// the first loud one to the last counts, the quiet ones held at the gate: counting only the
    /// loud ones dropped quiet speech (under about -30 dBFS), whose dips fall below the gate.
    /// A voice so quiet that its loudest frames barely clear the gate (about -38 dBFS: 6 of 6 lines
    /// lost in testing) still pauses between syllables, its quietest tenth of frames far under its
    /// median (8 dB and more); noise near the gate stays within about 6 dB of its median. So a flat
    /// top is steady only when it has no such dips, measured with quiet frames held at gate / 8.
    /// Very low rumble (brown noise with almost nothing over 20 Hz) can look like that and gets
    /// through more often than before (about 1 in 3 segments, was 1 in 5); what Ming makes of it
    /// still meets the hear filter (Translator.IsNoise).
    internal static bool IsSteady(IEnumerable<double> frameLevels, double? gate = null)
    {
        var all = frameLevels.ToList();
        var threshold = gate ?? Threshold;
        int first = all.FindIndex(l => l >= threshold), last = all.FindLastIndex(l => l >= threshold);
        if (first < 0 || last <= first) return false;
        var body = all.GetRange(first, last - first + 1);
        var top = body.Select(l => Math.Max(l, threshold)).Order().ToList();
        if (top[(int)(0.9 * (top.Count - 1))] >= Steady * top[(int)(0.1 * (top.Count - 1))]) return false;
        var low = body.Select(l => Math.Max(l, threshold / 8)).Order().ToList();
        return low[(int)(0.5 * (low.Count - 1))] < Dips * low[(int)(0.1 * (low.Count - 1))];
    }

    /// A short word on its own: a sound up to `Short` that rises out of real quiet and falls back
    /// into it (under gate / 4, about -52 dBFS, in the 0.6 s before it and in the pause after), and
    /// that swells and fades by 10 dB or more (90th / 10th percentile of its frames over gate / 4).
    /// Such a word ("Thanks.", "Good morning everyone,") is one smooth syllable or a run of voiced
    /// ones, so the steady test, which looks for dips inside, dropped it even at -26 dBFS; and a
    /// quiet one ("Thanks." at -36 dBFS) has under 0.25 s over the gate, so it needs `MinWord` over
    /// gate / 4 instead (a knock with a 150 ms tail has 0.15 s). A fan, hum or hiss is there on
    /// both sides; a short burst of one in silence stays within about 9 dB (brown noise), 5 dB (the
    /// rest), and Ming makes up a sentence for a hum or fan burst. Not for a forced cut, whose end
    /// isn't a pause.
    internal bool IsWord(List<double> frameLevels, double gate)
    {
        int first = frameLevels.FindIndex(l => l >= gate), last = frameLevels.FindLastIndex(l => l >= gate);
        if (first < 0 || (last - first + 1) * Frame > Short * Rate) return false;
        double quiet = gate / 4;
        if (lead is not { } q || q > quiet || last + 1 >= frameLevels.Count || frameLevels.Skip(last + 1).Min() > quiet) return false;
        int from = frameLevels.FindIndex(l => l >= quiet), to = frameLevels.FindLastIndex(l => l >= quiet);
        var body = frameLevels.GetRange(from, to - from + 1).Select(l => Math.Max(l, gate / 8)).Order().ToList();
        return body[(int)(0.9 * (body.Count - 1))] >= Swell * body[(int)(0.1 * (body.Count - 1))];
    }

    /// Emits `current[..end]` and keeps what follows as the start of the next segment.
    void Close(int end)
    {
        end = Math.Clamp(end, 0, current.Count);
        var samples = current.GetRange(0, end).ToArray();
        var rest = current.GetRange(end, current.Count - end);
        var restLevels = levels.GetRange(end / Frame, levels.Count - end / Frame);
        double start = currentStart;
        var sent = levels.GetRange(0, Math.Min(levels.Count, end / Frame));
        bool speech = IsWord(levels, line)
            ? sent.Count(l => l >= line / 4) * Frame >= MinWord * Rate
            : loudFrames * Frame >= MinSpeech * Rate && !IsSteady(sent, line);
        current.Clear(); levels.Clear();
        quietFrames = 0; loudFrames = 0;
        if (speech) Emitted?.Invoke(new Segment(++index, Math.Round(start, 3), samples));

        // A forced cut carries on with the remainder; after a pause the remainder is silence.
        if (restLevels.Any(l => l >= line))
        {
            currentStart = start + end / (double)Rate;
            lead = null;
            current.AddRange(rest);
            levels.AddRange(restLevels);
            int trailing = 0;
            for (int i = levels.Count - 1; i >= 0 && levels[i] < line; i--) trailing++;
            quietFrames = trailing;
            loudFrames = levels.Count(l => l >= line);
        }
    }
}
