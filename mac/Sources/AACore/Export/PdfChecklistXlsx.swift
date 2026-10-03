// Spec: 11 §2.8 PDF-090…094 (checklist-only Excel), §3.6 (rows; DEV-03 sheet-name rule), §4.5 (exact package
//       parts), §7.14 (package rows); 06 §4.8 (BUILD-C2); 04 §3.9, §7.10; ARCHITECTURE.md §6.4 (F1's XLSX package
//       writer and its constant parts are reused).
import Foundation

/// Product D: the checklist-only `.xlsx` (six parts, in order, UTF-8 without BOM).
public enum PdfChecklistXlsx {
    public static let header = ["#", "Done", "Step", "Due", "Linked Tasks", "Linked Equipment/Area"]

    /// 11 §3.6.1: header + one row per step; names resolved with FindById (any kind), missing ids dropped,
    /// joined with `"; "`; every value is text.
    public static func rows(_ s: PdfChecklistSnapshot) -> [[String]] {
        var rows = [header]
        for (i, st) in s.steps.enumerated() {
            let tasks = st.taskIds.compactMap { s.lookup.find($0)?.name }.joined(separator: "; ")
            let eqs = st.equipmentIds.compactMap { s.lookup.find($0)?.name }.joined(separator: "; ")
            rows.append([String(i + 1), st.done ? "Yes" : "No", st.title, st.deadline?.iso ?? "", tasks, eqs])
        }
        return rows
    }

    /// PDF-091 / DEV-03: sanitise → truncate (31 UTF-16 units) → XML-escape; blank → `Checklist`.
    public static func sheetName(_ procedureName: String) -> String {
        XlsxWriter.sanitizeSheetName(procedureName, fallback: "Checklist")
    }

    /// 11 §4.5.6 `sheet1.xml`: fixed `<cols>` 5/7/55/14/40/40, one `<row>` per line, every cell an inline string
    /// (`s="1"` on row 1, else `s="0"`), cells A..F, empty cells written; text escaped (DEV-03: XML-illegal
    /// characters dropped).
    public static func sheetXml(_ rows: [[String]]) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        s += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">\n"
        s += "<cols>\n"
        for (i, w) in [5, 7, 55, 14, 40, 40].enumerated() {
            s += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(w)\" customWidth=\"1\"/>\n"
        }
        s += "</cols>\n<sheetData>\n"
        for (r, row) in rows.enumerated() {
            s += "<row r=\"\(r + 1)\">"
            let style = r == 0 ? 1 : 0
            for (c, text) in row.enumerated() {
                s += "<c r=\"\(XlsxWriter.colRef(c))\(r + 1)\" t=\"inlineStr\" s=\"\(style)\"><is><t xml:space=\"preserve\">"
                s += XlsxWriter.xmlEscape(text) + "</t></is></c>"
            }
            s += "</row>\n"
        }
        s += "</sheetData>\n</worksheet>\n"
        return s
    }

    /// The six parts in PDF-090 order.
    public static func parts(_ s: PdfChecklistSnapshot) -> [(path: String, data: Data)] {
        [
            ("[Content_Types].xml", Data(XlsxWriter.contentTypesXml.utf8)),
            ("_rels/.rels", Data(XlsxWriter.rootRelsXml.utf8)),
            ("xl/workbook.xml", Data(XlsxWriter.workbookXml(safeName: sheetName(s.name)).utf8)),
            ("xl/_rels/workbook.xml.rels", Data(XlsxWriter.workbookRelsXml.utf8)),
            ("xl/styles.xml", Data(XlsxWriter.stylesXml.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheetXml(rows(s)).utf8)),
        ]
    }

    /// Writes the workbook (temp file next to `url`, then an atomic replace — the "delete first" of PDF-090).
    public static func write(_ s: PdfChecklistSnapshot, to url: URL) throws {
        try XlsxWriter.writePackage(to: url, parts: parts(s))
    }
}
