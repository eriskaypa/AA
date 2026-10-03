// TV: 11 §7.14 (package rows: 6 entries in order, no BOM, XML parses, sheet names, cell styles, `<cols>` widths),
//     §7.13 (XLSX rows), 04 §7.10 (checklist XLSX), PDF-090…094, DEV-03.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite("W-PDF checklist XLSX")
struct PdfChecklistXlsxTests {
    func written(_ s: PdfChecklistSnapshot) throws -> (ZipReader, TempFolder) {
        let folder = TempFolder("pdf-xlsx")
        let url = folder.file("out.xlsx")
        try "stale".write(to: url, atomically: true, encoding: .utf8)                       // replaced (PDF-090)
        try PdfChecklistXlsx.write(s, to: url)
        return (try ZipReader(url: url), folder)
    }

    func text(_ z: ZipReader, _ name: String) throws -> String {
        String(decoding: try z.data(for: try #require(z.entry(named: name))), as: UTF8.self)
    }

    /// Cell texts of sheet1.xml, row by row (parsed, not byte-compared — 11 §4.5 line-ending note).
    final class SheetParser: NSObject, XMLParserDelegate {
        var rows: [[String]] = []
        var styles: [[String]] = []
        var cols: [String] = []
        private var inT = false
        private var cell = ""
        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?,
                    attributes a: [String: String] = [:]) {
            switch e {
            case "row": rows.append([]); styles.append([])
            case "c": styles[styles.count - 1].append(a["s"] ?? "")
            case "t": inT = true; cell = ""
            case "col": cols.append(a["width"] ?? "")
            default: break
            }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { if inT { cell += s } }
        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            if e == "t" { inT = false; rows[rows.count - 1].append(cell) }
        }
    }

    func parse(_ xml: String) -> SheetParser {
        let d = SheetParser()
        let p = XMLParser(data: Data(xml.utf8))
        p.delegate = d
        #expect(p.parse())
        return d
    }

    // TV: 11 §7.13 XLSX rows; §7.14 package
    @Test func lotoWorkbook() throws {
        let g = PdfTestData.golden()
        let (z, folder) = try written(PdfSnapshotBuilder.checklist(g.loto, store: g.made.store))
        _ = folder
        #expect(z.entries.map(\.name) == ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
                                          "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml"])
        #expect(z.entries.allSatisfy { $0.method == 8 && !$0.isDirectory })
        for e in z.entries {
            let data = try z.data(for: e)
            #expect(!data.starts(with: [0xEF, 0xBB, 0xBF]))                                 // no BOM
            #expect(XMLParser(data: data).parse(), "\(e.name) parses")
        }
        #expect(try text(z, "xl/workbook.xml").contains("<sheet name=\"LOTO\" sheetId=\"1\" r:id=\"rId1\"/>"))
        #expect(try text(z, "xl/styles.xml") == XlsxWriter.stylesXml)
        let sheet = parse(try text(z, "xl/worksheets/sheet1.xml"))
        #expect(sheet.rows == [["#", "Done", "Step", "Due", "Linked Tasks", "Linked Equipment/Area"],
                               ["1", "Yes", "Isolate", "2026-07-01", "Pump overhaul", "Pump room"],
                               ["2", "No", "Tag", "", "", ""]])
        #expect(sheet.styles == [Array(repeating: "1", count: 6), Array(repeating: "0", count: 6), Array(repeating: "0", count: 6)])
        #expect(sheet.cols == ["5", "7", "55", "14", "40", "40"])
        let raw = try text(z, "xl/worksheets/sheet1.xml")
        #expect(raw.contains("<c r=\"F1\" t=\"inlineStr\" s=\"1\"><is><t xml:space=\"preserve\">Linked Equipment/Area</t></is></c>"))
        #expect(raw.contains("<c r=\"D3\" t=\"inlineStr\" s=\"0\"><is><t xml:space=\"preserve\"></t></is></c>"))
        #expect(!raw.contains("<pane") && !raw.contains("autoFilter"))
    }

    // TV: 04 §7.10
    @Test func fireAndRescue() throws {
        let t1 = UUID()
        let lookup = PdfLookup([PdfIndexEntry(id: t1, kind: .task, name: "Count crew")])
        let s = PdfChecklistSnapshot(name: "Fire & rescue", steps: [
            PdfStepSnapshot(title: "Muster", done: true, deadline: CivilDate(year: 2026, month: 10, day: 1), taskIds: [t1],
                            equipmentIds: [UUID()]),
            PdfStepSnapshot(title: "<Brief>", done: false),
        ], lookup: lookup)
        let (z, folder) = try written(s)
        _ = folder
        #expect(try text(z, "xl/workbook.xml").contains("name=\"Fire &amp; rescue\""))
        let raw = try text(z, "xl/worksheets/sheet1.xml")
        #expect(raw.contains("&lt;Brief&gt;"))
        #expect(parse(raw).rows == [PdfChecklistXlsx.header, ["1", "Yes", "Muster", "2026-10-01", "Count crew", ""],
                                    ["2", "No", "<Brief>", "", "", ""]])
    }

    // TV: 11 §7.14 sheet-name rows (DEV-03) and illegal characters
    @Test func sheetNames() {
        #expect(PdfChecklistXlsx.sheetName("Pump & Valve") == "Pump &amp; Valve")
        #expect(PdfChecklistXlsx.sheetName("A/B: [x]*?") == "A_B_ _x___")
        #expect(PdfChecklistXlsx.sheetName(String(repeating: "a", count: 40)) == String(repeating: "a", count: 31))
        #expect(PdfChecklistXlsx.sheetName(String(repeating: "a", count: 29) + "&b") == String(repeating: "a", count: 29) + "&amp;b")
        #expect(PdfChecklistXlsx.sheetName("  ") == "Checklist")
        #expect(PdfChecklistXlsx.sheetName("Tank\u{0B}check") == "Tankcheck")
        #expect(XlsxWriter.colRef(0) == "A" && XlsxWriter.colRef(25) == "Z" && XlsxWriter.colRef(26) == "AA")
        #expect(XlsxWriter.colRef(51) == "AZ" && XlsxWriter.colRef(52) == "BA" && XlsxWriter.colRef(701) == "ZZ")
        #expect(XlsxWriter.colRef(702) == "AAA")
    }

    // TV: 11 §7.14 — a title with U+000B is dropped from the cell text; header-only sheet for 0 steps
    @Test func illegalCharactersAndEmptyProcedure() throws {
        let (z, folder) = try written(PdfChecklistSnapshot(name: "X\u{0B}", steps: [PdfStepSnapshot(title: "a\u{0B}b")], lookup: PdfLookup()))
        _ = folder
        let raw = try text(z, "xl/worksheets/sheet1.xml")
        #expect(!raw.unicodeScalars.contains("\u{0B}"))
        #expect(parse(raw).rows[1][2] == "ab")
        let (e, f2) = try written(PdfChecklistSnapshot(name: "", steps: [], lookup: PdfLookup()))
        _ = f2
        #expect(parse(try text(e, "xl/worksheets/sheet1.xml")).rows == [PdfChecklistXlsx.header])
        #expect(try text(e, "xl/workbook.xml").contains("name=\"Checklist\""))
    }
}
