// Contract: ARCHITECTURE.md §6.7.
// Spec: 05 §XD.3 (RichTextMetadata additions), CONT-165 (completion source = `context`), 01 §4.11 invariant 1
// (`sourceHash` lets the editor detect "unchanged → never rewrite").
import Foundation

/// Stable id of a carried element within one document.
public typealias XamlElementID = String

/// Everything the writer needs that is not in the attributed string.
public struct RichTextMetadata: Sendable, Equatable {
    public var rootAttributes: [XamlRawAttribute]
    /// nil = new document.
    public var rootRole: XamlRootRole?
    /// Carried Section / List / ListItem / Table / TableRowGroup / TableRow / TableCell / TableColumn attributes.
    public var elementAttributes: [XamlElementID: [XamlRawAttribute]]
    public var hyperlinkAttributes: [XamlElementID: [XamlRawAttribute]]
    /// Which consumer loaded it; the CONT-165 completion source.
    public var context: XamlContext
    public var loadability: XamlLoadability
    public var hasAnyLock: Bool
    /// Lets the editor detect "unchanged → never rewrite".
    public var sourceHash: Int
    /// True only from the F1 placeholder reader (ARCHITECTURE.md §11).
    public var isPlaceholderResult: Bool

    /// Empty metadata for a new document.
    public init(context: XamlContext) {
        rootAttributes = []
        rootRole = nil
        elementAttributes = [:]
        hyperlinkAttributes = [:]
        self.context = context
        loadability = .loadable
        hasAnyLock = false
        sourceHash = 0
        isPlaceholderResult = false
    }

    /// FNV-1a (64-bit) over the UTF-8 bytes: stable across launches (unlike `hashValue`), cheap, and equal for equal
    /// strings — what `sourceHash` holds.
    public static func hash(of text: String) -> Int {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in text.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return Int(truncatingIfNeeded: h)
    }
}
