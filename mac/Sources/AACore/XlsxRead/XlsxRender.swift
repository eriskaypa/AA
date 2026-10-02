// Spec: 10 §X.4.11 (one module, three thin adapters), VESSEL-325 (`GetString` in the reference culture), VESSEL-326
//       (renderer A, COMPAS `CellString`), VESSEL-327 (renderer B = A, Shippalm `Cell`, + `ExcelDate`), VESSEL-328
//       (renderer C, ports `Cell`), VESSEL-329/330 (number texts via `NetNumberText`), §3.4.4 (`ExcelDate`),
//       VESSEL-318 (Mac-only hint), X.8.1, X.8.4–X.8.6.
import Foundation

public enum XlsxRender {
    /// A — COMPAS (VESSEL-326): empty → ""; number → `Int64` text when integral (saturating), else .NET shortest;
    /// dateTime → `yyyy-MM-dd` (may throw VESSEL-309); boolean → TRUE/FALSE; everything else → `GetString().Trim()`
    /// (so a duration renders `H:mm:ss[.fff]`).
    public static func compasCellString(_ c: XlsxCell, workbook: XlsxWorkbook) throws(XlsxReadError) -> String {
        if c.isEmpty { return "" }
        switch c.value {
        case .number(let d): return integralOrShortest(d)
        case .dateTime(let s): return try ExcelSerial.fromSerial(s).format(.isoDate)
        case .boolean(let b): return b ? "TRUE" : "FALSE"
        default: return NetText.trim(getString(c))
        }
    }

    /// B — Shippalm (VESSEL-327): byte-identical in behaviour to renderer A.
    public static func shippalmCell(_ c: XlsxCell, workbook: XlsxWorkbook) throws(XlsxReadError) -> String {
        try compasCellString(c, workbook: workbook)
    }

    /// C — ports of call (VESSEL-328): empty → ""; dateTime → `yyyy-MM-dd`, or `yyyy-MM-dd HH:mm` when the
    /// millisecond-rounded value is not midnight (seconds dropped); duration → `hh:mm` (hours component, days
    /// dropped); number → .NET `"0.####"`; everything else → `GetString().Trim()`.
    public static func portsCell(_ c: XlsxCell, workbook: XlsxWorkbook) throws(XlsxReadError) -> String {
        if c.isEmpty { return "" }
        switch c.value {
        case .dateTime(let s):
            let t = try ExcelSerial.fromSerial(s)
            return ExcelSerial.msOfDay(t) == 0 ? t.format(.isoDate) : t.format(.isoMinute)
        case .timeSpan(let s):
            return ExcelSerial.hoursMinutes(ms: try ExcelSerial.toTimeSpanMs(s))
        case .number(let d):
            return NetNumberText.net0_4(d)
        default:
            return NetText.trim(getString(c))
        }
    }

    /// VESSEL-325 `GetString()` in the reference culture: blank → ""; boolean → TRUE/FALSE; number → .NET shortest
    /// round-trip; text verbatim; error → its code; dateTime → `M/d/yyyy h:mm:ss tt` (en-US; unreachable from the
    /// three renderers); duration → `ToExcelString`. A value that cannot be converted renders "".
    public static func getString(_ c: XlsxCell) -> String {
        switch c.value {
        case .blank: return ""
        case .boolean(let b): return b ? "TRUE" : "FALSE"
        case .number(let d): return NetNumberText.shortest(d) ?? ""
        case .text(let s): return s
        case .error(let e): return e.rawValue
        case .dateTime(let s):
            guard let t = try? ExcelSerial.fromSerial(s) else { return "" }
            let h12 = t.hour % 12 == 0 ? 12 : t.hour % 12
            return "\(t.month)/\(t.day)/\(CivilDate.pad(t.year, 4)) \(h12):\(CivilDate.pad(t.minute, 2)):\(CivilDate.pad(t.second, 2)) \(t.hour < 12 ? "AM" : "PM")"
        case .timeSpan(let s):
            guard let ms = try? ExcelSerial.toTimeSpanMs(s) else { return "" }
            return ExcelSerial.excelString(ms: ms)
        }
    }

    /// B+ = `ShippalmDates.excelDate(_:today:)` — `today` injected (time-only and year-less shapes).
    public static func shippalmExcelDate(_ text: String, today: CivilDate) -> String {
        ShippalmDates.excelDate(text, today: today)
    }

    /// VESSEL-318 Mac-only status suffix for formula cells whose result was not saved in the file.
    public static func uncachedFormulaHint(count: Int) -> String {
        "\(count) formula cell(s) had no saved result; open and re-save the file in Excel to include them."
    }

    /// VESSEL-329: integral → `(long)d` (saturating; `-0` → `0`), else the .NET shortest round-trip text.
    static func integralOrShortest(_ d: Double) -> String {
        if d == d.rounded(.down) { return String(NetNumberText.int64Saturating(d)) }
        return NetNumberText.shortest(d) ?? ""
    }
}

/// 10 §X.4.11 / §3.4.4 (Shippalm due-date text normalisation; `XlsxRender.shippalmExcelDate` is the same function).
public enum ShippalmDates {
    /// blank → ""; trimmed; the shared `NetDateParser` (`today` resolves time-only and year-less text) → `yyyy-MM-dd`;
    /// else a number (`NumberStyles.Any`, invariant) strictly between 20 000 and 200 000 → `FromOADate` date (no
    /// leap shim, no 1904 shift); else the trimmed text unchanged.
    public static func excelDate(_ raw: String, today: CivilDate) -> String {
        guard !NetText.isBlank(raw) else { return "" }
        let s = NetText.trim(raw)
        if let d = NetDateParser.parse(s, today: today) { return d.format(.isoDate) }
        if let v = numberAny(s), v > 20_000, v < 200_000, let d = try? ExcelSerial.fromOADate(v) {
            return d.format(.isoDate)
        }
        return s
    }

    /// .NET `double.TryParse(s, NumberStyles.Any, InvariantCulture)`: surrounding white space, a leading or trailing
    /// sign, parentheses for negatives, the invariant currency symbol `¤`, `,` group separators in the integer part,
    /// a `.` fraction and an exponent.
    static func numberAny(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}"))
        var negative = false
        if s.hasPrefix("("), s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        s = s.replacingOccurrences(of: "\u{00A4}", with: "")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}"))
        if s.hasSuffix("-") { negative.toggle(); s.removeLast() } else if s.hasSuffix("+") { s.removeLast() }
        if s.hasPrefix("-") { negative.toggle(); s.removeFirst() } else if s.hasPrefix("+") { s.removeFirst() }
        guard let first = s.first, first.isASCII, first.isNumber || first == "." else { return nil }
        // Group separators only in the integer part.
        let mantissaEnd = s.firstIndex(where: { $0 == "." || $0 == "e" || $0 == "E" }) ?? s.endIndex
        let intPart = s[..<mantissaEnd].replacingOccurrences(of: ",", with: "")
        let rest = String(s[mantissaEnd...])
        guard !rest.contains(","), let canonical = SvcXlsxSheet.canonicalNumber(intPart + rest),
              let v = Double(canonical), v.isFinite else { return nil }
        return negative ? -v : v
    }
}
