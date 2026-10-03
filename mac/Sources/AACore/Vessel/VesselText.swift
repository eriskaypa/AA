// Spec: 10 §3 (OrdinalIgnoreCase / ToLowerInvariant semantics), §3.6 (safe export file names), §3.3.5–3.3.6
//       (NormDate / NormTime), §7.1–7.2, §7.14 (safe-name vector).
import Foundation

/// Small string helpers shared by W-VESSEL's readers and services (Windows string semantics).
public enum VesselText {
    /// `string.Contains(needle)` — ordinal over UTF-16 code units (used on already lower-cased header texts).
    public static func ordinalContains(_ haystack: String, _ needle: String) -> Bool {
        let h = Array(haystack.utf16), n = Array(needle.utf16)
        if n.isEmpty { return true }
        guard n.count <= h.count else { return false }
        outer: for start in 0...(h.count - n.count) {
            for k in 0..<n.count where h[start + k] != n[k] { continue outer }
            return true
        }
        return false
    }

    /// `string.StartsWith(prefix)` — ordinal.
    public static func ordinalHasPrefix(_ s: String, _ prefix: String) -> Bool {
        let h = Array(s.utf16), p = Array(prefix.utf16)
        guard p.count <= h.count else { return false }
        return Array(h[0..<p.count]) == p
    }

    /// §3.6: `(name ?? "vessel")` with every Windows `Path.GetInvalidFileNameChars()` character replaced by `_`
    /// (no trimming — the Windows `string.Concat` keeps everything else).
    public static func safeFileName(_ name: String?) -> String {
        let raw = name ?? "vessel"
        var out = String.UnicodeScalarView()
        for sc in raw.unicodeScalars {
            if sc.value < 0x20 || "\"<>|:*?\\/".unicodeScalars.contains(sc) { out.append("_") } else { out.append(sc) }
        }
        return String(out)
    }

    /// `WorkOrders-{safe}.xlsx` (VESSEL-103).
    public static func workOrdersExportName(_ vesselName: String?) -> String { "WorkOrders-\(safeFileName(vesselName)).xlsx" }

    /// `Ports-{safe}.xlsx` (VESSEL-205).
    public static func portsExportName(_ vesselName: String?) -> String { "Ports-\(safeFileName(vesselName)).xlsx" }

    // MARK: NormDate / NormTime (§3.3.5–3.3.6)

    /// §3.3.5: canonical `yyyy-MM-dd`, or the trimmed input unchanged.
    /// 1. prefix `^(\d{4})-(\d{1,2})-(\d{1,2})` with a valid date; 2. prefix `^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})`
    /// DAY-first, a year < 100 becomes 20xx; 3. the shared invariant parser (`DateTime.TryParse`, month-first, English
    /// month names, time-only input = `today`); 4. the text verbatim.
    public static func normDate(_ input: String, today: CivilDate? = nil, zone: TimeZone = .current) -> String {
        let s = NetText.trim(input)
        if s.isEmpty { return "" }
        let u = Array(s.utf8)
        // Step 1 — ISO-like prefix.
        if u.count >= 6, let y = digits(u, 0, 4), u[4] == 0x2D {
            var i = 5
            if let (mo, ni) = digits1to2(u, i), ni < u.count, u[ni] == 0x2D {
                i = ni + 1
                if let (d, _) = digits1to2(u, i), let date = CivilDate(year: y, month: mo, day: d) {
                    return date.iso
                }
            }
        }
        // Step 2 — day-first prefix.
        if let (d, i1) = digits1to2(u, 0), i1 < u.count, isSep(u[i1]),
           let (mo, i2) = digits1to2(u, i1 + 1), i2 < u.count, isSep(u[i2]) {
            var j = i2 + 1, yDigits = 0, y = 0
            while j < u.count, yDigits < 4, isDigit(u[j]) { y = y * 10 + Int(u[j] - 0x30); j += 1; yDigits += 1 }
            if yDigits >= 2 {
                if y < 100 { y += 2000 }
                if let date = CivilDate(year: y, month: mo, day: d) { return date.iso }
            }
        }
        // Step 3 — the invariant general parser.
        if let dt = NetDateParser.parse(s, zone: zone, today: today) { return dt.format(.isoDate, zone: zone) }
        return s
    }

    /// §3.3.6: the first (unanchored) `(\d{1,2}):(\d{2})` → two-digit hours + ":" + minutes; no match → "".
    public static func normTime(_ input: String) -> String {
        let u = Array(NetText.trim(input).utf8)
        var start = 0
        while start < u.count {
            // Greedy \d{1,2} (two digits first, then one), then ":" and exactly two digits.
            for len in [2, 1] {
                let colon = start + len
                guard colon + 2 < u.count else { continue }
                guard (start..<colon).allSatisfy({ isDigit(u[$0]) }), u[colon] == 0x3A,
                      isDigit(u[colon + 1]), isDigit(u[colon + 2]) else { continue }
                var h = 0
                for k in start..<colon { h = h * 10 + Int(u[k] - 0x30) }
                let hh = h < 10 ? "0\(h)" : String(h)
                return hh + ":" + String(decoding: u[(colon + 1)...(colon + 2)], as: UTF8.self)
            }
            start += 1
        }
        return ""
    }

    // MARK: Byte helpers

    static func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }
    static func isSep(_ c: UInt8) -> Bool { c == 0x2F || c == 0x2E || c == 0x2D }

    static func digits(_ u: [UInt8], _ start: Int, _ count: Int) -> Int? {
        guard start + count <= u.count else { return nil }
        var v = 0
        for i in start..<(start + count) {
            guard isDigit(u[i]) else { return nil }
            v = v * 10 + Int(u[i] - 0x30)
        }
        return v
    }

    /// Greedy `\d{1,2}` at `start`: (value, index after the digits).
    static func digits1to2(_ u: [UInt8], _ start: Int) -> (Int, Int)? {
        guard start < u.count, isDigit(u[start]) else { return nil }
        if start + 1 < u.count, isDigit(u[start + 1]) {
            return (Int(u[start] - 0x30) * 10 + Int(u[start + 1] - 0x30), start + 2)
        }
        return (Int(u[start] - 0x30), start + 1)
    }
}
