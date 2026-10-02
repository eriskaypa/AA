// Spec: 09 §3.1, §6.3 (`CrewMember.ParseDate` = exact `yyyy-MM-dd` / `yyyy/MM/dd` / `yyyy.MM.dd`, then a deterministic
//       emulation of .NET `DateTime.TryParse(s, InvariantCulture, None)`), 09 §7.1; 01 §3.23, §7.10; 10 VESSEL-327
//       note + §X.10 Q20/Q21 (time-only input → today at that time; hour ≥ 24 rejected); 10 §X.8.1 column B+;
//       ARCHITECTURE.md §6.5 (shared by the F1 models, the XLSX renderer B+, W-CREW and W-VESSEL).
import Foundation

/// The app-wide tolerant date parser. Month-first for ambiguous numeric dates (`03/04/2026` = 4 March), two-digit
/// years pivot at 2049, English month and day names, ISO date-times, times with AM/PM, `Z` / `GMT` / `±hh:mm`
/// (converted to the local wall clock, kind `.local`, exactly like .NET), `M/d` and `d MMM` without a year (the year
/// of `today`) and time-only input (`today` at that time). Anything else → nil.
public enum NetDateParser {
    /// `today` resolves time-only and year-less input (default: the current date in `zone`).
    public static func parse(_ text: String?, zone: TimeZone = .current, today: CivilDate? = nil) -> NetDateTime? {
        guard let text, !NetText.isBlank(text) else { return nil }
        let s = NetText.trim(text)
        if let exact = exactDate(s) { return exact }
        var p = SvcDateScan(s)
        return p.parse(zone: zone, today: today ?? NetDateTime(date: Date(), kind: .local, zone: zone).civilDate)
    }

    /// The three exact invariant formats: 4-digit year, 2-digit month and day, one separator used twice.
    static func exactDate(_ s: String) -> NetDateTime? {
        let t = Array(s.utf8)
        guard t.count == 10, t[4] == t[7], t[4] == 0x2D || t[4] == 0x2F || t[4] == 0x2E,
              let y = CivilDate.digits(t, 0, 4), let m = CivilDate.digits(t, 5, 2), let d = CivilDate.digits(t, 8, 2),
              let date = CivilDate(year: y, month: m, day: d) else { return nil }
        return NetDateTime.calendarDate(date)
    }
}

/// The general-parser emulation (one instance per call).
struct SvcDateScan {
    private enum Token: Equatable { case number(String), word(String), symbol(Character), space }
    private enum Element { case number, month }

    private var tokens: [Token] = []
    private var i = 0

    private var numbers: [String] = []
    private var elements: [Element] = []
    private var month: Int?
    private var weekday: Int?
    private var hour: Int?, minute = 0, second = 0, fractionTicks: Int64 = 0
    private var meridiem: Character?            // "A" / "P"
    private var utc = false
    private var offsetSeconds: Int?

    private static let months = ["january", "february", "march", "april", "may", "june", "july", "august",
                                 "september", "october", "november", "december"]
    private static let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    init(_ s: String) {
        var cur = ""
        var kind = 0                                    // 0 none, 1 digits, 2 letters
        func flush() {
            if kind == 1 { tokens.append(.number(cur)) } else if kind == 2 { tokens.append(.word(cur)) }
            cur = ""; kind = 0
        }
        for ch in s {
            if ch.isASCII && ch.isNumber {
                if kind != 1 { flush(); kind = 1 }
                cur.append(ch)
            } else if ch.isLetter {
                if kind != 2 { flush(); kind = 2 }
                cur.append(ch)
            } else if ch.isWhitespace {
                flush()
                if tokens.last != .space { tokens.append(.space) }
            } else {
                flush()
                tokens.append(.symbol(ch))
            }
        }
        flush()
    }

    private func peek(_ k: Int = 0) -> Token? { i + k < tokens.count ? tokens[i + k] : nil }

    /// The next token that is not a space, and its distance.
    private func peekSkippingSpace(from k: Int) -> (Token, Int)? {
        var j = k
        while let t = peek(j) {
            if t != .space { return (t, j) }
            j += 1
        }
        return nil
    }

    mutating func parse(zone: TimeZone, today: CivilDate) -> NetDateTime? {
        var afterTime = false                 // only spaces since the time (or its AM/PM): an offset may follow
        while let t = peek() {
            let wasAfterTime = afterTime
            if t != .space { afterTime = false }
            switch t {
            case .space:
                i += 1
            case .number(let n):
                if case .symbol(":") = peek(1) {
                    guard hour == nil, parseTime() else { return nil }
                    afterTime = true
                } else if case let (.word(w), k)? = peekSkippingSpace(from: 1), let m = Self.meridiem(w), hour == nil,
                          n.count <= 2 {
                    hour = Int(n); meridiem = m; i += k + 1        // "10 PM"
                    afterTime = true
                } else {
                    numbers.append(n); elements.append(.number); i += 1
                }
            case .word(let w):
                let lw = w.lowercased()
                if lw == "t", hour == nil, case .number? = peek(1) { i += 1; continue }        // ISO 'T'
                if let m = Self.monthIndex(lw) {
                    guard month == nil else { return nil }
                    month = m; elements.append(.month); i += 1
                } else if let d = Self.dayIndex(lw) {
                    guard weekday == nil else { return nil }
                    weekday = d; i += 1
                } else if let m = Self.meridiem(w), hour != nil, meridiem == nil, wasAfterTime {
                    meridiem = m; i += 1
                    afterTime = true
                } else if lw == "z" || lw == "gmt" || lw == "utc" {
                    guard wasAfterTime, !utc, offsetSeconds == nil else { return nil }
                    utc = true; i += 1
                    if case .symbol(let sign)? = peek(), sign == "+" || sign == "-" {         // "GMT+02:00"
                        utc = false
                        guard parseOffset() else { return nil }
                    }
                } else {
                    return nil
                }
            case .symbol(let c):
                if (c == "+" || c == "-"), wasAfterTime, offsetSeconds == nil, !utc, case .number? = peek(1) {
                    guard parseOffset() else { return nil }
                } else if c == "/" || c == "-" || c == "." || c == "," {
                    i += 1
                } else {
                    return nil
                }
            }
        }
        return assemble(zone: zone, today: today)
    }

    /// `H:mm[:ss[.fffffff]]` at the cursor (a number followed by `:`).
    private mutating func parseTime() -> Bool {
        guard case .number(let h)? = peek(), h.count <= 2, case .number(let m)? = peek(2), m.count <= 2 else { return false }
        hour = Int(h); minute = Int(m) ?? 0
        i += 3
        if case .symbol(":")? = peek(), case .number(let sec)? = peek(1), sec.count <= 2 {
            second = Int(sec) ?? 0
            i += 2
            if case .symbol(".")? = peek(), case .number(let f)? = peek(1) {
                var digits = String(f.prefix(7))
                while digits.count < 7 { digits += "0" }
                fractionTicks = Int64(digits) ?? 0
                i += 2
            }
        }
        return true
    }

    /// `±hh[:mm]` / `±hhmm` at the cursor.
    private mutating func parseOffset() -> Bool {
        guard case .symbol(let sign)? = peek(), case .number(let n)? = peek(1) else { return false }
        i += 2
        var h = 0, m = 0
        if n.count <= 2 {
            h = Int(n) ?? 0
            if case .symbol(":")? = peek(), case .number(let mm)? = peek(1), mm.count == 2 {
                m = Int(mm) ?? 0
                i += 2
            }
        } else if n.count == 4 {
            h = Int(n.prefix(2)) ?? 0; m = Int(n.suffix(2)) ?? 0
        } else {
            return false
        }
        guard h <= 14, m < 60 else { return false }
        offsetSeconds = (sign == "-" ? -1 : 1) * (h * 3600 + m * 60)
        return true
    }

    private func assemble(zone: TimeZone, today: CivilDate) -> NetDateTime? {
        var y = today.year, mo = 0, d = 0
        func year(_ s: String) -> Int? {
            guard let v = Int(s) else { return nil }
            if s.count <= 2 { return v <= 49 ? 2000 + v : 1900 + v }   // TwoDigitYearMax 2049
            return v
        }
        if let m = month {
            mo = m
            switch numbers.count {
            case 1:
                if numbers[0].count >= 3 { guard let yy = year(numbers[0]) else { return nil }; y = yy; d = 1 }
                else { d = Int(numbers[0]) ?? 0 }
            case 2:
                if numbers[0].count >= 3 {
                    guard let yy = year(numbers[0]) else { return nil }; y = yy; d = Int(numbers[1]) ?? 0
                } else {
                    guard let yy = year(numbers[1]) else { return nil }; y = yy; d = Int(numbers[0]) ?? 0
                }
            default:
                return nil
            }
        } else {
            switch numbers.count {
            case 0:
                guard hour != nil else { return nil }
                mo = today.month; d = today.day
            case 2:
                if numbers[0].count >= 3 {
                    guard let yy = year(numbers[0]) else { return nil }; y = yy; mo = Int(numbers[1]) ?? 0; d = 1
                } else if numbers[1].count >= 3 {
                    guard let yy = year(numbers[1]) else { return nil }; y = yy; mo = Int(numbers[0]) ?? 0; d = 1
                } else {
                    mo = Int(numbers[0]) ?? 0; d = Int(numbers[1]) ?? 0
                }
            case 3:
                if numbers[0].count >= 3 {
                    guard let yy = year(numbers[0]) else { return nil }
                    y = yy; mo = Int(numbers[1]) ?? 0; d = Int(numbers[2]) ?? 0
                } else {
                    guard let yy = year(numbers[2]) else { return nil }
                    mo = Int(numbers[0]) ?? 0; d = Int(numbers[1]) ?? 0; y = yy
                }
            default:
                return nil
            }
        }
        guard let date = CivilDate(year: y, month: mo, day: d) else { return nil }
        if let w = weekday, w != date.weekday { return nil }
        var h = hour ?? 0
        if let mer = meridiem {
            guard hour != nil, (0...12).contains(h) else { return nil }
            if mer == "A" { if h == 12 { h = 0 } } else if h != 12 { h += 12 }
        }
        guard (0..<24).contains(h), (0..<60).contains(minute), (0..<60).contains(second) else { return nil }
        let wall = NetDateTime(year: date.year, month: date.month, day: date.day, hour: h, minute: minute,
                               second: second, fractionTicks: fractionTicks, kind: .unspecified)
        if utc { return NetDateTime(ticks: wall.ticks, kind: .utc).toLocalTime(zone: zone) }
        if let off = offsetSeconds {
            return NetDateTime(ticks: wall.ticks - Int64(off) * NetDateTime.ticksPerSecond, kind: .utc).toLocalTime(zone: zone)
        }
        return wall
    }

    private static func monthIndex(_ w: String) -> Int? {
        if let k = months.firstIndex(of: w) { return k + 1 }
        if w.count == 3, let k = months.firstIndex(where: { $0.hasPrefix(w) }) { return k + 1 }
        return nil
    }

    private static func dayIndex(_ w: String) -> Int? {
        if let k = days.firstIndex(of: w) { return k }
        if w.count == 3, let k = days.firstIndex(where: { $0.hasPrefix(w) }) { return k }
        return nil
    }

    private static func meridiem(_ w: String) -> Character? {
        switch w.uppercased() {
        case "AM", "A": return "A"
        case "PM", "P": return "P"
        default: return nil
        }
    }
}
