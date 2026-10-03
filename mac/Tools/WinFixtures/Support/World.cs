// Determinism controls of the child process (spec 01 GF.3.4 "case(family)", GF.3.5).
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using AA.Models;
using AA.Services;

namespace WinFixtures;

internal static class World
{
    /// <summary>GF.3.5 Culture: en-US for every thread (the reference culture; culture probes are separate cases).</summary>
    public static void PinCulture(string name = "en-US")
    {
        var c = new CultureInfo(name);
        CultureInfo.DefaultThreadCurrentCulture = c;
        CultureInfo.DefaultThreadCurrentUICulture = c;
        CultureInfo.CurrentCulture = c;
        CultureInfo.CurrentUICulture = c;
    }

    /// <summary>The child's environment assertions: zone, data folder, newline.</summary>
    public static void AssertEnvironment(RunPlatform platform, string tz, string dataDir)
    {
        if (platform == RunPlatform.Unix)
        {
            var local = TimeZoneInfo.Local;
            bool ok = local.Id == tz
                      || (tz == "UTC" && local.BaseUtcOffset == TimeSpan.Zero && !local.SupportsDaylightSavingTime);
            if (!ok) throw new InvalidOperationException($"TimeZoneInfo.Local.Id is {local.Id}, expected {tz} (TZ not honoured?)");
            if (Environment.NewLine != "\n") throw new InvalidOperationException("unix run requires Environment.NewLine == \\n");
        }
        else if (Environment.NewLine != "\r\n") throw new InvalidOperationException("windows run requires Environment.NewLine == \\r\\n");
        if (!string.Equals(Path.GetFullPath(DataStore.AppFolder).TrimEnd('/', '\\'), Path.GetFullPath(dataDir).TrimEnd('/', '\\'),
                           StringComparison.Ordinal))
            throw new InvalidOperationException($"DataStore.AppFolder is {DataStore.AppFolder}, expected AA_DATA_DIR {dataDir}");
    }

    /// <summary>GF.3.5 ResetWorld(): empty the data folder, reload settings (no file → defaults), forget the app
    /// password and every item unlock.</summary>
    public static void Reset()
    {
        var dir = DataStore.AppFolder;
        Directory.CreateDirectory(dir);
        foreach (var f in Directory.GetFiles(dir)) File.Delete(f);
        foreach (var d in Directory.GetDirectories(dir)) Directory.Delete(d, recursive: true);
        DataStore.LoadSettings();
        PasswordService.LoadFrom(null, null);
        ItemLockService.RelockAll();
    }

    /// <summary>The file system's case sensitivity (GF.3.5: probed and recorded; case-insensitive is required for
    /// the bundle cases).</summary>
    public static bool CaseInsensitiveFs(string dir)
    {
        Directory.CreateDirectory(dir);
        var probe = Path.Combine(dir, "aa-case-probe-x");
        File.WriteAllText(probe, "x");
        try { return File.Exists(Path.Combine(dir, "AA-CASE-PROBE-X")); }
        finally { File.Delete(probe); }
    }
}

/// <summary>GF.4.7 expectation shapes.</summary>
internal static class Shapes
{
    /// <summary>The DateTime-read shape.</summary>
    public static JsonObject DateRead(string input, Func<DateTime> read)
    {
        try
        {
            var dt = read();
            return DateShape(input, dt);
        }
        catch (Exception ex)
        {
            return new JsonObject { ["input"] = input, ["ok"] = false, ["error"] = new JsonObject { ["type"] = ex.GetType().FullName } };
        }
    }

    public static JsonObject DateShape(string? input, DateTime dt)
    {
        var o = new JsonObject();
        if (input != null) o["input"] = input;
        o["ok"] = true;
        o["ticks"] = dt.Ticks;
        o["kind"] = dt.Kind.ToString();
        o["isAmbiguousTime"] = SafeBool(() => TimeZoneInfo.Local.IsAmbiguousTime(dt));
        o["isDaylightSavingTime"] = SafeBool(dt.IsDaylightSavingTime);
        o["wall"] = dt.ToString("yyyy-MM-dd HH:mm:ss.fffffff", CultureInfo.InvariantCulture);
        o["rewritten"] = Fx.StjText(dt);
        return o;
    }

    /// <summary>A nullable DateTime as the read shape, or JSON null.</summary>
    public static JsonNode? DateOrNull(DateTime? dt) => dt is DateTime d ? DateShape(null, d) : null;

    private static bool SafeBool(Func<bool> f) { try { return f(); } catch { return false; } }

    /// <summary>The exception shape; messages are compared only when written in AA's own source (aaAuthored).</summary>
    public static JsonObject ExceptionShape(Exception ex, bool aaAuthored) => new()
    {
        ["exception"] = new JsonObject
        {
            ["type"] = ex.GetType().FullName,
            ["message"] = ex.Message,
            ["aaAuthored"] = aaAuthored,
        },
    };

    /// <summary>Loads <paramref name="json"/> through DataStore.LoadFrom (written to the data file first) and
    /// re-serialises it. Returns (outcome, bytes-or-null).</summary>
    public static (JsonObject Outcome, string? Bytes, AppData? Model) LoadSave(string json)
    {
        var path = Path.Combine(DataStore.AppFolder, "data.json");
        File.WriteAllText(path, json, Fx.Utf8NoBom);
        AppData model;
        try { model = DataStore.LoadFrom(path); }
        catch (Exception ex)
        {
            var o = new JsonObject { ["loadOk"] = false, ["saveOk"] = false };
            o["exception"] = new JsonObject { ["type"] = ex.GetType().FullName, ["aaAuthored"] = false };
            return (o, null, null);
        }
        try
        {
            var bytes = DataStore.SerializeForSave(model);
            return (new JsonObject { ["loadOk"] = true, ["saveOk"] = true }, bytes, model);
        }
        catch (Exception ex)
        {
            var o = new JsonObject { ["loadOk"] = true, ["saveOk"] = false };
            o["exception"] = new JsonObject { ["type"] = ex.GetType().FullName, ["aaAuthored"] = false };
            return (o, null, model);
        }
    }

    /// <summary>A JsonNode copy of <paramref name="json"/> with the member at <paramref name="path"/> removed
    /// (path = property names / array indices). Used to derive "treat null as default" Mac expectations.</summary>
    public static string WithoutMember(string json, params object[] path)
    {
        var root = JsonNode.Parse(json)!;
        JsonNode cur = root;
        for (int i = 0; i < path.Length - 1; i++)
            cur = path[i] is int k ? cur.AsArray()[k]! : cur.AsObject()[(string)path[i]]!;
        if (path[^1] is int idx) cur.AsArray().RemoveAt(idx);
        else cur.AsObject().Remove((string)path[^1]);
        return root.ToJsonString(new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
    }
}
