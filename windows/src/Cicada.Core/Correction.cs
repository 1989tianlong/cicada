namespace Cicada;

/// 改正听错的词: which of the AI service's proposed fixes a line takes, and the line as shown once
/// they are in. The Mac's Correction.swift, rule for rule.
public static class Correction
{
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
}
