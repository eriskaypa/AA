// Spec: 09 §3.2 CrewText.Norm (COMPAS header matching, demonym/port/relationship lookups, the Shippalm reader).
import Foundation

public enum CrewText {
    /// `""` for empty; `’` (U+2019) → `'`; `\n` and `\r` → space; every run of .NET `\s` (Unicode white space incl.
    /// NBSP and tabs) → one space; .NET `Trim()`; `ToLowerInvariant()`.
    public static func norm(_ s: String) -> String {
        guard !s.isEmpty else { return "" }
        var out: [UInt16] = []
        out.reserveCapacity(s.utf16.count)
        var inSpace = false
        for var u in s.utf16 {
            if u == 0x2019 { u = 0x27 }
            if NetText.isWhiteSpace(u) {
                if !inSpace { out.append(0x20); inSpace = true }
            } else {
                out.append(u)
                inSpace = false
            }
        }
        return NetText.toLowerInvariant(NetText.trim(String(decoding: out, as: UTF16.self)))
    }
}
