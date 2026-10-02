// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 09 §6.3 CrewMember.ParseDate (.NET DateTime.TryParse emulation, invariant + en-US reference culture), 09 §7.1,
// 10 §X.8.1 column B+. Compiling stub created by F1; F2 replaces this file in place. ARCH §11 requires the stub to
// accept exactly the three exact formats until F2 merges (the F1 model helpers forward here).
import Foundation

/// The app-wide tolerant date parser shared by the F1 models (`CrewMember.parseDate`, `ShipJob.dueDateValue`, …),
/// F2's XLSX renderer B+, W-CREW and W-VESSEL. `today` resolves time-only and year-less input.
public enum NetDateParser {
    /// Stub: `yyyy-MM-dd`, `yyyy/MM/dd` and `yyyy.MM.dd` (4-digit year, 2-digit month/day) after trimming, as an
    /// Unspecified calendar date; nil for blank or anything else. F2 adds the `DateTime.TryParse` fallback.
    public static func parse(_ text: String?, zone: TimeZone = .current, today: CivilDate? = nil) -> NetDateTime? {
        // PLACEHOLDER(F2)
        guard let text, !NetText.isBlank(text) else { return nil }
        let t = Array(NetText.trim(text).utf8)
        guard t.count == 10, t[4] == t[7], t[4] == 0x2D || t[4] == 0x2F || t[4] == 0x2E,
              let y = CivilDate.digits(t, 0, 4), let m = CivilDate.digits(t, 5, 2), let d = CivilDate.digits(t, 8, 2),
              let date = CivilDate(year: y, month: m, day: d) else { return nil }
        return NetDateTime.calendarDate(date)
    }
}
