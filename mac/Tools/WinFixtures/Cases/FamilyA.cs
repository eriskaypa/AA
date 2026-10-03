// Family (a) `data.json` — cases A01–A26 (spec 01 GF.5.a, DATA-315).
using System.Globalization;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AA.Models;
using AA.Services;
using static WinFixtures.Fx;

namespace WinFixtures;

internal static class FamilyA
{
    private const string F = "json";
    private static string Gs(int n) => G(n).ToString("D");

    public static IEnumerable<CaseDef> Cases()
    {
        // ---- A01–A05: whole-database serialisation ----------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "A01", Family = F, Title = "new AppData() → SerializeForSave (the empty database string)",
            Settles = new[] { "01 §4.2.1" },
            Run = r => r.Text("result", "appdata", "json", DataStore.SerializeForSave(new AppData())),
        };
        yield return new CaseDef
        {
            Id = "A02", Family = F, Title = "kitchen sink → SerializeForSave (property order, escaping, kinds)",
            Settles = new[] { "01:1438 §4.1.3", "01 §8.2 Q-2", "04:931", "06 §7.14" },
            Run = r => r.Text("result", "appdata", "json", DataStore.SerializeForSave(KitchenSink.Build())),
        };
        yield return new CaseDef
        {
            Id = "A03", Family = F, Title = "A02 bytes → LoadFrom → SerializeForSave (idempotence)",
            Settles = new[] { "01 §7.14-1" },
            Run = r =>
            {
                var a02 = DataStore.SerializeForSave(KitchenSink.Build());
                r.Input("from", "json/A02.appdata.golden.json");
                var path = r.Data("data.json");
                File.WriteAllText(path, a02, Utf8NoBom);
                var again = DataStore.SerializeForSave(DataStore.LoadFrom(path));
                if (again != a02) Console.Error.WriteLine("  note: A03 differs from A02 — the golden records Windows' actual behaviour");
                r.Text("result", "appdata", "json", again);
            },
        };
        yield return new CaseDef
        {
            Id = "A04", Family = F, Title = "one instance of every type, only ids/dates fixed → written defaults",
            Settles = new[] { "01 §4.1.2", "01 §4.1.10" },
            Run = r => r.Text("result", "appdata", "json", DataStore.SerializeForSave(KitchenSink.Defaults())),
        };
        yield return new CaseDef
        {
            Id = "A05", Family = F, Title = "every collection with one {} element → LoadFrom → SerializeForSave (read defaults)",
            Settles = new[] { "01 §4.1.10" },
            Run = r =>
            {
                var input = r.AuthoredInput("A05.input.json");
                var (o, bytes, _) = Shapes.LoadSave(input);
                if (bytes == null) throw new InvalidOperationException("A05 must load: " + o.ToJsonString());
                r.Mask.AutoMask(bytes, input);
                r.Text("result", "appdata", "json", bytes);
            },
        };

        // ---- A06: reference-typed JSON null ----------------------------------------------------------------------
        var nulls = new (string Name, string Doc, object[] Path)[]
        {
            ("Name", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"Name\":null}}]}}", new object[] { "Tasks", 0, "Name" }),
            ("Description", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"Description\":null}}]}}", new object[] { "Tasks", 0, "Description" }),
            ("Tags", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"Tags\":null}}]}}", new object[] { "Tasks", 0, "Tags" }),
            ("RelatedIds", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"RelatedIds\":null}}]}}", new object[] { "Tasks", 0, "RelatedIds" }),
            ("BucketIds", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"BucketIds\":null}}]}}", new object[] { "Tasks", 0, "BucketIds" }),
            ("Container", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"Container\":null}}]}}", new object[] { "Tasks", 0, "Container" }),
            ("Files", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"Container\":{{\"Id\":\"{Gs(103)}\",\"Files\":null}}}}]}}", new object[] { "Tasks", 0, "Container", "Files" }),
            ("RichTextXaml", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"Container\":{{\"Id\":\"{Gs(103)}\",\"RichTextXaml\":null}}}}]}}", new object[] { "Tasks", 0, "Container", "RichTextXaml" }),
            ("Subtasks", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"Subtasks\":null}}]}}", new object[] { "Tasks", 0, "Subtasks" }),
            ("Steps", $"{{\"Procedures\":[{{\"Id\":\"{Gs(4)}\",\"Steps\":null}}]}}", new object[] { "Procedures", 0, "Steps" }),
            ("Ui", "{\"Ui\":null}", new object[] { "Ui" }),
            ("Sire", "{\"Sire\":null}", new object[] { "Sire" }),
            ("LockHash", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"LockHash\":null}}]}}", new object[] { "Tasks", 0, "LockHash" }),
            ("Ui.TabColors", "{\"Ui\":{\"TabColors\":null}}", new object[] { "Ui", "TabColors" }),
        };
        for (int i = 0; i < nulls.Length; i++)
        {
            var (name, doc, path) = nulls[i];
            yield return new CaseDef
            {
                Id = $"A06.{i + 1}", Family = F, Title = $"\"{name}\": null → load/save outcome",
                Settles = new[] { "01 §4.1.10" },
                Run = r => LoadSaveCase(r, doc, Shapes.WithoutMember(doc, path),
                                        "01 §4.1.10 SHOULD: JSON null reads as the property's default"),
            };
        }

        // ---- A07: value-type null and type mismatches ------------------------------------------------------------
        string TaskDoc(string member) => $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",{member}}}]}}";
        var mismatches = new (string Title, string Doc, string Level)[]
        {
            ("\"IsJob\":null", TaskDoc("\"IsJob\":null"), "record-only"),
            ("\"DurationMinutes\":null", TaskDoc("\"DurationMinutes\":null"), "record-only"),
            ("\"Id\":null", "{\"Tasks\":[{\"Id\":null,\"Name\":\"x\"}]}", "record-only"),
            ("\"Added\":null", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"Container\":{{\"Id\":\"{Gs(103)}\",\"Files\":[{{\"Id\":\"{Gs(201)}\",\"Added\":null}}]}}}}]}}", "record-only"),
            ("\"Status\":\"Done\"", TaskDoc("\"Status\":\"Done\""), "record-only"),
            ("\"DurationMinutes\":\"60\"", TaskDoc("\"DurationMinutes\":\"60\""), "record-only"),
            ("\"DurationMinutes\":60.0", TaskDoc("\"DurationMinutes\":60.0"), "record-only"),
            ("\"DurationMinutes\":6E1", TaskDoc("\"DurationMinutes\":6E1"), "record-only"),
            ("\"Name\":5", TaskDoc("\"Name\":5"), "record-only"),
            ("\"IsJob\":1", TaskDoc("\"IsJob\":1"), "record-only"),
            ("\"Recurrence\":7 (undefined enum value round-trips)", TaskDoc("\"Recurrence\":7"), "must"),
            ("\"SelectedMainTabIndex\":2147483648", "{\"Ui\":{\"SelectedMainTabIndex\":2147483648}}", "record-only"),
        };
        for (int i = 0; i < mismatches.Length; i++)
        {
            var (title, doc, level) = mismatches[i];
            yield return new CaseDef
            {
                Id = $"A07.{i + 1}", Family = F, Title = title + " → outcome", Normative = level,
                Settles = new[] { "01 §3.2", "01 §4.1.10" },
                Run = r => LoadSaveCase(r, doc, null, null),
            };
        }

        // ---- A08: GUID forms --------------------------------------------------------------------------------------
        var guidForms = new (string Title, string Text)[]
        {
            ("upper-case D", "3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
            ("braces", "{3f2504e0-4f89-11d3-9a0c-0305e82c3301}"),
            ("N (32 hex)", "3f2504e04f8911d39a0c0305e82c3301"),
            ("parentheses", "(3f2504e0-4f89-11d3-9a0c-0305e82c3301)"),
            ("Guid.Empty", "00000000-0000-0000-0000-000000000000"),
            ("35 characters", "3f2504e0-4f89-11d3-9a0c-0305e82c330"),
        };
        for (int i = 0; i < guidForms.Length; i++)
        {
            var (title, text) = guidForms[i];
            yield return new CaseDef
            {
                Id = $"A08.{i + 1}", Family = F, Title = $"GUID {title} → load outcome + re-write", Normative = "should",
                Settles = new[] { "01 §4.1.4", "01 §7.4" },
                Run = r => LoadSaveCase(r, $"{{\"Tasks\":[{{\"Id\":\"{text}\",\"Name\":\"g\",\"Container\":{{\"Id\":\"{Gs(103)}\"}}}}]}}", null, null),
            };
        }

        // ---- A09: escaping ----------------------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "A09a", Family = F, Title = "default JavaScriptEncoder escaping set (95 printable ASCII + controls/specials)",
            Settles = new[] { "01 §4.1.7" },
            Run = r =>
            {
                var printable = new string(Enumerable.Range(0x20, 95).Select(c => (char)c).ToArray());
                var special = "\u0000\u0001\b\t\n\u000B\f\r\u001F\u007F\u0080\u009F\u00A0é" + "e\u0301" +
                              "—→⚓😀\u2028\u2029\uFEFF\uFFFD\uFFFF";
                var t = KitchenSink.Task(3, printable);
                t.Description = special;
                r.Input("name", printable);
                r.Input("description", special);
                r.Input("taskId", Gs(3));
                r.Input("containerId", G(1003).ToString("D"));
                r.Text("result", "appdata", "json", DataStore.SerializeForSave(KitchenSink.WithTasks(new[] { t })));
            },
        };
        yield return new CaseDef
        {
            Id = "A09b", Family = F, Title = "lone surrogate tag \\uD800 (Swift strings cannot hold it)", Normative = "record-only",
            Settles = new[] { "01 §4.1.7" },
            Run = r =>
            {
                var t = KitchenSink.Task(3, "lone");
                t.Tags.Add("\uD800");
                string? bytes = null;
                Exception? error = null;
                try { bytes = DataStore.SerializeForSave(KitchenSink.WithTasks(new[] { t })); }
                catch (Exception ex) { error = ex; }
                if (error != null) r.Json("outcome", "outcome", Shapes.ExceptionShape(error, false), mac: false);
                else
                {
                    r.Json("outcome", "outcome", new JsonObject { ["threw"] = false }, mac: false);
                    r.Text("bytes", "appdata", "json", bytes!, mac: false);
                }
            },
        };

        // ---- A10: unknown members -----------------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "A10", Family = F, Title = "unknown members top-level/nested, raw numbers, duplicates, case → load/save",
            Settles = new[] { "01 DATA-024", "01 §7.4" },
            Run = r =>
            {
                var input = r.AuthoredInput("A10.input.json");
                var (o, bytes, _) = Shapes.LoadSave(input);
                r.Json("outcome", "outcome", o);
                if (bytes == null) return;
                r.Mask.AutoMask(bytes, input);
                r.Text("bytes", "appdata", "json", bytes);
                var superset = Derive.MacSuperset(input, bytes);
                r.Mask.AutoMask(superset, input);
                if (superset != bytes)
                    r.Divergent("bytes", superset, "01 DATA-024 (preserve nested unknown keys; re-appended at the end of their object, input order)");
            },
        };

        // ---- A11: legacy BucketId -----------------------------------------------------------------------------------
        var g = Gs(50); var h = Gs(51);
        var buckets = new (string Title, string Doc, string? Derived)[]
        {
            ("{\"BucketId\":g}", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"BucketId\":\"{g}\"}}]}}", null),
            ("BucketIds [g] then BucketId g", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"BucketIds\":[\"{g}\"],\"BucketId\":\"{g}\"}}]}}", null),
            ("legacy BucketId BEFORE BucketIds", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"BucketId\":\"{g}\",\"BucketIds\":[\"{h}\"]}}]}}",
             $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"BucketIds\":[\"{h}\"],\"BucketId\":\"{g}\"}}]}}"),
            ("{\"BucketId\":null}", $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"BucketId\":null}}]}}", null),
            ("BucketId on Procedure/Equipment/Vessel",
             $"{{\"Equipment\":[{{\"Id\":\"{Gs(1)}\",\"BucketId\":\"{g}\"}}],\"Procedures\":[{{\"Id\":\"{Gs(4)}\",\"BucketId\":\"{g}\"}}],\"Vessels\":[{{\"Id\":\"{Gs(8)}\",\"BucketId\":\"{g}\"}}]}}", null),
            ("BucketId on a ChecklistStep (no such property)",
             $"{{\"Procedures\":[{{\"Id\":\"{Gs(4)}\",\"Steps\":[{{\"Id\":\"{Gs(7)}\",\"BucketId\":\"{g}\"}}]}}]}}", "superset"),
        };
        for (int i = 0; i < buckets.Length; i++)
        {
            var (title, doc, derived) = buckets[i];
            yield return new CaseDef
            {
                Id = $"A11.{i + 1}", Family = F, Title = title + " → BucketIds + re-write",
                Settles = new[] { "01 §3.20" },
                Run = r =>
                {
                    if (derived == "superset")
                    {
                        LoadSaveCase(r, doc, null, null);
                        var (_, bytes, _) = Shapes.LoadSave(doc);
                        if (bytes != null)
                        {
                            var superset = Derive.MacSuperset(doc, bytes);
                            r.Mask.AutoMask(superset, doc);
                            if (superset != bytes) r.Divergent("bytes", superset, "01 DATA-024 (an unknown member of a ChecklistStep is preserved on the Mac)");
                        }
                    }
                    else LoadSaveCase(r, doc, derived, "01 §3.20 (the Mac appends a legacy BucketId regardless of key order)");
                },
            };
        }

        // ---- A12: date writing per zone --------------------------------------------------------------------------
        for (int z = 0; z < JsonZones.Length; z++)
        {
            var tz = JsonZones[z];
            var zi = z + 1;
            yield return new CaseDef
            {
                Id = $"A12.{zi}", Family = F, Runs = Runs.Unix, Tz = tz,
                Title = $"DateTime write forms (kinds, fractions, min/max, DST ambiguity and gaps) in {tz}",
                Settles = new[] { "01 §4.1.5", "01 §7.5" },
                Run = r => DateWriteCase(r, includeLocalMin: false),
            };
            yield return new CaseDef
            {
                Id = $"A12.{zi + 6}", Family = F, Runs = Runs.Unix, Tz = tz, Normative = "record-only",
                Title = $"DateTime.MinValue as Local in {tz} (LMT offsets differ between tz databases)",
                Settles = new[] { "01 §4.1.5" },
                Run = r => DateWriteCase(r, includeLocalMin: true),
            };
            yield return new CaseDef
            {
                Id = $"A13.{zi}", Family = F, Runs = Runs.Unix, Tz = tz, Compare = "json-semantic",
                Title = $"DateTime read forms → ticks/kind/rewritten in {tz}",
                Settles = new[] { "01 §4.1.5", "01 §7.5" },
                Run = DateReadCase,
            };
        }
        var crossZones = new[] { "America/New_York", "Asia/Kolkata", "UTC" };
        for (int z = 0; z < crossZones.Length; z++)
        {
            var tz = crossZones[z];
            yield return new CaseDef
            {
                Id = $"A14.{z + 1}", Family = F, Runs = Runs.Unix, Tz = tz,
                Title = $"the Athens-written A12.1 file read and re-written in {tz}",
                Settles = new[] { "01 §4.1.5", "06 §7.14" },
                Run = r =>
                {
                    var athens = r.ReadStaged("json/A12.1.appdata.golden.json");
                    r.Input("from", "json/A12.1.appdata.golden.json");
                    var path = r.Data("data.json");
                    File.WriteAllText(path, athens, Utf8NoBom);
                    r.Text("result", "appdata", "json", DataStore.SerializeForSave(DataStore.LoadFrom(path)));
                },
            };
        }

        // ---- A15: doubles ------------------------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "A15a", Family = F, Title = "QuickCard/Ui double write forms",
            Settles = new[] { "01 §4.1.6" },
            Run = r =>
            {
                var values = new[] { 24, 24.5, -24, 0.1, 0.30000000000000004, 1e15, 1e16, 1.5e-7, 5e-324, 1.7976931348623157e308, -0.0, 123456789.123 };
                var v = new Vessel { Id = G(8), Name = "doubles", Container = new Container { Id = G(108) } };
                for (int i = 0; i < values.Length; i++)
                    v.QuickCards.Add(new QuickCard { Id = G(300 + i), X = values[i], Y = values[i], Width = values[i], Height = values[i] });
                var d = new AppData();
                d.Vessels.Add(v);
                d.Ui.WindowLeft = -0.0; d.Ui.WindowTop = 5e-324; d.Ui.CalendarFontScale = 0.30000000000000004;
                d.Ui.DueWindowWidth = 1e16; d.Ui.DueWindowHeight = 1.5e-7;
                r.Input("values", new JsonArray(values.Select(x => (JsonNode?)x.ToString("R", CultureInfo.InvariantCulture)).ToArray()));
                r.Text("result", "appdata", "json", DataStore.SerializeForSave(d));
            },
        };
        var reads = new[] { "1.0", "1e2", "1E+2", "0.10", "NaN", "1e400" };
        for (int i = 0; i < reads.Length; i++)
        {
            var lit = reads[i];
            yield return new CaseDef
            {
                Id = $"A15.{i + 1}", Family = F, Title = $"read QuickCard X = {lit} → outcome", Normative = "should",
                Settles = new[] { "01 §4.1.6" },
                Run = r => LoadSaveCase(r, $"{{\"Vessels\":[{{\"Id\":\"{Gs(8)}\",\"Container\":{{\"Id\":\"{Gs(108)}\"}},\"QuickCards\":[{{\"Id\":\"{Gs(9)}\",\"X\":{lit}}}]}}]}}", null, null),
            };
        }

        // ---- A16: IsComplete / Status load rule -------------------------------------------------------------------
        var pairs = new List<(string Title, string Members, string? Canonical)>
        {
            ("{\"IsComplete\":true}", "\"IsComplete\":true", null),
            ("{\"IsComplete\":false}", "\"IsComplete\":false", null),
        };
        for (int s = 0; s <= 3; s++) pairs.Add(($"{{\"Status\":{s}}}", $"\"Status\":{s}", null));
        foreach (var b in new[] { "true", "false" })
            for (int s = 0; s <= 3; s++)
                pairs.Add(($"IsComplete {b} then Status {s}", $"\"IsComplete\":{b},\"Status\":{s}", null));
        foreach (var b in new[] { "true", "false" })
            for (int s = 0; s <= 3; s++)
                pairs.Add(($"Status {s} then IsComplete {b} (reversed)", $"\"Status\":{s},\"IsComplete\":{b}", $"\"IsComplete\":{b},\"Status\":{s}"));
        for (int i = 0; i < pairs.Count; i++)
        {
            var (title, members, canonical) = pairs[i];
            yield return new CaseDef
            {
                Id = $"A16.{i + 1}", Family = F, Title = title + " → (Status, IsComplete)",
                Settles = new[] { "01 §4.2.6", "02 T-DONE-10…13" },
                Run = r =>
                {
                    string Doc(string m) => $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"Container\":{{\"Id\":\"{Gs(103)}\"}},{m}}}]}}";
                    var doc = Doc(members);
                    r.Input("inline", doc);
                    var (o, bytes, model) = Shapes.LoadSave(doc);
                    if (model != null)
                    {
                        o["Status"] = (int)model.Tasks[0].Status;
                        o["IsComplete"] = model.Tasks[0].IsComplete;
                    }
                    r.Json("outcome", "outcome", o);
                    if (bytes != null) r.Text("bytes", "appdata", "json", bytes);
                    if (canonical != null && bytes != null)
                    {
                        var (_, derived, _) = Shapes.LoadSave(Doc(canonical));
                        if (derived != null && derived != bytes)
                            r.Divergent("bytes", derived, "01 §4.2.6 order-independent Status rule (02 T-DONE-12, D-21)");
                    }
                },
            };
        }

        // ---- A17: schema version & migration ---------------------------------------------------------------------
        var schemas = new (string Title, string? Version)[] { ("no SchemaVersion", null), ("SchemaVersion 7", "7"), ("SchemaVersion 0", "0"), ("SchemaVersion -1", "-1") };
        for (int i = 0; i < schemas.Length; i++)
        {
            var (title, version) = schemas[i];
            yield return new CaseDef
            {
                Id = $"A17.{i + 1}", Family = F, Title = $"{title} + completed recurring items → Load() flags + bytes",
                Settles = new[] { "01 DATA-022", "01 DATA-023", "02 T-REC-15" },
                Run = r =>
                {
                    var doc = $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"Container\":{{\"Id\":\"{Gs(103)}\"}},\"Recurrence\":3,\"IsComplete\":true," +
                              $"\"Subtasks\":[{{\"Id\":\"{Gs(5)}\",\"Container\":{{\"Id\":\"{Gs(105)}\"}},\"Recurrence\":3,\"IsComplete\":true}}]}}]," +
                              $"\"Procedures\":[{{\"Id\":\"{Gs(4)}\",\"Container\":{{\"Id\":\"{Gs(104)}\"}},\"Recurrence\":2,\"Status\":3}}]" +
                              (version != null ? $",\"SchemaVersion\":{version}" : "") + "}";
                    r.Input("inline", doc);
                    File.WriteAllText(DataStore.CurrentDataFile, doc, Utf8NoBom);
                    var data = DataStore.Load();
                    var o = new JsonObject
                    {
                        ["lastLoadFailed"] = DataStore.LastLoadFailed,
                        ["loadedNewerSchema"] = DataStore.LoadedNewerSchema,
                        ["schemaVersionAfterLoad"] = data.SchemaVersion,
                        ["taskSpawned"] = data.Tasks.FirstOrDefault()?.RecurrenceSpawned,
                        ["subtaskSpawned"] = data.Tasks.FirstOrDefault()?.Subtasks.FirstOrDefault()?.RecurrenceSpawned,
                        ["procedureSpawned"] = data.Procedures.FirstOrDefault()?.RecurrenceSpawned,
                    };
                    r.Json("outcome", "outcome", o);
                    r.Text("bytes", "appdata", "json", DataStore.SerializeForSave(data));
                },
            };
        }

        // ---- A18: depth ------------------------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "A18", Family = F, Compare = "json-semantic",
            Title = "subtask chains n = 25…32 (serialise) and documents of depth 62…66 (deserialise)",
            Settles = new[] { "01 §4.1.9", "01 §7.4" },
            Run = r =>
            {
                var ser = new JsonArray();
                for (int n = 25; n <= 32; n++)
                {
                    var root = Chain(n);
                    var o = new JsonObject { ["n"] = n };
                    try { DataStore.SerializeForSave(KitchenSink.WithTasks(new[] { root })); o["ok"] = true; }
                    catch (Exception ex) { o["ok"] = false; o["error"] = ex.GetType().FullName; }
                    ser.Add(o);
                }
                var de = new JsonArray();
                var docs = new JsonArray();
                for (int depth = 62; depth <= 66; depth++)
                {
                    var doc = DepthDoc(depth);
                    docs.Add(doc);
                    var o = new JsonObject { ["depth"] = depth };
                    try { JsonSerializer.Deserialize<AppData>(doc, Opts); o["ok"] = true; }
                    catch (Exception ex) { o["ok"] = false; o["error"] = ex.GetType().FullName; }
                    de.Add(o);
                }
                r.Input("documents", docs);
                r.Json("result", "depth", new JsonObject { ["serialize"] = ser, ["deserialize"] = de });
            },
        };

        // ---- A19: file variants ---------------------------------------------------------------------------------
        var a01 = DataStore.SerializeForSave(new AppData());
        var bom = new byte[] { 0xEF, 0xBB, 0xBF };
        var variants = new (string Title, byte[] Bytes)[]
        {
            ("UTF-8 BOM + A01", bom.Concat(Utf8(a01)).ToArray()),
            ("UTF-16 LE BOM + A01", Encoding.Unicode.GetPreamble().Concat(Encoding.Unicode.GetBytes(a01)).ToArray()),
            ("A01 + trailing newline and spaces", Utf8(a01 + "\n  ")),
            ("// comment + A01", Utf8("// comment\n" + a01)),
            ("trailing comma", Utf8(a01[..^1] + ",}")),
            ("literal null", Utf8("null")),
            ("[]", Utf8("[]")),
            ("empty (0 bytes)", Array.Empty<byte>()),
            ("A01 followed by a second object", Utf8(a01 + a01)),
        };
        for (int i = 0; i < variants.Length; i++)
        {
            var (title, bytes) = variants[i];
            var id = $"A19.{i + 1}";
            yield return new CaseDef
            {
                Id = id, Family = F, Title = title + " → Load()/LoadFrom outcome",
                Settles = new[] { "01 DATA-021", "01 §4.1.8" },
                Run = r => FileVariantCase(r, id, bytes),
            };
        }

        // ---- A20: Windows DPAPI magic ----------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "A20", Family = F, Runs = Runs.Both, Title = "AAENC1\\n + 64 random bytes → Load() fails safely",
            Settles = new[] { "01 §4.6", "01 §7.3" },
            Run = r =>
            {
                // "64 random bytes", made deterministic (DATA-303) from two SHA-256 digests.
                var noise = System.Security.Cryptography.SHA256.HashData(Utf8("AA-fixture-A20-1"))
                    .Concat(System.Security.Cryptography.SHA256.HashData(Utf8("AA-fixture-A20-2"))).ToArray();
                var bytes = Encoding.ASCII.GetBytes("AAENC1\n").Concat(noise).ToArray();
                r.InputFile($"{r.Id}.input.bin", bytes);
                File.WriteAllBytes(DataStore.CurrentDataFile, bytes);
                DataStore.Load();
                r.Json("outcome", "outcome", new JsonObject { ["lastLoadFailed"] = DataStore.LastLoadFailed });
                try { DataStore.LoadFrom(DataStore.CurrentDataFile); r.Json("exception", "exception", null, mac: false); }
                catch (Exception ex) { r.Json("exception", "exception", Shapes.ExceptionShape(ex, false), mac: false); }
            },
        };

        // ---- A21: duplicate member ----------------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "A21", Family = F, Title = "{\"Name\":\"a\",\"Name\":\"b\"} → outcome", Normative = "should",
            Settles = new[] { "01 §3.2" },
            Run = r => LoadSaveCase(r, $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"Container\":{{\"Id\":\"{Gs(103)}\"}},\"Name\":\"a\",\"Name\":\"b\"}}]}}", null, null),
        };

        // ---- A22: shared references / cycles ---------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "A22.1", Family = F, Title = "two tasks sharing one Container instance → written twice",
            Settles = new[] { "01 §3.3" },
            Run = r =>
            {
                var shared = new Container { Id = G(103), RichTextXaml = "shared" };
                var a = new TaskItem { Id = G(3), Name = "a", Container = shared };
                var b = new TaskItem { Id = G(5), Name = "b", Container = shared };
                r.Text("result", "appdata", "json", DataStore.SerializeForSave(KitchenSink.WithTasks(new[] { a, b })));
            },
        };
        yield return new CaseDef
        {
            Id = "A22.2", Family = F, Title = "a task that contains itself as a subtask (IgnoreCycles)", Normative = "record-only",
            Settles = new[] { "01 §3.3" },
            Run = r =>
            {
                var t = new TaskItem { Id = G(3), Name = "self", Container = new Container { Id = G(103) } };
                t.Subtasks.Add(t);
                try { r.Text("result", "appdata", "json", DataStore.SerializeForSave(KitchenSink.WithTasks(new[] { t })), mac: false); }
                catch (Exception ex) { r.Json("result", "exception", Shapes.ExceptionShape(ex, false), mac: false); }
            },
        };
        yield return new CaseDef
        {
            Id = "A22.3", Family = F, Title = "\"Subtasks\":[null] → outcome", Normative = "record-only",
            Settles = new[] { "01 §4.1.10" },
            Run = r => LoadSaveCase(r, $"{{\"Tasks\":[{{\"Id\":\"{Gs(3)}\",\"Container\":{{\"Id\":\"{Gs(103)}\"}},\"Subtasks\":[null]}}]}}", null, null),
        };

        // ---- A23: TrashOpts self-check --------------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "A23", Family = F, Title = "Serialize(KS, TrashOpts) — equals A02 (stamped KS) byte-for-byte",
            Settles = new[] { "01 §3.17" },
            Run = r =>
            {
                var ks = KitchenSink.Build();
                var viaTrash = JsonSerializer.Serialize(ks, TrashOpts);
                r.Text("result", "trashopts", "json", viaTrash);
                if (viaTrash != DataStore.SerializeForSave(KitchenSink.Build()))
                    Console.Error.WriteLine("  note: A23 differs from A02 — recorded");
            },
        };

        // ---- A24: AppRepository trash/restore over KS -------------------------------------------------------------
        var trashSteps = new (string Title, Func<AppRepository, JsonNode?> Act)[]
        {
            ("TrashHierarchyItem(task G(3))", repo => Ret(repo.TrashHierarchyItem(repo.Data.Tasks.First(t => t.Id == G(3)))?.ItemType)),
            ("TrashCrew(G(11))", repo => Ret(repo.TrashCrew(repo.Data.Crew.First(c => c.Id == G(11))).ItemType)),
            ("trash task G(3) then RestoreTrash", repo =>
            {
                var ti = repo.TrashHierarchyItem(repo.Data.Tasks.First(t => t.Id == G(3)))!;
                return Ret(repo.RestoreTrash(ti));
            }),
            ("trash crew G(11) then RestoreTrash", repo =>
            {
                var ti = repo.TrashCrew(repo.Data.Crew.First(c => c.Id == G(11)));
                return Ret(repo.RestoreTrash(ti));
            }),
            ("restore when the id already exists (D-11)", repo =>
            {
                var task = repo.Data.Tasks.First(t => t.Id == G(3));
                var ti = repo.TrashHierarchyItem(task)!;
                repo.Data.Tasks.Add(task);                       // something with that id is live again
                return Ret(repo.RestoreTrash(ti));
            }),
            ("payload {\"Tasks\": (invalid) → null; ItemType Bogus → null", repo =>
            {
                var bad = new TrashedItem { Id = G(31), ItemType = "Task", ItemId = G(32), Name = "bad", KindLabel = "Task", DeletedUtc = DateTime.UtcNow, PayloadJson = "{\"Tasks\":" };
                var bogus = new TrashedItem { Id = G(33), ItemType = "Bogus", ItemId = G(34), Name = "bogus", KindLabel = "?", DeletedUtc = DateTime.UtcNow, PayloadJson = "{}" };
                repo.Data.Trash.Add(bad); repo.Data.Trash.Add(bogus);
                return new JsonObject { ["invalidPayload"] = repo.RestoreTrash(bad), ["bogusType"] = repo.RestoreTrash(bogus) };
            }),
        };
        for (int i = 0; i < trashSteps.Length; i++)
        {
            var (title, act) = trashSteps[i];
            yield return new CaseDef
            {
                Id = $"A24.{i + 1}", Family = F, Title = "AppRepository over KS: " + title,
                Settles = new[] { "01 §3.17", "01 §4.10", "02 T-TR-1…5", "02 T-TR-14" },
                Run = r =>
                {
                    var ks = KitchenSink.Build();
                    // The KS trash entry is dated D_Z0; re-date it to now so the 90-day prune can never evict it
                    // when the goldens are regenerated later (it is masked %%NOWUTC%%).
                    ks.Trash[0].DeletedUtc = DateTime.UtcNow;
                    var baseline = DataStore.SerializeForSave(KitchenSink.Build());
                    var repo = new AppRepository(ks);
                    var returned = act(repo);
                    var bytes = DataStore.SerializeForSave(repo.Data);
                    r.Mask.AutoMask(bytes, baseline);
                    r.Json("returned", "returned", new JsonObject { ["returned"] = returned });
                    r.Text("bytes", "appdata", "json", bytes);
                },
            };
        }

        // ---- A25: attachment paths --------------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "A25", Family = F, Runs = Runs.Unix, Compare = "json-semantic",
            Title = "POSIX-form stored paths × {plain, IsLink, LinkInPlace} → Normalize/Migrate/Resolve; ClassifyFile; ImportFile",
            Settles = new[] { "01 §3.5–3.8", "01 §7.6" },
            Run = r => PathsCase(r, PosixPaths, includeClassifyAndImport: true),
        };
        yield return new CaseDef
        {
            Id = "A25x", Family = F, Runs = Runs.Both, Compare = "json-semantic", Normative = "record-only", NormativeWindows = "must",
            Title = "Windows-form stored paths × modes → Normalize/Migrate/Resolve (the Mac follows the windows run, DATA-310)",
            Settles = new[] { "01 §3.7 [MAC]", "01 §7.6" },
            Run = r => PathsCase(r, WindowsPaths, includeClassifyAndImport: false),
        };
        yield return new CaseDef
        {
            Id = "A25s", Family = F, Runs = Runs.Unix, Compare = "json-semantic",
            Title = "ImportFile(\"a:b?.pdf\") on unix (the Mac sanitises, 01 §6.6)",
            Settles = new[] { "01 §6.6", "01 §7.6" },
            Run = r =>
            {
                var src = Path.Combine(Path.GetTempPath(), "aa-winfixtures-src-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(src);
                try
                {
                    var file = Path.Combine(src, "a:b?.pdf");
                    File.WriteAllText(file, "x");
                    var result = DataStore.ImportFile(file);
                    MaskImported(r, result);
                    r.Json("result", "import", new JsonObject { ["source"] = "a:b?.pdf", ["result"] = result });
                    r.DivergentRecordOnly("01 §6.6 Windows-safe names: the Mac stores …_a_b_.pdf (asserted by W-PERSIST's tests)");
                }
                finally { Directory.Delete(src, true); }
            },
        };

        // ---- A26: LastModified peeks ----------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "A26", Family = F, Compare = "json-semantic",
            Title = "ReadLastModified / PeekFileLastModified on stamp variants",
            Settles = new[] { "01 §3.9" },
            Run = r =>
            {
                var inputs = new[]
                {
                    "{\"LastModified\":\"2026-09-29T11:15:29.9876543+03:00\"}", "{}", "{\"LastModified\":null}",
                    "{\"LastModified\":\"garbage\"}", "{\"LastModified\":5}", "{\"lastModified\":\"2026-09-29T11:15:29+03:00\"}",
                    "{\"Ui\":{\"LastModified\":\"2026-09-29T11:15:29+03:00\"}}", "[]", "not json",
                };
                var rows = new JsonArray();
                foreach (var text in inputs)
                {
                    var path = r.Data("peek.json");
                    File.WriteAllText(path, text, Utf8NoBom);
                    rows.Add(new JsonObject
                    {
                        ["input"] = text,
                        ["bom"] = false,
                        ["read"] = Shapes.DateOrNull(Call<DateTime?>(typeof(DataStore), "ReadLastModified", text)),
                        ["peekFile"] = Shapes.DateOrNull(DataStore.PeekFileLastModified(path)),
                    });
                }
                var bomPath = r.Data("peek-bom.json");
                File.WriteAllBytes(bomPath, new byte[] { 0xEF, 0xBB, 0xBF }.Concat(Utf8(inputs[0])).ToArray());
                rows.Add(new JsonObject
                {
                    ["input"] = inputs[0],
                    ["bom"] = true,
                    ["read"] = null,
                    ["peekFile"] = Shapes.DateOrNull(DataStore.PeekFileLastModified(bomPath)),
                });
                r.Input("rows", new JsonArray(inputs.Select(x => (JsonNode?)x).ToArray()));
                r.Json("result", "lastmodified", rows);
            },
        };
    }

    private static JsonNode? Ret(string? s) => s == null ? null : JsonValue.Create(s);

    // ---- helpers --------------------------------------------------------------------------------------------------

    /// <summary>Load → save outcome + bytes; with <paramref name="derivedDoc"/> the Mac expectation is the Windows
    /// output of the derived document when it differs.</summary>
    internal static void LoadSaveCase(CaseRun r, string doc, string? derivedDoc, string? reason)
    {
        r.Input("inline", doc);
        var (o, bytes, _) = Shapes.LoadSave(doc);
        string? derived = null;
        if (derivedDoc != null) derived = Shapes.LoadSave(derivedDoc).Bytes;
        if (bytes != null) r.Mask.AutoMask(bytes, doc);
        if (derived != null) r.Mask.AutoMask(derived, derivedDoc!);
        r.Json("outcome", "outcome", o);
        if (bytes != null) r.Text("bytes", "appdata", "json", bytes);
        if (derived != null && (bytes == null || !Derive.SameModuloTokens(r.Mask.Apply(bytes), r.Mask.Apply(derived))))
        {
            r.Input("derived", derivedDoc!);
            r.Divergent("bytes", derived, reason!);
        }
    }

    /// <summary>A12: one task per write form; the inputs carry ticks/kind/construction so the Swift side builds the
    /// identical values.</summary>
    private static void DateWriteCase(CaseRun r, bool includeLocalMin)
    {
        var rows = new List<(string Label, DateTime Value, string Via, long? UtcTicks)>();
        if (includeLocalMin)
            rows.Add(("MinValue Local", DateTime.SpecifyKind(DateTime.MinValue, DateTimeKind.Local), "ctor", null));
        else
        {
            var u = new DateTime(2026, 10, 1, 0, 0, 0, DateTimeKind.Unspecified);
            rows.Add(("Unspecified .0", u, "ctor", null));
            rows.Add(("Unspecified .1", u.AddTicks(1_000_000), "ctor", null));
            rows.Add(("Unspecified .123456", u.AddTicks(1_234_560), "ctor", null));
            rows.Add(("Unspecified .1234567", u.AddTicks(1_234_567), "ctor", null));
            rows.Add(("Unspecified .0000001", u.AddTicks(1), "ctor", null));
            rows.Add(("MinValue Unspecified", DateTime.MinValue, "ctor", null));
            rows.Add(("MaxValue Unspecified", DateTime.MaxValue, "ctor", null));
            rows.Add(("Utc 08:15:30", new DateTime(2026, 9, 29, 8, 15, 30, DateTimeKind.Utc), "ctor", null));
            rows.Add(("Utc 08:15:30.0000001", new DateTime(2026, 9, 29, 8, 15, 30, DateTimeKind.Utc).AddTicks(1), "ctor", null));
            rows.Add(("Local 11:15:30.5", new DateTime(2026, 9, 29, 11, 15, 30, DateTimeKind.Local).AddTicks(5_000_000), "ctor", null));
            rows.Add(("Local 2026-01-15 09:00", new DateTime(2026, 1, 15, 9, 0, 0, DateTimeKind.Local), "ctor", null));
            rows.Add(("Local 2100-06-01", new DateTime(2100, 6, 1, 0, 0, 0, DateTimeKind.Local), "ctor", null));
            rows.Add(("Local 2026-11-01 01:30 (New York ambiguous)", new DateTime(2026, 11, 1, 1, 30, 0, DateTimeKind.Local), "ctor", null));
            var utc = new DateTime(2026, 11, 1, 6, 30, 0, DateTimeKind.Utc);
            rows.Add(("ToLocalTime(2026-11-01 06:30Z) (same NY wall time, DST bit)", utc.ToLocalTime(), "utcToLocal", utc.Ticks));
            rows.Add(("Local 2026-03-08 02:30 (New York gap)", new DateTime(2026, 3, 8, 2, 30, 0, DateTimeKind.Local), "ctor", null));
            rows.Add(("Local 2026-10-25 03:30 (Athens ambiguous)", new DateTime(2026, 10, 25, 3, 30, 0, DateTimeKind.Local), "ctor", null));
            rows.Add(("Local 2026-03-29 03:30 (Athens gap)", new DateTime(2026, 3, 29, 3, 30, 0, DateTimeKind.Local), "ctor", null));
        }
        var tasks = new List<TaskItem>();
        var spec = new JsonArray();
        for (int k = 0; k < rows.Count; k++)
        {
            var (label, value, via, utcTicks) = rows[k];
            var t = KitchenSink.Task(100 + k + 1, label);
            t.Deadline = value;
            tasks.Add(t);
            var o = new JsonObject
            {
                ["id"] = t.Id.ToString("D"), ["containerId"] = t.Container.Id.ToString("D"), ["name"] = label,
                ["via"] = via, ["ticks"] = value.Ticks, ["kind"] = value.Kind.ToString(),
            };
            if (utcTicks != null) o["utcTicks"] = utcTicks;
            spec.Add(o);
        }
        r.Input("tasks", spec);
        r.Text("result", "appdata", "json", DataStore.SerializeForSave(KitchenSink.WithTasks(tasks)));
    }

    public static readonly string[] DateReadInputs =
    {
        "2026-10-01", "2026-10-01T00:00", "2026-10-01T00:00:00",
        "2026-10-01T00:00:00.1", "2026-10-01T00:00:00.12", "2026-10-01T00:00:00.123", "2026-10-01T00:00:00.1234",
        "2026-10-01T00:00:00.12345", "2026-10-01T00:00:00.123456", "2026-10-01T00:00:00.1234567", "2026-10-01T00:00:00.12345678",
        "2026-10-01T00:00:00Z", "2026-10-01T00:00:00z", "2026-10-01T00:00:00+03:00", "2026-10-01T00:00:00+0300",
        "2026-10-01T00:00:00+03", "2026-10-01T00:00:00-00:00", "2026-10-01T00:00:00+14:00", "2026-10-01T00:00:00+14:01",
        " 2026-10-01T00:00:00", "2026-10-01 00:00:00", "2026-10-01T24:00:00", "2026-02-29", "2024-02-29", "01/10/2026",
        "0001-01-01T00:00:00+03:00", "9999-12-31T23:59:59.9999999-05:00", "2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z",
        "2026-03-08T02:30:00-05:00",
    };

    private static void DateReadCase(CaseRun r)
    {
        var rows = new JsonArray();
        foreach (var s in DateReadInputs)
            rows.Add(Shapes.DateRead(s, () => JsonSerializer.Deserialize<DateTime>(JsonSerializer.Serialize(s), Opts)));
        r.Input("strings", new JsonArray(DateReadInputs.Select(x => (JsonNode?)x).ToArray()));
        r.Json("result", "read-matrix", new JsonObject { ["tz"] = r.Def.Tz, ["rows"] = rows });
    }

    /// <summary>A18: a subtask chain of n levels whose deepest container holds a file with LinkedItemIds.</summary>
    internal static TaskItem Chain(int n)
    {
        var root = KitchenSink.Task(2000, "level 1");
        var cur = root;
        for (int level = 2; level <= n; level++)
        {
            var next = KitchenSink.Task(2000 + level - 1, "level " + level);
            cur.Subtasks.Add(next);
            cur = next;
        }
        var f = new FileItem { Id = G(2999), Name = "deep.pdf", Path = "files/deep.pdf", Added = D_L };
        f.LinkedItemIds.Add(G(1));
        cur.Container.Files.Add(f);
        return root;
    }

    /// <summary>A18: a JSON document of exactly <paramref name="depth"/> nesting levels (root object = 1).</summary>
    internal static string DepthDoc(int depth)
    {
        // {"Tasks":[{}]} has depth 3; each nested subtask level adds 2 (array + object); an odd remainder is one
        // trailing empty "Subtasks":[] array.
        int levels = (depth - 3) / 2;
        bool trailing = (depth - 3) % 2 == 1;
        var sb = new StringBuilder("{\"Tasks\":[{");
        for (int i = 0; i < levels; i++) sb.Append("\"Subtasks\":[{");
        if (trailing) sb.Append("\"Subtasks\":[]");
        for (int i = 0; i < levels; i++) sb.Append("}]");
        sb.Append("}]}");
        return sb.ToString();
    }

    private static void FileVariantCase(CaseRun r, string id, byte[] bytes)
    {
        r.InputFile($"{id}.input.bin", bytes);
        File.WriteAllBytes(DataStore.CurrentDataFile, bytes);
        var model = DataStore.Load();
        var failed = DataStore.LastLoadFailed;
        bool threw = false;
        JsonNode? exception = null;
        try { DataStore.LoadFrom(DataStore.CurrentDataFile); }
        catch (Exception ex) { threw = true; exception = Shapes.ExceptionShape(ex, false); }
        r.Json("outcome", "outcome", new JsonObject { ["lastLoadFailed"] = failed, ["loadFromThrows"] = threw });
        var saved = DataStore.SerializeForSave(model);
        r.Mask.AutoMask(saved, "");
        r.Text("bytes", "appdata", "json", saved);
        r.Json("exception", "exception", exception, mac: false);
    }

    // ---- A25 ----

    private static readonly string[] PosixPaths =
    {
        "files/ab12_x.pdf", "{DATADIR}/files/ab12_x.pdf", "{DATADIR_UPPER}/files/ab12_x.pdf",
        "/Users/bob/AA/files/ab12_x.pdf", "/Users/bob/AA/files/zz_missing.pdf", "/Volumes/share/Files/ab12_x.pdf",
        "/Volumes/share/docs/a.xlsx", "files\\ab12_x.pdf", "..\\files\\ab12_x.pdf",
    };

    private static readonly string[] WindowsPaths =
    {
        @"C:\Users\bob\AppData\Local\AA\files\ab12_x.pdf", @"C:\Users\bob\AppData\Local\AA\files\zz_missing.pdf",
        @"D:\Projects\Files\ab12_x.pdf", @"\\srv\share\docs\a.xlsx", "C:/docs/a.xlsx", "C:foo.pdf",
    };

    private static string Expand(string p, string dataDir) =>
        p.Replace("{DATADIR_UPPER}", dataDir.ToUpperInvariant()).Replace("{DATADIR}", dataDir);

    private static void PathsCase(CaseRun r, string[] stored, bool includeClassifyAndImport)
    {
        Directory.CreateDirectory(DataStore.FilesFolder);
        File.WriteAllText(Path.Combine(DataStore.FilesFolder, "ab12_x.pdf"), "0123456789");
        r.Input("appFiles", new JsonArray("files/ab12_x.pdf"));
        r.Input("stored", new JsonArray(stored.Select(x => (JsonNode?)x).ToArray()));
        var rows = new JsonArray();
        foreach (var raw in stored)
            foreach (var mode in new[] { "plain", "IsLink", "LinkInPlace" })
            {
                var p = Expand(raw, DataStore.AppFolder);
                FileItem Make() => new() { Id = G(201), Name = "x", Path = p, IsLink = mode == "IsLink", LinkInPlace = mode == "LinkInPlace" };
                var nf = Make(); var nd = Holder(nf);
                DataStore.NormalizeFilePaths(nd);
                var mf = Make(); var md = Holder(mf);
                CallVoid(typeof(DataStore), "MigrateLegacyAbsolutePaths", md);
                bool? under = Path.IsPathRooted(p) ? Call<bool>(typeof(DataStore), "IsUnderAppFolder", p) : null;
                rows.Add(new JsonObject
                {
                    ["stored"] = raw, ["mode"] = mode, ["normalized"] = nf.Path, ["migrated"] = mf.Path,
                    ["resolved"] = DataStore.ResolveFilePath(p), ["isUnderAppFolder"] = under,
                });
            }
        var result = new JsonObject { ["rows"] = rows };
        if (includeClassifyAndImport)
        {
            var classify = new JsonArray();
            foreach (var name in new[] { "X.PDF", "a.heic", "b.webm", "c.csv", "noext", "a.tar.gz", ".hidden", "file.", "dir.d/file", "x.JPEG " })
                classify.Add(new JsonObject { ["path"] = name, ["kind"] = (int)DataStore.ClassifyFile(name) });
            result["classify"] = classify;
            var src = Path.Combine(Path.GetTempPath(), "aa-winfixtures-src-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(src);
            try
            {
                var file = Path.Combine(src, "Pump manual.pdf");
                File.WriteAllText(file, "pump");
                var imported = DataStore.ImportFile(file);
                MaskImported(r, imported);
                result["import"] = new JsonArray(new JsonObject
                {
                    ["source"] = "Pump manual.pdf", ["result"] = imported,
                    ["exists"] = File.Exists(Path.Combine(DataStore.AppFolder, imported)),
                });
            }
            finally { Directory.Delete(src, true); }
        }
        r.Json("result", "paths", result);
    }

    private static AppData Holder(FileItem f)
    {
        var d = new AppData();
        var e = new Equipment { Id = G(1), Container = new Container { Id = G(101) } };
        e.Container.Files.Add(f);
        d.Equipment.Add(e);
        return d;
    }

    /// <summary>`files/<32 hex>_<name>` → the hex part is a fresh Guid("N") → %%GUIDN:n%%.</summary>
    private static void MaskImported(CaseRun r, string imported)
    {
        var leaf = imported.StartsWith("files/", StringComparison.Ordinal) ? imported[6..] : imported;
        if (leaf.Length > 33 && Guid.TryParseExact(leaf[..32], "N", out var gid)) r.Mask.Guid(gid);
    }
}
