// Spec: 01 §4.1.5 (DateTime read/write rules), §3.22 (ToLocalTime), §6.3, App. A; DECISIONS Q-6;
//       ARCHITECTURE.md §3.4 — the one date type of the port (01 OC-56).
import Foundation

/// .NET `DateTime` emulation: wall-clock ticks (100 ns since 0001-01-01T00:00:00) plus a `Kind`.
/// Equality, hashing and ordering use ticks only (like .NET). A value read from JSON remembers its exact text
/// and writes it back unchanged until it is edited (DECISIONS Q-6).
public struct NetDateTime: Sendable, Hashable, Comparable, CustomStringConvertible {
    public enum Kind: UInt8, Sendable { case unspecified, utc, local }

    /// Wall-clock ticks since 0001-01-01T00:00:00 (100 ns). Every change goes through an initializer or the
    /// arithmetic API, which clear `originalText`.
    public private(set) var ticks: Int64
    public private(set) var kind: Kind
    /// Exact JSON text this value was read from; nil when created/edited on the Mac.
    public private(set) var originalText: String?
    /// UTC offset (seconds) of a `.local` value whose instant is known; nil for wall-clock-only values.
    public private(set) var offsetHint: Int32?

    public static let ticksPerSecond: Int64 = 10_000_000
    public static let ticksPerMinute: Int64 = 600_000_000
    public static let ticksPerDay: Int64 = 864_000_000_000
    public static let maxTicks: Int64 = 3_155_378_975_999_999_999          // 9999-12-31T23:59:59.9999999
    public static let unixEpochTicks: Int64 = 621_355_968_000_000_000
    static let daysTo1970 = 719_162

    public init(ticks: Int64, kind: Kind) {
        self.ticks = NetDateTime.clamp(ticks)
        self.kind = kind
        self.originalText = nil
        self.offsetHint = nil
    }

    init(ticks: Int64, kind: Kind, offsetHint: Int32?, originalText: String? = nil) {
        self.ticks = NetDateTime.clamp(ticks)
        self.kind = kind
        self.offsetHint = kind == .local ? offsetHint : nil
        self.originalText = originalText
    }

    /// Builds a value from calendar fields. Out-of-range fields are clamped (month 1…12, day to the month).
    public init(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0,
                fractionTicks: Int64 = 0, kind: Kind) {
        let y = min(max(year, 1), 9999), m = min(max(month, 1), 12)
        let d = min(max(day, 1), CivilDate.daysInMonth(year: y, month: m))
        let date = CivilDate(year: y, month: m, day: d)!
        let days = Int64(date.daysFromCivil + NetDateTime.daysTo1970)
        let t = days * NetDateTime.ticksPerDay
            + Int64(min(max(hour, 0), 23)) * 36_000_000_000
            + Int64(min(max(minute, 0), 59)) * NetDateTime.ticksPerMinute
            + Int64(min(max(second, 0), 59)) * NetDateTime.ticksPerSecond
            + min(max(fractionTicks, 0), NetDateTime.ticksPerSecond - 1)
        self.init(ticks: t, kind: kind)
    }

    static func clamp(_ t: Int64) -> Int64 { min(max(t, 0), maxTicks) }

    // MARK: Parsing (01 §4.1.5 read rules)

    /// `yyyy-MM-dd` | `yyyy-MM-ddTHH:mm` | `yyyy-MM-ddTHH:mm:ss[.fraction]` + optional `Z` / `±HH:mm`.
    /// Fraction: 1…16 digits accepted; the first 7 are used, the rest truncated. No offset → `.unspecified`;
    /// `Z` → `.utc`; an offset → converted to `zone` wall clock, kind `.local`. Anything else → nil.
    /// Keeps `originalText`.
    public init?(parsing text: String, zone: TimeZone = .current) {
        let u = Array(text.utf8)
        let n = u.count
        guard n >= 10, u[4] == 0x2D, u[7] == 0x2D,
              let y = CivilDate.digits(u, 0, 4), let mo = CivilDate.digits(u, 5, 2), let d = CivilDate.digits(u, 8, 2),
              let date = CivilDate(year: y, month: mo, day: d) else { return nil }
        var i = 10
        var hour = 0, minute = 0, second = 0
        var fraction: Int64 = 0
        if i < n, u[i] == 0x54 {                                   // 'T'
            guard i + 6 <= n, u[i + 3] == 0x3A,
                  let h = CivilDate.digits(u, i + 1, 2), let m = CivilDate.digits(u, i + 4, 2),
                  h <= 23, m <= 59 else { return nil }
            hour = h; minute = m; i += 6
            if i < n, u[i] == 0x3A {                               // ':ss'
                guard i + 3 <= n, let s = CivilDate.digits(u, i + 1, 2), s <= 59 else { return nil }
                second = s; i += 3
                if i < n, u[i] == 0x2E {                           // '.fraction'
                    i += 1
                    var count = 0
                    while i < n, u[i] >= 0x30, u[i] <= 0x39 {
                        if count < 7 { fraction = fraction * 10 + Int64(u[i] - 0x30) }
                        count += 1; i += 1
                    }
                    guard count >= 1, count <= 16 else { return nil }
                    if count < 7 { for _ in count..<7 { fraction *= 10 } }
                }
            }
        }
        let days = Int64(date.daysFromCivil + NetDateTime.daysTo1970)
        let wall = days * NetDateTime.ticksPerDay + Int64(hour) * 36_000_000_000
            + Int64(minute) * NetDateTime.ticksPerMinute + Int64(second) * NetDateTime.ticksPerSecond + fraction
        if i == n {
            self.init(ticks: wall, kind: .unspecified, offsetHint: nil, originalText: text)
            return
        }
        if u[i] == 0x5A, i + 1 == n {                              // 'Z'
            self.init(ticks: wall, kind: .utc, offsetHint: nil, originalText: text)
            return
        }
        guard u[i] == 0x2B || u[i] == 0x2D, i + 6 == n, u[i + 3] == 0x3A,
              let oh = CivilDate.digits(u, i + 1, 2), let om = CivilDate.digits(u, i + 4, 2),
              om <= 59, oh * 60 + om <= 14 * 60 else { return nil }
        let sign: Int64 = u[i] == 0x2B ? 1 : -1
        let offsetTicks = sign * Int64(oh * 3600 + om * 60) * NetDateTime.ticksPerSecond
        let utc = wall - offsetTicks
        guard utc >= 0, utc <= NetDateTime.maxTicks else { return nil }
        let local = NetDateTime.zoneOffset(atUTCTicks: utc, zone: zone)
        self.init(ticks: utc + Int64(local) * NetDateTime.ticksPerSecond, kind: .local,
                  offsetHint: Int32(local), originalText: text)
    }

    // MARK: Writing (01 §4.1.5 write rules)

    /// The JSON text: `originalText` when non-nil, else the canonical form.
    public func jsonString(zone: TimeZone = .current) -> String {
        if let t = originalText { return t }
        return formattedISO(zone: zone)
    }

    /// Canonical STJ form ignoring `originalText`: `yyyy-MM-ddTHH:mm:ss[.F{1..7}]` + `""` / `Z` / `±HH:mm`.
    public func formattedISO(zone: TimeZone = .current) -> String {
        var s = wallString(fraction: .trimmed)
        switch kind {
        case .unspecified: break
        case .utc: s += "Z"
        case .local: s += NetDateTime.offsetText(localOffsetSeconds(zone: zone))
        }
        return s
    }

    enum FractionStyle { case none, trimmed, seven }

    func wallString(fraction style: FractionStyle, dateTimeSeparator: String = "T") -> String {
        let p = parts
        var s = CivilDate.pad(p.date.year, 4) + "-" + CivilDate.pad(p.date.month, 2) + "-" + CivilDate.pad(p.date.day, 2)
            + dateTimeSeparator + CivilDate.pad(p.hour, 2) + ":" + CivilDate.pad(p.minute, 2) + ":" + CivilDate.pad(p.second, 2)
        switch style {
        case .none: break
        case .seven: s += "." + CivilDate.pad(Int(p.fraction), 7)
        case .trimmed:
            if p.fraction != 0 {
                var f = CivilDate.pad(Int(p.fraction), 7)
                while f.hasSuffix("0") { f.removeLast() }
                s += "." + f
            }
        }
        return s
    }

    static func offsetText(_ seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let a = abs(seconds) / 60
        return sign + CivilDate.pad(a / 60, 2) + ":" + CivilDate.pad(a % 60, 2)
    }

    /// Offset used when writing a `.local` value: `offsetHint` when known, else the zone's offset for the wall
    /// clock — the zone's standard offset when the wall clock is ambiguous or invalid (like .NET `GetUtcOffset`).
    func localOffsetSeconds(zone: TimeZone) -> Int {
        if let h = offsetHint { return Int(h) }
        return NetDateTime.resolveWallOffset(wallTicks: ticks, zone: zone)
    }

    public var description: String { "\(formattedISO(zone: .current)) (\(kind))" }

    // MARK: Equality (.NET: ticks only)

    public static func == (a: NetDateTime, b: NetDateTime) -> Bool { a.ticks == b.ticks }
    public func hash(into h: inout Hasher) { h.combine(ticks) }
    public static func < (a: NetDateTime, b: NetDateTime) -> Bool { a.ticks < b.ticks }

    // MARK: Creation (DECISIONS Q-6)

    public static func now(clock: AppClock = SystemClock()) -> NetDateTime { clock.now() }
    public static func utcNow(clock: AppClock = SystemClock()) -> NetDateTime { clock.utcNow() }

    /// `.unspecified` midnight of a calendar date (deadlines, ranges, recurrence dates, step/subtask deadlines).
    public static func calendarDate(_ d: CivilDate) -> NetDateTime {
        NetDateTime(ticks: Int64(d.daysFromCivil + daysTo1970) * ticksPerDay, kind: .unspecified)
    }

    /// `.unspecified` date + minutes after midnight (Planner `ScheduledStart`).
    public static func calendarDateTime(_ d: CivilDate, minutes: Int) -> NetDateTime {
        NetDateTime(ticks: Int64(d.daysFromCivil + daysTo1970) * ticksPerDay + Int64(max(0, minutes)) * ticksPerMinute,
                    kind: .unspecified)
    }

    /// Same wall clock, kind `.unspecified`, `originalText` and `offsetHint` nil.
    public var asCalendarDate: NetDateTime { NetDateTime(ticks: ticks, kind: .unspecified) }

    // MARK: Components & arithmetic (all drop originalText and offsetHint; kind preserved)

    struct Parts { var date: CivilDate; var hour: Int; var minute: Int; var second: Int; var fraction: Int64 }

    var parts: Parts {
        let days = ticks / NetDateTime.ticksPerDay
        var rem = ticks % NetDateTime.ticksPerDay
        let date = CivilDate(daysFromCivil: Int(days) - NetDateTime.daysTo1970)
        let hour = Int(rem / 36_000_000_000); rem %= 36_000_000_000
        let minute = Int(rem / NetDateTime.ticksPerMinute); rem %= NetDateTime.ticksPerMinute
        let second = Int(rem / NetDateTime.ticksPerSecond); rem %= NetDateTime.ticksPerSecond
        return Parts(date: date, hour: hour, minute: minute, second: second, fraction: rem)
    }

    /// .NET `.Date`: midnight of the wall clock, same kind.
    public var date: NetDateTime { NetDateTime(ticks: ticks - ticks % NetDateTime.ticksPerDay, kind: kind) }
    /// Wall-clock year-month-day (no zone math).
    public var civilDate: CivilDate { parts.date }
    public var minutesOfDay: Int { Int((ticks % NetDateTime.ticksPerDay) / NetDateTime.ticksPerMinute) }
    public var year: Int { parts.date.year }
    public var month: Int { parts.date.month }
    public var day: Int { parts.date.day }
    public var hour: Int { parts.hour }
    public var minute: Int { parts.minute }
    public var second: Int { parts.second }
    /// Ticks since midnight.
    public var timeOfDayTicks: Int64 { ticks % NetDateTime.ticksPerDay }

    public func addingDays(_ n: Int) -> NetDateTime { addingTicks(Int64(n) * NetDateTime.ticksPerDay) }

    /// .NET `AddMonths` (end-of-month clamp), time of day kept.
    public func addingMonths(_ n: Int) -> NetDateTime {
        let d = civilDate.addingMonths(n)
        return NetDateTime(ticks: Int64(d.daysFromCivil + NetDateTime.daysTo1970) * NetDateTime.ticksPerDay + timeOfDayTicks,
                           kind: kind)
    }

    /// .NET `AddYears` (Feb 29 → Feb 28), time of day kept.
    public func addingYears(_ n: Int) -> NetDateTime {
        let d = civilDate.addingYears(n)
        return NetDateTime(ticks: Int64(d.daysFromCivil + NetDateTime.daysTo1970) * NetDateTime.ticksPerDay + timeOfDayTicks,
                           kind: kind)
    }

    public func addingTicks(_ t: Int64) -> NetDateTime {
        let (r, overflow) = ticks.addingReportingOverflow(t)
        return NetDateTime(ticks: overflow ? (t > 0 ? NetDateTime.maxTicks : 0) : r, kind: kind)
    }

    /// .NET `ToLocalTime()`: `.utc` and `.unspecified` are treated as UTC and converted to `zone` wall clock
    /// (kind `.local`, offsetHint set); a `.local` value is returned unchanged.
    public func toLocalTime(zone: TimeZone = .current) -> NetDateTime {
        if kind == .local { return self }
        let off = NetDateTime.zoneOffset(atUTCTicks: ticks, zone: zone)
        return NetDateTime(ticks: ticks + Int64(off) * NetDateTime.ticksPerSecond, kind: .local, offsetHint: Int32(off))
    }

    /// The instant this value denotes (for display/arithmetic only): `.utc` as UTC; `.local` via its offset;
    /// `.unspecified` as a wall clock in `zone`.
    public func foundationDate(zone: TimeZone = .current) -> Date {
        let utc: Int64
        switch kind {
        case .utc: utc = ticks
        case .local: utc = ticks - Int64(localOffsetSeconds(zone: zone)) * NetDateTime.ticksPerSecond
        case .unspecified: utc = ticks - Int64(NetDateTime.resolveWallOffset(wallTicks: ticks, zone: zone)) * NetDateTime.ticksPerSecond
        }
        return NetDateTime.date(fromUTCTicks: utc)
    }

    /// From an instant: `.utc` → UTC ticks; `.local` → wall clock in `zone` with offsetHint; `.unspecified` →
    /// wall clock in `zone` without a hint.
    public init(date: Date, kind: Kind, zone: TimeZone = .current) {
        let utc = NetDateTime.utcTicks(of: date)
        switch kind {
        case .utc:
            self.init(ticks: utc, kind: .utc)
        case .local, .unspecified:
            let off = zone.secondsFromGMT(for: date)
            self.init(ticks: utc + Int64(off) * NetDateTime.ticksPerSecond, kind: kind,
                      offsetHint: kind == .local ? Int32(off) : nil)
        }
    }

    public func format(_ pattern: NetDateFormat, zone: TimeZone = .current) -> String {
        let p = parts
        let date = p.date
        let ymd = CivilDate.pad(date.year, 4) + "-" + CivilDate.pad(date.month, 2) + "-" + CivilDate.pad(date.day, 2)
        let hm = CivilDate.pad(p.hour, 2) + ":" + CivilDate.pad(p.minute, 2)
        let hms = hm + ":" + CivilDate.pad(p.second, 2)
        let compact = CivilDate.pad(date.year, 4) + CivilDate.pad(date.month, 2) + CivilDate.pad(date.day, 2)
        switch pattern {
        case .isoDate: return ymd
        case .isoMinute: return ymd + " " + hm
        case .isoSecond: return ymd + " " + hms
        case .time: return hm
        case .stampMinute: return compact + "-" + CivilDate.pad(p.hour, 2) + CivilDate.pad(p.minute, 2)
        case .stampSecond: return compact + "-" + CivilDate.pad(p.hour, 2) + CivilDate.pad(p.minute, 2) + CivilDate.pad(p.second, 2)
        case .isoLocalSeconds: return ymd + "T" + hms
        case .isoLocal7: return ymd + "T" + hms + "." + CivilDate.pad(Int(p.fraction), 7)
        case .roundTripO:
            let base = ymd + "T" + hms + "." + CivilDate.pad(Int(p.fraction), 7)
            switch kind {
            case .unspecified: return base
            case .utc: return base + "Z"
            case .local: return base + NetDateTime.offsetText(localOffsetSeconds(zone: zone))
            }
        }
    }

    // MARK: Zone helpers

    static func utcTicks(of date: Date) -> Int64 {
        let t = date.timeIntervalSince1970
        let whole = t.rounded(.down)
        let frac = ((t - whole) * 1e7).rounded()
        return unixEpochTicks + Int64(whole) * ticksPerSecond + Int64(frac)
    }

    static func date(fromUTCTicks t: Int64) -> Date {
        let rel = t - unixEpochTicks
        let secs = rel / ticksPerSecond, rem = rel % ticksPerSecond
        return Date(timeIntervalSince1970: Double(secs) + Double(rem) / 1e7)
    }

    /// Offset (seconds) of `zone` at a UTC instant.
    static func zoneOffset(atUTCTicks t: Int64, zone: TimeZone) -> Int {
        zone.secondsFromGMT(for: date(fromUTCTicks: t))
    }

    /// Offset for a wall-clock time in `zone`; the standard (base) offset when the wall clock is ambiguous
    /// (DST fall-back) or invalid (spring-forward gap), like .NET `TimeZoneInfo.GetUtcOffset`.
    static func resolveWallOffset(wallTicks: Int64, zone: TimeZone) -> Int {
        let wall = Double(wallTicks - unixEpochTicks) / 1e7
        var candidates: [Int] = []
        var h = -15
        while h <= 15 {
            let o = zone.secondsFromGMT(for: Date(timeIntervalSince1970: wall + Double(h) * 3600))
            if !candidates.contains(o) { candidates.append(o) }
            h += 3
        }
        let valid = candidates.filter { zone.secondsFromGMT(for: Date(timeIntervalSince1970: wall - Double($0))) == $0 }
        if valid.count == 1 { return valid[0] }
        let probe = Date(timeIntervalSince1970: wall - Double(valid.first ?? candidates.first ?? 0))
        return zone.secondsFromGMT(for: probe) - Int(zone.daylightSavingTimeOffset(for: probe))
    }
}

/// Fixed invariant formats (en_US_POSIX, Gregorian; 01 §6.3). Every owner uses these.
public enum NetDateFormat: Sendable {
    case isoDate            // "yyyy-MM-dd"
    case isoMinute          // "yyyy-MM-dd HH:mm"
    case isoSecond          // "yyyy-MM-dd HH:mm:ss"
    case time               // "HH:mm"
    case stampMinute        // "yyyyMMdd-HHmm"
    case stampSecond        // "yyyyMMdd-HHmmss"
    case isoLocalSeconds    // "yyyy-MM-ddTHH:mm:ss" (no offset) — Flash change-set `Created` (13 §3.11.6)
    case isoLocal7          // "yyyy-MM-ddTHH:mm:ss.fffffff" (no offset) — applier `LastModified` (13 §4.5)
    case roundTripO         // .NET "o": 7 fixed fraction digits + kind suffix ("" / "Z" / "±HH:mm")
}
