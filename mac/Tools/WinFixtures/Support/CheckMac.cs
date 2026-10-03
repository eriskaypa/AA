// Reverse check (spec 01 GF.3.11, DATA-312): proves the real C# accepts what the Mac writes. Input:
// mac/Tests/AACoreTests/Fixtures/mac-out/ written by the Swift emitter (GoldMacOutEmitter, GF.8.5). Runs in a child
// process with a scratch AA_DATA_DIR (DataStore.AppFolder is a static read once) — never the operator's real data.
// MUST also run on Windows: only NTFS rejects Windows-illegal entry names, the failure the bundle check exists for.
using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using AA.Models;
using AA.Services;

namespace WinFixtures;

internal static class CheckMac
{
    private sealed record Item(string File, bool Ok, string Detail);

    /// <summary>`check-mac <dir> --report <file> [--platform p]` — spawns the child with a scratch data folder.</summary>
    public static int Run(string macOut, string report, RunPlatform platform)
    {
        if (Environment.GetEnvironmentVariable("AA_WINFIXTURES_CHECKMAC_CHILD") == "1") return Child(macOut, report, platform);
        var scratch = Path.Combine(Path.GetTempPath(), "aa-winfixtures-checkmac-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(scratch);
        try
        {
            var exe = Environment.ProcessPath!;
            var psi = new ProcessStartInfo { FileName = exe, UseShellExecute = false };
            if (Path.GetFileNameWithoutExtension(exe).Equals("dotnet", StringComparison.OrdinalIgnoreCase))
                psi.ArgumentList.Add(Assembly.GetEntryAssembly()!.Location);
            foreach (var a in new[] { "check-mac", Path.GetFullPath(macOut), "--report", Path.GetFullPath(report),
                                      "--platform", platform.ToString().ToLowerInvariant() })
                psi.ArgumentList.Add(a);
            psi.Environment["AA_DATA_DIR"] = Path.Combine(scratch, "data");
            psi.Environment["AA_WINFIXTURES_CHECKMAC_CHILD"] = "1";
            using var p = Process.Start(psi)!;
            p.WaitForExit();
            return p.ExitCode;
        }
        finally { try { Directory.Delete(scratch, true); } catch { } }
    }

    private static int Child(string macOut, string report, RunPlatform platform)
    {
        World.PinCulture();
        var items = new List<Item>();
        void Add(string file, bool ok, string detail) { items.Add(new Item(file, ok, detail)); Console.WriteLine($"  {(ok ? "ok  " : "FAIL")} {file}  {detail}"); }

        // ---- json/ ----
        foreach (var f in Files(macOut, "json", "*.json"))
        {
            World.Reset();
            try
            {
                var macText = File.ReadAllText(f, Fx.Utf8NoBom);
                var data = DataStore.LoadFrom(f);
                var windows = DataStore.SerializeForSave(data);
                var projected = ProjectOutNestedUnknowns(macText);
                Add(Rel(macOut, f), windows == projected,
                    windows == projected ? "loads; SerializeForSave reproduces the Mac bytes (nested unknowns projected out)"
                                         : "loads, but the Windows re-serialisation differs at char " + FirstDiff(windows, projected));
            }
            catch (Exception ex) { Add(Rel(macOut, f), false, "LoadFrom threw " + ex.GetType().FullName + ": " + ex.Message); }
        }

        // ---- settings/ ----
        foreach (var f in Files(macOut, "settings", "*.json").Where(x => !x.EndsWith(".expect.json", StringComparison.Ordinal)))
        {
            World.Reset();
            try
            {
                File.Copy(f, DataStore.SettingsFile, true);
                DataStore.LoadSettings();
                var expectPath = f[..^".json".Length] + ".expect.json";
                var ok = true; var detail = "LoadSettings ok";
                if (File.Exists(expectPath))
                {
                    var expect = JsonNode.Parse(File.ReadAllText(expectPath)
                        .Replace("%%DATADIR%%", Fx.JsonEscape(DataStore.AppFolder))
                        .Replace("%%MACHINE%%", Fx.JsonEscape(Environment.MachineName)))!.AsObject();
                    var state = FamilyB.Dump();
                    foreach (var (k, v) in expect)
                        if (!JsonNode.DeepEquals(v, state[k])) { ok = false; detail = $"state {k}: expected {v?.ToJsonString()} got {state[k]?.ToJsonString()}"; break; }
                }
                var before = JsonNode.Parse(File.ReadAllText(DataStore.SettingsFile))!.AsObject().Select(kv => kv.Key).ToList();
                DataStore.SetDarkMode(!DataStore.DarkMode);
                var after = JsonNode.Parse(File.ReadAllText(DataStore.SettingsFile))!.AsObject().Select(kv => kv.Key).ToHashSet();
                var lost = before.Where(k => !after.Contains(k)).ToList();
                if (lost.Count > 0) { ok = false; detail = "SetDarkMode round trip lost keys " + string.Join(", ", lost); }
                Add(Rel(macOut, f), ok, detail);
            }
            catch (Exception ex) { Add(Rel(macOut, f), false, ex.GetType().FullName + ": " + ex.Message); }
        }

        // ---- crypto/ ----
        var locks = Path.Combine(macOut, "crypto", "locks.json");
        if (File.Exists(locks))
            foreach (var row in JsonNode.Parse(File.ReadAllText(locks))!.AsArray().OfType<JsonObject>())
            {
                var t = new TaskItem { Id = Guid.NewGuid(), LockHash = (string?)row["lockHash"], LockSalt = (string?)row["lockSalt"] };
                var right = ItemLockService.Verify(t, (string)row["password"]!);
                var wrong = ItemLockService.Verify(t, (string)row["wrong"]!);
                Add($"crypto/locks.json#{row["name"]}", right && !wrong, $"Verify(right)={right}, Verify(wrong)={wrong}");
            }
        var blobs = Path.Combine(macOut, "crypto", "blobs.json");
        if (File.Exists(blobs))
            foreach (var row in JsonNode.Parse(File.ReadAllText(blobs))!.AsArray().OfType<JsonObject>())
            {
                PasswordService.LoadFrom((string?)row["passwordHash"], (string?)row["passwordSalt"]);
                var unlocked = PasswordService.Unlock((string)row["password"]!);
                var plain = PasswordService.Decrypt((string)row["blob"]!);
                var ok = unlocked && plain == (string?)row["plaintext"];
                Add($"crypto/blobs.json#{row["name"]}", ok, $"Unlock={unlocked}, Decrypt {(plain == null ? "null" : plain == (string?)row["plaintext"] ? "= plaintext" : "≠ plaintext")}");
            }

        // ---- bundles/ ----
        foreach (var f in Files(macOut, "bundles", "*.*").Where(x => x.EndsWith(".zip", StringComparison.OrdinalIgnoreCase) || x.EndsWith(".aaz", StringComparison.OrdinalIgnoreCase)))
        {
            World.Reset();
            try
            {
                File.WriteAllText(DataStore.DefaultDataFile, DataStore.SerializeForSave(KitchenSink.Build()), Fx.Utf8NoBom);
                Directory.CreateDirectory(DataStore.FilesFolder);
                File.WriteAllText(Path.Combine(DataStore.FilesFolder, "a.pdf"), "0123456789");
                File.WriteAllText(Path.Combine(DataStore.FilesFolder, "b.pdf"), "abcde");
                var expectPath = Path.ChangeExtension(f, null) + ".expect.json";
                var expect = File.Exists(expectPath) ? JsonNode.Parse(File.ReadAllText(expectPath))!.AsObject() : new JsonObject();
                var kind = DataStore.ImportBundleSmart(f).ToString();
                var files = Directory.GetFiles(DataStore.FilesFolder).Select(Path.GetFileName).OrderBy(x => x, StringComparer.Ordinal).ToList();
                var problems = new List<string>();
                if (expect["importKind"] is JsonNode ek && (string?)ek != kind) problems.Add($"ImportKind {kind}, expected {ek}");
                if (expect["files"] is JsonArray ef)
                {
                    var want = ef.Select(x => (string?)x).OrderBy(x => x, StringComparer.Ordinal).ToList();
                    if (!want.SequenceEqual(files)) problems.Add($"files/ = [{string.Join(", ", files)}], expected [{string.Join(", ", want)}]");
                }
                if (DataStore.PeekBundleSource(f) == null) problems.Add("PeekBundleSource null");
                if (DataStore.PeekZipData(f) == null) problems.Add("PeekZipData null");
                if (DataStore.PeekZipLastModified(f) == null && expect["hasLastModified"] is JsonNode h && (bool)h) problems.Add("PeekZipLastModified null");
                Add(Rel(macOut, f), problems.Count == 0, problems.Count == 0 ? $"ImportBundleSmart → {kind}" : string.Join("; ", problems));
            }
            catch (Exception ex) { Add(Rel(macOut, f), false, ex.GetType().FullName + ": " + ex.Message); }
        }

        var reportNode = new JsonObject
        {
            ["platform"] = platform.ToString().ToLowerInvariant(),
            ["runtime"] = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
            ["checkedUtc"] = DateTime.UtcNow.ToString("O"),
            ["items"] = new JsonArray(items.Select(i => (JsonNode?)new JsonObject { ["file"] = i.File, ["ok"] = i.Ok, ["detail"] = i.Detail }).ToArray()),
        };
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(report))!);
        File.WriteAllText(report, Fx.Expect(reportNode), Fx.Utf8NoBom);
        var failed = items.Count(i => !i.Ok);
        Console.WriteLine($"check-mac: {items.Count} artefact(s), {failed} failure(s) → {report}");
        return failed == 0 && items.Count > 0 ? 0 : 1;
    }

    private static IEnumerable<string> Files(string root, string sub, string pattern)
    {
        var d = Path.Combine(root, sub);
        return Directory.Exists(d) ? Directory.GetFiles(d, pattern).OrderBy(x => x, StringComparer.Ordinal) : Enumerable.Empty<string>();
    }

    private static string Rel(string root, string f) => Path.GetRelativePath(root, f).Replace('\\', '/');

    private static int FirstDiff(string a, string b)
    {
        int n = Math.Min(a.Length, b.Length), i = 0;
        while (i < n && a[i] == b[i]) i++;
        return i;
    }

    /// <summary>The Mac file minus every nested unknown member (the Mac keeps them on every object, Windows only on
    /// AppData and Ui — A10), re-serialised compactly with the default encoder.</summary>
    public static string ProjectOutNestedUnknowns(string macText)
    {
        var root = JsonNode.Parse(macText)!;
        Walk(root, typeof(AppData), isRoot: true);
        return root.ToJsonString();
    }

    private static void Walk(JsonNode? node, Type type, bool isRoot)
    {
        switch (node)
        {
            case JsonObject o:
                if (typeof(System.Collections.IDictionary).IsAssignableFrom(type)) return;   // TabColors, SortAZ, QuestionStatuses…
                var props = type.GetProperties(BindingFlags.Public | BindingFlags.Instance)
                    .Where(p => p.GetIndexParameters().Length == 0 && p.GetCustomAttribute<JsonIgnoreAttribute>() == null
                                && p.GetCustomAttribute<JsonExtensionDataAttribute>() == null)
                    .ToDictionary(p => p.Name, p => p.PropertyType, StringComparer.Ordinal);
                bool keepsUnknown = isRoot || type.GetProperties().Any(p => p.GetCustomAttribute<JsonExtensionDataAttribute>() != null);
                foreach (var key in o.Select(kv => kv.Key).ToList())
                {
                    if (props.TryGetValue(key, out var t)) Walk(o[key], t, isRoot: false);
                    else if (!keepsUnknown) o.Remove(key);
                }
                break;
            case JsonArray a:
                var element = type.IsGenericType ? type.GetGenericArguments().FirstOrDefault() : type.GetElementType();
                if (element == null) return;
                foreach (var item in a) Walk(item, element, isRoot: false);
                break;
        }
    }
}
