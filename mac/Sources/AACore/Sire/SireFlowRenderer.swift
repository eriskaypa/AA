// Spec: 12 SIRE-020/041, §6.5 (display renderer: Segoe UI → the system font at 1 DIP = 1 pt, regular weight only,
//       italic via the font descriptor, WPF margins → paragraph spacing with collapsed margins approximated as
//       `max(0, top − previous.bottom)`, chip / label backgrounds + padding via TextKit 1 `NSTextBlock`, disc / circle
//       `NSTextList`s with marker text, intra-Run `\n` → U+2028 inside the same paragraph, fixed sRGB colours),
//       05 §6.4 (TextKit 1 list markers stored as `\t{marker}\t`).
import AppKit

/// Renders a `SireFlowDocument` as an attributed string for TextKit 1 display.
public enum SireFlowRenderer {
    /// `NSColor` from a fixed ARGB (sRGB).
    public static func color(_ c: ARGB) -> NSColor {
        NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: CGFloat(c.a) / 255)
    }

    /// The display font for a WPF size (regular weight; italic when asked).
    public static func font(size: Double, italic: Bool) -> NSFont {
        let base = NSFont.systemFont(ofSize: CGFloat(size), weight: .regular)
        guard italic else { return base }
        let d = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: d, size: CGFloat(size)) ?? base
    }

    static let listIndentStep: CGFloat = 24

    /// Renders the document. Paragraphs are separated by `\n`; the last one has no trailing newline.
    public static func render(_ doc: SireFlowDocument) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var prevBottom: Double = 0
        var first = true

        func appendParagraph(_ p: SireFlowParagraph, lists: [NSTextList], extraTop: Double = 0) {
            if !first { out.append(NSAttributedString(string: "\n")) }
            first = false
            let size = p.fontSize ?? SireFlowDocument.fontSize
            let margin = p.margin ?? SireThickness(0, 0, 0, 0)
            let top = max(0, margin.top + extraTop - prevBottom)
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = CGFloat(margin.bottom)
            style.paragraphSpacingBefore = CGFloat(top)
            style.lineBreakMode = .byWordWrapping
            if !lists.isEmpty {
                let level = CGFloat(lists.count)
                let markerAt = 6 + listIndentStep * (level - 1)
                let textAt = listIndentStep * level + 4
                style.textLists = lists
                style.tabStops = [NSTextTab(textAlignment: .left, location: markerAt),
                                  NSTextTab(textAlignment: .left, location: textAt)]
                style.headIndent = textAt
                style.firstLineHeadIndent = 0
            } else {
                style.headIndent = CGFloat(margin.left)
                style.firstLineHeadIndent = CGFloat(margin.left)
                style.tailIndent = margin.right > 0 ? -CGFloat(margin.right) : 0
            }
            if let bg = p.background {
                let block = NSTextBlock()
                block.backgroundColor = color(bg)
                let pad = p.padding ?? SireThickness(0, 0, 0, 0)
                block.setWidth(CGFloat(pad.left), type: .absoluteValueType, for: .padding, edge: .minX)
                block.setWidth(CGFloat(pad.top), type: .absoluteValueType, for: .padding, edge: .minY)
                block.setWidth(CGFloat(pad.right), type: .absoluteValueType, for: .padding, edge: .maxX)
                block.setWidth(CGFloat(pad.bottom), type: .absoluteValueType, for: .padding, edge: .maxY)
                block.setWidth(CGFloat(top), type: .absoluteValueType, for: .margin, edge: .minY)
                block.setWidth(CGFloat(margin.bottom), type: .absoluteValueType, for: .margin, edge: .maxY)
                style.textBlocks = [block]
                style.paragraphSpacing = 0
                style.paragraphSpacingBefore = 0
            }
            let font = font(size: size, italic: p.italic)
            let start = out.length
            if !lists.isEmpty, let list = lists.last {
                let marker = list.marker(forItemNumber: 1)
                out.append(NSAttributedString(string: "\t\(marker)\t", attributes: [
                    .font: font, .foregroundColor: color(doc.foreground)]))
            }
            if p.runs.isEmpty {
                // An empty paragraph keeps its line (a zero-width run carries the attributes).
                out.append(NSAttributedString(string: "", attributes: [.font: font]))
            }
            for r in p.runs {
                let text = r.text.replacingOccurrences(of: "\r\n", with: "\u{2028}")
                    .replacingOccurrences(of: "\n", with: "\u{2028}").replacingOccurrences(of: "\r", with: "\u{2028}")
                out.append(NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: color(r.foreground ?? doc.foreground)]))
            }
            out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: out.length - start))
            prevBottom = margin.bottom
        }

        func appendList(_ l: SireFlowList, parents: [NSTextList]) {
            let tl = NSTextList(markerFormat: l.marker == .disc ? .disc : .circle, options: 0)
            let lists = parents + [tl]
            for (i, item) in l.items.enumerated() {
                let extraTop = i == 0 ? (l.margin?.top ?? 0) : 0
                appendParagraph(item.paragraph, lists: lists, extraTop: extraTop)
                if let n = item.nested { appendList(n, parents: lists) }
            }
            if let b = l.margin?.bottom, b > 0 { prevBottom = max(prevBottom, b) }
        }

        for b in doc.blocks {
            switch b {
            case .paragraph(let p): appendParagraph(p, lists: [])
            case .list(let l): appendList(l, parents: [])
            }
        }
        return out
    }
}
