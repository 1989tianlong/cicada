// Unit tests for Cicada.Core: `scripts/test.sh` (or `dotnet run --project tests/Cicada.Tests`).
// Each test is a method below; a failed Check throws and the runner reports it. No network:
// LingClient runs against a fake handler.
using System.Net;
using System.Reflection;
using System.Text.Json.Nodes;
using Cicada;

Environment.SetEnvironmentVariable("CICADA_HOME", Path.Combine(Path.GetTempPath(), "cicada-tests-" + Environment.ProcessId));
Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), "zh-Hans");
int passed = 0, failed = 0;
foreach (var m in typeof(Tests).GetMethods(BindingFlags.Public | BindingFlags.Static).OrderBy(m => m.MetadataToken))
{
    try
    {
        if (m.Invoke(null, null) is Task t) await t;
        passed++;
    }
    catch (Exception e)
    {
        failed++;
        var inner = e is TargetInvocationException { InnerException: { } i } ? i : e;
        Console.WriteLine($"FAIL {m.Name}: {inner.Message}");
    }
}
try { Directory.Delete(Paths.Root, true); } catch { }
Console.WriteLine($"{passed} passed, {failed} failed");
return failed == 0 ? 0 : 1;

static class Tests
{
    static void Check(bool ok, string what) { if (!ok) throw new Exception(what); }
    static void Equal<T>(T expected, T actual, string what)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new Exception($"{what}: expected «{expected}», got «{actual}»");
    }

    // MARK: Records

    public static void SessionJsonMatchesTheMac()
    {
        var s = new Session
        {
            Id = "20261103-101611", Title = "会议 11月3日 10:16", HasAudio = false,
            StartedAt = DateTimeOffset.Parse("2026-11-03T15:16:11Z"),
            Lines = [new TranscriptLine { Id = "h1-1", T = 2.7636849899291995, Src = "你好/世界", SrcLang = "zh-CN", DstLang = "en" }],
        };
        var json = Json.Write(s);
        Check(json.Contains("\"startedAt\": \"2026-11-03T15:16:11Z\""), "dates are whole-second ISO-8601 UTC");
        Check(json.Contains("你好/世界"), "Chinese and slashes are written as they are");
        Check(!json.Contains("\"dst\""), "nil optionals are left out");
        Check(!json.Contains("endedAt") && !json.Contains("notes"), "absent fields stay absent");
        Check(json.Contains("2.7636849899291995"), "doubles keep full precision");
        var keys = JsonNode.Parse(json)!.AsObject().Select(p => p.Key).ToList();
        Check(keys.SequenceEqual(keys.Order(StringComparer.Ordinal)), "keys are sorted like the Mac's");
        var lineKeys = JsonNode.Parse(json)!["lines"]![0]!.AsObject().Select(p => p.Key).ToList();
        Check(lineKeys.SequenceEqual(lineKeys.Order(StringComparer.Ordinal)), "line keys are sorted");
    }

    public static void ReadsAMacRecord()
    {
        const string mac = """
        {
          "endedAt" : "2026-11-02T15:24:12Z",
          "hasAudio" : true,
          "id" : "20261102-101639",
          "lines" : [
            {
              "dst" : "Hello",
              "dstLang" : "en",
              "id" : "h1-1",
              "speaker" : "them",
              "src" : "你好",
              "srcLang" : "zh-CN",
              "t" : 2.5,
              "voice" : 1
            }
          ],
          "notes" : {
            "conclusions" : [ ], "covered" : 1, "final" : true, "summary" : "总结",
            "terms" : [ { "heard" : [ ], "name" : "鸟哥", "note" : "分享者" } ],
            "title" : "标题", "todos" : [ { "owner" : "你", "support" : 3, "t" : 202.4, "text" : "记录" } ],
            "topics" : [ { "pointTimes" : [ 12.4, null ], "points" : [ "a", "b" ], "start" : 0, "summary" : "s", "title" : "t" } ],
            "updatedAt" : "2026-11-02T15:24:40Z"
          },
          "startedAt" : "2026-11-02T15:16:39Z",
          "title" : "会议 11月2日 10:16",
          "voiceNames" : { "1" : "Emma" }
        }
        """;
        var s = Json.Read<Session>(mac)!;
        Equal(1, s.Lines.Count, "lines");
        Equal(1, s.Lines[0].Voice, "voice");
        Equal("Emma", s.VoiceNames!["1"], "voice names");
        Equal(12.4, s.Notes!.Topics[0].PointTime(0), "point time");
        Equal(null, s.Notes!.Topics[0].PointTime(1), "missing point time");
        Check(JsonNode.DeepEquals(JsonNode.Parse(mac), JsonNode.Parse(Json.Write(s))), "written back unchanged");
    }

    public static void StoreSavesAndDropsEmptyMeetings()
    {
        var store = new SessionStore();
        var empty = store.Begin(DateTimeOffset.Parse("2026-01-01T01:00:00Z"));
        store.End(empty.Id);
        Check(store.Get(empty.Id) is null && !Directory.Exists(Path.Combine(Paths.Sessions, empty.Id)), "an empty meeting is removed");
        var s = store.Begin(DateTimeOffset.Parse("2026-01-01T02:00:00Z"));
        store.Append(s.Id, new TranscriptLine { Id = "h1-1", Src = "hi", SrcLang = "en", DstLang = "zh-CN" });
        store.End(s.Id);
        var file = Path.Combine(Paths.Sessions, s.Id, "session.json");
        Check(File.Exists(file), "record written on end");
        Equal(1, Json.Read<Session>(File.ReadAllText(file))!.Lines.Count, "line saved");
        Check(new SessionStore().Get(s.Id) is not null, "loaded again");
        Check(s.Title.StartsWith("会议 "), "default title is the Mac's Chinese form");
    }

    public static void DisplayTitle()
    {
        var s = new Session { Title = "会议 1月1日 10:00", StartedAt = DateTimeOffset.Now, Notes = new MeetingNotes { Title = "路线评审", Summary = "x" } };
        Check(SessionStore.DisplayTitle(s).EndsWith(" 路线评审"), "notes' name after the date");
        s.Renamed = true; s.Title = "我的会";
        Equal("我的会", SessionStore.DisplayTitle(s), "the user's title wins");
        Check(SessionStore.Markdown(s).Split('\n')[0].TrimEnd() == "# 我的会", "the export is headed by the shown title");
    }

    // MARK: Hearing

    public static void ParsesMingReplies()
    {
        var h = Translator.ParseHeard("LANG: en\nORIGINAL: Hello there.\nTRANSLATION: 你好。", "zh-CN", null)!;
        Equal("en", h.Lang, "lang"); Equal("Hello there.", h.Original, "original"); Equal("你好。", h.Translation, "translation");
        Equal(null, Translator.ParseHeard("作为一个人工智能语言模型，这个问题超出我目前的学习范围了", "zh-CN", null), "no labelled lines");
        Equal(null, Translator.ParseHeard("LANG: en\nORIGINAL: NONE\nTRANSLATION: 无", "zh-CN", null), "no speech");
        Equal(null, Translator.ParseHeard("LANG: en\nORIGINAL: ...\nTRANSLATION: …", "zh-CN", null), "punctuation only");
        var same = Translator.ParseHeard("LANG: zh\nORIGINAL: 好的\nTRANSLATION: OK", "zh-CN", "en")!;
        Equal("zh-CN", same.Lang, "zh normalized"); Equal("好的", same.Translation, "already in the target: kept as is");
        var wrong = Translator.ParseHeard("LANG: en\nORIGINAL: Hi\nTRANSLATION: Hi again", "zh-CN", null)!;
        Equal(null, wrong.Translation, "a translation not in Chinese is dropped for the text translator");
        Equal("ja", Translator.ParseHeard("lang: ja-JP\noriginal: はい\ntranslation: 是", "zh-CN", null)!.Lang, "labels in any case");
    }

    public static void NormalizesLanguages()
    {
        Equal("zh-CN", Languages.Normalize("zh-Hans", "en"), "zh-Hans");
        Equal("zh-TW", Languages.Normalize("zh-TW", "en"), "zh-TW");
        Equal("zh-CN", Languages.Normalize("cmn", "en"), "cmn");
        Equal("en", Languages.Normalize("en-US", "ja"), "en-US");
        Equal("ja", Languages.Normalize("", "ja"), "empty falls back");
        Equal("zh-TW", Languages.FromSystem("zh-Hant-HK"), "system zh-Hant");
        Equal("zh-CN", Languages.FromSystem("zh-CN"), "system zh-CN");
        Equal("en", Languages.FromSystem("en-GB"), "system en");
        Equal("Simplified Chinese", Languages.EnglishName("zh-CN"), "english name");
        Equal("Japanese", Languages.EnglishName("ja"), "english name ja");
        Equal("01:05", Languages.Clock(65.9), "clock"); Equal("1:00:01", Languages.Clock(3601), "clock hours");
    }

    public static void CleansTranslations()
    {
        Equal("你好", Translator.CleanTranslation("Translation: 你好", "zh-CN"), "label stripped");
        Equal("你好", Translator.CleanTranslation("“你好”", "zh-CN"), "wrapping quotes");
        Equal("Hello", Translator.CleanTranslation("Here is the translation:\nHello", "en"), "remark line dropped");
        Equal(null, Translator.CleanTranslation("请提供需要翻译的字幕内容", "en"), "a request for input is not a translation");
        Equal(null, Translator.CleanTranslation("Hello", "zh-CN"), "wrong script");
        Equal("Done.", Translator.CleanTranslation("<think>x</think>Done.", "en"), "leaked reasoning");
    }

    public static void JoinsCutSentences()
    {
        var last = new TranscriptLine { Src = "We finished the migration and", SrcLang = "en" };
        Check(ListenEngine.Continues(last, 0.2, new Heard("en", "the error rate dropped.", null)), "mid-sentence cut joins");
        Check(!ListenEngine.Continues(last, 1.5, new Heard("en", "next", null)), "a long gap doesn't");
        Check(!ListenEngine.Continues(new TranscriptLine { Src = "Done.", SrcLang = "en" }, 0.1, new Heard("en", "Next", null)), "after a full stop doesn't");
        Check(!ListenEngine.Continues(last, 0.1, new Heard("ja", "はい", null)), "another language doesn't");
        Equal("我们完成了迁移", ListenEngine.Join("我们完成了", "迁移", "zh-CN"), "CJK joins without a space");
        Equal("a b", ListenEngine.Join("a ", " b", "en"), "others with one space");
    }

    // MARK: Segmenter

    static short[] Tone(double seconds, double amp = 0.3) =>
        Enumerable.Range(0, (int)(seconds * 16000)).Select(i => (short)(Math.Sin(2 * Math.PI * 300 * i / 16000) * amp * 32767)).ToArray();
    static short[] Silence(double seconds) => new short[(int)(seconds * 16000)];

    static List<Segment> Cut(params short[][] parts)
    {
        var seg = new Segmenter();
        var list = new List<Segment>();
        seg.Emitted += list.Add;
        foreach (var p in parts) for (int i = 0; i < p.Length; i += 1600) seg.Feed(p.AsSpan(i, Math.Min(1600, p.Length - i)));
        seg.Flush();
        return list;
    }

    public static void SegmentsOnPauses()
    {
        var list = Cut(Silence(0.5), Tone(2), Silence(1), Tone(1.5), Silence(1));
        Equal(2, list.Count, "two stretches");
        Check(Math.Abs(list[0].Start - 0.35) < 0.05, $"starts just before the speech (pre-roll), got {list[0].Start}");
        Check(Math.Abs(list[1].Start - 3.35) < 0.05, $"second start, got {list[1].Start}");
        Check(list[0].Seconds is > 2.1 and < 2.4, $"length with lead-in and tail, got {list[0].Seconds}");
    }

    public static void CutsLongSpeechAtItsQuietestMoment()
    {
        // 7 s of speech, a 0.3 s dip (shorter than a pause), 4 s more: one cut, at the dip.
        var list = Cut(Tone(7), Tone(0.3, 0.004), Tone(4), Silence(1));
        Equal(2, list.Count, "split in two");
        Check(list[0].Seconds is > 6.9 and < 7.4, $"cut inside the dip, got {list[0].Seconds}");
        Check(list.All(s => s.Seconds <= 8.0), "no segment over 8 s");
        Check(Math.Abs(list[1].Start - (list[0].Start + list[0].Seconds)) < 0.001, "the rest carries on without a gap");
    }

    public static void IgnoresClicks()
    {
        Equal(0, Cut(Silence(1), Tone(0.1), Silence(1)).Count, "under 0.25 s of sound is not speech");
        Equal(0, Cut(Tone(3, 0.002)).Count, "below the gate is silence");
    }

    public static void WavRoundTrip()
    {
        var pcm = Tone(0.5);
        var path = Path.Combine(Path.GetTempPath(), $"cicada-test-{Environment.ProcessId}.wav");
        File.WriteAllBytes(path, Wav.Bytes(pcm));
        Check(Wav.Read(path).SequenceEqual(pcm), "16 kHz mono reads back exactly");
        File.Delete(path);
        Equal(16000, Wav.Resample(new double[48000], 48000).Length, "48 kHz to 16 kHz");
    }

    // MARK: Notes

    public static void ParsesNotes()
    {
        const string reply = """
        ```json
        {"title": "“发布评审”", "summary": "讨论发布。",
         "topics": [{"start": 0, "title": "进展", "summary": "一句", "points": [{"text": "迁移完成", "evidence": ["L2"]}, "旧格式要点", {"text": "", "evidence": []}],
                     "fishbone": {"question": "为何延期", "branches": [{"label": "测试", "detail": "x", "t": 3, "evidence": ["L1"]}, {"label": "设计", "detail": "y", "evidence": ["L9"]}]}}],
         "conclusions": [{"text": "周五上线", "evidence": ["L1", "L2", "L99"]}],
         "todos": [{"text": "发说明", "owner": "", "evidence": ["L2"]}],
         "terms": [{"name": "Stripe", "note": "支付", "heard": ["Stripe", "Strip"]}]}
        ```
        """;
        var n = NotesEngine.Parse(reply, [1.0, 5.0], 0)!;
        Equal("发布评审", n.Title, "title quotes trimmed");
        Equal(2, n.Topics[0].Points.Count, "empty points dropped, plain strings kept");
        Equal(5.0, n.Topics[0].PointTime(0), "point time from evidence");
        Equal(null, n.Topics[0].PointTime(1), "no evidence, no time");
        Equal(2, n.Topics[0].Fishbone!.Branches.Count, "fishbone kept");
        Equal(0, n.Topics[0].Fishbone!.Branches[1].Support, "evidence beyond the transcript doesn't count");
        Equal(2, n.Conclusions[0].Support, "support counts real lines");
        Equal(null, n.Todos[0].Owner, "empty owner is none");
        Equal("Strip", string.Join(",", n.Terms[0].Heard), "the correct spelling isn't a mishearing");
        Equal(null, NotesEngine.Parse("not json", [], 0), "garbage");
        Equal(null, NotesEngine.Parse("{}", [], 0), "empty notes");
    }

    public static void KeepsEarliestTimes()
    {
        var old = new MeetingNotes { Topics = [new NoteTopic { Title = "t", Points = ["a"], PointTimes = [3] }], Todos = [new NoteItem { Text = "x", T = 2 }] };
        var next = new MeetingNotes { Topics = [new NoteTopic { Title = "t", Points = ["a", "b"], PointTimes = [9, null] }], Todos = [new NoteItem { Text = "x", T = 8 }] };
        NotesEngine.CarryTimes(old, next);
        Equal(3.0, next.Topics[0].PointTime(0), "a point keeps when it was first heard");
        Equal(2.0, next.Todos[0].T, "to-dos too");
    }

    public static void NotesPromptIsTheMacs()
    {
        var lines = new List<TranscriptLine> { new() { T = 1, Src = "你好", Speaker = "them" }, new() { T = 65, Src = "我来说", Speaker = "me" } };
        var p = NotesEngine.Prompt(new MeetingNotes(), lines, 0, "Simplified Chinese", final: false);
        Check(p.StartsWith("You keep notes for a meeting that is still going on. Update them with the new lines.\nWrite the notes in Simplified Chinese. Return JSON only.\n"), "opening");
        Check(p.Contains("[L1 00:01 对方] 你好\n[L2 01:05 你] 我来说"), "transcript lines");
        Check(p.Contains("These are the first lines: make one topic."), "first update");
        Check(p.EndsWith("No markdown, no text outside the JSON."), "ending");
        var f = NotesEngine.Prompt(new MeetingNotes(), lines, 0, "English", final: true);
        Check(f.Contains("This meeting ran 01:04: use at most 1 topic."), "final topic limit");
        Check(NotesEngine.Written(new MeetingNotes { Summary = "讨论发布 Stripe" }, "Simplified Chinese"), "Chinese notes");
        Check(!NotesEngine.Written(new MeetingNotes { Summary = "We talked" }, "Simplified Chinese"), "English isn't Chinese");
    }

    // MARK: Strings

    public static void LoadsTheMacsTranslations()
    {
        Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), "en");
        Equal("Live notes", Strings.L("实时纪要"), "an English string");
        Equal("没有这条", Strings.L("没有这条"), "missing keys show the Chinese");
        Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), "zh-Hans");
        Equal("实时纪要", Strings.L("实时纪要"), "Chinese is the key");
        Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), "en");
        var s = new Session { Title = "会议 11月4日 10:27", StartedAt = new DateTimeOffset(2026, 11, 4, 10, 27, 0, TimeSpan.Zero) };
        Check(!SessionStore.DisplayTitle(s).Contains('月'), "English dates whatever Windows' language: " + SessionStore.DisplayTitle(s));
        Strings.Load(Path.Combine(AppContext.BaseDirectory, "Resources"), "zh-Hans");
        var t = Strings.Parse("/* c */\n\"a \\\"b\\\"\" = \"x\\ny\";\n// line\n\"%@ 分钟\" = \"%@ min\";");
        Equal("x\ny", t["a \"b\""], "escapes");
        Equal("%@ min", t["%@ 分钟"], "placeholders kept");
        Equal("3 分钟", Strings.LF("%@ 分钟", 3), "LF fills %@");
    }

    // MARK: Ling

    sealed class Fake(Func<string, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public readonly List<(DateTime at, string body)> Calls = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancel)
        {
            var body = await request.Content!.ReadAsStringAsync(cancel);
            lock (Calls) Calls.Add((DateTime.UtcNow, body));
            return respond(body);
        }
    }

    static HttpResponseMessage Reply(string content, string? finish = "stop") => new(HttpStatusCode.OK)
    {
        Content = new StringContent(new JsonObject
        {
            ["choices"] = new JsonArray(new JsonObject { ["message"] = new JsonObject { ["content"] = content }, ["finish_reason"] = finish }),
            ["usage"] = new JsonObject { ["prompt_tokens"] = 1, ["completion_tokens"] = 1 },
        }.ToJsonString()),
    };

    static LingClient Client(Fake fake)
    {
        var key = new AIKey(new PlainProtector());
        key.Save("sk-test-0000000000");
        return new LingClient(key, fake);
    }

    public static async Task LingRequestShape()
    {
        var fake = new Fake(_ => Reply("ok"));
        var ling = Client(fake);
        await ling.Chat("the content", "Translate.", Priority.Translate, model: LingClient.AudioModel, audio: [1, 2, 3]);
        var body = JsonNode.Parse(fake.Calls[0].body)!;
        Equal("disabled", body["thinking"]!["type"]!.GetValue<string>(), "thinking disabled");
        Equal("system", body["messages"]![0]!["role"]!.GetValue<string>(), "content in the system message");
        Equal("the content", body["messages"]![0]!["content"]!.GetValue<string>(), "content");
        Equal("audio_url", body["messages"]![1]!["content"]![0]!["type"]!.GetValue<string>(), "audio first");
        Equal("data:audio/wav;base64,AQID", body["messages"]![1]!["content"]![0]!["audio_url"]!["url"]!.GetValue<string>(), "WAV as a data URL");
        Equal("Translate.", body["messages"]![1]!["content"]![1]!["text"]!.GetValue<string>(), "fixed instruction last");
    }

    public static async Task LingDropsHijackedAndRefusedReplies()
    {
        foreach (var (reply, finish) in new[] { ("根据现有检索证据，……", "stop"), ("作为一个人工智能语言模型，这个问题超出……", "stop"), ("fine", (string?)null) })
        {
            var ling = Client(new Fake(_ => Reply(reply, finish)));
            try { await ling.Chat("c", "i", Priority.Translate); throw new Exception($"accepted «{reply}»"); }
            catch (LingException e) { Equal(LingException.Kind.Hijacked, e.Failure, "dropped as hijacked"); }
        }
    }

    public static async Task LingRetriesAudioOnceWhenBusy()
    {
        int calls = 0;
        var fake = new Fake(_ => Interlocked.Increment(ref calls) == 1 ? new HttpResponseMessage(HttpStatusCode.TooManyRequests) : Reply("LANG: en\nORIGINAL: Hi.\nTRANSLATION: 嗨。"));
        var ling = Client(fake);
        var reply = await ling.Chat("c", "i", Priority.Translate, model: LingClient.AudioModel, audio: [1]);
        Check(reply.Contains("ORIGINAL: Hi."), "second attempt answered");
        Equal(2, calls, "one retry");
        var text = Client(new Fake(_ => new HttpResponseMessage(HttpStatusCode.TooManyRequests)));
        try { await text.Chat("c", "i", Priority.Translate); throw new Exception("text translation retried"); }
        catch (LingException e) { Equal(LingException.Kind.RateLimited, e.Failure, "text fails fast"); }
    }

    public static async Task LingMarksABadKey()
    {
        var ling = Client(new Fake(_ => new HttpResponseMessage(HttpStatusCode.Unauthorized)));
        try { await ling.Chat("c", "i", Priority.Translate); } catch (LingException e) { Equal(LingException.Kind.InvalidKey, e.Failure, "401"); }
        Equal(KeyState.Invalid, ling.KeyState, "key state");
        Check(!ling.Usable, "no longer usable");
    }

    public static async Task LingGateSpacesStartsAndServesPriorityFirst()
    {
        var old = LingClient.Spacing;
        LingClient.Spacing = 0.2;
        try
        {
            var fake = new Fake(_ => Reply("ok"));
            var ling = Client(fake);
            var first = ling.Chat("first", "i", Priority.Notes);
            await Task.Delay(20);
            // Queued while the gate is closed: the translation goes before the earlier notes call.
            var notes = ling.Chat("notes", "i", Priority.Notes);
            await Task.Delay(20);
            var translate = ling.Chat("translate", "i", Priority.Translate);
            await Task.WhenAll(first, notes, translate);
            var order = fake.Calls.Select(c => JsonNode.Parse(c.body)!["messages"]![0]!["content"]!.GetValue<string>()).ToList();
            Equal("first,translate,notes", string.Join(",", order), "priority order");
            for (int i = 1; i < fake.Calls.Count; i++)
                Check((fake.Calls[i].at - fake.Calls[i - 1].at).TotalSeconds >= 0.18, "starts spaced");
        }
        finally { LingClient.Spacing = old; }
    }

    public static async Task ListenEngineEndToEndWithAFakeMing()
    {
        // Two stretches of "speech", told apart by length (1 s, then 1.6 s); the fake Ming
        // answers the first one slower, and lines still come out in order.
        var fake = new Fake(body =>
        {
            if (body.Contains("Ming-3.0-audio-flash"))
            {
                var url = JsonNode.Parse(body)!["messages"]![1]!["content"]![0]!["audio_url"]!["url"]!.GetValue<string>();
                bool first = url.Length < 60_000; // base64 of ~1.3 s at 32 kB/s, with lead-in and tail
                if (first) Thread.Sleep(400);
                return Reply(first ? "LANG: en\nORIGINAL: First one.\nTRANSLATION: 第一句。" : "LANG: en\nORIGINAL: Second one.\nTRANSLATION: 第二句。");
            }
            return Reply("{}");
        });
        var old = LingClient.Spacing;
        LingClient.Spacing = 0.05;
        try
        {
            var ling = Client(fake);
            var store = new SessionStore();
            var notes = new NotesEngine(ling, store);
            var engine = new ListenEngine(ling, new Translator(ling), store, notes, new AppSettings { Target = "zh-CN" });
            var path = Path.Combine(Path.GetTempPath(), $"cicada-e2e-{Environment.ProcessId}.wav");
            File.WriteAllBytes(path, Wav.Bytes([.. Tone(1), .. Silence(1), .. Tone(1.6), .. Silence(1)]));
            var src = new FileAudioSource(path, speed: 0);
            var ended = new TaskCompletionSource();
            src.Ended += _ => ended.TrySetResult();
            engine.Start(src);
            await ended.Task;
            await Task.Delay(100);
            await engine.Stop();
            var s = store.Get(engine.SessionId!)!;
            Equal("First one.|Second one.", string.Join("|", s.Lines.Select(l => l.Src)), "in segment order");
            Equal("第一句。", s.Lines[0].Dst, "translation from the same call");
            Equal("h1-1", s.Lines[0].Id, "Mac-style ids");
            Check(s.EndedAt is not null, "ended");
            File.Delete(path);
        }
        finally { LingClient.Spacing = old; }
    }
}
