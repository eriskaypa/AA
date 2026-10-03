// Test support for the 10 Addendum X vectors: tiny hand-built .xlsx packages written with the AACore ZIP writer
// (10 §X.8: "Fixtures are tiny hand-built packages written by the AACore ZIP writer in the test, so no Excel is
// needed").
import Foundation
@testable import AACore

/// A minimal SpreadsheetML package. Each sheet is given as the inner XML of `<sheetData>` (plus optional extra
/// worksheet children and sheet-level relationships).
struct SvcXlsxTestBook: Sendable {
    struct Sheet: Sendable {
        var name: String
        var sheetData: String
        var extra: String = ""
        /// (relationship type suffix, part name under xl/, part XML)
        var parts: [(type: String, name: String, xml: String)] = []
        var kind: String = "worksheet"       // or "chartsheet"
        var state: String?
        var hasRelationship = true
    }

    var sheets: [Sheet] = []
    /// `<numFmt numFmtId formatCode>` entries.
    var numFmts: [(Int, String)] = []
    /// `cellXfs` numFmtIds in order (nil = no styles part).
    var xfs: [Int]? = [0]
    /// Raw inner XML of each `<si>`.
    var sharedStrings: [String]?
    var date1904 = false

    static let ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    static let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    /// One sheet named "Sheet1".
    init(sheetData: String, xfs: [Int]? = [0], numFmts: [(Int, String)] = [], sharedStrings: [String]? = nil,
         date1904: Bool = false) {
        self.sheets = [Sheet(name: "Sheet1", sheetData: sheetData)]
        self.xfs = xfs; self.numFmts = numFmts; self.sharedStrings = sharedStrings; self.date1904 = date1904
    }

    init(sheets: [Sheet], xfs: [Int]? = [0], sharedStrings: [String]? = nil) {
        self.sheets = sheets; self.xfs = xfs; self.sharedStrings = sharedStrings
    }

    func data() throws -> Data {
        let folder = TempFolder("aa-xlsx")
        let url = folder.file("book.xlsx")
        try write(to: url)
        return try Data(contentsOf: url)
    }

    func write(to url: URL) throws {
        let zip = try ZipWriter(url: url)
        func add(_ name: String, _ xml: String) throws {
            try zip.addData(Data(xml.utf8), named: name, modified: nil)
        }
        try add("[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"/>")
        try add("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(Self.rel)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>")
        var sheetElems = "", wbRels = ""
        for (k, s) in sheets.enumerated() {
            let rid = "rId\(k + 1)"
            let state = s.state.map { " state=\"\($0)\"" } ?? ""
            sheetElems += "<sheet name=\"\(s.name)\" sheetId=\"\(k + 1)\"\(state)\(s.hasRelationship ? " r:id=\"\(rid)\"" : "")/>"
            let folder = s.kind == "worksheet" ? "worksheets" : "chartsheets"
            wbRels += "<Relationship Id=\"\(rid)\" Type=\"\(Self.rel)/\(s.kind)\" Target=\"\(folder)/sheet\(k + 1).xml\"/>"
            if s.kind == "worksheet" {
                try add("xl/worksheets/sheet\(k + 1).xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"\(Self.ns)\" xmlns:r=\"\(Self.rel)\"><sheetData>\(s.sheetData)</sheetData>\(s.extra)</worksheet>")
            } else {
                try add("xl/chartsheets/sheet\(k + 1).xml", "<?xml version=\"1.0\"?><chartsheet xmlns=\"\(Self.ns)\"/>")
            }
            if !s.parts.isEmpty {
                var rels = ""
                for (j, part) in s.parts.enumerated() {
                    rels += "<Relationship Id=\"rIdP\(j + 1)\" Type=\"\(Self.rel)/\(part.type)\" Target=\"../\(part.name)\"/>"
                    try add("xl/\(part.name)", part.xml)
                }
                try add("xl/worksheets/_rels/sheet\(k + 1).xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(rels)</Relationships>")
            }
        }
        var next = sheets.count + 1
        if let xfs {
            wbRels += "<Relationship Id=\"rId\(next)\" Type=\"\(Self.rel)/styles\" Target=\"styles.xml\"/>"
            next += 1
            let fmts = numFmts.isEmpty ? "" : "<numFmts count=\"\(numFmts.count)\">" + numFmts.map { "<numFmt numFmtId=\"\($0.0)\" formatCode=\"\(Self.attr($0.1))\"/>" }.joined() + "</numFmts>"
            let cellXfs = "<cellXfs count=\"\(xfs.count)\">" + xfs.map { "<xf numFmtId=\"\($0)\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>" }.joined() + "</cellXfs>"
            try add("xl/styles.xml", "<?xml version=\"1.0\"?><styleSheet xmlns=\"\(Self.ns)\">\(fmts)<cellStyleXfs count=\"1\"><xf numFmtId=\"14\"/></cellStyleXfs>\(cellXfs)</styleSheet>")
        }
        if let sharedStrings {
            wbRels += "<Relationship Id=\"rId\(next)\" Type=\"\(Self.rel)/sharedStrings\" Target=\"sharedStrings.xml\"/>"
            try add("xl/sharedStrings.xml", "<?xml version=\"1.0\"?><sst xmlns=\"\(Self.ns)\" count=\"\(sharedStrings.count)\">" + sharedStrings.map { "<si>\($0)</si>" }.joined() + "</sst>")
        }
        let pr = date1904 ? "<workbookPr date1904=\"1\"/>" : "<workbookPr/>"
        try add("xl/workbook.xml", "<?xml version=\"1.0\"?><workbook xmlns=\"\(Self.ns)\" xmlns:r=\"\(Self.rel)\">\(pr)<sheets>\(sheetElems)</sheets></workbook>")
        try add("xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(wbRels)</Relationships>")
        try zip.finish()
    }

    func open() throws -> XlsxWorkbook { try XlsxWorkbook.open(data: data()) }

    /// The first worksheet, loaded.
    func firstSheet() throws -> (XlsxWorkbook, XlsxWorksheet) {
        let wb = try open()
        return (wb, try wb.load(wb.worksheets[0]))
    }

    static func attr(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}
