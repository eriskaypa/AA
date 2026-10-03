// Family (e) services — cases E01–E16 (spec 01 GF.5.e, DATA-319). Inputs are committed as AA-format JSON
// (`inputs/E<nn>…input.json`, loaded by the Swift codec, so family (a) must pass first) plus inline parameters.
// Outputs follow the GF.4.7 shapes.
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO.Compression;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using AA.Models;
using AA.Services;
using AA.Sire;
using static WinFixtures.Corpora;
using static WinFixtures.Fx;

namespace WinFixtures;

internal static class FamilyE
{
    private const string F = "services";

    private static string Doc(AppData d) => JsonSerializer.Serialize(d, Opts);

    /// <summary>Writes an AA-format input and returns it re-loaded through the app's own reader, so C# and Swift
    /// start from exactly the same bytes.</summary>
    private static AppData Input(CaseRun r, string name, AppData d, string key)
    {
        var json = Doc(d);
        r.InputFile($"{r.Id}.{name}.input.json", json, key);
        return JsonSerializer.Deserialize<AppData>(json, Opts)!;
    }

    private static JsonNode? DateNode(DateTime? d) =>
        d is DateTime v ? new JsonObject { ["ticks"] = v.Ticks, ["kind"] = v.Kind.ToString() } : null;

    // ---- E01 DataDiff ------------------------------------------------------------------------------------------------

    private static JsonObject DiffJson(DataDiff.Result r) => new()
    {
        ["Added"] = r.Added, ["Changed"] = r.Changed, ["Removed"] = r.Removed, ["HasChanges"] = r.HasChanges,
        ["Roots"] = new JsonArray(r.Roots.Select(n => (JsonNode?)NodeJson(n)).ToArray()),
    };

    private static JsonObject NodeJson(DataDiff.Node n) => new()
    {
        ["Change"] = n.Change.ToString(), ["Text"] = n.Text,
        ["Children"] = new JsonArray(n.Children.Select(c => (JsonNode?)NodeJson(c)).ToArray()),
    };

    private static void DiffCase(CaseRun r, AppData current, AppData incoming)
    {
        var cur = Input(r, "current", current, "current");
        var inc = Input(r, "incoming", incoming, "incoming");
        try { r.Json("result", "datadiff", DiffJson(DataDiff.Compare(cur, inc))); }
        catch (Exception ex) { r.Json("result", "datadiff", Shapes.ExceptionShape(ex, false)); }
    }

    private static IEnumerable<CaseDef> E01()
    {
        CaseDef D(string sub, string title, Action<CaseRun> run, string level = "must", string[]? settles = null) => new()
        {
            Id = "E01." + sub, Family = F, Compare = "json-semantic", Normative = level, Title = "DataDiff: " + title,
            Settles = settles ?? new[] { "01 §3.15", "01 §7.8" }, Run = run,
        };

        yield return D("1", "the 01 §7.8 example", r => { var (c, i) = DiffExample(); DiffCase(r, c, i); });
        yield return D("2", "identical databases → HasChanges false", r => DiffCase(r, KitchenSink.Build(), KitchenSink.Build()));
        yield return D("3", "changes only in crew, saved lists, ports, Ui, Log, Trash, tags, relations, locks (DATA-103 scope)", r =>
        {
            var inc = KitchenSink.Build();
            inc.Crew[0].FirstName = "Changed";
            inc.ChecklistTemplates[0].Name = "Renamed list";
            inc.Ports[0].Name = "Renamed port";
            inc.Ui.WindowLeft = 12;
            inc.Log.Add(new LogEntry { TimestampUtc = D_Z, Action = "Removed", Kind = "Task", Name = "x" });
            inc.Trash.Clear();
            inc.Equipment[0].Tags.Add("new-tag");
            inc.Equipment[0].RelatedIds.Clear();
            inc.Equipment[0].LockHint = "changed hint";
            DiffCase(r, KitchenSink.Build(), inc);
        });
        yield return D("4", "name / 45-char description / notes with entities and .NET \\s characters", r =>
        {
            var cur = new AppData();
            var e = Equip(1, "Pump"); e.Description = "short";
            e.Container.RichTextXaml = Xaml("A &amp; B&nbsp;C &#x2192; D\u000BE\u0085F G");
            cur.Equipment.Add(e);
            var inc = new AppData();
            var e2 = Equip(1, "Pump X"); e2.Description = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHI";
            e2.Container.RichTextXaml = Xaml("Totally different");
            inc.Equipment.Add(e2);
            DiffCase(r, cur, inc);
        }, settles: new[] { "01 §7.8", "02 §7.7" });
        yield return D("5", "bodies differing only in formatting attributes → no notes node", r =>
        {
            var cur = new AppData(); var a = Equip(1, "E"); a.Container.RichTextXaml = $"<Section {NS}><Paragraph><Run FontWeight=\"Bold\">x</Run></Paragraph></Section>"; cur.Equipment.Add(a);
            var inc = new AppData(); var b = Equip(1, "E"); b.Container.RichTextXaml = Xaml("x"); inc.Equipment.Add(b);
            DiffCase(r, cur, inc);
        });
        yield return D("6", "files added/removed by Name|Path; same name, different path", r =>
        {
            var cur = new AppData(); var a = Equip(1, "E"); a.Container.Files.Add(MkFile(201, "a.pdf", "files/1_a.pdf")); cur.Equipment.Add(a);
            var inc = new AppData(); var b = Equip(1, "E");
            b.Container.Files.Add(MkFile(202, "b.pdf", "files/2_b.pdf")); b.Container.Files.Add(MkFile(203, "a.pdf", "files/9_a.pdf")); inc.Equipment.Add(b);
            DiffCase(r, cur, inc);
        });
        yield return new CaseDef
        {
            Id = "E01.7", Family = F, Compare = "json-semantic", Title = "DataDiff: two files with the same Name|Path in one container (D-10)",
            Settles = new[] { "01 §7.8", "02 D-10" },
            Run = r =>
            {
                var cur = new AppData(); var a = Equip(1, "E");
                a.Container.Files.Add(MkFile(201, "a.pdf", "files/1_a.pdf")); a.Container.Files.Add(MkFile(202, "a.pdf", "files/1_a.pdf"));
                cur.Equipment.Add(a);
                DiffCase(r, cur, KitchenSink.WithTasks(Array.Empty<TaskItem>()));
                r.DivergentRecordOnly("02 D-10 fixed on the Mac (P2): duplicate Name|Path keys no longer throw (asserted by F2's tests)");
            },
        };
        yield return D("8", "Deadline Unspecified vs Local same wall clock; RangeStart added; Recurrence 0→3; Status 1→3", r =>
        {
            var cur = new AppData(); var a = MkTask(3, "T"); a.Deadline = new DateTime(2026, 10, 5, 0, 0, 0, DateTimeKind.Unspecified); a.Status = WorkStatus.InProgress; cur.Tasks.Add(a);
            var inc = new AppData(); var b = MkTask(3, "T"); b.Deadline = new DateTime(2026, 10, 5, 0, 0, 0, DateTimeKind.Local);
            b.RangeStart = Day(2026, 10, 1); b.Recurrence = RecurrenceKind.Monthly; b.Status = WorkStatus.Done; inc.Tasks.Add(b);
            DiffCase(r, cur, inc);
        });
        yield return D("9", "subtasks three levels deep: added (files + grandchildren), removed, changed", r =>
        {
            var cur = new AppData(); var a = MkTask(3, "Root");
            var keep = MkTask(5, "Keep"); var keepChild = MkTask(6, "Keep child"); var deep = MkTask(9, "Deep"); keepChild.Subtasks.Add(deep); keep.Subtasks.Add(keepChild);
            a.Subtasks.Add(keep); a.Subtasks.Add(MkTask(12, "Gone"));
            cur.Tasks.Add(a);
            var inc = new AppData(); var b = MkTask(3, "Root");
            var keep2 = MkTask(5, "Keep"); var keepChild2 = MkTask(6, "Keep child"); var deep2 = MkTask(9, "Deep renamed"); keepChild2.Subtasks.Add(deep2); keep2.Subtasks.Add(keepChild2);
            var added = MkTask(13, "New"); added.Container.Files.Add(MkFile(213, "new.pdf", "files/13_new.pdf"));
            var addedChild = MkTask(14, "New child"); addedChild.Subtasks.Add(MkTask(15, "New grandchild")); added.Subtasks.Add(addedChild);
            b.Subtasks.Add(keep2); b.Subtasks.Add(added);
            inc.Tasks.Add(b);
            DiffCase(r, cur, inc);
        });
        yield return D("10", "components added/removed/changed; linked procedure/task incl. an unknown id", r =>
        {
            var cur = new AppData(); var a = Equip(1, "E");
            var c1 = Comp(2, "Keep"); c1.Notes = "a"; a.Components.Add(c1); a.Components.Add(Comp(20, "Gone"));
            a.ProcedureIds.Add(G(4)); a.TaskIds.Add(G(3));
            cur.Equipment.Add(a); cur.Procedures.Add(Proc(4, "Proc")); cur.Tasks.Add(MkTask(3, "Task"));
            var inc = new AppData(); var b = Equip(1, "E");
            var c2 = Comp(2, "Keep renamed"); c2.Notes = "b"; c2.Container.RichTextXaml = Xaml("body"); c2.Container.Files.Add(MkFile(221, "c.pdf", "files/c.pdf"));
            var c3 = Comp(21, "New"); c3.Container.Files.Add(MkFile(222, "n.pdf", "files/n.pdf"));
            b.Components.Add(c2); b.Components.Add(c3);
            b.TaskIds.Add(G(3)); b.TaskIds.Add(G(98));
            inc.Equipment.Add(b); inc.Procedures.Add(Proc(4, "Proc")); inc.Tasks.Add(MkTask(3, "Task"));
            DiffCase(r, cur, inc);
        });
        yield return D("11", "steps: title, done False → True, notes, files, linked task/equipment", r =>
        {
            var cur = new AppData(); var p = Proc(4, "P");
            var s = Step(7, "Old title"); s.TaskIds.Add(G(3)); p.Steps.Add(s); p.Steps.Add(Step(70, "Removed step"));
            cur.Procedures.Add(p); cur.Tasks.Add(MkTask(3, "Linked task")); cur.Equipment.Add(Equip(1, "Linked eq"));
            var inc = new AppData(); var q = Proc(4, "P");
            var s2 = Step(7, "New title"); s2.Done = true; s2.Container.RichTextXaml = Xaml("step notes"); s2.Container.Files.Add(MkFile(271, "s.pdf", "files/s.pdf"));
            s2.EquipmentIds.Add(G(1));
            var s3 = Step(71, "Added step"); s3.TaskIds.Add(G(3)); s3.EquipmentIds.Add(G(1));
            q.Steps.Add(s2); q.Steps.Add(s3);
            inc.Procedures.Add(q); inc.Tasks.Add(MkTask(3, "Linked task")); inc.Equipment.Add(Equip(1, "Linked eq"));
            DiffCase(r, cur, inc);
        });
        yield return D("12", "the same id as a Task in current and a Vessel in incoming", r =>
        {
            var cur = new AppData(); var t = MkTask(3, "Shape shifter"); t.Deadline = Day(2026, 10, 1); cur.Tasks.Add(t);
            var inc = new AppData(); var v = Ship(3, "Shape shifter 2"); inc.Vessels.Add(v);
            DiffCase(r, cur, inc);
        });
        yield return D("13", "duplicate ids inside one collection (last value, first position)", r =>
        {
            var cur = new AppData(); cur.Tasks.Add(MkTask(3, "T"));
            var inc = new AppData(); inc.Tasks.Add(MkTask(3, "First copy")); inc.Tasks.Add(MkTask(5, "Other")); inc.Tasks.Add(MkTask(3, "Second copy"));
            DiffCase(r, cur, inc);
        });
        yield return D("14", "ProcedureIds [G5,G3,G4] vs [G4] and back (HashSet enumeration order)", r =>
        {
            AppData Make(params int[] ids)
            {
                var d = new AppData(); var e = Equip(1, "E");
                foreach (var i in ids) e.ProcedureIds.Add(G(i));
                d.Equipment.Add(e);
                d.Procedures.Add(Proc(5, "P5")); d.Procedures.Add(Proc(3, "P3")); d.Procedures.Add(Proc(4, "P4"));
                return d;
            }
            var a = Input(r, "a", Make(5, 3, 4), "a");
            var b = Input(r, "b", Make(4), "b");
            r.Json("result", "datadiff", new JsonObject
            {
                ["forward"] = DiffJson(DataDiff.Compare(a, b)), ["backward"] = DiffJson(DataDiff.Compare(b, a)),
            });
        }, settles: new[] { "01 §3.15" });
        yield return D("15", "List.Sort tie order: three identical root texts; twenty roots with pairwise ties", r =>
        {
            var inc = new AppData();
            int n = 300;
            foreach (var tag in new[] { "X", "Y", "Z" })
            {
                var t = MkTask(n++, "Same");
                t.Container.Files.Add(MkFile(n + 1000, tag + ".pdf", "files/" + tag + ".pdf"));
                inc.Tasks.Add(t);
            }
            for (int i = 0; i < 20; i++)
            {
                var t = MkTask(400 + i, "Tie " + (i / 2));
                t.Container.Files.Add(MkFile(1400 + i, "f" + i + ".pdf", "files/f" + i + ".pdf"));
                inc.Tasks.Add(t);
            }
            DiffCase(r, new AppData(), inc);
        }, level: "should", settles: new[] { "01 §3.15" });
        yield return D("16", "OrdinalIgnoreCase ordering of root names", r =>
        {
            var names = new[] { "_pump", "apple", "Äpfel", "zebra", "Straße", "STRASSE", "ǅ", "ǆ", "İ", "i", "ı", "I", "k", "K" };
            var inc = new AppData();
            for (int i = 0; i < names.Length; i++) inc.Tasks.Add(MkTask(500 + i, names[i]));
            r.Input("names", new JsonArray(names.Select(x => (JsonNode?)x).ToArray()));
            DiffCase(r, new AppData(), inc);
        }, settles: new[] { "01 §3.15", "GF.8.4" });
        yield return D("17", "added items of each kind with full content (ContentChildren order)", r =>
        {
            var inc = new AppData();
            var e = Equip(1, "Eq"); e.Container.Files.Add(MkFile(201, "e.pdf", "files/e.pdf"));
            var c = Comp(2, "Comp"); c.Container.Files.Add(MkFile(202, "c.pdf", "files/c.pdf")); e.Components.Add(c);
            e.ProcedureIds.Add(G(4)); e.TaskIds.Add(G(3)); e.TaskIds.Add(G(97));
            var t = MkTask(3, "Task"); t.Container.Files.Add(MkFile(203, "t.pdf", "files/t.pdf"));
            var st = MkTask(5, "Sub"); st.Container.Files.Add(MkFile(205, "s.pdf", "files/s.pdf")); st.Subtasks.Add(MkTask(6, "SubSub")); t.Subtasks.Add(st);
            var p = Proc(4, "Proc"); p.Container.Files.Add(MkFile(204, "p.pdf", "files/p.pdf"));
            var step = Step(7, "Step"); step.Container.Files.Add(MkFile(207, "st.pdf", "files/st.pdf")); step.TaskIds.Add(G(3)); step.EquipmentIds.Add(G(1)); p.Steps.Add(step);
            var v = Ship(8, "Ship"); v.Container.Files.Add(MkFile(208, "v.pdf", "files/v.pdf"));
            inc.Equipment.Add(e); inc.Tasks.Add(t); inc.Procedures.Add(p); inc.Vessels.Add(v);
            DiffCase(r, new AppData(), inc);
        });
        yield return D("18", "a linked id renamed in incoming (names map: incoming wins)", r =>
        {
            var cur = new AppData(); var e = Equip(1, "E"); cur.Equipment.Add(e); cur.Procedures.Add(Proc(4, "Old name"));
            var inc = new AppData(); var e2 = Equip(1, "E"); e2.ProcedureIds.Add(G(4)); inc.Equipment.Add(e2); inc.Procedures.Add(Proc(4, "New name"));
            DiffCase(r, cur, inc);
        });
        yield return D("19a", "Snip at exactly 40 and 41 characters; PlainText; Fmt", r =>
        {
            var rows = new JsonArray();
            foreach (var s in new[] { new string('a', 40), new string('b', 41), "a\r\nb", "  padded  ", "" })
                rows.Add(new JsonObject { ["input"] = s, ["snip"] = Call<string>(typeof(DataDiff), "Snip", s) });
            r.Json("result", "snip", rows);
        });
        yield return new CaseDef
        {
            Id = "E01.19b", Family = F, Compare = "json-semantic", Normative = "should",
            Title = "DataDiff: Snip with an emoji straddling position 40 (UTF-16 cut)", Settles = new[] { "01 §7.8" },
            Run = r =>
            {
                var s = new string('x', 39) + "😀tail";
                r.Json("result", "snip", new JsonArray(new JsonObject { ["input"] = s, ["snip"] = Call<string>(typeof(DataDiff), "Snip", s) }));
                r.DivergentRecordOnly("01 §7.8 / GF.5.e E01.19: the Mac SHOULD NOT split a surrogate pair");
            },
        };
    }

    // ---- E02 search -----------------------------------------------------------------------------------------------

    private static JsonObject SearchJson(AppData data, string query, int max, ISet<Guid>? locked)
    {
        var hits = SearchService.Search(data, query, max, locked);
        return new JsonObject
        {
            ["query"] = query, ["maxResults"] = max,
            ["lockedOwnerIds"] = new JsonArray((locked ?? new HashSet<Guid>()).Select(g => (JsonNode?)g.ToString("D")).ToArray()),
            ["hits"] = new JsonArray(hits.Select(h => (JsonNode?)new JsonObject
            {
                ["OwnerId"] = h.Owner.Id.ToString("D"), ["OwnerName"] = h.Owner.Name, ["Kind"] = h.Kind.ToString(),
                ["Where"] = h.Where, ["Snippet"] = h.Snippet, ["MatchStart"] = h.MatchStart, ["MatchLength"] = h.MatchLength,
                ["ChildId"] = h.ChildId?.ToString("D"),
            }).ToArray()),
        };
    }

    private static IEnumerable<CaseDef> E02()
    {
        CaseDef S(string sub, string title, Func<AppData> data, string query, int max = 500, int[]? locked = null, string level = "must") => new()
        {
            Id = "E02." + sub, Family = F, Compare = "json-semantic", Normative = level, Title = $"Search \"{query}\": {title}",
            Settles = new[] { "02 §7.7", "02 Q-9" },
            Run = r =>
            {
                var d = Input(r, "data", data(), "data");
                r.Input("query", query);
                r.Input("maxResults", max);
                var set = locked?.Select(G).ToHashSet();
                r.Input("lockedOwnerIds", new JsonArray((locked ?? Array.Empty<int>()).Select(i => (JsonNode?)G(i).ToString("D")).ToArray()));
                r.Json("result", "search", SearchJson(d, query, max, set));
            },
        };
        yield return S("1", "02 §7.7 corpus", SearchCorpus, "FUEL");
        yield return S("2", "02 §7.7 corpus", SearchCorpus, "engine");
        yield return S("3", "Main Engine locked: Tags still match", SearchCorpus, "ME", locked: new[] { 1 });
        yield return S("4", "Main Engine locked: component hit dropped", SearchCorpus, "FUEL", locked: new[] { 1 });
        yield return S("5", "blank query → no hits", SearchCorpus, "   ");
        yield return S("6", "501 matching items → exactly 500 hits", () =>
        {
            var d = new AppData();
            for (int i = 0; i < 501; i++) d.Tasks.Add(MkTask(3000 + i, "Pump " + i));
            return d;
        }, "pump");
        yield return S("8", "file labels File › Document / › Path", () =>
        {
            var d = new AppData(); var e = Equip(1, "Library");
            e.Container.Files.Add(MkFile(201, "manual.pdf", "files/manual-dir/manual.pdf"));
            e.Container.Files.Add(MkFile(202, "photo.jpg", "files/manual-photo.jpg", FileKind.Image));
            d.Equipment.Add(e); return d;
        }, "manual");
        yield return S("9", "subtask walk three levels", () =>
        {
            var d = new AppData(); var t = MkTask(3, "Root");
            var a = MkTask(5, "Level one valve"); var b = MkTask(6, "Level two valve"); var c = MkTask(9, "Level three valve");
            c.Description = "valve description"; b.Subtasks.Add(c); a.Subtasks.Add(b); t.Subtasks.Add(a);
            d.Tasks.Add(t); return d;
        }, "valve");
        yield return S("10", "surrounding spaces are trimmed", SearchCorpus, " fuel ");
        yield return S("11", "a+b is literal, not a regex", () =>
        {
            var d = new AppData(); d.Tasks.Add(MkTask(3, "Mix a+b now")); d.Tasks.Add(MkTask(5, "aab")); return d;
        }, "a+b");
        var probes = new (string Text, string Query)[]
        {
            ("Straße", "STRASSE"), ("k", "K"), ("i", "İ"), ("ς", "σ"), ("ǆ", "ǅ"), ("é", "é"),
        };
        for (int i = 0; i < probes.Length; i++)
        {
            var (text, query) = probes[i];
            yield return S((12 + i).ToString(CultureInfo.InvariantCulture), $"casing probe over \"{text}\"", () =>
            {
                var d = new AppData(); d.Tasks.Add(MkTask(3, text)); return d;
            }, query);
        }
        yield return new CaseDef
        {
            Id = "E02.7", Family = F, Compare = "json-semantic", Title = "MakeSnippet rows (02 §7.7, by reflection)",
            Settles = new[] { "02 §7.7" },
            Run = r =>
            {
                var rows = new (string Text, string Needle)[]
                {
                    (new string('a', 100) + "needle" + new string('b', 100), "needle"),
                    ("Line one\r\n\r\n   target here", "target"),
                    ("one  two three", "one  two"),
                    (new string('x', 70) + "  \n\t  KEY " + new string('y', 10), "KEY"),
                    ("Check " + new string('z', 55) + " pump pump", "pump"),
                };
                var arr = new JsonArray();
                foreach (var (text, needle) in rows)
                {
                    var idx = text.IndexOf(needle, StringComparison.OrdinalIgnoreCase);
                    var (snippet, start) = Call<(string, int)>(typeof(SearchService), "MakeSnippet", text, idx, needle.Length);
                    arr.Add(new JsonObject { ["text"] = text, ["index"] = idx, ["length"] = needle.Length, ["snippet"] = snippet, ["start"] = start });
                }
                r.Json("result", "snippets", arr);
            },
        };
    }

    // ---- E03 plain-text extractors ------------------------------------------------------------------------------------

    public static readonly string[] PlainTextInputs =
    {
        "", $"<Section {NS}><Paragraph><Run>Hello</Run></Paragraph><Paragraph><Run>World</Run></Paragraph></Section>",
        $"<Section {NS}><Paragraph><Run>A</Run><LineBreak /><Run>B</Run></Paragraph></Section>",
        $"<Section {NS}><List><ListItem><Paragraph><Run>One</Run></Paragraph></ListItem><ListItem><Paragraph><Run>Two</Run></Paragraph></ListItem></List></Section>",
        $"<Section {NS}><Paragraph><Run>Fish &amp; chips</Run></Paragraph></Section>",
        $"<Section {NS}><Paragraph><Run> </Run></Paragraph></Section>",
        "enc:QUJD", "<Paragraph><Run>Hi</Run>", "<Run>a</Run><Run>b</Run>",
        "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"><Paragraph><Run> </Run></Paragraph></Section>",
        $"<Section {NS}><Paragraph><Run><![CDATA[a < b]]></Run></Paragraph></Section>",
        $"<Section {NS}><!-- note --><Paragraph><Run>c</Run></Paragraph></Section>",
        $"<?xml version=\"1.0\"?><Section {NS}><?pi data?><Paragraph><Run>p</Run></Paragraph></Section>",
        $"<!DOCTYPE Section><Section {NS}><Paragraph><Run>d</Run></Paragraph></Section>",
        $"<Section {NS}><Paragraph><Run>a&nbsp;b</Run></Paragraph></Section>",
        $"<Section {NS}><Paragraph><Run>a&#160;b</Run></Paragraph></Section>",
        $"<Section {NS}><Paragraph><Run Text=\"x\" /></Paragraph></Section>",
        $"<Section {NS}><Paragraph><Span><Hyperlink NavigateUri=\"https://www.imo.org\"><Run>IMO</Run></Hyperlink> page</Span></Paragraph></Section>",
        $"<Section {NS}><Table><TableRowGroup><TableRow><TableCell><Paragraph><Run>r1c1</Run></Paragraph></TableCell><TableCell><Paragraph><Run>r1c2</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table></Section>",
        KitchenSink.EquipmentXaml,
    };

    // ---- E04 reminders ------------------------------------------------------------------------------------------------

    private static JsonObject ReminderJson(ReminderService.Summary s, string today) => new()
    {
        ["today"] = today, ["Overdue"] = s.Overdue, ["DueToday"] = s.DueToday, ["DueWeek"] = s.DueWeek,
        ["Total"] = s.Total, ["Any"] = s.Any, ["Headline"] = s.Headline(),
    };

    private static IEnumerable<CaseDef> E04()
    {
        CaseDef R(string sub, string title, Func<AppData> data) => new()
        {
            Id = "E04." + sub, Family = F, Compare = "json-semantic", Title = "Reminders: " + title,
            Settles = new[] { "02 §7.8" },
            Run = r =>
            {
                var d = Input(r, "data", data(), "data");
                r.Input("today", "2026-09-29");
                r.Json("result", "reminders", ReminderJson(ReminderService.Compute(new AppRepository(d), Day(2026, 9, 29)), "2026-09-29"));
            },
        };
        yield return R("1", "the 02 §7.8 data set", ReminderSet);
        yield return R("2", "Utc deadline 2026-09-29T23:30Z (.Date without conversion → due today)", () =>
        {
            var d = new AppData(); var t = MkTask(3, "utc"); t.Deadline = new DateTime(2026, 9, 29, 23, 30, 0, DateTimeKind.Utc); d.Tasks.Add(t); return d;
        });
        yield return R("3", "a deadline with a time of day", () =>
        {
            var d = new AppData(); var t = MkTask(3, "timed"); t.Deadline = new DateTime(2026, 9, 29, 17, 45, 0); d.Tasks.Add(t); return d;
        });
        yield return R("4", "week boundary: 10-06 counted, 10-07 not", () =>
        {
            var d = new AppData(); var a = MkTask(3, "in"); a.Deadline = Day(2026, 10, 6); var b = MkTask(5, "out"); b.Deadline = Day(2026, 10, 7);
            d.Tasks.Add(a); d.Tasks.Add(b); return d;
        });
        yield return R("5", "completed parent with an incomplete subtask", () =>
        {
            var d = new AppData(); var p = MkTask(3, "parent"); p.Deadline = Day(2026, 9, 28); p.IsComplete = true;
            var s = MkTask(5, "child"); s.Deadline = Day(2026, 9, 28); p.Subtasks.Add(s); d.Tasks.Add(p); return d;
        });
        yield return R("6", "Done procedure with an open step", () =>
        {
            var d = new AppData(); var p = Proc(4, "done"); p.Status = WorkStatus.Done; p.Deadline = Day(2026, 9, 1);
            var s = Step(7, "open"); s.Deadline = Day(2026, 9, 30); p.Steps.Add(s); d.Procedures.Add(p); return d;
        });
        yield return R("7", "all zero → Nothing due.", () => new AppData());
        yield return R("8", "week-only → 1 due this week", () =>
        {
            var d = new AppData(); var t = MkTask(3, "week"); t.Deadline = Day(2026, 10, 2); d.Tasks.Add(t); return d;
        });
    }

    // ---- E06/E07 batch done / deadline ------------------------------------------------------------------------------

    /// <summary>A completable item built from a row spec (also what the Swift reproducer builds).</summary>
    private static object? Build(JsonObject spec)
    {
        switch ((string)spec["kind"]!)
        {
            case "task":
            {
                var t = MkTask(3, "task");
                if (spec["status"] is JsonNode s) t.Status = (WorkStatus)(int)s;
                if (spec["isComplete"] is JsonNode c) t.IsComplete = (bool)c;
                if (spec["rangeStart"] is JsonNode rs) t.RangeStart = ParseDate((string)rs!);
                if (spec["deadline"] is JsonNode dl) t.Deadline = ParseDate((string)dl!);
                return t;
            }
            case "procedure":
            {
                var p = Proc(4, "procedure");
                if (spec["status"] is JsonNode s) p.Status = (WorkStatus)(int)s;
                if (spec["deadline"] is JsonNode dl) p.Deadline = ParseDate((string)dl!);
                return p;
            }
            case "step":
            {
                var s = Step(7, "step");
                if (spec["done"] is JsonNode d) s.Done = (bool)d;
                if (spec["deadline"] is JsonNode dl) s.Deadline = ParseDate((string)dl!);
                return s;
            }
            case "equipment": return Equip(1, "equipment");
            case "literal": return (string)spec["value"]!;
            default: return null;
        }
    }

    /// <summary>`yyyy-MM-dd[ HH:mm][ Local]` → DateTime (Unspecified unless "Local").</summary>
    private static DateTime ParseDate(string s)
    {
        var local = s.EndsWith(" Local", StringComparison.Ordinal);
        if (local) s = s[..^6];
        var dt = DateTime.ParseExact(s, s.Length > 10 ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd", CultureInfo.InvariantCulture);
        return DateTime.SpecifyKind(dt, local ? DateTimeKind.Local : DateTimeKind.Unspecified);
    }

    private static JsonObject State(object? o) => o switch
    {
        TaskItem t => new JsonObject { ["IsComplete"] = t.IsComplete, ["Status"] = (int)t.Status, ["RangeStart"] = DateNode(t.RangeStart), ["Deadline"] = DateNode(t.Deadline) },
        Procedure p => new JsonObject { ["Status"] = (int)p.Status, ["Deadline"] = DateNode(p.Deadline) },
        ChecklistStep s => new JsonObject { ["Done"] = s.Done, ["Deadline"] = DateNode(s.Deadline) },
        null => new JsonObject { ["null"] = true },
        _ => new JsonObject { ["other"] = o.GetType().Name },
    };

    private static JsonObject Spec(string kind, params (string K, JsonNode? V)[] kv)
    {
        var o = new JsonObject { ["kind"] = kind };
        foreach (var (k, v) in kv) o[k] = v;
        return o;
    }

    // ---- E08 batch delete -----------------------------------------------------------------------------------------------

    /// <summary>`new Row(item)` — the wrapper shape BatchDelete.Unwrap reflects on (GF.4.8 `#row:`).</summary>
    public sealed class Row(object item) { public object Item { get; } = item; }

    /// <summary>GF.4.8 selection-reference grammar over a database.</summary>
    public static object? Resolve(AppData d, string reference)
    {
        if (reference == "null") return null;
        if (reference.StartsWith("#literal:", StringComparison.Ordinal)) return reference[9..];
        if (reference.StartsWith("#row:", StringComparison.Ordinal)) return new Row(Resolve(d, reference[5..])!);
        object? cur = null;
        foreach (var part in reference.Split('.'))
        {
            var name = part[..part.IndexOf('[')];
            var index = int.Parse(part[(part.IndexOf('[') + 1)..^1], CultureInfo.InvariantCulture);
            System.Collections.IList list = cur == null
                ? name switch
                {
                    "Equipment" => d.Equipment, "Tasks" => d.Tasks, "Procedures" => d.Procedures, "Vessels" => d.Vessels,
                    "Crew" => d.Crew, "ChecklistTemplates" => d.ChecklistTemplates,
                    _ => throw new ArgumentException(reference),
                }
                : (System.Collections.IList)cur.GetType().GetProperty(name)!.GetValue(cur)!;
            cur = list[index];
        }
        return cur;
    }

    private static JsonObject SummaryJson(BatchDelete.Summary s) => new()
    {
        ["Equipment"] = s.Equipment, ["Tasks"] = s.Tasks, ["Procedures"] = s.Procedures, ["Vessels"] = s.Vessels,
        ["Locked"] = s.Locked, ["Descendants"] = s.Descendants, ["WithAttachments"] = s.WithAttachments,
        ["LinkedFromElsewhere"] = s.LinkedFromElsewhere, ["Total"] = s.Total, ["IsEmpty"] = s.IsEmpty,
        ["KindBreakdown"] = s.KindBreakdown(),
    };

    /// <summary>The 02 §7.6 setup: Task A (S1 → S1a with a file, S2), Procedure P (3 steps) referenced by X,
    /// Equipment L locked, Vessel V with a file.</summary>
    private static AppData BatchSetup()
    {
        var d = new AppData();
        var a = MkTask(3, "A");
        var s1 = MkTask(5, "S1"); var s1a = MkTask(6, "S1a"); s1a.Container.Files.Add(MkFile(206, "s1a.pdf", "files/s1a.pdf"));
        s1.Subtasks.Add(s1a); a.Subtasks.Add(s1); a.Subtasks.Add(MkTask(9, "S2"));
        d.Tasks.Add(a);
        var p = Proc(4, "P"); p.Steps.Add(Step(71, "s1")); p.Steps.Add(Step(72, "s2")); p.Steps.Add(Step(73, "s3"));
        d.Procedures.Add(p);
        var x = Equip(1, "X"); x.ProcedureIds.Add(G(4)); d.Equipment.Add(x);
        var l = Equip(2, "L"); l.LockHash = KitchenSink.LockHash; l.LockSalt = KitchenSink.LockSalt; d.Equipment.Add(l);
        var v = Ship(8, "V"); v.Container.Files.Add(MkFile(208, "v.pdf", "files/v.pdf")); d.Vessels.Add(v);
        return d;
    }

    private static IEnumerable<CaseDef> E08()
    {
        var selections = new (string Sub, string Title, Func<AppData> Data, string[] Refs, string Level)[]
        {
            ("1", "02 §7.6 setup: [A, S1, P, L, V, A]", BatchSetup, new[] { "Tasks[0]", "Tasks[0].Subtasks[0]", "Procedures[0]", "Equipment[1]", "Vessels[0]", "Tasks[0]" }, "must"),
            ("2", "(a) E1 + T1 + P1 + V1 of KS", KitchenSink.Build, new[] { "Equipment[0]", "Tasks[0]", "Procedures[0]", "Vessels[0]" }, "must"),
            ("3", "(b) T1 and its subtask T1a both selected", KitchenSink.Build, new[] { "Tasks[0]", "Tasks[0].Subtasks[0]" }, "must"),
            ("4", "(c) duplicates", KitchenSink.Build, new[] { "Procedures[0]", "Procedures[0]", "Vessels[0]" }, "must"),
            ("5", "(d) #row: wrappers, null and a literal", KitchenSink.Build, new[] { "#row:Tasks[0]", "#row:Vessels[0]", "null", "#literal:x" }, "must"),
            ("6", "(e) a locked item (Protect, no unlock) → Locked, skipped", KitchenSink.Build, new[] { "Equipment[0]" }, "must"),
            ("7", "(f) items referenced elsewhere → LinkedFromElsewhere", KitchenSink.Build, new[] { "Tasks[0]", "Procedures[0]" }, "must"),
        };
        foreach (var (sub, title, data, refs, level) in selections)
            yield return new CaseDef
            {
                Id = "E08." + sub, Family = F, Compare = "json-semantic", Normative = level, Title = "BatchDelete " + title,
                Settles = new[] { "02 §7.6", "02 REPO-073…075" },
                Run = r =>
                {
                    var d = Input(r, "data", data(), "data");
                    r.Input("selection", new JsonArray(refs.Select(x => (JsonNode?)x).ToArray()));
                    var baseline = DataStore.SerializeForSave(Input(r, "data", data(), "data"));
                    var repo = new AppRepository(d);
                    var sel = refs.Select(x => Resolve(d, x)).ToList();
                    var summary = BatchDelete.Describe(repo, sel);
                    var trashed = BatchDelete.TrashAll(repo, sel);
                    r.Json("result", "describe", new JsonObject { ["summary"] = SummaryJson(summary), ["trashed"] = trashed });
                    var bytes = DataStore.SerializeForSave(d);
                    r.Mask.AutoMask(bytes, baseline);
                    r.Text("bytes", "appdata", "json", bytes, "bytes-masked");
                },
            };
        yield return new CaseDef
        {
            Id = "E08.8", Family = F, Compare = "json-semantic", Normative = "record-only",
            Title = "BatchDelete (g): a C#-built cyclic subtask graph (cycle guard)", Settles = new[] { "02 §7.6" },
            Run = r =>
            {
                var d = new AppData(); var t = MkTask(3, "cyclic"); var s = MkTask(5, "child"); t.Subtasks.Add(s); s.Subtasks.Add(t); d.Tasks.Add(t);
                var summary = BatchDelete.Describe(new AppRepository(d), new object?[] { t });
                r.Json("result", "describe", new JsonObject { ["summary"] = SummaryJson(summary) }, mac: false);
            },
        };
        yield return new CaseDef
        {
            Id = "E08.9", Family = F, Compare = "json-semantic", Title = "BatchDelete.Summary.KindBreakdown for counts 0/1/2 of each kind",
            Settles = new[] { "02 §7.6" },
            Run = r =>
            {
                var rows = new JsonArray();
                foreach (var e in new[] { 0, 1, 2 })
                    foreach (var t in new[] { 0, 1, 2 })
                        foreach (var p in new[] { 0, 1, 2 })
                            foreach (var v in new[] { 0, 1, 2 })
                            {
                                var s = new BatchDelete.Summary { Equipment = e, Tasks = t, Procedures = p, Vessels = v };
                                rows.Add(new JsonObject { ["Equipment"] = e, ["Tasks"] = t, ["Procedures"] = p, ["Vessels"] = v, ["KindBreakdown"] = s.KindBreakdown() });
                            }
                r.Json("result", "kind-breakdown", rows);
            },
        };
    }

    // ---- E09/E10 dates -----------------------------------------------------------------------------------------------

    private static JsonObject Resolution(DateResolution d) => new()
    {
        ["Value"] = d.Value?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), ["Raw"] = d.Raw,
        ["DependedOnOrder"] = d.DependedOnOrder, ["Note"] = d.Note, ["ToStorage"] = d.ToStorage(),
    };

    private static readonly (string Input, DateRole Role, DateOrder Order)[] ResolveRows = BuildResolveRows();

    private static (string, DateRole, DateOrder)[] BuildResolveRows()
    {
        var any = DateRole.Any; var u = DateOrder.Unknown;
        var rows = new List<(string, DateRole, DateOrder)>();
        foreach (var s in new[] { "", " ", " ", "N/A", "tbc", "#N/A", "-", "Null", "0", "00/00/0000", "1899-12-30", "30/12/1899",
                                  "1900-01-01 00:00", "2026-03-04", "2026/3/4", "2026.03.04", "2026-03-04T10:30:00Z", "2026-03-04 10:30",
                                  "2026-03/04", "2026-02-29", "2024-02-29", "1899-12-31", "20260304", "04032026", "12 Mar 2026",
                                  "12 MARCH 2026", "12 march 2026", "March 4, 2026", "Mar 4 2026", "4th March 2026", "1ST Mar 2026",
                                  "12-SEPT-26", "2026 Mar 4", "12 Mar 1850", "12 AUGUST 2026", "DECEMBER 1ST 2026", "12 Mar 2026 10:00",
                                  "26-03-04", "15/07/2026", "15.07.26", "07/15/2026", "31/02/2026", "13/13/2026", "02/30/2026",
                                  "31/04/2026", "03/04/2026", "15/07/202" })
            rows.Add((s, any, u));
        rows.Add(("12 AUG 98", DateRole.PastOnly, u)); rows.Add(("12 AUG 98", DateRole.FutureLikely, u));
        rows.Add(("12-MAR-20", DateRole.FutureLikely, u));
        rows.Add(("98-03-04", any, u)); rows.Add(("98-03-04", DateRole.PastOnly, u)); rows.Add(("98-03-04", DateRole.FutureLikely, u));
        rows.Add(("45/12/31", any, u)); rows.Add(("45/12/31", DateRole.PastOnly, u));
        rows.Add(("15-07-98", DateRole.PastOnly, u));
        rows.Add(("3/4/2026", any, DateOrder.DayFirst)); rows.Add(("3/4/2026", any, DateOrder.MonthFirst)); rows.Add(("3/4/2026", any, DateOrder.Conflicted));
        rows.Add(("12/12/2026", any, DateOrder.DayFirst)); rows.Add(("00/05/2026", any, DateOrder.DayFirst)); rows.Add(("3/4/26", any, DateOrder.DayFirst));
        return rows.ToArray();
    }

    private static readonly string[] ParseDateInputs =
    {
        "", "   ", "2026-03-15", "2026/03/15", "2026.03.15", " 2026-03-15 ", "2026-3-5", "03/04/2026", "03-04-2026", "03.04.2026",
        "3/4/26", "3/4/50", "3/4/49", "1/2/99", "15/07/2026", "15 Jul 2026", "Jul 15, 2026", "July 15 2026", "2026-03-15T10:30:00",
        "2026-02-30", "garbage", "12", "2026-03-15T23:30:00Z", "2026-03-15T23:30:00+14:00", "Mar 15, 2026 10:00 PM", "15.03.2026", "20260315",
    };

    // ---- E12 saved-list order ----------------------------------------------------------------------------------------

    private sealed record OrdRow(string Id, string All, string Call, string Picks, int Target, bool Up);

    /// <summary>02 §7.9: letters are lists; (g)/(h) the group; · ungrouped. `all` = "A:g B:g X:h".</summary>
    private static readonly OrdRow[] OrdRows =
    {
        new("T-ORD-1", "A:g B:g C:g", "nudge", "B C", 0, true),
        new("T-ORD-2a", "A:g B:g C:g", "nudge", "A", 0, true),
        new("T-ORD-2b", "A:g B:g C:g", "nudge", "C", 0, false),
        new("T-ORD-3", "A:g X:h", "nudge", "A X", 0, true),
        new("T-ORD-4", "A:g", "nudge", "A", 0, false),
        new("T-ORD-5", "A:g X:h B:g", "nudge", "B", 0, true),
        new("T-ORD-6", "A:g X:h B:g C:g", "nudge", "B C", 0, true),
        new("T-ORD-7", "A:g B:g X:h C:g", "nudge", "A B", 0, false),
        new("T-ORD-8", "A:g X:h B:g", "moveTo", "B", 0, false),
        new("T-ORD-9", "A:g B:g C:g D:g", "moveTo", "A C", 4, false),
        new("T-ORD-10", "A:g B:g C:g D:g", "moveTo", "D", 1, false),
        new("T-ORD-11", "A:g B:g C:g D:g", "moveTo", "B", 2, false),
        new("T-ORD-12", "A:g B:g C:g", "moveTo", "A", 99, false),
        new("T-ORD-13a", "A:g B:g C:g", "moveTo", "", 0, false),
        new("T-ORD-13b", "A:g B:g X:h", "moveTo", "X", 0, false),
    };

    private static (ObservableCollection<ChecklistTemplate> All, Dictionary<string, ChecklistTemplate> ByName, Dictionary<string, Guid?> Groups) OrdSetup(string all)
    {
        var groups = new Dictionary<string, Guid?> { ["g"] = G(901), ["h"] = G(902), ["·"] = null };
        var list = new ObservableCollection<ChecklistTemplate>();
        var byName = new Dictionary<string, ChecklistTemplate>();
        int n = 910;
        foreach (var tok in all.Split(' ', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = tok.Split(':');
            var t = new ChecklistTemplate { Id = G(n++), Name = parts[0], GroupId = groups[parts[1]], CreatedUtc = D_Z };
            list.Add(t); byName[parts[0]] = t;
        }
        return (list, byName, groups);
    }

    // ---- E13/E14 XLSX ------------------------------------------------------------------------------------------------

    private static (Procedure Proc, AppRepository Repo) ChecklistSetup(string sub)
    {
        var d = new AppData();
        var t = MkTask(3, "Fire drill"); t.Subtasks.Add(MkTask(5, "Muster")); d.Tasks.Add(t);
        d.Equipment.Add(Equip(1, "Main Engine"));
        Procedure p;
        switch (sub)
        {
            case "X1":
                p = Proc(4, "Pump & Valve <weekly>");
                var s1 = Step(71, "Check \"seal\" & <gasket>"); s1.Done = true; s1.Deadline = Day(2026, 10, 5);
                s1.TaskIds.Add(G(3)); s1.TaskIds.Add(G(5)); s1.TaskIds.Add(G(99)); s1.EquipmentIds.Add(G(1));
                var s2 = Step(72, "Drain"); s2.Deadline = new DateTime(2026, 10, 6, 14, 30, 0, DateTimeKind.Local);
                var s3 = Step(73, "Log");
                p.Steps.Add(s1); p.Steps.Add(s2); p.Steps.Add(s3);
                break;
            case "X2": p = Proc(4, "Empty procedure"); break;
            case "X3a": p = Proc(4, new string('a', 40)); p.Steps.Add(Step(71, "one")); break;
            case "X3b": p = Proc(4, new string('a', 29) + "&b"); p.Steps.Add(Step(71, "one")); break;
            default: p = Proc(4, ""); p.Steps.Add(Step(71, "vertical\u000Btab")); break;
        }
        d.Procedures.Add(p);
        return (p, new AppRepository(d));
    }

    private static byte[] ZipBytes(string path) => System.IO.File.ReadAllBytes(path);

    // ---- catalogue ---------------------------------------------------------------------------------------------------

    public static IEnumerable<CaseDef> Cases()
    {
        foreach (var c in E01()) yield return c;
        foreach (var c in E02()) yield return c;

        yield return new CaseDef
        {
            Id = "E03", Family = F, Compare = "json-semantic",
            Title = "SearchService.PlainTextFromXaml and DataDiff.PlainText side by side",
            Settles = new[] { "02 §7.7", "01 §7.8", "GF.8.4" },
            Run = r =>
            {
                var rows = new JsonArray();
                foreach (var x in PlainTextInputs)
                    rows.Add(new JsonObject
                    {
                        ["input"] = x, ["search"] = SearchService.PlainTextFromXaml(x),
                        ["diff"] = Call<string>(typeof(DataDiff), "PlainText", x),
                    });
                rows.Add(new JsonObject { ["input"] = null, ["search"] = SearchService.PlainTextFromXaml(null), ["diff"] = Call<string>(typeof(DataDiff), "PlainText", new object?[] { null }) });
                r.Json("result", "plaintext", rows);
            },
        };

        foreach (var c in E04()) yield return c;

        yield return new CaseDef
        {
            Id = "E05", Family = F, Compare = "json-semantic", Title = "WorkRange.Coerce matrix (ticks and kind)",
            Settles = new[] { "02 §7.3", "06 §7.1" },
            Run = r =>
            {
                var starts = new DateTime?[] { null, Day(2026, 10, 1), Day(2026, 10, 5), Day(2026, 10, 9), new DateTime(2026, 10, 5, 13, 45, 0, DateTimeKind.Local) };
                var deadlines = new DateTime?[] { null, Day(2026, 10, 5), new DateTime(2026, 10, 5, 8, 0, 0, DateTimeKind.Local) };
                var rows = new JsonArray();
                foreach (var s in starts)
                    foreach (var d in deadlines)
                        foreach (var edited in new[] { true, false })
                        {
                            var (os, od) = WorkRange.Coerce(s, d, edited);
                            rows.Add(new JsonObject
                            {
                                ["start"] = DateNode(s), ["deadline"] = DateNode(d), ["editedStart"] = edited,
                                ["outStart"] = DateNode(os), ["outDeadline"] = DateNode(od),
                            });
                        }
                r.Json("result", "coerce", rows);
            },
        };

        yield return new CaseDef
        {
            Id = "E06", Family = F, Compare = "json-semantic", Title = "BatchDone T-DONE-1…9 + literal and null in the selection",
            Settles = new[] { "02 §7.2" },
            Run = r =>
            {
                var rows = new (string Id, JsonObject[] Items, string Op, bool Done)[]
                {
                    ("T-DONE-1", new[] { Spec("task", ("isComplete", false), ("status", 1)) }, "setDone", true),
                    ("T-DONE-2", new[] { Spec("task", ("isComplete", false), ("status", 2)) }, "setDone", false),
                    ("T-DONE-3", new[] { Spec("task", ("isComplete", true)) }, "setDone", false),
                    ("T-DONE-4", new[] { Spec("task", ("isComplete", true)) }, "setStatusInProgress", false),
                    ("T-DONE-5", new[] { Spec("procedure", ("status", 1)) }, "setDone", false),
                    ("T-DONE-6", new[] { Spec("procedure", ("status", 3)) }, "setDone", false),
                    ("T-DONE-7", new[] { Spec("procedure", ("status", 2)) }, "setDone", true),
                    ("T-DONE-8", new[] { Spec("step", ("done", true)) }, "setDone", true),
                    ("T-DONE-9", new[] { Spec("task", ("isComplete", false)), Spec("step", ("done", true)), Spec("procedure", ("status", 3)), Spec("literal", ("value", "x")), Spec("null") }, "setDoneAll", true),
                };
                var arr = new JsonArray();
                foreach (var (id, items, op, done) in rows)
                {
                    var objs = items.Select(Build).ToList();
                    JsonNode? ret = op switch
                    {
                        "setDone" => BatchDone.SetDone(objs[0], done),
                        "setDoneAll" => BatchDone.SetDoneAll(objs, done),
                        _ => SetInProgress(objs[0]),
                    };
                    arr.Add(new JsonObject
                    {
                        ["id"] = id, ["items"] = new JsonArray(items.Select(i => (JsonNode?)i.DeepClone()).ToArray()), ["op"] = op, ["done"] = done,
                        ["returned"] = ret, ["after"] = new JsonArray(objs.Select(o => (JsonNode?)State(o)).ToArray()),
                    });
                }
                r.Json("result", "batch-done", arr);
            },
        };

        yield return new CaseDef
        {
            Id = "E07", Family = F, Compare = "json-semantic", Title = "BatchDeadline T-DL-1…8 (incl. Local vs Unspecified equality)",
            Settles = new[] { "02 §7.3" },
            Run = r =>
            {
                var rows = new (string Id, JsonObject Item, string? Date)[]
                {
                    ("T-DL-1", Spec("task"), null),
                    ("T-DL-2", Spec("task", ("rangeStart", "2026-10-01"), ("deadline", "2026-10-05")), null),
                    ("T-DL-3", Spec("task", ("rangeStart", "2026-10-01"), ("deadline", "2026-10-05")), "2026-10-03"),
                    ("T-DL-4", Spec("task", ("rangeStart", "2026-10-01"), ("deadline", "2026-10-05")), "2026-09-28"),
                    ("T-DL-5", Spec("task", ("deadline", "2026-10-05")), "2026-10-05 14:00"),
                    ("T-DL-6a", Spec("procedure", ("deadline", "2026-10-05")), "2026-10-05"),
                    ("T-DL-6b", Spec("procedure", ("deadline", "2026-10-05")), null),
                    ("T-DL-7a", Spec("equipment"), "2026-10-05"),
                    ("T-DL-7b", Spec("null"), "2026-10-05"),
                    ("T-DL-8", Spec("task", ("deadline", "2026-10-05 Local")), "2026-10-05"),
                    ("step", Spec("step", ("deadline", "2026-10-05")), "2026-10-06 09:30"),
                };
                var arr = new JsonArray();
                foreach (var (id, item, date) in rows)
                {
                    var o = Build(item);
                    var ret = BatchDeadline.SetDeadline(o, date == null ? null : ParseDate(date));
                    arr.Add(new JsonObject { ["id"] = id, ["item"] = item.DeepClone(), ["date"] = date, ["returned"] = ret, ["after"] = State(o) });
                }
                r.Json("result", "batch-deadline", arr);
            },
        };

        foreach (var c in E08()) yield return c;

        yield return new CaseDef
        {
            Id = "E09", Family = F, Compare = "json-semantic", DependsOnToday = true,
            Title = "DateResolver: Resolve rows, Observe/Infer, ExpandYear, FromExcelSerial, IsPlaceholder",
            Settles = new[] { "09 §7.2", "09 §7.3", "09 §7.4" },
            Run = r =>
            {
                var resolve = new JsonArray();
                foreach (var (input, role, order) in ResolveRows)
                {
                    var dr = new DateResolver();
                    dr.Adopt(order);
                    var o = Resolution(dr.Resolve(input, role));
                    o["input"] = input; o["role"] = role.ToString(); o["order"] = order.ToString();
                    resolve.Add(o);
                }
                var infer = new JsonArray();
                var sets = new (string[] Values, DateOrder Fallback)[]
                {
                    (new[] { "15/07/2026", "03/04/2026" }, DateOrder.Unknown), (new[] { "07/15/2026", "03/04/2026" }, DateOrder.Unknown),
                    (new[] { "15/07/2026", "07/15/2026" }, DateOrder.Unknown), (new[] { "03/04/2026", "2026-07-15", "12 Mar 2026" }, DateOrder.Unknown),
                    (new[] { "15/07/2026 10:00" }, DateOrder.Unknown), (new[] { "45/03/2026", "13/13/2026", "15/07/202" }, DateOrder.Unknown),
                    (new[] { "31/02/2026" }, DateOrder.Unknown), (Enumerable.Repeat("15/07/2026", 60).ToArray(), DateOrder.Unknown),
                    (new[] { "03/04/2026" }, DateOrder.DayFirst), (new[] { "15/07/2026", "07/15/2026" }, DateOrder.DayFirst),
                };
                foreach (var (values, fallback) in sets)
                {
                    var dr = new DateResolver();
                    foreach (var v in values) dr.Observe(v);
                    dr.Infer(fallback);
                    infer.Add(new JsonObject
                    {
                        ["values"] = new JsonArray(values.Select(x => (JsonNode?)x).ToArray()), ["fallback"] = fallback.ToString(),
                        ["Order"] = dr.Order.ToString(), ["DecisiveCount"] = dr.DecisiveCount,
                    });
                }
                var expand = new JsonArray();
                foreach (var role in new[] { DateRole.Any, DateRole.PastOnly, DateRole.FutureLikely })
                    foreach (var y in new[] { 0, 5, 20, 21, 26, 27, 30, 68, 69, 98, 99, 100, 2026 })
                        expand.Add(new JsonObject { ["y"] = y, ["role"] = role.ToString(), ["result"] = Call<int>(typeof(DateResolver), "ExpandYear", y, role, false) });
                var serial = new JsonArray();
                foreach (var v in new[] { 0, 0.5, 1, 1.999, 59, 60, 61, 45000.75, 46096, 73051, 73052, -1, double.NaN, double.PositiveInfinity })
                    foreach (var use1904 in new[] { false, true })
                    {
                        var d = DateResolver.FromExcelSerial(v, use1904);
                        serial.Add(new JsonObject { ["serial"] = v.ToString("R", CultureInfo.InvariantCulture), ["use1904"] = use1904, ["result"] = d?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) });
                    }
                var placeholder = new JsonArray();
                foreach (var s in new[] { "N/A", "n/a", "TBC", "Pending", "#REF!", "NULL", "0", "00/00/0000", "1900-01-01", "01/01/1900", "30/12/1899", "x", "X", "", "  ", "2026-03-04" })
                    placeholder.Add(new JsonObject { ["input"] = s, ["result"] = DateResolver.IsPlaceholder(s) });
                r.Json("result", "dateresolver", new JsonObject
                {
                    ["today"] = DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                    ["resolve"] = resolve, ["infer"] = infer, ["expandYear"] = expand, ["fromExcelSerial"] = serial, ["isPlaceholder"] = placeholder,
                });
            },
        };

        for (int z = 0; z < JsonZones.Length; z++)
        {
            var tz = JsonZones[z];
            yield return new CaseDef
            {
                Id = $"E10.{z + 1}", Family = F, Runs = Runs.Unix, Tz = tz, Compare = "json-semantic", DependsOnToday = true,
                Title = $"CrewMember.ParseDate rows and ContractStatusOn in {tz}",
                Settles = new[] { "09 §7.1", "09 §7.8", "10:1637" },
                Run = r =>
                {
                    var rows = new JsonArray();
                    foreach (var s in ParseDateInputs)
                        rows.Add(new JsonObject { ["input"] = s, ["value"] = DateNode(CrewMember.ParseDate(s)) });
                    rows.Add(new JsonObject { ["input"] = null, ["value"] = DateNode(CrewMember.ParseDate(null)) });
                    var contract = new JsonArray();
                    foreach (var so in new[] { "2026-09-28", "2026-09-29", "2026-10-29", "2026-10-30", "2026-11-28", "2026-11-29", "", "garbage", "31/12/2026" })
                    {
                        var m = new CrewMember { SignOffDate = so };
                        contract.Add(new JsonObject
                        {
                            ["signOff"] = so, ["days"] = m.DaysUntilSignOff(Day(2026, 9, 29)),
                            ["status"] = m.ContractStatusOn(Day(2026, 9, 29)).ToString(),
                        });
                    }
                    r.Input("today", "2026-09-29");
                    r.Json("result", "parsedate", new JsonObject { ["tz"] = tz, ["parseDate"] = rows, ["contract"] = contract });
                },
            };
        }

        yield return new CaseDef
        {
            Id = "E11", Family = F, Compare = "json-semantic", DependsOnToday = true,
            Title = "CrewConverter over the 09 §7.6 rows under five date-evidence sets",
            Settles = new[] { "09 §7.6", "09 §7.5" },
            Run = r =>
            {
                var rowsJson = r.AuthoredInput("E11.rows.json");
                var rowSets = JsonNode.Parse(rowsJson)!.AsObject();
                var result = new JsonObject();
                foreach (var (setName, fallback) in new[] { ("dayFirstProof", DateOrder.Unknown), ("monthFirstProof", DateOrder.Unknown),
                                                            ("conflicted", DateOrder.Unknown), ("none", DateOrder.Unknown), ("none", DateOrder.DayFirst) })
                {
                    var rows = new List<CompasRow>();
                    foreach (var row in rowSets["rows"]!.AsArray())
                        rows.Add(new CompasRow(row!.AsObject().ToDictionary(kv => CrewText.Norm(kv.Key), kv => (string?)kv.Value ?? "")));
                    foreach (var row in rowSets["evidence"]![setName]!.AsArray())
                        rows.Add(new CompasRow(row!.AsObject().ToDictionary(kv => CrewText.Norm(kv.Key), kv => (string?)kv.Value ?? "")));
                    var conv = new CrewConverter("compas-fixture.xlsx");
                    typeof(CrewConverter).GetField("_importedAt", BindingFlags.NonPublic | BindingFlags.Instance)!.SetValue(conv, "2026-09-29 14:05");
                    conv.LearnDateFormat(rows, fallback);
                    var members = new JsonArray();
                    foreach (var row in rows)
                    {
                        var m = conv.Convert(row);
                        r.Mask.Guid(m.Id);
                        members.Add(JsonNode.Parse(JsonSerializer.Serialize(m, Opts)));
                    }
                    result[$"{setName}/{fallback}"] = new JsonObject
                    {
                        ["members"] = members, ["DateSummary"] = conv.DateSummary(), ["UnreadableDates"] = conv.UnreadableDates,
                        ["OrderDependentDates"] = conv.OrderDependentDates, ["DateOrder"] = conv.DateOrder.ToString(), ["DateEvidence"] = conv.DateEvidence,
                    };
                }
                r.Json("result", "crewconverter", result);
            },
        };

        foreach (var row in OrdRows)
        {
            var divergent = row.Id is "T-ORD-6" or "T-ORD-7";
            yield return new CaseDef
            {
                Id = "E12." + row.Id[6..], Family = F, Compare = "json-semantic",
                Title = $"SavedListOrder {row.Id}: {row.Call}([{row.Picks}]{(row.Call == "moveTo" ? ", " + row.Target : row.Up ? ", up" : ", down")}) over {row.All}",
                Settles = new[] { "02 §7.9", "06 §7.4" },
                Run = r =>
                {
                    var (all, byName, groups) = OrdSetup(row.All);
                    var picks = row.Picks.Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(n => byName[n]).ToList();
                    var ret = row.Call == "nudge" ? SavedListOrder.Nudge(all, picks, row.Up) : SavedListOrder.MoveTo(all, picks, row.Target);
                    var perGroup = new JsonObject();
                    foreach (var (gname, gid) in groups)
                    {
                        var names = all.Where(t => t.GroupId == gid).Select(t => (JsonNode?)t.Name).ToArray();
                        if (names.Length > 0) perGroup[gname] = new JsonArray(names);
                    }
                    r.Input("all", row.All); r.Input("call", row.Call); r.Input("picks", row.Picks);
                    r.Input("target", row.Target); r.Input("up", row.Up);
                    r.Json("result", "order", new JsonObject
                    {
                        ["returned"] = ret, ["flat"] = new JsonArray(all.Select(t => (JsonNode?)t.Name).ToArray()), ["groups"] = perGroup,
                    });
                    if (divergent) r.DivergentRecordOnly("DECISIONS 02 Q-1 / 02 D-1: the Mac's fixed Nudge yields the intended group order (asserted by F2's tests)");
                },
            };
        }
        yield return new CaseDef
        {
            Id = "E12.14", Family = F, Compare = "json-semantic", Title = "SavedListOrder AllEntries / GroupEntries (T-ORD-14…16)",
            Settles = new[] { "02 §7.9" },
            Run = r =>
            {
                var d = new AppData();
                d.ListGroups.Add(new ListGroup { Id = G(901), Name = "alpha", CreatedUtc = D_Z });
                d.ListGroups.Add(new ListGroup { Id = G(902), Name = "Beta", CreatedUtc = D_Z });
                d.ListGroups.Add(new ListGroup { Id = G(903), Name = "", CreatedUtc = D_Z });
                void T(int n, string name, Guid? g) => d.ChecklistTemplates.Add(new ChecklistTemplate { Id = G(n), Name = name, GroupId = g, CreatedUtc = D_Z });
                T(911, "T1", G(902)); T(912, "T2", null); T(913, "T3", G(901)); T(914, "T4", G(902)); T(915, "T5", G(901));
                T(916, "T6", G(999)); T(917, "T7", G(903));
                var data = Input(r, "data", d, "data");
                JsonArray Entries(List<(string? Group, ChecklistTemplate Template)> e) =>
                    new(e.Select(x => (JsonNode?)new JsonObject { ["group"] = x.Group, ["template"] = x.Template.Name }).ToArray());
                r.Json("result", "entries", new JsonObject
                {
                    ["allEntries"] = Entries(SavedListOrder.AllEntries(data)),
                    ["groupEntries.alpha"] = Entries(SavedListOrder.GroupEntries(data, G(901))),
                    ["groupEntries.unnamed"] = Entries(SavedListOrder.GroupEntries(data, G(903))),
                    ["groupEntries.ungrouped"] = Entries(SavedListOrder.GroupEntries(data, null)),
                });
            },
        };

        foreach (var sub in new[] { "X1", "X2", "X3a", "X3b", "X4" })
        {
            var divergent = sub is "X3b" or "X4";
            yield return new CaseDef
            {
                Id = "E13." + sub, Family = F, Runs = Runs.Both, NormativeWindows = "record-only", Compare = "zip-manifest-ordered",
                Title = "ChecklistExporter.ExportXlsx " + sub + (divergent ? " (Windows defect recorded; Mac divergent per 11 §7.14)" : ""),
                Settles = new[] { "11 §4.5", "11 §7.14", "09 §7.13" },
                Run = r =>
                {
                    var (proc, repo) = ChecklistSetup(sub);
                    var path = Path.Combine(r.DataDir, "checklist.xlsx");
                    ChecklistExporter.ExportXlsx(proc, repo, path);
                    var bytes = ZipBytes(path);
                    r.Side(r.Id + ".checklist.xlsx", bytes, mask: false);
                    ZipInspect.WriteManifest(r, "xlsx", bytes, orderSignificant: true);
                    if (divergent) r.DivergentRecordOnly("11 §7.14 / DEV-03: the Mac escapes after truncating and drops XML-illegal control characters");
                },
            };
        }
        var xlsxSheets = new[] { "", "Crew & Co", new string('S', 40) };
        for (int i = 0; i < xlsxSheets.Length; i++)
        {
            var sheet = xlsxSheets[i];
            yield return new CaseDef
            {
                Id = $"E14.{i + 1}", Family = F, Runs = Runs.Both, NormativeWindows = "record-only", Compare = "zip-manifest-ordered",
                Title = $"XlsxWriter.Write with sheet name \"{(sheet.Length > 12 ? sheet[..12] + "…" : sheet)}\"",
                Settles = new[] { "09 §7.13", "11 §4.5" },
                Run = r =>
                {
                    var headers = new[] { "Rank", "Name", "Sign-off" };
                    var rows = new List<string[]>
                    {
                        new[] { "Master", "Juan" },
                        new[] { "Chief Officer", "Ana", "2026-10-01", "extra" },
                        new[] { "2E", null!, "2026-12-01" },
                        new[] { "a\u0001b", "x\ty", "\"q\" & <t>" },
                    };
                    var path = Path.Combine(r.DataDir, "crew.xlsx");
                    XlsxWriter.Write(path, sheet, headers, rows);
                    r.Input("sheetName", sheet);
                    r.Input("headers", new JsonArray(headers.Select(h => (JsonNode?)h).ToArray()));
                    r.Input("rows", new JsonArray(rows.Select(row => (JsonNode?)new JsonArray(row.Select(c => (JsonNode?)c).ToArray())).ToArray()));
                    var bytes = ZipBytes(path);
                    r.Side(r.Id + ".crew.xlsx", bytes, mask: false);
                    ZipInspect.WriteManifest(r, "xlsx", bytes, orderSignificant: true);
                },
            };
        }

        yield return new CaseDef
        {
            Id = "E15", Family = F, Compare = "json-semantic", Title = "casing probes: model keys, ClassifyFile, ResolveFilePath, invariant casing",
            Settles = new[] { "GF.8.4", "01 §3.21" },
            Run = r =>
            {
                var chars = new[] { "İSTANBUL", "ΣΊΣΥΦΟΣ", "ǅ", "K", "ẞ", "ß", "ı", "ǆ", "ﬁ", "mast", "Straße", "STRASSE", "σς" };
                var rows = new JsonArray();
                foreach (var c in chars)
                    rows.Add(new JsonObject
                    {
                        ["input"] = c, ["lower"] = c.ToLowerInvariant(), ["upper"] = c.ToUpperInvariant(),
                        ["portKey"] = new Port { UnLocode = c }.Key, ["portKeyByName"] = new Port { Name = c, Country = "Nigeria" }.Key,
                        ["portCallKey"] = new PortCall { PortName = c, ArrivalDate = "2026-05-01" }.Key,
                        ["visitKey"] = new PortVisit { VesselName = c, ArrivalDate = "2026-05-01", ArrivalTime = "08:00" }.VisitKey,
                    });
                var crew = new JsonArray();
                foreach (var (id, first, last) in new[] { ("123", "", ""), (" ", "Ana", "Cruz"), ("", "Juan", ""), ("", "", "Cruz"), ("", "", "") })
                    crew.Add(new JsonObject { ["employeeId"] = id, ["first"] = first, ["last"] = last, ["key"] = new CrewMember { EmployeeId = id, FirstName = first, LastName = last }.Key });
                var classify = new JsonArray();
                foreach (var p in new[] { ".PDF", ".JPEG", "X.PDF", "a.HEIC" })
                    classify.Add(new JsonObject { ["path"] = p, ["kind"] = (int)DataStore.ClassifyFile(p) });
                var resolve = new JsonArray();
                foreach (var p in new[] { "HTTPS://x", "MAILTO:a@b", "Http://y" })
                    resolve.Add(new JsonObject { ["stored"] = p, ["resolved"] = DataStore.ResolveFilePath(p) });
                r.Json("result", "casing", new JsonObject { ["strings"] = rows, ["crewKey"] = crew, ["classify"] = classify, ["resolve"] = resolve });
            },
        };
        yield return new CaseDef
        {
            Id = "E15b", Family = F, Compare = "json-semantic", Title = "casing probes through CrewConverter (Rank/Gender/Nationality codes)",
            Settles = new[] { "GF.8.4", "09 §7.6" },
            Run = r =>
            {
                var conv = new CrewConverter("compas-fixture.xlsx");
                typeof(CrewConverter).GetField("_importedAt", BindingFlags.NonPublic | BindingFlags.Instance)!.SetValue(conv, "2026-09-29 14:05");
                var rows = new JsonArray();
                foreach (var v in new[] { "ß", "ı", "ǆ", "ﬁ", "mast" })
                {
                    var row = new CompasRow(new Dictionary<string, string>
                    {
                        [CrewText.Norm("First name")] = "Juan", [CrewText.Norm("Surname")] = "Cruz", [CrewText.Norm("Rank")] = v,
                        [CrewText.Norm("Gender")] = v, [CrewText.Norm("Nationality code")] = v, [CrewText.Norm("Nationality")] = v,
                    });
                    var m = conv.Convert(row);
                    rows.Add(new JsonObject { ["cell"] = v, ["Rank"] = m.Rank, ["RankCode"] = m.RankCode, ["Gender"] = m.Gender, ["Nationality"] = m.Nationality });
                }
                r.Json("result", "crew-casing", rows);
            },
        };

        foreach (var c in E16()) yield return c;
    }

    private static bool SetInProgress(object? o)
    {
        if (o is TaskItem t) { t.Status = WorkStatus.InProgress; return true; }
        return false;
    }

    // ---- E16 model computed strings & helpers --------------------------------------------------------------------------

    private static IEnumerable<CaseDef> E16()
    {
        yield return new CaseDef
        {
            Id = "E16", Family = F, Compare = "json-semantic", Title = "WhenText/HasRange/RangeFirst/CoversDay, DaysUntilDue, SIRE state, comparer",
            Settles = new[] { "02 T-RNG-8/9", "01 §7.10", "12 §7.2", "12 §7.8" },
            Run = r =>
            {
                var ranges = new (string? Start, string? Deadline)[]
                {
                    (null, "2026-10-05"), ("2026-10-01", "2026-10-05"), ("2026-10-05 10:00", "2026-10-05"), ("2026-10-09", "2026-10-05"),
                    ("2026-10-01", null), ("2026-10-07", "2026-10-05"),
                };
                var days = new[] { "2026-09-30", "2026-10-01", "2026-10-03", "2026-10-05 23:59", "2026-10-06" };
                var rangeRows = new JsonArray();
                foreach (var (s, d) in ranges)
                {
                    var t = MkTask(3, "t");
                    if (s != null) t.RangeStart = ParseDate(s);
                    if (d != null) t.Deadline = ParseDate(d);
                    var covers = new JsonObject();
                    foreach (var day in days) covers[day] = t.CoversDay(ParseDate(day));
                    rangeRows.Add(new JsonObject
                    {
                        ["start"] = s, ["deadline"] = d, ["WhenText"] = t.WhenText, ["HasRange"] = t.HasRange,
                        ["RangeFirst"] = DateNode(t.RangeFirst), ["CoversDay"] = covers,
                    });
                }
                var jobs = new JsonArray();
                foreach (var due in new[] { "2026-10-15", "2026-09-29", "2026-09-01", "", "garbage", "15/10/2026" })
                    jobs.Add(new JsonObject { ["DueDate"] = due, ["DaysUntilDue"] = new ShipJob { DueDate = due }.DaysUntilDue(Day(2026, 9, 29)) });
                var sire = new SireState();
                sire.QuestionStatuses["a"] = "InProgress"; sire.QuestionStatuses["b"] = "2"; sire.QuestionStatuses["c"] = "checked";
                sire.QuestionStatuses["d"] = "Bogus"; sire.QuestionStatuses["e"] = "Checked";
                var status = new JsonObject();
                foreach (var q in new[] { "a", "b", "c", "d", "e", "missing" }) status[q] = sire.GetStatus(q).ToString();
                var counts = new JsonObject();
                foreach (var st in Enum.GetValues<QuestionStatus>()) counts[st.ToString()] = sire.CountByStatus(st);
                sire.ToggleBookmark("1.1.1"); sire.ToggleBookmark("2.1.1"); sire.ToggleBookmark("1.1.1");
                sire.ToggleForExport("3.1"); sire.ToggleForExport("3.1"); sire.ToggleForExport("4.1");
                var order = new List<string> { "1.10", "1.2", "1.1.1", "11.1", "2", "a.1", "1..2" };
                order.Sort(QuestionNumberComparer.Instance);
                r.Json("result", "computed", new JsonObject
                {
                    ["ranges"] = rangeRows, ["daysUntilDue"] = jobs, ["sireStatus"] = status, ["sireCounts"] = counts,
                    ["bookmarks"] = new JsonArray(sire.Bookmarks.Select(x => (JsonNode?)x).ToArray()),
                    ["forExport"] = new JsonArray(sire.ForExport.Select(x => (JsonNode?)x).ToArray()),
                    ["questionOrder"] = new JsonArray(order.Select(x => (JsonNode?)x).ToArray()),
                });
            },
        };
        for (int z = 0; z < JsonZones.Length; z++)
        {
            var tz = JsonZones[z];
            yield return new CaseDef
            {
                Id = $"E16.{z + 1}", Family = F, Runs = Runs.Unix, Tz = tz, Compare = "json-semantic",
                Title = $"Display strings in {tz}: TrashedItem.DeletedLocal/Display, LogEntry.TimeUtc/TimeLocal, BundleSource.WrittenLocal",
                Settles = new[] { "01 §3.22", "01 §7.10" },
                Run = r =>
                {
                    var ti = new TrashedItem { Name = "Old tug", KindLabel = "Vessel", DeletedUtc = D_Z0 };
                    var unnamed = new TrashedItem { Name = "", KindLabel = "Task", DeletedUtc = D_Z };
                    var log = new LogEntry { TimestampUtc = D_Z0 };
                    var src = new BundleSource { WrittenUtc = D_Z };
                    r.Json("result", "display", new JsonObject
                    {
                        ["tz"] = tz, ["DeletedLocal"] = ti.DeletedLocal, ["Display"] = ti.Display, ["DisplayUnnamed"] = unnamed.Display,
                        ["TimeUtc"] = log.TimeUtc, ["TimeLocal"] = log.TimeLocal, ["WrittenLocal"] = src.WrittenLocal,
                    });
                },
            };
        }
        yield return new CaseDef
        {
            Id = "E16.th", Family = F, Compare = "json-semantic", Normative = "record-only",
            Title = "culture probe: WhenText and DataDiff.Fmt under th-TH (Buddhist calendar)", Settles = new[] { "01 §7.10" },
            Run = r =>
            {
                var t = MkTask(3, "t"); t.Deadline = Day(2026, 10, 5);
                World.PinCulture("th-TH");
                try
                {
                    r.Json("result", "culture", new JsonObject
                    {
                        ["culture"] = CultureInfo.CurrentCulture.Name, ["WhenText"] = t.WhenText,
                        ["Fmt"] = Call<string>(typeof(DataDiff), "Fmt", (DateTime?)Day(2026, 10, 5)),
                    }, mac: false);
                }
                finally { World.PinCulture(); }
            },
        };
    }
}
