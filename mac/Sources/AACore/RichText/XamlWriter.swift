// PLACEHOLDER(W-RICH) — contract: ARCHITECTURE.md §6.7
// Spec: 05 §4.3.7 (Mac writer rules), §XD.2.10 (output DOM, wanted/same), DECISIONS 05 (empty document = "").
// Compiling stub created by F1; W-RICH replaces this file in place. The stub writer returns "" and must never be
// called for persistence by a correct consumer (ARCH §11).
import AppKit

@MainActor public enum XamlWriter {
    public static func write(_ text: NSAttributedString, metadata: RichTextMetadata, context: XamlContext) -> String {
        // PLACEHOLDER(W-RICH)
        ""
    }

    /// "" (DECISIONS 05).
    public static func emptyDocument() -> String {
        // PLACEHOLDER(W-RICH)
        ""
    }
}
