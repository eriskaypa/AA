// TV: 09 §7.13 (ColRef, Esc, sheet names, package round trip with the §4.10 parts), 11 §7.14 (ColRef / escape /
//     sheet-name rows; the package rows are W-PDF's), 06 §7.13 (ColRef; sheet names under the OC-22 ruling),
//     01 TV-OWN-14 (OC-22 sheet names), 10 §6.6 "Writing" (typed cells, bold header, numFmtId 49, widths).
import Foundation
import Testing
@testable import AACore

@Suite struct XlsxWriterTests {
    static let partNames = ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels",
                            "xl/styles.xml", "xl/worksheets/sheet1.xml"]

    // 09 §4.10 constant parts, verbatim (LF newlines, no trailing newline)
    static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """
    static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """
    static let workbookCrew = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets>
        <sheet name="Crew" sheetId="1" r:id="rId1"/>
      </sheets>
    </workbook>
    """
    static let workbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """
    static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="2">
        <font><sz val="11"/><name val="Calibri"/></font>
        <font><b/><sz val="11"/><name val="Calibri"/></font>
      </fonts>
      <fills count="2">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFEEEEEE"/><bgColor indexed="64"/></patternFill></fill>
      </fills>
      <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="2">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="1" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
      </cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """
    /// 09 §4.10 sheet for headers ["Last Name","CID"], one row ["O'Neil & Co","<1>"] (trailing newline).
    static let sheetExample = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <cols>
    <col min="1" max="2" width="20" customWidth="1"/>
    </cols>
    <sheetData>
    <row r="1"><c r="A1" t="inlineStr" s="1"><is><t xml:space="preserve">Last Name</t></is></c><c r="B1" t="inlineStr" s="1"><is><t xml:space="preserve">CID</t></is></c></row>
    <row r="2"><c r="A2" t="inlineStr" s="0"><is><t xml:space="preserve">O'Neil &amp; Co</t></is></c><c r="B2" t="inlineStr" s="0"><is><t xml:space="preserve">&lt;1&gt;</t></is></c></row>
    </sheetData>
    </worksheet>

    """

    func parts(_ url: URL) throws -> [(String, String)] {
        let r = try ZipReader(url: url)
        return try r.entries.map { ($0.name, String(decoding: try r.data(for: $0), as: UTF8.self)) }
    }

    // TV: 09 §7.13 / 11 §7.14 / 06 §7.13 ColRef
    @Test func colRef() {
        let table: [(Int, String)] = [(0, "A"), (5, "F"), (25, "Z"), (26, "AA"), (27, "AB"), (51, "AZ"), (52, "BA"),
                                      (701, "ZZ"), (702, "AAA"), (18277, "ZZZ"), (18278, "AAAA")]
        for (i, s) in table { #expect(XlsxWriter.colRef(i) == s, "\(i)") }
    }

    // TV: 09 §7.13 Esc (plus the XML-illegal U+000B / U+FFFE rows of 11 §7.14)
    @Test func escaping() {
        #expect(XlsxWriter.xmlEscape("a\u{1}b") == "ab")
        #expect(XlsxWriter.xmlEscape("x\ty") == "x\ty")
        #expect(XlsxWriter.xmlEscape("\"") == "&quot;")
        #expect(XlsxWriter.xmlEscape("'") == "'")
        #expect(XlsxWriter.xmlEscape("&<>") == "&amp;&lt;&gt;")
        #expect(XlsxWriter.xmlEscape("l1\nl2\r\n") == "l1\nl2\r\n")
        #expect(XlsxWriter.xmlEscape("v\u{B}t\u{FFFE}\u{FFFF}") == "vt")
        #expect(XlsxWriter.xmlEscape("\u{2693} caf\u{E9} \u{1F600}") == "\u{2693} caf\u{E9} \u{1F600}")
    }

    // TV: 09 §7.13 sheet names, 11 §7.14 rows, 01 TV-OWN-14 (OC-22: sanitise → truncate → escape)
    @Test func sheetNames() {
        #expect(XlsxWriter.sanitizeSheetName("", fallback: "Sheet1") == "Sheet1")
        #expect(XlsxWriter.sanitizeSheetName("   ", fallback: "Sheet1") == "Sheet1")
        #expect(XlsxWriter.sanitizeSheetName("A&B", fallback: "Sheet1") == "A&amp;B")
        #expect(XlsxWriter.sanitizeSheetName("Crew", fallback: "Sheet1") == "Crew")
        #expect(XlsxWriter.sanitizeSheetName("report", fallback: "Sheet1") == "report")
        #expect(XlsxWriter.sanitizeSheetName("Ports of Call", fallback: "Sheet1") == "Ports of Call")
        #expect(XlsxWriter.sanitizeSheetName("Pump & Valve", fallback: "Checklist") == "Pump &amp; Valve")
        #expect(XlsxWriter.sanitizeSheetName("A/B: [x]*?", fallback: "Checklist") == "A_B_ _x___")
        #expect(XlsxWriter.sanitizeSheetName("A/B: [x]", fallback: "Checklist") == "A_B_ _x_")
        #expect(XlsxWriter.sanitizeSheetName(String(repeating: "a", count: 40), fallback: "Checklist") == String(repeating: "a", count: 31))
        #expect(XlsxWriter.sanitizeSheetName(String(repeating: "a", count: 29) + "&b", fallback: "Checklist")
                == String(repeating: "a", count: 29) + "&amp;b")
        #expect(XlsxWriter.sanitizeSheetName("History", fallback: "Checklist") == "Checklist")
        #expect(XlsxWriter.sanitizeSheetName("history", fallback: "Checklist") == "Checklist")
        #expect(XlsxWriter.sanitizeSheetName("'Quoted'", fallback: "Checklist") == "Quoted")
        #expect(XlsxWriter.sanitizeSheetName("''", fallback: "Checklist") == "Checklist")
        #expect(XlsxWriter.sanitizeSheetName("R&D", fallback: "Checklist") == "R&amp;D")
        #expect(XlsxWriter.sanitizeSheetName("Ti\u{B}tle", fallback: "Checklist") == "Title")
        // 06 §7.13 names under the Mac ruling (Windows truncated after escaping and could split an entity)
        #expect(XlsxWriter.sanitizeSheetName("R&D procedure with a very long name", fallback: "Checklist")
                == "R&amp;D procedure with a very long ")
        #expect(XlsxWriter.sanitizeSheetName("Engine room daily checks 2026 & more", fallback: "Checklist")
                == "Engine room daily checks 2026 &amp;")
        // never splits a surrogate pair: 30 × "a" + 😀 → the pair would straddle unit 31
        #expect(XlsxWriter.sanitizeSheetName(String(repeating: "a", count: 30) + "\u{1F600}", fallback: "S")
                == String(repeating: "a", count: 30))
    }

    // TV: 09 §7.13 round trip — 6 entries in order, constant parts byte-equal, sheet1.xml as §4.10, no BOM
    @Test func crewPackageBytes() throws {
        let folder = TempFolder()
        let url = folder.file("crew.xlsx")
        try folder.write("crew.xlsx", "old content is replaced")
        try XlsxWriter.write(to: url, sheetName: "Crew", headers: ["Last Name", "CID"], rows: [["O'Neil & Co", "<1>"]])
        let p = try parts(url)
        #expect(p.map(\.0) == Self.partNames)
        #expect(p[0].1 == Self.contentTypes)
        #expect(p[1].1 == Self.rootRels)
        #expect(p[2].1 == Self.workbookCrew)
        #expect(p[3].1 == Self.workbookRels)
        #expect(p[4].1 == Self.styles)
        #expect(p[5].1 == Self.sheetExample)
        let r = try ZipReader(url: url)
        for e in r.entries {
            #expect(e.method == 8)
            #expect(try r.data(for: e).prefix(3) != Data([0xEF, 0xBB, 0xBF]))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path) == ["crew.xlsx"])
    }

    // 09 §3.10: rows of any length, empty strings still produce a cell, no <cols> without headers
    @Test func raggedRowsAndNoHeaders() throws {
        let folder = TempFolder()
        let url = folder.file("r.xlsx")
        try XlsxWriter.write(to: url, sheetName: "", headers: [], rows: [["a", "", "c"], []])
        let p = try parts(url)
        #expect(p[2].1.contains(#"<sheet name="Sheet1" sheetId="1" r:id="rId1"/>"#))
        #expect(p[5].1 == """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>
        <row r="1"></row>
        <row r="2"><c r="A2" t="inlineStr" s="0"><is><t xml:space="preserve">a</t></is></c><c r="B2" t="inlineStr" s="0"><is><t xml:space="preserve"></t></is></c><c r="C2" t="inlineStr" s="0"><is><t xml:space="preserve">c</t></is></c></row>
        <row r="3"></row>
        </sheetData>
        </worksheet>

        """)
    }

    // 10 §6.6: per-cell type, bold header, numFmtId 49 text columns, widths
    @Test func typedSheet() throws {
        let folder = TempFolder()
        let url = folder.file("report.xlsx")
        let spec = XlsxSheetSpec(name: "report",
                                 columns: [XlsxColumnSpec(width: 12.5), XlsxColumnSpec(textFormat: true), XlsxColumnSpec()],
                                 boldHeader: true, header: ["Job", "Due", "Overdue Days"],
                                 rows: [[.text("J-1 & co"), .text("2026-10-01"), .number(-3)],
                                        [.text("J-2"), .empty, .number(0.1)]])
        try XlsxWriter.write(to: url, sheet: spec)
        let p = try parts(url)
        #expect(p.map(\.0) == Self.partNames)
        #expect(p[2].1.contains(#"<sheet name="report" sheetId="1" r:id="rId1"/>"#))
        #expect(p[4].1.contains(#"<cellXfs count="4">"#) && p[4].1.contains(#"numFmtId="49""#))
        #expect(p[5].1 == """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <cols>
        <col min="1" max="1" width="12.5" customWidth="1"/>
        <col min="2" max="2" style="2"/>
        </cols>
        <sheetData>
        <row r="1"><c r="A1" t="inlineStr" s="1"><is><t xml:space="preserve">Job</t></is></c><c r="B1" t="inlineStr" s="3"><is><t xml:space="preserve">Due</t></is></c><c r="C1" t="inlineStr" s="1"><is><t xml:space="preserve">Overdue Days</t></is></c></row>
        <row r="2"><c r="A2" t="inlineStr" s="0"><is><t xml:space="preserve">J-1 &amp; co</t></is></c><c r="B2" t="inlineStr" s="2"><is><t xml:space="preserve">2026-10-01</t></is></c><c r="C2" s="0"><v>-3</v></c></row>
        <row r="3"><c r="A3" t="inlineStr" s="0"><is><t xml:space="preserve">J-2</t></is></c><c r="C3" s="0"><v>0.1</v></c></row>
        </sheetData>
        </worksheet>

        """)
        // Not bold, no widths: no <cols>, header style 0
        try XlsxWriter.write(to: url, sheet: XlsxSheetSpec(name: "Ports of Call", columns: [], boldHeader: false,
                                                           header: ["A"], rows: [[.number(1e16)]]))
        let q = try parts(url)
        #expect(!q[5].1.contains("<cols>"))
        #expect(q[5].1.contains(#"<c r="A1" t="inlineStr" s="0">"#) && q[5].1.contains("<v>1E+16</v>"))
    }

    // 11 §4.5: raw parts written in the given order, Deflate, overwriting the target
    @Test func rawPackage() throws {
        let folder = TempFolder()
        let url = folder.file("pkg.xlsx")
        try XlsxWriter.writePackage(to: url, parts: [("b.xml", Data("<b/>".utf8)), ("a/x.xml", Data("<a/>".utf8))])
        try XlsxWriter.writePackage(to: url, parts: [("z.xml", Data("<z/>".utf8)), ("a.xml", Data("<a/>".utf8))])
        let p = try parts(url)
        #expect(p.map(\.0) == ["z.xml", "a.xml"] && p.map(\.1) == ["<z/>", "<a/>"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path) == ["pkg.xlsx"])
    }
}
