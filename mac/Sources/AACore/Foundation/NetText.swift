// Spec: 01 §3 ("Ordinal", "OrdinalIgnoreCase"), §3.21 (ToLowerInvariant), 06 BUILD-A23 (IsNullOrWhiteSpace),
//       12 §6.12 (culture compare); ARCHITECTURE.md §6.1 — .NET string semantics over UTF-16 code units.
import Foundation

public enum NetText {
    /// `char.IsWhiteSpace` set: U+0009–U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029,
    /// U+202F, U+205F, U+3000.
    public static func isWhiteSpace(_ u: UInt16) -> Bool {
        switch u {
        case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: return true
        default: return false
        }
    }

    /// `string.IsNullOrWhiteSpace`.
    public static func isBlank(_ s: String?) -> Bool {
        guard let s else { return true }
        for u in s.utf16 where !isWhiteSpace(u) { return false }
        return true
    }

    /// `string.Trim()` (the `char.IsWhiteSpace` set, both ends).
    public static func trim(_ s: String) -> String {
        let u = Array(s.utf16)
        var a = 0, b = u.count
        while a < b, isWhiteSpace(u[a]) { a += 1 }
        while b > a, isWhiteSpace(u[b - 1]) { b -= 1 }
        if a == 0 && b == u.count { return s }
        return String(decoding: u[a..<b], as: UTF16.self)
    }

    /// `string.Trim(chars)` for BMP characters.
    public static func trim(_ s: String, characters: Set<UInt16>) -> String {
        let u = Array(s.utf16)
        var a = 0, b = u.count
        while a < b, characters.contains(u[a]) { a += 1 }
        while b > a, characters.contains(u[b - 1]) { b -= 1 }
        return String(decoding: u[a..<b], as: UTF16.self)
    }

    /// Invariant simple upper-case mapping of one UTF-16 unit (OrdinalIgnoreCase folding).
    static func simpleUpper(_ u: UInt16) -> UInt16 {
        if u < 0x80 { return (u >= 0x61 && u <= 0x7A) ? u - 0x20 : u }
        guard !(0xD800...0xDFFF).contains(u), let sc = Unicode.Scalar(u) else { return u }
        let m = sc.properties.uppercaseMapping.unicodeScalars
        guard m.count == 1, let first = m.first, first.value <= 0xFFFF else { return u }
        return UInt16(first.value)
    }

    /// Invariant simple lower-case mapping of one scalar (`ToLowerInvariant`).
    static func simpleLower(_ sc: Unicode.Scalar) -> Unicode.Scalar {
        if sc.value < 0x80 { return (sc.value >= 0x41 && sc.value <= 0x5A) ? Unicode.Scalar(sc.value + 0x20)! : sc }
        if sc.value == 0x130 { return "i" }                       // İ → i (simple mapping)
        let m = sc.properties.lowercaseMapping.unicodeScalars
        guard m.count == 1, let first = m.first else { return sc }
        return first
    }

    static func folded(_ s: String) -> [UInt16] { s.utf16.map(simpleUpper) }

    /// `StringComparison.OrdinalIgnoreCase` equality.
    public static func equalsIgnoreCase(_ a: String, _ b: String) -> Bool {
        let ua = a.utf16, ub = b.utf16
        guard ua.count == ub.count else { return false }
        for (x, y) in zip(ua, ub) where x != y && simpleUpper(x) != simpleUpper(y) { return false }
        return true
    }

    /// `s.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0` (an empty query is contained).
    public static func containsIgnoreCase(_ s: String, _ q: String) -> Bool {
        indexOfIgnoreCase(s, q) != nil
    }

    /// UTF-16 offset of the first OrdinalIgnoreCase match, or nil.
    public static func indexOfIgnoreCase(_ s: String, _ q: String) -> Int? {
        let h = folded(s), n = folded(q)
        if n.isEmpty { return 0 }
        guard n.count <= h.count else { return nil }
        outer: for start in 0...(h.count - n.count) {
            for k in 0..<n.count where h[start + k] != n[k] { continue outer }
            return start
        }
        return nil
    }

    /// `string.Compare(a, b, StringComparison.OrdinalIgnoreCase)`.
    public static func compareIgnoreCase(_ a: String, _ b: String) -> ComparisonResult {
        let fa = folded(a), fb = folded(b)
        for (x, y) in zip(fa, fb) where x != y { return x < y ? .orderedAscending : .orderedDescending }
        if fa.count == fb.count { return .orderedSame }
        return fa.count < fb.count ? .orderedAscending : .orderedDescending
    }

    /// .NET default culture-sensitive comparer, en-US (12 §6.12).
    public static func compareCulture(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [], range: nil, locale: Locale(identifier: "en_US"))
    }

    /// `ToLowerInvariant` (simple per-character mapping, culture-invariant).
    public static func toLowerInvariant(_ s: String) -> String {
        var ascii = true
        for u in s.utf8 where u >= 0x80 || (u >= 0x41 && u <= 0x5A) { ascii = false; break }
        if ascii { return s }
        var out = String.UnicodeScalarView()
        for sc in s.unicodeScalars { out.append(simpleLower(sc)) }
        return String(out)
    }

    /// `ToUpperInvariant` (simple per-character mapping).
    public static func toUpperInvariant(_ s: String) -> String {
        String(decoding: folded(s), as: UTF16.self)
    }
}
