// PLACEHOLDER(W-RICH) — contract: ARCHITECTURE.md §6.7
// Spec: 05 §3.1 (lock geometry), §4.4 (the sentinel #FFFFE699 is data), CONT-065. Compiling stub created by F1;
// W-RICH replaces this file in place. The stubs report no locks (ARCH §11).
import AppKit

public enum LockRules {
    public static let sentinel = ARGB(a: 0xFF, r: 0xFF, g: 0xE6, b: 0x99)

    public static func blocksEdit(_ s: NSAttributedString, range: NSRange, replacementLength: Int) -> Bool {
        // PLACEHOLDER(W-RICH)
        false
    }

    public static func lockedRanges(_ s: NSAttributedString, touching range: NSRange) -> [NSRange] {
        // PLACEHOLDER(W-RICH)
        []
    }

    /// Raw-string fast path (CONT-065).
    public static func quickHasAnyLock(_ xaml: String) -> Bool {
        // PLACEHOLDER(W-RICH)
        false
    }
}
