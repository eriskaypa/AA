// Volatile-value masking (spec 01 GF.3.7, GF.4.5, DATA-305). Values that are random or clock-derived BY DESIGN are
// replaced by tokens using exact-value substitution; the Swift GoldenMatcher accepts any value of the right shape,
// with same-numbered tokens required to be equal.
using System.Text.RegularExpressions;

namespace WinFixtures;

internal sealed partial class Masker
{
    private readonly List<(string Lit, string Tok)> _subs = new();
    private readonly Dictionary<Guid, int> _guidNumbers = new();
    private int _nextGuid = 1;

    /// <summary>Number already assigned to <paramref name="g"/>, or the next free one.</summary>
    public int Guid(Guid g)
    {
        if (_guidNumbers.TryGetValue(g, out var n)) return n;
        n = _nextGuid++;
        _guidNumbers[g] = n;
        _subs.Add((g.ToString("D"), $"%%NEWGUID:{n}%%"));
        _subs.Add((g.ToString("N"), $"%%GUIDN:{n}%%"));
        return n;
    }

    /// <summary>A DateTime.Now / UtcNow default read back from an object.</summary>
    public void Now(DateTime dt) =>
        _subs.Add((Fx.StjText(dt), dt.Kind == DateTimeKind.Utc ? "%%NOWUTC%%" : "%%NOWLOCAL%%"));

    /// <summary>A literal in raw and JSON-escaped form (paths with '\' or non-ASCII).</summary>
    public void Literal(string s, string token)
    {
        if (string.IsNullOrEmpty(s)) return;
        _subs.Add((s, token));
        var esc = Fx.JsonEscape(s);
        if (esc != s) _subs.Add((esc, token));
        var relaxed = s.Replace("\\", "\\\\");
        if (relaxed != s && relaxed != esc) _subs.Add((relaxed, token));
    }

    /// <summary>A literal that is only masked as a whole JSON string value (the machine name is short and may occur
    /// inside other words).</summary>
    public void QuotedLiteral(string s, string token)
    {
        if (string.IsNullOrEmpty(s)) return;
        _subs.Add(("\"" + Fx.JsonEscape(s) + "\"", "\"" + token + "\""));
        var relaxed = "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
        if (relaxed != "\"" + Fx.JsonEscape(s) + "\"") _subs.Add((relaxed, "\"" + token + "\""));
    }

    public string Apply(string text)
    {
        foreach (var (lit, tok) in _subs.OrderByDescending(x => x.Lit.Length).ThenBy(x => x.Lit, StringComparer.Ordinal))
            text = text.Replace(lit, tok, StringComparison.Ordinal);
        return text;
    }

    // ---- automatic masking against a baseline -----------------------------------------------------------------------

    [GeneratedRegex(@"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")]
    private static partial Regex GuidD();

    [GeneratedRegex(@"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})")]
    private static partial Regex StjDate();

    /// <summary>Masks every lower-case "D" GUID of <paramref name="output"/> that does not occur in
    /// <paramref name="baseline"/> (new by design: Guid.NewGuid() defaults, trash entry ids, batch ids, clones), numbered
    /// in order of first appearance, and every offset- or Z-bearing timestamp that does not occur in the baseline
    /// (DateTime.Now / UtcNow defaults).</summary>
    public void AutoMask(string output, string baseline)
    {
        foreach (Match m in GuidD().Matches(output))
            if (!baseline.Contains(m.Value, StringComparison.Ordinal)) Guid(System.Guid.Parse(m.Value));
        foreach (Match m in StjDate().Matches(output))
            if (!baseline.Contains(m.Value, StringComparison.Ordinal))
                _subs.Add((m.Value, m.Value.EndsWith('Z') ? "%%NOWUTC%%" : "%%NOWLOCAL%%"));
    }

    [GeneratedRegex(@"%%(NEWGUID:\d+|GUIDN:\d+|NOWLOCAL|NOWUTC|MACHINE|DATADIR|DATADIRUPPER|TEMP|SALT16|HASH32|ENCBLOB)%%")]
    private static partial Regex TokenPattern();

    /// <summary>GF.3.7: masking never collides with real content — no input may contain a token.</summary>
    public static void AssertNoToken(string input, string what)
    {
        if (TokenPattern().IsMatch(input))
            throw new InvalidOperationException($"input {what} contains a %%TOKEN%% pattern; masking would be ambiguous");
    }
}
