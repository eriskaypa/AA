// The GF.4.7 expectation shapes built from Mac values, and the small .NET-semantics probes they need (spec 01
// GF.4.7, GF.8.4): `DateTime` kind names, `TimeZoneInfo.IsAmbiguousTime`, `DateTime.IsDaylightSavingTime`, the
// DateTime-read shape and the `{ticks, kind}` date node the services cases use. Pure helpers — no AACore state.
import Foundation
@testable import AACore

enum GoldDotNet {
    // MARK: JSON builders

    static func obj(_ pairs: [(String, JSONValue)]) -> JSONValue { .object(JSONObject(pairs)) }
    static func str(_ s: String?) -> JSONValue { s.map(JSONValue.string) ?? .null }
    static func int(_ i: Int?) -> JSONValue { i.map { .number(JSONNumber($0)) } ?? .null }
    static func int64(_ i: Int64) -> JSONValue { .number(JSONNumber(i)) }
    static func bool(_ b: Bool?) -> JSONValue { b.map(JSONValue.bool) ?? .null }
    static func arr(_ items: [JSONValue]) -> JSONValue { .array(items) }
    static func strings(_ items: [String]) -> JSONValue { .array(items.map(JSONValue.string)) }
    static func guid(_ g: UUID?) -> JSONValue { g.map { .string($0.netString) } ?? .null }

    /// A framework exception the Mac reproduces only as "an exception happened" (GF.4.7: messages are compared only
    /// when AA-authored; the matcher drops `type`/`message` when `aaAuthored` is false).
    static var frameworkException: JSONValue { obj([("aaAuthored", .bool(false))]) }

    // MARK: DateTime

    static func kindName(_ k: NetDateTime.Kind) -> String {
        switch k {
        case .unspecified: return "Unspecified"
        case .utc: return "Utc"
        case .local: return "Local"
        }
    }

    /// `{"ticks": …, "kind": …}` or null — the date node of the services cases.
    static func dateNode(_ d: NetDateTime?) -> JSONValue {
        guard let d else { return .null }
        return obj([("ticks", int64(d.ticks)), ("kind", .string(kindName(d.kind)))])
    }

    /// The offsets that are valid for a wall-clock time in `zone` (two when ambiguous, none in a gap).
    static func validOffsets(wallTicks: Int64, zone: TimeZone) -> [Int] {
        let wall = Double(wallTicks - NetDateTime.unixEpochTicks) / 1e7
        var candidates: [Int] = []
        var h = -27
        while h <= 27 {
            let o = zone.secondsFromGMT(for: Date(timeIntervalSince1970: wall + Double(h) * 3600))
            if !candidates.contains(o) { candidates.append(o) }
            h += 3
        }
        return candidates.filter { zone.secondsFromGMT(for: Date(timeIntervalSince1970: wall - Double($0))) == $0 }.sorted()
    }

    /// The wall clock of `d` in `zone` (`.utc` converted, like `TimeZoneInfo.Local.IsAmbiguousTime(utc)`).
    static func localWallTicks(_ d: NetDateTime, zone: TimeZone) -> Int64 {
        d.kind == .utc ? d.toLocalTime(zone: zone).ticks : d.ticks
    }

    /// `TimeZoneInfo.Local.IsAmbiguousTime(dt)`.
    static func isAmbiguousTime(_ d: NetDateTime, zone: TimeZone) -> Bool {
        validOffsets(wallTicks: localWallTicks(d, zone: zone), zone: zone).count > 1
    }

    /// `DateTime.IsDaylightSavingTime()`: false for Utc; for an ambiguous wall clock only a Local value that carries
    /// the daylight offset (the hidden DST bit) is daylight time; a gap is not daylight time.
    static func isDaylightSavingTime(_ d: NetDateTime, zone: TimeZone) -> Bool {
        if d.kind == .utc { return false }
        let valid = validOffsets(wallTicks: d.ticks, zone: zone)
        if valid.count > 1 {
            guard d.kind == .local, let hint = d.offsetHint else { return false }
            return Int(hint) == valid.max()
        }
        guard let off = valid.first else { return false }
        let instant = Date(timeIntervalSince1970: Double(d.ticks - NetDateTime.unixEpochTicks) / 1e7 - Double(off))
        return zone.isDaylightSavingTime(for: instant)
    }

    /// `yyyy-MM-dd HH:mm:ss.fffffff` of the stored wall clock.
    static func wall(_ d: NetDateTime) -> String {
        d.format(.isoLocal7).replacingOccurrences(of: "T", with: " ")
    }

    /// The GF.4.7 DateTime shape of a value.
    static func dateShape(input: String?, _ d: NetDateTime, zone: TimeZone) -> JSONValue {
        var pairs: [(String, JSONValue)] = []
        if let input { pairs.append(("input", .string(input))) }
        pairs += [("ok", .bool(true)), ("ticks", int64(d.ticks)), ("kind", .string(kindName(d.kind))),
                  ("isAmbiguousTime", .bool(isAmbiguousTime(d, zone: zone))),
                  ("isDaylightSavingTime", .bool(isDaylightSavingTime(d, zone: zone))),
                  ("wall", .string(wall(d))), ("rewritten", .string(d.formattedISO(zone: zone)))]
        return obj(pairs)
    }

    /// The DateTime-read shape: `JsonSerializer.Deserialize<DateTime>` of a JSON string.
    static func dateReadShape(_ input: String, zone: TimeZone) -> JSONValue {
        guard let d = NetDateTime(parsing: input, zone: zone) else {
            return obj([("input", .string(input)), ("ok", .bool(false)), ("error", frameworkException)])
        }
        return dateShape(input: input, d, zone: zone)
    }

    static func dateOrNull(_ d: NetDateTime?, zone: TimeZone) -> JSONValue {
        guard let d else { return .null }
        return dateShape(input: nil, d, zone: zone)
    }

    /// `yyyy-MM-dd[ HH:mm][ Local]` → value (Unspecified unless "Local") — the row-spec date form of E06/E07/E16.
    static func parseSpecDate(_ s: String) -> NetDateTime? {
        var text = s
        var kind = NetDateTime.Kind.unspecified
        if text.hasSuffix(" Local") { text.removeLast(6); kind = .local }
        let parts = text.split(separator: " ")
        guard let day = CivilDate(iso: String(parts[0])) else { return nil }
        var minutes = 0
        if parts.count > 1 {
            let hm = parts[1].split(separator: ":")
            guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]) else { return nil }
            minutes = h * 60 + m
        }
        return NetDateTime(year: day.year, month: day.month, day: day.day, hour: minutes / 60, minute: minutes % 60, kind: kind)
    }
}
