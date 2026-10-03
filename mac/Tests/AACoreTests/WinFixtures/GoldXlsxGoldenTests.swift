// The XLSX-reader goldens (spec 10 §X.7.6): the C# XlsxGolden oracle records, for every workbook in
// Fixtures/xlsx (F2's POC copies) and Fixtures/winfixtures/xlsx-inputs (the synthetic 10 §X.8 workbooks below), what
// ClosedXML + the app's renderers produce; this suite asserts F2's XlsxWorkbook + XlsxRender against them. The
// synthetic workbooks are written by the AACore ZIP writer exactly like F2's own tests, by an env-gated emitter
// (`AA_EMIT_XLSX_INPUTS=1`, Scripts/fixtures.sh emit-xlsx-inputs) and committed so XlsxGolden can read them.
import Foundation
import Testing
@testable import AACore

enum GoldXlsxInputs {
    /// Style index → numFmtId: 0→0, 1→14, 2→22, 3→164 "dd/mm/yyyy", 4→17, 5→30, 6→20, 7→46, 8→21, 9→165 "[h]:mm".
    static let xfs = [0, 14, 22, 164, 17, 30, 20, 46, 21, 165]
    static let numFmts: [(Int, String)] = [(164, "dd/mm/yyyy"), (165, "[h]:mm")]

    /// Column A of row r: `<c r="A{r}" …>`.
    static func cell(_ r: Int, style: Int? = nil, type: String? = nil, _ inner: String) -> String {
        let s = style.map { " s=\"\($0)\"" } ?? ""
        let t = type.map { " t=\"\($0)\"" } ?? ""
        return "<row r=\"\(r)\"><c r=\"A\(r)\"\(s)\(t)>\(inner)</c></row>"
    }
    static func v(_ r: Int, style: Int? = nil, type: String? = nil, _ value: String) -> String { cell(r, style: style, type: type, "<v>\(value)</v>") }

    /// X.8.1 matrix + X.8.3 serials + X.8.4 durations + X.8.5 number text + X.8.6 strings (1900 system).
    static var matrix: SvcXlsxTestBook {
        var rows: [String] = [
            v(1, style: 1, "45000"), v(2, style: 2, "45000.75"), v(3, style: 3, "45000"), v(4, style: 4, "45000"),
            v(5, style: 5, "45000"), v(6, style: 6, "0.5"), v(7, style: 6, "0.25"), v(8, style: 7, "1.5"),
            v(9, style: 8, "0.500001"), v(10, style: 1, "0.5"), v(11, style: 9, "1.5"), v(12, style: 1, type: "s", "0"),
            v(13, type: "s", "1"), cell(14, type: "inlineStr", "<is><t>2026-03-04</t></is>"), v(15, "48108"),
            v(16, type: "b", "1"), v(17, type: "b", "0"), v(18, type: "b", "false"), v(19, type: "b", "yes"),
            v(20, type: "e", "#N/A"), v(21, type: "e", "#SPILL!"),
        ]
        var r = 22
        // X.8.3 serials (id14 / id22) — the failing 60.5 and 2958466 have their own workbooks.
        for (value, style) in [("0", 1), ("1", 1), ("59", 1), ("60", 1), ("61", 1), ("46085", 1), ("46096", 1),
                               ("46218.99999999", 2), ("46218.999999999", 2), ("-1.25", 2), ("-0.25", 2), ("2958465.999999", 1)] {
            rows.append(v(r, style: style, value)); r += 1
        }
        // `t="d"` ISO cells.
        for value in ["2026-03-04", "2026-03-04T10:30", "2026-03-04T10:30:00.000"] { rows.append(v(r, type: "d", value)); r += 1 }
        // X.8.4 durations (id21 = [h]:mm:ss-like time).
        for value in ["0", "0.25", "0.5", "0.500001", "0.999999", "1.5", "0.500002314814815", "0.500002893518519", "0.563138888888889"] {
            rows.append(v(r, style: 8, value)); r += 1
        }
        // X.8.5 number text (unstyled).
        for value in ["12345.0", "180.5", "0.30000000000000004", "1E-7", "0.0001", "0.00001234", "0.00005", "2.00005",
                      "1234.56785", "1234.56789", "-3", "-1.5", "-0", "-0.00001", "9792606", "123456789012345.6",
                      "1000000000000000.5", "12345678901234567", "1E+20"] {
            rows.append(v(r, value)); r += 1
        }
        // X.8.6 strings: plain, rich runs with a phonetic run, _xHHHH_ escapes, interior newline.
        for k in 2..<6 { rows.append(v(r, type: "s", String(k))); r += 1 }
        rows.append(cell(r, type: "inlineStr", "<is><r><t>Line </t></r><r><t>one\nline two</t></r></is>")); r += 1
        return SvcXlsxTestBook(sheetData: rows.joined(separator: "\n"), xfs: xfs, numFmts: numFmts, sharedStrings: [
            "<t>2026-03-04</t>", "<t xml:space=\"preserve\">  2026-03-04 </t>", "<t>Hello</t>",
            "<r><t xml:space=\"preserve\">Hello </t></r><r><rPr><b/></rPr><t>World</t></r><rPh sb=\"0\" eb=\"1\"><t>ハロー</t></rPh><phoneticPr fontId=\"1\"/>",
            "<t>A_x000D__x000A_B _x0041_ _X0041_ _x005F_x0041_</t>",
            "<t xml:space=\"preserve\">two\nlines</t>",
        ])
    }

    /// X.8.3 1904 system.
    static var matrix1904: SvcXlsxTestBook {
        SvcXlsxTestBook(sheetData: [v(1, style: 1, "44623"), v(2, style: 1, "45000"), v(3, style: 1, "0"), v(4, "44623"),
                                    v(5, type: "d", "2026-03-04")].joined(separator: "\n"),
                        xfs: xfs, numFmts: numFmts, date1904: true)
    }

    /// X.8.1 M7/M7a: merged header without and with a stale value in the covered cell.
    static var merged: SvcXlsxTestBook {
        var b = SvcXlsxTestBook(sheets: [
            .init(name: "Ports", sheetData: "<row r=\"5\"><c r=\"A5\" t=\"s\"><v>0</v></c></row>",
                  extra: "<mergeCells count=\"1\"><mergeCell ref=\"A5:C5\"/></mergeCells>"),
            .init(name: "Stale", sheetData: "<row r=\"5\"><c r=\"A5\" t=\"s\"><v>0</v></c><c r=\"C5\" t=\"s\"><v>1</v></c></row>",
                  extra: "<mergeCells count=\"1\"><mergeCell ref=\"A5:C5\"/></mergeCells>"),
        ], xfs: xfs, sharedStrings: ["<t>Port</t>", "<t>X</t>"])
        b.numFmts = numFmts
        return b
    }

    /// Workbooks the import must reject (10 §X.8.3): kept separate so the rest of the matrix stays readable.
    static var serial605: SvcXlsxTestBook { SvcXlsxTestBook(sheetData: v(1, style: 1, "60.5"), xfs: xfs, numFmts: numFmts) }
    static var serialTooLarge: SvcXlsxTestBook { SvcXlsxTestBook(sheetData: v(1, style: 1, "2958466"), xfs: xfs, numFmts: numFmts) }
    static var isoSeconds: SvcXlsxTestBook { SvcXlsxTestBook(sheetData: v(1, type: "d", "2026-03-04T10:30:00"), xfs: xfs, numFmts: numFmts) }

    static var all: [(String, SvcXlsxTestBook)] {
        [("x8-matrix-1900.xlsx", matrix), ("x8-matrix-1904.xlsx", matrix1904), ("x8-merged.xlsx", merged),
         ("x8-serial-60.5.xlsx", serial605), ("x8-serial-2958466.xlsx", serialTooLarge), ("x8-tdate-seconds.xlsx", isoSeconds)]
    }

    // MARK: Golden comparison

    static func columnIndex(_ letters: Substring) -> Int {
        letters.reduce(0) { $0 * 26 + Int($1.asciiValue! - 64) }
    }

    /// "B12" → (12, 2).
    static func parse(_ address: String) -> (row: Int, column: Int)? {
        let letters = address.prefix { $0.isLetter && $0.isASCII && $0.isUppercase }
        guard !letters.isEmpty, let row = Int(address.dropFirst(letters.count)) else { return nil }
        return (row, columnIndex(letters))
    }

    static func letters(_ c: Int) -> String {
        var n = c, s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(UInt8(65 + r))) + s; n = (n - 1) / 26 }
        return s
    }

    static func kindName(_ cell: XlsxCell) -> String {
        if cell.isEmpty { return "Blank" }
        switch cell.value {
        case .blank: return "Blank"
        case .text: return "Text"
        case .number: return "Number"
        case .boolean: return "Boolean"
        case .error: return "Error"
        case .dateTime: return "DateTime"
        case .timeSpan: return "TimeSpan"
        }
    }

    /// Every disagreement between a golden and the Swift reader for one workbook.
    static func compare(golden: JSONObject, workbook url: URL) -> [String] {
        var problems: [String] = []
        let today = golden["$meta"]?.objectValue?["today"]?.stringValue.flatMap(CivilDate.init(iso:)) ?? CivilDate(year: 2026, month: 9, day: 29)!
        let wb: XlsxWorkbook
        do { wb = try XlsxWorkbook.open(url) } catch {
            if golden["$error"] == nil { problems.append("the Mac reader cannot open the workbook (\(error)); Windows can") }
            return problems
        }
        if golden["$error"] != nil { problems.append("Windows refuses to open the workbook; the Mac opens it") }
        for (sheetName, value) in golden where !sheetName.hasPrefix("$") {
            guard let sheetGolden = value.objectValue else { continue }
            guard let ref = wb.worksheet(named: sheetName) else { problems.append("\(sheetName): no such worksheet on the Mac"); continue }
            let sheet: XlsxWorksheet
            do { sheet = try wb.load(ref) } catch { problems.append("\(sheetName): load failed: \(error)"); continue }
            let used = sheet.rangeUsed().map { "\(letters($0.firstColumn))\($0.firstRow):\(letters($0.lastColumn))\($0.lastRow)" }
            if used != sheetGolden["usedRange"]?.stringValue {
                problems.append("\(sheetName): used range \(used ?? "nil") vs \(sheetGolden["usedRange"]?.stringValue ?? "nil")")
            }
            for (address, ev) in sheetGolden["cells"]?.objectValue ?? JSONObject() {
                guard let rc = parse(address), let e = ev.objectValue else { continue }
                let cell = sheet.cell(rc.row, rc.column)
                let errors = e["errors"]?.objectValue ?? JSONObject()
                func check(_ key: String, _ produce: () throws -> String) {
                    let result: Result<String, Error> = Result { try produce() }
                    switch (result, e[key]?.stringValue, errors[key]) {
                    case (.success(let s), let want?, _) where s != want:
                        problems.append("\(sheetName)!\(address) \(key): \(JSONWriter.escape(s)) vs Windows \(JSONWriter.escape(want))")
                    case (.success(let s), nil, _?):
                        problems.append("\(sheetName)!\(address) \(key): \(JSONWriter.escape(s)), Windows throws \(errors[key]?.stringValue ?? "")")
                    case (.failure(let err), _?, _):
                        problems.append("\(sheetName)!\(address) \(key): the Mac throws \(err)")
                    default: break
                    }
                }
                if let k = e["kind"]?.stringValue, k != kindName(cell) {
                    problems.append("\(sheetName)!\(address) kind: \(kindName(cell)) vs \(k)")
                }
                check("compas") { try XlsxRender.compasCellString(cell, workbook: wb) }
                check("shippalm") { try XlsxRender.shippalmCell(cell, workbook: wb) }
                if let b = try? XlsxRender.shippalmCell(cell, workbook: wb) { check("shippalmDate") { ShippalmDates.excelDate(b, today: today) } }
                check("ports") { try XlsxRender.portsCell(cell, workbook: wb) }
                // portsDate / portsTime are the Ports reader's NormDate/NormTime (W-VESSEL's private code).
            }
        }
        return problems
    }

    /// Every committed golden with the workbook it describes.
    static var goldens: [(golden: URL, workbook: URL)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: GoldPaths.xlsxGoldens.path) else { return [] }
        return names.filter { $0.hasSuffix(".golden.json") }.sorted().compactMap { name in
            let fixture = String(name.dropLast(".golden.json".count))
            for dir in [GoldPaths.f2Xlsx, GoldPaths.xlsxInputs] {
                let u = dir.appending(path: fixture)
                if fm.fileExists(atPath: u.path) { return (GoldPaths.xlsxGoldens.appending(path: name), u) }
            }
            return nil
        }
    }

    static var available: Bool { !goldens.isEmpty }
}

@Suite("WinFixtures — XLSX reader goldens (10 X.7.6)", .tags(.goldWinFixtures),
       .enabled(if: GoldXlsxInputs.available, "XlsxGolden output is absent: run `Scripts/fixtures.sh xlsx-golden` with the .NET 10 SDK (mac/Tools/XlsxGolden/README.md)"))
struct GoldXlsxGoldenTests {
    @Test("every workbook golden matches the Swift reader and renderers")
    func goldens() throws {
        for (golden, workbook) in GoldXlsxInputs.goldens {
            guard let tree = try JSONParser.parse(try Data(contentsOf: golden)).objectValue else {
                Issue.record("\(golden.lastPathComponent) is not a JSON object"); continue
            }
            for p in GoldXlsxInputs.compare(golden: tree, workbook: workbook) {
                Issue.record(Comment(rawValue: "\(workbook.lastPathComponent): \(p)"))
            }
        }
    }
}

@Suite("WinFixtures harness — XLSX inputs", .tags(.goldWinFixtures))
struct GoldXlsxInputEmitter {
    @Test("the synthetic 10 §X.8 workbooks are well-formed; the reader accepts the matrix ones")
    func wellFormed() throws {
        for (name, book) in GoldXlsxInputs.all {
            let data = try book.data()
            let zip = try GoldZipManifest(zip: data)
            #expect(zip.entries.contains { $0.name == "xl/worksheets/sheet1.xml" }, "\(name)")
            if name.contains("matrix") || name.contains("merged") {
                let wb = try XlsxWorkbook.open(data: data)
                #expect(!wb.worksheets.isEmpty)
            }
        }
    }

    @Test("a golden shaped like XlsxGolden's output compares cell by cell (synthetic)")
    func compareLogic() throws {
        let folder = TempFolder("gold-xlsx")
        let url = folder.file("book.xlsx")
        try GoldXlsxInputs.matrix.write(to: url)
        let wb = try XlsxWorkbook.open(url)
        let sheet = try wb.load(try #require(wb.worksheet(named: "Sheet1")))
        let used = try #require(sheet.rangeUsed())
        // A golden built from the Mac's own answers must compare clean; one changed value must be reported once.
        var cells = JSONObject()
        for address in ["A1", "A6", "A15", "A16", "A20"] {
            let rc = try #require(GoldXlsxInputs.parse(address))
            let cell = sheet.cell(rc.row, rc.column)
            var e = JSONObject([("kind", .string(GoldXlsxInputs.kindName(cell)))])
            if let v = try? XlsxRender.compasCellString(cell, workbook: wb) { e.set("compas", .string(v)) }
            if let v = try? XlsxRender.shippalmCell(cell, workbook: wb) {
                e.set("shippalm", .string(v))
                e.set("shippalmDate", .string(ShippalmDates.excelDate(v, today: CivilDate(year: 2026, month: 9, day: 29)!)))
            }
            if let v = try? XlsxRender.portsCell(cell, workbook: wb) { e.set("ports", .string(v)) }
            cells.set(address, .object(e))
        }
        let range = "\(GoldXlsxInputs.letters(used.firstColumn))\(used.firstRow):\(GoldXlsxInputs.letters(used.lastColumn))\(used.lastRow)"
        func golden(_ cells: JSONObject) -> JSONObject {
            JSONObject([("$meta", GoldDotNet.obj([("today", .string("2026-09-29"))])),
                        ("Sheet1", GoldDotNet.obj([("usedRange", .string(range)), ("cells", .object(cells))]))])
        }
        #expect(GoldXlsxInputs.compare(golden: golden(cells), workbook: url).isEmpty)
        var a1 = try #require(cells["A1"]?.objectValue)
        a1.set("compas", .string("not what the Mac says"))
        cells.set("A1", .object(a1))
        let problems = GoldXlsxInputs.compare(golden: golden(cells), workbook: url)
        #expect(problems.count == 1 && problems[0].contains("A1 compas"), "\(problems)")
        let ab12 = try #require(GoldXlsxInputs.parse("AB12"))
        #expect(ab12.row == 12 && ab12.column == 28)
        #expect(GoldXlsxInputs.letters(28) == "AB")
    }

    /// `AA_EMIT_XLSX_INPUTS=1`: (re)writes Fixtures/winfixtures/xlsx-inputs/ for the XlsxGolden oracle.
    @Test("emit the synthetic workbooks", .enabled(if: GoldEnv.emitXlsxInputs, "set AA_EMIT_XLSX_INPUTS=1 to (re)write Fixtures/winfixtures/xlsx-inputs"))
    func emit() throws {
        let dir = GoldPaths.xlsxInputs
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, book) in GoldXlsxInputs.all { try book.write(to: dir.appending(path: name)) }
    }
}
