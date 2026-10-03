// Spec: 12 §3.3–§3.4, §3.6, §3.8 — .NET `string`/`char` semantics over UTF-16 code units for the SIRE engine
//       (`char.IsDigit` = Unicode Nd, `char.IsLetter` = L*, `char.IsUpper` = Lu, `char.ToUpper/ToLower` = simple
//       single-unit mapping, ordinal `StartsWith`/`Split`).
import Foundation

/// UTF-16 helpers mirroring the .NET string APIs the C# SIRE code uses.
public enum SireText {
    @inline(__always) static func units(_ s: String) -> [UInt16] { Array(s.utf16) }
    @inline(__always) static func string<C: Collection>(_ u: C) -> String where C.Element == UInt16 {
        String(decoding: u, as: UTF16.self)
    }

    static func category(_ u: UInt16) -> Unicode.GeneralCategory? {
        guard !(0xD800...0xDFFF).contains(u), let sc = Unicode.Scalar(u) else { return nil }
        return sc.properties.generalCategory
    }

    /// `char.IsDigit` (DecimalDigitNumber).
    static func isDigit(_ u: UInt16) -> Bool {
        if u < 0x80 { return u >= 0x30 && u <= 0x39 }
        return category(u) == .decimalNumber
    }

    /// `char.IsLetter` (Lu, Ll, Lt, Lm, Lo).
    static func isLetter(_ u: UInt16) -> Bool {
        if u < 0x80 { return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) }
        switch category(u) {
        case .uppercaseLetter?, .lowercaseLetter?, .titlecaseLetter?, .modifierLetter?, .otherLetter?: return true
        default: return false
        }
    }

    /// `char.IsUpper` (Lu).
    static func isUpper(_ u: UInt16) -> Bool {
        if u < 0x80 { return u >= 0x41 && u <= 0x5A }
        return category(u) == .uppercaseLetter
    }

    /// `char.IsLetterOrDigit`.
    static func isLetterOrDigit(_ u: UInt16) -> Bool { isLetter(u) || isDigit(u) }

    /// `char.ToUpper(c)` — single-unit simple mapping; a multi-scalar mapping leaves the unit unchanged.
    static func toUpper(_ u: UInt16) -> UInt16 { NetText.simpleUpper(u) }

    /// `char.ToLower(c)` — single-unit simple mapping.
    static func toLower(_ u: UInt16) -> UInt16 {
        if u < 0x80 { return (u >= 0x41 && u <= 0x5A) ? u + 0x20 : u }
        guard !(0xD800...0xDFFF).contains(u), let sc = Unicode.Scalar(u) else { return u }
        let m = sc.properties.lowercaseMapping.unicodeScalars
        guard m.count == 1, let first = m.first, first.value <= 0xFFFF else { return u }
        return UInt16(first.value)
    }

    /// Ordinal `StartsWith` (the C# culture-sensitive overload behaves identically for these ASCII prefixes).
    static func startsWith(_ s: [UInt16], _ prefix: String) -> Bool {
        let p = Array(prefix.utf16)
        guard p.count <= s.count else { return false }
        for i in 0..<p.count where s[i] != p[i] { return false }
        return true
    }

    static func startsWith(_ s: String, _ prefix: String) -> Bool { startsWith(units(s), prefix) }

    /// `StartsWith(prefix, OrdinalIgnoreCase)`.
    static func startsWithIgnoreCase(_ s: [UInt16], _ prefix: String) -> Bool {
        let p = Array(prefix.utf16)
        guard p.count <= s.count else { return false }
        for i in 0..<p.count where s[i] != p[i] && NetText.simpleUpper(s[i]) != NetText.simpleUpper(p[i]) { return false }
        return true
    }

    /// Ordinal `EndsWith`.
    static func endsWith(_ s: [UInt16], _ suffix: String) -> Bool {
        let p = Array(suffix.utf16)
        guard p.count <= s.count else { return false }
        let off = s.count - p.count
        for i in 0..<p.count where s[off + i] != p[i] { return false }
        return true
    }

    /// `string.Split(separators, options)` over UTF-16 units.
    static func split(_ s: [UInt16], on separators: Set<UInt16>, removeEmpty: Bool) -> [[UInt16]] {
        var out: [[UInt16]] = []
        var cur: [UInt16] = []
        for u in s {
            if separators.contains(u) {
                if !(removeEmpty && cur.isEmpty) { out.append(cur) }
                cur = []
            } else {
                cur.append(u)
            }
        }
        if !(removeEmpty && cur.isEmpty) { out.append(cur) }
        return out
    }

    /// `Trim()` over units (the `char.IsWhiteSpace` set).
    static func trim(_ u: [UInt16]) -> [UInt16] {
        var a = 0, b = u.count
        while a < b, NetText.isWhiteSpace(u[a]) { a += 1 }
        while b > a, NetText.isWhiteSpace(u[b - 1]) { b -= 1 }
        return Array(u[a..<b])
    }

    /// `TrimStart()`.
    static func trimStart(_ u: [UInt16]) -> [UInt16] {
        var a = 0
        while a < u.count, NetText.isWhiteSpace(u[a]) { a += 1 }
        return Array(u[a...])
    }

    /// `TrimEnd()`.
    static func trimEnd(_ u: [UInt16]) -> [UInt16] {
        var b = u.count
        while b > 0, NetText.isWhiteSpace(u[b - 1]) { b -= 1 }
        return Array(u[..<b])
    }

    /// `string.IsNullOrWhiteSpace` over units.
    static func isBlank(_ u: [UInt16]) -> Bool { u.allSatisfy(NetText.isWhiteSpace) }

    /// Index of the first OrdinalIgnoreCase occurrence of `needle` at or after `from`.
    static func indexOfIgnoreCase(_ hay: [UInt16], _ needle: [UInt16], from: Int = 0) -> Int? {
        let fh = hay.map(NetText.simpleUpper), fn = needle.map(NetText.simpleUpper)
        if fn.isEmpty { return from }
        guard fn.count <= fh.count, from <= fh.count - fn.count else { return nil }
        outer: for i in from...(fh.count - fn.count) {
            for k in 0..<fn.count where fh[i + k] != fn[k] { continue outer }
            return i
        }
        return nil
    }

    /// Ordinal `s.Replace(old, new)` over units (non-overlapping, left to right).
    static func replaceOrdinal(_ s: [UInt16], _ old: [UInt16], _ new: [UInt16]) -> [UInt16] {
        guard !old.isEmpty, s.count >= old.count else { return s }
        var out: [UInt16] = []
        out.reserveCapacity(s.count)
        var i = 0
        while i < s.count {
            if i + old.count <= s.count, s[i] == old[0], Array(s[i..<(i + old.count)]) == old {
                out.append(contentsOf: new)
                i += old.count
            } else {
                out.append(s[i]); i += 1
            }
        }
        return out
    }

    /// `s.Replace(old, new, StringComparison.OrdinalIgnoreCase)` — every non-overlapping occurrence, left to right.
    static func replaceIgnoreCase(_ s: [UInt16], _ old: String, _ new: String) -> [UInt16] {
        let o = Array(old.utf16), n = Array(new.utf16)
        guard !o.isEmpty else { return s }
        var out: [UInt16] = []
        var i = 0
        while i < s.count {
            if let j = indexOfIgnoreCase(s, o, from: i) {
                out.append(contentsOf: s[i..<j])
                out.append(contentsOf: n)
                i = j + o.count
            } else {
                out.append(contentsOf: s[i...])
                break
            }
        }
        return out
    }
}
