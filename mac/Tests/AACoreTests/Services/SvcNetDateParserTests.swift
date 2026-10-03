// Tests for 09 §7.1 (`CrewMember.ParseDate` / `NetDateParser`), 01 §7.10 ParseDate + ContractStatus rows that depend
// on the parser, 10 VESSEL-327 note / §X.10 Q20/Q21 (time-only → today), 09 §3.2 (`CrewText.Norm`).
import Foundation
import Testing
@testable import AACore

@Suite struct SvcNetDateParserTests {
    static let today = CivilDate(iso: "2026-09-29")!

    private func p(_ s: String?) -> String? {
        NetDateParser.parse(s, zone: TZ.athens, today: Self.today)?.format(.isoDate)
    }

    private func full(_ s: String) -> String? {
        NetDateParser.parse(s, zone: TZ.athens, today: Self.today)?.format(.isoSecond)
    }

    @Test func specVectors() {
        // TV: 09 §7.1
        #expect(p(nil) == nil && p("") == nil && p("   ") == nil)
        #expect(p("2026-03-15") == "2026-03-15" && p("2026/03/15") == "2026-03-15" && p("2026.03.15") == "2026-03-15")
        #expect(p(" 2026-03-15 ") == "2026-03-15")
        #expect(p("2026-3-5") == "2026-03-05")
        #expect(p("03/04/2026") == "2026-03-04" && p("03-04-2026") == "2026-03-04" && p("03.04.2026") == "2026-03-04")
        #expect(p("3/4/26") == "2026-03-04" && p("3/4/50") == "1950-03-04" && p("3/4/49") == "2049-03-04")
        #expect(p("15/07/2026") == nil)
        #expect(p("15 Jul 2026") == "2026-07-15" && p("Jul 15, 2026") == "2026-07-15" && p("July 15 2026") == "2026-07-15")
        #expect(p("2026-03-15T10:30:00") == "2026-03-15")
        #expect(full("2026-03-15T10:30:00") == "2026-03-15 10:30:00")
        #expect(p("2026-02-30") == nil)
        #expect(p("garbage") == nil && p("12") == nil)
    }

    @Test func specOneVectors() {
        // TV: 01 §7.10 ParseDate
        #expect(p("2026-03-04") == "2026-03-04" && p("2026/03/04") == "2026-03-04" && p("2026.03.04") == "2026-03-04")
        #expect(p(" 2026-03-04 ") == "2026-03-04" && p("03/04/2026") == "2026-03-04")
        #expect(p("12 Mar 2026") == "2026-03-12" && p("abc") == nil)
        let exact = NetDateParser.parse("2026-03-04")!
        #expect(exact.kind == .unspecified && exact.originalText == nil && exact.timeOfDayTicks == 0)
    }

    @Test func moreShapes() {
        // 09 §6.3 shape list
        #expect(p("2026/3/5") == "2026-03-05" && p("2026.3.5") == "2026-03-05" && p("2026-03/05") == "2026-03-05")
        #expect(p("3/4") == "2026-03-04")                              // no year → today's year
        #expect(p("15 Jul") == "2026-07-15")
        #expect(p("15-Jul-26") == "2026-07-15" && p("15-jul-2026") == "2026-07-15")
        #expect(p("2026 Jul 15") == "2026-07-15" && p("July 2026") == "2026-07-01")
        #expect(p("Wednesday, July 15, 2026") == "2026-07-15" && p("Wed, 15 Jul 2026") == "2026-07-15")
        #expect(p("Tuesday, July 15, 2026") == nil)                    // the day name must match
        #expect(p("Sept 15 2026") == nil && p("15 Foo 2026") == nil)
        #expect(full("2026-03-15 10:30") == "2026-03-15 10:30:00")
        #expect(full("3/15/2023 12:00:00 AM") == "2023-03-15 00:00:00")
        #expect(full("3/15/2023 1:05:09 PM") == "2023-03-15 13:05:09")
        #expect(full("3/15/2023 12:30 PM") == "2023-03-15 12:30:00")
        #expect(p("3/15/2023 13:00 PM") == nil)
        #expect(full("2026-03-15T10:30:00.1234567") == "2026-03-15 10:30:00")
        let ticks: Int64 = 378_001_234_567                            // 10:30:00 + 0.1234567 s (7 digits used)
        #expect(NetDateParser.parse("2026-03-15T10:30:00.123456789")?.timeOfDayTicks == ticks)
        #expect(p("2026-03-15 25:00") == nil && p("2026-03-15 10:60") == nil)
        #expect(p("٣/٤/٢٠٢٦") == nil)                                 // non-ASCII digits are not digits here
        #expect(p("1/2/3/4") == nil && p("10 PM") == "2026-09-29")
        #expect(full("10 PM") == "2026-09-29 22:00:00")
    }

    @Test func zonesConvertToLocalLikeDotNet() {
        // 09 §6.3: a trailing Z or offset converts to the local wall clock (can move the day)
        let z = NetDateParser.parse("2026-03-15T22:30:00Z", zone: TZ.athens)!
        #expect(z.kind == .local && z.format(.isoSecond) == "2026-03-16 00:30:00")
        let off = NetDateParser.parse("2026-03-15T10:30:00-05:00", zone: TZ.athens)!
        #expect(off.format(.isoSecond) == "2026-03-15 17:30:00" && off.kind == .local)
        let off2 = NetDateParser.parse("2026-03-15T10:30:00+0530", zone: TZ.utc)!
        #expect(off2.format(.isoSecond) == "2026-03-15 05:00:00")
        #expect(NetDateParser.parse("2026-03-15 10:30 GMT", zone: TZ.athens)?.format(.isoSecond) == "2026-03-15 12:30:00")
        #expect(NetDateParser.parse("10:30 2026-03-15", zone: TZ.athens)?.format(.isoSecond) == "2026-03-15 10:30:00")
    }

    @Test func timeOnlyMeansToday() {
        // TV: 10 X.8.1 M2/M2a/M2c (B+ = {today}); §X.10 Q20 (hour ≥ 24 → nil)
        #expect(full("12:00:00") == "2026-09-29 12:00:00")
        #expect(full("6:00:00") == "2026-09-29 06:00:00")
        #expect(full("12:00:00.086") == "2026-09-29 12:00:00")
        #expect(full("22:00") == "2026-09-29 22:00:00")
        #expect(full("10:15 pm") == "2026-09-29 22:15:00")
        #expect(p("36:00:00") == nil && p("12:61") == nil)
        let defaultToday = NetDateParser.parse("12:00")
        #expect(defaultToday?.civilDate == NetDateTime(date: Date(), kind: .local).civilDate)
    }

    @MainActor @Test func crewModelUsesTheSharedParser() {
        // 01 §7.10 ContractStatusOn rows that need the general parser; ShipJob.dueDateValue
        let today = CivilDate(iso: "2026-09-29")!
        let m = CrewMember()
        m.signOffDate = "31/12/2026"
        #expect(m.contractStatus(on: today) == .unknown)
        m.signOffDate = "10/30/2026"
        #expect(m.contractStatus(on: today) == .dueSoon)
        m.signOffDate = "Oct 29, 2026"
        #expect(m.daysUntilSignOff(today: today) == 30 && m.contractStatus(on: today) == .critical)
        #expect(CrewMember.parseDate("03/04/2026")?.format(.isoDate) == "2026-03-04")
    }

    @Test func crewTextNorm() {
        // TV: 09 §3.2
        #expect(CrewText.norm("") == "")
        #expect(CrewText.norm("  First\u{00A0}\tName \r\n") == "first name")
        #expect(CrewText.norm("Seaman\u{2019}s Book") == "seaman's book")
        #expect(CrewText.norm("DATE  OF\nBIRTH") == "date of birth")
        #expect(CrewText.norm("ÉCOLE") == "école")
        #expect(CrewText.norm("\u{3000}Rank\u{2003}Code\u{3000}") == "rank code")
    }
}
