// Contract: ARCHITECTURE.md §6.7.
// Spec: 05 §4.3.7 (Mac writer rules 1–11), §XD.2.10 (output DOM, `wanted()`, `same()`, run splitting keys,
//       attribute order), §XD.2.11 (root completion), CONT-163 (flattened / modelled / carried; lock Span; Hyperlink
//       wrappers; empty paragraphs take character properties from the terminator), CONT-164 ("differs from
//       inherited"), CONT-165 (root verbatim + completion), CONT-166 (line-break provenance), CONT-167 (link colour →
//       `linkDefault`), CONT-162 (invalid recognised attributes are never re-emitted), DECISIONS 05 (empty → "").
import AppKit

@MainActor public enum XamlWriter {
    public static func write(_ text: NSAttributedString, metadata: RichTextMetadata, context: XamlContext) -> String {
        guard text.length > 0 else { return emptyDocument() }
        let doc = RichDoc.build(from: text)
        var e = XamlWriterEmitter(metadata: metadata, context: context)
        return e.emit(doc)
    }

    /// "" (DECISIONS 05).
    public static func emptyDocument() -> String { "" }

    /// The canonical S-1 root attributes for a context (new documents, non-Section roots), in S-1 order.
    public static func s1RootAttributes(_ c: XamlContext) -> [XamlRawAttribute] {
        func a(_ n: String, _ v: String, _ ns: String? = nil) -> XamlRawAttribute {
            XamlRawAttribute(qualifiedName: n, namespaceURI: ns, value: v)
        }
        var out = [a("xmlns", XamlXMLNamespaces.presentation, XamlXMLNamespaces.xmlns),
                   a("xml:space", "preserve", XamlXMLNamespaces.xml),
                   a("TextAlignment", c.textAlignment.rawValue), a("LineHeight", XamlValues.formatLength(c.lineHeight)),
                   a("IsHyphenationEnabled", c.isHyphenationEnabled ? "True" : "False"),
                   a("xml:lang", c.language, XamlXMLNamespaces.xml), a("FlowDirection", c.flowDirection.rawValue)]
        var ns = XamlContext.s1NumberSubstitution.compactMap { k, _ in c.numberSubstitution[k].map { a(k, $0) } }
        for k in c.numberSubstitution.keys.sorted() where !XamlContext.s1NumberSubstitution.contains(where: { $0.0 == k }) {
            ns.append(a(k, c.numberSubstitution[k]!))
        }
        out += ns
        out += [a("FontFamily", c.fontFamily), a("FontStyle", c.fontStyle.rawValue),
                a("FontWeight", XamlValues.fontWeightToken(c.fontWeight)),
                a("FontStretch", XamlValues.fontStretchToken(c.fontStretch)),
                a("FontSize", XamlValues.formatLength(c.fontSize)), a("Foreground", XamlValues.formatColor(c.foreground))]
        for (k, _) in XamlContext.s1Typography { if let v = c.typography[k] { out.append(a(k, v)) } }
        for k in c.typography.keys.sorted() where !XamlContext.s1Typography.contains(where: { $0.0 == k }) {
            out.append(a(k, c.typography[k]!))
        }
        return out
    }
}

/// Inheritable property names (XD.2.3 rows 1–14), as attribute names.
enum XamlInheritable {
    static let core: Set<String> = ["FontFamily", "FontSize", "FontWeight", "FontStyle", "FontStretch", "Foreground",
                                    "TextAlignment", "LineHeight", "LineStackingStrategy", "FlowDirection",
                                    "IsHyphenationEnabled"]

    static func isInheritable(_ a: XamlRawAttribute) -> Bool {
        if a.namespaceURI == XamlXMLNamespaces.xml { return a.qualifiedName == "xml:lang" }
        guard a.namespaceURI == nil else { return false }
        return core.contains(a.qualifiedName) || a.qualifiedName.hasPrefix("Typography.")
            || a.qualifiedName.hasPrefix("NumberSubstitution.")
    }

    /// Character (not paragraph) inheritable properties — the ones an empty paragraph takes from its terminator.
    static func isCharacterProperty(_ a: XamlRawAttribute) -> Bool {
        if a.namespaceURI == XamlXMLNamespaces.xml { return a.qualifiedName == "xml:lang" }
        guard a.namespaceURI == nil else { return false }
        return ["FontFamily", "FontSize", "FontWeight", "FontStyle", "FontStretch", "Foreground"].contains(a.qualifiedName)
            || a.qualifiedName.hasPrefix("Typography.") || a.qualifiedName.hasPrefix("NumberSubstitution.")
    }

    /// XD.2.10 `same(P, value, inherited)`.
    static func same(_ name: String, _ value: String, _ s: XamlComputedStyle) -> Bool {
        switch name {
        case "FontFamily": return XamlFontFamily(raw: value).canon == s.fontFamily.canon
        case "FontSize": return XamlValues.parseFontSize(value).map { XamlValues.sameLength($0, s.fontSize) } ?? false
        case "FontWeight": return XamlValues.parseFontWeight(value) == s.fontWeight
        case "FontStyle": return XamlValues.parseFontStyle(value) == s.fontStyle
        case "FontStretch": return XamlValues.parseFontStretch(value) == s.fontStretch
        case "Foreground": return XamlValues.parseBrush(value).map { XamlValues.sameBrush($0, s.foreground) } ?? false
        case "TextAlignment": return XamlValues.parseTextAlignment(value) == s.textAlignment
        case "LineHeight":
            return XamlValues.parseLength(value, allowAuto: true).map { XamlValues.sameLength($0, s.lineHeight) } ?? false
        case "LineStackingStrategy": return XamlValues.parseLineStacking(value) == s.lineStackingStrategy
        case "FlowDirection": return XamlValues.parseFlowDirection(value) == s.flowDirection
        case "IsHyphenationEnabled": return XamlValues.parseBool(value) == s.isHyphenationEnabled
        case "xml:lang": return XamlValues.sameToken(value, s.language)
        default:
            if name.hasPrefix("Typography.") { return s.typography[name].map { XamlValues.sameToken($0, value) } ?? false }
            if name.hasPrefix("NumberSubstitution.") {
                return s.numberSubstitution[name].map { XamlValues.sameToken($0, value) } ?? false
            }
            return false
        }
    }

    /// The style after an element sets `name = value`.
    static func apply(_ name: String, _ value: String, to s: inout XamlComputedStyle) {
        var local = XamlLocalValues()
        if name == "xml:lang" { local.language = NetText.toLowerInvariant(NetText.trim(value)) }
        else if name.hasPrefix("Typography.") { local.typography[name] = NetText.trim(value) }
        else if name.hasPrefix("NumberSubstitution.") { local.numberSubstitution[name] = NetText.trim(value) }
        else { _ = XamlAttributeTable.apply(name, value, to: &local) }
        s = s.applying(local, styleLayer: nil, node: XamlNodeID(index: -1))
    }
}

/// What a run (or an empty paragraph's terminator) wants, read from its attributes (XD.2.10 `wanted()` for Run).
struct RichCharWanted: Equatable {
    var family: String
    var size: Double
    var weight: Int
    var weightToken: String
    var style: XamlFontStyle
    var styleToken: String
    var foreground: XamlBrush?
    var foregroundXml: String?
    var language: String?
    var extras: [String: String]
    var flow: XamlFlowDirection?

    @MainActor init(_ a: [NSAttributedString.Key: Any], context: XamlContext) {
        let font = (a[.font] as? NSFont)
            ?? RichFontResolver.font(family: context.fontFamily, size: context.fontSize, weight: context.fontWeight,
                                     italic: context.fontStyle != .normal)
        if let tok = a[.aaFontFamilyName] as? String, !NetText.isBlank(tok), RichFontResolver.familyMatches(token: tok, font: font) {
            family = tok
        } else {
            family = RichFontResolver.writableFamilyName(of: font)
        }
        size = Double(font.pointSize)
        let italic = RichFontResolver.isItalic(font, attributes: a)
        if let tok = a[.aaFontWeightToken] as? String, let w = XamlValues.parseFontWeight(tok),
           RichFontResolver.weightTokenMatches(w, font: font, token: family, italic: italic) {
            weight = w
            weightToken = NetText.trim(tok)
        } else {
            let bold = RichFontResolver.isBoldish(font)
            weight = bold ? 700 : 400
            weightToken = bold ? "Bold" : "Normal"
        }
        if let tok = a[.aaFontStyleToken] as? String, let st = XamlValues.parseFontStyle(tok), (st != .normal) == italic {
            style = st
            styleToken = NetText.trim(tok)
        } else {
            style = italic ? .italic : .normal
            styleToken = style.rawValue
        }
        if a[.aaLinkStyled] as? Bool == true {
            foreground = .linkDefault
        } else if let c = a[.foregroundColor] as? NSColor {
            let argb = RichColor.argb(c)
            if let xml = a[.aaForegroundBrushXml] as? String, let disp = a[.richForegroundBrushDisplay] as? String,
               XamlValues.parseBrush(disp).map({ if case .solid(let v, _, _) = $0 { return v == argb }; return false }) == true {
                foreground = RichBrushXML.brush(xml)
                foregroundXml = xml
            } else {
                foreground = .solid(argb: argb, opacity: 1, isScRgb: false)
            }
        }
        language = (a[.aaXmlLang] as? String).map { NetText.toLowerInvariant($0) }
        extras = (a[.aaInheritedExtras] as? [String: String]) ?? [:]
        if let wd = (a[.writingDirection] as? [NSNumber])?.first {
            flow = (wd.intValue & 0x1) == 1 ? .rightToLeft : .leftToRight
        }
    }
}

/// Parsing preserved brush XML (`<SolidColorBrush Color= Opacity=/>`) for comparisons.
enum RichBrushXML {
    static func brush(_ xml: String) -> XamlBrush {
        let wrapped = "<Run xmlns=\"\(XamlXMLNamespaces.presentation)\"><Run.Foreground>\(xml)</Run.Foreground></Run>"
        if case .success(let d) = XamlDOM.parse(wrapped), let b = d.nodes.first(where: { $0.kind == .run })?.local.foreground {
            return b
        }
        return .nonSolid(rawXML: xml)
    }
}

@MainActor
struct XamlWriterEmitter {
    let metadata: RichTextMetadata
    let context: XamlContext
    private var out = ""
    private var rootStyle: XamlComputedStyle

    init(metadata: RichTextMetadata, context: XamlContext) {
        self.metadata = metadata
        self.context = context
        self.rootStyle = XamlComputedStyle(context: context)
    }

    // MARK: - Escaping

    static func escapeText(_ s: String) -> String {
        var r = ""
        r.reserveCapacity(s.utf16.count)
        for sc in s.unicodeScalars {
            switch sc {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            case "\r": r += "&#xD;"
            default:
                if isXMLChar(sc) { r.unicodeScalars.append(sc) }
            }
        }
        return r
    }

    static func escapeAttribute(_ s: String) -> String {
        var r = ""
        for sc in s.unicodeScalars {
            switch sc {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            case "\"": r += "&quot;"
            case "\t": r += "&#x9;"
            case "\n": r += "&#xA;"
            case "\r": r += "&#xD;"
            default:
                if isXMLChar(sc) { r.unicodeScalars.append(sc) }
            }
        }
        return r
    }

    static func isXMLChar(_ sc: Unicode.Scalar) -> Bool { XamlValues.isXMLChar(sc) }

    private mutating func attr(_ name: String, _ value: String) {
        out += " " + name + "=\"" + Self.escapeAttribute(value) + "\""
    }

    // MARK: - Root (CONT-165, XD.2.11)

    private func rootAttributes() -> [XamlRawAttribute] {
        var attrs: [XamlRawAttribute]
        switch metadata.rootRole {
        case .wrapper(.section)?:
            attrs = metadata.rootAttributes
        case .wrapper?:
            attrs = XamlWriter.s1RootAttributes(context)
            for old in metadata.rootAttributes where XamlInheritable.isInheritable(old) {
                if let i = attrs.firstIndex(where: { $0.qualifiedName == old.qualifiedName }) { attrs[i] = old } else {
                    attrs.append(old)
                }
            }
        default:
            attrs = XamlWriter.s1RootAttributes(context)
        }
        if !attrs.contains(where: { $0.qualifiedName == "xmlns" }) {
            attrs.insert(XamlRawAttribute(qualifiedName: "xmlns", namespaceURI: XamlXMLNamespaces.xmlns,
                                          value: XamlXMLNamespaces.presentation), at: 0)
        }
        if let i = attrs.firstIndex(where: { $0.qualifiedName == "xml:space" }) {
            attrs[i] = XamlRawAttribute(qualifiedName: "xml:space", namespaceURI: XamlXMLNamespaces.xml, value: "preserve")
        } else {
            attrs.append(XamlRawAttribute(qualifiedName: "xml:space", namespaceURI: XamlXMLNamespaces.xml, value: "preserve"))
        }
        let s1 = XamlWriter.s1RootAttributes(context)
        for name in ["TextAlignment", "LineHeight", "xml:lang", "FlowDirection", "FontFamily", "FontStyle", "FontWeight",
                     "FontStretch", "FontSize", "Foreground"] where !attrs.contains(where: { $0.qualifiedName == name }) {
            if let a = s1.first(where: { $0.qualifiedName == name }) { attrs.append(a) }
        }
        return attrs
    }

    mutating func emit(_ doc: RichDoc) -> String {
        let attrs = rootAttributes()
        var style = XamlComputedStyle(context: context)
        for a in attrs where XamlInheritable.isInheritable(a) && !XamlAttributeTable.isInvalid(a, on: .section) {
            XamlInheritable.apply(a.qualifiedName, a.value, to: &style)
        }
        rootStyle = style
        out = "<Section"
        for a in attrs { attr(a.qualifiedName, a.value) }
        let mark = out.count
        out += ">"
        blocks(doc.blocks, style)
        if out.count == mark + 1 {
            out.removeLast()
            out += " />"
        } else {
            out += "</Section>"
        }
        return out
    }

    // MARK: - Blocks

    /// Emits carried attributes (source order) applying CONT-164 to inheritable ones; returns property elements.
    private mutating func carried(_ attrs: [XamlRawAttribute], on kind: XamlNodeKind, style: inout XamlComputedStyle,
                                  skip: (XamlRawAttribute) -> Bool = { _ in false }) -> [String] {
        let parent = style
        var pes: [String] = []
        for a in attrs {
            if a.qualifiedName == "#pe" { pes.append(a.value); continue }
            if skip(a) || XamlAttributeTable.isInvalid(a, on: kind) { continue }
            if XamlInheritable.isInheritable(a) {
                if XamlInheritable.same(a.qualifiedName, a.value, parent) { continue }
                XamlInheritable.apply(a.qualifiedName, a.value, to: &style)
            }
            attr(a.qualifiedName, a.value)
        }
        return pes
    }

    private mutating func open(_ name: String) { out += "<" + name }

    private mutating func blocks(_ nodes: [RichNode], _ style: XamlComputedStyle) {
        for n in nodes {
            switch n {
            case .para(let p): paragraph(p, style)
            case .container(let c): container(c, style)
            }
        }
    }

    private mutating func container(_ c: RichContainer, _ parent: XamlComputedStyle) {
        var style = parent
        switch c.info.kind {
        case .section:
            open("Section")
            let pes = carried(c.info.carried, on: .section, style: &style)
            out += ">" + pes.joined()
            blocks(c.children, style)
            out += "</Section>"
        case .list:
            open("List")
            let pes = carried(c.info.carried, on: .list, style: &style)
            attr("MarkerStyle", c.info.model["MarkerStyle"] ?? "Disc")
            if let s = c.info.model["StartIndex"], s != "1" { attr("StartIndex", s) }
            if let m = c.info.model["Margin"] { attr("Margin", m) }
            if let p = c.info.model["Padding"] { attr("Padding", p) }
            out += ">" + pes.joined()
            for item in c.children {
                if case .container(let ic) = item, ic.info.kind == .listItem {
                    var istyle = style
                    open("ListItem")
                    let ipes = carried(ic.info.carried, on: .listItem, style: &istyle)
                    if ic.children.isEmpty && ipes.isEmpty { out += " />"; continue }
                    out += ">" + ipes.joined()
                    blocks(ic.children, istyle)
                    out += "</ListItem>"
                } else {
                    out += "<ListItem>"
                    blocks([item], style)
                    out += "</ListItem>"
                }
            }
            out += "</List>"
        case .table:
            table(c, &style)
        case .listItem, .rowGroup, .row, .cell:
            blocks(c.children, style)                                   // grammar repaired upstream
        }
    }

    private mutating func table(_ c: RichContainer, _ style: inout XamlComputedStyle) {
        open("Table")
        let pes = carried(c.info.carried, on: .table, style: &style)
        if let s = c.info.model["CellSpacing"] { attr("CellSpacing", s) }
        if let m = c.info.model["Margin"] { attr("Margin", m) }
        out += ">" + pes.joined()
        // Column count: declared, or the grid width (Σ spans).
        var gridCols = 0
        var occupied: [[Bool]] = []
        var r = 0
        for g in c.children {
            guard case .container(let gc) = g else { continue }
            for row in gc.children {
                guard case .container(let rc) = row, rc.info.kind == .row else { continue }
                for cell in rc.children {
                    guard case .container(let cc) = cell, cc.info.kind == .cell else { continue }
                    let cs = max(1, Int(cc.info.model["ColumnSpan"] ?? "") ?? 1)
                    let rs = max(1, Int(cc.info.model["RowSpan"] ?? "") ?? 1)
                    while occupied.count < r + rs { occupied.append([]) }
                    var col = 0
                    while col < occupied[r].count, occupied[r][col] { col += 1 }
                    for rr in r..<(r + rs) {
                        while occupied[rr].count < col + cs { occupied[rr].append(false) }
                        for k in col..<(col + cs) { occupied[rr][k] = true }
                    }
                }
                r += 1
            }
        }
        gridCols = occupied.map(\.count).max() ?? 0
        let declared = Int(c.info.model["Columns"] ?? "") ?? 0
        let cols = max(declared, gridCols)
        if cols > 0 {
            out += "<Table.Columns>"
            for k in 0..<cols {
                open("TableColumn")
                for a in RichColumnCoding.decode(c.info.model["Col\(k)"]) where !XamlAttributeTable.isInvalid(a, on: .tableColumn) {
                    if a.qualifiedName == "#pe" { continue }
                    attr(a.qualifiedName, a.value)
                }
                if let w = c.info.model["Col\(k).Width"] { attr("Width", w) }
                out += " />"
            }
            out += "</Table.Columns>"
        }
        var wroteGroup = false
        for g in c.children {
            guard case .container(let gc) = g, gc.info.kind == .rowGroup else { continue }
            wroteGroup = true
            var gstyle = style
            open("TableRowGroup")
            let gpes = carried(gc.info.carried, on: .tableRowGroup, style: &gstyle)
            out += ">" + gpes.joined()
            for row in gc.children {
                guard case .container(let rc) = row, rc.info.kind == .row else { continue }
                var rstyle = gstyle
                open("TableRow")
                let rpes = carried(rc.info.carried, on: .tableRow, style: &rstyle)
                out += ">" + rpes.joined()
                for cell in rc.children {
                    guard case .container(let cc) = cell, cc.info.kind == .cell else { continue }
                    tableCell(cc, rstyle)
                }
                out += "</TableRow>"
            }
            out += "</TableRowGroup>"
        }
        if !wroteGroup { out += "<TableRowGroup />" }
        out += "</Table>"
    }

    private mutating func tableCell(_ cc: RichContainer, _ parent: XamlComputedStyle) {
        var style = parent
        let m = cc.info.model
        open("TableCell")
        var pesModel: [String] = []
        if let v = m["BorderBrush.xml"] { pesModel.append("<TableCell.BorderBrush>" + v + "</TableCell.BorderBrush>") }
        else if let v = m["BorderBrush"] { attr("BorderBrush", v) }
        if let v = m["BorderThickness"] { attr("BorderThickness", v) }
        if let v = m["Padding"] { attr("Padding", v) }
        if let v = m["ColumnSpan"], v != "1" { attr("ColumnSpan", v) }
        if let v = m["RowSpan"], v != "1" { attr("RowSpan", v) }
        if let v = m["Background.xml"] { pesModel.append("<TableCell.Background>" + v + "</TableCell.Background>") }
        else if let v = m["Background"] { attr("Background", v) }
        let pes = carried(cc.info.carried, on: .tableCell, style: &style)
        out += ">" + pesModel.joined() + pes.joined()
        if cc.children.contains(where: { !$0.paragraphs().isEmpty }) { blocks(cc.children, style) } else {
            out += "<Paragraph />"
        }
        out += "</TableCell>"
    }

    // MARK: - Paragraphs

    private mutating func paragraph(_ p: RichPara, _ parent: XamlComputedStyle) {
        if p.isSynthetic && p.isEmpty { return }
        if p.isOpaqueBlock, p.content.length >= 1, let raw = p.content.attribute(.aaPreservedXaml, at: 0, effectiveRange: nil) as? String {
            out += raw
            if p.content.length == 1 { return }
            let rest = p.copy()
            rest.content.deleteCharacters(in: NSRange(location: 0, length: 1))
            rest.model["OpaqueBlock"] = nil
            paragraph(rest, parent)
            return
        }
        var style = parent
        let empty = p.isEmpty
        open("Paragraph")
        var pes = carried(p.carried, on: .paragraph, style: &style) { a in
            empty && XamlInheritable.isCharacterProperty(a)
        }
        // Modelled (CONT-163) — inheritable ones through CONT-164.
        let rtl = p.direction == .rightToLeft
            || (p.direction == .natural && style.flowDirection == .rightToLeft)
        if let al = XamlReaderBuilder.wpfAlignment(p.alignment, rtl: rtl) { inheritable("TextAlignment", al.rawValue, &style) }
        let lh = p.minimumLineHeight ?? 0
        let lhToken = lh > 0 ? XamlValues.formatLength(Double(lh)) : "Auto"
        inheritable("LineHeight", lhToken, &style)
        if let s = p.model["c.LineStackingStrategy"] ?? p.model["LineStackingStrategy"] {
            inheritable("LineStackingStrategy", s, &style)
        }
        if p.direction != .natural {
            inheritable("FlowDirection", p.direction == .rightToLeft ? "RightToLeft" : "LeftToRight", &style)
        }
        let m = p.model
        if let v = m["Margin"] { attr("Margin", v) }
        if let v = m["Padding"] { attr("Padding", v) }
        if let v = m["BorderThickness"] { attr("BorderThickness", v) }
        if let v = m["BorderBrush.xml"] { pes.append("<Paragraph.BorderBrush>" + v + "</Paragraph.BorderBrush>") }
        else if let v = m["BorderBrush"] { attr("BorderBrush", v) }
        if let v = m["Background.xml"] { pes.append("<Paragraph.Background>" + v + "</Paragraph.Background>") }
        else if let v = m["Background"] { attr("Background", v) }
        if let v = m["TextIndent"] { attr("TextIndent", v) }
        if empty {
            let w = RichCharWanted(p.terminator, context: context)
            characterAttributes(w, base: &style, emptyParagraph: true)
            if pes.isEmpty { out += " />"; return }
            out += ">" + pes.joined() + "</Paragraph>"
            return
        }
        out += ">" + pes.joined()
        inlines(p, style)
        out += "</Paragraph>"
    }

    private mutating func inheritable(_ name: String, _ value: String, _ style: inout XamlComputedStyle) {
        guard !XamlInheritable.same(name, value, style) else { return }
        XamlInheritable.apply(name, value, to: &style)
        attr(name, value)
    }

    /// Run / empty-paragraph inheritable character attributes in XD.2.10 order (CONT-164 against `base`).
    private mutating func characterAttributes(_ w: RichCharWanted, base: inout XamlComputedStyle, emptyParagraph: Bool,
                                              foregroundOverride: XamlBrush?? = nil) {
        let parent = base
        func put(_ name: String, _ value: String) {
            guard !XamlInheritable.same(name, value, parent) else { return }
            XamlInheritable.apply(name, value, to: &base)
            attr(name, value)
        }
        put("FontFamily", w.family)
        put("FontStyle", w.styleToken)
        put("FontWeight", w.weightToken)
        let wantedExtras = rootStyle.typography.merging(rootStyle.numberSubstitution) { a, _ in a }
            .merging(w.extras) { _, b in b }
        if let st = w.extras["FontStretch"] { put("FontStretch", st) }
        else if parent.fontStretch != rootStyle.fontStretch { put("FontStretch", XamlValues.fontStretchToken(rootStyle.fontStretch)) }
        put("FontSize", XamlValues.formatLength(w.size))
        let fg: XamlBrush? = foregroundOverride ?? w.foreground
        if let fg, !XamlValues.sameBrush(fg, parent.foreground) {
            switch fg {
            case .solid(let argb, let op, _) where op == 1 && w.foregroundXml == nil:
                attr("Foreground", XamlValues.formatColor(argb))
            case .linkDefault:
                break                                                   // never written explicitly (CONT-167)
            default:
                if let xml = w.foregroundXml { pendingPropertyElements.append(("Foreground", xml)) }
                else if case .solid(let argb, _, _) = fg { attr("Foreground", XamlValues.formatColor(argb)) }
            }
            base.foreground = fg
        }
        if !emptyParagraph {
            runNonInheritable()
        }
        if let f = w.flow { put("FlowDirection", f.rawValue) }
        if let l = w.language { put("xml:lang", l) }
        var keys = Set(parent.typography.keys).union(parent.numberSubstitution.keys)
        keys.formUnion(w.extras.keys.filter { $0 != "FontStretch" })
        for k in keys.sorted() {
            guard let v = wantedExtras[k] else { continue }
            put(k, v)
        }
    }

    // MARK: - Inlines

    private enum Seg {
        case text(String)
        case lineBreak
        case raw(String)
    }

    private struct RunKey: Equatable {
        var wanted: RichCharWanted
        var background: String?          // `#AARRGGBB`, or `xml:<inner>`
        var decorations: XamlDecorations
        var extraDecorations: [String]
        var baseline: String?
        var extraAttributes: [[String]]
        var lock: XamlLockSource?
        var hyperlink: String?
        var linkStyled: Bool
        var underlying: UInt32?

        static func == (a: RunKey, b: RunKey) -> Bool {
            a.wanted == b.wanted && a.background == b.background && a.decorations == b.decorations
                && a.extraDecorations == b.extraDecorations && a.baseline == b.baseline
                && a.extraAttributes == b.extraAttributes && a.lock == b.lock && a.hyperlink == b.hyperlink
                && a.linkStyled == b.linkStyled && a.underlying == b.underlying
        }
    }

    private var pendingPropertyElements: [(String, String)] = []
    private var currentKey: RunKey?

    private func runKey(_ a: [NSAttributedString.Key: Any]) -> RunKey {
        let w = RichCharWanted(a, context: context)
        var bg: String?
        var lock = (a[.aaLockSource] as? String).flatMap(XamlLockSource.init(rawValue:))
        if let c = a[.backgroundColor] as? NSColor {
            let argb = RichColor.argb(c)
            if argb == XamlValues.sentinelARGB { lock = .inlineRun }
            if let xml = a[.aaBackgroundBrushXml] as? String, let disp = a[.richBackgroundBrushDisplay] as? String,
               disp == XamlValues.formatColor(XamlReaderBuilder.displayARGB(argb, 1)) || disp == XamlValues.formatColor(argb) {
                bg = "xml:" + xml
            } else if (argb >> 24) > 0 {
                bg = XamlValues.formatColor(argb)
            }
        } else if let xml = a[.aaBackgroundBrushXml] as? String, a[.richBackgroundBrushDisplay] as? String == "none" {
            bg = "xml:" + xml
        }
        if lock == .inlineRun, bg == nil { bg = XamlValues.formatColor(XamlValues.sentinelARGB) }
        var d: XamlDecorations = []
        if let u = a[.underlineStyle] as? Int, u != 0 { d.insert(.underline) }
        if let s = a[.strikethroughStyle] as? Int, s != 0 { d.insert(.strikethrough) }
        let extra = (a[.aaExtraDecorations] as? [String]) ?? []
        // Baseline: the preserved token while it still matches `.superscript`.
        let shift = (a[.superscript] as? Int) ?? (a[.superscript] as? NSNumber)?.intValue ?? 0
        var baseline: String?
        let tok = a[.aaBaselineAlignment] as? String
        let tokShift: Int = {
            switch tok.flatMap(XamlValues.parseBaselineAlignment) {
            case .superscript?: return 1
            case .subscript?: return -1
            case nil:
                switch w.extras["Typography.Variants"]?.lowercased() {
                case "superscript"?: return 1
                case "subscript"?: return -1
                default: return 0
                }
            default: return 0
            }
        }()
        var wanted = w
        if shift == tokShift || (shift > 0) == (tokShift > 0) && (shift < 0) == (tokShift < 0) {
            baseline = tok
        } else {
            baseline = shift > 0 ? "Superscript" : (shift < 0 ? "Subscript" : nil)
            if let v = wanted.extras["Typography.Variants"]?.lowercased(), v == "superscript" || v == "subscript" {
                wanted.extras["Typography.Variants"] = "Normal"
            }
        }
        var hyperlink: String?
        if let h = a[.aaHyperlink] as? String { hyperlink = "id:" + h }
        else if let l = a[.link] { hyperlink = "link:" + ((l as? URL)?.absoluteString ?? "\(l)") }
        let linkStyled = a[.aaLinkStyled] as? Bool == true
        let underlying = (a[.aaUnderlyingForeground] as? NSColor).map(RichColor.argb)
        if lock == .block { lock = nil }
        return RunKey(wanted: wanted, background: bg, decorations: d, extraDecorations: extra, baseline: baseline,
                      extraAttributes: (a[.aaExtraAttributes] as? [[String]]) ?? [], lock: lock, hyperlink: hyperlink,
                      linkStyled: linkStyled, underlying: underlying)
    }

    private mutating func runNonInheritable() {
        guard let k = currentKey else { return }
        if let bg = k.background {
            if bg.hasPrefix("xml:") { pendingPropertyElements.append(("Background", String(bg.dropFirst(4)))) }
            else { attr("Background", bg) }
        }
        let all = k.decorations
        var parts: [String] = []
        if all.contains(.underline) { parts.append("Underline") }
        if all.contains(.strikethrough) { parts.append("Strikethrough") }
        for e in ["OverLine", "Baseline"] where k.extraDecorations.contains(e) { parts.append(e) }
        if !parts.isEmpty { attr("TextDecorations", parts.joined(separator: ",")) }
        if let b = k.baseline { attr("BaselineAlignment", b) }
    }

    private mutating func inlines(_ p: RichPara, _ paraStyle: XamlComputedStyle) {
        // 1. Segments with their keys.
        var items: [(RunKey, Seg, [NSAttributedString.Key: Any])] = []
        let c = p.content
        let ns = c.string as NSString
        c.enumerateAttributes(in: NSRange(location: 0, length: c.length), options: []) { a, range, _ in
            if a[.aaListMarker] != nil { return }
            let key = runKey(a)
            var buf = ""
            func flush() { if !buf.isEmpty { items.append((key, .text(buf), a)); buf = "" } }
            let sub = ns.substring(with: range)
            for ch in sub.unicodeScalars {
                switch ch.value {
                case 0x2028:
                    if let seq = a[.aaInRunNewline] as? String { buf += seq } else { flush(); items.append((key, .lineBreak, a)) }
                case 0xFFFC:
                    flush()
                    if let raw = a[.aaPreservedXaml] as? String { items.append((key, .raw(raw), a)) }
                default:
                    buf.unicodeScalars.append(ch)
                }
            }
            flush()
        }
        // 2. Merge adjacent text with equal keys.
        var merged: [(RunKey, Seg, [NSAttributedString.Key: Any])] = []
        for it in items {
            if case .text(let t) = it.1, let last = merged.last, case .text(let lt) = last.1, last.0 == it.0 {
                merged[merged.count - 1].1 = .text(lt + t)
            } else { merged.append(it) }
        }
        // 3. Hyperlink and lock-Span grouping.
        var i = 0
        while i < merged.count {
            let h = merged[i].0.hyperlink
            var j = i
            while j < merged.count, merged[j].0.hyperlink == h { j += 1 }
            if let h {
                var linkStyle = paraStyle
                linkStyle.foreground = .linkDefault
                open("Hyperlink")
                hyperlinkAttributes(h, merged[i].2)
                out += ">"
                lockGroups(Array(merged[i..<j]), linkStyle, inLink: true)
                out += "</Hyperlink>"
            } else {
                lockGroups(Array(merged[i..<j]), paraStyle, inLink: false)
            }
            i = j
        }
    }

    private mutating func hyperlinkAttributes(_ key: String, _ a: [NSAttributedString.Key: Any]) {
        var carried = RichAttributeCoding.decode(a[.richHyperlinkAttributes])
        if carried.isEmpty, let id = a[.aaHyperlink] as? String { carried = metadata.hyperlinkAttributes[id] ?? [] }
        let link: String? = (a[.link] as? URL)?.absoluteString ?? (a[.link] as? String)
        var pes: [String] = []
        var wroteUri = false
        for x in carried where !XamlAttributeTable.isInvalid(x, on: .hyperlink) {
            if x.qualifiedName == "#pe" { pes.append(x.value); continue }
            if x.namespaceURI == nil && x.qualifiedName == "NavigateUri" {
                guard let link else { continue }
                let t = NetText.trim(x.value)
                let keep = t == link || URL(string: t)?.absoluteString == link
                attr("NavigateUri", keep ? x.value : link)
                wroteUri = true
                continue
            }
            attr(x.qualifiedName, x.value)
        }
        if !wroteUri, let link { attr("NavigateUri", link) }
        pendingLinkPropertyElements = pes
    }

    private var pendingLinkPropertyElements: [String] = []

    private mutating func lockGroups(_ segs: [(RunKey, Seg, [NSAttributedString.Key: Any])], _ style: XamlComputedStyle,
                                     inLink: Bool) {
        if !pendingLinkPropertyElements.isEmpty {
            out += pendingLinkPropertyElements.joined()
            pendingLinkPropertyElements = []
        }
        var i = 0
        while i < segs.count {
            let inSpan = segs[i].0.lock == .inlineAncestor
            var j = i
            while j < segs.count, (segs[j].0.lock == .inlineAncestor) == inSpan { j += 1 }
            if inSpan { out += "<Span Background=\"" + XamlValues.formatColor(XamlValues.sentinelARGB) + "\">" }
            for k in i..<j { segment(segs[k], style, inLink: inLink) }
            if inSpan { out += "</Span>" }
            i = j
        }
    }

    private mutating func segment(_ s: (RunKey, Seg, [NSAttributedString.Key: Any]), _ style: XamlComputedStyle,
                                  inLink: Bool) {
        switch s.1 {
        case .raw(let xml):
            out += xml
        case .lineBreak:
            out += "<LineBreak />"
        case .text(let t):
            var base = style
            currentKey = s.0
            pendingPropertyElements = []
            open("Run")
            var fgOverride: XamlBrush?? = nil
            if s.0.linkStyled && !inLink {
                fgOverride = .some(s.0.underlying.map { .solid(argb: $0, opacity: 1, isScRgb: false) })
            }
            characterAttributes(s.0.wanted, base: &base, emptyParagraph: false, foregroundOverride: fgOverride)
            for a in s.0.extraAttributes where a.count == 3 {
                if a[0] == "#pe" { pendingPropertyElements.append(("", a[2])); continue }
                attr(a[0], a[2])
            }
            out += ">"
            for (prop, xml) in pendingPropertyElements {
                out += prop.isEmpty ? xml : "<Run." + prop + ">" + xml + "</Run." + prop + ">"
            }
            out += Self.escapeText(t) + "</Run>"
            currentKey = nil
        }
    }
}
