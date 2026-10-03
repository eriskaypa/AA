// The process-per-group driver (spec 01 GF.3.4, DATA-302/303/310/313, GF.3.12). `DataStore.AppFolder` is a static
// initialised once from AA_DATA_DIR and `TimeZoneInfo.Local` is cached per process, so the driver re-launches
// itself per (family, time zone) group — and per case for families that mutate statics (settings, bundle matrix) —
// with a fresh data folder and a pinned environment. A failing group aborts the whole run: a partial run is never
// committed.
using System.Diagnostics;
using System.Globalization;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace WinFixtures;

internal static class Driver
{
    /// <summary>Authored inputs: committed by hand, read by both the generator and the Swift tests, never rewritten.</summary>
    public static readonly string[] AuthoredInputs = { "A05.input.json", "A10.input.json", "E11.rows.json" };

    /// <summary>Folders of the fixture root that WinFixtures never touches (XlsxGolden's output, the Swift emitter's
    /// synthetic workbooks).</summary>
    private static readonly string[] ForeignFolders = { "xlsx", "xlsx-inputs" };

    // ---- generate ---------------------------------------------------------------------------------------------------

    public static int Generate(string root, RunPlatform platform, string[] families, bool verifyOnly)
    {
        var bad = SourcePin.Verify(out var provenance);
        if (bad.Count > 0)
        {
            Console.Error.WriteLine("generate: aborted — the linked sources differ from the pinned checksums (DATA-301):");
            foreach (var b in bad) Console.Error.WriteLine("  " + b);
            return 1;
        }
        root = Path.GetFullPath(root);
        var runId = DateTime.UtcNow.ToString("yyyyMMdd'T'HHmmss'Z'", CultureInfo.InvariantCulture);
        var today = DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var staging = verifyOnly
            ? Path.Combine(Path.GetTempPath(), "aa-winfixtures-verify-" + runId)
            : root.TrimEnd('/', '\\') + ".staging-" + runId;
        var neutral = Path.Combine(Path.GetTempPath(), "aa-winfixtures-neutral-" + runId);
        try
        {
            PrepareStaging(root, staging, platform, families);
            if (platform == RunPlatform.Windows) Directory.CreateDirectory(neutral);

            var groups = Groups(platform, families);
            Console.WriteLine($"generate: run {runId}, platform {platform.ToString().ToLowerInvariant()}, {groups.Count} group(s), today {today}");
            foreach (var g in groups)
            {
                var dataDir = platform == RunPlatform.Unix
                    ? $"/tmp/aa-winfixtures/{runId}/{g.Slug}"
                    : $@"C:\aa-winfixtures\{runId}\{g.Slug}";
                if (Directory.Exists(dataDir)) Directory.Delete(dataDir, recursive: true);
                Directory.CreateDirectory(dataDir);
                var args = new List<string> { "case", g.Family, "--out", staging, "--tz", g.Tz, "--run", runId,
                                              "--platform", platform.ToString().ToLowerInvariant(), "--today", today };
                if (platform == RunPlatform.Windows) { args.Add("--neutral"); args.Add(neutral); }
                if (g.Only != null) { args.Add("--only"); args.Add(g.Only); }
                var env = new Dictionary<string, string>
                {
                    ["AA_DATA_DIR"] = dataDir,
                    ["LANG"] = "en_US.UTF-8",
                    ["LC_ALL"] = "en_US.UTF-8",
                    ["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1",
                };
                if (platform == RunPlatform.Unix) env["TZ"] = g.Tz;
                var rc = SpawnSelf(args, env);
                if (rc != 0)
                {
                    Console.Error.WriteLine($"generate: group {g.Slug} failed (exit {rc}) — nothing committed");
                    return 1;
                }
                try { Directory.Delete(dataDir, recursive: true); } catch { }
            }

            var manifest = MergeManifest(root, staging, platform, families, provenance, today);
            if (platform == RunPlatform.Unix)
                manifest["specConflicts"] = SelfCheck.Run(staging, manifest, print: true);
            else
                manifest["platformDivergences"] = NeutralityCheck(staging, neutral, manifest);
            File.WriteAllText(Path.Combine(staging, "MANIFEST.json"), Fx.Expect(manifest), Fx.Utf8NoBom);
            var partial = Path.Combine(staging, ".partial");
            if (Directory.Exists(partial)) Directory.Delete(partial, recursive: true);

            if (verifyOnly)
            {
                var diffs = Diff(root, staging, platform, families, manifest);
                if (diffs.Count == 0) { Console.WriteLine("generate --verify-only: the committed goldens are reproduced exactly"); return 0; }
                Console.Error.WriteLine($"generate --verify-only: {diffs.Count} difference(s):");
                foreach (var d in diffs.Take(200)) Console.Error.WriteLine("  " + d);
                return 1;
            }
            Swap(root, staging);
            Console.WriteLine($"generate: {((JsonArray)manifest["cases"]!).Count} case(s) in {Path.Combine(root, "MANIFEST.json")}");
            return 0;
        }
        finally
        {
            // After a successful swap the staging root no longer exists; after a failure or --verify-only it is
            // discarded, so a partial run never reaches the committed tree.
            try { if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true); } catch { }
            try { if (Directory.Exists(neutral)) Directory.Delete(neutral, recursive: true); } catch { }
            try { var runDir = platform == RunPlatform.Unix ? $"/tmp/aa-winfixtures/{runId}" : $@"C:\aa-winfixtures\{runId}"; if (Directory.Exists(runDir)) Directory.Delete(runDir, true); } catch { }
        }
    }

    private sealed record Group(string Family, string Tz, string? Only)
    {
        public string Slug => Fx.Slug(Family + "-" + Tz + (Only != null ? "-" + Only : ""));
    }

    /// <summary>GF.3.4: groups = (family, tz) for every family's zones; settings and bundle-matrix cases one group per
    /// case; (json, Europe/Athens) first because A14 reads the Athens-written A12 file.</summary>
    private static List<Group> Groups(RunPlatform platform, string[] families)
    {
        var groups = new List<Group>();
        foreach (var family in Catalog.Families.Where(families.Contains))
        {
            var cases = Catalog.All.Where(c => c.Family == family && c.RunsOn(platform)).ToList();
            // Shared groups first: the bundle matrix reads the B/R archives the shared bundles group writes.
            var zones = platform == RunPlatform.Unix
                ? cases.Where(c => !c.OwnProcess).Select(c => c.Tz).Distinct().ToList()
                : cases.Any(c => !c.OwnProcess) ? new List<string> { Fx.DefaultZone } : new List<string>();
            foreach (var tz in zones.OrderBy(z => z == Fx.DefaultZone ? 0 : 1 + Array.IndexOf(Fx.JsonZones, z)))
                groups.Add(new Group(family, tz, null));
            foreach (var c in cases.Where(c => c.OwnProcess))
                groups.Add(new Group(family, platform == RunPlatform.Unix ? c.Tz : Fx.DefaultZone, c.Id));
        }
        return groups.OrderBy(g => g.Family == "json" && g.Tz == Fx.DefaultZone && g.Only == null ? 0 : 1).ToList();
    }

    private static int SpawnSelf(List<string> args, Dictionary<string, string> env)
    {
        var exe = Environment.ProcessPath ?? throw new InvalidOperationException("no process path");
        var psi = new ProcessStartInfo { FileName = exe, UseShellExecute = false };
        if (Path.GetFileNameWithoutExtension(exe).Equals("dotnet", StringComparison.OrdinalIgnoreCase))
            psi.ArgumentList.Add(Assembly.GetEntryAssembly()!.Location);
        foreach (var a in args) psi.ArgumentList.Add(a);
        foreach (var kv in env) psi.Environment[kv.Key] = kv.Value;
        using var p = Process.Start(psi) ?? throw new InvalidOperationException("could not start the child process");
        p.WaitForExit();
        return p.ExitCode;
    }

    /// <summary>The staging root starts as a copy of everything this run does not own: authored inputs, the other
    /// platform's outputs, families not being regenerated, and the folders other tools own.</summary>
    private static void PrepareStaging(string root, string staging, RunPlatform platform, string[] families)
    {
        if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true);
        Directory.CreateDirectory(staging);
        if (!Directory.Exists(root)) return;
        foreach (var dir in Directory.GetDirectories(root))
        {
            var name = Path.GetFileName(dir);
            if (name == ".partial") continue;
            if (platform == RunPlatform.Unix && families.Contains(name)) continue;            // regenerated
            if (name == "windows" && platform == RunPlatform.Windows)
            {
                foreach (var sub in Directory.GetDirectories(dir))
                    if (!families.Contains(Path.GetFileName(sub)))
                        CopyTree(sub, Path.Combine(staging, "windows", Path.GetFileName(sub)));
                continue;
            }
            CopyTree(dir, Path.Combine(staging, name));
        }
        foreach (var f in Directory.GetFiles(root))
            if (Path.GetFileName(f) != "MANIFEST.json") File.Copy(f, Path.Combine(staging, Path.GetFileName(f)), true);
        if (File.Exists(Path.Combine(root, "MANIFEST.json")))
            File.Copy(Path.Combine(root, "MANIFEST.json"), Path.Combine(staging, ".previous-MANIFEST.json"), true);
        foreach (var a in AuthoredInputs)
            if (!File.Exists(Path.Combine(staging, "inputs", a)) && File.Exists(Path.Combine(root, "inputs", a)))
                File.Copy(Path.Combine(root, "inputs", a), Path.Combine(staging, "inputs", a), true);
    }

    private static void CopyTree(string src, string dst)
    {
        Directory.CreateDirectory(dst);
        foreach (var f in Directory.GetFiles(src)) File.Copy(f, Path.Combine(dst, Path.GetFileName(f)), true);
        foreach (var d in Directory.GetDirectories(src)) CopyTree(d, Path.Combine(dst, Path.GetFileName(d)));
    }

    /// <summary>Moves the staging root over the fixture root (rename, then delete the old tree).</summary>
    private static void Swap(string root, string staging)
    {
        var prev = Path.Combine(staging, ".previous-MANIFEST.json");
        if (File.Exists(prev)) File.Delete(prev);
        var old = root.TrimEnd('/', '\\') + ".old-" + Guid.NewGuid().ToString("N");
        if (Directory.Exists(root)) Directory.Move(root, old);
        Directory.Move(staging, root);
        if (Directory.Exists(old)) Directory.Delete(old, recursive: true);
    }

    // ---- manifest ---------------------------------------------------------------------------------------------------

    private static JsonObject MergeManifest(string root, string staging, RunPlatform platform, string[] families,
                                            JsonArray provenance, string today)
    {
        JsonObject? previous = null;
        var prevPath = Path.Combine(staging, ".previous-MANIFEST.json");
        if (File.Exists(prevPath)) previous = JsonNode.Parse(File.ReadAllText(prevPath))?.AsObject();

        bool OwnedHere(JsonObject c)
        {
            var family = (string?)c["family"] ?? "";
            var plat = (string?)c["platform"] ?? "any";
            if (!families.Contains(family)) return false;
            return platform == RunPlatform.Windows ? plat == "windows" : plat != "windows";
        }

        var cases = new List<JsonObject>();
        if (previous?["cases"] is JsonArray prevCases)
            foreach (var c in prevCases.OfType<JsonObject>())
                if (!OwnedHere(c)) cases.Add((JsonObject)c.DeepClone());
        var partialDir = Path.Combine(staging, ".partial");
        if (Directory.Exists(partialDir))
            foreach (var f in Directory.GetFiles(partialDir, "*.json").OrderBy(x => x, StringComparer.Ordinal))
                foreach (var c in JsonNode.Parse(File.ReadAllText(f))!.AsArray().OfType<JsonObject>())
                    cases.Add((JsonObject)c.DeepClone());
        cases = cases.OrderBy(c => (string?)c["id"], StringComparer.Ordinal).ToList();

        var runs = new JsonArray();
        if (previous?["runs"] is JsonArray prevRuns)
            foreach (var r in prevRuns.OfType<JsonObject>())
                if ((string?)r["platform"] != (platform == RunPlatform.Unix ? "unix" : "windows")) runs.Add(r.DeepClone());
        var probeDir = Path.Combine(Path.GetTempPath(), "aa-winfixtures-fsprobe-" + Guid.NewGuid().ToString("N"));
        bool ci;
        try { ci = World.CaseInsensitiveFs(probeDir); } finally { try { Directory.Delete(probeDir, true); } catch { } }
        var thisRun = platform == RunPlatform.Unix
            ? new JsonObject
            {
                ["platform"] = "unix",
                ["timeZones"] = new JsonArray(Fx.JsonZones.Select(z => (JsonNode?)JsonValue.Create(z)).ToArray()),
                ["caseInsensitiveFs"] = ci,
                ["culture"] = "en-US",
            }
            : new JsonObject
            {
                ["platform"] = "windows",
                ["timeZone"] = TimeZoneInfo.Local.Id,
                ["caseInsensitiveFs"] = ci,
                ["culture"] = "en-US",
            };
        runs.Add(thisRun);
        var sortedRuns = new JsonArray(runs.OfType<JsonObject>().OrderBy(r => (string?)r["platform"], StringComparer.Ordinal)
                                           .Select(r => (JsonNode?)r.DeepClone()).ToArray());

        var manifest = new JsonObject
        {
            ["schema"] = 1,
            ["generator"] = new JsonObject
            {
                ["name"] = "WinFixtures",
                ["version"] = typeof(Driver).Assembly.GetName().Version?.ToString(3) ?? "1.0.0",
                ["linkedSourcesCommit"] = LinkedSourcesCommit(),
                ["linkedSources"] = provenance.DeepClone(),
                ["runtime"] = RuntimeInformation.FrameworkDescription,
                ["sdk"] = SdkVersion(),
                ["icu"] = IcuVersion(),
                ["os"] = $"{RuntimeInformation.OSDescription} ({RuntimeInformation.OSArchitecture.ToString().ToLowerInvariant()})",
            },
            ["generatedAtUtc"] = DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture),
            ["today"] = today,
            ["runs"] = sortedRuns,
            ["cases"] = new JsonArray(cases.Select(c => (JsonNode?)c).ToArray()),
            ["specConflicts"] = previous?["specConflicts"]?.DeepClone() ?? new JsonArray(),
            ["platformDivergences"] = previous?["platformDivergences"]?.DeepClone() ?? new JsonArray(),
        };
        if (File.Exists(prevPath)) File.Delete(prevPath);
        return manifest;
    }

    /// <summary>The commit of the linked sources (`git log -1 --format=%h -- AA`), else the pinned one.</summary>
    private static string LinkedSourcesCommit()
    {
        var s = RunTool("git", "-C", SourcePin.RepoRoot(), "log", "-1", "--format=%h", "--", "AA");
        return string.IsNullOrWhiteSpace(s) ? SourcePin.PinnedCommit : s.Trim();
    }

    private static string SdkVersion() => RunTool("dotnet", "--version")?.Trim() is { Length: > 0 } v ? v : "unknown";

    /// <summary>ICU version via the runtime's internal interop (best effort; recorded, never asserted).</summary>
    private static string IcuVersion()
    {
        try
        {
            var interop = typeof(object).Assembly.GetType("Interop+Globalization");
            var m = interop?.GetMethod("GetICUVersion", BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.Public);
            if (m?.Invoke(null, null) is int v && v != 0)
                return $"{(v >> 24) & 0xFF}.{(v >> 16) & 0xFF}.{(v >> 8) & 0xFF}";
        }
        catch { }
        return OperatingSystem.IsWindows() ? "windows-icu" : "unknown";
    }

    private static string? RunTool(string file, params string[] args)
    {
        try
        {
            var psi = new ProcessStartInfo { FileName = file, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
            foreach (var a in args) psi.ArgumentList.Add(a);
            using var p = Process.Start(psi);
            if (p == null) return null;
            var o = p.StandardOutput.ReadToEnd();
            p.WaitForExit(15000);
            return p.ExitCode == 0 ? o : null;
        }
        catch { return null; }
    }

    // ---- neutrality (GF.3.12) ---------------------------------------------------------------------------------------

    /// <summary>Every `platform: any` case regenerated on Windows is compared byte-for-byte (after masking) with the
    /// committed unix golden. A difference must be resolved by re-classifying the case.</summary>
    private static JsonArray NeutralityCheck(string staging, string neutral, JsonObject manifest)
    {
        var divergences = new JsonArray();
        if (manifest["platformDivergences"] is JsonArray existing)
            foreach (var d in existing.OfType<JsonObject>())
                if ((string?)d["resolution"] is { Length: > 0 }) divergences.Add(d.DeepClone());
        var nroot = Path.Combine(neutral, "windows");
        if (!Directory.Exists(nroot)) return divergences;
        foreach (var file in Directory.GetFiles(nroot, "*", SearchOption.AllDirectories).OrderBy(x => x, StringComparer.Ordinal))
        {
            var rel = Path.GetRelativePath(nroot, file).Replace('\\', '/');
            var unix = Path.Combine(staging, rel.Replace('/', Path.DirectorySeparatorChar));
            if (!File.Exists(unix))
            {
                divergences.Add(new JsonObject { ["file"] = rel, ["note"] = "no unix golden to compare with", ["resolution"] = "" });
                continue;
            }
            if (!File.ReadAllBytes(unix).AsSpan().SequenceEqual(File.ReadAllBytes(file)))
                divergences.Add(new JsonObject
                {
                    ["file"] = rel,
                    ["note"] = "the windows run of a platform:any case differs from the unix golden (newline, path API, tz database or file-system semantics) — re-classify the case",
                    ["resolution"] = "",
                });
        }
        foreach (var d in divergences) Console.Error.WriteLine("neutrality: " + d!.ToJsonString());
        return divergences;
    }

    // ---- verify-only diff (DATA-313) --------------------------------------------------------------------------------

    private static List<string> Diff(string root, string staging, RunPlatform platform, string[] families, JsonObject manifest)
    {
        var diffs = new List<string>();
        if (!Directory.Exists(root)) { diffs.Add("no committed fixture root to verify against"); return diffs; }
        var committedManifest = File.Exists(Path.Combine(root, "MANIFEST.json"))
            ? JsonNode.Parse(File.ReadAllText(Path.Combine(root, "MANIFEST.json")))!.AsObject() : null;
        var sameDay = (string?)committedManifest?["today"] == (string?)manifest["today"];
        var todayDependent = new HashSet<string>(StringComparer.Ordinal);
        if (!sameDay && manifest["cases"] is JsonArray cs)
            foreach (var c in cs.OfType<JsonObject>().Where(c => (bool?)c["dependsOnToday"] == true))
                foreach (var o in (c["outputs"] as JsonArray ?? new JsonArray()).OfType<JsonObject>())
                    todayDependent.Add((string)o["file"]!);
        if (manifest["cases"] is JsonArray all)
            foreach (var c in all.OfType<JsonObject>().Where(c => (bool?)c["nonDeterministic"] == true))
                foreach (var o in (c["outputs"] as JsonArray ?? new JsonArray()).OfType<JsonObject>())
                    todayDependent.Add((string)o["file"]!);
        if (todayDependent.Count > 0)
            Console.WriteLine($"verify-only: {todayDependent.Count} dependsOnToday/nonDeterministic output(s) excluded from the byte comparison");

        IEnumerable<string> Scope(string baseDir)
        {
            foreach (var family in families)
            {
                var d = platform == RunPlatform.Unix ? Path.Combine(baseDir, family) : Path.Combine(baseDir, "windows", family);
                if (!Directory.Exists(d)) continue;
                foreach (var f in Directory.GetFiles(d, "*", SearchOption.AllDirectories))
                    yield return Path.GetRelativePath(baseDir, f).Replace('\\', '/');
            }
        }
        var a = Scope(root).ToHashSet(StringComparer.Ordinal);
        var b = Scope(staging).ToHashSet(StringComparer.Ordinal);
        foreach (var m in a.Except(b).OrderBy(x => x, StringComparer.Ordinal)) diffs.Add("missing after regeneration: " + m);
        foreach (var m in b.Except(a).OrderBy(x => x, StringComparer.Ordinal)) diffs.Add("new after regeneration: " + m);
        foreach (var f in a.Intersect(b).OrderBy(x => x, StringComparer.Ordinal))
        {
            if (todayDependent.Contains(f)) continue;
            var x = File.ReadAllBytes(Path.Combine(root, f));
            var y = File.ReadAllBytes(Path.Combine(staging, f));
            if (!x.AsSpan().SequenceEqual(y)) diffs.Add("content differs: " + f);
        }
        static string Normalised(JsonObject? m)
        {
            if (m == null) return "";
            var c = (JsonObject)m.DeepClone();
            c.Remove("generatedAtUtc");
            c.Remove("today");
            if (c["generator"] is JsonObject g) { g.Remove("sdk"); }
            return c.ToJsonString();
        }
        if (Normalised(committedManifest) != Normalised(manifest)) diffs.Add("MANIFEST.json differs (beyond generatedAtUtc/today)");
        return diffs;
    }

    // ---- child: case <family> ---------------------------------------------------------------------------------------

    public static int Case(string family, string staging, string? neutral, string tz, string runId, RunPlatform platform,
                           string? only, string today)
    {
        World.PinCulture();
        var dataDir = Environment.GetEnvironmentVariable("AA_DATA_DIR") ?? throw new InvalidOperationException("AA_DATA_DIR not set");
        World.AssertEnvironment(platform, tz, dataDir);
        var committed = new JsonArray();
        var neutralRecords = new JsonArray();
        var defs = Catalog.All.Where(c => c.Family == family && c.RunsOn(platform)
                                         && (only == null ? !c.OwnProcess : c.Id == only)
                                         && (platform == RunPlatform.Windows || c.Tz == tz)).ToList();
        foreach (var def in defs)
        {
            var commits = def.Commits(platform);
            if (!commits && neutral == null) continue;
            World.Reset();
            var run = new CaseRun(def, commits ? staging : neutral!, dataDir, platform, runId, today);
            try { def.Run(run); }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"case {def.Id} failed: {ex}");
                return 1;
            }
            (commits ? committed : neutralRecords).Add(run.Record());
            Console.WriteLine($"  {run.Id,-14} {def.Title}");
        }
        var name = $"{family}.{Fx.Slug(tz)}.{(only ?? "all")}.json";
        if (committed.Count > 0)
        {
            Directory.CreateDirectory(Path.Combine(staging, ".partial"));
            File.WriteAllText(Path.Combine(staging, ".partial", name), committed.ToJsonString(), Fx.Utf8NoBom);
        }
        if (neutral != null && neutralRecords.Count > 0)
        {
            Directory.CreateDirectory(Path.Combine(neutral, ".partial"));
            File.WriteAllText(Path.Combine(neutral, ".partial", name), neutralRecords.ToJsonString(), Fx.Utf8NoBom);
        }
        return 0;
    }
}
