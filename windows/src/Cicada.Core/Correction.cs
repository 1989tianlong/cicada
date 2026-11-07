using System.Globalization;
using System.Text.Json.Nodes;

namespace Cicada;

/// 改正听错的词: deciding which of the AI service's proposed fixes to take, without asking it again,
/// and the line as shown once they are in. The Mac's Correction.swift, rule for rule. The service's
/// own confidence isn't enough (in a 21-minute test it rated "快销 → 区块" and "苍蝇 → 方向" above
/// 0.85), so a Chinese word may only be swapped for one that sounds alike (pinyin), a Latin word
/// only for a near spelling, and a new name only once the user says so.
public static class Correction
{
    public sealed record Edit(string From, string To, double Confidence);

    public enum Verdict { Apply, Ask, Drop }

    public const double ApplyAt = 0.6, SpellingAt = 0.8, AskAt = 0.8;

    /// Characters as the Mac counts them (grapheme clusters, Swift's Character).
    static string[] Chars(string s)
    {
        var e = StringInfo.GetTextElementEnumerator(s);
        var out_ = new List<string>();
        while (e.MoveNext()) out_.Add(e.GetTextElement());
        return [.. out_];
    }

    public static int Length(string s) => new StringInfo(s).LengthInTextElements;

    static bool Word(string c) => c.Length == 1 && char.IsAsciiLetterOrDigit(c[0]);

    /// The part an edit changes, as a word: "解除质压" → "解除质押" is "质压" → "质押" (at least two
    /// characters, so one refusal doesn't block every 压 → 押), and a Latin word stays whole
    /// ("Un450P三" → "Uniswap V3", not "450P三" → "iswap V3").
    public static (string From, string To) Core(string from, string to)
    {
        var a = Chars(from); var b = Chars(to);
        int min = Math.Min(a.Length, b.Length);
        int i = 0;
        while (i < min && a[i] == b[i]) i++;
        int j = 0;
        while (j < min - i && a[a.Length - 1 - j] == b[b.Length - 1 - j]) j++;
        // Only a change that starts or ends inside a Latin word takes the rest of the word.
        bool FromEdge(int k) => (k < a.Length && Word(a[k])) || (k < b.Length && Word(b[k]));
        if (FromEdge(i)) while (i > 0 && Word(a[i - 1])) i--;
        if ((a.Length - j - 1 >= 0 && Word(a[a.Length - j - 1])) || (b.Length - j - 1 >= 0 && Word(b[b.Length - j - 1])))
            while (j > 0 && Word(a[a.Length - j])) j--;
        // Two characters at least, taken from the Chinese side: "FFT制押" → "FFT质押" is "制押" → "质押".
        while (a.Length - j - i < 2 || b.Length - j - i < 2)
        {
            if (j > 0 && !Word(a[a.Length - j])) j--;
            else if (i > 0 && !Word(a[i - 1])) i--;
            else break;
        }
        return (string.Concat(a[i..(a.Length - j)]), string.Concat(b[i..(b.Length - j)]));
    }

    /// `known`: the user confirmed this heard form for this word (the word list). `rejected`: they
    /// said no to it in this meeting.
    public static Verdict Decide(Edit e, Func<string, string, bool> known, Func<string, string, bool> rejected)
    {
        var c = Core(e.From, e.To);
        if (c.From.Length == 0 || c.To.Length == 0 || c.From.ToLowerInvariant() == c.To.ToLowerInvariant()
            || rejected(e.From, e.To) || rejected(c.From, c.To)) return Verdict.Drop;
        if (known(e.From, e.To) || known(c.From, c.To)) return Verdict.Apply;
        if (e.Confidence < ApplyAt) return Verdict.Drop;
        bool latinFrom = c.From.Any(char.IsAsciiLetter), latinTo = c.To.Any(char.IsAsciiLetter);
        if (!latinFrom && !latinTo && Han(c.From) && Han(c.To) && SoundsAlike(c.From, c.To)) return Verdict.Apply;
        if (latinFrom && latinTo && c.From.All(char.IsAscii) && c.To.All(char.IsAscii) && e.Confidence >= SpellingAt
            && Distance(c.From.ToLowerInvariant(), c.To.ToLowerInvariant()) <= 2) return Verdict.Apply;
        // A new name (Chinese heard as a Latin name, or a respelled one): sound can't check it.
        if (latinTo && e.Confidence >= AskAt) return Verdict.Ask;
        return Verdict.Drop;
    }

    // Toneless pinyin for every CJK Unified Ideograph (U+4E00–U+9FFF) that has a reading: Windows
    // has no Mandarin transform of its own, so this table was generated once from Apple's ICU/CLDR
    // Han-Latin transform (the one the Mac uses, kCFStringTransformMandarinLatin with diacritics
    // stripped). Data, not a dependency: one "<char>\t<syllable>" per line.
    static readonly Lazy<Dictionary<char, string>> Table = new(() =>
    {
        var d = new Dictionary<char, string>();
        using var stream = typeof(Correction).Assembly.GetManifestResourceStream("pinyin.tsv");
        if (stream is null) return d;
        using var reader = new StreamReader(stream);
        while (reader.ReadLine() is { } line)
            if (line.Length > 2 && line[1] == '\t') d[line[0]] = line[2..];
        return d;
    });

    /// Toneless pinyin, one syllable per character; a character the table doesn't read stays itself.
    public static string[] Pinyin(string s) =>
        Chars(s).Select(ch => ch.Length == 1 && Table.Value.TryGetValue(ch[0], out var p) ? p : ch.ToLowerInvariant().Trim()).ToArray();

    static readonly string[] Initials = ["zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q",
                                         "x", "r", "z", "c", "s", "y", "w"];

    static (string, string) Split(string syllable)
    {
        foreach (var i in Initials) if (syllable.StartsWith(i, StringComparison.Ordinal)) return (i, syllable[i.Length..]);
        return ("", syllable);
    }

    /// Same number of syllables, and on average three quarters alike: a syllable counts whole when
    /// equal, half when its initial or its final matches (质/追, 销/照). 苍蝇/方向 is a quarter.
    public static bool SoundsAlike(string a, string b)
    {
        var x = Pinyin(a); var y = Pinyin(b);
        if (x.Length != y.Length || x.Length == 0) return false;
        double score = 0;
        for (int k = 0; k < x.Length; k++)
        {
            if (x[k] == y[k]) { score += 1; continue; }
            var (i1, f1) = Split(x[k]); var (i2, f2) = Split(y[k]);
            if (i1 == i2 || f1 == f2 || f1.Replace("ng", "n") == f2.Replace("ng", "n")) score += 0.5;
        }
        return score / x.Length >= 0.75;
    }

    /// Every character an ideograph (Swift's isIdeographic).
    public static bool Han(string s) => s.EnumerateRunes().All(r => r.Value is >= 0x3400 and <= 0x4DBF or >= 0x4E00 and <= 0x9FFF
        or >= 0xF900 and <= 0xFAFF or >= 0x20000 and <= 0x3134F or 0x3006 or 0x3007 or >= 0x3021 and <= 0x3029);

    public static int Distance(string a, string b)
    {
        var row = Enumerable.Range(0, b.Length + 1).ToArray();
        for (int i = 0; i < a.Length; i++)
        {
            int prev = row[0];
            row[0] = i + 1;
            for (int j = 0; j < b.Length; j++)
            {
                int cur = row[j + 1];
                row[j + 1] = Math.Min(Math.Min(row[j + 1] + 1, row[j] + 1), prev + (a[i] == b[j] ? 0 : 1));
                prev = cur;
            }
        }
        return row[b.Length];
    }

    /// The line as shown: each applied fix replaces its words where they still are. The marks are
    /// the replaced words (start, length in the shown text), for the dotted underline.
    public static (string Text, List<(int Start, int Length)> Marks) Apply(IReadOnlyList<LineFix> fixes, string src)
    {
        var text = src;
        var spans = new List<(string Word, int At)>();
        // The user's own last: written against the line as it was shown, other fixes in.
        foreach (var f in fixes.Where(f => f.User != true).Concat(fixes.Where(f => f.User == true)))
        {
            if (!f.Applied || f.From.Length == 0) continue;
            var at = text.IndexOf(f.From, StringComparison.Ordinal);
            if (at < 0) continue;
            var delta = f.To.Length - f.From.Length;
            for (int k = 0; k < spans.Count; k++) if (spans[k].At > at) spans[k] = (spans[k].Word, spans[k].At + delta);
            text = text[..at] + f.To + text[(at + f.From.Length)..];
            spans.Add((f.To, at));
        }
        var marks = spans.Where(s => s.At + s.Word.Length <= text.Length).Select(s => (s.At, s.Word.Length)).OrderBy(m => m.Item1).ToList();
        return (text, marks);
    }

    /// The service's reply to a sentence sent with fixes asked for:
    /// {"translation": "…", "fixes": [{"from", "to", "confidence"}]}. Null when it isn't that shape,
    /// and the caller treats the reply as a failed one. Fixes whose words aren't in the subtitle are
    /// dropped: the service sometimes quotes them rephrased.
    public static (string Translation, List<Edit> Edits)? Parse(string reply, string subtitle)
    {
        // Asked for JSON in the prompt only: take the outermost {…}, fenced or not.
        int open = reply.IndexOf('{'), close = reply.LastIndexOf('}');
        if (open < 0 || close <= open) return null;
        JsonObject? o;
        try { o = JsonNode.Parse(reply[open..(close + 1)]) as JsonObject; } catch { return null; }
        if (o?["translation"] is not JsonValue tv || !tv.TryGetValue<string>(out var translation)) return null;
        var edits = new List<Edit>();
        if (o["fixes"] is JsonArray raw)
            foreach (var f in raw.OfType<JsonObject>())
            {
                if (f["from"] is not JsonValue fv || !fv.TryGetValue<string>(out var from) || f["to"] is not JsonValue tov || !tov.TryGetValue<string>(out var to)) continue;
                if (from.Length == 0 || from == to || !subtitle.Contains(from, StringComparison.Ordinal)) continue;
                double c = f["confidence"] is JsonValue cv && cv.TryGetValue<double>(out var d) ? d : 0;
                edits.Add(new Edit(from, to, c));
            }
        return (translation.Trim(), edits);
    }

    /// What a line's fixes become after the service answered for it again (a joined line): the
    /// user's decisions stay (said no, said yes, wrote it), and of the rest only what is proposed
    /// again. So a pass that no longer proposes a fix takes it back.
    public static List<LineFix> Merge(IReadOnlyList<LineFix> old, IReadOnlyList<LineFix> fresh)
    {
        var kept = old.Where(f => f.Off == true || f.User == true).ToList();
        var added = fresh.Where(n =>
        {
            var c = Core(n.From, n.To);
            return !kept.Any(k => k.From == n.From || Core(k.From, k.To).From == c.From);
        });
        return [.. kept, .. added];
    }

    /// 改这句…: the user rewrote the line as shown. What changed, as a fix on top of the others,
    /// and the heard form it replaces (for the word list): the words in `src` when they are there,
    /// else the heard words of the fix the user corrected again ("莫纳" → "Morpho" → "Monad").
    public static (LineFix Fix, string Heard)? UserEdit(string shown, string edited, string src, IReadOnlyList<LineFix> fixes)
    {
        var now = edited.Trim();
        if (now.Length == 0 || now == shown) return null;
        var c = Core(shown, now);
        if (c.From.Length == 0 || c.To.Length == 0) return null;
        var heard = c.From;
        if (!src.Contains(c.From, StringComparison.Ordinal) && fixes.FirstOrDefault(f => f.Applied && c.From.Contains(f.To, StringComparison.Ordinal)) is { } earlier)
            heard = Core(earlier.From, earlier.To).From;
        return (new LineFix(c.From, c.To, user: true), heard);
    }
}
