// PLACEHOLDER(W-RICH) — contract: ARCHITECTURE.md §6.7
// Spec: 05 §3.2 (list engine over NSTextStorage), CONT-040…047. ("ListFormatter" clashes with
// Foundation.ListFormatter.) One undo group per call, by the caller. Compiling stub created by F1; W-RICH
// replaces this file in place. The stubs change nothing (ARCH §11).
import AppKit

@MainActor public enum RichListFormatter {
    nonisolated public enum ListKind: Sendable, Equatable { case bullets, numbered }

    /// CONT-040/041.
    public static func toggleList(_ kind: ListKind, in s: NSTextStorage, selection: NSRange) -> NSRange {
        // PLACEHOLDER(W-RICH)
        selection
    }

    /// CONT-042.
    public static func normalise(_ s: NSTextStorage) {
        // PLACEHOLDER(W-RICH)
    }

    /// CONT-043.
    public static func indent(_ s: NSTextStorage, selection: NSRange) -> NSRange {
        // PLACEHOLDER(W-RICH)
        selection
    }

    public static func outdent(_ s: NSTextStorage, selection: NSRange) -> NSRange {
        // PLACEHOLDER(W-RICH)
        selection
    }

    /// CONT-044 (nil = not at an item start).
    public static func handleTab(_ s: NSTextStorage, selection: NSRange, shift: Bool) -> NSRange? {
        // PLACEHOLDER(W-RICH)
        nil
    }

    public static func handleReturn(_ s: NSTextStorage, selection: NSRange) -> NSRange? {
        // PLACEHOLDER(W-RICH)
        nil
    }

    /// CONT-045.
    public static func handleBackspaceAtItemStart(_ s: NSTextStorage, selection: NSRange) -> NSRange? {
        // PLACEHOLDER(W-RICH)
        nil
    }

    /// CONT-046.
    public static func moveItem(_ s: NSTextStorage, selection: NSRange, up: Bool) -> NSRange? {
        // PLACEHOLDER(W-RICH)
        nil
    }

    /// CONT-047.
    public static func insertList(lines: [String], kind: ListKind, into s: NSTextStorage, at: NSRange) -> NSRange {
        // PLACEHOLDER(W-RICH)
        NSRange(location: at.location, length: 0)
    }

    public static func isAtItemStart(_ s: NSAttributedString, location: Int) -> Bool {
        // PLACEHOLDER(W-RICH)
        false
    }
}
