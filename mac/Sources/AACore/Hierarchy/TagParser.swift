// PLACEHOLDER(W-HIER) — contract: ARCHITECTURE.md §6.8
// Spec: 04 §3.4 unified tag parsing (DECISIONS 04 Q-A: multi-delimiter, `#` strip, case-insensitive de-dup), Q-E
// (`#tag` sidebar search). Compiling stub created by F1; W-HIER replaces this file in place (ARCH §11).
import Foundation

public enum TagParser {
    public static func parse(_ text: String) -> [String] {
        // PLACEHOLDER(W-HIER)
        []
    }

    /// ", " joined.
    public static func display(_ tags: [String]) -> String {
        // PLACEHOLDER(W-HIER)
        ""
    }

    /// "#tag" sidebar search (DECISIONS 04 Q-E).
    public static func matches(_ tags: [String], hashQuery: String) -> Bool {
        // PLACEHOLDER(W-HIER)
        false
    }
}
