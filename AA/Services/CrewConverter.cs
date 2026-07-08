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

    public CrewConverter(string sourceFile)
    {
        _sourceFile = sourceFile;
        _importedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm");
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
        m.DateOfBirth = FmtDate(row.Get("Date of Birth"), "Date of birth", flags);
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
        m.SignOnDate = FmtDate(row.Get("Joining Date"), "Sign-on date", flags);
        m.SignOnPortRaw = row.Get("Joining Port");
        m.SignOnPort = MapPort(m.SignOnPortRaw, "Sign-on port", flags);

        // --- sign-off (drives contract-expiry tracking) ---
        m.SignOffDate = FmtDate(row.Get("Sign Off Date"), "Sign-off date", flags);
        m.SignOffPortRaw = row.Get("SignOff Port");
        if (!string.IsNullOrWhiteSpace(m.SignOffPortRaw))
            m.SignOffPort = MapPort(m.SignOffPortRaw, "Sign-off port", flags);
        if (string.IsNullOrWhiteSpace(m.SignOffDate))
            flags.Add(new CrewReviewFlag(CrewFlagSeverity.Info, "Sign-off date",
                "No sign-off date in COMPAS — contract expiry can't be tracked until it's filled in."));

        // --- passport ---
        m.PassportNumber = row.Get("Passport Number");
        m.PassportExpiry = FmtDate(row.Get("Passport Expiry Date"), "Passport expiry", flags);
        m.PassportIssued = FmtDate(row.Get("Passport Issued Date"), "Passport issued", flags);

        // --- seaman's book ---
        m.SeamansBookNumber = row.Get("Seaman Book Number");
        m.SeamansBookExpiry = FmtDate(row.Get("Seaman Book Expiry Date"), "Seaman's book expiry", flags);
        m.SeamansBookIssued = FmtDate(row.Get("Seaman Book Issue Date"), "Seaman's book issued", flags);

        // --- certificate of competency ---
        if (row.Has("Licence Number"))
        {
            m.CocNumber = row.Get("Licence Number");
            m.CocExpiry = FmtDate(row.Get("Licence Expiry Date"), "CoC expiry", flags);
            m.CocIssue = FmtDate(row.Get("Licence Issue Date"), "CoC issue", flags);
        }
        m.HealthCertExpiry = FmtDate(row.Get("Medical Examination Expiry"), "Health cert. expiry", flags);

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

    private static string FmtDate(string value, string field, List<CrewReviewFlag> flags)
    {
        if (string.IsNullOrWhiteSpace(value)) return "";
        var s = value.Trim();
        var match = DateRegex().Match(s);
        if (match.Success)
        {
            int y = int.Parse(match.Groups[1].Value);
            int mo = int.Parse(match.Groups[2].Value);
            int d = int.Parse(match.Groups[3].Value);
            return $"{y:D4}-{mo:D2}-{d:D2}";
        }
        flags.Add(new CrewReviewFlag(CrewFlagSeverity.Info, field, $"Could not parse {field.ToLowerInvariant()} '{s}' — left as-is."));
        return s;
    }

    private static string FirstNonEmpty(params string[] vals)
        => vals.FirstOrDefault(v => !string.IsNullOrWhiteSpace(v)) ?? "";

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRegex();

    [GeneratedRegex(@"^(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})$")]
    private static partial Regex DateRegex();
}
