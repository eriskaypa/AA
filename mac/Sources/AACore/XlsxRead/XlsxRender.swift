// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 10 §X.4.11 (renderers A / B / C, getString, B+), VESSEL-325…328. Compiling stub created by F1; F2 replaces
// this file in place. The stubs render every cell as "" (ARCH §11).
import Foundation

public enum XlsxRender {
    /// A — COMPAS (VESSEL-326).
    public static func compasCellString(_ c: XlsxCell, workbook: XlsxWorkbook) throws(XlsxReadError) -> String {
        // PLACEHOLDER(F2)
        ""
    }

    /// B — Shippalm (VESSEL-327 = A).
    public static func shippalmCell(_ c: XlsxCell, workbook: XlsxWorkbook) throws(XlsxReadError) -> String {
        // PLACEHOLDER(F2)
        ""
    }

    /// C — ports of call (VESSEL-328).
    public static func portsCell(_ c: XlsxCell, workbook: XlsxWorkbook) throws(XlsxReadError) -> String {
        // PLACEHOLDER(F2)
        ""
    }

    /// VESSEL-325 (reference culture).
    public static func getString(_ c: XlsxCell) -> String {
        // PLACEHOLDER(F2)
        ""
    }

    /// B+ = `ShippalmDates.excelDate(_:today:)` — `today` injected (time-only and year-less shapes).
    public static func shippalmExcelDate(_ text: String, today: CivilDate) -> String {
        // PLACEHOLDER(F2)
        ""
    }
}

/// 10 §X.4.11 / §3.4.4 (Shippalm due-date text normalisation; `XlsxRender.shippalmExcelDate` is the same function).
public enum ShippalmDates {
    public static func excelDate(_ raw: String, today: CivilDate) -> String {
        // PLACEHOLDER(F2)
        ""
    }
}
