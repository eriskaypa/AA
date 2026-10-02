// TV: 01 §7.5 (dates table, reads in New York, ticks, equality), 01 §4.1.5, App. A12 (DST ambiguous / gap write
//     offsets), A13 (read shapes), ARCHITECTURE.md §3.4 (originalText round trip, mutation clears it, toLocalTime).
import Foundation
import Testing
@testable import AACore

@Suite struct NetDateTimeTests {
    // TV: 01 §7.5 write table
    @Test func writeTable() {
        #expect(NetDateTime(year: 2026, month: 10, day: 1, kind: .unspecified).jsonString(zone: TZ.athens)
                == "2026-10-01T00:00:00")
        #expect(NetDateTime(year: 2026, month: 9, day: 29, hour: 8, minute: 15, second: 30, fractionTicks: 1_234_560,
                            kind: .utc).jsonString(zone: TZ.athens) == "2026-09-29T08:15:30.123456Z")
        #expect(NetDateTime(year: 2026, month: 9, day: 29, hour: 11, minute: 15, second: 30, fractionTicks: 5_000_000,
                            kind: .local).jsonString(zone: TZ.athens) == "2026-09-29T11:15:30.5+03:00")
        #expect(NetDateTime(year: 2026, month: 1, day: 15, hour: 9, kind: .local).jsonString(zone: TZ.london)
                == "2026-01-15T09:00:00+00:00")
        #expect(NetDateTime(year: 2026, month: 1, day: 15, hour: 9, kind: .local).jsonString(zone: TZ.kolkata)
                == "2026-01-15T09:00:00+05:30")
    }

    @Test func fractionTrimming() {
        let base = NetDateTime(year: 2026, month: 10, day: 1, kind: .unspecified)
        #expect(base.addingTicks(1_000_000).jsonString() == "2026-10-01T00:00:00.1")
        #expect(base.addingTicks(1_234_567).jsonString() == "2026-10-01T00:00:00.1234567")
        #expect(base.addingTicks(1).jsonString() == "2026-10-01T00:00:00.0000001")
        #expect(NetDateTime(ticks: 0, kind: .unspecified).jsonString() == "0001-01-01T00:00:00")
        #expect(NetDateTime(ticks: NetDateTime.maxTicks, kind: .unspecified).jsonString() == "9999-12-31T23:59:59.9999999")
    }

    // TV: 01 §7.5 reads (zone America/New_York)
    @Test func readsInNewYork() throws {
        let a = try #require(NetDateTime(parsing: "2026-10-01T00:00:00+03:00", zone: TZ.newYork))
        #expect(a.kind == .local)
        #expect(a.format(.isoSecond) == "2026-09-30 17:00:00")
        #expect(a.jsonString(zone: TZ.newYork) == "2026-10-01T00:00:00+03:00")        // untouched → original text
        #expect(a.formattedISO(zone: TZ.newYork) == "2026-09-30T17:00:00-04:00")      // re-written form
        let b = try #require(NetDateTime(parsing: "2026-10-01", zone: TZ.newYork))
        #expect(b.kind == .unspecified && b.formattedISO() == "2026-10-01T00:00:00")
        let c = try #require(NetDateTime(parsing: "2026-10-01T00:00Z", zone: TZ.newYork))
        #expect(c.kind == .utc && c.formattedISO() == "2026-10-01T00:00:00Z")
        #expect(NetDateTime(parsing: "2026-10-01 00:00:00") == nil)
        #expect(NetDateTime(parsing: "01/10/2026") == nil)
    }

    // TV: 01 App. A13 read shapes (Mac rule until the golden exists)
    @Test func readShapes() {
        #expect(NetDateTime(parsing: "2026-10-01T00:00")?.kind == .unspecified)
        #expect(NetDateTime(parsing: "2026-10-01T00:00:00.1234567")?.ticks == 639_264_096_001_234_567)
        #expect(NetDateTime(parsing: "2026-10-01T00:00:00.12345678")?.ticks == 639_264_096_001_234_567)   // 8 digits truncated
        #expect(NetDateTime(parsing: "2026-10-01T00:00:00.1234567890123456") != nil)                      // 16 digits
        #expect(NetDateTime(parsing: "2026-10-01T00:00:00.12345678901234567") == nil)                     // 17 digits
        #expect(NetDateTime(parsing: "2026-10-01T00:00:00.") == nil)
        #expect(NetDateTime(parsing: "2026-10-01T00:00:00z") == nil)
        #expect(NetDateTime(parsing: "2026-10-01T00:00:00+0300") == nil)
        #expect(NetDateTime(parsing: "2026-10-01T00:00:00+03") == nil)
        #expect(NetDateTime(parsing: "2026-10-01T00:00:00+14:00") != nil)
        #expect(NetDateTime(parsing: "2026-10-01T00:00:00+14:01") == nil)
        #expect(NetDateTime(parsing: "2026-10-01T00:00:00-00:00", zone: TZ.utc)?.kind == .local)
        #expect(NetDateTime(parsing: " 2026-10-01") == nil)
        #expect(NetDateTime(parsing: "2026-10-01T24:00:00") == nil)
        #expect(NetDateTime(parsing: "2026-02-29") == nil)
        #expect(NetDateTime(parsing: "2024-02-29") != nil)
        #expect(NetDateTime(parsing: "0001-01-01T00:00:00+03:00") == nil)                    // before MinValue in UTC
        #expect(NetDateTime(parsing: "9999-12-31T23:59:59.9999999-05:00", zone: TZ.newYork) == nil)
        #expect(NetDateTime(parsing: "2026-10-01T00:00:60") == nil)
    }

    @Test func ticksAndEquality() {
        #expect(NetDateTime(year: 2026, month: 10, day: 1, kind: .unspecified).ticks == 639_264_096_000_000_000)
        #expect(NetDateTime(year: 1970, month: 1, day: 1, kind: .utc).ticks == NetDateTime.unixEpochTicks)
        let local = NetDateTime(year: 2026, month: 10, day: 1, kind: .local)
        let unspecified = NetDateTime(year: 2026, month: 10, day: 1, kind: .unspecified)
        #expect(local == unspecified)                                                     // ticks only, like .NET
        #expect(local.hashValue == unspecified.hashValue)
        #expect(unspecified < unspecified.addingTicks(1))
    }

    // ARCHITECTURE.md §3.4 — originalText kept until edited
    @Test func originalTextRoundTrip() throws {
        let texts = ["2026-09-29T11:15:29.9876543+03:00", "2026-10-01", "2026-10-01T00:00Z", "2026-10-01T00:00:00.100",
                     "2026-09-28T00:00:00+02:00"]
        for t in texts {
            let d = try #require(NetDateTime(parsing: t, zone: TZ.newYork))
            #expect(d.jsonString(zone: TZ.kolkata) == t)
            #expect(d.originalText == t)
            #expect(d.addingDays(0).originalText == nil)
            #expect(d.asCalendarDate.originalText == nil)
            #expect(d.addingDays(1).jsonString(zone: TZ.newYork) != t)
            #expect(d.date.originalText == nil)
        }
    }

    @Test func calendarDates() {
        let d = CivilDate(year: 2026, month: 10, day: 5)!
        let c = NetDateTime.calendarDate(d)
        #expect(c.kind == .unspecified && c.jsonString() == "2026-10-05T00:00:00")
        #expect(NetDateTime.calendarDateTime(d, minutes: 510).jsonString() == "2026-10-05T08:30:00")
        let local = NetDateTime(parsing: "2026-10-05T10:00:00+03:00", zone: TZ.athens)!
        let asCal = local.asCalendarDate
        #expect(asCal.kind == .unspecified && asCal.offsetHint == nil && asCal.jsonString() == "2026-10-05T10:00:00")
        #expect(local.civilDate == d && local.minutesOfDay == 600)
    }

    @Test func arithmetic() {
        let jan31 = NetDateTime(year: 2027, month: 1, day: 31, hour: 7, kind: .local)
        #expect(jan31.addingMonths(1).format(.isoMinute) == "2027-02-28 07:00")
        #expect(jan31.addingMonths(1).kind == .local)
        #expect(NetDateTime(year: 2028, month: 2, day: 29, kind: .unspecified).addingYears(1).format(.isoDate) == "2029-02-28")
        #expect(jan31.addingDays(-31).format(.isoDate) == "2026-12-31")
        #expect(jan31.date.format(.isoSecond) == "2027-01-31 00:00:00")
        #expect(jan31.date.kind == .local)
    }

    // TV: ARCHITECTURE.md §3.4 / 01 §3.22 — ToLocalTime treats Unspecified as UTC
    @Test func toLocalTime() {
        let u = NetDateTime(year: 2026, month: 9, day: 29, hour: 8, minute: 15, second: 30, kind: .unspecified)
        let l = u.toLocalTime(zone: TZ.athens)
        #expect(l.kind == .local)
        #expect(l.format(.isoSecond) == "2026-09-29 11:15:30")
        #expect(l.jsonString(zone: TZ.athens) == "2026-09-29T11:15:30+03:00")
        let utc = NetDateTime(year: 2026, month: 9, day: 29, hour: 8, minute: 15, second: 30, kind: .utc)
        #expect(utc.toLocalTime(zone: TZ.athens) == l)
        #expect(l.toLocalTime(zone: TZ.newYork) == l)                                   // Local → unchanged
    }

    // TV: 01 App. A12 — ambiguous / invalid wall clocks write the standard offset; values from an instant keep theirs
    @Test func dstOffsets() {
        let nyAmbiguous = NetDateTime(year: 2026, month: 11, day: 1, hour: 1, minute: 30, kind: .local)
        #expect(nyAmbiguous.jsonString(zone: TZ.newYork) == "2026-11-01T01:30:00-05:00")
        let nyGap = NetDateTime(year: 2026, month: 3, day: 8, hour: 2, minute: 30, kind: .local)
        #expect(nyGap.jsonString(zone: TZ.newYork) == "2026-03-08T02:30:00-05:00")
        let athensAmbiguous = NetDateTime(year: 2026, month: 10, day: 25, hour: 3, minute: 30, kind: .local)
        #expect(athensAmbiguous.jsonString(zone: TZ.athens) == "2026-10-25T03:30:00+02:00")
        let athensGap = NetDateTime(year: 2026, month: 3, day: 29, hour: 3, minute: 30, kind: .local)
        #expect(athensGap.jsonString(zone: TZ.athens) == "2026-03-29T03:30:00+02:00")
        // The first 01:30 in New York (05:30Z, still EDT) keeps its daylight offset through the hint.
        let fromUTC = NetDateTime(year: 2026, month: 11, day: 1, hour: 5, minute: 30, kind: .utc).toLocalTime(zone: TZ.newYork)
        #expect(fromUTC.format(.isoMinute) == "2026-11-01 01:30")
        #expect(fromUTC.jsonString(zone: TZ.newYork) == "2026-11-01T01:30:00-04:00")
        let second = NetDateTime(year: 2026, month: 11, day: 1, hour: 6, minute: 30, kind: .utc).toLocalTime(zone: TZ.newYork)
        #expect(second.jsonString(zone: TZ.newYork) == "2026-11-01T01:30:00-05:00")
        #expect(fromUTC.addingTicks(0).jsonString(zone: TZ.newYork) == "2026-11-01T01:30:00-05:00")   // hint cleared
        #expect(NetDateTime(parsing: "2026-11-01T05:30:00Z", zone: TZ.newYork)!.toLocalTime(zone: TZ.newYork)
                .formattedISO(zone: TZ.newYork) == "2026-11-01T01:30:00-04:00")
        #expect(NetDateTime(parsing: "2026-03-08T02:30:00-05:00", zone: TZ.newYork)!.formattedISO(zone: TZ.newYork)
                == "2026-03-08T03:30:00-04:00")
        #expect(NetDateTime(year: 2026, month: 7, day: 1, hour: 12, kind: .local).jsonString(zone: TZ.newYork)
                == "2026-07-01T12:00:00-04:00")
    }

    @Test func formats() {
        let d = NetDateTime(year: 2026, month: 9, day: 27, hour: 12, minute: 5, second: 9, fractionTicks: 1_200_000, kind: .local)
        #expect(d.format(.isoDate) == "2026-09-27")
        #expect(d.format(.isoMinute) == "2026-09-27 12:05")
        #expect(d.format(.isoSecond) == "2026-09-27 12:05:09")
        #expect(d.format(.time) == "12:05")
        #expect(d.format(.stampMinute) == "20260927-1205")
        #expect(d.format(.stampSecond) == "20260927-120509")
        #expect(d.format(.isoLocalSeconds) == "2026-09-27T12:05:09")
        #expect(d.format(.isoLocal7) == "2026-09-27T12:05:09.1200000")
        #expect(d.format(.roundTripO, zone: TZ.athens) == "2026-09-27T12:05:09.1200000+03:00")
        #expect(NetDateTime(year: 2026, month: 9, day: 27, hour: 12, kind: .utc).format(.roundTripO) == "2026-09-27T12:00:00.0000000Z")
        #expect(NetDateTime(year: 2026, month: 9, day: 27, hour: 12, kind: .unspecified).format(.roundTripO) == "2026-09-27T12:00:00.0000000")
    }

    @Test func clocksAndInstants() {
        let clock = FixedClock(local: "2026-09-29T14:05:00", zone: TZ.athens)
        #expect(clock.now().jsonString(zone: TZ.athens) == "2026-09-29T14:05:00+03:00")
        #expect(clock.utcNow().jsonString() == "2026-09-29T11:05:00Z")
        #expect(clock.today().iso == "2026-09-29")
        let d = NetDateTime(date: clock.instant(), kind: .unspecified, zone: TZ.newYork)
        #expect(d.format(.isoMinute) == "2026-09-29 07:05")
        #expect(clock.now().foundationDate(zone: TZ.athens) == clock.instant())
        #expect(clock.utcNow().foundationDate() == clock.instant())
    }
}
