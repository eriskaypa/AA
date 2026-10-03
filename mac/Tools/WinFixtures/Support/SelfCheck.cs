// Self-checks against literals quoted in the specs (spec 01 GF.3.10, DATA-308): every mismatch between a golden and
// a literal vector quoted in mac/Docs/Spec is recorded in MANIFEST.json.specConflicts[] and printed. The golden wins;
// the owner of the spec appends an erratum and names it in the entry's `erratum` field (GF.9 item 4).
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using AA.Models;
using AA.Services;

namespace WinFixtures;

internal static class SelfCheck
{
    private sealed record Check(string Case, string Spec, string Literal, Func<string, string?> Golden, string Note);

    /// <summary>Reads a golden file of the staged/committed root (null when absent).</summary>
    private static string? Read(string root, string rel)
    {
        var p = Path.Combine(root, rel.Replace('/', Path.DirectorySeparatorChar));
        return File.Exists(p) ? File.ReadAllText(p, Fx.Utf8NoBom) : null;
    }

    private static JsonNode? ReadJson(string root, string rel) => Read(root, rel) is string s ? JsonNode.Parse(s) : null;

    private static string? Row(JsonNode? rows, Func<JsonObject, bool> pick, string key) =>
        rows?.AsArray().OfType<JsonObject>().FirstOrDefault(pick)?[key]?.ToString();

    private static IEnumerable<Check> Checks()
    {
        // 01 §4.2.1 — the empty database string.
        yield return new Check("A01", "01 §4.2.1",
            "{\"Equipment\":[],\"Tasks\":[],\"Procedures\":[],\"Vessels\":[],\"Groups\":[],\"Crew\":[],\"Log\":[],\"ChecklistTemplates\":[],\"ListGroups\":[],\"QuickBuckets\":[],\"Ports\":[],\"ScheduleTemplates\":[],\"Trash\":[],\"Sire\":{\"QuestionStatuses\":{},\"Bookmarks\":[],\"ForExport\":[],\"Tasks\":[],\"QuestionBodies\":{}},\"Ui\":{\"SelectedMainTabIndex\":0,\"ShowShortcutBar\":true,\"QuickViewPinIds\":[],\"TabColors\":{},\"TabOrder\":[],\"SortAZ\":{},\"GroupExpanded\":{},\"CrewTableColumns\":[],\"CrewTableShownColumns\":[]},\"SchemaVersion\":1}",
            root => Read(root, "json/A01.appdata.golden.json"), "empty database");

        // 01 §7.4 — the Task output line (produced here by the linked code, the same serializer as A02).
        yield return new Check("A02", "01 §7.4",
            "{\"Deadline\":\"2026-10-01T00:00:00\",\"IsJob\":false,\"DurationMinutes\":60,\"Recurrence\":3,\"RecurrenceSpawned\":false,\"IsComplete\":false,\"Status\":1,\"Subtasks\":[],\"Id\":\"3f2504e0-4f89-11d3-9a0c-0305e82c3301\",\"Name\":\"Fire drill\",\"Description\":\"\",\"Container\":{\"Id\":\"11111111-2222-3333-4444-555555555555\",\"RichTextXaml\":\"\",\"Files\":[],\"SharedWithContainerIds\":[],\"IsLocked\":false},\"RelatedIds\":[],\"Tags\":[\"safety\"],\"BucketIds\":[]}",
            _ =>
            {
                var t = new TaskItem
                {
                    Id = Guid.Parse("3f2504e0-4f89-11d3-9a0c-0305e82c3301"), Name = "Fire drill",
                    Deadline = new DateTime(2026, 10, 1, 0, 0, 0, DateTimeKind.Unspecified), Recurrence = RecurrenceKind.Monthly,
                    Container = new Container { Id = Guid.Parse("11111111-2222-3333-4444-555555555555") },
                };
                t.Status = WorkStatus.InProgress;
                t.Tags.Add("safety");
                return JsonSerializer.Serialize(t, Fx.Opts);
            }, "Task output line (derived-first property order)");

        // 01 §7.4 — escaping examples.
        foreach (var (input, literal) in new[]
        {
            ("Pump → main <A&B> 'x' \"y\" +1", "\"Pump \\u2192 main \\u003CA\\u0026B\\u003E \\u0027x\\u0027 \\u0022y\\u0022 \\u002B1\""),
            ("⚓", "\"\\u2693\""), ("😀", "\"\\uD83D\\uDE00\""), ("\t\n", "\"\\t\\n\""), ("C:\\x", "\"C:\\\\x\""), ("\u0001", "\"\\u0001\""),
        })
            yield return new Check("A09a", "01 §7.4", literal, _ => JsonSerializer.Serialize(input, Fx.Opts), "escaping of " + JsonSerializer.Serialize(input));

        // 01 §7.4 — numbers.
        foreach (var (value, literal) in new[] { (24.0, "24"), (180.5, "180.5"), (0.1, "0.1"), (1e16, "1E+16") })
            yield return new Check("A15a", "01 §7.4", literal, _ => JsonSerializer.Serialize(value, Fx.Opts), "number " + literal);

        // 01 §7.5 — the date table.
        foreach (var (rel, pick, literal) in new (string, string, string)[]
        {
            ("json/A12.1.appdata.golden.json", "Unspecified .0", "\"Deadline\":\"2026-10-01T00:00:00\""),
            ("json/A12.1.appdata.golden.json", "Local 11:15:30.5", "\"Deadline\":\"2026-09-29T11:15:30.5+03:00\""),
            ("json/A12.3.appdata.golden.json", "Local 2026-01-15 09:00", "\"Deadline\":\"2026-01-15T09:00:00+05:30\""),
        })
            yield return new Check(rel.Split('/')[1][..5], "01 §7.5", literal, root =>
            {
                var doc = ReadJson(root, rel);
                var task = doc?["Tasks"]?.AsArray().OfType<JsonObject>().FirstOrDefault(t => (string?)t["Name"] == pick);
                return task == null ? null : "\"Deadline\":" + task["Deadline"]!.ToJsonString();
            }, "date write form of " + pick);
        foreach (var (input, literal) in new[]
        {
            ("2026-10-01T00:00:00+03:00", "2026-09-30T17:00:00-04:00"), ("2026-10-01", "2026-10-01T00:00:00"),
            ("2026-10-01T00:00:00Z", "2026-10-01T00:00:00Z"),
        })
            yield return new Check("A13.2", "01 §7.5", literal,
                root => Row(ReadJson(root, "json/A13.2.read-matrix.golden.json")?["rows"], r => (string?)r["input"] == input, "rewritten"),
                "New York read + rewrite of " + input);
        foreach (var input in new[] { "2026-10-01 00:00:00", "01/10/2026" })
            yield return new Check("A13.2", "01 §7.5", "false",
                root => Row(ReadJson(root, "json/A13.2.read-matrix.golden.json")?["rows"], r => (string?)r["input"] == input, "ok"),
                input + " is an error");

        // 01 §4.4 — the source.json literal.
        yield return new Check("B07", "01 §4.4",
            "{\"Identity\":\"Vessel-Alpha\",\"Machine\":\"BRIDGE-PC\",\"WrittenUtc\":\"2026-09-29T08:15:30.1234567Z\",\"LastModified\":\"2026-09-29T11:15:29.9876543+03:00\",\"DataOnly\":false}",
            root => Read(root, "bundles/B07.source.golden.json"), "source.json example");

        // 01 §7.1 — PBKDF2 table; 01 §7.2 / 05 §7.6 — enc: blobs.
        foreach (var (pw, literal) in new[]
        {
            ("correct horse", "V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk="), ("redemption", "1+930ag9iT2JBP4/zxFyJccLLHJhA+CvurBLnPPS7Hc="),
            ("p\u00E4ssw\u00F6rd", "trmn14eaJqetmcWSJJwUWVLKUOyf765hiEQzeYnvalM="), ("test1234", "r8aEvRy/8yh5is2gkdnAZp/hnmK1R108BLIM6VbhOyI="),
        })
            yield return new Check("K01", "01 §7.1", literal,
                root => Row(ReadJson(root, "crypto/K01.pbkdf2.golden.json")?["rows"], r => (string?)r["password"] == pw && (string?)r["salt"] == "S", "dk32Base64"),
                "PasswordHash of " + pw);
        yield return new Check("K01", "01 §7.1", "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b",
            root => ReadJson(root, "crypto/K01.pbkdf2.golden.json")?["primitive"]?["hex"]?.ToString(), "PBKDF2 primitive password/salt/c=1");
        foreach (var (name, literal) in new[]
        {
            ("BOM + \"\"", "enc:EBESExQVFhcYGRobHB0eHw4QRSqEYezPC65cF1E8B3R1ApbahQo1UxRvd3kio+7TgvGYrwMij8bZDWxhSRRHsw=="),
            ("BOM + <Section>hi</Section>", "enc:EBESExQVFhcYGRobHB0eHxJkbpvR5sxlvHs4LU1Zlc/8FgD7jQznyIZndaufj6DG8Ti6ErBbvtnRWs5/oiOkMApZpCT7lzAUZnjCNe73CmY="),
            ("\"\" without BOM", "enc:EBESExQVFhcYGRobHB0eHxVqH9CC+wbDQym8EpaLqTzI1CGEYvJ2gETXttL9DZejPrh/qVUIZuxQ+8nwx/+CxQ=="),
            ("<Section>hi</Section> without BOM", "enc:EBESExQVFhcYGRobHB0eH8BIPRoz9iURWzr6BNWef9ZK5CiJh6kBlV01N1xabuu0pXm6TefrY/0XFRCF8+BkC6FJF5y0PoPkSQT/8rTn8rg="),
            ("test1234: BOM + the 05 §7.6 XAML", "enc:EBESExQVFhcYGRobHB0eH7yh0+cZnnHk+wt1LaJhOt37Vp1TfN1upIjugsLMCx8A+1BO/lOwe048ZDbt09pbLyzc0beZRySCCCdKYiLMU5PdZE5PJzh+Mh/dB0qGRrpyynpDMaDlxhjSkurNzory7yVyLf5MXDJksvDN6MZQ6xq0cW8h2FEuYihYTqxvmhwrVt1py4SETHUppvsjlMHfskgrHLivepYL5vBOq4Iy1MYzL9/UXBU8F/ZSwuzCLFPP"),
        })
            yield return new Check("K03", name.StartsWith("test1234") ? "05 §7.6" : "01 §7.2", literal,
                root => Row(ReadJson(root, "crypto/K03.blobs.golden.json"), r => (string?)r["name"] == name, "blob"), "enc: blob " + name);

        // 01 §7.8 — the DataDiff example.
        yield return new Check("E01.1", "01 §7.8", "Added 1, Changed 1, Removed 1: Added [Vessel] Alpha / Changed [Task] Pump 2 / Removed [Equipment/Area] Boiler",
            root =>
            {
                var d = ReadJson(root, "services/E01.1.datadiff.golden.json");
                if (d == null) return null;
                var roots = string.Join(" / ", d["Roots"]!.AsArray().OfType<JsonObject>().Select(n => $"{n["Change"]} {n["Text"]}"));
                return $"Added {d["Added"]}, Changed {d["Changed"]}, Removed {d["Removed"]}: {roots}";
            }, "roots and counts");
        yield return new Check("E01.1", "01 §7.8", "name: \"Pump\" → \"Pump 2\" | deadline: (none) → 2026-10-01 | subtask: Check oil",
            root =>
            {
                var d = ReadJson(root, "services/E01.1.datadiff.golden.json");
                var changed = d?["Roots"]?.AsArray().OfType<JsonObject>().FirstOrDefault(n => (string?)n["Change"] == "Changed");
                return changed == null ? null : string.Join(" | ", changed["Children"]!.AsArray().OfType<JsonObject>().Select(n => (string?)n["Text"]));
            }, "children of the changed root");

        // 02 §7.7 — search.
        yield return new Check("E02.1", "02 §7.7", "Component › Name|Fuel pump|0 ; Name|Replace the fuel filter on the main engine|12 ; Step › Title|Sample fuel|7",
            root => Hits(ReadJson(root, "services/E02.1.search.golden.json")), "FUEL hits");
        yield return new Check("E02.2", "02 §7.7", "Name|Main Engine|5 ; Tags|engine, ME|0 ; Name|Replace the fuel filter on the main engine|36",
            root => Hits(ReadJson(root, "services/E02.2.search.golden.json")), "engine hits");

        // 02 §7.8 — reminders.
        yield return new Check("E04.1", "02 §7.8", "2|2|3|2 overdue  ·  2 due today  ·  3 due this week",
            root =>
            {
                var d = ReadJson(root, "services/E04.1.reminders.golden.json");
                return d == null ? null : $"{d["Overdue"]}|{d["DueToday"]}|{d["DueWeek"]}|{d["Headline"]}";
            }, "the 02 §7.8 data set");

        // 02 §7.9 — saved-list order (the non-defect rows).
        foreach (var (sub, literal) in new[] { ("1", "true|B C A"), ("5", "true|B A"), ("9", "true|B D A C"), ("10", "true|A D B C"), ("11", "true|A B C D"), ("12", "true|B C A") })
            yield return new Check("E12." + sub, "02 §7.9", literal,
                root =>
                {
                    var d = ReadJson(root, $"services/E12.{sub}.order.golden.json");
                    return d == null ? null : $"{d["returned"]!.ToJsonString()}|{string.Join(" ", d["groups"]!["g"]!.AsArray().Select(x => (string?)x))}";
                }, "group order T-ORD-" + sub);

        // 09 §7.13 — XLSX helpers.
        foreach (var (index, literal) in new[] { (0, "A"), (25, "Z"), (26, "AA"), (27, "AB"), (51, "AZ"), (52, "BA"), (701, "ZZ"), (702, "AAA") })
            yield return new Check("E14.1", "09 §7.13", literal, _ => Fx.Call<string>(typeof(XlsxWriter), "ColRef", index), "ColRef " + index);
        foreach (var (input, literal) in new[] { ("a\u0001b", "ab"), ("x\ty", "x\ty"), ("\"", "&quot;"), ("'", "'"), ("&<>", "&amp;&lt;&gt;") })
            yield return new Check("E14.1", "09 §7.13", literal, _ => Fx.Call<string>(typeof(XlsxWriter), "Esc", input), "Esc " + JsonSerializer.Serialize(input));

        // 09 §7.1 — ParseDate rows that carried "— verify" (New York run is irrelevant for dates without zones).
        foreach (var (input, literal) in new[] { ("03/04/2026", "2026-03-04"), ("3/4/26", "2026-03-04"), ("3/4/50", "1950-03-04"), ("garbage", "null"), ("12", "null") })
            yield return new Check("E10.1", "09 §7.1", literal,
                root =>
                {
                    var rows = ReadJson(root, "services/E10.1.parsedate.golden.json")?["parseDate"];
                    var row = rows?.AsArray().OfType<JsonObject>().FirstOrDefault(r => (string?)r["input"] == input);
                    if (row == null) return null;
                    if (row["value"] is not JsonObject v) return "null";
                    return new DateTime((long)v["ticks"]!).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
                }, "ParseDate " + input);
    }

    private static string? Hits(JsonNode? d) =>
        d == null ? null : string.Join(" ; ", d["hits"]!.AsArray().OfType<JsonObject>().Select(h => $"{h["Where"]}|{h["Snippet"]}|{h["MatchStart"]}"));

    /// <summary>Runs every check against <paramref name="root"/>; returns the new specConflicts[] (keeping the
    /// `erratum` of an entry that is still open).</summary>
    public static JsonArray Run(string root, JsonObject manifest, bool print)
    {
        var previous = (manifest["specConflicts"] as JsonArray)?.OfType<JsonObject>().ToList() ?? new List<JsonObject>();
        var conflicts = new JsonArray();
        int ran = 0, skipped = 0;
        foreach (var c in Checks())
        {
            string? golden;
            try { golden = c.Golden(root); }
            catch (Exception ex) { golden = "<error " + ex.GetType().Name + ": " + ex.Message + ">"; }
            if (golden == null) { skipped++; continue; }
            ran++;
            if (string.Equals(golden, c.Literal, StringComparison.Ordinal)) continue;
            var entry = new JsonObject { ["case"] = c.Case, ["spec"] = c.Spec, ["literal"] = c.Literal, ["golden"] = golden, ["note"] = c.Note };
            var old = previous.FirstOrDefault(p => (string?)p["case"] == c.Case && (string?)p["spec"] == c.Spec && (string?)p["note"] == c.Note);
            if (old?["erratum"] is JsonNode e) entry["erratum"] = e.DeepClone();
            conflicts.Add(entry);
            if (print) Console.Error.WriteLine($"selfcheck: {c.Case} vs {c.Spec} ({c.Note}): spec says {c.Literal} — golden is {golden}");
        }
        if (print) Console.WriteLine($"selfcheck: {ran} literal check(s), {conflicts.Count} conflict(s), {skipped} skipped (golden not generated)");
        return conflicts;
    }

    /// <summary>`selfcheck --out <root>`: rewrites specConflicts[] of the committed manifest.</summary>
    public static int RunStandalone(string root)
    {
        var path = Path.Combine(root, "MANIFEST.json");
        if (!File.Exists(path)) { Console.Error.WriteLine("selfcheck: no MANIFEST.json under " + root); return 1; }
        World.PinCulture();
        var manifest = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        manifest["specConflicts"] = Run(root, manifest, print: true);
        File.WriteAllText(path, Fx.Expect(manifest), Fx.Utf8NoBom);
        return 0;
    }
}
