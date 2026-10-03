// W-RICH test helpers (ARCH §12.2: prefixed): fixture loading, the S-1 root, canonical XML for "semantically equal"
// comparisons (05 §7.1 / §7.7: attribute-order-insensitive; XD.5: values normalised by their XD.2.2 grammar).
import AppKit
import Testing
@testable import AACore

enum RichTest {
    static let P = "http://schemas.microsoft.com/winfx/2006/xaml/presentation"

    static func sample(_ name: String) throws -> String { try Fixtures.string("xaml/samples/" + name) }

    /// The S-1 root start tag (05 §4.3.4).
    static var s1: String {
        let full = (try? sample("S-01-editor-save.xaml")) ?? ""
        guard let gt = full.firstIndex(of: ">") else { return "" }
        return String(full[...gt])
    }

    /// `R` + body + `/R` with the S-1 root.
    static func doc(_ body: String) -> String { s1 + body + "</Section>" }

    @MainActor static func read(_ xaml: String, _ ctx: XamlContext = .containerEditor) -> (NSAttributedString, RichTextMetadata) {
        switch XamlReader.read(xaml, context: ctx) {
        case .document(let s, let m): return (s, m)
        case .empty(let m): return (NSAttributedString(), m)
        case .unparseable: Issue.record("unparseable: \(xaml.prefix(120))"); return (NSAttributedString(), RichTextMetadata(context: ctx))
        }
    }

    @MainActor static func roundTrip(_ xaml: String, _ ctx: XamlContext = .containerEditor) -> String {
        let (s, m) = read(xaml, ctx)
        return XamlWriter.write(s, metadata: m, context: ctx)
    }

    /// Body of a written document (everything inside the root element).
    static func body(_ xaml: String) -> String {
        guard let gt = xaml.firstIndex(of: ">"), let end = xaml.range(of: "</Section>", options: .backwards) else { return xaml }
        return String(xaml[xaml.index(after: gt)..<end.lowerBound])
    }

    /// Visible text without list markers and terminators (paragraphs joined by `|`).
    static func paragraphs(_ s: NSAttributedString) -> [String] {
        var out: [String] = []
        let ns = s.string as NSString
        for r in RichDoc.paragraphRanges(ns) {
            var t = ""
            for i in r.start..<r.contentEnd where s.attribute(.aaListMarker, at: i, effectiveRange: nil) == nil {
                t += String(utf16CodeUnits: [ns.character(at: i)], count: 1)
            }
            out.append(t)
        }
        return out
    }

    /// Attributes of the first character of `substring` in `s`.
    static func attrs(_ s: NSAttributedString, at substring: String) -> [NSAttributedString.Key: Any] {
        let r = (s.string as NSString).range(of: substring)
        precondition(r.location != NSNotFound, "missing \(substring)")
        return s.attributes(at: r.location, effectiveRange: nil)
    }

    static func argb(_ any: Any?) -> UInt32? { (any as? NSColor).map(RichColor.argb) }

    // MARK: Canonical XML

    /// Canonical form: elements with attributes sorted by name; values normalised by grammar (thickness, colours,
    /// lengths, tokens); namespace declarations dropped; text kept verbatim.
    static func canonical(_ xml: String) -> String {
        let units = Array(xml.utf16)
        guard case .success(let tree) = XamlXMLScanner.scan(units) else { return "MALFORMED: " + xml }
        var out = ""
        func emit(_ i: Int) {
            let e = tree.elements[i]
            out += "<" + e.localName
            let attrs = e.attributes.filter { !$0.isNamespaceDeclaration }
                .map { ($0.qualifiedName, normalise($0.qualifiedName, $0.value)) }
                .sorted { $0.0 < $1.0 }
            for (n, v) in attrs { out += " \(n)=\"\(v)\"" }
            out += ">"
            for c in e.children {
                switch c {
                case .element(let k): emit(k)
                case .text(let s, _, _): out += s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                }
            }
            out += "</" + e.localName + ">"
        }
        emit(tree.root)
        return out
    }

    static func normalise(_ name: String, _ value: String) -> String {
        switch name {
        case "Margin", "Padding", "BorderThickness":
            return XamlValues.parseThickness(value).map(XamlValues.formatThickness) ?? value
        case "Foreground", "Background", "BorderBrush":
            if case .solid(let v, _, _)? = XamlValues.parseBrush(value) { return XamlValues.formatColor(v) }
            return value
        case "FontSize", "LineHeight", "TextIndent", "CellSpacing":
            return XamlValues.parseLength(value, allowAuto: true).map(XamlValues.formatLength) ?? value
        case "FontWeight":
            return XamlValues.parseFontWeight(value).map(XamlValues.fontWeightToken) ?? value
        case "TextDecorations":
            return XamlValues.parseDecorations(value).map(XamlValues.formatDecorations) ?? value
        case "xml:lang":
            return value.lowercased()
        default:
            return value
        }
    }

    static func semanticallyEqual(_ a: String, _ b: String) -> Bool { canonical(a) == canonical(b) }
}
