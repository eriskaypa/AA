// Spec: 09 §3.1 (`ParseDate` — the app-wide reader), §8 Q4 ("unread ambiguous dates are later read month-first"),
//       §4.2 ("never re-interpret stored dates on load"); DECISIONS 09 Q4 (fix: never mis-read). The stored text is
//       never changed; only how the crew views interpret it.
import Foundation

/// How the crew subsystem reads a stored crew date string.
///
/// Identical to `CrewMember.parseDate` (F2's `NetDateParser`) except for one shape: a numeric `a/b/y` whose two
/// components are both 1…12 and different (e.g. `03/04/2026`). The import leaves such a value unread with an Error
/// note because the file did not say which way round it is; the general parser would silently read it month-first
/// (4 March), so the expiry, sort, table and editor would all show a date nobody confirmed. On the Mac it stays
/// unread (no expiry tracking, shown verbatim) until someone sets it — DECISIONS 09 Q4.
public enum CrewStoredDate {
    public static func parse(_ s: String?) -> NetDateTime? {
        guard let s, !NetText.isBlank(s) else { return nil }
        if isAmbiguous(s) { return nil }
        return CrewMember.parseDate(s)
    }

    /// The calendar day, or nil.
    public static func civil(_ s: String?) -> CivilDate? { parse(s)?.civilDate }

    /// True for a numeric day/month value that reads differently day-first and month-first.
    public static func isAmbiguous(_ s: String) -> Bool {
        let cleaned = CrewDateResolver.clean(s)
        let stripped = CrewDateResolver.stripTime(cleaned)
        guard let m = CrewDateResolver.numeric(stripped) else { return false }
        return (1...12).contains(m.a) && (1...12).contains(m.b) && m.a != m.b
    }

    /// Whole calendar days from `today` to the member's sign-off date (negative = past), nil when unknown.
    @MainActor public static func daysUntilSignOff(_ m: CrewMember, today: CivilDate) -> Int? {
        guard let d = civil(m.signOffDate) else { return nil }
        return today.days(to: d)
    }

    /// CREW-052 contract status over the strict reading.
    @MainActor public static func contractStatus(_ m: CrewMember, today: CivilDate,
                                                 criticalDays: Int = CrewExpiry.criticalDays,
                                                 soonDays: Int = CrewExpiry.warnDays) -> ContractStatus {
        guard let days = daysUntilSignOff(m, today: today) else { return .unknown }
        if days < 0 { return .expired }
        if days <= criticalDays { return .critical }
        if days <= soonDays { return .dueSoon }
        return .ok
    }
}
