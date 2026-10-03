// Spec: 05 §6.2 (TextKit 1: NSTextTable / NSTextTableBlock / NSTextBlock for tables, paragraph backgrounds, borders,
//       padding — SIRE chips, `<hr>`), §6.4 "Opaque" (an NSTextAttachment holding the original XML fragment, drawn as
//       a small grey chip `⧉ embedded content`, written back verbatim), §4.3.7 rule 10.
import AppKit

/// The text block of a single Paragraph's own `Background` / `Padding` / `BorderThickness` (display only; the writer
/// reads the paragraph's modelled tokens).
public final class XamlParagraphBlock: NSTextBlock {}

/// The text block of a Section, List or ListItem that has a background, border or padding (display only).
public final class XamlContainerBlock: NSTextBlock {}

/// An element the Mac cannot represent (InlineUIContainer, BlockUIContainer, Figure, Floater, unknown elements):
/// kept byte-for-byte and written back at its position (§4.3.7 rule 10). The character also carries
/// `.aaPreservedXaml` with the same XML, which is what the writer reads.
public final class XamlPreservedAttachment: NSTextAttachment {
    public var xml: String = ""
    public var isBlock: Bool = false

    @MainActor public convenience init(xml: String, isBlock: Bool) {
        self.init(data: nil, ofType: nil)
        self.xml = xml
        self.isBlock = isBlock
        self.image = Self.chipImage
    }

    /// `⧉ embedded content` on a light grey rounded chip (the editor paper stays light in both appearances).
    @MainActor static let chipImage: NSImage = {
        let label = "⧉ embedded content" as NSString
        let font = NSFont.systemFont(ofSize: 11)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor(srgbRed: 0.33, green: 0.36, blue: 0.40, alpha: 1),
        ]
        let size = label.size(withAttributes: attrs)
        let w = ceil(size.width) + 14, h = ceil(size.height) + 4
        return NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            NSColor(srgbRed: 0.91, green: 0.92, blue: 0.94, alpha: 1).setFill()
            path.fill()
            NSColor(srgbRed: 0.75, green: 0.77, blue: 0.80, alpha: 1).setStroke()
            path.lineWidth = 1
            path.stroke()
            label.draw(at: NSPoint(x: 7, y: (h - size.height) / 2), withAttributes: attrs)
            return true
        }
    }()
}
