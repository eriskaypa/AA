// W-VESSEL test helpers (ARCHITECTURE.md §12.2: prefixed, owner-local). Hand-built OOXML packages written with F1's
// package writer, so no Excel is needed (10 §X.8 notation).
import Foundation
import Testing
@testable import AACore

/// A tiny workbook builder: one sheet, raw `<c>` XML per cell, optional shared strings and number formats.
struct VesselTestWorkbook {
    var sheetName = "Sheet1"
    /// Shared strings, referenced by index from `t="s"` cells.
    var sharedStrings: [String] = []
    /// Raw `<row>` contents keyed by row number.
    var rows: [Int: [String]] = [:]
    /// `cellXfs` numFmtIds (index = style `s`); index 0 is General.
    var xfNumFmts: [Int] = [0]

    /// A text cell through the shared-string table.
    mutating func text(_ ref: String, _ s: String) {
        let idx: Int
        if let i = sharedStrings.firstIndex(of: s) { idx = i } else { sharedStrings.append(s); idx = sharedStrings.count - 1 }
        add(ref, "<c r=\"\(ref)\" t=\"s\"><v>\(idx)</v></c>")
    }

    /// A numeric cell with an optional built-in number format id.
    mutating func number(_ ref: String, _ v: String, numFmt: Int? = nil) {
        var s = 0
        if let numFmt {
            if let i = xfNumFmts.firstIndex(of: numFmt) { s = i } else { xfNumFmts.append(numFmt); s = xfNumFmts.count - 1 }
        }
        add(ref, "<c r=\"\(ref)\" s=\"\(s)\"><v>\(v)</v></c>")
    }

    mutating func raw(_ ref: String, _ xml: String) { add(ref, xml) }

    private mutating func add(_ ref: String, _ xml: String) {
        let digits = ref.drop { $0.isLetter }
        let r = Int(digits) ?? 1
        rows[r, default: []].append(xml)
    }

    /// A row of text cells starting at column A.
    mutating func textRow(_ r: Int, _ values: [String]) {
        for (i, v) in values.enumerated() where !v.isEmpty { text("\(XlsxWriter.colRef(i))\(r)", v) }
    }

    func parts() -> [(path: String, data: Data)] {
        func esc(_ s: String) -> String { XlsxWriter.xmlEscape(s) }
        let ct = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """
        let wbRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>
        """
        let wb = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="\(esc(sheetName))" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
        let xfs = xfNumFmts.map { "<xf numFmtId=\"\($0)\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>" }.joined()
        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/></font></fonts><fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="\(xfNumFmts.count)">\(xfs)</cellXfs></styleSheet>
        """
        let sst = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"\(sharedStrings.count)\" uniqueCount=\"\(sharedStrings.count)\">"
            + sharedStrings.map { "<si><t xml:space=\"preserve\">\(esc($0))</t></si>" }.joined() + "</sst>"
        var sheet = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
        for r in rows.keys.sorted() { sheet += "<row r=\"\(r)\">" + rows[r]!.joined() + "</row>" }
        sheet += "</sheetData></worksheet>"
        return [("[Content_Types].xml", Data(ct.utf8)), ("_rels/.rels", Data(rels.utf8)), ("xl/workbook.xml", Data(wb.utf8)),
                ("xl/_rels/workbook.xml.rels", Data(wbRels.utf8)), ("xl/styles.xml", Data(styles.utf8)),
                ("xl/sharedStrings.xml", Data(sst.utf8)), ("xl/worksheets/sheet1.xml", Data(sheet.utf8))]
    }

    /// Writes the package to `<folder>/<name>`.
    func write(in folder: TempFolder, name: String = "book.xlsx") throws -> URL {
        let url = folder.file(name)
        try XlsxWriter.writePackage(to: url, parts: parts())
        return url
    }
}

/// Fixed test instants (10 §7: today 2026-09-29 local).
enum VesselTestClock {
    static let zone = TimeZone(identifier: "Europe/Athens")!
    static let today = CivilDate(year: 2026, month: 9, day: 29)!
    static let clock = FixedClock(local: "2026-09-29T10:15:00", zone: zone)
    static var now: NetDateTime { clock.now() }
}

/// The two POC workbooks copied to `Fixtures/vessel/` (10 §4.8–4.9).
enum VesselPOC {
    static let layoutA = "vessel/Last Ports - 24 Months (4).xlsx"
    static let layoutB = "vessel/Port of Call List - Last 10 Ports (14).xlsx"

    static func read(_ path: String) throws -> PortCallReadResult {
        try PortCallReader.read(url: Fixtures.url(path), now: VesselTestClock.now, today: VesselTestClock.today,
                                zone: VesselTestClock.zone)
    }

    @MainActor static func calls(_ path: String) throws -> [PortCall] {
        try read(path).calls.map { $0.makePortCall() }
    }
}
