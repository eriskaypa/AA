// Contract: ARCHITECTURE.md §6.7.
// Spec: 05 §3.3 (HtmlToXamlConverter port, rule for rule: Convert, ExtractCfHtmlFragment, Style, EmitChildren,
//       HandleElement, EmitTable, EmitInlineChildren, WriteRun / WriteStyleAttrs, MergeStyle, ApplyCss, MapAlign,
//       ParseLengthPx, NormaliseColor), §7.1 (H1–H20 and the helper vectors), CONT-035, CONT-037,
//       DECISIONS 05 ("HTML paste whitespace quirk: clean up — don't create blank ' ' paragraphs"; recorded in
//       Deviations/W-RICH.md together with K-13 and the CF_HTML byte offsets).
// The output is a paste intermediate (never stored as-is): the editor feeds it to `XamlReader.readFragment`.
import Foundation

public enum HTMLToXAML {
    /// 05 §3.3 `Convert`: blank → `""`. An output that XmlWriter could not write (an XML-illegal character) is `""`
    /// as well, so the paste falls back to plain text exactly as on Windows.
    public static func convert(_ html: String) -> String {
        guard !NetText.isBlank(html) else { return "" }
        let doc = RichHTMLParser.parse(extractFragment(html))
        for bad in doc.descendants where ["script", "style", "meta", "link", "head", "title"].contains(bad.name) {
            bad.remove()
        }
        var w = RichHTMLConverter()
        w.out.start("Section")
        w.out.attr("xml:space", "preserve")
        w.out.attr("xmlns", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
        var open = false
        w.emitChildren(doc, RichHTMLStyle(), &open)
        if open { w.closeParagraph() }
        w.out.end()
        return w.out.failed ? "" : w.out.text
    }

    /// CF_HTML `StartFragment` / `EndFragment` (UTF-8 byte offsets, as the format defines them), else the text from
    /// the first `<html`, else the input.
    static func extractFragment(_ html: String) -> String {
        if let s = number(after: "StartFragment:", in: html), let e = number(after: "EndFragment:", in: html) {
            let bytes = Array(html.utf8)
            if s >= 0, e > s, e <= bytes.count {
                return String(decoding: bytes[s..<e], as: UTF8.self)
            }
        }
        if let r = html.range(of: "<\\s*html", options: [.regularExpression, .caseInsensitive]) {
            return String(html[r.lowerBound...])
        }
        return html
    }

    private static func number(after key: String, in s: String) -> Int? {
        guard let r = s.range(of: key, options: .caseInsensitive) else { return nil }
        let digits = s[r.upperBound...].prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        return Int(digits)
    }

    // MARK: Helpers exposed for the §7.1 vectors

    /// 05 §3.3 rule 13, with K-13 (alpha 0 → no colour on the Mac).
    public static func normaliseColor(_ raw: String) -> String? {
        let c = NetText.trim(raw)
        guard !c.isEmpty else { return nil }
        if c.hasPrefix("#") {
            let hex = c.dropFirst()
            return [3, 4, 6, 8].contains(hex.count) && hex.allSatisfy({ $0.isHexDigit && $0.isASCII }) ? c : nil
        }
        if let m = c.wholeMatch(of: #/(?i)rgba?\(\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*(?:,\s*([0-9.]+)\s*)?\)/#) {
            if let a = m.output.4, let av = Double(a), av == 0 { return nil }          // K-13
            func clamp(_ s: Substring) -> Int { Int(s).map { max(0, min(255, $0)) } ?? 255 }
            return String(format: "#%02X%02X%02X", clamp(m.output.1), clamp(m.output.2), clamp(m.output.3))
        }
        if c.allSatisfy({ $0.isASCII && $0.isLetter }), WpfColor.parse(c) != nil { return c }
        return nil
    }

    /// 05 §3.3 rule 12.
    public static func parseLengthPx(_ raw: String) -> Double? {
        let v = NetText.trim(raw)
        guard let m = v.wholeMatch(of: #/(?i)([0-9.]+)\s*(px|pt|em|rem|%)?/#), let n = Double(m.output.1),
              m.output.1.filter({ $0 == "." }).count <= 1, m.output.1 != "." else { return nil }
        switch m.output.2?.lowercased() {
        case "pt"?: return n * 1.333
        case "em"?, "rem"?: return n * 14
        case "%"?: return 14 * n / 100
        default: return n
        }
    }

    /// 05 §3.3 rule 11.
    public static func mapAlign(_ v: String) -> String {
        switch NetText.trim(v).lowercased() {
        case "center": return "Center"
        case "right": return "Right"
        case "justify": return "Justify"
        default: return "Left"
        }
    }

    /// .NET `ToString("0.##", InvariantCulture)`: 15 significant digits, then half-away-from-zero to 2 decimals.
    public static func formatSize(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        var d = Decimal(string: String(format: "%.15g", v)) ?? Decimal(v)
        var r = Decimal()
        NSDecimalRound(&r, &d, 2, .plain)
        return NSDecimalNumber(decimal: r).stringValue
    }
}

/// The converter's style state (05 §3.3 rule 3), cloned per element.
struct RichHTMLStyle {
    var bold = false, italic = false, underline = false, strike = false
    var foreground: String?, background: String?, fontFamily: String?
    var fontSize: Double?
    var align: String?
}

/// XmlWriter-shaped output: no declaration, no indentation, empty elements as `<X />`.
struct RichXMLOut {
    private(set) var text = ""
    private(set) var failed = false
    private var stack: [String] = []
    private var startOpen = false

    mutating func start(_ name: String) {
        closeStart()
        text += "<" + name
        stack.append(name)
        startOpen = true
    }

    mutating func attr(_ name: String, _ value: String) {
        text += " " + name + "=\"" + escape(value, attribute: true) + "\""
    }

    mutating func string(_ s: String) {
        closeStart()
        text += escape(s, attribute: false)
    }

    mutating func end() {
        guard let name = stack.popLast() else { return }
        if startOpen { text += " />"; startOpen = false } else { text += "</" + name + ">" }
    }

    private mutating func closeStart() {
        if startOpen { text += ">"; startOpen = false }
    }

    private mutating func escape(_ s: String, attribute: Bool) -> String {
        var r = ""
        for sc in s.unicodeScalars {
            switch sc {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            case "\"" where attribute: r += "&quot;"
            case "\n" where attribute: r += "&#xA;"
            case "\r" where attribute: r += "&#xD;"
            default:
                if XamlValues.isXMLChar(sc) { r.unicodeScalars.append(sc) } else { failed = true }
            }
        }
        return r
    }
}

/// The walker of 05 §3.3 rules 4–10.
struct RichHTMLConverter {
    var out = RichXMLOut()
    /// DECISIONS 05 clean-up: a paragraph opened by a block element is written lazily, so one that a nested block
    /// closes before it received any content leaves nothing behind (no empty `<div>`→`<p>` paragraphs).
    private var pending: (attrs: [(String, String)], byBlock: Bool)?
    /// Whitespace-only runs that arrived while `pending` was still unwritten (dropped with it, else written first).
    private var pendingWhitespace: [(String, RichHTMLStyle)] = []

    static let inlineTags: Set<String> = ["a", "b", "strong", "i", "em", "u", "s", "strike", "del", "span", "font", "mark",
                                          "sub", "sup", "code", "tt", "cite", "abbr", "big", "small"]
    static let blockTags: Set<String> = ["p", "div", "section", "article", "header", "footer", "main", "nav", "aside",
                                         "blockquote", "pre", "figure", "figcaption", "h1", "h2", "h3", "h4", "h5", "h6"]

    // MARK: Paragraph state

    private mutating func openParagraph(_ s: RichHTMLStyle, indent: String? = nil, byBlock: Bool) {
        pendingWhitespace = []
        var attrs: [(String, String)] = []
        if let a = s.align, !a.isEmpty { attrs.append(("TextAlignment", a)) }
        if let i = indent { attrs.append(("Margin", i)) }
        pending = (attrs, byBlock)
    }

    private mutating func materialise() {
        guard let p = pending else { return }
        out.start("Paragraph")
        for (n, v) in p.attrs { out.attr(n, v) }
        pending = nil
        let ws = pendingWhitespace
        pendingWhitespace = []
        for (t, st) in ws { writeRun(t, st) }
    }

    /// Close the open paragraph. `byNestedBlock`: a still-empty paragraph opened by a block element is dropped.
    mutating func closeParagraph(byNestedBlock: Bool = false) {
        if let p = pending {
            if byNestedBlock && p.byBlock { pending = nil; pendingWhitespace = []; return }
            materialise()
        }
        out.end()
    }

    // MARK: Text helpers

    static func collapse(_ s: String) -> String {
        var out: [UInt16] = []
        var inSpace = false
        for u in s.utf16 {
            if NetText.isWhiteSpace(u) {
                if !inSpace { out.append(0x20); inSpace = true }
            } else { out.append(u); inSpace = false }
        }
        return String(decoding: out, as: UTF16.self)
    }

    private func textOf(_ node: RichHTMLNode, parent: RichHTMLNode) -> String {
        var t = RichHTMLEntities.decode(node.text)
        if parent.name != "pre" && parent.name != "code" { t = Self.collapse(t) }
        return t
    }

    // MARK: Rule 4 EmitChildren

    mutating func emitChildren(_ parent: RichHTMLNode, _ style: RichHTMLStyle, _ open: inout Bool) {
        for node in parent.children {
            switch node.kind {
            case .text:
                let text = textOf(node, parent: parent)
                if text.isEmpty { continue }
                if !open {
                    if NetText.isBlank(text) { continue }               // DECISIONS 05: no blank " " paragraphs
                    openParagraph(style, byBlock: false)
                    open = true
                }
                if pending != nil, NetText.isBlank(text) {
                    pendingWhitespace.append((text, style))             // kept only if the paragraph gets content
                    continue
                }
                materialise()
                writeRun(text, style)
            case .element:
                handleElement(node, style, &open)
            default:
                continue
            }
        }
    }

    // MARK: Rule 5 HandleElement

    private mutating func handleElement(_ node: RichHTMLNode, _ style: RichHTMLStyle, _ open: inout Bool) {
        let name = node.name
        switch name {
        case "br":
            if !open { openParagraph(style, byBlock: false); open = true }
            materialise()
            out.start("LineBreak"); out.end()
            return
        case "hr":
            if open { closeParagraph(byNestedBlock: true); open = false }
            out.start("Paragraph")
            out.attr("BorderThickness", "0,0,0,1"); out.attr("BorderBrush", "#888"); out.attr("Padding", "0")
            out.end()
            return
        case "ul", "ol":
            if open { closeParagraph(byNestedBlock: true); open = false }
            out.start("List")
            out.attr("MarkerStyle", name == "ol" ? "Decimal" : "Disc")
            for li in node.children where li.kind == .element && li.name == "li" {
                out.start("ListItem")
                var liOpen = false
                emitChildren(li, mergeStyle(style, li), &liOpen)
                if liOpen { closeParagraph() }
                out.end()
            }
            out.end()
            return
        case "li":
            if open { closeParagraph(byNestedBlock: true); open = false }
            let s = mergeStyle(style, node)
            openParagraph(s, byBlock: true)
            var liOpen = true
            emitChildren(node, s, &liOpen)
            if liOpen { closeParagraph() }
            return
        case "table":
            if open { closeParagraph(byNestedBlock: true); open = false }
            emitTable(node, mergeStyle(style, node))
            return
        default:
            break
        }
        var merged = mergeStyle(style, node)
        if Self.blockTags.contains(name) {
            if open { closeParagraph(byNestedBlock: true); open = false }
            if ["h1", "h2", "h3", "h4", "h5", "h6"].contains(name) {
                merged.bold = true
                if merged.fontSize == nil {
                    merged.fontSize = ["h1": 22, "h2": 18, "h3": 16, "h4": 14, "h5": 13][name] ?? 12
                }
            }
            openParagraph(merged, indent: name == "blockquote" ? "20,0,0,0" : nil, byBlock: true)
            open = true
            emitChildren(node, merged, &open)
            if open { closeParagraph(); open = false }
            return
        }
        if Self.inlineTags.contains(name) {
            switch name {
            case "b", "strong": merged.bold = true
            case "i", "em", "cite": merged.italic = true
            case "u": merged.underline = true
            case "s", "strike", "del": merged.strike = true
            default: break
            }
            if !open { openParagraph(style, byBlock: false); open = true }
            materialise()
            if name == "a" {
                out.start("Hyperlink")
                let href = node.attribute("href") ?? ""
                if !NetText.isBlank(href) { out.attr("NavigateUri", href) }
                writeStyleAttrs(merged, isHyperlink: true)
                emitInlineChildren(node, merged)
                out.end()
            } else {
                out.start("Span")
                writeStyleAttrs(merged)
                emitInlineChildren(node, merged)
                out.end()
            }
            return
        }
        emitChildren(node, merged, &open)                               // unknown: children inline with merged style
    }

    // MARK: Rule 6 EmitTable

    private mutating func emitTable(_ table: RichHTMLNode, _ style: RichHTMLStyle) {
        func owned(_ tr: RichHTMLNode) -> Bool {
            var a = tr.parent
            while let p = a {
                if p === table { return true }
                if p.name == "table" { return false }
                a = p.parent
            }
            return false
        }
        let rows = table.descendants.filter { $0.kind == .element && $0.name == "tr" && owned($0) }
        guard !rows.isEmpty else { return }
        func cells(_ r: RichHTMLNode) -> [RichHTMLNode] {
            r.children.filter { $0.kind == .element && ($0.name == "td" || $0.name == "th") }
        }
        let cols = rows.map { r in cells(r).reduce(0) { $0 + max(1, $1.intAttribute("colspan", default: 1)) } }.max() ?? 0
        guard cols > 0 else { return }
        out.start("Table")
        out.attr("CellSpacing", "0")
        out.attr("Margin", "0,4,0,4")
        out.start("Table.Columns")
        for _ in 0..<cols { out.start("TableColumn"); out.end() }
        out.end()
        out.start("TableRowGroup")
        for row in rows {
            let rowStyle = mergeStyle(style, row)
            out.start("TableRow")
            for cell in cells(row) {
                var cellStyle = mergeStyle(rowStyle, cell)
                if cell.name == "th" { cellStyle.bold = true }
                out.start("TableCell")
                out.attr("BorderBrush", "#FF9AA0A6")
                out.attr("BorderThickness", "0.6")
                out.attr("Padding", "3,1,3,1")
                let colspan = max(1, cell.intAttribute("colspan", default: 1))
                let rowspan = max(1, cell.intAttribute("rowspan", default: 1))
                if colspan > 1 { out.attr("ColumnSpan", String(colspan)) }
                if rowspan > 1 { out.attr("RowSpan", String(rowspan)) }
                out.start("Paragraph")
                if let a = cellStyle.align, !a.isEmpty { out.attr("TextAlignment", a) }
                emitInlineChildren(cell, cellStyle)
                out.end()
                out.end()
            }
            out.end()
        }
        out.end()
        out.end()
    }

    // MARK: Rule 7 EmitInlineChildren

    private mutating func emitInlineChildren(_ parent: RichHTMLNode, _ style: RichHTMLStyle) {
        for node in parent.children {
            switch node.kind {
            case .text:
                let text = textOf(node, parent: parent)
                if text.isEmpty { continue }
                writeRun(text, style)
            case .element:
                let name = node.name
                if name == "br" { out.start("LineBreak"); out.end(); continue }
                var s = mergeStyle(style, node)
                switch name {
                case "b", "strong": s.bold = true
                case "i", "em", "cite": s.italic = true
                case "u": s.underline = true
                case "s", "strike", "del": s.strike = true
                default: break
                }
                if name == "a" {
                    out.start("Hyperlink")
                    let href = node.attribute("href") ?? ""
                    if !NetText.isBlank(href) { out.attr("NavigateUri", href) }
                    writeStyleAttrs(s, isHyperlink: true)
                    emitInlineChildren(node, s)
                    out.end()
                } else {
                    out.start("Span")
                    writeStyleAttrs(s)
                    emitInlineChildren(node, s)
                    out.end()
                }
            default:
                continue
            }
        }
    }

    // MARK: Rule 8 WriteRun / WriteStyleAttrs

    private mutating func writeRun(_ text: String, _ s: RichHTMLStyle) {
        out.start("Run")
        writeStyleAttrs(s)
        out.string(text)
        out.end()
    }

    private mutating func writeStyleAttrs(_ s: RichHTMLStyle, isHyperlink: Bool = false) {
        if s.bold { out.attr("FontWeight", "Bold") }
        if s.italic { out.attr("FontStyle", "Italic") }
        switch (s.underline, s.strike) {
        case (true, true): out.attr("TextDecorations", "Underline,Strikethrough")
        case (true, false): out.attr("TextDecorations", "Underline")
        case (false, true): out.attr("TextDecorations", "Strikethrough")
        default: break
        }
        if !isHyperlink, let f = s.foreground, !f.isEmpty { out.attr("Foreground", f) }
        if let b = s.background, !b.isEmpty { out.attr("Background", b) }
        if let f = s.fontFamily, !f.isEmpty { out.attr("FontFamily", f) }
        if let z = s.fontSize { out.attr("FontSize", HTMLToXAML.formatSize(z)) }
    }

    // MARK: Rules 9–10 MergeStyle / ApplyCss

    private func mergeStyle(_ parent: RichHTMLStyle, _ node: RichHTMLNode) -> RichHTMLStyle {
        var s = parent
        if let color = node.attribute("color"), !color.isEmpty { s.foreground = HTMLToXAML.normaliseColor(color) }
        if let face = node.attribute("face"), !face.isEmpty { s.fontFamily = face }
        if let size = node.attribute("size"), !size.isEmpty, let sz = Self.netDouble(size) { s.fontSize = 8 + sz * 2 }
        if let align = node.attribute("align"), !align.isEmpty { s.align = HTMLToXAML.mapAlign(align) }
        if let css = node.attribute("style"), !css.isEmpty { applyCss(&s, css) }
        return s
    }

    /// `double.TryParse(…, NumberStyles.Any, InvariantCulture)` for the legacy `size` attribute.
    static func netDouble(_ raw: String) -> Double? {
        let t = NetText.trim(raw).replacingOccurrences(of: ",", with: "")
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return v
    }

    private func applyCss(_ s: inout RichHTMLStyle, _ css: String) {
        for raw in css.split(separator: ";", omittingEmptySubsequences: false) {
            let part = NetText.trim(String(raw))
            guard !part.isEmpty, let colon = part.firstIndex(of: ":"), colon > part.startIndex else { continue }
            let key = NetText.toLowerInvariant(NetText.trim(String(part[..<colon])))
            let val = NetText.trim(String(part[part.index(after: colon)...]))
            switch key {
            case "font-weight":
                if val == "bold" || val == "bolder" || (XamlValues.parseInt(val).map { $0 >= 600 } ?? false) { s.bold = true }
                else if val == "normal" || val == "lighter" { s.bold = false }
            case "font-style":
                if val == "italic" || val == "oblique" { s.italic = true } else if val == "normal" { s.italic = false }
            case "text-decoration", "text-decoration-line":
                if val.contains("underline") { s.underline = true }
                if val.contains("line-through") { s.strike = true }
                if val == "none" { s.underline = false; s.strike = false }
            case "color":
                if let c = HTMLToXAML.normaliseColor(val) { s.foreground = c }
            case "background-color", "background":
                if let c = HTMLToXAML.normaliseColor(val) { s.background = c }
            case "font-family":
                s.fontFamily = NetText.trim(val, characters: [0x22, 0x27])
            case "font-size":
                if let px = HTMLToXAML.parseLengthPx(val) { s.fontSize = px }
            case "text-align":
                s.align = HTMLToXAML.mapAlign(val)
            default:
                break
            }
        }
    }
}
