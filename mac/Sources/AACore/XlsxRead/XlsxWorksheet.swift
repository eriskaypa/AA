// Spec: 10 §X.4.10 (`IsEmpty`, `RangeUsed`, `cell(r, c)` never nil), VESSEL-319…321, VESSEL-318 (formula cells
//       without a cached value: rendered "" and counted for the Mac-only hint), X.8.7.
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
    /// (row, column) → cell, keyed by `SvcCellKey`.
    let cells: [Int64: XlsxCell]
    let used: XlsxRange?
    /// Cells that carry a formula but no cached value (VESSEL-318).
    let uncachedFormulaKeys: Set<Int64>

    public init(name: String) {
        self.init(name: name, cells: [:], uncachedFormulas: [])
    }

    init(name: String, cells: [Int64: XlsxCell], uncachedFormulas: Set<Int64>) {
        self.name = name
        self.cells = cells
        self.uncachedFormulaKeys = uncachedFormulas
        var bounds: XlsxRange?
        for (key, cell) in cells where !cell.isEmpty {
            let (r, c) = SvcCellKey.split(key)
            if var b = bounds {
                b.firstRow = min(b.firstRow, r); b.lastRow = max(b.lastRow, r)
                b.firstColumn = min(b.firstColumn, c); b.lastColumn = max(b.lastColumn, c)
                bounds = b
            } else {
                bounds = XlsxRange(firstRow: r, firstColumn: c, lastRow: r, lastColumn: c)
            }
        }
        used = bounds
    }

    /// 1-based row and column; a missing cell is blank.
    public func cell(_ r: Int, _ c: Int) -> XlsxCell {
        cells[SvcCellKey.make(r, c)] ?? XlsxCell()
    }

    /// Bounds over every non-empty cell (`IsEmpty` false: a value, a formula or a comment), or nil.
    public func rangeUsed() -> XlsxRange? { used }

    /// VESSEL-318: true when the cell has a formula whose result was not saved in the file (rendered `""`).
    public func hasUncachedFormula(_ r: Int, _ c: Int) -> Bool {
        uncachedFormulaKeys.contains(SvcCellKey.make(r, c))
    }

    /// VESSEL-318: how many formula cells inside `range` (default: the used range) had no saved result.
    public func uncachedFormulaCount(in range: XlsxRange? = nil) -> Int {
        guard let r = range ?? used else { return 0 }
        return uncachedFormulaKeys.reduce(0) { n, key in
            let (row, col) = SvcCellKey.split(key)
            return n + ((r.firstRow...r.lastRow).contains(row) && (r.firstColumn...r.lastColumn).contains(col) ? 1 : 0)
        }
    }
}

/// Packs a 1-based (row, column) pair into one dictionary key.
enum SvcCellKey {
    static func make(_ r: Int, _ c: Int) -> Int64 { Int64(r) << 20 | Int64(c & 0xFFFFF) }
    static func split(_ k: Int64) -> (row: Int, column: Int) { (Int(k >> 20), Int(k & 0xFFFFF)) }

    /// `"B12"` → (12, 2); nil when malformed (letters A–Z / a–z, then a positive row number).
    static func parse(_ ref: String) -> (row: Int, column: Int)? {
        var col = 0, row = 0, inDigits = false
        for c in ref.utf8 {
            if !inDigits, let v = letter(c) {
                col = col * 26 + v
                guard col <= 16_384 else { return nil }
            } else if c >= 0x30 && c <= 0x39 {
                guard col > 0 else { return nil }
                inDigits = true
                row = row * 10 + Int(c - 0x30)
                guard row <= 1_048_576 else { return nil }
            } else {
                return nil
            }
        }
        guard inDigits, row > 0 else { return nil }
        return (row, col)
    }

    private static func letter(_ c: UInt8) -> Int? {
        if c >= 0x41 && c <= 0x5A { return Int(c - 0x40) }
        if c >= 0x61 && c <= 0x7A { return Int(c - 0x60) }
        return nil
    }
}
