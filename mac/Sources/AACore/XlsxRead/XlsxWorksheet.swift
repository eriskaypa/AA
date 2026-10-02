// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5, 10 §X.7.1
// Spec: 10 §X.4.10 (cell / RangeUsed), VESSEL-320. Compiling stub created by F1; F2 replaces this file in place.
// The stub sheet has no cells (ARCH §11).
import Foundation

/// 1-based, inclusive bounds of the used range.
public struct XlsxRange: Sendable, Hashable {
    public var firstRow: Int
    public var firstColumn: Int
    public var lastRow: Int
    public var lastColumn: Int

    public init(firstRow: Int, firstColumn: Int, lastRow: Int, lastColumn: Int) {
        self.firstRow = firstRow; self.firstColumn = firstColumn; self.lastRow = lastRow; self.lastColumn = lastColumn
    }
}

public struct XlsxWorksheet: Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    /// 1-based row and column; a missing cell is blank.
    public func cell(_ r: Int, _ c: Int) -> XlsxCell {
        // PLACEHOLDER(F2)
        XlsxCell()
    }

    /// Bounds over every non-empty cell, or nil.
    public func rangeUsed() -> XlsxRange? {
        // PLACEHOLDER(F2)
        nil
    }
}
