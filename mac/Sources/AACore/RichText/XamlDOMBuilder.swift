// Spec: 05 §XD.2.1 steps 5–9 (element kinds, property elements, attributes, text rules, root classification,
//       loadability), CONT-151 (node kinds; transparent collection property elements), CONT-152 (implicit nodes),
//       CONT-153 (raw + parsed attribute storage), CONT-154 (property-element values, `{x:Null}`, duplicates),
//       CONT-155 (wrapper vs content roots), CONT-162 / XD.2.12 (loadability), §4.3.1 (whitespace tolerance),
//       XD.2.3 (where each property is writable).
// Phase 2 of `XamlDOM.parse`: turns the raw XML tree into the XAML arena.
import Foundation

/// Which properties each element kind recognises (XD.2.3 "Writable on", §4.3.3) and how they parse.
enum XamlAttributeTable {
    static func name(_ k: XamlNodeKind) -> String {
        switch k {
        case .section: return "Section"
        case .flowDocument: return "FlowDocument"
        case .paragraph: return "Paragraph"
        case .list: return "List"
        case .listItem: return "ListItem"
        case .table: return "Table"
        case .tableColumn: return "TableColumn"
        case .tableRowGroup: return "TableRowGroup"
        case .tableRow: return "TableRow"
        case .tableCell: return "TableCell"
        case .blockUIContainer: return "BlockUIContainer"
        case .figure: return "Figure"
        case .floater: return "Floater"
        case .run: return "Run"
        case .span: return "Span"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .hyperlink: return "Hyperlink"
        case .lineBreak: return "LineBreak"
        case .inlineUIContainer: return "InlineUIContainer"
        case .text: return "#text"
        case .unknown(let n): return n
        }
    }

    static func kind(localName: String) -> XamlNodeKind? {
        switch localName {
        case "Section": return .section
        case "FlowDocument": return .flowDocument
        case "Paragraph": return .paragraph
        case "List": return .list
        case "ListItem": return .listItem
        case "Table": return .table
        case "TableColumn": return .tableColumn
        case "TableRowGroup": return .tableRowGroup
        case "TableRow": return .tableRow
        case "TableCell": return .tableCell
        case "BlockUIContainer": return .blockUIContainer
        case "Figure": return .figure
        case "Floater": return .floater
        case "Run": return .run
        case "Span": return .span
        case "Bold": return .bold
        case "Italic": return .italic
        case "Underline": return .underline
        case "Hyperlink": return .hyperlink
        case "LineBreak": return .lineBreak
        case "InlineUIContainer": return .inlineUIContainer
        default: return nil
        }
    }

    private static func isBlock(_ k: XamlNodeKind) -> Bool {
        switch k { case .section, .paragraph, .list, .table, .blockUIContainer: return true; default: return false }
    }

    private static func isInline(_ k: XamlNodeKind) -> Bool {
        switch k {
        case .run, .span, .bold, .italic, .underline, .hyperlink, .lineBreak, .inlineUIContainer, .figure, .floater: return true
        default: return false
        }
    }

    private static func isTextElement(_ k: XamlNodeKind) -> Bool {
        isBlock(k) || isInline(k) || k == .listItem || k == .tableRowGroup || k == .tableRow || k == .tableCell
    }

    /// Is `property` (a plain attribute name) writable on element `k`?
    static func recognises(_ property: String, on k: XamlNodeKind) -> Bool {
        let isTE = isTextElement(k)
        let isFD = k == .flowDocument
        let isBlock = Self.isBlock(k), isInline = Self.isInline(k)
        switch property {
        case "FontFamily", "FontSize", "FontWeight", "FontStyle", "FontStretch", "Foreground":
            return isTE || isFD
        case "Background": return isTE || isFD || k == .tableColumn
        case "TextAlignment", "LineHeight", "LineStackingStrategy":
            return isBlock || isFD || k == .listItem || k == .tableCell
        case "FlowDirection": return isBlock || isInline || isFD || k == .listItem || k == .tableCell
        case "IsHyphenationEnabled": return isBlock || isFD
        case "TextDecorations": return isInline || k == .paragraph
        case "BaselineAlignment": return isInline
        case "Margin": return isBlock || k == .listItem || k == .figure || k == .floater
        case "Padding", "BorderThickness", "BorderBrush":
            return isBlock || k == .listItem || k == .tableCell || k == .figure || k == .floater
        case "TextIndent", "KeepTogether": return k == .paragraph
        case "MarkerStyle", "StartIndex", "MarkerOffset": return k == .list
        case "CellSpacing": return k == .table
        case "Width": return k == .tableColumn
        case "ColumnSpan", "RowSpan": return k == .tableCell
        case "NavigateUri", "TargetName": return k == .hyperlink
        case "Text": return k == .run
        default: return false
        }
    }

    /// Known WPF properties that carry no semantics here (kept raw, never `unknownAttribute`).
    static func isKnownRawOnly(_ property: String, on k: XamlNodeKind) -> Bool {
        let isTE = isTextElement(k) || k == .flowDocument || k == .tableColumn
        switch property {
        case "Name", "Tag", "ToolTip", "Uid", "Cursor", "ForceCursor", "Focusable", "IsEnabled", "DataContext",
             "Style", "ContextMenu", "InputScope", "AllowDrop", "Language", "Resources", "FocusVisualStyle",
             "ToolTipService.ShowDuration":
            return isTE
        case "KeepWithNext", "MinOrphanLines", "MinWidowLines": return k == .paragraph
        case "BreakPageBefore", "BreakColumnBefore", "ClearFloaters":
            return isBlock(k)
        case "Command", "CommandParameter", "CommandTarget": return k == .hyperlink
        case "PagePadding", "PageWidth", "PageHeight", "MinPageWidth", "MaxPageWidth", "MinPageHeight", "MaxPageHeight",
             "ColumnWidth", "ColumnGap", "ColumnRuleWidth", "ColumnRuleBrush", "IsColumnWidthFlexible",
             "IsOptimalParagraphEnabled", "TextEffects":
            return k == .flowDocument
        case "HorizontalAnchor", "VerticalAnchor", "HorizontalOffset", "VerticalOffset", "CanDelayPlacement",
             "WrapDirection", "Height", "HorizontalAlignment", "Width":
            return k == .figure || k == .floater
        default: return false
        }
    }

    /// The typed-parse outcome of one recognised attribute: applied, invalid, or a markup extension.
    enum Outcome { case ok, invalid, markupExtension }

    /// Parses `value` into `local` for a recognised `property`.
    static func apply(_ property: String, _ value: String, to local: inout XamlLocalValues) -> Outcome {
        let t = XamlValues.trim(value)
        let isBrush = property == "Foreground" || property == "Background" || property == "BorderBrush"
        if t.hasPrefix("{"), !t.hasPrefix("{}") {
            if isBrush, let b = XamlValues.parseBrush(t), case .null = b {
                switch property {
                case "Foreground": local.foreground = .null
                case "Background": local.background = .null
                default: local.borderBrush = .null
                }
                return .ok
            }
            return .markupExtension
        }
        func ok<T>(_ v: T?, _ set: (T) -> Void) -> Outcome {
            guard let v else { return .invalid }
            set(v)
            return .ok
        }
        switch property {
        case "FontFamily":
            guard !NetText.isBlank(value) else { return .invalid }
            local.fontFamily = XamlFontFamily(raw: value)
            return .ok
        case "FontSize": return ok(XamlValues.parseFontSize(value)) { local.fontSize = $0 }
        case "FontWeight":
            return ok(XamlValues.parseFontWeight(value)) { local.fontWeight = $0; local.fontWeightToken = t }
        case "FontStyle": return ok(XamlValues.parseFontStyle(value)) { local.fontStyle = $0; local.fontStyleToken = t }
        case "FontStretch": return ok(XamlValues.parseFontStretch(value)) { local.fontStretch = $0 }
        case "Foreground": return ok(XamlValues.parseBrush(value)) { local.foreground = $0 }
        case "Background": return ok(XamlValues.parseBrush(value)) { local.background = $0 }
        case "BorderBrush": return ok(XamlValues.parseBrush(value)) { local.borderBrush = $0 }
        case "TextAlignment": return ok(XamlValues.parseTextAlignment(value)) { local.textAlignment = $0 }
        case "LineHeight":
            let v = XamlValues.parseLength(value, allowAuto: true)
            return ok(v.flatMap { $0.isNaN || $0 >= 0 ? $0 : nil }) { local.lineHeight = $0 }
        case "LineStackingStrategy": return ok(XamlValues.parseLineStacking(value)) { local.lineStackingStrategy = $0 }
        case "FlowDirection": return ok(XamlValues.parseFlowDirection(value)) { local.flowDirection = $0 }
        case "IsHyphenationEnabled": return ok(XamlValues.parseBool(value)) { local.isHyphenationEnabled = $0 }
        case "TextDecorations": return ok(XamlValues.parseDecorations(value)) { local.textDecorations = $0 }
        case "BaselineAlignment": return ok(XamlValues.parseBaselineAlignment(value)) { local.baselineAlignment = $0 }
        case "Margin": return ok(XamlValues.parseThickness(value)) { local.margin = $0 }
        case "Padding": return ok(XamlValues.parseThickness(value)) { local.padding = $0 }
        case "BorderThickness": return ok(XamlValues.parseThickness(value)) { local.borderThickness = $0 }
        case "TextIndent": return ok(XamlValues.parseLength(value, allowAuto: false)) { local.textIndent = $0 }
        case "KeepTogether": return ok(XamlValues.parseBool(value)) { local.keepTogether = $0 }
        case "MarkerStyle": return ok(XamlValues.parseMarkerStyle(value)) { local.markerStyle = $0 }
        case "StartIndex":
            return ok(XamlValues.parseInt(value).flatMap { $0 >= 1 ? $0 : nil }) { local.startIndex = $0 }
        case "MarkerOffset": return ok(XamlValues.parseLength(value, allowAuto: true)) { local.markerOffset = $0 }
        case "CellSpacing":
            return ok(XamlValues.parseLength(value, allowAuto: false).flatMap { $0 >= 0 ? $0 : nil }) {
                local.cellSpacing = $0
            }
        case "ColumnSpan":
            return ok(XamlValues.parseInt(value).flatMap { $0 >= 1 ? $0 : nil }) { local.columnSpan = $0 }
        case "RowSpan":
            return ok(XamlValues.parseInt(value).flatMap { $0 >= 1 ? $0 : nil }) { local.rowSpan = $0 }
        case "Width":
            guard let gl = XamlGridLength.parse(value) else { return .invalid }
            if case .pixel(let px) = gl { local.width = px } else if case .auto = gl { local.width = .nan }
            return .ok
        case "NavigateUri": local.navigateUri = value; return .ok
        case "TargetName": local.targetName = value; return .ok
        case "Text": return .ok
        default: return .ok
        }
    }

    /// True when a recognised attribute of `k` has a value the typed parser rejects (CONT-162: never re-emitted).
    static func isInvalid(_ a: XamlRawAttribute, on k: XamlNodeKind) -> Bool {
        guard a.namespaceURI == nil, recognises(a.qualifiedName, on: k) else { return false }
        var scratch = XamlLocalValues()
        return apply(a.qualifiedName, a.value, to: &scratch) != .ok
    }
}

/// TableColumn `Width` (GridLength): `Auto`, `*`, `n*`, `n` (px, with units).
enum XamlGridLength: Equatable {
    case auto, star(Double), pixel(Double)

    static func parse(_ text: String) -> XamlGridLength? {
        let t = NetText.trim(text)
        if NetText.equalsIgnoreCase(t, "Auto") { return .auto }
        if t.hasSuffix("*") {
            let n = String(t.dropLast())
            if n.isEmpty { return .star(1) }
            guard XamlValues.isPlainNumber(n), let v = Double(n), v >= 0 else { return nil }
            return .star(v)
        }
        guard let v = XamlValues.parseLength(t, allowAuto: false), v >= 0 else { return nil }
        return .pixel(v)
    }
}

/// Phase-2 builder: raw XML tree → XAML arena.
struct XamlDOMBuilder {
    private struct MNode {
        var kind: XamlNodeKind
        var qualifiedName: String
        var rawAttributes: [XamlRawAttribute] = []
        var namespaceDeclarations: [XamlRawAttribute] = []
        var local = XamlLocalValues()
        var propertyElements: [XamlPropertyElement] = []
        var text: String?
        var isImplicit = false
        var sourceRange: Range<Int>?
        var parent: Int?
        var children: [Int] = []
    }

    private let source: String
    private var unitsCache: [UInt16]?
    private let raw: XamlRawXMLTree
    private var nodes: [MNode] = []
    private var issues: [XamlIssue] = []

    private enum Child {
        case element(Int)            // raw element index
        case text(String, Range<Int>)
    }

    static func build(source: String, tree: XamlRawXMLTree) -> Result<XamlDocument, XamlFatalError> {
        var b = XamlDOMBuilder(source: source, raw: tree)
        return b.run()
    }

    private init(source: String, raw: XamlRawXMLTree) {
        self.source = source; self.raw = raw
    }

    private mutating func run() -> Result<XamlDocument, XamlFatalError> {
        let re = raw.elements[raw.root]
        guard re.namespaceURI == XamlXMLNamespaces.presentation else {
            return .failure(.wrongRootNamespace(re.namespaceURI))
        }
        let preserve = xmlSpacePreserve(re, inherited: false)
        let rootKind = classify(re)
        let rootRole: XamlRootRole
        var rootIndex = 0
        switch rootKind {
        case .some(.section), .some(.flowDocument):
            rootIndex = makeElement(raw.root, parent: nil)
            rootRole = .wrapper(rootKind!)
            processBlocks(rootIndex, content(of: raw.root, owner: rootIndex), preserve: preserve, contentRoot: false)
        case .some(.span):
            rootIndex = makeElement(raw.root, parent: nil)
            rootRole = .wrapper(.span)
            let p = addImplicit(.paragraph, parent: rootIndex)
            processInlines(p, content(of: raw.root, owner: rootIndex), preserve: preserve)
        default:
            rootIndex = addImplicit(.section, parent: nil)
            let k = rootKind ?? .unknown(re.qualifiedName)
            rootRole = .content(k)
            processBlocks(rootIndex, [.element(raw.root)], preserve: preserve, contentRoot: true)
        }
        let blocking = issues.filter {
            if case .unknownAttribute = $0 { return false }
            return true
        }
        let loadability: XamlLoadability
        if !blocking.isEmpty {
            loadability = .notLoadable(blocking)
        } else if case .content(let k) = rootRole {
            loadability = .unconfirmed("A \(XamlAttributeTable.name(k)) root is not a Section (XD-Q1).")
        } else if case .wrapper(.flowDocument) = rootRole {
            loadability = .unconfirmed("A FlowDocument root (XD-Q1).")
        } else {
            loadability = .loadable
        }
        let frozen = nodes.map { n in
            XamlNode(kind: n.kind, qualifiedName: n.qualifiedName, rawAttributes: n.rawAttributes,
                     namespaceDeclarations: n.namespaceDeclarations, local: n.local,
                     propertyElements: n.propertyElements, text: n.text, isImplicit: n.isImplicit,
                     sourceRange: n.sourceRange, parent: n.parent.map { XamlNodeID(index: Int32($0)) },
                     children: n.children.map { XamlNodeID(index: Int32($0)) })
        }
        return .success(XamlDocument(source: source, nodes: frozen, root: XamlNodeID(index: Int32(rootIndex)),
                                     rootRole: rootRole, loadability: loadability, issues: issues))
    }

    // MARK: - Helpers

    /// nil = a property element (`Owner.Prop`).
    private func classify(_ e: XamlRawXMLElement) -> XamlNodeKind? {
        if e.namespaceURI == XamlXMLNamespaces.presentation {
            if e.localName.utf8.contains(0x2E) { return nil }
            return XamlAttributeTable.kind(localName: e.localName) ?? .unknown(e.qualifiedName)
        }
        return .unknown(e.qualifiedName)
    }

    private func isPropertyElement(_ rawIndex: Int) -> Bool {
        let e = raw.elements[rawIndex]
        return e.namespaceURI == XamlXMLNamespaces.presentation && e.localName.utf8.contains(0x2E)
    }

    private func xmlSpacePreserve(_ e: XamlRawXMLElement, inherited: Bool) -> Bool {
        for a in e.attributes where a.namespaceURI == XamlXMLNamespaces.xml && a.localName == "space" {
            return a.value == "preserve"
        }
        return inherited
    }

    /// The verbatim source of a UTF-16 range (property elements; the code units are materialised on first use).
    private mutating func slice(_ r: Range<Int>) -> String {
        if unitsCache == nil { unitsCache = Array(source.utf16) }
        return String(decoding: unitsCache![r], as: UTF16.self)
    }

    private mutating func addImplicit(_ kind: XamlNodeKind, parent: Int?) -> Int {
        let idx = nodes.count
        nodes.append(MNode(kind: kind, qualifiedName: XamlAttributeTable.name(kind), isImplicit: true, parent: parent))
        if let p = parent { nodes[p].children.append(idx) }
        return idx
    }

    private mutating func addImplicitRun(_ text: String, range: Range<Int>?, parent: Int) {
        let idx = nodes.count
        nodes.append(MNode(kind: .run, qualifiedName: "Run", text: text, isImplicit: true, sourceRange: range,
                           parent: parent))
        nodes[parent].children.append(idx)
    }

    /// Creates the node for raw element `rawIndex` (attributes parsed), attached to `parent`.
    private mutating func makeElement(_ rawIndex: Int, parent: Int?, kindOverride: XamlNodeKind? = nil) -> Int {
        let e = raw.elements[rawIndex]
        let kind = kindOverride ?? classify(e) ?? .unknown(e.qualifiedName)
        var n = MNode(kind: kind, qualifiedName: e.qualifiedName, sourceRange: e.range, parent: parent)
        for a in e.attributes {
            let ra = XamlRawAttribute(qualifiedName: a.qualifiedName, namespaceURI: a.namespaceURI, value: a.value)
            if a.isNamespaceDeclaration { n.namespaceDeclarations.append(ra); continue }
            n.rawAttributes.append(ra)
            if case .unknown = kind { continue }
            if a.namespaceURI == XamlXMLNamespaces.xml {
                if a.localName == "lang" { n.local.language = NetText.toLowerInvariant(NetText.trim(a.value)) }
                continue
            }
            if a.namespaceURI == XamlXMLNamespaces.xaml { continue }
            if a.namespaceURI != nil { issues.append(.unknownAttribute(a.qualifiedName)); continue }
            let name = a.qualifiedName
            if name.hasPrefix("Typography.") { n.local.typography[name] = NetText.trim(a.value); continue }
            if name.hasPrefix("NumberSubstitution.") { n.local.numberSubstitution[name] = NetText.trim(a.value); continue }
            if name.utf8.contains(0x2E) { continue }                              // other attached properties
            if XamlAttributeTable.recognises(name, on: kind) {
                switch XamlAttributeTable.apply(name, a.value, to: &n.local) {
                case .ok: break
                case .invalid: issues.append(.invalidValue(property: name, value: a.value))
                case .markupExtension: issues.append(.markupExtension(name))
                }
            } else if !XamlAttributeTable.isKnownRawOnly(name, on: kind) {
                issues.append(.unknownAttribute(name))
            }
        }
        let idx = nodes.count
        nodes.append(n)
        if let p = parent { nodes[p].children.append(idx) }
        return idx
    }

    /// The content children of a raw element: transparent collection property elements are flattened, value
    /// property elements are parsed onto `owner` (CONT-151, CONT-154), `Table.Columns` becomes TableColumn nodes.
    private mutating func content(of rawIndex: Int, owner: Int) -> [Child] {
        var out: [Child] = []
        for c in raw.elements[rawIndex].children {
            switch c {
            case .text(let s, let r, _):
                out.append(.text(s, r))
            case .element(let ci):
                guard isPropertyElement(ci) else { out.append(.element(ci)); continue }
                let pe = raw.elements[ci]
                let parts = pe.localName.split(separator: ".", maxSplits: 1).map(String.init)
                let ownerName = parts[0], prop = parts.count > 1 ? parts[1] : ""
                switch prop {
                case "Inlines", "Blocks", "ListItems", "RowGroups", "Rows", "Cells":
                    out.append(contentsOf: content(of: ci, owner: owner))
                case "Columns" where nodes[owner].kind == .table:
                    nodes[owner].propertyElements.append(
                        XamlPropertyElement(ownerName: ownerName, propertyName: prop, rawXML: slice(pe.range), brush: nil))
                    for cc in pe.children {
                        guard case .element(let col) = cc else { continue }
                        if raw.elements[col].namespaceURI == XamlXMLNamespaces.presentation,
                           raw.elements[col].localName == "TableColumn" {
                            _ = makeElement(col, parent: owner)
                        } else {
                            issues.append(.invalidNesting("\(raw.elements[col].qualifiedName) in Table.Columns"))
                        }
                    }
                default:
                    parseValuePropertyElement(ci, ownerName: ownerName, property: prop, owner: owner)
                }
            }
        }
        return out
    }

    private mutating func parseValuePropertyElement(_ ci: Int, ownerName: String, property: String, owner: Int) {
        let pe = raw.elements[ci]
        let rawXML = slice(pe.range)
        var brush: XamlBrush?
        let kind = nodes[owner].kind
        let childElements: [Int] = pe.children.compactMap { if case .element(let x) = $0 { return x }; return nil }
        let textContent = pe.children.compactMap { c -> String? in if case .text(let s, _, _) = c { return s }; return nil }
            .joined()
        switch property {
        case "Foreground", "Background", "BorderBrush":
            if let first = childElements.first {
                let be = raw.elements[first]
                if be.localName == "SolidColorBrush", be.namespaceURI == XamlXMLNamespaces.presentation {
                    var color: UInt32?
                    var sc = false
                    var opacity = 1.0
                    var bad = false
                    for a in be.attributes where !a.isNamespaceDeclaration && a.namespaceURI == nil {
                        if a.qualifiedName == "Color" {
                            if let c = WpfColor.parse(a.value) {
                                color = XamlValues.argbValue(c)
                                sc = NetText.trim(a.value).lowercased().hasPrefix("sc#")
                            } else { bad = true }
                        } else if a.qualifiedName == "Opacity" {
                            if let o = XamlValues.parseLength(a.value, allowAuto: false) { opacity = o } else { bad = true }
                        }
                    }
                    if bad {
                        issues.append(.invalidValue(property: property, value: slice(be.range)))
                    } else {
                        brush = .solid(argb: color ?? 0xFF00_0000, opacity: opacity, isScRgb: sc)
                    }
                } else {
                    brush = .nonSolid(rawXML: slice(be.range))
                }
            } else if !NetText.isBlank(textContent) {
                if let b = XamlValues.parseBrush(textContent) { brush = b } else {
                    issues.append(.invalidValue(property: property, value: textContent))
                }
            }
            if let b = brush, XamlAttributeTable.recognises(property, on: kind) {
                var dup = false
                switch property {
                case "Foreground": dup = nodes[owner].local.foreground != nil; nodes[owner].local.foreground = b
                case "Background": dup = nodes[owner].local.background != nil; nodes[owner].local.background = b
                default: dup = nodes[owner].local.borderBrush != nil; nodes[owner].local.borderBrush = b
                }
                if dup || hasAttribute(owner, property) { issues.append(.duplicateProperty(property)) }
            }
        case "TextDecorations":
            var d: XamlDecorations = []
            var found = false
            func collect(_ idx: Int) {
                let e = raw.elements[idx]
                if e.localName == "TextDecoration" {
                    found = true
                    let loc = e.attributes.first { $0.qualifiedName == "Location" }?.value ?? "Underline"
                    if let one = XamlValues.parseDecorations(loc) { d.formUnion(one) }
                } else if e.localName == "TextDecorationCollection" {
                    found = true
                    for c in e.children { if case .element(let x) = c { collect(x) } }
                }
            }
            for x in childElements { collect(x) }
            if !found, !NetText.isBlank(textContent), let p = XamlValues.parseDecorations(textContent) {
                d = p; found = true
            }
            if found, XamlAttributeTable.recognises(property, on: kind) {
                if nodes[owner].local.textDecorations != nil || hasAttribute(owner, property) {
                    issues.append(.duplicateProperty(property))
                }
                nodes[owner].local.textDecorations = d
            }
        default:
            break
        }
        nodes[owner].propertyElements.append(
            XamlPropertyElement(ownerName: ownerName, propertyName: property, rawXML: rawXML, brush: brush))
    }

    private func hasAttribute(_ node: Int, _ name: String) -> Bool {
        nodes[node].rawAttributes.contains { $0.namespaceURI == nil && $0.qualifiedName == name }
    }

    private static func isXMLWhitespace(_ s: String) -> Bool {
        s.utf16.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
    }

    /// XAML default-space normalisation: collapse runs of whitespace to one space (§4.3.1).
    private static func collapse(_ s: String) -> String {
        var out: [UInt16] = []
        var inSpace = false
        for c in s.utf16 {
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                if !inSpace { out.append(0x20); inSpace = true }
            } else { out.append(c); inSpace = false }
        }
        return String(decoding: out, as: UTF16.self)
    }

    private func isLineBreak(_ c: Child?) -> Bool {
        guard case .element(let r)? = c else { return false }
        let e = raw.elements[r]
        return e.namespaceURI == XamlXMLNamespaces.presentation && e.localName == "LineBreak"
    }

    // MARK: - Content models

    private static let blockKinds: Set<String> = ["Section", "Paragraph", "List", "Table", "BlockUIContainer"]

    private mutating func processBlocks(_ owner: Int, _ children: [Child], preserve: Bool, contentRoot: Bool) {
        var pendingPara: Int?
        var pendingList: Int?
        for child in children {
            switch child {
            case .text(let s, let r):
                if Self.isXMLWhitespace(s) { continue }
                if !contentRoot { issues.append(.textInBlockContainer) }
                pendingList = nil
                let p = pendingPara ?? addImplicit(.paragraph, parent: owner)
                pendingPara = p
                let t = preserve ? s : NetText.trim(Self.collapse(s))
                if !t.isEmpty { addImplicitRun(t, range: r, parent: p) }
            case .element(let ri):
                let e = raw.elements[ri]
                let kind = classify(e) ?? .unknown(e.qualifiedName)
                let childPreserve = xmlSpacePreserve(e, inherited: preserve)
                switch kind {
                case .section, .paragraph, .list, .table, .blockUIContainer:
                    pendingPara = nil; pendingList = nil
                    addElement(ri, parent: owner, preserve: childPreserve)
                case .run, .span, .bold, .italic, .underline, .hyperlink, .lineBreak, .inlineUIContainer, .figure,
                     .floater:
                    if !contentRoot { issues.append(.invalidNesting("\(e.qualifiedName) in a block container")) }
                    pendingList = nil
                    let p = pendingPara ?? addImplicit(.paragraph, parent: owner)
                    pendingPara = p
                    addElement(ri, parent: p, preserve: childPreserve)
                case .listItem:
                    if !contentRoot { issues.append(.invalidNesting("ListItem outside a List")) }
                    pendingPara = nil
                    let l = pendingList ?? addImplicit(.list, parent: owner)
                    pendingList = l
                    addElement(ri, parent: l, preserve: childPreserve)
                case .unknown(let n):
                    issues.append(.unknownElement(n))
                    pendingPara = nil; pendingList = nil
                    _ = makeElement(ri, parent: owner)
                case .text:
                    break
                default:                                                     // misplaced structure → opaque
                    issues.append(.invalidNesting("\(e.qualifiedName) in a block container"))
                    pendingPara = nil; pendingList = nil
                    _ = makeElement(ri, parent: owner)
                }
            }
        }
    }

    private mutating func processInlines(_ owner: Int, _ children: [Child], preserve: Bool) {
        for (k, child) in children.enumerated() {
            switch child {
            case .text(let s, let r):
                var t = s
                if !preserve {
                    t = Self.collapse(s)
                    if k == 0 || isLineBreak(children[k - 1]) { t = String(t.drop(while: { $0 == " " })) }
                    if k == children.count - 1 || (k + 1 < children.count && isLineBreak(children[k + 1])) {
                        while t.hasSuffix(" ") { t.removeLast() }
                    }
                }
                if !t.isEmpty { addImplicitRun(t, range: r, parent: owner) }
            case .element(let ri):
                let e = raw.elements[ri]
                let kind = classify(e) ?? .unknown(e.qualifiedName)
                let childPreserve = xmlSpacePreserve(e, inherited: preserve)
                switch kind {
                case .run, .span, .bold, .italic, .underline, .hyperlink, .lineBreak, .inlineUIContainer, .figure,
                     .floater:
                    addElement(ri, parent: owner, preserve: childPreserve)
                case .unknown(let n):
                    issues.append(.unknownElement(n))
                    _ = makeElement(ri, parent: owner)
                default:
                    issues.append(.invalidNesting("\(e.qualifiedName) inside an inline"))
                    _ = makeElement(ri, parent: owner)
                }
            }
        }
    }

    /// Creates the node for an element and fills its content according to its kind.
    private mutating func addElement(_ ri: Int, parent: Int, preserve: Bool) {
        let idx = makeElement(ri, parent: parent)
        let kind = nodes[idx].kind
        switch kind {
        case .blockUIContainer, .inlineUIContainer, .unknown, .text:
            return                                                           // opaque: subtree kept raw
        default: break
        }
        let children = content(of: ri, owner: idx)
        switch kind {
        case .section, .listItem, .tableCell, .figure, .floater, .flowDocument:
            processBlocks(idx, children, preserve: preserve, contentRoot: false)
        case .paragraph, .span, .bold, .italic, .underline, .hyperlink:
            processInlines(idx, children, preserve: preserve)
        case .run:
            processRun(idx, ri, children, preserve: preserve)
        case .list:
            processList(idx, children, preserve: preserve)
        case .table:
            processTable(idx, children, preserve: preserve)
        case .tableRowGroup:
            processRowGroup(idx, children, preserve: preserve)
        case .tableRow:
            processRow(idx, children, preserve: preserve)
        case .lineBreak, .tableColumn:
            for c in children {
                if case .text(let s, _) = c, Self.isXMLWhitespace(s) { continue }
                issues.append(.invalidNesting("content inside \(nodes[idx].qualifiedName)"))
                break
            }
        default: break
        }
    }

    private mutating func processRun(_ idx: Int, _ ri: Int, _ children: [Child], preserve: Bool) {
        var text = ""
        var hasContent = false
        for c in children {
            switch c {
            case .text(let s, _):
                text += s
                hasContent = true
            case .element(let ci):
                issues.append(.invalidNesting("\(raw.elements[ci].qualifiedName) inside a Run"))
                _ = makeElement(ci, parent: idx)
            }
        }
        if !preserve { text = Self.collapse(text) }                       // §4.3.1: collapse (Run text keeps its ends)
        let attr = nodes[idx].rawAttributes.first { $0.namespaceURI == nil && $0.qualifiedName == "Text" }
        if hasContent, attr != nil, !(text.isEmpty) { issues.append(.runTextAndContent) }
        if hasContent && !text.isEmpty {
            nodes[idx].text = text
        } else if let a = attr {
            nodes[idx].text = a.value
        } else {
            nodes[idx].text = text
        }
    }

    private mutating func processList(_ idx: Int, _ children: [Child], preserve: Bool) {
        for c in children {
            switch c {
            case .text(let s, let r):
                if Self.isXMLWhitespace(s) { continue }
                issues.append(.textInBlockContainer)
                let li = addImplicit(.listItem, parent: idx)
                let p = addImplicit(.paragraph, parent: li)
                addImplicitRun(preserve ? s : NetText.trim(Self.collapse(s)), range: r, parent: p)
            case .element(let ri):
                let e = raw.elements[ri]
                if classify(e) == .listItem {
                    addElement(ri, parent: idx, preserve: xmlSpacePreserve(e, inherited: preserve))
                } else {
                    issues.append(.invalidNesting("\(e.qualifiedName) in a List"))
                    let li = addImplicit(.listItem, parent: idx)
                    processBlocks(li, [c], preserve: preserve, contentRoot: false)
                }
            }
        }
    }

    private mutating func processTable(_ idx: Int, _ children: [Child], preserve: Bool) {
        var pendingGroup: Int?
        for c in children {
            switch c {
            case .text(let s, _):
                if Self.isXMLWhitespace(s) { continue }
                issues.append(.textInBlockContainer)
            case .element(let ri):
                let e = raw.elements[ri]
                let kind = classify(e)
                if kind == .tableRowGroup {
                    pendingGroup = nil
                    addElement(ri, parent: idx, preserve: xmlSpacePreserve(e, inherited: preserve))
                } else if kind == .tableRow {
                    issues.append(.invalidNesting("TableRow directly in a Table"))
                    let g = pendingGroup ?? addImplicit(.tableRowGroup, parent: idx)
                    pendingGroup = g
                    addElement(ri, parent: g, preserve: xmlSpacePreserve(e, inherited: preserve))
                } else {
                    if case .unknown(let n)? = kind { issues.append(.unknownElement(n)) } else {
                        issues.append(.invalidNesting("\(e.qualifiedName) in a Table"))
                    }
                    pendingGroup = nil
                    _ = makeElement(ri, parent: idx)
                }
            }
        }
    }

    private mutating func processRowGroup(_ idx: Int, _ children: [Child], preserve: Bool) {
        var pendingRow: Int?
        for c in children {
            switch c {
            case .text(let s, _):
                if Self.isXMLWhitespace(s) { continue }
                issues.append(.textInBlockContainer)
            case .element(let ri):
                let e = raw.elements[ri]
                let kind = classify(e)
                if kind == .tableRow {
                    pendingRow = nil
                    addElement(ri, parent: idx, preserve: xmlSpacePreserve(e, inherited: preserve))
                } else if kind == .tableCell {
                    issues.append(.invalidNesting("TableCell directly in a TableRowGroup"))
                    let r = pendingRow ?? addImplicit(.tableRow, parent: idx)
                    pendingRow = r
                    addElement(ri, parent: r, preserve: xmlSpacePreserve(e, inherited: preserve))
                } else {
                    if case .unknown(let n)? = kind { issues.append(.unknownElement(n)) } else {
                        issues.append(.invalidNesting("\(e.qualifiedName) in a TableRowGroup"))
                    }
                    pendingRow = nil
                    _ = makeElement(ri, parent: idx)
                }
            }
        }
    }

    private mutating func processRow(_ idx: Int, _ children: [Child], preserve: Bool) {
        for c in children {
            switch c {
            case .text(let s, let r):
                if Self.isXMLWhitespace(s) { continue }
                issues.append(.textInBlockContainer)
                let cell = addImplicit(.tableCell, parent: idx)
                let p = addImplicit(.paragraph, parent: cell)
                addImplicitRun(preserve ? s : NetText.trim(Self.collapse(s)), range: r, parent: p)
            case .element(let ri):
                let e = raw.elements[ri]
                if classify(e) == .tableCell {
                    addElement(ri, parent: idx, preserve: xmlSpacePreserve(e, inherited: preserve))
                } else {
                    issues.append(.invalidNesting("\(e.qualifiedName) in a TableRow"))
                    let cell = addImplicit(.tableCell, parent: idx)
                    processBlocks(cell, [c], preserve: preserve, contentRoot: false)
                }
            }
        }
    }
}
