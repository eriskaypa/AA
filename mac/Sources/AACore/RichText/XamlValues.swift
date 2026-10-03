// Spec: 05 §XD.2.2 (value parsers and canonical forms), §XD.2.10 (`same()` table), §4.3.3 (attribute grammars),
//       §4.3.5 (WPF colour names), CONT-154 (`{x:Null}`, markup extensions), CONT-159 (lock sentinel).
// Pure, Sendable helpers shared by the DOM, the resolver, the reader, the writer and the list engine.
import Foundation

public enum XamlValues {
    /// `string.Trim()` without allocating when there is nothing to trim (the common case).
    @inline(__always) public static func trim(_ s: String) -> String {
        guard let f = s.utf16.first, let l = s.utf16.last else { return s }
        if !NetText.isWhiteSpace(f) && !NetText.isWhiteSpace(l) { return s }
        return NetText.trim(s)
    }

    // MARK: Numbers

    /// XD.2.2 Length: `[+-]digits[.digits][e±n][px|in|cm|pt]`, invariant, case-insensitive unit; `Auto`/`NaN` → NaN
    /// when `allowAuto`. Returns nil when the text does not parse.
    public static func parseLength(_ text: String, allowAuto: Bool) -> Double? {
        let t = trim(text)
        if let v = Double(t), v.isFinite, isPlainNumber(t) { return v }          // fast path: a plain number
        if allowAuto, NetText.equalsIgnoreCase(t, "Auto") || NetText.equalsIgnoreCase(t, "NaN") { return .nan }
        var s = Substring(t)
        var factor = 1.0
        let lower = t.lowercased()
        for (unit, f) in [("px", 1.0), ("in", 96.0), ("cm", 96.0 / 2.54), ("pt", 96.0 / 72.0)] where lower.hasSuffix(unit) {
            s = s.dropLast(2)
            factor = f
            break
        }
        let body = String(s).trimmingCharacters(in: .whitespaces)
        guard isPlainNumber(body), let v = Double(body), v.isFinite else { return nil }
        return v * factor
    }

    /// `[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?` over ASCII digits.
    static func isPlainNumber(_ s: String) -> Bool {
        let u = Array(s.utf8)
        var k = 0
        if k < u.count, u[k] == 0x2B || u[k] == 0x2D { k += 1 }
        var intDigits = 0, fracDigits = 0
        while k < u.count, u[k] >= 0x30, u[k] <= 0x39 { k += 1; intDigits += 1 }
        if k < u.count, u[k] == 0x2E {
            k += 1
            while k < u.count, u[k] >= 0x30, u[k] <= 0x39 { k += 1; fracDigits += 1 }
        }
        guard intDigits + fracDigits > 0, intDigits > 0 || fracDigits > 0 else { return false }
        if k < u.count, u[k] == 0x65 || u[k] == 0x45 {
            k += 1
            if k < u.count, u[k] == 0x2B || u[k] == 0x2D { k += 1 }
            var e = 0
            while k < u.count, u[k] >= 0x30, u[k] <= 0x39 { k += 1; e += 1 }
            guard e > 0 else { return false }
        }
        return k == u.count
    }

    /// XD.2.2 FontSize range `1/300 ≤ v ≤ 35791.3940666667`.
    public static func parseFontSize(_ text: String) -> Double? {
        guard let v = parseLength(text, allowAuto: false), v >= 1.0 / 300.0, v <= 35791.3940666667 else { return nil }
        return v
    }

    /// Integer as .NET `int.Parse` (invariant, surrounding whitespace, optional sign).
    public static func parseInt(_ text: String) -> Int? {
        let t = trim(text)
        guard !t.isEmpty, let v = Int(t.hasPrefix("+") ? String(t.dropFirst()) : t), v >= Int(Int32.min),
              v <= Int(Int32.max) else { return nil }
        return v
    }

    /// Shortest round-trip decimal, fixed notation, no trailing `.0`; NaN → `Auto` (XD.2.2 canonical length).
    public static func formatLength(_ v: Double) -> String {
        if v.isNaN { return "Auto" }
        if v == 0 { return "0" }
        var s = "\(v)"
        if s.hasSuffix(".0") { s.removeLast(2) }
        if let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            s = expandExponent(mantissa: String(s[..<e]), exponent: Int(s[s.index(after: e)...]) ?? 0)
        }
        return s
    }

    private static func expandExponent(mantissa: String, exponent: Int) -> String {
        var m = mantissa
        var negative = false
        if m.hasPrefix("-") { negative = true; m.removeFirst() }
        let parts = m.split(separator: ".", omittingEmptySubsequences: false)
        var digits = String(parts[0]) + (parts.count > 1 ? String(parts[1]) : "")
        var point = parts[0].count + exponent
        if point <= 0 {
            digits = String(repeating: "0", count: -point + 1) + digits
            point = 1
        } else if point > digits.count {
            digits += String(repeating: "0", count: point - digits.count)
        }
        var intPart = String(digits.prefix(point))
        var frac = String(digits.dropFirst(point))
        while frac.hasSuffix("0") { frac.removeLast() }
        while intPart.count > 1, intPart.hasPrefix("0") { intPart.removeFirst() }
        return (negative ? "-" : "") + intPart + (frac.isEmpty ? "" : "." + frac)
    }

    // MARK: Thickness

    /// `u` / `h,v` / `l,t,r,b`, comma or whitespace separated, each a length or `Auto`.
    public static func parseThickness(_ text: String) -> XamlThickness? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .map(String.init)
        var v: [Double] = []
        for p in parts {
            guard let d = parseLength(p, allowAuto: true) else { return nil }
            v.append(d)
        }
        switch v.count {
        case 1: return XamlThickness(left: v[0], top: v[0], right: v[0], bottom: v[0])
        case 2: return XamlThickness(left: v[0], top: v[1], right: v[0], bottom: v[1])
        case 4: return XamlThickness(left: v[0], top: v[1], right: v[2], bottom: v[3])
        default: return nil
        }
    }

    /// Canonical 4-value form `l,t,r,b` (§4.3.7 rule 7).
    public static func formatThickness(_ t: XamlThickness) -> String {
        [t.left, t.top, t.right, t.bottom].map(formatLength).joined(separator: ",")
    }

    // MARK: Font tokens

    public static func parseFontWeight(_ text: String) -> Int? {
        let t = trim(text)
        switch t {                                                       // canonical spellings first (no allocation)
        case "Normal": return 400
        case "Bold": return 700
        case "SemiBold": return 600
        default: break
        }
        switch t.lowercased() {
        case "thin": return 100
        case "extralight", "ultralight": return 200
        case "light": return 300
        case "normal", "regular": return 400
        case "medium": return 500
        case "demibold", "semibold": return 600
        case "bold": return 700
        case "extrabold", "ultrabold": return 800
        case "black", "heavy": return 900
        case "extrablack", "ultrablack": return 950
        default:
            guard let v = parseInt(t), v >= 1, v <= 999 else { return nil }
            return v
        }
    }

    public static func fontWeightToken(_ w: Int) -> String {
        switch w {
        case 100: return "Thin"
        case 200: return "ExtraLight"
        case 300: return "Light"
        case 400: return "Normal"
        case 500: return "Medium"
        case 600: return "SemiBold"
        case 700: return "Bold"
        case 800: return "ExtraBold"
        case 900: return "Black"
        case 950: return "ExtraBlack"
        default: return String(w)
        }
    }

    public static func parseFontStyle(_ text: String) -> XamlFontStyle? {
        let t = trim(text)
        if let exact = XamlFontStyle(rawValue: t) { return exact }
        switch t.lowercased() {
        case "normal": return .normal
        case "italic": return .italic
        case "oblique": return .oblique
        default: return nil
        }
    }

    static let stretchNames: [(String, Int)] = [
        ("UltraCondensed", 1), ("ExtraCondensed", 2), ("Condensed", 3), ("SemiCondensed", 4), ("Normal", 5),
        ("Medium", 5), ("SemiExpanded", 6), ("Expanded", 7), ("ExtraExpanded", 8), ("UltraExpanded", 9),
    ]

    public static func parseFontStretch(_ text: String) -> Int? {
        let t = NetText.trim(text)
        for (n, v) in stretchNames where NetText.equalsIgnoreCase(n, t) { return v }
        guard let v = parseInt(t), v >= 1, v <= 9 else { return nil }
        return v
    }

    public static func fontStretchToken(_ v: Int) -> String {
        stretchNames.first(where: { $0.1 == v && $0.0 != "Medium" })?.0 ?? String(v)
    }

    // MARK: Enums

    @inline(__always)
    static func parseEnum<E: RawRepresentable & CaseIterable>(_ text: String, _: E.Type) -> E? where E.RawValue == String {
        let t = trim(text)
        if let exact = E(rawValue: t) { return exact }
        return E.allCases.first { NetText.equalsIgnoreCase($0.rawValue, t) }
    }

    public static func parseBool(_ text: String) -> Bool? {
        let t = trim(text)
        if t == "True" { return true }
        if t == "False" { return false }
        if NetText.equalsIgnoreCase(t, "True") { return true }
        if NetText.equalsIgnoreCase(t, "False") { return false }
        return nil
    }

    public static func parseTextAlignment(_ t: String) -> XamlTextAlignment? { parseEnum(t, XamlTextAlignment.self) }
    public static func parseFlowDirection(_ t: String) -> XamlFlowDirection? { parseEnum(t, XamlFlowDirection.self) }
    public static func parseLineStacking(_ t: String) -> XamlLineStacking? { parseEnum(t, XamlLineStacking.self) }
    public static func parseBaselineAlignment(_ t: String) -> XamlBaselineAlignment? {
        parseEnum(t, XamlBaselineAlignment.self)
    }

    /// `List.MarkerStyle` names (§4.3.3), canonical spelling.
    public static let markerStyles = ["None", "Disc", "Circle", "Square", "Box", "LowerRoman", "UpperRoman",
                                      "LowerLatin", "UpperLatin", "Decimal"]

    public static func parseMarkerStyle(_ text: String) -> String? {
        let t = NetText.trim(text)
        return markerStyles.first { NetText.equalsIgnoreCase($0, t) }
    }

    /// `IsNumbered` of 05 §3.2.
    public static func isNumberedMarker(_ style: String) -> Bool {
        ["Decimal", "LowerLatin", "UpperLatin", "LowerRoman", "UpperRoman"].contains(style)
    }

    // MARK: Decorations

    /// `None`, or a comma list of `Underline`, `Strikethrough`, `OverLine`, `Baseline` (case-insensitive).
    public static func parseDecorations(_ text: String) -> XamlDecorations? {
        let t = NetText.trim(text)
        if NetText.equalsIgnoreCase(t, "None") { return [] }
        var d: XamlDecorations = []
        let parts = t.split(separator: ",", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        for p in parts {
            switch NetText.trim(String(p)).lowercased() {
            case "underline": d.insert(.underline)
            case "strikethrough": d.insert(.strikethrough)
            case "overline": d.insert(.overLine)
            case "baseline": d.insert(.baseline)
            default: return nil
            }
        }
        return d
    }

    /// Fixed order Underline, Strikethrough, OverLine, Baseline joined with `,`; empty → `None`.
    public static func formatDecorations(_ d: XamlDecorations) -> String {
        var parts: [String] = []
        if d.contains(.underline) { parts.append("Underline") }
        if d.contains(.strikethrough) { parts.append("Strikethrough") }
        if d.contains(.overLine) { parts.append("OverLine") }
        if d.contains(.baseline) { parts.append("Baseline") }
        return parts.isEmpty ? "None" : parts.joined(separator: ",")
    }

    // MARK: Brushes

    /// Brush attribute grammar (XD.2.2). `{x:Null}` → `.null`; any other `{…}` → nil with `isMarkupExtension`.
    public static func parseBrush(_ text: String) -> XamlBrush? {
        let t = trim(text)
        if t.utf8.count == 9, t.utf8.first == 0x23,
           t.utf8.dropFirst().allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x46) || ($0 >= 0x61 && $0 <= 0x66) }),
           let v = UInt32(t.dropFirst(), radix: 16) {                    // `#AARRGGBB` fast path
            return .solid(argb: v, opacity: 1, isScRgb: false)
        }
        if t.hasPrefix("{") {
            let inner = t.replacingOccurrences(of: " ", with: "")
            return inner == "{x:Null}" ? .null : nil
        }
        guard let c = WpfColor.parse(t) else { return nil }
        let isSc = t.lowercased().hasPrefix("sc#")
        return .solid(argb: argbValue(c), opacity: 1, isScRgb: isSc)
    }

    public static func argbValue(_ c: ARGB) -> UInt32 {
        UInt32(c.a) << 24 | UInt32(c.r) << 16 | UInt32(c.g) << 8 | UInt32(c.b)
    }

    public static func argb(_ v: UInt32) -> ARGB {
        ARGB(a: UInt8(v >> 24 & 0xFF), r: UInt8(v >> 16 & 0xFF), g: UInt8(v >> 8 & 0xFF), b: UInt8(v & 0xFF))
    }

    /// `#AARRGGBB` upper case.
    public static func formatColor(_ v: UInt32) -> String { WpfColor.hexAARRGGBB(argb(v)) }

    public static let sentinelARGB: UInt32 = 0xFFFF_E699

    /// CONT-159 lock test: `.solid` with ARGB exactly `0xFFFFE699`, not scRGB; opacity ignored.
    public static func isSentinel(_ b: XamlBrush?) -> Bool {
        if case .solid(let argb, _, let sc)? = b, argb == sentinelARGB, !sc { return true }
        return false
    }

    // MARK: same() (XD.2.10)

    public static func sameFontFamily(_ a: String, _ b: String) -> Bool { XamlFontFamily(raw: a).canon == XamlFontFamily(raw: b).canon }
    public static func sameLength(_ a: Double, _ b: Double) -> Bool {
        if a.isNaN || b.isNaN { return a.isNaN && b.isNaN }
        return abs(a - b) <= 1e-6
    }

    public static func sameBrush(_ a: XamlBrush, _ b: XamlBrush) -> Bool {
        switch (a, b) {
        case let (.solid(x, ox, _), .solid(y, oy, _)): return x == y && abs(ox - oy) <= 1e-9
        case (.linkDefault, .linkDefault), (.null, .null): return true
        case let (.nonSolid(x), .nonSolid(y)): return x == y
        default: return false
        }
    }

    /// XML 1.0 `Char` (§4.3.7 rule 4: characters illegal in XML 1.0 are dropped).
    public static func isXMLChar(_ sc: Unicode.Scalar) -> Bool {
        let v = sc.value
        return v == 0x9 || v == 0xA || v == 0xD || (v >= 0x20 && v <= 0xD7FF) || (v >= 0xE000 && v <= 0xFFFD)
            || (v >= 0x10000 && v <= 0x10FFFF)
    }

    public static func sameToken(_ a: String, _ b: String) -> Bool {
        NetText.trim(a).lowercased() == NetText.trim(b).lowercased()
    }
}
