// Spec: 01 §4.5 (SafeIdentity), 03 §3.8, 09 §7.14 (Sanitize), 11 §7.15; Windows `Path.GetInvalidFileNameChars()`.
import Foundation

public enum WindowsFileName {
    /// `" < > | : * ? \ /` and U+0000–U+001F (Windows `Path.GetInvalidFileNameChars()`).
    public static let invalidCharacters: Set<Character> = {
        var s: Set<Character> = ["\"", "<", ">", "|", ":", "*", "?", "\\", "/"]
        for v in 0..<0x20 { s.insert(Character(Unicode.Scalar(UInt8(v)))) }
        return s
    }()

    static func isInvalid(_ sc: Unicode.Scalar) -> Bool {
        sc.value < 0x20 || "\"<>|:*?\\/".unicodeScalars.contains(sc)
    }

    /// Replaces every invalid character with `replacement`; a blank result → `fallback`, else the result trimmed
    /// (the `Sanitize` helpers of the crew schedule and saved-lists exports).
    public static func sanitize(_ name: String, replacement: Character = "_", fallback: String) -> String {
        var out = String.UnicodeScalarView()
        let rep = replacement.unicodeScalars
        for sc in name.unicodeScalars {
            if isInvalid(sc) { out.append(contentsOf: rep) } else { out.append(sc) }
        }
        let s = String(out)
        return NetText.isBlank(s) ? fallback : NetText.trim(s)
    }

    /// 03 §3.8 `SafeIdentity`: drop invalid characters and spaces, trim, `"AA"` when empty.
    public static func safeIdentity(_ identity: String) -> String {
        var out = String.UnicodeScalarView()
        for sc in identity.unicodeScalars where !isInvalid(sc) && sc != " " { out.append(sc) }
        let s = NetText.trim(String(out))
        return s.isEmpty ? "AA" : s
    }
}
