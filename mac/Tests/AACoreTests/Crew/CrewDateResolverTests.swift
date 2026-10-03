// Tests for 09 §3.6 DateResolver: vectors §7.2 (Resolve), §7.3 (Observe/Infer), §7.4 (ExpandYear), and the DECISIONS 09
// fixes Q1 (ambiguity counter), Q2 (adopt on Conflicted), Q6 (no truncation), Q7 (Excel serials), Q8 (ASCII digits),
// Q9 (29 Feb expansion is unreadable).
import Foundation
import Testing
@testable import AACore

@Suite struct CrewDateResolverTests {
    static let today = CrewTestDates.today

    func resolver(_ order: CrewDateOrder = .unknown) -> CrewDateResolver {
        var r = CrewDateResolver(today: Self.today, zone: CrewTestDates.athens)
        if order != .unknown { r.adopt(order) }
        return r
    }

    func d(_ y: Int, _ m: Int, _ day: Int) -> CivilDate { CivilDate(year: y, month: m, day: day)! }

    @Test func blanksPlaceholdersAndZeroDates() {
        // TV: 09 §7.2 rows 1–3
        let r = resolver()
        for s in ["", " ", "\u{00A0}"] { #expect(r.resolve(s) == CrewDateResolution()) }
        #expect(r.resolve(nil) == CrewDateResolution())
        for s in ["N/A", "tbc", "#N/A", "-", "Null", "TBA", "  pending "] { #expect(r.resolve(s) == CrewDateResolution()) }
        for s in ["0", "00/00/0000", "1899-12-30", "30/12/1899", "01/01/1900", "00-00-0000"] {
            #expect(r.resolve(s) == CrewDateResolution(note: "empty date"))
        }
        #expect(CrewDateResolver.isPlaceholder("n.a.") && CrewDateResolver.isPlaceholder("1900-01-01"))
        #expect(!CrewDateResolver.isPlaceholder("2026-01-01") && !CrewDateResolver.isPlaceholder("  "))
    }

    @Test func zeroDateCheckHappensBeforeTimeStrip() {
        // TV: 09 §7.2 "1900-01-01 00:00"
        let r = resolver().resolve("1900-01-01 00:00")
        #expect(r.value == d(1900, 1, 1) && r.raw == "1900-01-01" && !r.dependedOnOrder && r.note == nil)
    }

    @Test func yearFirstCompactAndIso() {
        // TV: 09 §7.2 year-first rows
        let r = resolver()
        for s in ["2026-03-04", "2026/3/4", "2026.03.04"] {
            let x = r.resolve(s)
            #expect(x.value == d(2026, 3, 4) && x.raw == s && x.note == nil)
        }
        #expect(r.resolve("2026-03-04T10:30:00Z") == CrewDateResolution(value: d(2026, 3, 4), raw: "2026-03-04"))
        #expect(r.resolve("2026-03-04 10:30") == CrewDateResolution(value: d(2026, 3, 4), raw: "2026-03-04"))
        #expect(r.resolve("2026-03/04") == CrewDateResolution(raw: "2026-03/04", note: "'2026-03/04' is not a date AA recognises"))
        #expect(r.resolve("2026-02-29") == CrewDateResolution(raw: "2026-02-29", note: "'2026-02-29' is not a date AA recognises"))
        #expect(r.resolve("2024-02-29").value == d(2024, 2, 29))
        #expect(r.resolve("1899-12-31").note == "'1899-12-31' is not a date AA recognises")
        #expect(r.resolve("20260304").value == d(2026, 3, 4))
        #expect(r.resolve("04032026") == CrewDateResolution(raw: "04032026", note: "'04032026' is not a date AA recognises"))
    }

    @Test func monthNames() {
        // TV: 09 §7.2 month-name rows
        let r = resolver()
        for s in ["12 Mar 2026", "12 MARCH 2026", "12 march 2026"] { #expect(r.resolve(s).value == d(2026, 3, 12)) }
        for s in ["March 4, 2026", "Mar 4 2026"] { #expect(r.resolve(s).value == d(2026, 3, 4)) }
        #expect(r.resolve("4th March 2026").value == d(2026, 3, 4))
        #expect(r.resolve("1ST Mar 2026").value == d(2026, 3, 1))
        #expect(r.resolve("12-SEPT-26").value == d(2026, 9, 12))
        #expect(r.resolve("2026 Mar 4").value == d(2026, 3, 4))
        #expect(r.resolve("12 AUG 98", role: .pastOnly).value == d(1998, 8, 12))
        #expect(r.resolve("12 AUG 98", role: .futureLikely).value == d(2098, 8, 12))
        #expect(r.resolve("12-MAR-20", role: .futureLikely).value == d(2120, 3, 12))
        #expect(r.resolve("12 Mar 1850").value == d(1850, 3, 12))
        #expect(r.resolve("Tuesday, 29 September 2026").value == d(2026, 9, 29))      // general-parser fallback
    }

    @Test func decisionsQ6NoTruncationOfValidDates() {
        // DECISIONS 09 Q6 (supersedes the Windows rows "12 AUGUST 2026" → "12 AUGUS", "DECEMBER 1ST 2026", and
        // "12 Mar 2026 10:00" → "12"): T is stripped only after a digit, a time only when the text after the space is H:mm.
        let r = resolver()
        #expect(r.resolve("12 AUGUST 2026").value == d(2026, 8, 12))
        #expect(r.resolve("DECEMBER 1ST 2026").value == d(2026, 12, 1))
        #expect(r.resolve("12 Mar 2026 10:00").value == d(2026, 3, 12))
        #expect(r.resolve("15/07/2026 10:00").value == d(2026, 7, 15))
        // An unreadable value keeps the whole cell text.
        let bad = r.resolve("2026-02-30 08:00")
        #expect(bad.value == nil && bad.raw == "2026-02-30 08:00" && bad.note == "'2026-02-30' is not a date AA recognises")
        #expect(CrewDateResolver.stripTime("2026-03-04T10:30:00Z") == "2026-03-04")
        #expect(CrewDateResolver.stripTime("12 AUGUST 2026") == "12 AUGUST 2026")
        #expect(CrewDateResolver.stripTime("2026-03-04 9:05:00") == "2026-03-04")
        #expect(CrewDateResolver.stripTime("2026-03-04Z") == "2026-03-04")
    }

    @Test func shortYearFirstAndNumeric() {
        // TV: 09 §7.2 short-year and numeric rows
        let r = resolver()
        #expect(r.resolve("98-03-04").value == d(1998, 3, 4))
        #expect(r.resolve("98-03-04", role: .pastOnly).value == d(1998, 3, 4))
        #expect(r.resolve("98-03-04", role: .futureLikely).value == d(2098, 3, 4))
        #expect(r.resolve("45/12/31").value == d(2045, 12, 31))
        #expect(r.resolve("45/12/31", role: .pastOnly).value == d(1945, 12, 31))
        #expect(r.resolve("26-03-04").value == d(2004, 3, 26))
        for s in ["15/07/2026", "15.07.26", "07/15/2026"] { #expect(r.resolve(s).value == d(2026, 7, 15)) }
        #expect(r.resolve("15-07-98", role: .pastOnly).value == d(1998, 7, 15))
        for s in ["31/02/2026", "13/13/2026", "02/30/2026", "31/04/2026"] {
            #expect(r.resolve(s) == CrewDateResolution(raw: s, note: "'\(s)' is not a real date"))
        }
        #expect(r.resolve("15/07/202").note == "'15/07/202' is not a date AA recognises")
        #expect(r.resolve("15/07/202").dependedOnOrder == false)
    }

    @Test func ambiguousByOrder() {
        // TV: 09 §7.2 ambiguous rows
        let day = resolver(.dayFirst).resolve("3/4/2026")
        #expect(day == CrewDateResolution(value: d(2026, 4, 3), raw: "3/4/2026", dependedOnOrder: true,
                                          note: "read as 3 Apr 2026 (day first); would be 4 Mar 2026 if month first"))
        let month = resolver(.monthFirst).resolve("3/4/2026")
        #expect(month == CrewDateResolution(value: d(2026, 3, 4), raw: "3/4/2026", dependedOnOrder: true,
                                            note: "read as 4 Mar 2026 (month first); would be 3 Apr 2026 if day first"))
        let conflicted = resolver(.conflicted).resolve("3/4/2026")
        #expect(conflicted == CrewDateResolution(raw: "3/4/2026", dependedOnOrder: true,
                                                 note: "'3/4/2026' left unread — this file writes dates both ways, so neither reading is safe"))
        let unknown = resolver().resolve("03/04/2026")
        #expect(unknown == CrewDateResolution(raw: "03/04/2026", dependedOnOrder: true,
                                              note: "'03/04/2026' could be 3 Apr or 4 Mar, and nothing in the file says which"))
        let same = resolver(.dayFirst).resolve("12/12/2026")
        #expect(same.value == d(2026, 12, 12) && same.dependedOnOrder
                && same.note == "read as 12 Dec 2026 (day first); would be 12 Dec 2026 if month first")
        let zero = resolver(.dayFirst).resolve("00/05/2026")
        #expect(zero.value == nil && zero.dependedOnOrder
                && zero.note == "'00/05/2026' could be 0 May or 5 ?, and nothing in the file says which")
        let short = resolver(.dayFirst).resolve("3/4/26")
        #expect(short.value == d(2026, 4, 3) && short.note?.hasPrefix("read as 3 Apr 2026") == true)
    }

    @Test func observeAndInfer() {
        // TV: 09 §7.3
        func run(_ values: [String], fallback: CrewDateOrder = .unknown) -> CrewDateResolver {
            var r = resolver()
            values.forEach { r.observe($0) }
            r.infer(fallback: fallback)
            return r
        }
        var r = run(["15/07/2026", "03/04/2026"])
        #expect(r.order == .dayFirst && r.decisiveCount == 1)
        r = run(["07/15/2026", "03/04/2026"])
        #expect(r.order == .monthFirst && r.decisiveCount == 1)
        r = run(["15/07/2026", "07/15/2026"])
        #expect(r.order == .conflicted && r.decisiveCount == 0 && r.isConflicted)
        r = run(["03/04/2026", "2026-07-15", "12 Mar 2026"])
        #expect(r.order == .unknown && r.decisiveCount == 0)
        r = run(["15/07/2026 10:00"])
        #expect(r.order == .unknown && r.decisiveCount == 0)
        r = run(["45/03/2026", "13/13/2026", "15/07/202"])
        #expect(r.order == .unknown)
        r = run(["31/02/2026"])
        #expect(r.order == .dayFirst && r.decisiveCount == 1)
        r = run(Array(repeating: "15/07/2026", count: 60))
        #expect(r.order == .dayFirst && r.decisiveCount == 50 && r.dayWitnesses.count == 50)
        r = run([], fallback: .dayFirst)
        #expect(r.order == .dayFirst && r.decisiveCount == 0)
        r = run(["15/07/2026", "07/15/2026"], fallback: .dayFirst)
        #expect(r.order == .conflicted && r.decisiveCount == 0)
    }

    @Test func decisionsQ1AmbiguityCounter() {
        // DECISIONS 09 Q1: only values that Resolve would read by the convention count.
        var r = resolver()
        ["2026-07-15", "12 Mar 2026", "15/07/2026", "N/A", "00/00/0000", "26-03-04", ""].forEach { r.observe($0) }
        #expect(r.ambiguousCount == 0)
        r.observe("03/04/2026")
        r.observe("03/04/2026 10:30")        // stripped by Resolve, so it counts
        r.observe("3.4.26")
        #expect(r.ambiguousCount == 3)
    }

    @Test func decisionsQ2AdoptOnConflicted() {
        // DECISIONS 09 Q2: the answer takes effect for a Conflicted file.
        var r = resolver()
        ["15/07/2026", "07/15/2026", "03/04/2026"].forEach { r.observe($0) }
        r.infer()
        #expect(r.order == .conflicted)
        r.adopt(.dayFirst, byUser: true)
        #expect(r.order == .dayFirst && r.orderChosenByUser && r.conflictOverridden && r.decisiveCount == 0)
        #expect(r.resolve("03/04/2026").value == d(2026, 4, 3))
        #expect(r.resolve("07/15/2026").value == d(2026, 7, 15))           // unambiguous values stay unambiguous
    }

    @Test func expandYear() {
        // TV: 09 §7.4 (today.year 2026)
        let r = resolver()
        #expect([26, 68, 69, 0].map { r.expandYear($0, role: .any) } == [2026, 2068, 1969, 2000])
        #expect([26, 27, 98, 5].map { r.expandYear($0, role: .pastOnly) } == [2026, 1927, 1998, 2005])
        #expect([20, 21, 30, 98, 69].map { r.expandYear($0, role: .futureLikely) } == [2120, 2021, 2030, 2098, 2069])
        #expect(r.expandYear(26, role: .pastOnly, alreadyFull: true) == 26)
        #expect(r.expandYear(150, role: .futureLikely) == 150)
    }

    @Test func tryMakeAndSerials() {
        #expect(CrewDateResolver.tryMake(1899, 12, 31) == nil && CrewDateResolver.tryMake(2200, 1, 1) == nil)
        #expect(CrewDateResolver.tryMake(2199, 12, 31) == d(2199, 12, 31))
        #expect(CrewDateResolver.tryMake(2026, 2, 29) == nil)
        #expect(CrewDateResolver.fromExcelSerial(46096) == d(2026, 3, 15))
        #expect(CrewDateResolver.fromExcelSerial(46096.75) == d(2026, 3, 15))
        #expect(CrewDateResolver.fromExcelSerial(1) == d(1899, 12, 31))
        #expect(CrewDateResolver.fromExcelSerial(0.5) == nil && CrewDateResolver.fromExcelSerial(73_052) == nil)
        #expect(CrewDateResolver.fromExcelSerial(.nan) == nil && CrewDateResolver.fromExcelSerial(.infinity) == nil)
        #expect(CrewDateResolver.fromExcelSerial(1, use1904: true) == d(1904, 1, 2))
    }

    @Test func decisionsQ7PlainNumberSerials() {
        // DECISIONS 09 Q7: a five-digit plain number in a date column reads as an Excel serial.
        var r = resolver()
        #expect(r.resolve("46096").value == d(2026, 3, 15))
        #expect(r.resolve("1234").note == "'1234' is not a date AA recognises")
        r.use1904 = true
        #expect(r.resolve("46096").value == d(2030, 3, 16))
    }

    @Test func decisionsQ8AsciiDigitsOnly() {
        // DECISIONS 09 Q8 / 06 D6: non-ASCII digits never crash and are not read.
        let r = resolver()
        let x = r.resolve("\u{0661}\u{0665}/07/2026")
        #expect(x.value == nil && x.note?.hasSuffix("is not a date AA recognises") == true)
        var o = resolver()
        o.observe("\u{0661}\u{0665}/07/2026")
        o.infer()
        #expect(o.order == .unknown)
    }

    @Test func decisionsQ9LeapDayExpansionIsUnreadable() {
        // DECISIONS 09 Q9: 29-Feb-00 FutureLikely → 2100-02-29 does not exist → unreadable, never a crash.
        let r = resolver()
        let x = r.resolve("29-Feb-00", role: .futureLikely)
        #expect(x.value == nil && x.raw == "29-Feb-00" && x.note == "'29-Feb-00' is not a real date")
        #expect(r.resolve("29-Feb-00", role: .pastOnly).value == d(2000, 2, 29))
    }

    @Test func longTextIsEnglish() {
        #expect(CrewDateResolver.longText(d(2026, 4, 3)) == "3 Apr 2026")
        #expect(CrewDateResolver.longText(d(1850, 12, 31)) == "31 Dec 1850")
    }
}
