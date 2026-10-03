// Tests for 09 §3.9 CrewColumns / CrewTableWindow: vectors §7.11 (cells, Pattern), §7.12 (column chooser), CREW-101/104
// persistence values, and the CREW-105 export through F1's writer (09 §4.10 parts, §7.13 round trip).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct CrewTableTests {
    static let today = CrewTestDates.today

    func m(_ date: String) -> CrewMember { let x = CrewMember(); x.dateOfBirth = date; return x }
    var dob: CrewColumn { CrewColumns.column("DateOfBirth")! }

    @Test func catalog() {
        #expect(CrewColumns.all.count == 40 && Set(CrewColumns.all.map(\.key)).count == 40)
        #expect(CrewColumns.all.filter(\.isDate).map(\.key) == ["DateOfBirth", "SignOnDate", "SignOffDate", "PassportExpiry",
                                                               "PassportIssued", "SeamansBookExpiry", "SeamansBookIssued",
                                                               "CocExpiry", "CocIssue", "HealthCertExpiry"])
        #expect(CrewColumns.all[22].header == "Days to Sign-Off" && CrewColumns.all[37].header == "Checklist Items")
        #expect(CrewColumns.resolve(["Bogus"]).map(\.key) == CrewColumns.defaultKeys)
        #expect(CrewColumns.resolve(["Vessel", "Bogus", "Cid"]).map(\.key) == ["Vessel", "Cid"])
    }

    @Test func dateCells() {
        // TV: 09 §7.11
        let x = m("2026-03-15")
        let cases: [(CrewDateFormat, String, String)] = [
            (.iso, "-", "2026-03-15"), (.iso, "/", "2026/03/15"), (.iso, "", "20260315"), (.iso, "'", "2026'03'15"),
            (.iso, "m", "2026m03m15"), (.dayMonthYear, ".", "15.03.2026"), (.monthDayYear, "/", "03/15/2026"),
            (.dayMonthName, "-", "15-Mar-2026"), (.dayMonthName, " ", "15 Mar 2026"),
        ]
        for (f, sep, want) in cases {
            #expect(CrewColumns.cell(dob, x, format: f, separator: sep, today: Self.today) == want)
        }
        for f in CrewDateFormat.allCases {
            #expect(CrewColumns.cell(dob, m("15/07/2026"), format: f, separator: "-", today: Self.today) == "15/07/2026")
        }
        // Legacy month-first text that is not ambiguous reads as on Windows; an ambiguous one stays verbatim (Q4).
        #expect(CrewColumns.cell(dob, m("2026-3-4"), format: .iso, separator: "-", today: Self.today) == "2026-03-04")
        #expect(CrewColumns.cell(dob, m("03/04/2026"), format: .iso, separator: "-", today: Self.today) == "03/04/2026")
        let name = CrewColumns.column("LastName")!
        let y = CrewMember(); y.lastName = "2026-03-15"
        #expect(CrewColumns.cell(name, y, format: .dayMonthYear, separator: "-", today: Self.today) == "2026-03-15")
        // Backslash separators are verbatim on the Mac (09 §8 Q10).
        #expect(CrewColumns.formatDate(CivilDate(year: 2026, month: 3, day: 15)!, format: .iso, separator: "\\") == "2026\\03\\15")
    }

    @Test func patterns() {
        // TV: 09 §7.11 Pattern rows
        #expect(CrewColumns.pattern(.iso, separator: "-") == "yyyy'-'MM'-'dd")
        #expect(CrewColumns.pattern(.iso, separator: "") == "yyyyMMdd")
        #expect(CrewColumns.pattern(.iso, separator: "'") == "yyyy'\\''MM'\\''dd")
        #expect(CrewColumns.pattern(.dayMonthName, separator: nil) == "dd-MMM-yyyy")
    }

    @Test func computedColumns() {
        let x = CrewMember(); x.firstName = "A"; x.lastName = "B"; x.employeeId = "77"; x.signOffDate = "2026-10-01"
        x.checklist = [ChecklistStep(title: "1"), ChecklistStep(title: "2")]
        x.importedAt = "2026-09-29 10:15"; x.sourceFile = "C.xlsx"; x.eyesColor = "BROWN"
        func v(_ k: String) -> String { CrewColumns.value(CrewColumns.column(k)!, x, today: Self.today) }
        #expect(v("FullName") == "A B" && v("Cid") == "77" && v("DaysUntilSignOff") == "2" && v("ContractStatus") == "Critical")
        #expect(v("ChecklistCount") == "2" && v("ImportedAt") == "2026-09-29 10:15" && v("SourceFile") == "C.xlsx")
        #expect(v("EyesColor") == "BROWN")
        x.signOffDate = "2026-09-26"
        #expect(v("DaysUntilSignOff") == "-3" && v("ContractStatus") == "Expired")
        x.signOffDate = ""
        #expect(v("DaysUntilSignOff") == "" && v("ContractStatus") == "Unknown")
    }

    @Test func chooser() {
        // TV: 09 §7.12
        var c = CrewColumns.buildChoices(order: [], shown: [])
        #expect(c.count == 40 && c.prefix(9).allSatisfy(\.shown) && c.dropFirst(9).allSatisfy { !$0.shown })
        #expect(c.prefix(9).map(\.column.key) == CrewColumns.defaultKeys)
        #expect(c[9].column.key == "MiddleName")
        c = CrewColumns.buildChoices(order: ["Vessel", "Bogus", "LastName", "Vessel"], shown: ["LastName"])
        #expect(c.count == 40 && c[0].column.key == "Vessel" && !c[0].shown && c[1].column.key == "LastName" && c[1].shown)
        #expect(c.dropFirst(2).allSatisfy { !$0.shown } && c[2].column.key == "FirstName")
        c = CrewColumns.buildChoices(order: ["Vessel"], shown: [])
        #expect(c.allSatisfy { !$0.shown })
        let p = CrewColumns.persistedLists(c)
        #expect(p.order.count == 40 && p.shown.isEmpty)
        #expect(CrewColumns.countText(crew: 5, columns: 0) == "5 crew  \u{00B7}  0 columns")
        #expect(CrewColumns.countText(crew: 5, columns: 1) == "5 crew  \u{00B7}  1 column")
    }

    @Test func formatAndSeparatorPersistence() {
        // TV: 09 CREW-101, §8 Q11
        #expect(CrewDateFormat.allCases.map(\.label) == ["2026-03-15  (Y-M-D)", "15-03-2026  (D-M-Y)", "03-15-2026  (M-D-Y)",
                                                         "15-Mar-2026  (D-Mon-Y)"])
        #expect(CrewDateFormat(persisted: "DayMonthName") == .dayMonthName && CrewDateFormat(persisted: "x") == .iso)
        #expect(CrewDateFormat(persisted: nil) == .iso && CrewDateFormat(persisted: "2") == .monthDayYear)
        #expect(CrewColumns.loadedSeparator(nil) == "-" && CrewColumns.loadedSeparator("") == "-")
        #expect(CrewColumns.loadedSeparator(" / ") == " / " && CrewColumns.clampSeparator("abcd") == "abc")
        #expect(CrewColumns.exportFileName(today: Self.today) == "crew-2026-09-29.xlsx")
        #expect(CrewColumns.exportedMessage(count: 2, path: "/tmp/x.xlsx") == "Exported 2 crew to:\n/tmp/x.xlsx\n\nOpen it now?")
    }

    @Test func exportWritesTheShownTable() throws {
        // TV: 09 §7.13 round trip (F1 writer bytes, CREW-105)
        let a = CrewMember(); a.lastName = "O'Neil & Co"; a.employeeId = "<1>"; a.dateOfBirth = "1990-05-12"
        let cols = ["LastName", "Cid", "DateOfBirth"].compactMap(CrewColumns.column)
        let rows = CrewColumns.rows([a], columns: cols, format: .dayMonthName, separator: " ", today: Self.today)
        #expect(rows == [["O'Neil & Co", "<1>", "12 May 1990"]])
        let folder = TempFolder("crew-export")
        let url = folder.file(CrewColumns.exportFileName(today: Self.today))
        try CrewColumns.export(to: url, headers: cols.map(\.header), rows: rows)
        let zip = try ZipReader(url: url)
        #expect(zip.entries.map(\.name) == ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
                                           "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml"])
        let sheet = String(decoding: try zip.data(for: zip.entry(named: "xl/worksheets/sheet1.xml")!), as: UTF8.self)
        #expect(sheet.contains("<col min=\"1\" max=\"3\" width=\"20\" customWidth=\"1\"/>"))
        #expect(sheet.contains("<c r=\"A1\" t=\"inlineStr\" s=\"1\"><is><t xml:space=\"preserve\">Last Name</t></is></c>"))
        #expect(sheet.contains("<c r=\"A2\" t=\"inlineStr\" s=\"0\"><is><t xml:space=\"preserve\">O'Neil &amp; Co</t></is></c>"))
        #expect(sheet.contains("<t xml:space=\"preserve\">&lt;1&gt;</t>"))
        let wb = String(decoding: try zip.data(for: zip.entry(named: "xl/workbook.xml")!), as: UTF8.self)
        #expect(wb.contains("<sheet name=\"Crew\" sheetId=\"1\" r:id=\"rId1\"/>"))
        // Re-read through F2's reader: what Excel would show.
        let book = try XlsxWorkbook.open(url)
        let ws = try book.load(book.worksheets[0])
        #expect(XlsxRender.getString(ws.cell(2, 3)) == "12 May 1990")
    }
}
