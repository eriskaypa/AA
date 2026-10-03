// Spec: 10 §X.4.7 (serial → date-time: ClosedXML `ToSerialDateTime` leap-year shim + .NET `DateTime.FromOADate`,
//       half-away-from-zero millisecond rounding, the OA negative-date rule), §X.4.8 (1904), §X.4.9 (durations:
//       `TimeSpan.FromDays` truncated to ticks, then banker's rounding to whole ms; `ToExcelString`), VESSEL-309…311,
//       X.8.3–X.8.4; OC-56 (functions over the one `NetDateTime`, pure civil arithmetic — never `Date` + a zone).
import Foundation

public enum ExcelSerial {
    static let msPerDay: Int64 = 86_400_000
    /// 1899-12-30 as days since 1970-01-01.
    static let oaEpochDays = CivilDate(year: 1899, month: 12, day: 30)!.daysFromCivil
    /// 1899-12-30T00:00 in .NET ticks.
    static let oaEpochTicks = Int64(CivilDate(year: 1899, month: 12, day: 30)!.daysFromCivil) * NetDateTime.ticksPerDay
        + NetDateTime.unixEpochTicks

    /// VESSEL-309: `v ≥ 61` → `FromOADate(v)`; `v ≤ 60` → `FromOADate(v + 1)` (ClosedXML's 1900 leap-year shim);
    /// `60 < v < 61` → the ClosedXML message. Result kind `.unspecified`.
    public static func fromSerial(_ v: Double) throws(XlsxReadError) -> NetDateTime {
        if v >= 61 { return try fromOADate(v) }
        if v <= 60 { return try fromOADate(v + 1) }
        throw .message("Serial date 60 is on a leap year of 1900 - date that doesn't exist and isn't representable in DateTime.")
    }

    /// .NET `DateTime.FromOADate`: valid range (−657435, 2958466) exclusive, else "Not a legal OleAut date.";
    /// milliseconds rounded half away from zero; a negative date's time part counts forward from its day.
    public static func fromOADate(_ d: Double) throws(XlsxReadError) -> NetDateTime {
        guard d < 2_958_466.0, d > -657_435.0 else { throw .message("Not a legal OleAut date.") }
        var ms = Int64(d * Double(msPerDay) + (d >= 0 ? 0.5 : -0.5))
        if ms < 0 { ms -= (ms % msPerDay) * 2 }
        let day = ms >= 0 ? ms / msPerDay : -((-ms + msPerDay - 1) / msPerDay)
        let msOfDay = ms - day * msPerDay
        let date = CivilDate(daysFromCivil: oaEpochDays + Int(day))
        let wall = Int64(date.daysFromCivil) * NetDateTime.ticksPerDay + NetDateTime.unixEpochTicks + msOfDay * 10_000
        return NetDateTime(ticks: wall, kind: .unspecified)
    }

    /// ClosedXML `ToSerialDateTime`: `oa = ToOADate(dt)`; `oa <= 60 ? oa − 1 : oa`.
    public static func toSerial(_ dt: NetDateTime) -> Double {
        let oa = toOADate(dt)
        return oa <= 60 ? oa - 1 : oa
    }

    /// .NET `DateTime.ToOADate` (`TicksToOADate`).
    static func toOADate(_ dt: NetDateTime) -> Double {
        if dt.ticks == 0 { return 0 }
        var millis = (dt.ticks - oaEpochTicks) / 10_000
        if millis < 0 {
            let frac = millis % msPerDay
            if frac != 0 { millis -= (msPerDay + frac) * 2 }
        }
        return Double(millis) / Double(msPerDay)
    }

    /// `XLHelper.GetTimeSpan` in whole milliseconds: `TimeSpan.FromDays(v)` (ticks truncated toward zero), then
    /// `Math.Round(ticks / 10 000)` (banker's rounding).
    public static func toTimeSpanMs(_ v: Double) throws(XlsxReadError) -> Int64 {
        let ticks = v * 864_000_000_000.0
        guard ticks.isFinite, abs(ticks) < 9.2e18 else {
            throw .message("TimeSpan overflowed because the duration is too long.")
        }
        let t = Int64(ticks)
        return Int64((Double(t) / 10_000.0).rounded(.toNearestOrEven))
    }

    /// `TimeSpan.ToExcelString`: `{hours + 24·days}:{mm}:{ss}` plus `.f` / `.ff` / `.fff` when the milliseconds are
    /// non-zero (`6:00:00`, `36:00:00`, `12:00:00.086`, `13:30:55.2`).
    public static func excelString(ms: Int64) -> String {
        let c = components(ms)
        var s = "\(c.hours + 24 * c.days):\(d2(c.minutes)):\(d2(c.seconds))"
        let f = c.fraction
        if f != 0 {
            s += "." + (f % 100 == 0 ? "\(f / 100)" : f % 10 == 0 ? d2(f / 10) : d3(f))
        }
        return s
    }

    /// Renderer C (VESSEL-328): `TimeSpan.ToString(@"hh\:mm")` — the hours COMPONENT (0–23), days dropped.
    public static func hoursMinutes(ms: Int64) -> String {
        let c = components(ms)
        return pad2(abs(c.hours)) + ":" + pad2(abs(c.minutes))
    }

    /// .NET `TimeSpan` components (truncating; signs follow the value).
    static func components(_ ms: Int64) -> (days: Int64, hours: Int64, minutes: Int64, seconds: Int64, fraction: Int64) {
        (ms / msPerDay, (ms / 3_600_000) % 24, (ms / 60_000) % 60, (ms / 1_000) % 60, ms % 1_000)
    }

    /// .NET "D2": `-` for negatives, then the absolute value zero-padded to 2.
    static func d2(_ v: Int64) -> String { (v < 0 ? "-" : "") + pad2(abs(v)) }
    static func d3(_ v: Int64) -> String {
        let a = String(abs(v))
        return (v < 0 ? "-" : "") + String(repeating: "0", count: max(0, 3 - a.count)) + a
    }
    static func pad2(_ v: Int64) -> String { v < 10 ? "0\(v)" : "\(v)" }

    /// Milliseconds since midnight of a date-time.
    static func msOfDay(_ dt: NetDateTime) -> Int64 { dt.timeOfDayTicks / 10_000 }
}
