// Spec: 01 §4.1.4 (Guid row: lowercase "D" on write, 36-char 8-4-4-4-12 any case on read), ARCHITECTURE.md §3.6
import Foundation

public extension UUID {
    /// Lowercase .NET "D" format: `3f2504e0-4f89-11d3-9a0c-0305e82c3301`.
    var netString: String { uuidString.lowercased() }

    /// Accepts exactly 36 characters `8-4-4-4-12` with hex digits in any case; anything else → nil.
    init?(netString s: String) {
        let u = Array(s.utf8)
        guard u.count == 36 else { return nil }
        for (i, c) in u.enumerated() {
            if i == 8 || i == 13 || i == 18 || i == 23 {
                guard c == 0x2D else { return nil }
            } else {
                let hex = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)
                guard hex else { return nil }
            }
        }
        guard let g = UUID(uuidString: s) else { return nil }
        self = g
    }

    /// `00000000-0000-0000-0000-000000000000` (`Guid.Empty`, never omitted on write).
    static let netEmpty = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// .NET `Guid.ToString("N")`: 32 lowercase hex digits, no dashes (attachment and temp-file names).
    var netN: String { netString.replacingOccurrences(of: "-", with: "") }
}
