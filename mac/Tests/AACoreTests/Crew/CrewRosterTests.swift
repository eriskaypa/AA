// Tests for 09 vectors §7.8 (Key, FullName, ContractStatus, expiry text, ExpiringCount, CheckExpiries line), §7.9
// (sorting), §7.10 (search), the roster rows / status line / card texts (CREW-013…025) and DECISIONS 09 Q4.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct CrewRosterTests {
    static let today = CrewTestDates.today

    func member(first: String = "", middle: String = "", last: String = "", id: String = "", signOff: String = "",
                dob: String = "", rank: String = "", code: String = "", nat: String = "", vessel: String = "") -> CrewMember {
        let m = CrewMember()
        m.firstName = first; m.middleName = middle; m.lastName = last; m.employeeId = id; m.signOffDate = signOff
        m.dateOfBirth = dob; m.rank = rank; m.rankCode = code; m.nationality = nat; m.vessel = vessel
        return m
    }

    @Test func keyAndFullName() {
        // TV: 09 §7.8 Key / FullName
        #expect(member(first: "Juan", id: "123").key == "123")
        #expect(member(first: "Juan").key == "Juan")
        #expect(member(last: "Cruz").key == "Cruz")
        #expect(member().key == "")
        #expect(member(first: "Juan", middle: " ", last: "Cruz").fullName == "Juan Cruz")
        #expect(member(first: " A", last: "B").fullName == " A B")
    }

    @Test func expiryTable() {
        // TV: 09 §7.8 table
        let rows: [(String, Int?, ContractStatus, String, CrewExpiryTone)] = [
            ("2026-09-28", -1, .expired, "\u{26A0} Contract ended 1d ago  (2026-09-28)", .red),
            ("2026-09-29", 0, .critical, "\u{26A0} Signs off today  (2026-09-29)", .red),
            ("2026-10-29", 30, .critical, "\u{26A0} Signs off in 30d  (2026-10-29)", .orange),
            ("2026-10-30", 31, .dueSoon, "Signs off in 31d  (2026-10-30)", .amber),
            ("2026-11-28", 60, .dueSoon, "Signs off in 60d  (2026-11-28)", .amber),
            ("2026-11-29", 61, .ok, "Signs off in 61d  (2026-11-29)", .green),
            ("", nil, .unknown, "", .neutral),
            ("garbage", nil, .unknown, "", .neutral),
        ]
        var crew: [CrewMember] = []
        for (date, days, status, text, tone) in rows {
            let m = member(signOff: date)
            crew.append(m)
            #expect(CrewStoredDate.daysUntilSignOff(m, today: Self.today) == days)
            #expect(m.daysUntilSignOff(today: Self.today) == days)              // F1's model agrees on these
            #expect(CrewStoredDate.contractStatus(m, today: Self.today) == status)
            #expect(m.contractStatus(on: Self.today) == status)
            let e = CrewExpiry.expiry(m, today: Self.today)
            #expect(e.text == text && e.tone == tone)
        }
        #expect(CrewExpiry.expiringCount(crew, today: Self.today) == 5)
        #expect(CrewExpiry.noSignOffDate == "No sign-off date on file — contract expiry can't be tracked.")
        #expect(ContractStatus.allCases.map(\.name) == ["Unknown", "Ok", "DueSoon", "Critical", "Expired"])
    }

    @Test func badgeAndReport() {
        // TV: 09 CREW-002, CREW-050, §7.8 last row
        #expect(CrewExpiry.badgeText(3) == "Crew  \u{26A0} 3" && CrewExpiry.badgeText(0) == "Crew")
        let a = member(first: "Juan", last: "Cruz", signOff: "2026-09-28", rank: "Master", code: "MAST")
        let b = member(first: "Ann", signOff: "2026-10-05", rank: "Cook")
        let c = member(first: "Zed", signOff: "2026-09-29", rank: "AB", code: "AB")
        let far = member(first: "Far", signOff: "2027-01-01")
        let due = CrewExpiry.due([b, far, a, c], today: Self.today)
        #expect(due.map(\.member.firstName) == ["Juan", "Zed", "Ann"])
        #expect(CrewExpiry.reportLine(a, days: -1) == "  \u{2022}  Juan Cruz  (Master (MAST))  \u{2014}  2026-09-28  [OVERDUE by 1d]")
        #expect(CrewExpiry.reportLine(c, days: 0).hasSuffix("[signs off TODAY]"))
        #expect(CrewExpiry.reportLine(b, days: 6) == "  \u{2022}  Ann  (Cook)  \u{2014}  2026-10-05  [in 6d]")
        #expect(CrewExpiry.reportMessage(due).hasPrefix("3 crew contract(s) overdue or due within 60 days:\n\n  \u{2022}  Juan Cruz"))
        #expect(CrewExpiry.reportMessage(due).components(separatedBy: "\n").count == 5)
        #expect(CrewExpiry.noneMessage == "No crew contracts are overdue or due within 60 days.")
    }

    @Test func decisionsQ4AmbiguousStoredDatesAreNotMisread() {
        // DECISIONS 09 Q4: "03/04/2026" left unread by the import is not silently read as 4 March.
        let m = member(signOff: "03/04/2026")
        #expect(CrewStoredDate.isAmbiguous("03/04/2026") && CrewStoredDate.isAmbiguous("3.4.26"))
        #expect(!CrewStoredDate.isAmbiguous("03/03/2026") && !CrewStoredDate.isAmbiguous("15/07/2026"))
        #expect(!CrewStoredDate.isAmbiguous("2026-03-04"))
        #expect(CrewStoredDate.daysUntilSignOff(m, today: Self.today) == nil)
        #expect(CrewExpiry.expiry(m, today: Self.today).text == "")
        #expect(CrewStoredDate.civil("2026-3-4") == CivilDate(year: 2026, month: 3, day: 4))
        #expect(CrewStoredDate.civil("03/03/2026") == CivilDate(year: 2026, month: 3, day: 3))
    }

    @Test func sortModes() {
        // TV: 09 §7.9
        let a = member(first: "John", last: "Smith", id: "20", signOff: "2026-10-01", dob: "1990-01-01")
        let b = member(first: "Ann")
        let c = member(first: "Zed", last: "adams", id: "100", signOff: "2026-09-01", dob: "1985-05-05")
        let crew = [a, b, c]
        func names(_ mode: CrewSortMode) -> [String] {
            CrewSort.sorted(crew, mode: mode, today: Self.today).map(\.firstName)
        }
        #expect(names(.signOffDate) == ["Zed", "John", "Ann"])
        #expect(names(.lastName) == ["Zed", "John", "Ann"])
        #expect(names(.firstName) == ["Ann", "John", "Zed"])
        #expect(names(.cid) == ["Zed", "John", "Ann"])
        #expect(names(.birthDate) == ["Zed", "John", "Ann"])
        // Ties keep roster order.
        let t1 = member(first: "X", id: "a"), t2 = member(first: "x", id: "b")
        #expect(CrewSort.sorted([t2, t1], mode: .firstName, today: Self.today).map(\.employeeId) == ["b", "a"])
        // OrdinalIgnoreCase: "_" sorts after letters.
        let u = member(last: "_z"), l = member(last: "b")
        #expect(CrewSort.sorted([u, l], mode: .lastName, today: Self.today).first === l)
    }

    @Test func sortModePersistence() {
        // TV: 09 CREW-015, §4.5
        #expect(CrewSortMode.allCases.map(\.label) == ["Sign-off date", "Last name", "First name", "CID", "Birth date"])
        #expect(CrewSortMode.allCases.map(\.name) == ["SignOffDate", "LastName", "FirstName", "Cid", "BirthDate"])
        #expect(CrewSortMode(persisted: nil) == .signOffDate && CrewSortMode(persisted: "Cid") == .cid)
        #expect(CrewSortMode(persisted: "cid") == .signOffDate && CrewSortMode(persisted: "4") == .birthDate)
        #expect(CrewSortMode(persisted: "9") == .signOffDate && CrewSortMode(persisted: "") == .signOffDate)
    }

    @Test func search() {
        // TV: 09 §7.10
        let m = member(first: "Juan", last: "Cruz", id: "A1234", rank: "Master", code: "MAST", nat: "Philippines")
        m.signOnPort = "SGSIN"
        func hit(_ q: String) -> Bool { !CrewRoster.filter([m], query: q, expiringOnly: false, today: Self.today).isEmpty }
        #expect(hit("phil") && hit("123") && hit("mast") && hit("  juan  ") && hit(""))
        #expect(!hit("COFF") && !hit("SGSIN") && !hit("zzz"))
        let rank = member(first: "Ann", rank: "Chief Officer", code: "COFF")
        #expect(CrewRoster.filter([rank], query: "COFF", expiringOnly: false, today: Self.today).isEmpty)
    }

    @Test func expiringFilterAndStatus() {
        // TV: 09 CREW-014, CREW-016
        let crew = [member(first: "A", signOff: "2026-10-01"), member(first: "B", signOff: "2027-06-01"), member(first: "C")]
        let rows = CrewRoster.rows(crew, query: "", expiringOnly: true, mode: .signOffDate, today: Self.today)
        #expect(rows.map(\.name) == ["A"])
        #expect(CrewRoster.statusLine(total: 0, expiring: 0) == "No crew yet — click \u{201C}Import COMPAS...\u{201D} to load a crew report.")
        #expect(CrewRoster.statusLine(total: 3, expiring: 0) == "3 crew")
        #expect(CrewRoster.statusLine(total: 3, expiring: 1) == "3 crew  \u{00B7}  \u{26A0} 1 contract(s) expiring \u{2264}60d")
    }

    @Test func rowsAndSelection() {
        // TV: 09 CREW-013, CREW-017, CREW-005
        let m = member(first: "Juan", last: "Cruz", id: "1", signOff: "2026-10-01", rank: "Master", code: "MAST",
                       nat: "Philippines", vessel: "MT X")
        m.flags = [CrewReviewFlag(), CrewReviewFlag()]
        let unnamed = member(id: "2", rank: "Cook")
        let row = CrewRoster.row(m, today: Self.today)
        #expect(row.name == "Juan Cruz" && row.sub == "Master (MAST)   \u{00B7}   Philippines   \u{00B7}   MT X   \u{2691} 2")
        #expect(row.expiryText == "\u{26A0} Signs off in 2d  (2026-10-01)" && row.tone == .orange)
        #expect(CrewRoster.row(unnamed, today: Self.today).name == "(unnamed)" && CrewRoster.row(unnamed, today: Self.today).sub == "Cook")
        let rows = [row, CrewRoster.row(unnamed, today: Self.today)]
        #expect(CrewRoster.selection(after: rows, keepKey: "2") == unnamed.id)
        #expect(CrewRoster.selection(after: rows, keepKey: "zzz") == m.id)
        #expect(CrewRoster.selection(after: [], keepKey: "1") == nil)
        #expect(CrewRoster.selection(for: UUID(), key: "1", in: rows) == m.id)
        #expect(CrewRoster.selection(for: unnamed.id, key: nil, in: rows) == unnamed.id)
    }

    @Test func cardTexts() {
        // TV: 09 CREW-020…025
        let m = member(first: "Juan", last: "Cruz", id: "1", rank: "Master", code: "MAST", nat: "Philippines")
        m.rawNationality = "FILIPINO"
        m.signOnPort = "SGSIN"; m.signOnPortRaw = "Singapore (SGP)"
        m.signOffPort = "Rotterdam"; m.signOffPortRaw = "Rotterdam"
        let sections = CrewRoster.sections(m)
        #expect(sections.map(\.title) == ["Identity", "Employment & Sign-On / Sign-Off", "Travel Documents",
                                          "Certificates & Medical", "Physical", "Next of Kin"])
        #expect(sections.map { $0.fields.count } == [8, 9, 6, 4, 3, 3])
        #expect(sections[0].header == "\u{1FAAA}  Identity")
        #expect(sections[0].fields[4].display == "Philippines   (COMPAS: FILIPINO)")
        #expect(sections[0].fields[1].display == "\u{2014}")
        #expect(sections[1].fields[6].value == "SGSIN   (COMPAS: Singapore (SGP))")
        #expect(sections[1].fields[8].value == "Rotterdam")
        #expect(CrewRoster.portDisplay(code: "", raw: "") == "" && CrewRoster.portDisplay(code: "X", raw: " ") == "X")
        #expect(CrewRoster.provenance(m) == nil)
        m.sourceFile = "C.xlsx"
        #expect(CrewRoster.provenance(m) == "Imported  from C.xlsx")
        m.importedAt = "2026-09-29 10:15"
        #expect(CrewRoster.provenance(m) == "Imported 2026-09-29 10:15 from C.xlsx")
        #expect(CrewRoster.reviewNotesTitle(2) == "\u{2691} Review notes (2)")
        let f = CrewReviewFlag(severity: .warning, field: "Sign-off date", message: "Sign-off date: read as 3 Apr 2026 (day first); would be 4 Mar 2026 if month first")
        #expect(CrewRoster.flagLine(f) == "Sign-off date: Sign-off date: read as 3 Apr 2026 (day first); would be 4 Mar 2026 if month first")
        #expect(CrewRoster.deleteMessage(m) == "Move Juan Cruz to the Trash?\n\nYou can restore them from File \u{25B8} Trash, or undo with \u{2318}Z.")
    }

    @Test func checklistSummary() {
        // TV: 09 CREW-022
        let m = member(first: "A")
        #expect(CrewRoster.checklistSummary(m) == "No items yet — open to add tasks (each can have a due date).")
        let s1 = ChecklistStep(title: "Done one"); s1.done = true; s1.deadline = .calendarDate(CivilDate(year: 2026, month: 9, day: 1)!)
        let s2 = ChecklistStep(title: String(repeating: "x", count: 45)); s2.deadline = .calendarDate(CivilDate(year: 2026, month: 10, day: 5)!)
        let s3 = ChecklistStep(title: "Tie later"); s3.deadline = .calendarDate(CivilDate(year: 2026, month: 10, day: 5)!)
        let s4 = ChecklistStep(title: "No date")
        m.checklist = [s1, s2, s3, s4]
        #expect(CrewRoster.checklistSummary(m) == "4 item(s), 1 done   \u{00B7}   next due 2026-10-05 — \(String(repeating: "x", count: 39))\u{2026}")
        m.checklist = [s1, s4]
        #expect(CrewRoster.checklistSummary(m) == "2 item(s), 1 done")
        #expect(CrewRoster.shorten(String(repeating: "y", count: 40), 40) == String(repeating: "y", count: 40))
    }
}
