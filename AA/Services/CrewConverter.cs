using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using AA.Models;

namespace AA.Services;

/// <summary>
/// Converts a COMPAS row into a crew card (<see cref="CrewMember"/>), translating codes into
/// DNV-style controlled vocabularies and recording review notes for anything that needed a guess
/// or is missing. Ported from CrewBridge; extended to also read the sign-off date/port so contract
/// expiries can be tracked.
/// </summary>
public sealed partial class CrewConverter
{
    private readonly string _sourceFile;
    private readonly string _importedAt;

    /// <summary>Every COMPAS column this converter reads as a date, with what the field means (which
    /// decides how a 2-digit year is expanded).</summary>
    private static readonly (string Column, DateRole Role)[] DateColumns =
    {
        ("Date of Birth", DateRole.PastOnly),
        ("Joining Date", DateRole.Any),
        ("Sign Off Date", DateRole.FutureLikely),
        ("Passport Expiry Date", DateRole.FutureLikely),
        ("Passport Issued Date", DateRole.PastOnly),
        ("Seaman Book Expiry Date", DateRole.FutureLikely),
        ("Seaman Book Issue Date", DateRole.PastOnly),
        ("Licence Expiry Date", DateRole.FutureLikely),
        ("Licence Issue Date", DateRole.PastOnly),
        ("Medical Examination Expiry", DateRole.FutureLikely),
    };

    private readonly DateResolver _dates = new();

    /// <summary>The day/month convention this import settled on.</summary>
    public DateOrder DateOrder => _dates.Order;

    /// <summary>How many values proved that convention.</summary>
    public int DateEvidence => _dates.DecisiveCount;

    /// <summary>Dates that could not be read at all, across the whole import.</summary>
    public int UnreadableDates { get; private set; }

    /// <summary>Dates whose meaning depended on the inferred convention, so a wrong inference is visible.</summary>
    public int OrderDependentDates { get; private set; }

    public CrewConverter(string sourceFile)
    {
        _sourceFile = sourceFile;
        _importedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm");
    }

    /// <summary>Read every date in the file BEFORE converting any row, so the day/month convention is
    /// decided from the whole sheet. One value with a day above 12 settles every ambiguous value in it.
    /// Call once, with all rows, before <see cref="Convert"/>.
    ///
    /// <paramref name="fallback"/> is used only when nothing in the file settles it; pass Unknown to
    /// leave ambiguous dates unread rather than guessing at them.</summary>
    public void LearnDateFormat(IEnumerable<CompasRow> rows, DateOrder fallback = DateOrder.Unknown)
    {
        foreach (var row in rows)
            foreach (var (col, _) in DateColumns)
                _dates.Observe(row.Get(col));
        _dates.Infer(fallback);
    }

    /// <summary>A one-line account of how dates were read, for the status bar and the activity log.</summary>
    public string DateSummary()
    {
        var how = _dates.Order switch
        {
            DateOrder.DayFirst => $"day first (dd/mm), proved by {_dates.DecisiveCount} value{(_dates.DecisiveCount == 1 ? "" : "s")}",
            DateOrder.MonthFirst => $"month first (mm/dd), proved by {_dates.DecisiveCount} value{(_dates.DecisiveCount == 1 ? "" : "s")}",
            DateOrder.Conflicted => "inconsistently — this file writes dates BOTH ways, so ambiguous ones were left unread",
            _ => "in unambiguous formats only; nothing in the file said whether 03/04 means 3 April or 4 March"
        };
        var tail = UnreadableDates > 0 ? $", {UnreadableDates} could not be read" : "";
        return $"dates read {how}{tail}";
    }

    public CrewMember Convert(CompasRow row)
    {
        var m = new CrewMember { SourceFile = _sourceFile, ImportedAt = _importedAt };
        var flags = m.Flags;

        // --- names / identity ---
        m.FirstName = row.Get("First name");
        m.LastName = row.Get("Surname");
        m.MiddleName = DeriveMiddle(row);
        m.EmployeeId = FirstNonEmpty(row.Get("Code"), row.Get("CMS ID Number"), row.Get("Passport Number"));

        // --- nationality ---
        var code = row.Get("Nationality code").Trim().ToUpperInvariant();
        var dem = CrewText.Norm(row.Get("Nationality"));
        string nat;
        if (CrewMappingTables.Iso3Nationality.TryGetValue(code, out var n1)) nat = n1;
        else if (CrewMappingTables.DemonymNationality.TryGetValue(dem, out var n2)) nat = n2;
        else nat = row.Get("Nationality");
        m.RawNationality = row.Get("Nationality");
        m.Nationality = nat;

        // --- demographics ---
        m.DateOfBirth = FmtDate(row.Get("Date of Birth"), "Date of birth", flags, DateRole.PastOnly);
        m.PlaceOfBirth = row.Get("Place of Birth");
        var g = row.Get("Gender").Trim().ToUpperInvariant();
        m.Gender = CrewMappingTables.Gender.TryGetValue(g, out var gg) ? gg : "";
        if (g.Length > 0 && m.Gender.Length == 0)
            flags.Add(new CrewReviewFlag(CrewFlagSeverity.Info, "Gender", $"Gender code '{g}' not recognised."));
        m.Height = row.Get("Height");
        m.EyesColor = row.Get("Eyes Colour");
        m.HairColor = row.Get("Hair Colour");

        // --- employment ---
        m.UserType = "Crew";
        m.SignedOnOff = "On";              // COMPAS arrival list = currently onboard
        m.Company = row.Get("Source");
        m.Vessel = row.Get("Last Vessel");

        var raw = row.Get("Rank").Trim().ToUpperInvariant();
        m.RankCode = raw;
        if (CrewMappingTables.Rank.TryGetValue(raw, out var rm))
        {
            m.Rank = rm.Dnv;
            if (rm.Approximate)
                flags.Add(new CrewReviewFlag(CrewFlagSeverity.Warning, "Rank", $"Rank code '{raw}' → '{rm.Dnv}' (approximate — verify)."));
        }
        else if (raw.Length > 0)
        {
            m.Rank = "Other";
            flags.Add(new CrewReviewFlag(CrewFlagSeverity.Warning, "Rank", $"Unknown rank code '{raw}' → 'Other' (set manually)."));
        }
        else
        {
            m.Rank = "Other";
            flags.Add(new CrewReviewFlag(CrewFlagSeverity.Error, "Rank", "No rank in COMPAS → 'Other' (mandatory, set manually)."));
        }

        // --- sign-on (mandatory) ---
        m.SignOnDate = FmtDate(row.Get("Joining Date"), "Sign-on date", flags, DateRole.Any);
        m.SignOnPortRaw = row.Get("Joining Port");
        m.SignOnPort = MapPort(m.SignOnPortRaw, "Sign-on port", flags);

        // --- sign-off (drives contract-expiry tracking) ---
        m.SignOffDate = FmtDate(row.Get("Sign Off Date"), "Sign-off date", flags, DateRole.FutureLikely);
        m.SignOffPortRaw = row.Get("SignOff Port");
        if (!string.IsNullOrWhiteSpace(m.SignOffPortRaw))
            m.SignOffPort = MapPort(m.SignOffPortRaw, "Sign-off port", flags);
        if (string.IsNullOrWhiteSpace(m.SignOffDate))
            flags.Add(new CrewReviewFlag(CrewFlagSeverity.Info, "Sign-off date",
                "No sign-off date in COMPAS — contract expiry can't be tracked until it's filled in."));

        // --- passport ---
        m.PassportNumber = row.Get("Passport Number");
        m.PassportExpiry = FmtDate(row.Get("Passport Expiry Date"), "Passport expiry", flags, DateRole.FutureLikely);
        m.PassportIssued = FmtDate(row.Get("Passport Issued Date"), "Passport issued", flags, DateRole.PastOnly);

        // --- seaman's book ---
        m.SeamansBookNumber = row.Get("Seaman Book Number");
        m.SeamansBookExpiry = FmtDate(row.Get("Seaman Book Expiry Date"), "Seaman's book expiry", flags, DateRole.FutureLikely);
        m.SeamansBookIssued = FmtDate(row.Get("Seaman Book Issue Date"), "Seaman's book issued", flags, DateRole.PastOnly);

        // --- certificate of competency ---
        if (row.Has("Licence Number"))
        {
            m.CocNumber = row.Get("Licence Number");
            m.CocExpiry = FmtDate(row.Get("Licence Expiry Date"), "CoC expiry", flags, DateRole.FutureLikely);
            m.CocIssue = FmtDate(row.Get("Licence Issue Date"), "CoC issue", flags, DateRole.PastOnly);
        }
        m.HealthCertExpiry = FmtDate(row.Get("Medical Examination Expiry"), "Health cert. expiry", flags, DateRole.FutureLikely);

        // --- next of kin ---
        var (nokFirst, nokLast) = SplitName(row.Get("Next of Kin - Name"));
        m.NokFirstName = nokFirst;
        m.NokLastName = nokLast;
        var grade = CrewText.Norm(row.Get("Next of Kin - Grade"));
        if (grade.Length > 0)
        {
            m.NokRelationship = CrewMappingTables.Relationship.TryGetValue(grade, out var rel) ? rel : "Other";
            if (m.NokRelationship == "Other" && grade != "not specified")
                flags.Add(new CrewReviewFlag(CrewFlagSeverity.Info, "Next of kin", $"Relationship '{grade}' → 'Other'."));
        }

        CheckMandatory(m);
        return m;
    }

    private static void CheckMandatory(CrewMember m)
    {
        void Req(string val, string label)
        {
            if (string.IsNullOrWhiteSpace(val))
                m.Flags.Add(new CrewReviewFlag(CrewFlagSeverity.Error, label,
                    $"Mandatory field '{label}' is empty — missing in COMPAS, fill manually."));
        }
        Req(m.FirstName, "First name");
        Req(m.LastName, "Last name");
        Req(m.EmployeeId, "Employee ID");
        Req(m.Rank, "Rank");
        Req(m.SignOnDate, "Sign-on date");
        Req(m.SignOnPort, "Sign-on port");
    }

    /// <summary>
    /// COMPAS has no populated middle-name column; the middle name is the portion of the 'Name'
    /// field that follows the 'First name'. '-' placeholders → empty.
    /// </summary>
    private static string DeriveMiddle(CompasRow row)
    {
        var explicitMid = row.Get("Original middle name").Trim();
        if (explicitMid.Length > 0 && explicitMid != "-") return explicitMid;

        var name = WhitespaceRegex().Replace(row.Get("Name").Trim(), " ");
        var first = WhitespaceRegex().Replace(row.Get("First name").Trim(), " ");
        if (name.Length > 0 && first.Length > 0 &&
            name.StartsWith(first, StringComparison.OrdinalIgnoreCase))
        {
            return name.Substring(first.Length).Trim(' ', '-').Trim();
        }
        return "";
    }

    private static (string first, string last) SplitName(string full)
    {
        if (string.IsNullOrWhiteSpace(full)) return ("", "");
        var parts = WhitespaceRegex().Replace(full.Trim(), " ").Split(' ');
        if (parts.Length == 1) return (parts[0], "");
        return (string.Join(" ", parts[..^1]), parts[^1]);
    }

    private static string MapPort(string value, string field, List<CrewReviewFlag> flags)
    {
        if (string.IsNullOrWhiteSpace(value)) return "";
        var key = CrewText.Norm(value);
        if (CrewMappingTables.Port.TryGetValue(key, out var pm))
        {
            if (pm.Verify)
                flags.Add(new CrewReviewFlag(CrewFlagSeverity.Warning, field,
                    $"Port '{value}' → {pm.Unlocode} (UN/LOCODE best-guess — verify)."));
            return pm.Unlocode;
        }
        flags.Add(new CrewReviewFlag(CrewFlagSeverity.Warning, field,
            $"Port '{value}' has no UN/LOCODE mapping — left as name, set manually."));
        return value;
    }

    /// <summary>Read one date cell using the convention learned from the whole file.
    ///
    /// This previously accepted year-first values only, so a real "15/07/2026" fell through and was stored
    /// as raw text -- which CrewMember.ParseDate then re-read with InvariantCulture, i.e. MONTH-first. An
    /// ordinary day-first date therefore came back a month out, silently.</summary>
    private string FmtDate(string value, string field, List<CrewReviewFlag> flags, DateRole role = DateRole.Any)
    {
        var r = _dates.Resolve(value, role);
        if (r.Value == null)
        {
            if (!string.IsNullOrEmpty(r.Raw))
            {
                UnreadableDates++;
                // Error, not Info: an unread date silently disables the expiry tracking that depends on it.
                flags.Add(new CrewReviewFlag(CrewFlagSeverity.Error, field,
                    $"{field}: {r.Note ?? $"could not read '{r.Raw}'"} — left as-is, set it by hand."));
            }
            return r.Raw;
        }

        if (r.DependedOnOrder)
        {
            OrderDependentDates++;
            flags.Add(new CrewReviewFlag(CrewFlagSeverity.Warning, field, $"{field}: {r.Note}"));
        }
        return r.ToStorage();
    }

    private static string FirstNonEmpty(params string[] vals)
        => vals.FirstOrDefault(v => !string.IsNullOrWhiteSpace(v)) ?? "";

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRegex();

}
