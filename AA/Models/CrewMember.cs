using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Linq;
using System.Text.Json.Serialization;

namespace AA.Models;

/// <summary>Severity of a COMPAS→crew-card conversion review note.</summary>
public enum CrewFlagSeverity { Info, Warning, Error }

/// <summary>A note raised while converting a COMPAS record into a crew card
/// (a guessed value, or a missing mandatory field). Nothing is silently invented.</summary>
public sealed class CrewReviewFlag
{
    public CrewFlagSeverity Severity { get; set; }
    public string Field { get; set; } = "";
    public string Message { get; set; } = "";

    public CrewReviewFlag() { }
    public CrewReviewFlag(CrewFlagSeverity severity, string field, string message)
    {
        Severity = severity; Field = field; Message = message;
    }
}

/// <summary>How close a crew member's contract (sign-off date) is.</summary>
public enum ContractStatus { Unknown, Ok, DueSoon, Critical, Expired }

/// <summary>
/// One crew member imported from a COMPAS report, holding the translated (DNV-style) data plus a
/// little COMPAS provenance (raw rank code, raw ports, raw nationality) so the info card can show
/// how each value was translated. The <see cref="SignOffDate"/> drives contract-expiry tracking.
/// </summary>
public sealed class CrewMember
{
    /// <summary>Stable per-member id (persisted). Used so a crew member's checklist items can be
    /// navigated to from the due-dates window / Calendar, and preserved across COMPAS re-import.</summary>
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>This crew member's personal checklist — reuses <see cref="ChecklistStep"/> so each item
    /// can carry a deadline, done state, notes and files, and appears in the due-dates window and Calendar.</summary>
    public ObservableCollection<ChecklistStep> Checklist { get; set; } = new();

    /// <summary>This crew member's schedule/timeline — dated entries (tasks, procedures, equipment or
    /// free notes). Built in the crew editor's Schedule tab; saveable/exportable as a reusable template.</summary>
    public ObservableCollection<ScheduleEntry> Schedule { get; set; } = new();
    /// <summary>Optional vessel this schedule is linked to.</summary>
    public Guid? ScheduleVesselId { get; set; }

    // --- Identity ---
    public string EmployeeId { get; set; } = "";
    public string FirstName { get; set; } = "";
    public string MiddleName { get; set; } = "";
    public string LastName { get; set; } = "";
    public string Nationality { get; set; } = "";
    public string DateOfBirth { get; set; } = "";
    public string PlaceOfBirth { get; set; } = "";
    public string Gender { get; set; } = "";
    public string Height { get; set; } = "";
    public string EyesColor { get; set; } = "";
    public string HairColor { get; set; } = "";

    // --- Employment & sign-on / sign-off ---
    public string UserType { get; set; } = "Crew";
    public string Rank { get; set; } = "";
    public string RankCode { get; set; } = "";        // raw COMPAS code, e.g. "MAST"
    public string SignedOnOff { get; set; } = "On";
    public string Company { get; set; } = "";
    public string Vessel { get; set; } = "";          // COMPAS "Last Vessel"
    public string SignOnDate { get; set; } = "";
    public string SignOnPort { get; set; } = "";      // UN/LOCODE
    public string SignOnPortRaw { get; set; } = "";   // raw COMPAS port name
    /// <summary>Planned end-of-contract / sign-off date (COMPAS "Sign Off Date"). Drives expiry tracking.</summary>
    public string SignOffDate { get; set; } = "";
    public string SignOffPort { get; set; } = "";     // UN/LOCODE
    public string SignOffPortRaw { get; set; } = "";  // raw COMPAS port name

    // --- Travel documents ---
    public string PassportNumber { get; set; } = "";
    public string PassportExpiry { get; set; } = "";
    public string PassportIssued { get; set; } = "";
    public string SeamansBookNumber { get; set; } = "";
    public string SeamansBookExpiry { get; set; } = "";
    public string SeamansBookIssued { get; set; } = "";

    // --- Certificates & medical ---
    public string CocNumber { get; set; } = "";
    public string CocExpiry { get; set; } = "";
    public string CocIssue { get; set; } = "";
    public string HealthCertExpiry { get; set; } = "";

    // --- Next of kin ---
    public string NokFirstName { get; set; } = "";
    public string NokLastName { get; set; } = "";
    public string NokRelationship { get; set; } = "";

    // --- Meta ---
    public string RawNationality { get; set; } = "";
    public List<CrewReviewFlag> Flags { get; set; } = new();
    public string ImportedAt { get; set; } = "";
    public string SourceFile { get; set; } = "";

    [JsonIgnore]
    public string FullName => string.Join(" ",
        new[] { FirstName, MiddleName, LastName }.Where(s => !string.IsNullOrWhiteSpace(s)));

    /// <summary>Stable identity key used for de-duplication on re-import (employee id, else name).</summary>
    [JsonIgnore]
    public string Key => !string.IsNullOrWhiteSpace(EmployeeId)
        ? EmployeeId
        : $"{FirstName}|{LastName}".Trim('|');

    [JsonIgnore] public bool HasFlags => Flags.Count > 0;
    [JsonIgnore] public bool HasErrors => Flags.Any(f => f.Severity == CrewFlagSeverity.Error);

    /// <summary>The parsed sign-off date (contract end), or null when absent/unparseable.</summary>
    [JsonIgnore] public DateTime? SignOffDateValue => ParseDate(SignOffDate);

    /// <summary>Whole days from <paramref name="today"/> until the contract sign-off date.
    /// Negative = already past. Null when there is no valid sign-off date.</summary>
    public int? DaysUntilSignOff(DateTime today)
    {
        var d = SignOffDateValue;
        return d == null ? null : (int)(d.Value.Date - today.Date).TotalDays;
    }

    /// <summary>Bucketed contract status relative to <paramref name="today"/>.
    /// Critical ≤ <paramref name="criticalDays"/>, DueSoon ≤ <paramref name="soonDays"/>.</summary>
    public ContractStatus ContractStatusOn(DateTime today, int criticalDays = 30, int soonDays = 60)
    {
        var days = DaysUntilSignOff(today);
        if (days == null) return ContractStatus.Unknown;
        if (days < 0) return ContractStatus.Expired;
        if (days <= criticalDays) return ContractStatus.Critical;
        if (days <= soonDays) return ContractStatus.DueSoon;
        return ContractStatus.Ok;
    }

    /// <summary>Tolerant date parser for the yyyy-MM-dd / yyyy/MM/dd values COMPAS produces.</summary>
    public static DateTime? ParseDate(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        s = s.Trim();
        foreach (var fmt in new[] { "yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd" })
            if (DateTime.TryParseExact(s, fmt, CultureInfo.InvariantCulture, DateTimeStyles.None, out var d))
                return d;
        if (DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, out var d2)) return d2;
        return null;
    }
}
