// Tests for 10 Addendum X.8.1 (the required matrix: columns Kind, A, B, B+, C; C·D/C·T are W-VESSEL's).
import Foundation
import Testing
@testable import AACore

@Suite struct XlsxReadMatrixTests {
    static let today = CivilDate(iso: "2026-09-29")!

    // style index → numFmtId: 0→0, 1→14, 2→22, 3→164 "dd/mm/yyyy", 4→17, 5→30, 6→20, 7→46, 8→21, 9→165 "[h]:mm"
    static let book = SvcXlsxTestBook(
        sheetData: """
        <row r="1"><c r="A1" s="1"><v>45000</v></c></row>
        <row r="2"><c r="A2" s="2"><v>45000.75</v></c></row>
        <row r="3"><c r="A3" s="3"><v>45000</v></c></row>
        <row r="4"><c r="A4" s="4"><v>45000</v></c></row>
        <row r="5"><c r="A5" s="5"><v>45000</v></c></row>
        <row r="6"><c r="A6" s="6"><v>0.5</v></c></row>
        <row r="7"><c r="A7" s="6"><v>0.25</v></c></row>
        <row r="8"><c r="A8" s="7"><v>1.5</v></c></row>
        <row r="9"><c r="A9" s="8"><v>0.500001</v></c></row>
        <row r="10"><c r="A10" s="1"><v>0.5</v></c></row>
        <row r="11"><c r="A11" s="9"><v>1.5</v></c></row>
        <row r="12"><c r="A12" s="1" t="s"><v>0</v></c></row>
        <row r="13"><c r="A13" t="s"><v>1</v></c></row>
        <row r="14"><c r="A14" t="inlineStr"><is><t>2026-03-04</t></is></c></row>
        <row r="15"><c r="A15"><v>48108</v></c></row>
        <row r="16"><c r="A16" t="b"><v>1</v></c></row>
        <row r="17"><c r="A17" t="b"><v>0</v></c></row>
        <row r="18"><c r="A18" t="b"><v>false</v></c></row>
        <row r="19"><c r="A19" t="b"><v>yes</v></c></row>
        <row r="20"><c r="A20" t="e"><v>#N/A</v></c></row>
        <row r="21"><c r="A21" t="e"><v>#SPILL!</v></c></row>
        <row r="22"><c r="A22" t="s"><v>2</v></c><c r="C22" t="s"><v>3</v></c></row>
        <row r="23"><c r="A23" t="b"><v>TRUE</v></c></row>
        """,
        xfs: [0, 14, 22, 164, 17, 30, 20, 46, 21, 165],
        numFmts: [(164, "dd/mm/yyyy"), (165, "[h]:mm")],
        sharedStrings: ["<t>2026-03-04</t>", "<t xml:space=\"preserve\">  2026-03-04 </t>", "<t>Port</t>", "<t>X</t>"])

    struct Row: Sendable, CustomStringConvertible {
        let id: String, r: Int, c: Int, kind: String, a: String, bPlus: String, ports: String
        var description: String { id }
    }

    static let rows: [Row] = [
        Row(id: "M1", r: 1, c: 1, kind: "dateTime", a: "2023-03-15", bPlus: "2023-03-15", ports: "2023-03-15"),
        Row(id: "M1a", r: 2, c: 1, kind: "dateTime", a: "2023-03-15", bPlus: "2023-03-15", ports: "2023-03-15 18:00"),
        Row(id: "M1b", r: 3, c: 1, kind: "dateTime", a: "2023-03-15", bPlus: "2023-03-15", ports: "2023-03-15"),
        Row(id: "M1c", r: 4, c: 1, kind: "number", a: "45000", bPlus: "2023-03-15", ports: "45000"),
        Row(id: "M1d", r: 5, c: 1, kind: "number", a: "45000", bPlus: "2023-03-15", ports: "45000"),
        Row(id: "M2", r: 6, c: 1, kind: "timeSpan", a: "12:00:00", bPlus: "2026-09-29", ports: "12:00"),
        Row(id: "M2a", r: 7, c: 1, kind: "timeSpan", a: "6:00:00", bPlus: "2026-09-29", ports: "06:00"),
        Row(id: "M2b", r: 8, c: 1, kind: "timeSpan", a: "36:00:00", bPlus: "36:00:00", ports: "12:00"),
        Row(id: "M2c", r: 9, c: 1, kind: "timeSpan", a: "12:00:00.086", bPlus: "2026-09-29", ports: "12:00"),
        Row(id: "M2d", r: 10, c: 1, kind: "dateTime", a: "1899-12-31", bPlus: "1899-12-31", ports: "1899-12-31 12:00"),
        Row(id: "M2e", r: 11, c: 1, kind: "dateTime", a: "1900-01-01", bPlus: "1900-01-01", ports: "1900-01-01 12:00"),
        Row(id: "M3", r: 12, c: 1, kind: "text", a: "2026-03-04", bPlus: "2026-03-04", ports: "2026-03-04"),
        Row(id: "M3a", r: 13, c: 1, kind: "text", a: "2026-03-04", bPlus: "2026-03-04", ports: "2026-03-04"),
        Row(id: "M3b", r: 14, c: 1, kind: "text", a: "2026-03-04", bPlus: "2026-03-04", ports: "2026-03-04"),
        Row(id: "M4", r: 15, c: 1, kind: "number", a: "48108", bPlus: "2031-09-17", ports: "48108"),
        Row(id: "M5", r: 16, c: 1, kind: "boolean", a: "TRUE", bPlus: "TRUE", ports: "TRUE"),
        Row(id: "M5a.0", r: 17, c: 1, kind: "boolean", a: "FALSE", bPlus: "FALSE", ports: "FALSE"),
        Row(id: "M5a.false", r: 18, c: 1, kind: "boolean", a: "FALSE", bPlus: "FALSE", ports: "FALSE"),
        Row(id: "M5a.yes", r: 19, c: 1, kind: "boolean", a: "FALSE", bPlus: "FALSE", ports: "FALSE"),
        Row(id: "M6", r: 20, c: 1, kind: "error", a: "#N/A", bPlus: "#N/A", ports: "#N/A"),
        Row(id: "M6a", r: 21, c: 1, kind: "blank", a: "", bPlus: "", ports: ""),
        Row(id: "M7.A", r: 22, c: 1, kind: "text", a: "Port", bPlus: "Port", ports: "Port"),
        Row(id: "M7.B", r: 22, c: 2, kind: "blank", a: "", bPlus: "", ports: ""),
        Row(id: "M7a.C", r: 22, c: 3, kind: "text", a: "X", bPlus: "X", ports: "X"),
        Row(id: "M5.TRUE", r: 23, c: 1, kind: "boolean", a: "TRUE", bPlus: "TRUE", ports: "TRUE"),
    ]

    static func kind(_ v: XlsxValue) -> String {
        switch v {
        case .blank: return "blank"
        case .text: return "text"
        case .number: return "number"
        case .boolean: return "boolean"
        case .error: return "error"
        case .dateTime: return "dateTime"
        case .timeSpan: return "timeSpan"
        }
    }

    @Test(arguments: rows) func matrixRow(_ row: Row) throws {
        // TV: 10 X.8.1 (Kind/A/B/B+/C)
        let (wb, sheet) = try Self.book.firstSheet()
        let cell = sheet.cell(row.r, row.c)
        #expect(Self.kind(cell.value) == row.kind)
        let a = try XlsxRender.compasCellString(cell, workbook: wb)
        let b = try XlsxRender.shippalmCell(cell, workbook: wb)
        #expect(a == row.a)
        #expect(b == row.a)
        #expect(XlsxRender.shippalmExcelDate(b, today: Self.today) == row.bPlus)
        #expect(ShippalmDates.excelDate(b, today: Self.today) == row.bPlus)
        #expect(try XlsxRender.portsCell(cell, workbook: wb) == row.ports)
    }

    @Test func mergedHeaderDoesNotPropagate() throws {
        // TV: 10 X.8.1 M7 / VESSEL-322 (mergeCells parsed, no effect)
        var book = Self.book
        book.sheets[0].extra = "<mergeCells count=\"1\"><mergeCell ref=\"A22:C22\"/></mergeCells>"
        let (_, sheet) = try book.firstSheet()
        #expect(sheet.cell(22, 2).isEmpty && sheet.cell(22, 3).value == .text("X"))
    }
}
