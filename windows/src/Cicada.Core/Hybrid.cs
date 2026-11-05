namespace Cicada;

// 电脑和会议室: the room side's echo handling, and how its lines are shown (RoomMic.swift,
// EchoMatch.swift, RecordList.swift).

/// 电脑和会议室 without echo cancellation (Windows has none we can use): while the computer plays
/// speech, the room mic hears it again from the speakers. The computer's side `Hold`s the gate on
/// every loud buffer; the room mic hears silence until `Hang` after the last one. Room speech over a
/// remote speaker is lost this way; EchoMatch catches what still gets through.
public sealed class EchoGate(Func<double>? clock = null)
{
    public const double Hang = 0.4;
    /// Seconds; a monotonic clock shared with EchoMatch's times.
    public readonly Func<double> Clock = clock ?? (() => Environment.TickCount64 / 1000.0);
    readonly object gate = new();
    double until = double.NegativeInfinity;

    /// When the computer last played something loud.
    public double LastLoud { get { lock (gate) return until - Hang; } }

    public void Hold() { var now = Clock(); lock (gate) until = Math.Max(until, now + Hang); }
    public bool Closed { get { var now = Clock(); lock (gate) return now < until; } }
}

/// 电脑和会议室's last line of defence against hearing a remote sentence twice: once from the
/// computer's audio, once more from the speakers into the room mic. A room line made mostly of
/// what the computer played around the same time is dropped (EchoMatch.swift, same numbers).
public static class EchoMatch
{
    /// Times in seconds on EchoGate's clock.
    public sealed record Heard(string Text, double Start, double End);

    /// Seconds around the room line where the computer's lines count.
    public const double Window = 3.0;
    /// How long a room line waits for the computer's line it may echo.
    public const double Hold = 2.5;
    /// Share of the room line found in the computer's lines that makes it an echo.
    public const double Contained = 0.6;

    public static bool IsEcho(Heard room, IEnumerable<Heard> online)
    {
        var near = online.Where(o => o.End >= room.Start - Window && o.Start <= room.End + Window).ToList();
        if (near.Count == 0) return false;
        var r = Units(room.Text);
        if (r.Count == 0) return false;
        var o = near.Select(n => Units(n.Text)).ToList();
        // A word or two ("OK", "对"): the very same words near it.
        if (r.Count <= 2) return o.Any(x => x.SequenceEqual(r));
        var mine = Pairs(r).ToHashSet();
        var theirs = o.SelectMany(Pairs).ToHashSet();
        return (double)mine.Count(theirs.Contains) / mine.Count >= Contained;
    }

    /// Lower-case words, each CJK character on its own; punctuation and spacing don't count.
    public static List<string> Units(string text)
    {
        var output = new List<string>();
        var word = new System.Text.StringBuilder();
        foreach (var rune in text.ToLowerInvariant().EnumerateRunes())
        {
            if (Cjk(rune.Value))
            {
                if (word.Length > 0) { output.Add(word.ToString()); word.Clear(); }
                output.Add(rune.ToString());
            }
            else if (System.Text.Rune.IsLetterOrDigit(rune)) word.Append(rune.ToString());
            else if (word.Length > 0) { output.Add(word.ToString()); word.Clear(); }
        }
        if (word.Length > 0) output.Add(word.ToString());
        return output;
    }

    static IEnumerable<string> Pairs(List<string> u) => u.Count < 2 ? u : Enumerable.Range(1, u.Count - 1).Select(i => u[i - 1] + " " + u[i]);

    static bool Cjk(int v) => v is >= 0x3040 and <= 0x30FF or >= 0x3400 and <= 0x4DBF or >= 0x4E00 and <= 0x9FFF or >= 0xAC00 and <= 0xD7AF or >= 0xF900 and <= 0xFAFF;
}

/// The computer's recent lines, for the room side to check its own against.
public sealed class EchoFilter(EchoGate gate)
{
    public readonly EchoGate Gate = gate;
    readonly List<EchoMatch.Heard> online = [];

    public void Online(EchoMatch.Heard h)
    {
        lock (online)
        {
            online.Add(h);
            online.RemoveAll(o => o.End < h.End - 20);
        }
    }

    public bool IsEcho(EchoMatch.Heard room) { lock (online) return EchoMatch.IsEcho(room, online); }

    /// The computer played nothing loud around this room line: there is nothing for it to echo.
    public bool Quiet(EchoMatch.Heard room) => Gate.LastLoud < room.Start - EchoMatch.Window;
}

/// 线上也有人？: listening to the room alone while a meeting app is in a call, so people online are
/// likely speaking through it. Once a meeting.
public static class RoomPrompt
{
    public static bool AsksOnline(bool roomOnly, bool answered, bool inCall) => roomOnly && !answered && inCall;
}

/// A meeting that heard both: each of the other side's lines says where (RecordList.swift).
public static class Places
{
    /// The room mic and the computer's audio both brought in the other side's lines.
    public static bool HeardBoth(IEnumerable<TranscriptLine> lines)
    {
        bool room = false, computer = false;
        foreach (var l in lines)
        {
            if (l.Speaker != "them") continue;
            if (l.Via == "room") room = true; else computer = true;
            if (room && computer) return true;
        }
        return false;
    }

    /// The other side's lines where the place changes from the line before: their label shows again.
    public static HashSet<string> Starts(IEnumerable<TranscriptLine> lines)
    {
        var output = new HashSet<string>();
        string? last = "\0";
        foreach (var l in lines)
        {
            var key = l.Speaker == "me" ? "me" : l.Via;
            if (l.Speaker != "me" && key != last) output.Add(l.Id);
            last = key;
        }
        return output;
    }

    public static string Place(TranscriptLine l) => l.Via == "room" ? Strings.L("现场") : Strings.L("线上");
}
