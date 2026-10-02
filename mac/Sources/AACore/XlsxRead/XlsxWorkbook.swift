// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5, 10 §X.7.1
// Spec: 10 §X.4.1 (open and gate), §X.4.2 (parts), §X.4.8 (1904), VESSEL-301…304. Compiling stub created by F1;
// F2 replaces this file in place. The stub workbook has no worksheets (ARCH §11).
import Foundation

/// A worksheet entry of the workbook (chartsheets are not listed), in workbook order.
public struct XlsxWorksheetRef: Sendable, Hashable {
    public var name: String
    /// Package part path, e.g. `xl/worksheets/sheet1.xml`.
    public var partPath: String
    public var isHidden: Bool

    public init(name: String, partPath: String, isHidden: Bool = false) {
        self.name = name; self.partPath = partPath; self.isHidden = isHidden
    }
}

public struct XlsxWorkbook: Sendable {
    public let worksheets: [XlsxWorksheetRef]
    public let use1904: Bool

    public init(worksheets: [XlsxWorksheetRef], use1904: Bool) {
        self.worksheets = worksheets; self.use1904 = use1904
    }

    /// X.4.1: extension gate (VESSEL-301), package open (VESSEL-302). Parsing runs off-main.
    public static func open(_ url: URL) throws(XlsxReadError) -> XlsxWorkbook {
        // PLACEHOLDER(F2)
        XlsxWorkbook(worksheets: [], use1904: false)
    }

    /// Case-insensitive sheet lookup (COMPAS `report`, 09 §7.7).
    public func worksheet(named name: String) -> XlsxWorksheetRef? {
        // PLACEHOLDER(F2)
        nil
    }

    public func load(_ ref: XlsxWorksheetRef) throws(XlsxReadError) -> XlsxWorksheet {
        // PLACEHOLDER(F2)
        XlsxWorksheet(name: ref.name)
    }
}
