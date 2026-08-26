using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

namespace AA.Services;

/// <summary>Which way round an ambiguous numeric date is written.</summary>
public enum DateOrder
{
    /// <summary>Nothing in the data settled it.</summary>
    Unknown,
    /// <summary>03/04 means 3 April.</summary>
    DayFirst,
    /// <summary>03/04 means 4 March.</summary>
    MonthFirst,
    /// <summary>The data contains proof of BOTH, so no single convention fits it.</summary>
    Conflicted
}

/// <summary>What a date field means, which decides how a 2-digit year is expanded.</summary>
public enum DateRole
{
    Any,
    /// <summary>Birth dates, issue dates — cannot be in the future.</summary>
    PastOnly,
    /// <summary>Expiries, sign-off dates — normally ahead of today.</summary>
    FutureLikely
}

/// <summary>One resolved value, with enough context to explain itself.</summary>
public sealed class DateResolution
{
    public DateTime? Value { get; init; }
    public string Raw { get; init; } = "";

    /// <summary>Set when the value depended on the inferred day/month order, so a wrong inference is
    /// traceable to exactly these cells.</summary>
    public bool DependedOnOrder { get; init; }

    public string? Note { get; init; }

    /// <summary>Canonical storage form. The app stores dates as yyyy-MM-dd strings; unreadable input keeps
    /// its original text rather than being thrown away.</summary>
    public string ToStorage() => Value?.ToString("yyyy-MM-dd") ?? Raw;
}

/// <summary>Reads dates in whatever shape they arrive, and — the hard part — decides whether ambiguous
/// numeric dates like 03/04/2026 are day-first or month-first.
///
/// That question cannot be answered from a single value, so it is answered from the whole column: if any
/// date has a first component above 12 the column must be day-first; if any has a second component above
/// 12 it must be month-first. One unambiguous value settles every ambiguous one around it.
///
/// When the data proves both, or proves neither, this says so rather than guessing. A wrong guess moves a
/// contract expiry by weeks and nothing on screen would look wrong.</summary>
public sealed class DateResolver
{
    // Ambiguous numeric date: 3/4/26, 03-04-2026, 03.04.2026. The backreference forces a single separator,
    // so "03/04-2026" is not mistaken for a date.
    private static readonly Regex Numeric =
        new(@"^(\d{1,2})([/.\-])(\d{1,2})\2(\d{2}|\d{4})$", RegexOptions.Compiled);

    // Year-first, always unambiguous: 2026-03-04, 2026/3/4.
    private static readonly Regex YearFirst =
        new(@"^(\d{4})([/.\-])(\d{1,2})\2(\d{1,2})$", RegexOptions.Compiled);

    // Two-digit year first (98-03-04) — the leading value is too large to be a day or a month.
    private static readonly Regex ShortYearFirst =
        new(@"^(\d{2})([/.\-])(\d{1,2})\2(\d{1,2})$", RegexOptions.Compiled);

    private static readonly string[] MonthNameFormats =
    {
        "d MMM yyyy", "d MMMM yyyy", "dd MMM yyyy", "dd MMMM yyyy",
        "MMM d yyyy", "MMMM d yyyy",
        "d-MMM-yyyy", "dd-MMM-yyyy", "d-MMM-yy", "dd-MMM-yy",
        "d MMM yy", "dd MMM yy", "yyyy MMM d"
    };

    /// <summary>Values meaning "no date", as opposed to "unreadable date" — no warning is owed for these.</summary>
    private static readonly HashSet<string> Placeholders = new(StringComparer.OrdinalIgnoreCase)
    {
        "-", "--", "---", "n/a", "na", "n.a.", "nil", "none", "tbc", "tba", "tbd",
        "pending", "unknown", "?", "x", "#n/a", "#ref!", "#value!", "null"
    };

    /// <summary>Excel's zero-ish sentinels, which mean empty rather than the year 1900.</summary>
    private static readonly HashSet<string> ZeroDates = new(StringComparer.OrdinalIgnoreCase)
    {
        "0", "00/00/0000", "00-00-0000", "1900-01-01", "1899-12-30", "01/01/1900", "30/12/1899"
    };

    private readonly List<string> _dayWitnesses = new();
    private readonly List<string> _monthWitnesses = new();

    /// <summary>The convention decided by <see cref="Infer"/>.</summary>
    public DateOrder Order { get; private set; } = DateOrder.Unknown;

    /// <summary>How many values proved the convention. One witness could be a typo; several is evidence.</summary>
    public int DecisiveCount => Order == DateOrder.DayFirst ? _dayWitnesses.Count
                              : Order == DateOrder.MonthFirst ? _monthWitnesses.Count
                              : 0;

    public IReadOnlyList<string> DayWitnesses => _dayWitnesses;
    public IReadOnlyList<string> MonthWitnesses => _monthWitnesses;

    /// <summary>True when the data proved both conventions — a broken file, not a choice to be made.</summary>
    public bool IsConflicted => Order == DateOrder.Conflicted;

    /// <summary>Feed every candidate date string before calling <see cref="Infer"/>. Already-unambiguous
    /// values (ISO, month names, typed cells) contribute no evidence and are ignored.</summary>
    public void Observe(string? raw)
    {
        var s = Clean(raw);
        if (s.Length == 0) return;
        var m = Numeric.Match(s);
        if (!m.Success) return;

        int c1 = int.Parse(m.Groups[1].Value), c2 = int.Parse(m.Groups[3].Value);
        if (c1 > 31 || c2 > 31 || (c1 > 12 && c2 > 12)) return;   // not a date at all

        if (c1 > 12) { if (_dayWitnesses.Count < 50) _dayWitnesses.Add(s); }
        else if (c2 > 12) { if (_monthWitnesses.Count < 50) _monthWitnesses.Add(s); }
    }

    /// <summary>Decide the convention from everything observed. <paramref name="fallback"/> applies only
    /// when nothing in the data settled it — pass Unknown to refuse to guess.</summary>
    public void Infer(DateOrder fallback = DateOrder.Unknown)
    {
        bool day = _dayWitnesses.Count > 0, month = _monthWitnesses.Count > 0;
        if (day && month) Order = DateOrder.Conflicted;   // never take a majority: half the rows would be wrong
        else if (day) Order = DateOrder.DayFirst;
        else if (month) Order = DateOrder.MonthFirst;
        else Order = fallback;
    }

    /// <summary>Adopt a convention decided elsewhere — another column in the same file, or the user.</summary>
    public void Adopt(DateOrder order) => Order = order;

    /// <summary>Read one value. Never throws: bad input comes back unparsed with its original text kept.</summary>
    public DateResolution Resolve(string? raw, DateRole role = DateRole.Any)
    {
        var s = Clean(raw);
        if (s.Length == 0) return new DateResolution { Raw = "" };
        if (Placeholders.Contains(s)) return new DateResolution { Raw = "" };
        if (ZeroDates.Contains(s)) return new DateResolution { Raw = "", Note = "empty date" };

        s = StripTime(s);

        // ---- Unambiguous shapes, most certain first ----
        var ym = YearFirst.Match(s);
        if (ym.Success && TryMake(int.Parse(ym.Groups[1].Value), int.Parse(ym.Groups[3].Value),
                                  int.Parse(ym.Groups[4].Value), out var isoDate))
            return new DateResolution { Value = isoDate, Raw = s };

        if (s.Length == 8 && s.All(char.IsDigit) &&
            TryMake(int.Parse(s.Substring(0, 4)), int.Parse(s.Substring(4, 2)), int.Parse(s.Substring(6, 2)),
                    out var compact))
            return new DateResolution { Value = compact, Raw = s };

        if (TryMonthName(s, role, out var named))
            return new DateResolution { Value = named, Raw = s };

        var sy = ShortYearFirst.Match(s);
        if (sy.Success && int.Parse(sy.Groups[1].Value) > 31 &&
            TryMake(ExpandYear(int.Parse(sy.Groups[1].Value), role), int.Parse(sy.Groups[3].Value),
                    int.Parse(sy.Groups[4].Value), out var shortIso))
            return new DateResolution { Value = shortIso, Raw = s };

        // ---- Ambiguous numeric ----
        var nm = Numeric.Match(s);
        if (!nm.Success)
            return new DateResolution { Raw = s, Note = "'" + s + "' is not a date AA recognises" };

        int a = int.Parse(nm.Groups[1].Value), b = int.Parse(nm.Groups[3].Value);
        bool fullYear = nm.Groups[4].Value.Length == 4;
        int year = ExpandYear(int.Parse(nm.Groups[4].Value), role, fullYear);

        // A component above 12 settles this value on its own, whatever the column convention is.
        if (a > 12 && b <= 12)
            return TryMake(year, b, a, out var d1)
                ? new DateResolution { Value = d1, Raw = s }
                : new DateResolution { Raw = s, Note = "'" + s + "' is not a real date" };
        if (b > 12 && a <= 12)
            return TryMake(year, a, b, out var d2)
                ? new DateResolution { Value = d2, Raw = s }
                : new DateResolution { Raw = s, Note = "'" + s + "' is not a real date" };
        if (a > 12 && b > 12)
            return new DateResolution { Raw = s, Note = "'" + s + "' is not a real date" };

        // Genuinely ambiguous: both readings are valid dates. Only the column convention can decide.
        if (Order == DateOrder.DayFirst && TryMake(year, b, a, out var dayFirst))
        {
            var other = TryMake(year, a, b, out var alt) ? alt.ToString("d MMM yyyy") : "an invalid date";
            return new DateResolution
            {
                Value = dayFirst,
                Raw = s,
                DependedOnOrder = true,
                Note = "read as " + dayFirst.ToString("d MMM yyyy") + " (day first); would be " + other + " if month first"
            };
        }
        if (Order == DateOrder.MonthFirst && TryMake(year, a, b, out var monthFirst))
        {
            var other = TryMake(year, b, a, out var alt) ? alt.ToString("d MMM yyyy") : "an invalid date";
            return new DateResolution
            {
                Value = monthFirst,
                Raw = s,
                DependedOnOrder = true,
                Note = "read as " + monthFirst.ToString("d MMM yyyy") + " (month first); would be " + other + " if day first"
            };
        }
        if (Order == DateOrder.Conflicted)
            return new DateResolution
            {
                Raw = s,
                DependedOnOrder = true,
                Note = "'" + s + "' left unread — this file writes dates both ways, so neither reading is safe"
            };

        return new DateResolution
        {
            Raw = s,
            DependedOnOrder = true,
            Note = "'" + s + "' could be " + a + " " + Month(b) + " or " + b + " " + Month(a) +
                   ", and nothing in the file says which"
        };
    }

    /// <summary>An Excel serial number (days since 1899-12-30, or 1904-01-01 on the Mac system). These
    /// carry no ambiguity at all, which is why a typed date cell must never be turned back into text.</summary>
    public static DateTime? FromExcelSerial(double serial, bool use1904 = false)
    {
        if (double.IsNaN(serial) || double.IsInfinity(serial)) return null;
        if (serial < 1 || serial > 73051) return null;              // outside 1900..2099 — not a date
        var epoch = use1904 ? new DateTime(1904, 1, 1) : new DateTime(1899, 12, 30);
        try { return epoch.AddDays(Math.Floor(serial)); } catch { return null; }
    }

    public static bool IsPlaceholder(string? s)
    {
        var t = Clean(s);
        return t.Length > 0 && (Placeholders.Contains(t) || ZeroDates.Contains(t));
    }

    // ---- helpers ----

    private static string Clean(string? raw) => (raw ?? "").Replace(' ', ' ').Trim();

    /// <summary>Drop a trailing time or zone marker. Never convert time zones — that can shift the DAY.</summary>
    private static string StripTime(string s)
    {
        int t = s.IndexOf('T');
        if (t >= 8) s = s.Substring(0, t);
        int sp = s.IndexOf(' ');
        if (sp > 0 && s.Substring(sp + 1).Contains(':')) s = s.Substring(0, sp);
        return s.TrimEnd('Z', 'z').Trim();
    }

    private static bool TryMonthName(string s, DateRole role, out DateTime value)
    {
        // "SEPT" is common in crew lists and is not a .NET abbreviation; ordinals appear too.
        var t = Regex.Replace(s, @"\bSEPT\b", "Sep", RegexOptions.IgnoreCase);
        t = Regex.Replace(t, @"(?<=\d)(st|nd|rd|th)\b", "", RegexOptions.IgnoreCase);
        t = t.Replace(",", " ");
        t = Regex.Replace(t, @"\s+", " ").Trim();

        foreach (var f in MonthNameFormats)
            if (DateTime.TryParseExact(t, f, CultureInfo.InvariantCulture, DateTimeStyles.None, out value))
            {
                if (f.Contains("yy") && !f.Contains("yyyy"))
                    value = new DateTime(ExpandYear(value.Year % 100, role), value.Month, value.Day);
                return true;
            }

        // Only if a month NAME is present do we fall back to the general parser. A bare "03/04/2026" must
        // never reach it: that parser is month-first and would silently decide the ambiguity for us.
        if (Regex.IsMatch(t, "[A-Za-z]{3}") &&
            DateTime.TryParse(t, CultureInfo.InvariantCulture, DateTimeStyles.None, out value))
            return true;

        value = default;
        return false;
    }

    /// <summary>Expand a 2-digit year using the field's meaning. .NET's default pivot (2049) turns a
    /// passport expiring in '50 into 1950, which then reads as long expired.</summary>
    private static int ExpandYear(int y, DateRole role, bool alreadyFull = false)
    {
        if (alreadyFull || y > 99) return y;
        // Base pivot: 00-68 -> 2000s, 69-99 -> 1900s (the usual convention). Blindly adding the current
        // century would read a seafarer born in '98 as 2098.
        int candidate = y <= 68 ? 2000 + y : 1900 + y;
        // Then let the field's meaning override it: an expiry is not in the past, a birth date is not
        // in the future.
        if (role == DateRole.PastOnly && candidate > DateTime.Today.Year) return candidate - 100;
        if (role == DateRole.FutureLikely && candidate < DateTime.Today.Year - 5) return candidate + 100;
        return candidate;
    }

    private static bool TryMake(int y, int m, int d, out DateTime value)
    {
        value = default;
        if (y < 1900 || y > 2199 || m < 1 || m > 12 || d < 1) return false;
        if (d > DateTime.DaysInMonth(y, m)) return false;
        value = new DateTime(y, m, d);
        return true;
    }

    private static string Month(int m) =>
        m >= 1 && m <= 12 ? CultureInfo.InvariantCulture.DateTimeFormat.GetAbbreviatedMonthName(m) : "?";
}
