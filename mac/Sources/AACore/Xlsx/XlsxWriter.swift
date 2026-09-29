// Spec: 09 §3.10, §4.10, §7.13 (exact package parts of XlsxWriter.Write), 10 §6.6 "Writing" (typed cells, bold
//       header, numFmtId 49 text columns, widths), 11 §4.5 (raw parts), §3.6.2 / DEV-03 and 01 OC-22 (sheet names:
//       sanitise → truncate → escape), 06 §7.13, 11 §7.14 (ColRef, escaping); ARCHITECTURE.md §6.4.
import Foundation

public enum XlsxCellValue: Sendable, Hashable { case text(String), number(Double), empty }

public struct XlsxColumnSpec: Sendable {
    public var width: Double?
    /// Text number format (`numFmtId 49`, `@`).
    public var textFormat: Bool = false
    public init(width: Double? = nil, textFormat: Bool = false) { self.width = width; self.textFormat = textFormat }
}

public struct XlsxSheetSpec: Sendable {
    public var name: String
    public var columns: [XlsxColumnSpec]
    public var boldHeader: Bool
    public var header: [String]
    public var rows: [[XlsxCellValue]]
    public init(name: String, columns: [XlsxColumnSpec], boldHeader: Bool, header: [String], rows: [[XlsxCellValue]]) {
        self.name = name; self.columns = columns; self.boldHeader = boldHeader; self.header = header; self.rows = rows
    }
}

public enum XlsxWriter {
    // MARK: Constant parts (09 §4.10 / 11 §4.5 — byte-identical text, LF newlines, no trailing newline)

    static let contentTypesXml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    static let rootRelsXml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    static let workbookRelsXml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    static let stylesXml = """
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

    /// 10 §6.6 styles: 0 normal · 1 bold + shaded header · 2 text (`numFmtId 49`) · 3 bold + shaded text header.
    static let extendedStylesXml = """
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
      <cellXfs count="4">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="1" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
        <xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
        <xf numFmtId="49" fontId="1" fillId="1" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/>
      </cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """

    static func workbookXml(safeName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="\(safeName)" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """
    }

    // MARK: Helpers (09 §3.10)

    /// Bijective base-26 from 0: A…Z, AA…AZ, BA…, ZZ, AAA.
    public static func colRef(_ index: Int) -> String {
        var i = index + 1
        var out: [Character] = []
        while i > 0 {
            let rem = (i - 1) % 26
            out.insert(Character(Unicode.Scalar(UInt8(65 + rem))), at: 0)
            i = (i - 1) / 26
        }
        return String(out)
    }

    /// Drops XML-1.0-illegal characters (< U+0020 except TAB/LF/CR, U+FFFE, U+FFFF); escapes `& < > "`
    /// (`'` is not escaped).
    public static func xmlEscape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for sc in text.unicodeScalars {
            let v = sc.value
            if (v < 0x20 && v != 0x09 && v != 0x0A && v != 0x0D) || v == 0xFFFE || v == 0xFFFF { continue }
            switch sc {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.unicodeScalars.append(sc)
            }
        }
        return out
    }

    /// OC-22 / 11 §3.6.2: blank → `fallback`; `: \ / ? * [ ]` → `_`; XML-illegal characters dropped; leading/trailing
    /// `'` trimmed; empty or `History` → `fallback`; truncated to 31 UTF-16 units without splitting a surrogate pair;
    /// then XML-escaped (the result is ready for `workbook.xml`).
    public static func sanitizeSheetName(_ name: String, fallback: String) -> String {
        var raw = NetText.isBlank(name) ? fallback : name
        var cleaned = String.UnicodeScalarView()
        for sc in raw.unicodeScalars {
            let v = sc.value
            if (v < 0x20 && v != 0x09 && v != 0x0A && v != 0x0D) || v == 0xFFFE || v == 0xFFFF { continue }
            if ":\\/?*[]".unicodeScalars.contains(sc) { cleaned.append("_") } else { cleaned.append(sc) }
        }
        raw = NetText.trim(String(cleaned), characters: [0x27])
        if raw.isEmpty || raw.caseInsensitiveCompare("History") == .orderedSame { raw = fallback }
        var units = Array(raw.utf16)
        if units.count > 31 {
            units = Array(units.prefix(31))
            if let last = units.last, UTF16.isLeadSurrogate(last) { units.removeLast() }
        }
        return xmlEscape(String(decoding: units, as: UTF16.self))
    }

    // MARK: 09 §3.10 — XlsxWriter.Write(path, sheetName, headers, rows)

    static func sheetXml(rows all: [[String]], colCount: Int) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        s += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">\n"
        if colCount > 0 {
            s += "<cols>\n<col min=\"1\" max=\"\(colCount)\" width=\"20\" customWidth=\"1\"/>\n</cols>\n"
        }
        s += "<sheetData>\n"
        for (r, row) in all.enumerated() {
            s += "<row r=\"\(r + 1)\">"
            let style = r == 0 ? 1 : 0
            for (c, text) in row.enumerated() {
                s += "<c r=\"\(colRef(c))\(r + 1)\" t=\"inlineStr\" s=\"\(style)\"><is><t xml:space=\"preserve\">"
                s += xmlEscape(text) + "</t></is></c>"
            }
            s += "</row>\n"
        }
        s += "</sheetData>\n</worksheet>\n"
        return s
    }

    /// 09 §3.10 / §4.10: header row bold + shaded, every cell an inline string, one `<col>` of width 20 over all
    /// header columns; rows of any length tolerated. Overwrites `url`.
    public static func write(to url: URL, sheetName: String, headers: [String], rows: [[String]]) throws {
        let all = [headers] + rows
        try writePackage(to: url, parts: [
            ("[Content_Types].xml", Data(contentTypesXml.utf8)),
            ("_rels/.rels", Data(rootRelsXml.utf8)),
            ("xl/workbook.xml", Data(workbookXml(safeName: sanitizeSheetName(sheetName, fallback: "Sheet1")).utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRelsXml.utf8)),
            ("xl/styles.xml", Data(stylesXml.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheetXml(rows: all, colCount: headers.count).utf8)),
        ])
    }

    // MARK: 10 §6.6 — typed cells, bold header, text columns, widths

    static func sheetXml(_ spec: XlsxSheetSpec) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        s += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">\n"
        let colLines: [String] = spec.columns.enumerated().compactMap { i, col in
            guard col.width != nil || col.textFormat else { return nil }
            var line = "<col min=\"\(i + 1)\" max=\"\(i + 1)\""
            if let w = col.width, let text = NetNumberText.shortest(w) { line += " width=\"\(text)\" customWidth=\"1\"" }
            if col.textFormat { line += " style=\"2\"" }
            return line + "/>"
        }
        if !colLines.isEmpty { s += "<cols>\n" + colLines.joined(separator: "\n") + "\n</cols>\n" }
        s += "<sheetData>\n"
        func isText(_ c: Int) -> Bool { c < spec.columns.count && spec.columns[c].textFormat }
        var rowNo = 1
        if !spec.header.isEmpty {
            s += "<row r=\"1\">"
            for (c, text) in spec.header.enumerated() {
                let style = spec.boldHeader ? (isText(c) ? 3 : 1) : (isText(c) ? 2 : 0)
                s += "<c r=\"\(colRef(c))1\" t=\"inlineStr\" s=\"\(style)\"><is><t xml:space=\"preserve\">"
                s += xmlEscape(text) + "</t></is></c>"
            }
            s += "</row>\n"
            rowNo = 2
        }
        for row in spec.rows {
            s += "<row r=\"\(rowNo)\">"
            for (c, cell) in row.enumerated() {
                let ref = "\(colRef(c))\(rowNo)"
                let style = isText(c) ? 2 : 0
                switch cell {
                case .text(let t):
                    s += "<c r=\"\(ref)\" t=\"inlineStr\" s=\"\(style)\"><is><t xml:space=\"preserve\">\(xmlEscape(t))</t></is></c>"
                case .number(let d):
                    if let text = NetNumberText.shortest(d) { s += "<c r=\"\(ref)\" s=\"\(style)\"><v>\(text)</v></c>" }
                case .empty:
                    break
                }
            }
            s += "</row>\n"
            rowNo += 1
        }
        s += "</sheetData>\n</worksheet>\n"
        return s
    }

    public static func write(to url: URL, sheet: XlsxSheetSpec) throws {
        try writePackage(to: url, parts: [
            ("[Content_Types].xml", Data(contentTypesXml.utf8)),
            ("_rels/.rels", Data(rootRelsXml.utf8)),
            ("xl/workbook.xml", Data(workbookXml(safeName: sanitizeSheetName(sheet.name, fallback: "Sheet1")).utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRelsXml.utf8)),
            ("xl/styles.xml", Data(extendedStylesXml.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheetXml(sheet).utf8)),
        ])
    }

    // MARK: 11 §4.5 — raw parts

    /// Writes the parts in order (Deflate) into a temp file next to `url`, then atomically replaces `url`.
    public static func writePackage(to url: URL, parts: [(path: String, data: Data)]) throws {
        let tmp = AtomicWrite.tempURL(for: url)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let zip = try ZipWriter(url: tmp)
        let now = Date()
        for p in parts { try zip.addData(p.data, named: p.path, modified: now) }
        try zip.finish()
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}
