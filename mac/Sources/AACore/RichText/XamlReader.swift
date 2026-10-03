// Contract: ARCHITECTURE.md §6.7.
// Spec: 05 §XD.2.8 (projection: editor, viewer and SIRE pane → NSAttributedString, every key), CONT-006 (unparseable →
//       the editor withholds saving), CONT-161 (fragments resolved in the destination context), CONT-162 (fatal vs
//       recoverable issues), CONT-163 (carried / modelled attributes, `.aaParagraphAttrs`), CONT-166 (line-break
//       provenance), CONT-167 (Hyperlink display colour), §4.3.1 (blank → empty document), §4.3.7 rule 10 (opaque
//       fragments), 01 §4.11 (sourceHash: untouched bodies are never rewritten), §6.4 (one ordinary paragraph after a
//       table so the caret can leave it).
import AppKit

public enum XamlReadOutcome {
    case empty(RichTextMetadata)
    case document(NSAttributedString, RichTextMetadata)
    /// The editor withholds saving (CONT-006).
    case unparseable(raw: String)
}

@MainActor public enum XamlReader {
    public static func read(_ xaml: String, context: XamlContext) -> XamlReadOutcome {
        var md = RichTextMetadata(context: context)
        md.sourceHash = RichTextMetadata.hash(of: xaml)
        if NetText.isBlank(xaml) { return .empty(md) }
        switch XamlDOM.parse(xaml) {
        case .failure:
            return .unparseable(raw: xaml)
        case .success(let doc):
            var b = XamlReaderBuilder(doc: doc, context: context, fragment: false)
            let text = b.run()
            md.rootAttributes = b.rootAttributes
            md.rootRole = doc.rootRole
            md.elementAttributes = b.elementAttributes
            md.hyperlinkAttributes = b.hyperlinkAttributes
            md.loadability = doc.loadability
            md.hasAnyLock = b.hasAnyLock
            return .document(text, md)
        }
    }

    /// CONT-161: a fragment (HTML paste output, AA clipboard XAML, an inserted table or list) resolved in the
    /// destination context. A root without the presentation namespace is accepted here (it gets one).
    public static func readFragment(_ xaml: String, destinationContext: XamlContext) -> NSAttributedString? {
        guard let blocks = fragmentTree(xaml, destinationContext: destinationContext) else { return nil }
        let out = RichRenderer.render(RichDoc(blocks: blocks))
        // WPF merges a pasted fragment's last paragraph with the text after the caret (CONT-161), so a fragment that
        // ends with an ordinary paragraph carries no final paragraph break: pasting "word" (an in-app copy or an
        // inline web selection) inserts no new line. A fragment ending with a list, table, section or opaque block
        // keeps it — the structure stays a block of its own.
        if case .para(let last)? = blocks.last, !last.isOpaqueBlock, out.length > 0,
           (out.string as NSString).character(at: out.length - 1) == 0x0A {
            out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1))
        }
        return out
    }

    /// XD.2.8 "Typing attributes": the projection of the document's root context (an empty or cleared body keeps
    /// typing in it — a cleared SIRE body is still Segoe UI 13 `#334155`). New documents use `metadata.context`.
    public static func typingAttributes(for metadata: RichTextMetadata) -> [NSAttributedString.Key: Any] {
        var root = "<Section"
        let attrs = metadata.rootRole == nil ? XamlWriter.s1RootAttributes(metadata.context) : metadata.rootAttributes
        var hasNS = false
        for a in attrs {
            if a.qualifiedName == "xmlns" { hasNS = true }
            root += " " + a.qualifiedName + "=\"" + XamlWriterEmitter.escapeAttribute(a.value) + "\""
        }
        if !hasNS { root += " xmlns=\"" + XamlXMLNamespaces.presentation + "\"" }
        let xaml = root + "><Paragraph /></Section>"
        guard case .document(let s, _) = read(xaml, context: metadata.context), s.length > 0 else {
            return RichEditTree.defaultCharacterAttributes
        }
        var a = s.attributes(at: 0, effectiveRange: nil)
        for k in RichParagraphKeys.all where k != .paragraphStyle { a[k] = nil }
        return a
    }

    static func injectNamespace(_ xaml: String) -> String? {
        guard let lt = xaml.firstIndex(of: "<") else { return nil }
        var i = xaml.index(after: lt)
        while i < xaml.endIndex, !" \t\r\n/>".contains(xaml[i]) { i = xaml.index(after: i) }
        guard i > xaml.index(after: lt) else { return nil }
        var s = xaml
        s.insert(contentsOf: " xmlns=\"\(XamlXMLNamespaces.presentation)\"", at: i)
        return s
    }

    /// CONT-161 helper: the computed character context of the paragraph at `location`, as a `XamlContext` for
    /// `readFragment` (falls back to `base` for anything the text does not say).
    public static func destinationContext(in text: NSAttributedString, at location: Int, base: XamlContext) -> XamlContext {
        guard text.length > 0 else { return base }
        let ns = text.string as NSString
        let loc = max(0, min(location, text.length - 1))
        let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
        let probe = max(para.location, NSMaxRange(para) - 1)
        let a = text.attributes(at: min(probe, text.length - 1), effectiveRange: nil)
        var c = base
        if let fam = a[.aaFontFamilyName] as? String { c.fontFamily = fam }
        if let f = a[.font] as? NSFont {
            c.fontSize = Double(f.pointSize)
            if let tok = a[.aaFontWeightToken] as? String, let w = XamlValues.parseFontWeight(tok),
               (w >= 600) == RichFontResolver.isBoldish(f) {
                c.fontWeight = w
            } else {
                c.fontWeight = RichFontResolver.isBoldish(f) ? 700 : 400
            }
            c.fontStyle = RichFontResolver.isItalic(f, attributes: a) ? .italic : .normal
        }
        if let col = a[.foregroundColor] as? NSColor { c.foreground = RichColor.argb(col) }
        if let lang = a[.aaXmlLang] as? String { c.language = lang }
        if let ps = a[.paragraphStyle] as? NSParagraphStyle {
            c.flowDirection = ps.baseWritingDirection == .rightToLeft ? .rightToLeft : .leftToRight
            c.textAlignment = XamlReaderBuilder.wpfAlignment(ps.alignment, rtl: c.flowDirection == .rightToLeft)
                ?? c.textAlignment
        }
        return c
    }
}

/// Builds the block tree from a DOM and renders it (XD.2.8).
@MainActor
struct XamlReaderBuilder {
    let doc: XamlDocument
    let res: XamlStyleResolver
    let ctx: XamlContext
    let fragment: Bool
    private let rootStyle: XamlComputedStyle
    private(set) var rootAttributes: [XamlRawAttribute] = []
    private(set) var elementAttributes: [XamlElementID: [XamlRawAttribute]] = [:]
    private(set) var hyperlinkAttributes: [XamlElementID: [XamlRawAttribute]] = [:]
    private(set) var hasAnyLock = false
    private var hyperlinkIDs: [Int32: String] = [:]

    init(doc: XamlDocument, context: XamlContext, fragment: Bool) {
        self.doc = doc
        self.ctx = context
        self.fragment = fragment
        self.res = XamlStyleResolver(doc, context: context)
        self.rootStyle = res.computed(doc.root)
    }

    mutating func run() -> NSAttributedString {
        RichRenderer.render(RichDoc(blocks: readTree()))
    }

    /// The block tree of the document (a document ending with a table gets the §6.4 synthetic paragraph after it).
    mutating func readTree() -> [RichNode] {
        let root = doc[doc.root]
        if !root.isImplicit { rootAttributes = root.namespaceDeclarations + root.rawAttributes }
        var blocks = readBlocks(root.children)
        if !fragment, case .container(let c)? = blocks.last, c.info.kind == .table {
            let p = RichPara(content: NSMutableAttributedString(), terminator: terminatorAttributes(doc.root),
                             alignment: Self.nsAlignment(rootStyle), direction: Self.nsDirection(rootStyle.flowDirection),
                             carried: [], model: ["Synthetic": "1"])
            blocks.append(.para(p))
        }
        return blocks
    }

    // MARK: - Attribute classes (CONT-163)

    static let formatting: Set<String> = ["FontFamily", "FontSize", "FontWeight", "FontStyle", "FontStretch",
                                          "Foreground", "Background", "TextDecorations", "BaselineAlignment",
                                          "FlowDirection"]

    static func isFormatting(_ a: XamlRawAttribute) -> Bool {
        if a.namespaceURI == XamlXMLNamespaces.xml && a.qualifiedName == "xml:lang" { return true }
        guard a.namespaceURI == nil else { return false }
        return formatting.contains(a.qualifiedName) || a.qualifiedName.hasPrefix("Typography.")
            || a.qualifiedName.hasPrefix("NumberSubstitution.")
    }

    /// Raw attributes minus `excluded` names minus invalid recognised values, plus non-value property elements.
    private func carried(_ id: XamlNodeID, excluding excluded: Set<String>,
                         excludingProperties: Set<String> = []) -> [XamlRawAttribute] {
        let n = doc[id]
        var out = n.rawAttributes.filter { a in
            if a.namespaceURI == nil && excluded.contains(a.qualifiedName) { return false }
            return !XamlAttributeTable.isInvalid(a, on: n.kind)
        }
        for pe in n.propertyElements where !excludingProperties.contains(pe.propertyName) && pe.propertyName != "Columns" {
            out.append(XamlRawAttribute(qualifiedName: "#pe", namespaceURI: nil, value: pe.rawXML))
        }
        return out
    }

    /// Canonical brush token, or the inner XML of a property element when the brush has no attribute form.
    private func brushModel(_ id: XamlNodeID, _ property: String, _ b: XamlBrush?, into m: inout [String: String]) {
        guard let b else { return }
        switch b {
        case .solid(let argb, let op, _) where op == 1: m[property] = XamlValues.formatColor(argb)
        case .null: m[property] = "{x:Null}"
        default:
            if let pe = doc[id].propertyElements.first(where: { $0.propertyName == property }) {
                m[property + ".xml"] = Self.innerXML(pe.rawXML)
            }
            if case .solid(let argb, let op, _) = b { m[property] = XamlValues.formatColor(argb); m[property + ".opacity"] = XamlValues.formatLength(op) }
        }
    }

    /// The content of a property element (`<X.P>inner</X.P>` → `inner`).
    static func innerXML(_ raw: String) -> String {
        guard let gt = raw.firstIndex(of: ">"), let lt = raw.range(of: "</", options: .backwards) else { return raw }
        let start = raw.index(after: gt)
        guard start <= lt.lowerBound else { return "" }
        return String(raw[start..<lt.lowerBound])
    }

    // MARK: - Blocks

    private mutating func readBlocks(_ ids: [XamlNodeID]) -> [RichNode] {
        var out: [RichNode] = []
        for id in ids {
            let n = doc[id]
            switch n.kind {
            case .paragraph:
                out.append(.para(makePara(id)))
            case .section, .figure, .floater:
                if n.kind != .section { out.append(.para(opaqueBlock(id))); continue }
                let info = RichContainerInfo(kind: .section, id: RichIDs.fresh(), carried: carried(id, excluding: []))
                elementAttributes[info.id] = info.carried
                out.append(.container(RichContainer(info, children: readBlocks(n.children))))
            case .list:
                out.append(.container(makeList(id)))
            case .table:
                let (t, strays) = makeTable(id)
                out.append(.container(t))
                out.append(contentsOf: strays)
            case .listItem:
                let item = makeItem(id)
                out.append(.container(RichContainer(RichContainerInfo(kind: .list, id: RichIDs.fresh(),
                                                                      model: ["MarkerStyle": "Disc"]),
                                                    children: [.container(item)])))
            default:
                out.append(.para(opaqueBlock(id)))
            }
        }
        return out
    }

    private mutating func makeList(_ id: XamlNodeID) -> RichContainer {
        let n = doc[id]
        var model: [String: String] = ["MarkerStyle": n.local.markerStyle ?? "Disc"]
        if let s = n.local.startIndex { model["StartIndex"] = String(s) }
        if let m = n.local.margin { model["Margin"] = XamlValues.formatThickness(m) }
        if let p = n.local.padding { model["Padding"] = XamlValues.formatThickness(p) }
        let info = RichContainerInfo(kind: .list, id: RichIDs.fresh(),
                                     carried: carried(id, excluding: ["MarkerStyle", "StartIndex", "Margin", "Padding"]),
                                     model: model)
        elementAttributes[info.id] = info.carried
        var items: [RichNode] = []
        for c in n.children {
            if doc[c].kind == .listItem { items.append(.container(makeItem(c))) } else {
                let wrapper = RichContainer(RichContainerInfo(kind: .listItem, id: RichIDs.fresh()),
                                            children: readBlocks([c]))
                items.append(.container(wrapper))
            }
        }
        return RichContainer(info, children: items)
    }

    private mutating func makeItem(_ id: XamlNodeID) -> RichContainer {
        let info = RichContainerInfo(kind: .listItem, id: RichIDs.fresh(), carried: carried(id, excluding: []))
        elementAttributes[info.id] = info.carried
        return RichContainer(info, children: readBlocks(doc[id].children))
    }

    private mutating func makeTable(_ id: XamlNodeID) -> (RichContainer, [RichNode]) {
        let n = doc[id]
        var model: [String: String] = [:]
        if let s = n.local.cellSpacing { model["CellSpacing"] = XamlValues.formatLength(s) }
        if let m = n.local.margin { model["Margin"] = XamlValues.formatThickness(m) }
        var col = 0
        var groups: [RichNode] = []
        var strays: [RichNode] = []
        for c in n.children {
            let cn = doc[c]
            switch cn.kind {
            case .tableColumn:
                if let w = cn.rawAttributes.first(where: { $0.namespaceURI == nil && $0.qualifiedName == "Width" }),
                   XamlGridLength.parse(w.value) != nil {
                    model["Col\(col).Width"] = NetText.trim(w.value)
                }
                let extra = carried(c, excluding: ["Width"])
                if !extra.isEmpty { model["Col\(col)"] = RichColumnCoding.encode(extra) }
                col += 1
            case .tableRowGroup:
                let gi = RichContainerInfo(kind: .rowGroup, id: RichIDs.fresh(), carried: carried(c, excluding: []))
                elementAttributes[gi.id] = gi.carried
                var rows: [RichNode] = []
                for r in cn.children {
                    guard doc[r].kind == .tableRow else { strays.append(.para(opaqueBlock(r))); continue }
                    rows.append(.container(makeRow(r)))
                }
                groups.append(.container(RichContainer(gi, children: rows)))
            default:
                strays.append(.para(opaqueBlock(c)))
            }
        }
        if col > 0 { model["Columns"] = String(col) }
        let info = RichContainerInfo(kind: .table, id: RichIDs.fresh(),
                                     carried: carried(id, excluding: ["CellSpacing", "Margin"]), model: model)
        elementAttributes[info.id] = info.carried
        return (RichContainer(info, children: groups), strays)
    }

    private mutating func makeRow(_ id: XamlNodeID) -> RichContainer {
        let ri = RichContainerInfo(kind: .row, id: RichIDs.fresh(), carried: carried(id, excluding: []))
        elementAttributes[ri.id] = ri.carried
        var cells: [RichNode] = []
        for c in doc[id].children {
            let cn = doc[c]
            guard cn.kind == .tableCell else { continue }
            var model: [String: String] = [:]
            if let v = cn.local.columnSpan, v > 1 { model["ColumnSpan"] = String(v) }
            if let v = cn.local.rowSpan, v > 1 { model["RowSpan"] = String(v) }
            if let t = cn.local.borderThickness { model["BorderThickness"] = XamlValues.formatThickness(t) }
            if let t = cn.local.padding { model["Padding"] = XamlValues.formatThickness(t) }
            brushModel(c, "BorderBrush", cn.local.borderBrush, into: &model)
            brushModel(c, "Background", cn.local.background, into: &model)
            let ci = RichContainerInfo(kind: .cell, id: RichIDs.fresh(),
                                       carried: carried(c, excluding: ["ColumnSpan", "RowSpan", "BorderThickness",
                                                                       "Padding", "BorderBrush", "Background"],
                                                        excludingProperties: ["BorderBrush", "Background"]),
                                       model: model)
            elementAttributes[ci.id] = ci.carried
            var content = readBlocks(cn.children)
            if !content.contains(where: { !$0.paragraphs().isEmpty }) {
                content.append(.para(RichPara(content: NSMutableAttributedString(), terminator: terminatorAttributes(c),
                                              alignment: Self.nsAlignment(res.computed(c)),
                                              direction: Self.nsDirection(res.computed(c).flowDirection),
                                              carried: [], model: ["c.FontSize": XamlValues.formatLength(res.computed(c).fontSize)])))
            }
            cells.append(.container(RichContainer(ci, children: content)))
        }
        return RichContainer(ri, children: cells)
    }

    private mutating func opaqueBlock(_ id: XamlNodeID) -> RichPara {
        let xml = doc.sourceText(of: id) ?? ""
        let content = NSMutableAttributedString(attributedString: attachment(id, xml: xml, block: true))
        let parent = doc[id].parent ?? doc.root
        return RichPara(content: content, terminator: terminatorAttributes(parent),
                        alignment: Self.nsAlignment(res.computed(parent)),
                        direction: Self.nsDirection(res.computed(parent).flowDirection), carried: [],
                        model: ["OpaqueBlock": "1"])
    }

    // MARK: - Paragraphs

    static let paragraphModelled: Set<String> = ["TextAlignment", "LineHeight", "LineStackingStrategy", "FlowDirection",
                                                 "Margin", "TextIndent", "Padding", "BorderThickness", "BorderBrush",
                                                 "Background", "TextDecorations"]

    private mutating func makePara(_ id: XamlNodeID) -> RichPara {
        let n = doc[id]
        let cs = res.computed(id)
        var model: [String: String] = [:]
        if let m = n.local.margin { model["Margin"] = XamlValues.formatThickness(m) }
        if let t = n.local.textIndent { model["TextIndent"] = XamlValues.formatLength(t) }
        if let t = n.local.padding { model["Padding"] = XamlValues.formatThickness(t) }
        if let t = n.local.borderThickness { model["BorderThickness"] = XamlValues.formatThickness(t) }
        brushModel(id, "BorderBrush", n.local.borderBrush, into: &model)
        brushModel(id, "Background", n.local.background, into: &model)
        if let lh = n.local.lineHeight { model["LineHeight"] = XamlValues.formatLength(lh) }
        if let s = n.local.lineStackingStrategy { model["LineStackingStrategy"] = s.rawValue }
        if cs.lineHeight.isFinite { model["c.LineHeight"] = XamlValues.formatLength(cs.lineHeight) }
        if cs.lineStackingStrategy != .maxHeight { model["c.LineStackingStrategy"] = cs.lineStackingStrategy.rawValue }
        if cs.isHyphenationEnabled { model["c.IsHyphenationEnabled"] = "True" }
        model["c.FontSize"] = XamlValues.formatLength(cs.fontSize)
        let content = NSMutableAttributedString()
        inlines(n.children, into: content)
        return RichPara(content: content, terminator: terminatorAttributes(id), alignment: Self.nsAlignment(cs),
                        direction: Self.nsDirection(cs.flowDirection),
                        carried: carried(id, excluding: Self.paragraphModelled,
                                         excludingProperties: ["Background", "BorderBrush", "TextDecorations"]),
                        model: model)
    }

    static func nsDirection(_ d: XamlFlowDirection) -> NSWritingDirection { d == .rightToLeft ? .rightToLeft : .leftToRight }

    /// WPF `Left`/`Right` are relative to the flow direction (`Left` = leading).
    static func nsAlignment(_ cs: XamlComputedStyle) -> NSTextAlignment {
        let rtl = cs.flowDirection == .rightToLeft
        switch cs.textAlignment {
        case .left: return rtl ? .right : .left
        case .right: return rtl ? .left : .right
        case .center: return .center
        case .justify: return .justified
        }
    }

    static func wpfAlignment(_ a: NSTextAlignment, rtl: Bool) -> XamlTextAlignment? {
        switch a {
        case .left: return rtl ? .right : .left
        case .right: return rtl ? .left : .right
        case .center: return .center
        case .justified: return .justify
        default: return nil
        }
    }

    // MARK: - Inlines

    private mutating func inlines(_ ids: [XamlNodeID], into out: NSMutableAttributedString) {
        for id in ids {
            let n = doc[id]
            switch n.kind {
            case .run:
                let attrs = projection(id)
                Self.appendRunText(n.text ?? "", attrs: attrs, to: out)
                for c in n.children {                               // invalid nesting inside a Run: kept opaque
                    out.append(attachment(c, xml: doc.sourceText(of: c) ?? "", block: false))
                }
            case .span, .bold, .italic, .underline, .hyperlink:
                inlines(n.children, into: out)
            case .lineBreak:
                out.append(NSAttributedString(string: "\u{2028}", attributes: projection(id)))
            default:
                out.append(attachment(id, xml: doc.sourceText(of: id) ?? "", block: false))
            }
        }
    }

    /// CONT-166: newlines inside Run text become U+2028 marked with the exact original sequence.
    static func appendRunText(_ text: String, attrs: [NSAttributedString.Key: Any], to out: NSMutableAttributedString) {
        guard !text.isEmpty else { return }
        let u = Array(text.utf16)
        var seg: [UInt16] = []
        func flush() {
            if !seg.isEmpty {
                out.append(NSAttributedString(string: String(decoding: seg, as: UTF16.self), attributes: attrs))
                seg.removeAll()
            }
        }
        var i = 0
        while i < u.count {
            let c = u[i]
            var seq: String?
            if c == 0x0D { seq = (i + 1 < u.count && u[i + 1] == 0x0A) ? "\r\n" : "\r" }
            else if c == 0x0A { seq = "\n" }
            else if c == 0x2028 { seq = "\u{2028}" }
            else if c == 0x2029 { seq = "\u{2029}" }
            if let s = seq {
                flush()
                var a = attrs
                a[.aaInRunNewline] = s
                out.append(NSAttributedString(string: "\u{2028}", attributes: a))
                i += s.utf16.count
            } else {
                seg.append(c)
                i += 1
            }
        }
        flush()
    }

    private mutating func attachment(_ id: XamlNodeID, xml: String, block: Bool) -> NSAttributedString {
        var attrs = projection(id)
        let a = XamlPreservedAttachment(xml: xml, isBlock: block)
        attrs[.attachment] = a
        attrs[.aaPreservedXaml] = xml
        return NSAttributedString(string: "\u{FFFC}", attributes: attrs)
    }

    // MARK: - Projection (XD.2.8)

    private func familyToken(_ cs: XamlComputedStyle) -> String {
        if let s = cs.setter[.fontFamily], let f = doc[s].local.fontFamily { return f.raw }
        return ctx.fontFamily
    }

    /// The solid colour shown for a node whose computed foreground is not solid (nearest solid ancestor).
    private func inheritedSolid(_ id: XamlNodeID) -> (NSColor, UInt32) {
        var cur = doc[id].parent
        while let p = cur {
            switch res.computed(p).foreground {
            case .solid(let argb, let op, _): return (RichColor.color(argb, opacity: op), Self.displayARGB(argb, op))
            case .linkDefault: return (RichColor.color(ctx.linkDisplayColor), ctx.linkDisplayColor)
            default: cur = doc[p].parent
            }
        }
        return (RichColor.color(ctx.foreground), ctx.foreground)
    }

    static func displayARGB(_ argb: UInt32, _ op: Double) -> UInt32 {
        let a = UInt32(max(0, min(255, (Double(argb >> 24) * op).rounded())))
        return a << 24 | (argb & 0x00FF_FFFF)
    }

    private func characterBase(_ id: XamlNodeID) -> [NSAttributedString.Key: Any] {
        let cs = res.computed(id)
        var a: [NSAttributedString.Key: Any] = [:]
        let family = familyToken(cs)
        a[.font] = RichFontResolver.font(family: family, size: cs.fontSize, weight: cs.fontWeight,
                                         italic: cs.fontStyle != .normal)
        a[.aaFontFamilyName] = family
        if let s = cs.setter[.fontWeight], let t = doc[s].local.fontWeightToken { a[.aaFontWeightToken] = t }
        if let s = cs.setter[.fontStyle], let t = doc[s].local.fontStyleToken { a[.aaFontStyleToken] = t }
        a[.aaXmlLang] = cs.language
        a[NSAttributedString.Key("NSLanguage")] = cs.language
        var extras: [String: String] = [:]
        if cs.fontStretch != rootStyle.fontStretch {
            var tok = XamlValues.fontStretchToken(cs.fontStretch)
            if let s = cs.setter[.fontStretch],
               let raw = doc[s].rawAttributes.first(where: { $0.qualifiedName == "FontStretch" }) {
                tok = NetText.trim(raw.value)
            }
            extras["FontStretch"] = tok
        }
        for (k, v) in cs.typography where !XamlValues.sameToken(v, rootStyle.typography[k] ?? "") { extras[k] = v }
        for (k, v) in cs.numberSubstitution where !XamlValues.sameToken(v, rootStyle.numberSubstitution[k] ?? "") {
            extras[k] = v
        }
        if !extras.isEmpty { a[.aaInheritedExtras] = extras }
        switch cs.foreground {
        case .solid(let argb, let op, _):
            a[.foregroundColor] = RichColor.color(argb, opacity: op)
            if op != 1, let s = cs.setter[.foreground],
               let pe = doc[s].propertyElements.first(where: { $0.propertyName == "Foreground" }) {
                a[.aaForegroundBrushXml] = Self.innerXML(pe.rawXML)
                a[.richForegroundBrushDisplay] = XamlValues.formatColor(Self.displayARGB(argb, op))
            }
        case .nonSolid(let raw):
            let (c, v) = inheritedSolid(id)
            a[.foregroundColor] = c
            a[.aaForegroundBrushXml] = raw
            a[.richForegroundBrushDisplay] = XamlValues.formatColor(v)
        case .null:
            a[.foregroundColor] = inheritedSolid(id).0
        case .linkDefault:
            a[.foregroundColor] = RichColor.color(ctx.linkDisplayColor)
        }
        return a
    }

    /// The terminator of a paragraph: its own character context (XD.2.8 "Paragraph terminator").
    func terminatorAttributes(_ id: XamlNodeID) -> [NSAttributedString.Key: Any] { characterBase(id) }

    private mutating func projection(_ id: XamlNodeID) -> [NSAttributedString.Key: Any] {
        var a = characterBase(id)
        let n = doc[id]
        // Link colour (CONT-167).
        if res.isLinkStyled(id), let h = doc.enclosingHyperlink(of: id) {
            a[.aaLinkStyled] = true
            a[.foregroundColor] = RichColor.color(ctx.linkDisplayColor)
            a[.aaUnderlyingForeground] = underlying(h)
        }
        // Inline background (+ preserved brush).
        if let bg = res.inlineBackground(id) {
            switch bg {
            case .solid(let argb, let op, _):
                a[.backgroundColor] = RichColor.color(argb, opacity: op)
                if op != 1, let owner = ([id] + doc.inlineAncestors(of: id)).first(where: {
                    if case .solid? = doc[$0].local.background { return true }; return false
                }), let pe = doc[owner].propertyElements.first(where: { $0.propertyName == "Background" }) {
                    a[.aaBackgroundBrushXml] = Self.innerXML(pe.rawXML)
                    a[.richBackgroundBrushDisplay] = XamlValues.formatColor(Self.displayARGB(argb, op))
                }
            case .nonSolid(let raw):
                a[.aaBackgroundBrushXml] = raw
                a[.richBackgroundBrushDisplay] = "none"
            default: break
            }
        }
        // Decorations.
        let d = res.modelDecorations(id)
        if d.contains(.underline) { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if d.contains(.strikethrough) { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        var extra: [String] = []
        if d.contains(.overLine) { extra.append("OverLine") }
        if d.contains(.baseline) { extra.append("Baseline") }
        if !extra.isEmpty { a[.aaExtraDecorations] = extra }
        // Baseline.
        let shift = res.baselineShift(id)
        if shift != 0 { a[.superscript] = shift }
        if let tok = res.baselineToken(id) { a[.aaBaselineAlignment] = tok }
        // Writing direction differing from the paragraph's.
        if let p = res.paragraph(of: id), res.computed(id).flowDirection != res.computed(p).flowDirection {
            let dir = res.computed(id).flowDirection == .rightToLeft ? NSWritingDirection.rightToLeft : .leftToRight
            a[.writingDirection] = [NSNumber(value: dir.rawValue | NSWritingDirectionFormatType.embedding.rawValue)]
        }
        // Hyperlink identity.
        if let h = doc.enclosingHyperlink(of: id) {
            let hid: String
            if let v = hyperlinkIDs[h.index] { hid = v } else {
                hid = RichIDs.fresh()
                hyperlinkIDs[h.index] = hid
                hyperlinkAttributes[hid] = carried(h, excluding: [], excludingProperties: ["Foreground", "Background",
                                                                                           "TextDecorations"])
                    .filter { !Self.isFormatting($0) }
            }
            a[.aaHyperlink] = hid
            let hc = hyperlinkAttributes[hid] ?? []
            if !hc.isEmpty { a[.richHyperlinkAttributes] = RichAttributeCoding.encode(hc) }
            if let uri = doc[h].local.navigateUri, !NetText.isBlank(uri) {
                let t = NetText.trim(uri)
                if let url = URL(string: t) { a[.link] = url } else { a[.link] = t }
            }
        }
        // Lock (CONT-159).
        if let src = res.lockSource(id) {
            a[.aaLockSource] = src.rawValue
            a[.aaLocked] = true
            hasAnyLock = true
        }
        // Unrecognised / non-formatting Run attributes.
        if n.kind == .run, !n.isImplicit {
            let extra = carried(id, excluding: ["Text"], excludingProperties: ["Foreground", "Background",
                                                                                 "TextDecorations"])
                .filter { !Self.isFormatting($0) }
            if !extra.isEmpty { a[.aaExtraAttributes] = RichAttributeCoding.encode(extra) }
        }
        return a
    }

    /// CONT-167 `.aaUnderlyingForeground`: the colour the text has without the Hyperlink style layer.
    private func underlying(_ h: XamlNodeID) -> NSColor {
        guard let p = doc[h].parent else { return RichColor.color(ctx.foreground) }
        switch res.computed(p).foreground {
        case .solid(let argb, let op, _): return RichColor.color(argb, opacity: op)
        default: return inheritedSolid(h).0
        }
    }
}

/// Encoding of a TableColumn's carried attributes inside a table descriptor.
enum RichColumnCoding {
    static func encode(_ attrs: [XamlRawAttribute]) -> String {
        attrs.map { [$0.qualifiedName, $0.namespaceURI ?? "", $0.value].joined(separator: "\u{1E}") }
            .joined(separator: "\u{1F}")
    }

    static func decode(_ s: String?) -> [XamlRawAttribute] {
        guard let s, !s.isEmpty else { return [] }
        return s.split(separator: "\u{1F}", omittingEmptySubsequences: true).compactMap { e in
            let f = e.split(separator: "\u{1E}", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3 else { return nil }
            return XamlRawAttribute(qualifiedName: f[0], namespaceURI: f[1].isEmpty ? nil : f[1], value: f[2])
        }
    }
}
