using System;
using System.Collections.Generic;
using System.Linq;
using AA.Models;

namespace AA.Services;

/// <summary>How the Crew roster is sorted.</summary>
public enum CrewSortMode { SignOffDate, LastName, FirstName, Cid, BirthDate }

/// <summary>Date component order used by the crew table (the separator is chosen separately).</summary>
public enum CrewDateFormat { Iso, DayMonthYear, MonthDayYear, DayMonthName }

/// <summary>One selectable column for the crew table: a stable key, a display header, whether it holds a
/// date (so the chosen format/separator applies), and how to read the raw value from a crew member.</summary>
public sealed class CrewColumn
{
    public required string Key { get; init; }
    public required string Header { get; init; }
    public bool IsDate { get; init; }
    public required Func<CrewMember, string> Raw { get; init; }
}

/// <summary>The catalog of every column the crew table can show, plus the shared date formatting and the
/// roster sort keys — so the roster, the table window and the Excel export all agree on fields and formats.</summary>
public static class CrewColumns
{
    /// <summary>All available columns, in a sensible default order.</summary>
    public static readonly IReadOnlyList<CrewColumn> All = new List<CrewColumn>
    {
        Col("LastName",        "Last Name",         c => c.LastName),
        Col("FirstName",       "First Name",        c => c.FirstName),
        Col("MiddleName",      "Middle Name",       c => c.MiddleName),
        Col("FullName",        "Full Name",         c => c.FullName),
        Col("Cid",             "CID",               c => c.EmployeeId),
        Col("Rank",            "Rank",              c => c.Rank),
        Col("RankCode",        "Rank Code",         c => c.RankCode),
        Col("Nationality",     "Nationality",       c => c.Nationality),
        Col("Gender",          "Gender",            c => c.Gender),
        Date("DateOfBirth",    "Date of Birth",     c => c.DateOfBirth),
        Col("PlaceOfBirth",    "Place of Birth",    c => c.PlaceOfBirth),
        Col("Height",          "Height",            c => c.Height),
        Col("EyesColor",       "Eyes",              c => c.EyesColor),
        Col("HairColor",       "Hair",              c => c.HairColor),
        Col("UserType",        "User Type",         c => c.UserType),
        Col("SignedOnOff",     "Signed On/Off",     c => c.SignedOnOff),
        Col("Company",         "Company",           c => c.Company),
        Col("Vessel",          "Vessel",            c => c.Vessel),
        Date("SignOnDate",     "Sign-On Date",      c => c.SignOnDate),
        Col("SignOnPort",      "Sign-On Port",      c => c.SignOnPort),
        Date("SignOffDate",    "Sign-Off Date",     c => c.SignOffDate),
        Col("SignOffPort",     "Sign-Off Port",     c => c.SignOffPort),
        Col("DaysUntilSignOff","Days to Sign-Off",  c => c.DaysUntilSignOff(DateTime.Today)?.ToString() ?? ""),
        Col("ContractStatus",  "Contract Status",   c => c.ContractStatusOn(DateTime.Today).ToString()),
        Col("PassportNumber",  "Passport No.",      c => c.PassportNumber),
        Date("PassportExpiry", "Passport Expiry",   c => c.PassportExpiry),
        Date("PassportIssued", "Passport Issued",   c => c.PassportIssued),
        Col("SeamansBookNumber","Seaman's Book No.", c => c.SeamansBookNumber),
        Date("SeamansBookExpiry","Seaman's Book Expiry", c => c.SeamansBookExpiry),
        Date("SeamansBookIssued","Seaman's Book Issued", c => c.SeamansBookIssued),
        Col("CocNumber",       "CoC No.",           c => c.CocNumber),
        Date("CocExpiry",      "CoC Expiry",        c => c.CocExpiry),
        Date("CocIssue",       "CoC Issue",         c => c.CocIssue),
        Date("HealthCertExpiry","Health Cert Expiry", c => c.HealthCertExpiry),
        Col("NokFirstName",    "Next of Kin (First)", c => c.NokFirstName),
        Col("NokLastName",     "Next of Kin (Last)",  c => c.NokLastName),
        Col("NokRelationship", "Next of Kin (Relation)", c => c.NokRelationship),
        Col("ChecklistCount",  "Checklist Items",   c => c.Checklist.Count.ToString()),
        Col("ImportedAt",      "Imported At",       c => c.ImportedAt),
        Col("SourceFile",      "Source File",       c => c.SourceFile),
    };

    private static readonly Dictionary<string, CrewColumn> ByKey = All.ToDictionary(c => c.Key, StringComparer.Ordinal);

    /// <summary>Default columns shown when the user hasn't configured any.</summary>
    public static readonly string[] Defaults =
        { "LastName", "FirstName", "Cid", "Rank", "Nationality", "DateOfBirth", "SignOnDate", "SignOffDate", "ContractStatus" };

    /// <summary>Resolve a saved key list to real columns (dropping unknown keys); falls back to the
    /// defaults when the list is empty.</summary>
    public static List<CrewColumn> Resolve(IEnumerable<string>? keys)
    {
        var chosen = (keys ?? Enumerable.Empty<string>())
            .Select(k => ByKey.TryGetValue(k, out var c) ? c : null)
            .Where(c => c != null)!.Cast<CrewColumn>().ToList();
        if (chosen.Count == 0)
            chosen = Defaults.Select(k => ByKey[k]).ToList();
        return chosen;
    }

    /// <summary>The cell value for a column, applying the chosen date format/separator to date columns.
    /// An unparseable date is shown as its raw stored text rather than being dropped.</summary>
    public static string Cell(CrewColumn col, CrewMember m, CrewDateFormat fmt, string separator)
    {
        var raw = col.Raw(m) ?? "";
        if (!col.IsDate || raw.Length == 0) return raw;
        var d = CrewMember.ParseDate(raw);
        // InvariantCulture so output is deterministic regardless of the machine locale.
        return d == null ? raw : d.Value.ToString(Pattern(fmt, separator), System.Globalization.CultureInfo.InvariantCulture);
    }

    /// <summary>Build a .NET date pattern from the component order and separator. The separator is emitted as
    /// a quoted LITERAL so characters like '/', ':' or format letters ('m', 'y', …) are taken verbatim
    /// instead of being interpreted as date/time specifiers.</summary>
    public static string Pattern(CrewDateFormat fmt, string sep)
    {
        var s = LiteralSeparator(sep);
        return fmt switch
        {
            CrewDateFormat.DayMonthYear  => $"dd{s}MM{s}yyyy",
            CrewDateFormat.MonthDayYear  => $"MM{s}dd{s}yyyy",
            CrewDateFormat.DayMonthName  => $"dd{s}MMM{s}yyyy",
            _                            => $"yyyy{s}MM{s}dd",
        };
    }

    private static string LiteralSeparator(string? sep)
    {
        sep ??= "-";
        if (sep.Length == 0) return "";
        // Wrap in single quotes (escaping any embedded quote) so the whole separator is a literal.
        return "'" + sep.Replace("'", "\\'") + "'";
    }

    private static CrewColumn Col(string key, string header, Func<CrewMember, string> raw)
        => new() { Key = key, Header = header, Raw = m => raw(m) ?? "" };
    private static CrewColumn Date(string key, string header, Func<CrewMember, string> raw)
        => new() { Key = key, Header = header, IsDate = true, Raw = m => raw(m) ?? "" };
}
