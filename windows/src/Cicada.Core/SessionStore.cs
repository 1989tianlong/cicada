using System.Globalization;
using System.Text;

namespace Cicada;

/// The meeting records: one folder per meeting under Sessions\<yyyyMMdd-HHmmss>\ with
/// session.json, as on the Mac. Saves are debounced by 1.5 s; a meeting with no lines is removed
/// when it ends. Thread-safe; `Changed` fires on whichever thread made the change.
public sealed class SessionStore
{
    readonly object gate = new();
    readonly Dictionary<string, Session> sessions = [];
    readonly HashSet<string> dirty = [];
    Timer? saveTimer;
    public event Action<string>? Changed;

    public SessionStore() { Load(); }

    static string Folder(string id) => Path.Combine(Paths.Sessions, id);
    static string FileOf(string id) => Path.Combine(Folder(id), "session.json");

    void Load()
    {
        if (!Directory.Exists(Paths.Sessions)) return;
        foreach (var dir in Directory.GetDirectories(Paths.Sessions))
        {
            var file = Path.Combine(dir, "session.json");
            if (!File.Exists(file)) continue;
            try
            {
                if (Json.Read<Session>(File.ReadAllText(file)) is { } s) sessions[s.Id] = s;
            }
            catch (Exception e) { Log.Debug($"store: skipped {Path.GetFileName(dir)}: {e.GetType().Name}"); }
        }
    }

    /// Newest first.
    public List<Session> All()
    {
        lock (gate) return sessions.Values.OrderByDescending(s => s.StartedAt).ToList();
    }

    public Session? Get(string id)
    {
        lock (gate) return sessions.GetValueOrDefault(id);
    }

    public Session Begin(DateTimeOffset? at = null)
    {
        var start = at ?? DateTimeOffset.Now;
        var id = start.ToLocalTime().ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
        var s = new Session { Id = id, Title = DefaultTitle(start), StartedAt = start, HasAudio = false };
        lock (gate) sessions[id] = s;
        return s;
    }

    /// The stored default title is always Chinese ("会议 11月1日 14:30"), as on the Mac; the UI
    /// shows DisplayTitle instead.
    public static string DefaultTitle(DateTimeOffset at) =>
        "会议 " + at.ToLocalTime().ToString("M月d日 HH:mm", CultureInfo.InvariantCulture);

    /// The user's own title, else the date and the name the notes gave the meeting, else the
    /// default title in the UI language (Session.displayTitle).
    public static string DisplayTitle(Session s)
    {
        if (s.Renamed ?? !s.Title.StartsWith("会议 ")) return s.Title;
        var local = s.StartedAt.ToLocalTime();
        var ui = Strings.Culture;
        if (string.IsNullOrEmpty(s.Notes?.Title))
            return Strings.L("会议") + " " + local.ToString(Strings.L("M月d日 HH:mm"), ui);
        var date = local.Year == DateTimeOffset.Now.Year ? local.ToString(Strings.L("M月d日"), ui) : local.ToString(Strings.L("yyyy年M月d日"), ui);
        return $"{date} {s.Notes!.Title}";
    }

    public void Append(string id, TranscriptLine line) => Mutate(id, s => s.Lines.Add(line));

    public void Replace(string id, TranscriptLine line) => Mutate(id, s =>
    {
        int i = s.Lines.FindIndex(l => l.Id == line.Id);
        if (i >= 0) s.Lines[i] = line;
    });

    public void SetNotes(string id, MeetingNotes notes) => Mutate(id, s => s.Notes = notes);

    public void Rename(string id, string title) => Mutate(id, s => { s.Title = title.Trim(); s.Renamed = true; });

    /// The meeting ended: kept if anything was said, removed otherwise.
    public void End(string id)
    {
        bool empty;
        lock (gate)
        {
            if (!sessions.TryGetValue(id, out var s)) return;
            s.EndedAt = DateTimeOffset.Now;
            empty = s.Lines.Count == 0;
        }
        if (empty) Delete(id);
        else { MarkDirty(id); Flush(); }
    }

    public void Delete(string id)
    {
        lock (gate) { sessions.Remove(id); dirty.Remove(id); }
        try { if (Directory.Exists(Folder(id))) Directory.Delete(Folder(id), recursive: true); } catch (Exception e) { Log.Debug($"store: delete failed {e.GetType().Name}"); }
        Changed?.Invoke(id);
    }

    void Mutate(string id, Action<Session> change)
    {
        lock (gate)
        {
            if (!sessions.TryGetValue(id, out var s)) return;
            change(s);
        }
        MarkDirty(id);
        Changed?.Invoke(id);
    }

    void MarkDirty(string id)
    {
        lock (gate)
        {
            dirty.Add(id);
            saveTimer ??= new Timer(_ => Flush(), null, Timeout.Infinite, Timeout.Infinite);
            saveTimer.Change(1500, Timeout.Infinite);
        }
    }

    /// Writes every changed record now (also on quit).
    public void Flush()
    {
        List<(string id, string json)> writes;
        lock (gate)
        {
            writes = dirty.Where(sessions.ContainsKey).Select(id => (id, Json.Write(sessions[id]))).ToList();
            dirty.Clear();
        }
        foreach (var (id, json) in writes)
        {
            try
            {
                Directory.CreateDirectory(Folder(id));
                var tmp = FileOf(id) + ".tmp";
                File.WriteAllText(tmp, json, new UTF8Encoding(false));
                File.Move(tmp, FileOf(id), overwrite: true);
            }
            catch (Exception e) { Log.Debug($"store: save failed {e.GetType().Name}"); }
        }
    }

    // MARK: Export

    /// The record as Markdown: notes, then the bilingual transcript.
    public static string Markdown(Session s)
    {
        var b = new StringBuilder();
        b.AppendLine($"# {DisplayTitle(s)}").AppendLine();
        b.AppendLine(s.StartedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture)).AppendLine();
        if (s.Notes is { IsEmpty: false } n)
        {
            b.AppendLine($"## {Strings.L("纪要")}").AppendLine().AppendLine(n.Summary).AppendLine();
            foreach (var t in n.Topics)
            {
                b.AppendLine($"### {Languages.Clock(t.Start)} {t.Title}").AppendLine();
                if (t.Summary.Length > 0) b.AppendLine(t.Summary).AppendLine();
                foreach (var p in t.Points) b.AppendLine($"- {p}");
                b.AppendLine();
            }
            if (n.Conclusions.Count > 0)
            {
                b.AppendLine($"### {Strings.L("结论")}").AppendLine();
                foreach (var c in n.Conclusions) b.AppendLine($"- {c.Text}");
                b.AppendLine();
            }
            if (n.Todos.Count > 0)
            {
                b.AppendLine($"### {Strings.L("待办")}").AppendLine();
                foreach (var t in n.Todos) b.AppendLine($"- [ ] {t.Text}{(t.Owner is null ? "" : $"（{t.Owner}）")}");
                b.AppendLine();
            }
        }
        b.AppendLine($"## {Strings.L("文字记录")}").AppendLine();
        foreach (var l in s.Lines)
        {
            b.AppendLine($"**{Languages.Clock(l.T)}** {l.Src}  ");
            if (!string.IsNullOrEmpty(l.Dst) && l.Dst != l.Src) b.AppendLine($"{l.Dst}");
            b.AppendLine();
        }
        return b.ToString();
    }
}
