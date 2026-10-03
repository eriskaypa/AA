// Spec: 09 §3.6 (DateResolver — every rule), CREW-032/033, §7.2–§7.4, §8 Q1/Q2/Q6/Q7/Q8/Q9;
//       DECISIONS 09 (Q1 ask only when an ambiguous value was seen; Q2 the answer takes effect for Conflicted files;
//       Q6 never truncate raw text; Q7 Excel serials; Q8 ASCII digits; Q9 unreadable instead of abort).
//       ARCHITECTURE.md §2.2 (pure algorithm → nonisolated Sendable value type).
import Foundation

/// The file-wide day/month convention (never persisted as an integer, 09 §4.12).
public enum CrewDateOrder: String, Sendable, CaseIterable {
    case unknown = "Unknown", dayFirst = "DayFirst", monthFirst = "MonthFirst", conflicted = "Conflicted"
}

/// What a date column means (drives two-digit-year expansion).
public enum CrewDateRole: Sendable { case any, pastOnly, futureLikely }

/// One resolved value: a date, or the raw text kept with a note explaining why it was not read.
public struct CrewDateResolution: Sendable, Equatable {
    public var value: CivilDate?
    /// The cleaned text (empty for blanks, placeholders and zero dates).
    public var raw: String
    public var dependedOnOrder: Bool
    public var note: String?

    public init(value: CivilDate? = nil, raw: String = "", dependedOnOrder: Bool = false, note: String? = nil) {
        self.value = value; self.raw = raw; self.dependedOnOrder = dependedOnOrder; self.note = note
    }

    /// `ToStorage()` — `yyyy-MM-dd` when read, else the kept text.
    public var storage: String { value?.iso ?? raw }
}

/// Reads any date shape a crewing export produces and works out dd/mm vs mm/dd from the whole file.
public struct CrewDateResolver: Sendable {
    public static let witnessCap = 50

    public private(set) var dayWitnesses: [String] = []
    public private(set) var monthWitnesses: [String] = []
    /// DECISIONS 09 Q1: values whose reading depends on the convention (both components ≤ 12).
    public private(set) var ambiguousCount = 0
    public private(set) var order: CrewDateOrder = .unknown
    /// The order came from the user's answer, not from the data.
    public private(set) var orderChosenByUser = false
    /// The file proved both conventions before the user chose one (DECISIONS 09 Q2).
    public private(set) var conflictOverridden = false

    /// "Today" for two-digit-year expansion and year-less month-name text (injected for tests).
    public let today: CivilDate
    public let zone: TimeZone
    /// The workbook's date system, for plain-number Excel serials (DECISIONS 09 Q7).
    public var use1904: Bool

    public init(today: CivilDate, zone: TimeZone = .current, use1904: Bool = false) {
        self.today = today; self.zone = zone; self.use1904 = use1904
    }

    /// How many values proved the convention (0 when the order came from the user's answer).
    public var decisiveCount: Int {
        if orderChosenByUser { return 0 }
        switch order {
        case .dayFirst: return dayWitnesses.count
        case .monthFirst: return monthWitnesses.count
        default: return 0
        }
    }

    public var isConflicted: Bool { order == .conflicted }

    // MARK: Observe / infer

    /// Feeds one candidate value. Only numeric `a/b/y` values with a component above 12 are evidence (no validity
    /// check: `31/02/2026` is a day witness). Values that will be read ambiguously are counted for Q1.
    public mutating func observe(_ raw: String?) {
        let s = Self.clean(raw)
        if s.isEmpty { return }
        if let m = Self.numeric(s) {
            let c1 = m.a, c2 = m.b
            if !(c1 > 31 || c2 > 31 || (c1 > 12 && c2 > 12)) {
                if c1 > 12 {
                    if dayWitnesses.count < Self.witnessCap { dayWitnesses.append(s) }
                } else if c2 > 12 {
                    if monthWitnesses.count < Self.witnessCap { monthWitnesses.append(s) }
                }
            }
        }
        if isOrderDependent(s) { ambiguousCount += 1 }
    }

    /// True when `Resolve` would have to use the convention for this cleaned value.
    func isOrderDependent(_ cleaned: String) -> Bool {
        if Self.isPlaceholderText(cleaned) || Self.isZeroDate(cleaned) { return false }
        let s = Self.stripTime(cleaned)
        guard let m = Self.numeric(s) else { return false }
        return m.a <= 12 && m.b <= 12
    }

    /// Decides the convention: both kinds of witness → Conflicted (never a majority); one kind → that order;
    /// neither → `fallback`.
    public mutating func infer(fallback: CrewDateOrder = .unknown) {
        let day = !dayWitnesses.isEmpty, month = !monthWitnesses.isEmpty
        if day && month { order = .conflicted } else if day { order = .dayFirst } else if month { order = .monthFirst } else {
            order = fallback
        }
    }

    /// Adopts a convention decided elsewhere (the user's answer; DECISIONS 09 Q2 also for Conflicted files).
    public mutating func adopt(_ newOrder: CrewDateOrder, byUser: Bool = false) {
        if byUser && order == .conflicted && newOrder != .conflicted { conflictOverridden = true }
        order = newOrder
        if byUser { orderChosenByUser = true }
    }

    // MARK: Resolve

    /// Reads one value; never throws.
    public func resolve(_ raw: String?, role: CrewDateRole = .any) -> CrewDateResolution {
        let original = Self.clean(raw)
        if original.isEmpty { return CrewDateResolution() }
        if Self.isPlaceholderText(original) { return CrewDateResolution() }
        if Self.isZeroDate(original) { return CrewDateResolution(note: "empty date") }

        let s = Self.stripTime(original)
        // DECISIONS 09 Q6: an unreadable value keeps the whole cell text, never a truncated piece of it.
        func unread(_ note: String, dependent: Bool = false) -> CrewDateResolution {
            CrewDateResolution(value: nil, raw: original, dependedOnOrder: dependent, note: note)
        }

        // ---- Unambiguous shapes, most certain first ----
        if let m = Self.match(s, first: [4], second: [1, 2], third: [1, 2]),
           let d = Self.tryMake(m.0, m.1, m.2) {
            return CrewDateResolution(value: d, raw: s)
        }
        let u = Array(s.utf16)
        if u.count == 8, u.allSatisfy(Self.isDigit),
           let d = Self.tryMake(Self.int(u[0..<4]), Self.int(u[4..<6]), Self.int(u[6..<8])) {
            return CrewDateResolution(value: d, raw: s)
        }
        switch monthName(s, role: role) {
        case .date(let d): return CrewDateResolution(value: d, raw: s)
        case .invalid: return unread("'\(s)' is not a real date")
        case .none: break
        }
        if let m = Self.match(s, first: [2], second: [1, 2], third: [1, 2]), m.0 > 31,
           let d = Self.tryMake(expandYear(m.0, role: role), m.1, m.2) {
            return CrewDateResolution(value: d, raw: s)
        }
        // DECISIONS 09 Q7: a plain five-digit number in a date column is an Excel serial (1900 or 1904 system).
        if u.count == 5, u.allSatisfy(Self.isDigit),
           let d = Self.fromExcelSerial(Double(Self.int(u[0..<5])), use1904: use1904) {
            return CrewDateResolution(value: d, raw: s)
        }

        // ---- Ambiguous numeric ----
        guard let nm = Self.numeric(s) else { return unread("'\(s)' is not a date AA recognises") }
        let a = nm.a, b = nm.b
        let year = expandYear(nm.year, role: role, alreadyFull: nm.yearDigits == 4)

        if a > 12 && b <= 12 {
            if let d = Self.tryMake(year, b, a) { return CrewDateResolution(value: d, raw: s) }
            return unread("'\(s)' is not a real date")
        }
        if b > 12 && a <= 12 {
            if let d = Self.tryMake(year, a, b) { return CrewDateResolution(value: d, raw: s) }
            return unread("'\(s)' is not a real date")
        }
        if a > 12 && b > 12 { return unread("'\(s)' is not a real date") }

        if order == .dayFirst, let dayFirst = Self.tryMake(year, b, a) {
            let other = Self.tryMake(year, a, b).map(Self.longText) ?? "an invalid date"
            return CrewDateResolution(value: dayFirst, raw: s, dependedOnOrder: true,
                                      note: "read as \(Self.longText(dayFirst)) (day first); would be \(other) if month first")
        }
        if order == .monthFirst, let monthFirst = Self.tryMake(year, a, b) {
            let other = Self.tryMake(year, b, a).map(Self.longText) ?? "an invalid date"
            return CrewDateResolution(value: monthFirst, raw: s, dependedOnOrder: true,
                                      note: "read as \(Self.longText(monthFirst)) (month first); would be \(other) if day first")
        }
        if order == .conflicted {
            return unread("'\(s)' left unread — this file writes dates both ways, so neither reading is safe", dependent: true)
        }
        return unread("'\(s)' could be \(a) \(Self.monthAbbrev(b)) or \(b) \(Self.monthAbbrev(a)), and nothing in the file says which",
                      dependent: true)
    }

    // MARK: Year expansion, validity, serials

    /// `ExpandYear`: 00–68 → 2000s, 69–99 → 1900s; a past-only field never lands after this year, a future-likely
    /// field never more than five years back.
    public func expandYear(_ y: Int, role: CrewDateRole, alreadyFull: Bool = false) -> Int {
        if alreadyFull || y > 99 { return y }
        let candidate = y <= 68 ? 2000 + y : 1900 + y
        if role == .pastOnly && candidate > today.year { return candidate - 100 }
        if role == .futureLikely && candidate < today.year - 5 { return candidate + 100 }
        return candidate
    }

    /// `TryMake`: 1900…2199, a real month and day (proleptic Gregorian).
    public static func tryMake(_ y: Int, _ m: Int, _ d: Int) -> CivilDate? {
        guard (1900...2199).contains(y) else { return nil }
        return CivilDate(year: y, month: m, day: d)
    }

    /// `FromExcelSerial`: NaN/∞ → nil; outside 1…73051 → nil; epoch 1899-12-30 (1904-01-01) + whole days.
    public static func fromExcelSerial(_ serial: Double, use1904: Bool = false) -> CivilDate? {
        guard serial.isFinite, serial >= 1, serial <= 73_051 else { return nil }
        let epoch = use1904 ? CivilDate(year: 1904, month: 1, day: 1)! : CivilDate(year: 1899, month: 12, day: 30)!
        return epoch.addingDays(Int(serial.rounded(.down)))
    }

    /// `IsPlaceholder`: a placeholder or a zero date.
    public static func isPlaceholder(_ s: String?) -> Bool {
        let t = clean(s)
        return !t.isEmpty && (isPlaceholderText(t) || isZeroDate(t))
    }

    // MARK: Tables

    static let placeholders: Set<String> = ["-", "--", "---", "n/a", "na", "n.a.", "nil", "none", "tbc", "tba", "tbd",
                                            "pending", "unknown", "?", "x", "#n/a", "#ref!", "#value!", "null"]
    static let zeroDates: Set<String> = ["0", "00/00/0000", "00-00-0000", "1900-01-01", "1899-12-30", "01/01/1900",
                                         "30/12/1899"]
    static let monthAbbrevs = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let monthFull = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                            "October", "November", "December"]

    static func isPlaceholderText(_ s: String) -> Bool { placeholders.contains(NetText.toLowerInvariant(s)) }
    static func isZeroDate(_ s: String) -> Bool { zeroDates.contains(NetText.toLowerInvariant(s)) }

    /// `Month(m)`: `Jan`…`Dec`, `?` outside 1…12.
    static func monthAbbrev(_ m: Int) -> String { (1...12).contains(m) ? monthAbbrevs[m - 1] : "?" }

    /// `d MMM yyyy` in English (`3 Apr 2026`) — flag messages are data (09 §4.12 rule 5).
    public static func longText(_ d: CivilDate) -> String {
        "\(d.day) \(monthAbbrevs[d.month - 1]) \(CivilDate.pad(d.year, 4))"
    }

    // MARK: Text helpers

    /// `Clean`: NBSP → space, .NET `Trim()`.
    static func clean(_ raw: String?) -> String {
        NetText.trim((raw ?? "").replacingOccurrences(of: "\u{00A0}", with: " "))
    }

    /// `StripTime` with the DECISIONS 09 Q6 fix: a `T` is a date/time separator only at index ≥ 8 **after a digit**;
    /// a space starts a time only when the text after it begins `H:mm`/`HH:mm`. Then trailing `Z`/`z` and white space go.
    static func stripTime(_ input: String) -> String {
        var u = Array(input.utf16)
        if let t = u.indices.first(where: { $0 >= 8 && u[$0] == 0x54 && isDigit(u[$0 - 1]) }) {
            u = Array(u[..<t])
        }
        var k = 1
        while k < u.count {
            if u[k] == 0x20, startsWithClock(u, from: k + 1) { u = Array(u[..<k]); break }
            k += 1
        }
        while let last = u.last, last == 0x5A || last == 0x7A { u.removeLast() }
        return NetText.trim(String(decoding: u, as: UTF16.self))
    }

    /// `^\d{1,2}:\d{2}` at `from`.
    static func startsWithClock(_ u: [UInt16], from i: Int) -> Bool {
        var j = i, n = 0
        while j < u.count, isDigit(u[j]), n < 2 { j += 1; n += 1 }
        guard n >= 1, j + 2 < u.count, u[j] == 0x3A else { return false }
        return isDigit(u[j + 1]) && isDigit(u[j + 2])
    }

    static func isDigit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }

    static func int<C: Collection>(_ digits: C) -> Int where C.Element == UInt16 {
        digits.reduce(0) { $0 * 10 + Int($1 - 0x30) }
    }

    /// Digit run (ASCII only, DECISIONS 09 Q8) of an allowed length, a separator `/ . -`, a run, the same separator,
    /// a run, end of text.
    static func match(_ s: String, first: Set<Int>, second: Set<Int>, third: Set<Int>) -> (Int, Int, Int, Int)? {
        let u = Array(s.utf16)
        var i = 0
        func run() -> ArraySlice<UInt16> {
            let start = i
            while i < u.count, isDigit(u[i]) { i += 1 }
            return u[start..<i]
        }
        let g1 = run()
        guard first.contains(g1.count), i < u.count else { return nil }
        let sep = u[i]
        guard sep == 0x2F || sep == 0x2E || sep == 0x2D else { return nil }
        i += 1
        let g2 = run()
        guard second.contains(g2.count), i < u.count, u[i] == sep else { return nil }
        i += 1
        let g3 = run()
        guard third.contains(g3.count), i == u.count else { return nil }
        return (int(g1), int(g2), int(g3), g3.count)
    }

    /// `Numeric = ^(\d{1,2})([/.\-])(\d{1,2})\2(\d{2}|\d{4})$`.
    static func numeric(_ s: String) -> (a: Int, b: Int, year: Int, yearDigits: Int)? {
        guard let m = match(s, first: [1, 2], second: [1, 2], third: [2, 4]) else { return nil }
        return (m.0, m.1, m.2, m.3)
    }

    // MARK: Month names

    enum MonthNameResult { case date(CivilDate), invalid, none }

    /// The thirteen exact formats in order, then — only when three letters are present — the general parser.
    func monthName(_ s: String, role: CrewDateRole) -> MonthNameResult {
        var t = Self.replace(s, pattern: "\\bSEPT\\b", with: "Sep")
        t = Self.replace(t, pattern: "(?<=\\d)(st|nd|rd|th)\\b", with: "")
        t = t.replacingOccurrences(of: ",", with: " ")
        t = NetText.trim(Self.replace(t, pattern: "\\s+", with: " ", caseInsensitive: false))

        for f in Self.monthNameFormats {
            guard let p = Self.parseExact(t, format: f) else { continue }
            if p.twoDigitYear {
                // DECISIONS 09 Q9: an expansion that lands on 29 Feb of a non-leap year is unreadable, not a crash.
                guard let d = CivilDate(year: expandYear(p.date.year % 100, role: role), month: p.date.month,
                                        day: p.date.day) else { return .invalid }
                return .date(d)
            }
            return .date(p.date)
        }
        if Self.hasThreeLetters(t), let g = NetDateParser.parse(t, zone: zone, today: today) {
            return .date(g.civilDate)
        }
        return .none
    }

    static let monthNameFormats: [[FormatToken]] = [
        "d MMM yyyy", "d MMMM yyyy", "dd MMM yyyy", "dd MMMM yyyy", "MMM d yyyy", "MMMM d yyyy", "d-MMM-yyyy",
        "dd-MMM-yyyy", "d-MMM-yy", "dd-MMM-yy", "d MMM yy", "dd MMM yy", "yyyy MMM d",
    ].map(tokens)

    enum FormatToken: Equatable { case d, dd, mmm, mmmm, yy, yyyy, literal(UInt16) }

    static func tokens(_ f: String) -> [FormatToken] {
        var out: [FormatToken] = []
        let u = Array(f.utf16)
        var i = 0
        while i < u.count {
            var j = i
            while j < u.count, u[j] == u[i] { j += 1 }
            let n = j - i
            switch (u[i], n) {
            case (0x64, 1): out.append(.d)
            case (0x64, 2): out.append(.dd)
            case (0x4D, 3): out.append(.mmm)
            case (0x4D, 4): out.append(.mmmm)
            case (0x79, 2): out.append(.yy)
            case (0x79, 4): out.append(.yyyy)
            default: for _ in 0..<n { out.append(.literal(u[i])) }
            }
            i = j
        }
        return out
    }

    /// .NET `TryParseExact` (InvariantCulture, no styles) for the month-name formats: `d` = 1–2 digits, `dd`/`yy` =
    /// exactly 2, `yyyy` = exactly 4, month names case-insensitive; `yy` uses the 2049 pivot for validation.
    static func parseExact(_ text: String, format: [FormatToken]) -> (date: CivilDate, twoDigitYear: Bool)? {
        let u = Array(text.utf16)
        var i = 0
        var day: Int?, month: Int?, year: Int?, twoDigit = false
        func digits(min: Int, max: Int) -> Int? {
            let start = i
            while i < u.count, i - start < max, isDigit(u[i]) { i += 1 }
            guard i - start >= min else { return nil }
            return int(u[start..<i])
        }
        func monthName(_ names: [String]) -> Int? {
            // Longest match first (so "Sep" never shadows a longer name in the same table).
            let ordered = names.enumerated().sorted { $0.element.utf16.count > $1.element.utf16.count }
            for (k, name) in ordered {
                let n = Array(name.utf16)
                guard i + n.count <= u.count else { continue }
                let slice = String(decoding: u[i..<(i + n.count)], as: UTF16.self)
                if NetText.equalsIgnoreCase(slice, name) { i += n.count; return k + 1 }
            }
            return nil
        }
        for tok in format {
            switch tok {
            case .d: guard let v = digits(min: 1, max: 2) else { return nil }; day = v
            case .dd: guard let v = digits(min: 2, max: 2) else { return nil }; day = v
            case .yy: guard let v = digits(min: 2, max: 2) else { return nil }; year = v <= 49 ? 2000 + v : 1900 + v; twoDigit = true
            case .yyyy: guard let v = digits(min: 4, max: 4) else { return nil }; year = v
            case .mmm: guard let v = monthName(monthAbbrevs) else { return nil }; month = v
            case .mmmm: guard let v = monthName(monthFull) else { return nil }; month = v
            case .literal(let c): guard i < u.count, u[i] == c else { return nil }; i += 1
            }
        }
        guard i == u.count, let day, let month, let year, let date = CivilDate(year: year, month: month, day: day) else {
            return nil
        }
        return (date, twoDigit)
    }

    static func hasThreeLetters(_ s: String) -> Bool {
        var run = 0
        for u in s.utf16 {
            if (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) { run += 1; if run >= 3 { return true } } else { run = 0 }
        }
        return false
    }

    static func replace(_ s: String, pattern: String, with template: String, caseInsensitive: Bool = true) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else {
            return s
        }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}
