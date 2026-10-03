// Shared constants and helpers of the oracle (spec 01 GF.3.5 determinism controls, GF.3.6 reflection access,
// GF.3.8 expectation JSON).
using System.Globalization;
using System.Reflection;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using AA.Models;
using AA.Services;

namespace WinFixtures;

internal enum RunPlatform { Unix, Windows }

internal static class Fx
{
    // ---- ids (GF.3.5) -------------------------------------------------------------------------------------------

    /// <summary>G(n) = aaaaaaaa-0000-4000-8000-{n:D12}: every constructed object gets an explicit id.</summary>
    public static Guid G(int n) => Guid.Parse($"aaaaaaaa-0000-4000-8000-{n.ToString("D12", CultureInfo.InvariantCulture)}");

    // ---- dates (exact ticks and kind, GF.3.5) ---------------------------------------------------------------------

    /// <summary>D_U: 2026-10-01 00:00 Unspecified.</summary>
    public static DateTime D_U => new(2026, 10, 1, 0, 0, 0, DateTimeKind.Unspecified);
    /// <summary>D_U7: 2026-10-01 08:30:15.1234567 Unspecified (7 fraction digits).</summary>
    public static DateTime D_U7 => new DateTime(2026, 10, 1, 8, 30, 15, DateTimeKind.Unspecified).AddTicks(1234567);
    /// <summary>D_L: 2026-09-29 11:15:30.5 Local (1 fraction digit; Europe/Athens = +03:00 in the json group).</summary>
    public static DateTime D_L => new DateTime(2026, 9, 29, 11, 15, 30, DateTimeKind.Local).AddTicks(5_000_000);
    /// <summary>D_LM: 2026-09-29 11:15:29.9876543 Local — the root LastModified stamp.</summary>
    public static DateTime D_LM => new DateTime(2026, 9, 29, 11, 15, 29, DateTimeKind.Local).AddTicks(9876543);
    /// <summary>D_Z: 2026-09-29 08:15:30.1234560 Utc.</summary>
    public static DateTime D_Z => new DateTime(2026, 9, 29, 8, 15, 30, DateTimeKind.Utc).AddTicks(1234560);
    /// <summary>D_Z0: 2026-09-29 08:15:30 Utc (no fraction).</summary>
    public static DateTime D_Z0 => new(2026, 9, 29, 8, 15, 30, DateTimeKind.Utc);

    public static DateTime Day(int y, int m, int d, DateTimeKind k = DateTimeKind.Unspecified) => new(y, m, d, 0, 0, 0, k);

    // ---- the app's own serializer options (GF.3.6: read-only reflection) ------------------------------------------

    public static readonly JsonSerializerOptions Opts =
        (JsonSerializerOptions)typeof(DataStore).GetField("Opts", BindingFlags.NonPublic | BindingFlags.Static)!.GetValue(null)!;

    public static readonly JsonSerializerOptions TrashOpts =
        (JsonSerializerOptions)typeof(AppRepository).GetField("TrashOpts", BindingFlags.NonPublic | BindingFlags.Static)!.GetValue(null)!;

    /// <summary>GF.3.8: expectation JSON (not an AA format) — indented by 2, LF, relaxed escaping, trailing LF.</summary>
    public static readonly JsonSerializerOptions ExpectOpts = new()
    {
        WriteIndented = true,
        IndentSize = 2,
        NewLine = "\n",
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static string Expect(JsonNode? node) => (node?.ToJsonString(ExpectOpts) ?? "null") + "\n";

    /// <summary>The value exactly as the app's Opts write it, without the surrounding quotes for strings.</summary>
    public static string StjText(DateTime dt)
    {
        var s = JsonSerializer.Serialize(dt, Opts);
        return s.Length >= 2 && s[0] == '"' ? s[1..^1] : s;
    }

    /// <summary>The default-encoder JSON escaping of a string (no quotes) — how a path or name appears in data.json.</summary>
    public static string JsonEscape(string s)
    {
        var q = JsonSerializer.Serialize(s);
        return q[1..^1];
    }

    // ---- reflection helpers (GF.3.6) -------------------------------------------------------------------------------

    private const BindingFlags NonPublicStatic = BindingFlags.NonPublic | BindingFlags.Static;

    /// <summary>Invokes a private static method of <paramref name="t"/>. None of the listed methods is overloaded.</summary>
    public static T Call<T>(Type t, string name, params object?[] a)
    {
        var m = t.GetMethod(name, NonPublicStatic) ?? throw new MissingMethodException(t.FullName, name);
        try { return (T)m.Invoke(null, a)!; }
        catch (TargetInvocationException tie) when (tie.InnerException != null)
        {
            System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(tie.InnerException).Throw();
            throw;
        }
    }

    public static void CallVoid(Type t, string name, params object?[] a)
    {
        var m = t.GetMethod(name, NonPublicStatic) ?? throw new MissingMethodException(t.FullName, name);
        try { m.Invoke(null, a); }
        catch (TargetInvocationException tie) when (tie.InnerException != null)
        {
            System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(tie.InnerException).Throw();
        }
    }

    // ---- misc ---------------------------------------------------------------------------------------------------

    public static readonly System.Text.UTF8Encoding Utf8NoBom = new(false);

    public static byte[] Utf8(string s) => Utf8NoBom.GetBytes(s);

    /// <summary>Time-zone slug for folder and file names ("Europe/Athens" → "europe-athens").</summary>
    public static string Slug(string s) => new string(s.ToLowerInvariant().Select(c => char.IsLetterOrDigit(c) ? c : '-').ToArray()).Trim('-');

    /// <summary>The json family's time zones (GF.3.4 TZS(json)), in this order.</summary>
    public static readonly string[] JsonZones =
        { "Europe/Athens", "America/New_York", "Asia/Kolkata", "UTC", "Asia/Kathmandu", "Pacific/Chatham" };

    public const string DefaultZone = "Europe/Athens";

    /// <summary>The Windows-form path inputs (A25, C01): never touched on the unix run except as data.</summary>
    public static bool IsWindowsForm(string p) =>
        p.Length >= 2 && (p[1] == ':' || (p[0] == '\\' && p[1] == '\\'));
}
