// Spec: 14 TOOLS-061…071, §3.4.1 ComputeDiff, §3.4.2 ComputeAdd, §6.8 (pure civil-date arithmetic, never
//       `Calendar.current`; weekday names and N0 grouping from the locale), vectors 7.4; DECISIONS 14 Q-16 (out-of-range
//       results show "Result is out of range." instead of crashing; Int64 arithmetic, no `n * 7` wrap).
//       Source: AA/Views/DateCalculatorWindow.xaml.cs.
import Foundation

public enum ToolDateOperation: String, CaseIterable, Sendable { case add = "Add", subtract = "Subtract" }

public enum ToolDateUnit: String, CaseIterable, Sendable { case days = "Days", weeks = "Weeks", months = "Months", years = "Years" }

public enum ToolDateCalc {
    public static let pickBothDates = "Pick both dates."
    public static let pickADate = "Pick a date."
    public static let enterWholeNumber = "Enter a whole number."
    /// DECISIONS 14 Q-16 (Mac deviation for the Windows crash).
    public static let outOfRange = "Result is out of range."

    /// .NET `N0` with the given culture: digit grouping, no decimals, the culture's minus sign.
    public static func n0(_ n: Int64, locale: Locale) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// Plain `int.ToString()` with the culture's negative sign.
    static func plain(_ n: Int, locale: Locale) -> String {
        guard n < 0 else { return String(n) }
        let f = NumberFormatter()
        f.locale = locale
        return f.minusSign + String(-n)
    }

    /// The culture's full weekday name (`dddd`), Gregorian.
    public static func weekdayName(_ d: CivilDate, locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        f.calendar = cal
        let symbols = f.weekdaySymbols ?? ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return symbols[d.weekday % symbols.count]
    }

    private static func plural(_ n: Int, _ word: String, locale: Locale) -> String {
        "\(plain(n, locale: locale)) \(word)\(abs(n) == 1 ? "" : "s")"
    }

    /// §3.4.1 — the three-line difference text, or `Pick both dates.` when a date is missing.
    public static func difference(from: CivilDate?, to: CivilDate?, inclusive: Bool, locale: Locale = .current) -> String {
        guard let a = from, let b = to else { return pickBothDates }
        let totalDays = a.days(to: b)
        let shown = totalDays + (inclusive ? (totalDays >= 0 ? 1 : -1) : 0)
        let absDays = abs(totalDays)
        let weeks = absDays / 7, remDays = absDays % 7
        let (s, e) = a <= b ? (a, b) : (b, a)
        var years = e.year - s.year
        var months = e.month - s.month
        var days = e.day - s.day
        if days < 0 {
            months -= 1
            let pm = e.addingMonths(-1)
            days += CivilDate.daysInMonth(year: pm.year, month: pm.month)
        }
        if months < 0 { years -= 1; months += 12 }
        let dir = totalDays < 0 ? "  (To is before From)" : ""
        return "Total: \(n0(Int64(shown), locale: locale)) day\(abs(shown) == 1 ? "" : "s")\(inclusive ? " (inclusive)" : "")\(dir)\n"
            + "\u{2248} \(n0(Int64(weeks), locale: locale)) week\(weeks == 1 ? "" : "s"), \(remDays) day\(remDays == 1 ? "" : "s")\n"
            + "= \(plural(years, "year", locale: locale)), \(plural(months, "month", locale: locale)), \(plural(days, "day", locale: locale))"
    }

    /// The result date of §3.4.2, or nil when it falls outside 0001-01-01…9999-12-31 (Q-16).
    public static func shifted(_ d: CivilDate, by n: Int64, unit: ToolDateUnit) -> CivilDate? {
        let minDays = -719_162, maxDays = 2_932_896                // 0001-01-01 … 9999-12-31
        switch unit {
        case .days, .weeks:
            let delta = unit == .weeks ? n * 7 : n
            let target = Int64(d.daysFromCivil) + delta
            guard target >= Int64(minDays), target <= Int64(maxDays) else { return nil }
            return CivilDate(daysFromCivil: Int(target))
        case .months:
            let total = Int64(d.year) * 12 + Int64(d.month - 1) + n
            guard total >= 12, total <= 9999 * 12 + 11 else { return nil }
            let y = Int(total / 12), m = Int(total % 12) + 1
            return CivilDate(year: y, month: m, day: min(d.day, CivilDate.daysInMonth(year: y, month: m)))
        case .years:
            let y = Int64(d.year) + n
            guard y >= 1, y <= 9999 else { return nil }
            return CivilDate(year: Int(y), month: d.month, day: min(d.day, CivilDate.daysInMonth(year: Int(y), month: d.month)))
        }
    }

    /// §3.4.2 — the two-line add/subtract text (`Pick a date.`, `Enter a whole number.` or `Result is out of range.`).
    public static func add(date: CivilDate?, operation: ToolDateOperation, amountText: String, unit: ToolDateUnit,
                           locale: Locale = .current) -> String {
        guard let d = date else { return pickADate }
        guard let amount = ToolNetNumber.parseInt32(amountText) else { return enterWholeNumber }
        let n = operation == .subtract ? -Int64(amount) : Int64(amount)
        guard let r = shifted(d, by: n, unit: unit) else { return outOfRange }
        let delta = d.days(to: r)
        return "Result: \(r.iso) (\(weekdayName(r, locale: locale)))\n"
            + "(\(delta >= 0 ? "+" : "")\(n0(Int64(delta), locale: locale)) days from \(d.iso))"
    }
}
