// Tests for 10 Addendum X.8.7 (used range, sheet choice, merges, tables, comments, addressing), X.8.8 (gate and
// error messages), X.8.9 / VESSEL-303 on the two POC workbooks, X.7.2 performance budget (2 524 × 16 < 200 ms).
import Foundation
import Testing
@testable import AACore

@Suite struct XlsxReadStructureTests {
    private func range(_ s: XlsxWorksheet) -> [Int]? {
        s.rangeUsed().map { [$0.firstRow, $0.firstColumn, $0.lastRow, $0.lastColumn] }
    }

    @Test func usedRangeRules() throws {
        // TV: 10 X.8.7 rows 3–7
        let comment = SvcXlsxTestBook.Sheet(name: "S", sheetData: "", parts: [
            (type: "comments", name: "comments1.xml",
             xml: "<comments xmlns=\"\(SvcXlsxTestBook.ns)\"><authors><author>a</author></authors><commentList><comment ref=\"C3\" authorId=\"0\"><text><t>note</t></text></comment></commentList></comments>")])
        let (_, s1) = try SvcXlsxTestBook(sheets: [comment]).firstSheet()
        #expect(range(s1) == [3, 3, 3, 3] && s1.cell(3, 3).hasComment && !s1.cell(3, 3).isEmpty)
        #expect(try XlsxRender.compasCellString(s1.cell(3, 3), workbook: XlsxWorkbook(worksheets: [], use1904: false)) == "")

        let (_, s2) = try SvcXlsxTestBook(sheetData: "<row r=\"2\"><c r=\"B2\" t=\"s\"><v>0</v></c></row>", sharedStrings: ["<t xml:space=\"preserve\"> </t>"]).firstSheet()
        #expect(range(s2) == [2, 2, 2, 2])
        let (_, s3) = try SvcXlsxTestBook(sheetData: "<row r=\"2\"><c r=\"B2\" t=\"e\"><v>#SPILL!</v></c></row>").firstSheet()
        #expect(s3.rangeUsed() == nil)
        let (_, s4) = try SvcXlsxTestBook(sheetData: "<row r=\"4\"><c r=\"D4\"><f>NOW()</f></c></row>").firstSheet()
        #expect(range(s4) == [4, 4, 4, 4] && s4.hasUncachedFormula(4, 4) && s4.uncachedFormulaCount() == 1)
        #expect(XlsxRender.uncachedFormulaHint(count: 1) == "1 formula cell(s) had no saved result; open and re-save the file in Excel to include them.")
        var dim = SvcXlsxTestBook(sheetData: "<row r=\"2\"><c r=\"B2\"><v>1</v></c><c r=\"C2\" s=\"0\"/></row><row r=\"3\"><c r=\"C3\"><v>2</v></c></row><row r=\"9\"><c r=\"Z9\" s=\"0\"/></row>")
        dim.sheets[0].extra = ""
        let (_, s5) = try dim.firstSheet()
        #expect(range(s5) == [2, 2, 3, 3])
        let (_, cached) = try SvcXlsxTestBook(sheetData: "<row r=\"1\"><c r=\"A1\"><f>1+1</f><v>2</v></c></row>").firstSheet()
        #expect(cached.cell(1, 1).value == .number(2) && cached.cell(1, 1).hasFormula && !cached.hasUncachedFormula(1, 1))
    }

    @Test func sheetEnumerationAndChoice() throws {
        // TV: 10 X.8.7 rows 8–10; VESSEL-303/304
        let book = SvcXlsxTestBook(sheets: [
            SvcXlsxTestBook.Sheet(name: "Chart1", sheetData: "", kind: "chartsheet"),
            SvcXlsxTestBook.Sheet(name: "Empty", sheetData: ""),
            SvcXlsxTestBook.Sheet(name: "Data", sheetData: "<row r=\"1\"><c r=\"A1\"><v>1</v></c></row>"),
        ])
        let wb = try book.open()
        #expect(wb.worksheets.map(\.name) == ["Empty", "Data"])
        #expect(try wb.load(wb.worksheets[0]).rangeUsed() == nil)
        #expect(try wb.load(wb.worksheets[1]).rangeUsed() != nil)
        #expect(wb.worksheet(named: "report") == nil)

        let wb2 = try SvcXlsxTestBook(sheets: [SvcXlsxTestBook.Sheet(name: "Summary", sheetData: ""),
                                               SvcXlsxTestBook.Sheet(name: "REPORT", sheetData: "")]).open()
        #expect(wb2.worksheet(named: "report")?.name == "REPORT")
        let wb3 = try SvcXlsxTestBook(sheets: [SvcXlsxTestBook.Sheet(name: "report", sheetData: "", state: "hidden"),
                                               SvcXlsxTestBook.Sheet(name: "Sheet1", sheetData: "")]).open()
        #expect(wb3.worksheet(named: "Report")?.isHidden == true)
        let wb4 = try SvcXlsxTestBook(sheets: [SvcXlsxTestBook.Sheet(name: "NoRel", sheetData: "", hasRelationship: false)]).open()
        #expect(wb4.worksheets.map(\.partPath) == [""])
        let noRel = try wb4.load(wb4.worksheets[0])
        #expect(noRel.rangeUsed() == nil)
    }

    @Test func addressingQuirks() throws {
        // TV: 10 X.8.7 rows 11–14; VESSEL-321
        let (_, a) = try SvcXlsxTestBook(sheetData: "<row><c t=\"s\"><v>0</v></c></row><row><c t=\"s\"><v>1</v></c></row>",
                                         sharedStrings: ["<t>x</t>", "<t>y</t>"]).firstSheet()
        #expect(a.cell(1, 1).value == .text("x") && a.cell(2, 1).value == .text("y"))
        let (_, b) = try SvcXlsxTestBook(sheetData: "<row r=\"5\"><c><v>1</v></c></row><row><c><v>2</v></c></row>").firstSheet()
        #expect(b.cell(5, 1).value == .number(1) && b.cell(1, 1).value == .number(2))
        let (_, c) = try SvcXlsxTestBook(sheetData: "<row r=\"3\"><c><v>1</v></c><c><v>2</v></c><c><v>3</v></c></row>").firstSheet()
        #expect([c.cell(3, 1), c.cell(3, 2), c.cell(3, 3)].map(\.value) == [.number(1), .number(2), .number(3)])
        let (_, d) = try SvcXlsxTestBook(sheetData: "<row r=\"3\"><c r=\"C3\"><v>1</v></c><c><v>2</v></c></row>").firstSheet()
        #expect(d.cell(3, 4).value == .number(2))
        let (_, e) = try SvcXlsxTestBook(sheetData: "<row r=\"1\"><c r=\"A1\"><v>1</v></c><c r=\"A1\"/><c r=\"B1\"><v>2</v></c><c r=\"B1\"><v>3</v></c></row>").firstSheet()
        #expect(e.cell(1, 1).value == .number(1) && e.cell(1, 2).value == .number(3))
        #expect(e.cell(100, 100) == XlsxCell())
        let (_, prefixed) = try SvcXlsxTestBook(sheetData: "<x:row xmlns:x=\"\(SvcXlsxTestBook.ns)\" r=\"1\"><x:c r=\"A1\"><x:v>7</x:v></x:c></x:row>").firstSheet()
        #expect(prefixed.cell(1, 1).value == .number(7))
    }

    @Test func tableSideEffects() throws {
        // TV: 10 X.8.7 rows 15–17; VESSEL-324
        func table(_ ref: String) -> (type: String, name: String, xml: String) {
            (type: "table", name: "tables/table1.xml",
             xml: "<table xmlns=\"\(SvcXlsxTestBook.ns)\" id=\"1\" name=\"T\" ref=\"\(ref)\"/>")
        }
        let one = SvcXlsxTestBook.Sheet(name: "S", sheetData: "<row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>H</t></is></c></row><row r=\"2\"><c r=\"B2\"><v>5</v></c><c r=\"D2\"><v>6</v></c></row>",
                                        parts: [table("A1:C1")])
        let (_, s1) = try SvcXlsxTestBook(sheets: [one]).firstSheet()
        #expect(s1.cell(3, 2).value == .number(5) && s1.cell(2, 2).isEmpty && s1.cell(2, 4).value == .number(6))
        #expect(s1.cell(1, 2).value == .text("Column2") && s1.cell(1, 3).value == .text("Column3"))

        let two = SvcXlsxTestBook.Sheet(name: "S", sheetData: "<row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>Column2</t></is></c></row>",
                                        parts: [table("A1:C5")])
        let (_, s2) = try SvcXlsxTestBook(sheets: [two]).firstSheet()
        #expect(s2.cell(1, 2).value == .text("Column3"))
        let three = SvcXlsxTestBook.Sheet(name: "S", sheetData: "<row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>Name</t></is></c><c r=\"C1\" t=\"inlineStr\"><is><t>Column2</t></is></c></row>",
                                          parts: [table("A1:C5")])
        let (_, s3) = try SvcXlsxTestBook(sheets: [three]).firstSheet()
        #expect(s3.cell(1, 2).value == .text("Column2"))
    }

    @Test func gateMessages() throws {
        // TV: 10 X.8.8
        let folder = TempFolder("aa-xlsx-gate")
        func open(_ name: String) -> XlsxReadError? {
            do { _ = try XlsxWorkbook.open(folder.file(name)); return nil } catch { return error }
        }
        #expect(open("jobs.csv") == .gate("Extension 'csv' is not supported. Supported extensions are '.xlsx', '.xlsm', '.xltx' and '.xltm'."))
        #expect(open("jobs.XLS") == .gate("Extension 'xls' is not supported. Supported extensions are '.xlsx', '.xlsm', '.xltx' and '.xltm'."))
        #expect(open("jobs") == .gate("Empty extension is not supported."))
        #expect(open("jobs.") == .gate("Empty extension is not supported."))
        let book = SvcXlsxTestBook(sheetData: "<row r=\"1\"><c r=\"A1\"><v>1</v></c></row>")
        for name in ["JOBS.XLSX", "jobs.xlsm", ".xlsx"] {
            try book.write(to: folder.file(name))
            #expect(open(name) == nil, "\(name)")
        }
        try folder.write("csv.xlsx", "a,b\n1,2\n")
        if case .corrupt? = open("csv.xlsx") {} else { Issue.record("a CSV named .xlsx must be corrupt") }
        #expect(XlsxReadError.corrupt(detail: "x").errorDescription == "The file could not be opened as an Excel workbook (.xlsx).\nx")
        #expect(XlsxReadError.corrupt(detail: "").errorDescription == "The file could not be opened as an Excel workbook (.xlsx).")

        let unknownType = SvcXlsxTestBook(sheetData: "<row r=\"1\"><c r=\"A1\" t=\"z\"><v>1</v></c></row>")
        #expect(throws: XlsxReadError.self) { _ = try unknownType.firstSheet() }
        let badStyle = SvcXlsxTestBook(sheetData: "<row r=\"1\"><c r=\"A1\" s=\"99\"><v>1</v></c></row>", xfs: Array(repeating: 0, count: 12))
        #expect(throws: XlsxReadError.self) { _ = try badStyle.firstSheet() }
        let noStyles = SvcXlsxTestBook(sheetData: "<row r=\"1\"><c r=\"A1\" s=\"99\"><v>1</v></c></row>", xfs: nil)
        #expect(try noStyles.firstSheet().1.cell(1, 1).value == .number(1))
        let malformed = SvcXlsxTestBook(sheetData: "<row r=\"1\"><c r=\"A1\"><v>1</v></row>")
        #expect(throws: XlsxReadError.self) { _ = try malformed.firstSheet() }
        let nan = SvcXlsxTestBook(sheetData: "<row r=\"1\"><c r=\"A1\"><v>NaN</v></c></row>")
        #expect(throws: XlsxReadError.self) { _ = try nan.firstSheet() }
    }

    @Test func pocLayoutA() throws {
        // TV: 10 X.8.7 row 1, X.8.9 layout A
        let wb = try XlsxWorkbook.open(Fixtures.url("xlsx/Last Ports - 24 Months (4).xlsx"))
        let sheet = try wb.load(wb.worksheets[0])
        let r = try #require(sheet.rangeUsed())
        #expect(range(sheet) == [2, 1, 53, 13])
        var dates = 0
        for row in r.firstRow...r.lastRow {
            for col in r.firstColumn...r.lastColumn {
                let text = try XlsxRender.portsCell(sheet.cell(row, col), workbook: wb)
                if text.count == 10, text.dropFirst(2).first == "/" { dates += 1 }
            }
        }
        #expect(dates > 0)
        #expect(sheet.cell(6, 3).value != .blank)
        if case .text = sheet.cell(6, 3).value {} else { Issue.record("C6 must be text (a shared string styled id14)") }
    }

    @Test func pocLayoutB() throws {
        // TV: 10 X.8.7 row 2, X.8.9 layout B
        let wb = try XlsxWorkbook.open(Fixtures.url("xlsx/Port of Call List - Last 10 Ports (14).xlsx"))
        #expect(wb.worksheets.count >= 1 && !wb.use1904)
        let first = try #require(wb.worksheets.first)
        #expect(first.name == "Sheet1")
        let sheet = try wb.load(first)
        let r = try #require(sheet.rangeUsed())
        #expect(range(sheet) == [1, 1, 18, 12])
        for ref in wb.worksheets.dropFirst() { #expect(try wb.load(ref).rangeUsed() == nil) }
        #expect(try XlsxRender.portsCell(sheet.cell(7, 9), workbook: wb) == "22:00")
        var texts: [String] = []
        for row in r.firstRow...r.lastRow {
            for col in r.firstColumn...r.lastColumn { texts.append(try XlsxRender.portsCell(sheet.cell(row, col), workbook: wb)) }
        }
        #expect(texts.contains("9792606") && texts.contains("9V6330"))
        #expect(texts.contains { $0.uppercased().contains("BW PAVILION ARANDA") })
    }

    @Test func largeSheetIsFast() throws {
        // X.7.2 / ARCHITECTURE.md §9.7: a 2 524 × 16 Shippalm-sized sheet parses and renders in < 200 ms
        var sst: [String] = []
        var rows = ""
        rows.reserveCapacity(2_600_000)
        for r in 1...2524 {
            rows += "<row r=\"\(r)\">"
            for c in 1...16 {
                let ref = String(UnicodeScalar(UInt8(64 + c))) + String(r)
                if c % 2 == 0 {
                    sst.append("<t>Work order \(r)-\(c)</t>")
                    rows += "<c r=\"\(ref)\" t=\"s\"><v>\(sst.count - 1)</v></c>"
                } else if c == 3 {
                    rows += "<c r=\"\(ref)\" s=\"1\"><v>\(46000 + r % 300)</v></c>"
                } else {
                    rows += "<c r=\"\(ref)\"><v>\(r * c)</v></c>"
                }
            }
            rows += "</row>"
        }
        let data = try SvcXlsxTestBook(sheetData: rows, xfs: [0, 14], sharedStrings: sst).data()
        let start = Date()
        let wb = try XlsxWorkbook.open(data: data)
        let sheet = try wb.load(wb.worksheets[0])
        let r = try #require(sheet.rangeUsed())
        var n = 0
        for row in r.firstRow...r.lastRow {
            for col in r.firstColumn...r.lastColumn { n += try XlsxRender.shippalmCell(sheet.cell(row, col), workbook: wb).isEmpty ? 0 : 1 }
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(n == 2524 * 16)
        // The 200 ms budget is for the optimised (shipping) build — `swift test -c release -Xswiftc -enable-testing`
        // runs this in ~40 ms on Apple silicon. An unoptimised debug build is ~10× slower, so it gets a looser
        // bound that still catches an algorithmic regression.
        #if DEBUG
        let budget = 1.5
        #else
        let budget = 0.2
        #endif
        #expect(elapsed < budget, "parsed and rendered 2 524 × 16 in \(Int(elapsed * 1000)) ms")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: Fixtures.url("winfixtures/xlsx").path)))
    func windowsGoldens() throws {
        // Post-merge (W-GOLD's XlsxGolden output, 10 X.7.6): every fixture's golden JSON must match this reader.
        let folder = Fixtures.url("winfixtures/xlsx")
        let goldens = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".golden.json") }
        for golden in goldens {
            let name = String(golden.lastPathComponent.dropLast(".golden.json".count))
            let fixture = Fixtures.url("xlsx/\(name)")
            guard FileManager.default.fileExists(atPath: fixture.path) else { continue }
            let wb = try XlsxWorkbook.open(fixture)
            let tree = try JSONParser.parse(try Data(contentsOf: golden))
            for ref in wb.worksheets {
                guard let sheetGolden = tree.objectValue?[ref.name]?.objectValue else { continue }
                let sheet = try wb.load(ref)
                for (address, expected) in sheetGolden["cells"]?.objectValue ?? JSONObject() {
                    guard let rc = SvcCellKey.parse(address), let e = expected.objectValue else { continue }
                    let cell = sheet.cell(rc.row, rc.column)
                    if let a = e["compas"]?.stringValue { #expect((try? XlsxRender.compasCellString(cell, workbook: wb)) == a, "\(name) \(address)") }
                    if let c = e["ports"]?.stringValue { #expect((try? XlsxRender.portsCell(cell, workbook: wb)) == c, "\(name) \(address)") }
                }
            }
        }
    }
}
