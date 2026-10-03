// Tests for 09 §3.3 CompasReader (vectors §7.7), the import session (CREW-032/033 with DECISIONS 09 Q1/Q2), the upsert
// (CREW-035/036/037, §7.15 with DECISIONS 09 Q3), the status line (CREW-038) and the persisted JSON shape (§4.2, §7.15).
import Foundation
import Testing
@testable import AACore

@Suite struct CrewCompasReaderTests {
    typealias C = CrewTestBook.Cell

    @Test func picksReportSheetCaseInsensitively() throws {
        // TV: 09 §7.7 sheets
        let header: [C] = [.s("First name"), .s("Surname")]
        let book = CrewTestBook(sheets: [
            .init(name: "Summary", rows: [header, [.s("Wrong"), .s("Sheet")]]),
            .init(name: "REPORT", rows: [header, [.s("Right"), .s("Sheet")]]),
        ])
        let sheet = try CrewCompasReader.read(workbook: try book.workbook())
        #expect(sheet.sheetName == "REPORT" && sheet.rows.count == 1 && sheet.rows[0].get("First name") == "Right")
        let other = CrewTestBook(sheets: [.init(name: "A", rows: [header, [.s("A1"), .s("x")]]),
                                          .init(name: "B", rows: [header, [.s("B1"), .s("x")]])])
        #expect(try CrewCompasReader.read(workbook: try other.workbook()).rows.first?.get("First name") == "A1")
    }

    @Test func findsHeaderBelowTitleRows() throws {
        // TV: 09 §7.7 header row 4; header text normalisation
        let rows: [[C]] = [[.s("Crew arrival list")], [.s("Vessel: MT EXAMPLE")], [],
                           [.s("First\nname"), .s("SURNAME"), .s("Sign  Off Date"), .s("Rank"), .s("Rank")],
                           [.s("Juan"), .s("Cruz"), .s("2026-11-01"), .s("AB"), .s("MAST")]]
        let sheet = try CrewCompasReader.read(workbook: try CrewTestBook(rows: rows).workbook())
        #expect(sheet.headerRow == 4 && sheet.rows.count == 1)
        let r = sheet.rows[0]
        #expect(r.get("First name") == "Juan" && r.get("Surname") == "Cruz" && r.get("sign off date") == "2026-11-01")
        #expect(r.get("Rank") == "MAST")                       // the right-most duplicate header wins
        #expect(r.get("Not there") == "" && !r.has("Not there"))
    }

    @Test func headerOnRow21IsNotFound() throws {
        // TV: 09 §7.7 header on row 21 → the CREW-031 message
        var rows: [[C]] = Array(repeating: [.s("title")], count: 20)
        rows.append([.s("First name"), .s("Surname")])
        rows.append([.s("Juan"), .s("Cruz")])
        #expect(throws: CrewImportError.headerNotFound) { try CrewCompasReader.read(workbook: try CrewTestBook(rows: rows).workbook()) }
        #expect(CrewImportError.headerNotFound.errorDescription == "Could not find the COMPAS header row (expected 'First name' and 'Surname').")
    }

    @Test func cellStringsAndRowSkipping() throws {
        // TV: 09 §7.7 cell rendering and skipped rows
        let rows: [[C]] = [
            [.s("First name"), .s("Surname"), .s("Code"), .s("Height"), .s("Flag"), .s("Sign Off Date"), .s("Place of Birth"), .s("Gender")],
            [.s("Juan"), .s("Cruz"), .n(12345.0), .n(180.5), .b(true), .d(46096), .s("  ABC  "), .e("#N/A")],
            [.blank, .s(" "), .s("orphan data"), .n(1)],
            [.blank, .s("Santos")],
        ]
        let sheet = try CrewCompasReader.read(workbook: try CrewTestBook(rows: rows).workbook())
        #expect(sheet.rows.count == 2)
        let r = sheet.rows[0]
        #expect(r.get("Code") == "12345" && r.get("Height") == "180.5" && r.get("Flag") == "TRUE")
        #expect(r.get("Sign Off Date") == "2026-03-15" && r.get("Place of Birth") == "ABC" && r.get("Gender") == "#N/A")
        #expect(sheet.rows[1].get("Surname") == "Santos" && sheet.rows[1].get("First name") == "")
    }

    @Test func emptyWorkbookAndDate1904() throws {
        let empty = try CrewCompasReader.read(workbook: try CrewTestBook(rows: []).workbook())
        #expect(empty.rows.isEmpty && empty.headerRow == 0)
        let book = CrewTestBook(rows: [[.s("First name"), .s("Surname"), .s("Sign Off Date")],
                                       [.s("A"), .s("B"), .d(44635)]], date1904: true)
        let sheet = try CrewCompasReader.read(workbook: try book.workbook())
        #expect(sheet.use1904 && sheet.rows[0].get("Sign Off Date") == "2026-03-16")
    }

    @Test func notAWorkbook() throws {
        let folder = TempFolder("crew-bad")
        let url = try folder.write("crew.xlsx", "not a zip")
        #expect(throws: CrewImportError.self) { try CrewCompasReader.read(url: url) }
        let txt = try folder.write("crew.txt", "x")
        do {
            _ = try CrewCompasReader.read(url: txt)
            Issue.record("expected a failure")
        } catch {
            #expect(CrewImport.failureMessage(error.localizedDescription).hasPrefix("Could not import the COMPAS file:\n\n"))
        }
    }
}

@MainActor
@Suite struct CrewImportSessionTests {
    func session(_ values: [[String: String]]) -> CrewImportSession {
        CrewImportSession(sheet: CrewCompasSheet(rows: values.map(CrewCompasHeaders.row)), fileName: "COMPAS.xlsx",
                          now: CrewTestDates.clock.now(), today: CrewTestDates.today, zone: CrewTestDates.athens)
    }

    @Test func decisionsQ1AsksOnlyWhenSomethingIsAmbiguous() {
        // DECISIONS 09 Q1 (supersedes 09 CREW-033 quirk (a)).
        #expect(session([]).question == nil)
        #expect(session([["First name": "A", "Sign Off Date": "2026-11-01"]]).question == nil)
        #expect(session([["First name": "A", "Sign Off Date": "03/04/2026"]]).question == .unknown)
        #expect(session([["First name": "A", "Sign Off Date": "15/07/2026", "Joining Date": "03/04/2026"]]).question == nil)
        #expect(session([["First name": "A", "Sign Off Date": "15/07/2026", "Joining Date": "07/15/2026"]]).question == nil)
        #expect(session([["First name": "A", "Sign Off Date": "15/07/2026", "Joining Date": "07/15/2026",
                          "Date of Birth": "03/04/1990"]]).question == .conflicted)
    }

    @Test func decisionsQ2AnswerAppliesToConflictedFile() {
        var s = session([["First name": "A", "Code": "1", "Sign Off Date": "15/07/2026", "Joining Date": "07/15/2026",
                          "Date of Birth": "03/04/1990"]])
        #expect(s.question == .conflicted)
        s.answer(.dayFirst)
        s.convertAll()
        #expect(s.records[0].dateOfBirth == "1990-04-03")
        #expect(s.records[0].flags.contains { $0.message == "Date of birth: read as 3 Apr 1990 (day first); would be 4 Mar 1990 if month first" })
    }

    @Test func unknownAnswerAndQuestionText() {
        var s = session([["First name": "A", "Sign Off Date": "03/04/2026"]])
        s.answer(.monthFirst)
        s.convertAll()
        #expect(s.records[0].signOffDate == "2026-03-04")
        #expect(s.dateSummary() == "dates read month first (mm/dd), proved by 0 values")
        let msg = CrewImportSession.questionMessage(.unknown, fileName: "COMPAS.xlsx")
        #expect(msg == "COMPAS.xlsx\n\nEvery date in this file could be read either way (nothing has a day above 12), so AA cannot tell which convention it uses.\n\nIs a date like 03/04/2026 the 3rd of April, or the 4th of March?\n\nGetting this wrong shifts contract dates by weeks, so check the file if you are unsure.")
        #expect(CrewDateQuestion.conflicted.why == "This file writes dates BOTH ways - some are clearly day-first and others clearly month-first, so no single reading fits all of them.")
    }
}

@MainActor
@Suite struct CrewUpsertTests {
    func session(_ values: [[String: String]]) -> CrewImportSession {
        var s = CrewImportSession(sheet: CrewCompasSheet(rows: values.map(CrewCompasHeaders.row)), fileName: "COMPAS.xlsx",
                                  now: CrewTestDates.clock.now(), today: CrewTestDates.today, zone: CrewTestDates.athens)
        s.convertAll()
        return s
    }

    @Test func updateKeepsIdChecklistAndScheduleAtSameIndex() throws {
        // TV: 09 §7.15 row 1 (+ DECISIONS 09 Q3: Schedule / ScheduleVesselId carried over)
        let made = StoreFactory.make(clock: CrewTestDates.clock); let store = made.store
        let first = CrewMember(); first.employeeId = "900"; first.firstName = "Ann"
        let existing = CrewMember(); existing.employeeId = "123"; existing.firstName = "Old"
        let step = ChecklistStep(title: "s1"); existing.checklist = [step]
        let entry = ScheduleEntry(title: "e1"); existing.schedule = [entry]
        let vessel = UUID(); existing.scheduleVesselId = vessel
        existing.flags = [CrewReviewFlag(severity: .error, field: "x", message: "old")]
        store.data.crew = [first, existing]
        let s = session([["First name": "Juan", "Surname": "Cruz", "Code": "123", "Rank": "MAST"]])
        let result = CrewImport.apply(s, to: store)
        #expect(result.added == 0 && result.updated == 1 && result.memberCount == 1)
        #expect(store.data.crew.count == 2 && store.data.crew[0] === first)
        let m = store.data.crew[1]
        #expect(m !== existing && m.id == existing.id && m.firstName == "Juan" && m.rank == "Master")
        #expect(m.checklist.count == 1 && m.checklist[0] === step)
        #expect(m.schedule.count == 1 && m.schedule[0] === entry && m.scheduleVesselId == vessel)
        #expect(!m.flags.contains { $0.message == "old" })
        let log = try #require(store.data.log.last)
        #expect(log.action == "Added" && log.kind == "Crew import" && log.name == "0 added, 1 updated" && log.detail == "COMPAS.xlsx")
        #expect(result.statusText.hasPrefix("Imported 1 from COMPAS.xlsx (0 new, 1 updated) — dates read"))
    }

    @Test func duplicateKeysInOneFileCollapse() {
        // TV: 09 §7.15 row 2
        let made = StoreFactory.make(clock: CrewTestDates.clock); let store = made.store
        let s = session([["First name": "A", "Code": "123"], ["First name": "B", "Code": "123"]])
        let result = CrewImport.apply(s, to: store)
        #expect(store.data.crew.count == 1 && store.data.crew[0].firstName == "B")
        #expect(result.added == 1 && result.updated == 1)
    }

    @Test func keyMatchingIsOrdinalAndNameBased() {
        let made = StoreFactory.make(clock: CrewTestDates.clock); let store = made.store
        let a = CrewMember(); a.firstName = "Juan"; a.lastName = "Cruz"
        store.data.crew = [a]
        var s = session([["First name": "juan", "Surname": "Cruz"]])
        #expect(CrewImport.apply(s, to: store).added == 1)
        s = session([["First name": "Juan", "Surname": "Cruz"]])
        let r = CrewImport.apply(s, to: store)
        #expect(r.updated == 1 && store.data.crew[0].id == a.id)
    }

    @Test func statusAndDatesLog() throws {
        // TV: 09 CREW-037/038
        let made = StoreFactory.make(clock: CrewTestDates.clock); let store = made.store
        let s = session([["First name": "A", "Surname": "B", "Code": "1", "Rank": "", "Sign Off Date": "nope"]])
        let r = CrewImport.apply(s, to: store)
        CrewImport.logDates(r, to: store)
        let log = try #require(store.data.log.last)
        #expect(log.kind == "Crew import dates" && log.name == s.dateSummary() && log.detail == "COMPAS.xlsx")
        #expect(r.flagTotal == s.records[0].flags.count && r.flagTotal >= 4)
        #expect(r.statusText == "Imported 1 from COMPAS.xlsx (1 new, 0 updated) — \(s.dateSummary()); \(r.flagTotal) review note(s).")
    }

    @Test func deleteThenUndoAndSecondRestoreIsNoOp() throws {
        // TV: 09 §7.15 row 3 (REPO-071 / REPO-076 through F2's Trash)
        let made = StoreFactory.make(clock: CrewTestDates.clock); let store = made.store
        let m = CrewMember(); m.firstName = "Juan"; m.lastName = "Cruz"; m.checklist = [ChecklistStep(title: "c")]
        m.schedule = [ScheduleEntry(title: "e")]
        store.data.crew = [m]
        let entry = store.trash(m)
        #expect(store.data.crew.isEmpty && entry.kindLabel == "Crew member" && entry.name == "Juan Cruz")
        _ = store.undoLastDelete()
        let back = try #require(store.data.crew.first)
        #expect(back.id == m.id && back.checklist.count == 1 && back.schedule.count == 1)
        #expect(store.restore(entry) == nil || store.data.crew.count == 1)
        #expect(store.data.crew.count == 1)
    }

    @Test func clearAllIsOneTrashBatch() throws {
        // DECISIONS 09 "Clear all → through the Trash as one batch (undoable)"
        let made = StoreFactory.make(clock: CrewTestDates.clock); let store = made.store
        store.data.crew = (0..<3).map { k in let m = CrewMember(); m.employeeId = "\(k)"; return m }
        #expect(store.trashAllCrew() == 3)
        #expect(store.data.crew.isEmpty && store.data.log.last?.name == "all 3 member(s)")
        _ = store.undoLastDelete()
        #expect(store.data.crew.map(\.employeeId) == ["0", "1", "2"])
        #expect(CrewRoster.clearMessage(count: 3).hasPrefix("Remove ALL crew from the roster?"))
    }

    @Test func persistedShapeMatchesSpecExample() throws {
        // TV: 09 §7.15 JSON round-trip of the §4.2 example (Severity stays an integer, key order kept)
        let json = #"{"Id":"0b6f1c9e-5d0a-4f7e-9a51-2c3d4e5f6a7b","Checklist":[],"Schedule":[],"EmployeeId":"12345","FirstName":"JUAN","MiddleName":"CARLOS","LastName":"DELA CRUZ","Nationality":"Philippines","DateOfBirth":"1990-05-12","PlaceOfBirth":"MANILA","Gender":"Male","Height":"175","EyesColor":"BROWN","HairColor":"BLACK","UserType":"Crew","Rank":"Able Seaman","RankCode":"AB","SignedOnOff":"On","Company":"ACME CREWING","Vessel":"MT EXAMPLE","SignOnDate":"2026-05-01","SignOnPort":"SGSIN","SignOnPortRaw":"Singapore (SGP)","SignOffDate":"2026-11-01","SignOffPort":"","SignOffPortRaw":"","PassportNumber":"P1234567","PassportExpiry":"2030-01-31","PassportIssued":"2020-02-01","SeamansBookNumber":"","SeamansBookExpiry":"","SeamansBookIssued":"","CocNumber":"","CocExpiry":"","CocIssue":"","HealthCertExpiry":"2027-04-30","NokFirstName":"MARIA","NokLastName":"DELA CRUZ","NokRelationship":"Spouse","RawNationality":"FILIPINO","Flags":[{"Severity":1,"Field":"Sign-off date","Message":"Sign-off date: read as 1 Nov 2026 (day first); would be 11 Jan 2026 if month first"}],"ImportedAt":"2026-09-29 10:15","SourceFile":"COMPAS.xlsx"}"#
        guard case .object(let o) = try JSONParser.parse(Data(json.utf8)) else { Issue.record("not an object"); return }
        let m = try CrewMember(json: o, context: .standard)
        #expect(m.flags.first?.severity == .warning && m.fullName == "JUAN CARLOS DELA CRUZ")
        let out = String(decoding: try JSONWriter.data(.object(m.toJSON())), as: UTF8.self)
        #expect(try JSONAssert.equalCanonical(out, json))
        #expect(out.contains("\"Severity\":1"))
    }
}
