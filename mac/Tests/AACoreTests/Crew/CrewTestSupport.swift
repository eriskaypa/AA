// W-CREW test helpers: tiny hand-built COMPAS workbooks (written with F1's public `XlsxWriter.writePackage`) and crew
// fixtures. Spec: 09 §7 (today = 2026-09-29 unless noted).
import Foundation
@testable import AACore

enum CrewTestDates {
    static let today = CivilDate(year: 2026, month: 9, day: 29)!
    static let athens = TimeZone(identifier: "Europe/Athens")!
    static let clock = FixedClock(local: "2026-09-29T10:15:00", zone: athens)
}

/// A one-or-more-sheet SpreadsheetML package. Cells: `.s` inline text, `.n` number, `.d` a number styled as a date
/// (built-in numFmt 14), `.b` boolean, `.e` error.
struct CrewTestBook {
    enum Cell { case s(String), n(Double), d(Double), b(Bool), e(String), blank }

    struct Sheet {
        var name: String
        /// Rows from row 1; each inner array from column A.
        var rows: [[Cell]]
    }

    var sheets: [Sheet]
    var date1904 = false

    init(sheets: [Sheet], date1904: Bool = false) { self.sheets = sheets; self.date1904 = date1904 }
    init(rows: [[Cell]], name: String = "report", date1904: Bool = false) {
        self.sheets = [Sheet(name: name, rows: rows)]; self.date1904 = date1904
    }

    static let ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    static let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let pkgRel = "http://schemas.openxmlformats.org/package/2006/relationships"

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    func sheetXML(_ sheet: Sheet) -> String {
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"\(Self.ns)\"><sheetData>"
        for (r, row) in sheet.rows.enumerated() {
            x += "<row r=\"\(r + 1)\">"
            for (c, cell) in row.enumerated() {
                let ref = XlsxWriter.colRef(c) + String(r + 1)
                switch cell {
                case .s(let t): x += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(Self.esc(t))</t></is></c>"
                case .n(let v): x += "<c r=\"\(ref)\"><v>\(NetNumberText.shortest(v) ?? "0")</v></c>"
                case .d(let v): x += "<c r=\"\(ref)\" s=\"1\"><v>\(NetNumberText.shortest(v) ?? "0")</v></c>"
                case .b(let v): x += "<c r=\"\(ref)\" t=\"b\"><v>\(v ? 1 : 0)</v></c>"
                case .e(let v): x += "<c r=\"\(ref)\" t=\"e\"><v>\(Self.esc(v))</v></c>"
                case .blank: break
                }
            }
            x += "</row>"
        }
        return x + "</sheetData></worksheet>"
    }

    func write(to url: URL) throws {
        var parts: [(path: String, data: Data)] = []
        func add(_ p: String, _ s: String) { parts.append((p, Data(s.utf8))) }
        add("[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/></Types>")
        add("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"\(Self.pkgRel)\"><Relationship Id=\"rId1\" Type=\"\(Self.rel)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>")
        var sheetElems = "", rels = ""
        for (k, s) in sheets.enumerated() {
            sheetElems += "<sheet name=\"\(Self.esc(s.name))\" sheetId=\"\(k + 1)\" r:id=\"rId\(k + 1)\"/>"
            rels += "<Relationship Id=\"rId\(k + 1)\" Type=\"\(Self.rel)/worksheet\" Target=\"worksheets/sheet\(k + 1).xml\"/>"
        }
        rels += "<Relationship Id=\"rIdS\" Type=\"\(Self.rel)/styles\" Target=\"styles.xml\"/>"
        let pr = date1904 ? "<workbookPr date1904=\"1\"/>" : ""
        add("xl/workbook.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><workbook xmlns=\"\(Self.ns)\" xmlns:r=\"\(Self.rel)\">\(pr)<sheets>\(sheetElems)</sheets></workbook>")
        add("xl/_rels/workbook.xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"\(Self.pkgRel)\">\(rels)</Relationships>")
        add("xl/styles.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><styleSheet xmlns=\"\(Self.ns)\"><cellXfs count=\"2\"><xf numFmtId=\"0\"/><xf numFmtId=\"14\" applyNumberFormat=\"1\"/></cellXfs></styleSheet>")
        for (k, s) in sheets.enumerated() { add("xl/worksheets/sheet\(k + 1).xml", sheetXML(s)) }
        try XlsxWriter.writePackage(to: url, parts: parts)
    }

    func workbook() throws -> XlsxWorkbook {
        let folder = TempFolder("crew-book")
        let url = folder.file("book.xlsx")
        try write(to: url)
        return try XlsxWorkbook.open(url)
    }
}

/// The 33 COMPAS headers of 09 §4.9 in a realistic order.
enum CrewCompasHeaders {
    static let all = ["First name", "Surname", "Original middle name", "Name", "Code", "CMS ID Number", "Passport Number",
                      "Nationality code", "Nationality", "Date of Birth", "Place of Birth", "Gender", "Height",
                      "Eyes Colour", "Hair Colour", "Source", "Last Vessel", "Rank", "Joining Date", "Joining Port",
                      "Sign Off Date", "SignOff Port", "Passport Expiry Date", "Passport Issued Date",
                      "Seaman Book Number", "Seaman Book Expiry Date", "Seaman Book Issue Date", "Licence Number",
                      "Licence Expiry Date", "Licence Issue Date", "Medical Examination Expiry", "Next of Kin - Name",
                      "Next of Kin - Grade"]

    /// A row from header → text (missing headers are blank).
    static func row(_ values: [String: String]) -> CrewCompasRow {
        var v: [String: String] = [:]
        for h in all { v[CrewText.norm(h)] = values[h] ?? "" }
        return CrewCompasRow(values: v)
    }
}
