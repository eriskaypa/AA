// Spec: 10 §X.4.1 (extension gate, VESSEL-301; package open, VESSEL-302), §X.4.2 (parts and relationships),
//       VESSEL-303 (worksheet enumeration: document order, worksheets only, empty r:id → empty sheet, hidden kept,
//       names compared ordinal ignore-case), VESSEL-310 (date1904), §X.7.2 (shared strings once, sheets lazily);
//       ARCHITECTURE.md §6.5 (Sendable value types, parsing off-main).
import Foundation

/// A worksheet entry of the workbook (chartsheets are not listed), in workbook order.
public struct XlsxWorksheetRef: Sendable, Hashable {
    public var name: String
    /// Package part path, e.g. `xl/worksheets/sheet1.xml` (`""` for a `<sheet>` without a relationship id).
    public var partPath: String
    public var isHidden: Bool

    public init(name: String, partPath: String, isHidden: Bool = false) {
        self.name = name; self.partPath = partPath; self.isHidden = isHidden
    }
}

public struct XlsxWorkbook: Sendable {
    public let worksheets: [XlsxWorksheetRef]
    public let use1904: Bool
    let package: SvcXlsxPackage?
    let sharedStrings: [String]
    let styles: SvcXlsxStyleTable

    public init(worksheets: [XlsxWorksheetRef], use1904: Bool) {
        self.worksheets = worksheets; self.use1904 = use1904
        package = nil; sharedStrings = []; styles = SvcXlsxStyleTable()
    }

    init(worksheets: [XlsxWorksheetRef], use1904: Bool, package: SvcXlsxPackage, sharedStrings: [String],
         styles: SvcXlsxStyleTable) {
        self.worksheets = worksheets; self.use1904 = use1904; self.package = package
        self.sharedStrings = sharedStrings; self.styles = styles
    }

    /// X.4.1: the extension gate (VESSEL-301, the ClosedXML messages verbatim), then the package (VESSEL-302).
    /// Parsing runs on the caller's thread — call it off-main.
    public static func open(_ url: URL) throws(XlsxReadError) -> XlsxWorkbook {
        try gate(url.lastPathComponent)
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) } catch {
            throw .corrupt(detail: error.localizedDescription)
        }
        return try open(data: data)
    }

    /// The package itself (no extension gate) — for in-memory workbooks and tests.
    public static func open(data: Data) throws(XlsxReadError) -> XlsxWorkbook {
        let package = try SvcXlsxPackage(archive: data)
        guard let main = try package.relationships(of: "")
            .first(where: { !$0.external && SvcXlsxPackage.isType($0.type, "officeDocument") })?.target,
              let workbookXML = try package.part(main) else {
            throw .corrupt(detail: "The package has no workbook part.")
        }
        let rels = try package.relationships(of: main)
        func relTarget(_ suffix: String) -> String? {
            rels.first { !$0.external && SvcXlsxPackage.isType($0.type, suffix) }?.target
        }

        var use1904 = false
        var refs: [XlsxWorksheetRef] = []
        let scanner = try SvcXmlScanner(workbookXML)
        var path: [String] = []
        while let ev = try scanner.next() {
            switch ev {
            case .start(let name, let attrs):
                if name == "workbookPr", let v = attrs.first(where: { $0.local == "date1904" })?.value {
                    use1904 = v == "1" || v.lowercased() == "true"
                }
                if name == "sheet", path.last == "sheets" {
                    let sheetName = attrs.first(where: { $0.name == "name" })?.value ?? ""
                    let state = attrs.first(where: { $0.name == "state" })?.value ?? "visible"
                    let rid = attrs.first(where: { $0.name != $0.local && $0.local == "id" })?.value ?? ""
                    let hidden = state != "visible"
                    if rid.isEmpty {
                        refs.append(XlsxWorksheetRef(name: sheetName, partPath: "", isHidden: hidden))
                    } else {
                        guard let rel = rels.first(where: { $0.id == rid }) else {
                            throw .corrupt(detail: "The sheet \"\(sheetName)\" points at a missing part.")
                        }
                        if SvcXlsxPackage.isType(rel.type, "worksheet") && !rel.external {
                            refs.append(XlsxWorksheetRef(name: sheetName, partPath: rel.target, isHidden: hidden))
                        }
                    }
                }
                path.append(name)
            case .end:
                path.removeLast()
            case .text:
                break
            }
        }

        var styles = SvcXlsxStyleTable()
        if let p = relTarget("styles"), let data = try package.part(p) { styles = try SvcXlsxStyleTable(data: data) }
        var strings: [String] = []
        if let p = relTarget("sharedStrings"), let data = try package.part(p) { strings = try SvcXlsxText.sharedStrings(data) }
        return XlsxWorkbook(worksheets: refs, use1904: use1904, package: package, sharedStrings: strings, styles: styles)
    }

    /// VESSEL-301 (`Path.GetExtension` semantics: the text after the last `.` of the file name).
    static func gate(_ fileName: String) throws(XlsxReadError) {
        guard let dot = fileName.lastIndex(of: "."), fileName.index(after: dot) < fileName.endIndex else {
            throw .gate("Empty extension is not supported.")
        }
        let ext = NetText.toLowerInvariant(String(fileName[fileName.index(after: dot)...]))
        guard ["xlsx", "xlsm", "xltx", "xltm"].contains(ext) else {
            throw .gate("Extension '\(ext)' is not supported. Supported extensions are '.xlsx', '.xlsm', '.xltx' and '.xltm'.")
        }
    }

    /// Case-insensitive (ordinal) sheet lookup — the first match (COMPAS `report`, 09 §7.7).
    public func worksheet(named name: String) -> XlsxWorksheetRef? {
        worksheets.first { NetText.equalsIgnoreCase($0.name, name) }
    }

    /// Parses one worksheet: cells, comments, then table side effects (X.4.10). An empty `partPath` → an empty sheet.
    public func load(_ ref: XlsxWorksheetRef) throws(XlsxReadError) -> XlsxWorksheet {
        guard let package, !ref.partPath.isEmpty else { return XlsxWorksheet(name: ref.name) }
        guard let data = try package.part(ref.partPath) else {
            throw .corrupt(detail: "The worksheet part \(ref.partPath) is missing.")
        }
        var loaded = try SvcXlsxSheet.parse(data, sharedStrings: sharedStrings, styles: styles, use1904: use1904)
        let rels = try package.relationships(of: ref.partPath)
        for rel in rels where !rel.external && SvcXlsxPackage.isType(rel.type, "comments") {
            if let d = try package.part(rel.target) { try SvcXlsxSheet.applyComments(d, to: &loaded.cells) }
        }
        for rel in rels where !rel.external && SvcXlsxPackage.isType(rel.type, "table") {
            if let d = try package.part(rel.target) { try SvcXlsxSheet.applyTable(d, to: &loaded.cells) }
        }
        return XlsxWorksheet(name: ref.name, cells: loaded.cells, uncachedFormulas: loaded.uncachedFormulas)
    }
}
