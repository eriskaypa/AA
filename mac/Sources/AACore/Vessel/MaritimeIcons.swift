// PLACEHOLDER(W-VESSEL) — contract: ARCHITECTURE.md §6.8
// Spec: 10 §4.6/4.7 (quick-card icons and palette), OC-51. Compiling stub created by F1; W-VESSEL replaces this file
// in place. The stub tables are empty; `parseColor` returns the documented fallback #FF1E88E5 (ARCH §11).
import Foundation

public enum MaritimeIcons {
    public struct Icon: Sendable, Hashable {
        public let glyph: String
        public let name: String

        public init(glyph: String, name: String) {
            self.glyph = glyph; self.name = name
        }
    }

    public static let all: [Icon] = []        // PLACEHOLDER(W-VESSEL)
    public static let palette: [String] = []  // PLACEHOLDER(W-VESSEL)

    /// Blank / invalid → #FF1E88E5.
    public static func parseColor(_ s: String?) -> ARGB {
        // PLACEHOLDER(W-VESSEL)
        ARGB(a: 0xFF, r: 0x1E, g: 0x88, b: 0xE5)
    }

    /// luma / 255 > 0.6 → dark text (#1A1A1A).
    public static func readableForegroundIsDark(_ c: ARGB) -> Bool {
        // PLACEHOLDER(W-VESSEL)
        false
    }
}
