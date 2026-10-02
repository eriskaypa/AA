// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5, 10 §X.7.1
// Spec: 10 §X.4.7 (serial → date-time), §X.4.8 (1904), §X.4.9 (durations), X.8.3–X.8.4; OC-56 (functions over the
// one `NetDateTime`). Compiling stub created by F1; F2 replaces this file in place. The conversion stubs throw
// rather than invent a date (ARCH §11).
import Foundation

public enum ExcelSerial {
    /// `ToSerialDateTime` + `DateTime.FromOADate` (serial 60 → the VESSEL-309 leap-year message).
    public static func fromSerial(_ v: Double) throws(XlsxReadError) -> NetDateTime {
        // PLACEHOLDER(F2)
        throw .message("Excel serial dates are not available yet.")
    }

    /// `DateTime.FromOADate` in pure civil arithmetic (never through `Date` + a time zone).
    public static func fromOADate(_ d: Double) throws(XlsxReadError) -> NetDateTime {
        // PLACEHOLDER(F2)
        throw .message("Excel serial dates are not available yet.")
    }

    /// `ToSerialDateTime`: OA date, minus 1 at or below 60.
    public static func toSerial(_ dt: NetDateTime) -> Double {
        // PLACEHOLDER(F2)
        0
    }

    /// `XLHelper.GetTimeSpan` in whole milliseconds (banker's rounding of ticks / 10 000).
    public static func toTimeSpanMs(_ v: Double) throws(XlsxReadError) -> Int64 {
        // PLACEHOLDER(F2)
        throw .message("Excel durations are not available yet.")
    }

    /// `ToExcelString` of a duration ("h:mm:ss[.f]").
    public static func excelString(ms: Int64) -> String {
        // PLACEHOLDER(F2)
        ""
    }
}
