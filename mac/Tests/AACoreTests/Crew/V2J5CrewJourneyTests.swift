// V2-J5 journey (Stage V round 2, adopted by W-CREW as a regression test): COMPAS import → ask → convert → upsert →
// save → reload → edit → table/export → schedule; plus the crew-checklist deadline reaching the reminders.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct V2J5CrewJourney {
    typealias C = CrewTestBook.Cell
    let clock = CrewTestDates.clock
    let today = CrewTestDates.today

    func compas(_ data: [[String: C]]) -> CrewTestBook {
        var rows: [[C]] = [[.s("COMPAS — Crew arrival list")], [.blank], [.s("Vessel: MT EXAMPLE")]]
        rows.append(CrewCompasHeaders.all.map { .s($0) })
        for d in data { rows.append(CrewCompasHeaders.all.map { d[$0] ?? .blank }) }
        return CrewTestBook(rows: rows, name: "Report")
    }

    func importFile(_ book: CrewTestBook, name: String, into store: AppStore, answer: CrewDateOrder?) throws
        -> (CrewImportSession, CrewImportResult?) {
        let folder = TempFolder("j5")
        let url = folder.file(name)
        try book.write(to: url)
        let sheet = try CrewCompasReader.read(url: url)
        var s = CrewImportSession(sheet: sheet, fileName: name, now: clock.now(), today: today, zone: CrewTestDates.athens)
        if s.question != nil {
            guard let answer else { return (s, nil) }
            s.answer(answer)
        }
        s.convertAll()
        let r = CrewImport.apply(s, to: store)
        try store.save()
        CrewImport.logDates(r, to: store)
        return (s, r)
    }

    @Test func importAskReloadEditTableExportSchedule() throws {
        let made = StoreFactory.make(clock: clock); let store = made.store
        // 1. All numeric dates ambiguous → question .unknown; answer Day First.
        let v1 = compas([
            ["First name": .s("JUAN"), "Surname": .s("DELA CRUZ"), "Name": .s("JUAN CARLOS DELA CRUZ"),
             "Code": .n(100234), "Nationality code": .s("PHL"), "Nationality": .s("FILIPINO"),
             "Date of Birth": .s("05/12/1990"), "Rank": .s("AB"), "Joining Date": .s("01/05/2026"),
             "Joining Port": .s("Singapore (SGP)"), "Sign Off Date": .s("10/11/2026"), "Height": .n(175)],
            ["First name": .s("ANDREI"), "Surname": .s("POPESCU"), "Code": .n(100567), "Nationality code": .s("ROU"),
             "Rank": .s("COFF"), "Joining Date": .d(46213), "Joining Port": .s("Rotterdam"),
             "Sign Off Date": .s("02/10/2026"), "Gender": .s("M")],
        ])
        let (s1, cancelled) = try importFile(v1, name: "COMPAS.xlsx", into: store, answer: nil)
        #expect(s1.question == .unknown && cancelled == nil && store.data.crew.isEmpty && store.data.log.isEmpty)
        let (_, r1o) = try importFile(v1, name: "COMPAS.xlsx", into: store, answer: .dayFirst)
        let r1 = try #require(r1o)
        #expect(r1.added == 2 && r1.updated == 0)
        let juan = try #require(store.data.crew.first { $0.employeeId == "100234" })
        #expect(juan.signOffDate == "2026-11-10" && juan.dateOfBirth == "1990-12-05" && juan.signOnDate == "2026-05-01")
        #expect(juan.middleName == "CARLOS DELA CRUZ" && juan.nationality == "Philippines" && juan.signOnPort == "SGSIN")
        #expect(juan.height == "175" && juan.rank == "Able Seaman" && juan.rankCode == "AB")
        let andrei = try #require(store.data.crew.first { $0.employeeId == "100567" })
        #expect(andrei.signOnDate == "2026-07-10")                       // typed date cell
        #expect(andrei.signOffDate == "2026-10-02")
        #expect(andrei.signOnPort == "Rotterdam")
        // Expiry with today 2026-09-29: Andrei 3d (orange), Juan 42d (amber) → badge 2.
        #expect(CrewExpiry.expiringCount(store.data.crew, today: today) == 2)
        #expect(CrewExpiry.expiry(andrei, today: today).text == "\u{26A0} Signs off in 3d  (2026-10-02)")
        let report = CrewExpiry.reportMessage(CrewExpiry.due(store.data.crew, today: today))
        #expect(report.hasPrefix("2 crew contract(s) overdue or due within 60 days:\n\n  \u{2022}  ANDREI POPESCU  (Chief Officer (COFF))"))
        // Log entries.
        #expect(store.data.log.map(\.kind) == ["Crew import", "Crew import dates"])

        // 2. Reload from disk (save happened) → identical members, flags with integer severity.
        try store.flushIfDirty()
        let reloaded = made.dataStore.load()
        #expect(reloaded.crew.count == 2)
        let rj = try #require(reloaded.crew.first { $0.employeeId == "100234" })
        #expect(rj.id == juan.id && rj.signOffDate == "2026-11-10" && rj.flags.count == juan.flags.count)
        let raw = String(decoding: try Data(contentsOf: made.dataStore.currentDataFile), as: UTF8.self)
        #expect(raw.contains("\"Severity\":1"))
        #expect(!raw.contains("\"FullName\"") && !raw.contains("\"Key\""))

        // 3. Checklist + schedule on Juan, then a re-import (v2 has a day witness 15/07) updates in place.
        juan.checklist = [ChecklistStep(title: "Familiarisation")]
        let vessel = Vessel(name: "MT EXAMPLE"); store.data.vessels.append(vessel)
        juan.scheduleVesselId = vessel.id
        CrewScheduleOps.addEntry(to: juan, title: "Drill briefing", kind: .note, refID: nil,
                                 date: CivilDate(year: 2026, month: 10, day: 1), time: "8:00", store: store)
        let v2 = compas([
            ["First name": .s("JUAN"), "Surname": .s("DELA CRUZ"), "Code": .s("100234"), "Rank": .s("BOSN"),
             "Date of Birth": .s("15/07/1990"), "Joining Date": .s("01/05/2026"), "Joining Port": .s("Singapore (SGP)"),
             "Sign Off Date": .s("03/04/2027")],
        ])
        let (s2, r2o) = try importFile(v2, name: "COMPAS-2.xlsx", into: store, answer: nil)
        #expect(s2.question == nil)
        let r2 = try #require(r2o)
        #expect(r2.added == 0 && r2.updated == 1)
        let juan2 = store.data.crew[store.data.crew.firstIndex { $0.employeeId == "100234" }!]
        #expect(juan2.id == juan.id && juan2.rank == "Bosun" && juan2.signOffDate == "2027-04-03")
        #expect(juan2.checklist.count == 1 && juan2.schedule.count == 1 && juan2.scheduleVesselId == vessel.id)
        #expect(juan2.schedule[0].time == "08:00")

        // 4. Edit: EmployeeId + typed sign-off text; Save normalises "2027-5-6".
        var draft = CrewEditorForm.draft(of: juan2)
        let original = draft
        draft["EmployeeId"] = "  777 "
        draft["SignOffDate"] = "2027-5-6"
        CrewEditorForm.apply(draft, original: original, to: juan2)
        #expect(juan2.employeeId == "777" && juan2.key == "777" && juan2.signOffDate == "2027-05-06")

        // 5. Table view: Day-Mon-Year with a space separator; export → read sheet1.xml.
        let ui = store.data.ui
        var choices = CrewColumns.buildChoices(order: ui.crewTableColumns, shown: ui.crewTableShownColumns)
        if let i = choices.firstIndex(where: { $0.column.key == "DaysUntilSignOff" }) { choices[i].shown = true }
        let lists = CrewColumns.persistedLists(choices)
        ui.crewTableColumns = lists.order; ui.crewTableShownColumns = lists.shown
        ui.crewTableDateFormat = CrewDateFormat.dayMonthName.name; ui.crewTableDateSeparator = " "
        let cols = choices.filter(\.shown).map(\.column)
        let crew = CrewSort.sorted(store.data.crew, mode: .lastName, today: today)
        let rows = CrewColumns.rows(crew, columns: cols, format: .dayMonthName, separator: " ", today: today)
        let out = TempFolder("j5x").file("crew-2026-09-29.xlsx")
        try CrewColumns.export(to: out, headers: cols.map(\.header), rows: rows)
        let zip = try ZipReader(url: out)
        #expect(zip.entries.map(\.name) == ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
                                             "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml"])
        let sheet = String(decoding: try zip.data(for: zip.entry(named: "xl/worksheets/sheet1.xml")!), as: UTF8.self)
        #expect(sheet.contains("<c r=\"A1\" t=\"inlineStr\" s=\"1\"><is><t xml:space=\"preserve\">Last Name</t></is></c>"))
        #expect(sheet.contains(">DELA CRUZ<") && sheet.contains(">06 May 2027<") && sheet.contains(">Days to Sign-Off<"))
        #expect(sheet.contains("<col min=\"1\" max=\"\(cols.count)\" width=\"20\" customWidth=\"1\"/>"))
        let wb = String(decoding: try zip.data(for: zip.entry(named: "xl/workbook.xml")!), as: UTF8.self)
        #expect(wb.contains("<sheet name=\"Crew\" sheetId=\"1\" r:id=\"rId1\"/>"))

        // 6. Schedule: save as template, apply to Andrei (append), export / import round trip.
        let t = CrewScheduleOps.saveAsTemplate(juan2, name: "Joining routine", store: store)
        #expect(t.vesselId == vessel.id && t.vesselName == "MT EXAMPLE" && t.entries.first?.done == false)
        let n = CrewScheduleOps.apply(t, to: andrei, replace: false, store: store)
        #expect(n == 1 && andrei.schedule.count == 1 && andrei.scheduleVesselId == vessel.id)
        #expect(andrei.schedule[0].id != juan2.schedule[0].id && andrei.schedule[0].date == "2026-10-01")
        let bytes = try CrewScheduleOps.exportData(juan2, store: store)
        let json = String(decoding: bytes, as: UTF8.self)
        #expect(json.contains("\"Kind\": 0") && json.contains("\"RefId\": null") && json.contains("\"Name\": \"JUAN DELA CRUZ schedule\""))
        let imported = try CrewScheduleOps.importTemplate(bytes, store: store)
        #expect(imported.entries.count == 1 && imported.id != t.id && store.data.scheduleTemplates.count == 2)

        // 7. Everything survives a save + reload.
        try store.save()
        let back = made.dataStore.load()
        let bj = try #require(back.crew.first { $0.id == juan.id })
        #expect(bj.employeeId == "777" && bj.signOffDate == "2027-05-06" && bj.schedule.count == 1 && bj.checklist.count == 1)
        #expect(back.ui.crewTableDateSeparator == " " && back.ui.crewTableDateFormat == "DayMonthName")
        #expect(back.scheduleTemplates.count == 2)
    }

    /// Windows reads a stored legacy "03/04/2027" month-first (4 March); the Mac deliberately leaves it unread
    /// (DEVIATIONS 09 Q4). This pins what each surface shows for such a member.
    @Test func ambiguousStoredSignOffDate() {
        let m = CrewMember(); m.firstName = "WEI"; m.lastName = "ZHANG"; m.signOffDate = "03/04/2027"
        #expect(CrewStoredDate.daysUntilSignOff(m, today: today) == nil)
        #expect(m.daysUntilSignOff(today: today) != nil)       // the model API still reads it month-first
        let cols = [CrewColumns.column("SignOffDate")!, CrewColumns.column("ContractStatus")!]
        #expect(CrewColumns.rows([m], columns: cols, format: .iso, separator: "-", today: today) == [["03/04/2027", "Unknown"]])
    }

    /// From V2-J5's vessel journey: a crew checklist deadline in the past is counted as overdue by the reminders.
    @Test func crewChecklistDeadlineReachesReminders() throws {
        let made = StoreFactory.make(clock: clock); let store = made.store
        let m = CrewMember(); m.firstName = "Ana"; m.lastName = "Reyes"
        let step = ChecklistStep(title: "Yellow fever certificate")
        step.deadline = .calendarDate(CivilDate(year: 2026, month: 9, day: 27)!)
        m.checklist = [step]
        store.data.crew = [m]
        let s = ReminderService.compute(store: store, today: today)
        #expect(s.overdue == 1)
        #expect(CrewRoster.checklistSummary(m) == "1 item(s), 0 done   \u{00B7}   next due 2026-09-27 \u{2014} Yellow fever certificate")
    }
}
