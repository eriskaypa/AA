// Spec: 01 §4.1.5 (Now → Local, UtcNow → Utc), ARCHITECTURE.md §3.5 — every "now/today" is injectable.
import Foundation

public protocol AppClock: Sendable {
    /// `DateTime.Now` — kind `.local` with the zone's offset hint.
    func now() -> NetDateTime
    /// `DateTime.UtcNow` — kind `.utc`.
    func utcNow() -> NetDateTime
    /// `DateTime.Today` as a civil date in `timeZone`.
    func today() -> CivilDate
    var timeZone: TimeZone { get }
    /// The current instant.
    func instant() -> Date
}

public struct SystemClock: AppClock {
    public init() {}
    public var timeZone: TimeZone { .current }
    public func instant() -> Date { Date() }
    public func now() -> NetDateTime { NetDateTime(date: instant(), kind: .local, zone: timeZone) }
    public func utcNow() -> NetDateTime { NetDateTime(date: instant(), kind: .utc, zone: timeZone) }
    public func today() -> CivilDate { now().civilDate }
}

/// A clock frozen at a local wall-clock time in a given zone (tests, golden fixtures).
public struct FixedClock: AppClock {
    public let timeZone: TimeZone
    private let fixedInstant: Date

    /// `local` is `yyyy-MM-ddTHH:mm[:ss[.fffffff]]` interpreted as wall-clock time in `zone`
    /// (an unparseable text freezes the clock at 0001-01-01T00:00:00).
    public init(local: String, zone: TimeZone) {
        timeZone = zone
        let wall = NetDateTime(parsing: local, zone: zone) ?? NetDateTime(ticks: 0, kind: .unspecified)
        fixedInstant = NetDateTime(ticks: wall.ticks, kind: .unspecified).foundationDate(zone: zone)
    }

    /// A clock frozen at an exact instant.
    public init(instant: Date, zone: TimeZone) {
        timeZone = zone
        fixedInstant = instant
    }

    public func instant() -> Date { fixedInstant }
    public func now() -> NetDateTime { NetDateTime(date: fixedInstant, kind: .local, zone: timeZone) }
    public func utcNow() -> NetDateTime { NetDateTime(date: fixedInstant, kind: .utc, zone: timeZone) }
    public func today() -> CivilDate { now().civilDate }
}
