// Spec: 01 §3.19, §3.23, 09 §3.1 (civil-day arithmetic, never TimeInterval division), ARCHITECTURE.md §3.5
import Foundation

/// A proleptic-Gregorian calendar date without a time or time zone (year 1…9999, like .NET `DateTime`).
public struct CivilDate: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int, month: Int, day: Int

    /// Validating initializer (year 1…9999).
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              day >= 1, day <= CivilDate.daysInMonth(year: year, month: month) else { return nil }
        self.year = year; self.month = month; self.day = day
    }

    private init(unchecked year: Int, _ month: Int, _ day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    /// Exactly `yyyy-MM-dd` (4-digit year, 2-digit month and day, `-` separators).
    public init?(iso text: String) {
        let u = Array(text.utf8)
        guard u.count == 10, u[4] == 0x2D, u[7] == 0x2D,
              let y = CivilDate.digits(u, 0, 4), let m = CivilDate.digits(u, 5, 2), let d = CivilDate.digits(u, 8, 2)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    static func digits(_ u: [UInt8], _ start: Int, _ count: Int) -> Int? {
        var v = 0
        for i in start..<(start + count) {
            let c = u[i]
            guard c >= 0x30, c <= 0x39 else { return nil }
            v = v * 10 + Int(c - 0x30)
        }
        return v
    }

    /// `yyyy-MM-dd`.
    public var iso: String {
        CivilDate.pad(year, 4) + "-" + CivilDate.pad(month, 2) + "-" + CivilDate.pad(day, 2)
    }

    public var description: String { iso }

    static func pad(_ v: Int, _ width: Int) -> String {
        let s = String(v)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    public static func isLeapYear(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    /// Days since 1970-01-01 (negative before). Howard Hinnant's `days_from_civil`.
    public var daysFromCivil: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Inverse of `daysFromCivil` (`civil_from_days`). Results outside year 1…9999 are clamped to that range.
    public init(daysFromCivil z0: Int) {
        let minDays = -719_162, maxDays = 2_932_896           // 0001-01-01 … 9999-12-31
        let z = min(max(z0, minDays), maxDays) + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.init(unchecked: y, m, d)
    }

    public func addingDays(_ n: Int) -> CivilDate { CivilDate(daysFromCivil: daysFromCivil + n) }

    /// .NET `AddMonths`: the day is clamped to the last day of the target month (Jan 31 + 1 → Feb 28/29).
    public func addingMonths(_ n: Int) -> CivilDate {
        let total = (year * 12 + (month - 1)) + n
        var y = total / 12, m = total % 12 + 1
        if total < 0 { y = (total - 11) / 12; m = total - y * 12 + 1 }
        y = min(max(y, 1), 9999)
        return CivilDate(unchecked: y, m, min(day, CivilDate.daysInMonth(year: y, month: m)))
    }

    /// .NET `AddYears`: Feb 29 → Feb 28 in a non-leap target year.
    public func addingYears(_ n: Int) -> CivilDate {
        let y = min(max(year + n, 1), 9999)
        return CivilDate(unchecked: y, month, min(day, CivilDate.daysInMonth(year: y, month: month)))
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(to other: CivilDate) -> Int { other.daysFromCivil - daysFromCivil }

    /// .NET `DayOfWeek`: 0 = Sunday … 6 = Saturday.
    public var weekday: Int {
        let r = (daysFromCivil + 4) % 7                      // 1970-01-01 was a Thursday
        return r < 0 ? r + 7 : r
    }

    public static func < (a: CivilDate, b: CivilDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}
