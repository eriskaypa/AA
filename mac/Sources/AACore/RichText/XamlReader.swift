// PLACEHOLDER(W-RICH) — contract: ARCHITECTURE.md §6.7
// Spec: 05 §XD.2.8 (projection to NSAttributedString), CONT-006 (unparseable → the editor withholds saving),
// CONT-161 (fragments). Compiling stub created by F1; W-RICH replaces this file in place.
// Placeholder safety (ARCH §6.7, §11): `read` returns `.empty` for "" and `.unparseable(raw:)` for ANY other input
// (never `.empty`), so an editor built against the stub withholds saving and can never blank a note.
import AppKit

public enum XamlReadOutcome {
    case empty(RichTextMetadata)
    case document(NSAttributedString, RichTextMetadata)
    /// The editor withholds saving (CONT-006).
    case unparseable(raw: String)
}

@MainActor public enum XamlReader {
    public static func read(_ xaml: String, context: XamlContext) -> XamlReadOutcome {
        // PLACEHOLDER(W-RICH)
        if xaml.isEmpty {
            var metadata = RichTextMetadata(context: context)
            metadata.isPlaceholderResult = true
            return .empty(metadata)
        }
        return .unparseable(raw: xaml)
    }

    /// CONT-161.
    public static func readFragment(_ xaml: String, destinationContext: XamlContext) -> NSAttributedString? {
        // PLACEHOLDER(W-RICH)
        nil
    }
}
