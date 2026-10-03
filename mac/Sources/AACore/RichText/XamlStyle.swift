// Contract: ARCHITECTURE.md §6.7 (05 §XD.4 XamlStyle.swift).
// Spec: 05 §XD.2.5 (default contexts, exact values), §XD.2.6 (computed-style algorithm: local → element style layer
//       → inherited → root context / consumer default), §XD.2.7 (rendered non-inherited functions), CONT-155…160.
import Foundation

public struct XamlContext: Sendable, Equatable {
    public var fontFamily: String
    public var fontSize: Double
    public var fontWeight: Int
    public var fontStyle: XamlFontStyle
    public var fontStretch: Int
    public var foreground: UInt32
    public var textAlignment: XamlTextAlignment
    /// NaN = Auto.
    public var lineHeight: Double
    public var lineStackingStrategy: XamlLineStacking
    public var flowDirection: XamlFlowDirection
    public var language: String
    public var isHyphenationEnabled: Bool
    /// Keys are the full attribute names (`Typography.Kerning`), values the tokens.
    public var typography: [String: String]
    /// Keys are the full attribute names (`NumberSubstitution.CultureSource`).
    public var numberSubstitution: [String: String]
    public var linkDisplayColor: UInt32

    public init(fontFamily: String, fontSize: Double, fontWeight: Int, fontStyle: XamlFontStyle, fontStretch: Int,
                foreground: UInt32, textAlignment: XamlTextAlignment, lineHeight: Double,
                lineStackingStrategy: XamlLineStacking, flowDirection: XamlFlowDirection, language: String,
                isHyphenationEnabled: Bool, typography: [String: String], numberSubstitution: [String: String],
                linkDisplayColor: UInt32) {
        self.fontFamily = fontFamily; self.fontSize = fontSize; self.fontWeight = fontWeight
        self.fontStyle = fontStyle; self.fontStretch = fontStretch; self.foreground = foreground
        self.textAlignment = textAlignment; self.lineHeight = lineHeight
        self.lineStackingStrategy = lineStackingStrategy; self.flowDirection = flowDirection
        self.language = language; self.isHyphenationEnabled = isHyphenationEnabled; self.typography = typography
        self.numberSubstitution = numberSubstitution; self.linkDisplayColor = linkDisplayColor
    }

    /// NaN-aware: two Auto (NaN) line heights are equal.
    public static func == (a: XamlContext, b: XamlContext) -> Bool {
        a.fontFamily == b.fontFamily && a.fontSize == b.fontSize && a.fontWeight == b.fontWeight
            && a.fontStyle == b.fontStyle && a.fontStretch == b.fontStretch && a.foreground == b.foreground
            && a.textAlignment == b.textAlignment
            && (a.lineHeight == b.lineHeight || (a.lineHeight.isNaN && b.lineHeight.isNaN))
            && a.lineStackingStrategy == b.lineStackingStrategy && a.flowDirection == b.flowDirection
            && a.language == b.language && a.isHyphenationEnabled == b.isHyphenationEnabled
            && a.typography == b.typography && a.numberSubstitution == b.numberSubstitution
            && a.linkDisplayColor == b.linkDisplayColor
    }

    /// The `Typography.*` values WPF writes on every saved root (S-1), in S-1 order.
    public static let s1Typography: [(String, String)] = {
        var t: [(String, String)] = [
            ("Typography.StandardLigatures", "True"), ("Typography.ContextualLigatures", "True"),
            ("Typography.DiscretionaryLigatures", "False"), ("Typography.HistoricalLigatures", "False"),
            ("Typography.AnnotationAlternates", "0"), ("Typography.ContextualAlternates", "True"),
            ("Typography.HistoricalForms", "False"), ("Typography.Kerning", "True"),
            ("Typography.CapitalSpacing", "False"), ("Typography.CaseSensitiveForms", "False"),
        ]
        for k in 1...20 { t.append(("Typography.StylisticSet\(k)", "False")) }
        t += [
            ("Typography.Fraction", "Normal"), ("Typography.SlashedZero", "False"),
            ("Typography.MathematicalGreek", "False"), ("Typography.EastAsianExpertForms", "False"),
            ("Typography.Variants", "Normal"), ("Typography.Capitals", "Normal"), ("Typography.NumeralStyle", "Normal"),
            ("Typography.NumeralAlignment", "Normal"), ("Typography.EastAsianWidths", "Normal"),
            ("Typography.EastAsianLanguage", "Normal"), ("Typography.StandardSwashes", "0"),
            ("Typography.ContextualSwashes", "0"), ("Typography.StylisticAlternates", "0"),
        ]
        return t
    }()

    /// `NumberSubstitution.*` of S-1, in S-1 order.
    public static let s1NumberSubstitution: [(String, String)] = [
        ("NumberSubstitution.CultureSource", "User"), ("NumberSubstitution.Substitution", "AsCulture"),
    ]

    private static func make(_ family: String, _ size: Double, _ fg: UInt32) -> XamlContext {
        XamlContext(fontFamily: family, fontSize: size, fontWeight: 400, fontStyle: .normal, fontStretch: 5,
                    foreground: fg, textAlignment: .left, lineHeight: .nan, lineStackingStrategy: .maxHeight,
                    flowDirection: .leftToRight, language: "en-us", isHyphenationEnabled: false,
                    typography: Dictionary(uniqueKeysWithValues: s1Typography),
                    numberSubstitution: Dictionary(uniqueKeysWithValues: s1NumberSubstitution),
                    linkDisplayColor: 0xFF00_66CC)
    }

    // XD.2.5 values.
    public static let containerEditor = make("Consolas", 14, 0xFF1A_1A1A)
    public static let containerViewer = containerEditor
    public static let pdf = make("Segoe UI", 12, 0xFF00_0000)
    public static let sirePane = make("Segoe UI", 13, 0xFF1A_1A1A)
}

/// XD.2.6 `Computed`.
public struct XamlComputedStyle: Sendable, Equatable {
    public var fontFamily: XamlFontFamily
    public var fontSize: Double
    public var fontWeight: Int
    public var fontStyle: XamlFontStyle
    public var fontStretch: Int
    public var foreground: XamlBrush
    public var textAlignment: XamlTextAlignment
    /// NaN = Auto.
    public var lineHeight: Double
    public var lineStackingStrategy: XamlLineStacking
    public var flowDirection: XamlFlowDirection
    public var language: String
    public var isHyphenationEnabled: Bool
    public var typography: [String: String]
    public var numberSubstitution: [String: String]
    /// Absent key = supplied by the context.
    public var setter: [XamlProperty: XamlNodeID]

    public init(fontFamily: XamlFontFamily, fontSize: Double, fontWeight: Int, fontStyle: XamlFontStyle,
                fontStretch: Int, foreground: XamlBrush, textAlignment: XamlTextAlignment, lineHeight: Double,
                lineStackingStrategy: XamlLineStacking, flowDirection: XamlFlowDirection, language: String,
                isHyphenationEnabled: Bool, typography: [String: String], numberSubstitution: [String: String],
                setter: [XamlProperty: XamlNodeID] = [:]) {
        self.fontFamily = fontFamily; self.fontSize = fontSize; self.fontWeight = fontWeight
        self.fontStyle = fontStyle; self.fontStretch = fontStretch; self.foreground = foreground
        self.textAlignment = textAlignment; self.lineHeight = lineHeight
        self.lineStackingStrategy = lineStackingStrategy; self.flowDirection = flowDirection
        self.language = language; self.isHyphenationEnabled = isHyphenationEnabled; self.typography = typography
        self.numberSubstitution = numberSubstitution; self.setter = setter
    }

    /// NaN-aware: two Auto (NaN) line heights are equal.
    public static func == (a: XamlComputedStyle, b: XamlComputedStyle) -> Bool {
        a.fontFamily == b.fontFamily && a.fontSize == b.fontSize && a.fontWeight == b.fontWeight
            && a.fontStyle == b.fontStyle && a.fontStretch == b.fontStretch && a.foreground == b.foreground
            && a.textAlignment == b.textAlignment
            && (a.lineHeight == b.lineHeight || (a.lineHeight.isNaN && b.lineHeight.isNaN))
            && a.lineStackingStrategy == b.lineStackingStrategy && a.flowDirection == b.flowDirection
            && a.language == b.language && a.isHyphenationEnabled == b.isHyphenationEnabled
            && a.typography == b.typography && a.numberSubstitution == b.numberSubstitution
            && a.setter == b.setter
    }

    /// The context as a computed style (every value "supplied by the context").
    public init(context c: XamlContext) {
        self.init(fontFamily: XamlFontFamily(raw: c.fontFamily), fontSize: c.fontSize, fontWeight: c.fontWeight,
                  fontStyle: c.fontStyle, fontStretch: c.fontStretch,
                  foreground: .solid(argb: c.foreground, opacity: 1, isScRgb: false), textAlignment: c.textAlignment,
                  lineHeight: c.lineHeight, lineStackingStrategy: c.lineStackingStrategy,
                  flowDirection: c.flowDirection, language: c.language, isHyphenationEnabled: c.isHyphenationEnabled,
                  typography: c.typography, numberSubstitution: c.numberSubstitution)
    }

    /// Step 1 (local) and step 2 (element style layer) of CONT-157 applied over an inherited style.
    func applying(_ local: XamlLocalValues, styleLayer kind: XamlNodeKind?, node: XamlNodeID) -> XamlComputedStyle {
        var s = self
        if let v = local.fontFamily { s.fontFamily = v; s.setter[.fontFamily] = node }
        if let v = local.fontSize { s.fontSize = v; s.setter[.fontSize] = node }
        if let v = local.fontWeight { s.fontWeight = v; s.setter[.fontWeight] = node }
        else if kind == .bold { s.fontWeight = 700; s.setter[.fontWeight] = node }
        if let v = local.fontStyle { s.fontStyle = v; s.setter[.fontStyle] = node }
        else if kind == .italic { s.fontStyle = .italic; s.setter[.fontStyle] = node }
        if let v = local.fontStretch { s.fontStretch = v; s.setter[.fontStretch] = node }
        if let v = local.foreground { s.foreground = v; s.setter[.foreground] = node }
        else if kind == .hyperlink { s.foreground = .linkDefault; s.setter[.foreground] = node }
        if let v = local.textAlignment { s.textAlignment = v; s.setter[.textAlignment] = node }
        if let v = local.lineHeight { s.lineHeight = v; s.setter[.lineHeight] = node }
        if let v = local.lineStackingStrategy { s.lineStackingStrategy = v; s.setter[.lineStackingStrategy] = node }
        if let v = local.flowDirection { s.flowDirection = v; s.setter[.flowDirection] = node }
        if let v = local.language { s.language = v; s.setter[.language] = node }
        if let v = local.isHyphenationEnabled { s.isHyphenationEnabled = v; s.setter[.isHyphenationEnabled] = node }
        if !local.typography.isEmpty {
            s.typography.merge(local.typography) { _, new in new }
            s.setter[.typography] = node
        }
        if !local.numberSubstitution.isEmpty {
            s.numberSubstitution.merge(local.numberSubstitution) { _, new in new }
            s.setter[.numberSubstitution] = node
        }
        return s
    }
}

public struct XamlStyleResolver: Sendable {
    public let document: XamlDocument
    public let context: XamlContext
    private let styles: [XamlComputedStyle]

    /// O(n) pre-order pass (XD.2.6, XD.5).
    public init(_ doc: XamlDocument, context: XamlContext) {
        self.document = doc
        self.context = context
        var styles: [XamlComputedStyle] = []
        styles.reserveCapacity(doc.nodes.count)
        let base = XamlComputedStyle(context: context)
        let root = Int(doc.root.index)
        for (i, n) in doc.nodes.enumerated() {
            let id = XamlNodeID(index: Int32(i))
            if i == root {
                if case .wrapper? = doc.rootRole, !n.isImplicit {
                    styles.append(base.applying(n.local, styleLayer: nil, node: id))
                } else {
                    styles.append(base)
                }
                continue
            }
            guard let p = n.parent, Int(p.index) < styles.count else {
                styles.append(base)
                continue
            }
            let inherited = styles[Int(p.index)]
            switch n.kind {
            case .tableColumn, .unknown, .text:
                styles.append(inherited)                                // never a content ancestor (CONT-152)
            default:
                styles.append(inherited.applying(n.local, styleLayer: n.kind, node: id))
            }
        }
        self.styles = styles
    }

    /// O(1).
    public func computed(_ id: XamlNodeID) -> XamlComputedStyle {
        let i = Int(id.index)
        return styles.indices.contains(i) ? styles[i] : XamlComputedStyle(context: context)
    }

    private var rootIndex: Int32 { document.root.index }

    /// XD.2.7 `modelDecorations`.
    public func modelDecorations(_ run: XamlNodeID) -> XamlDecorations {
        var d = document[run].local.textDecorations ?? []
        for a in document.inlineAncestors(of: run) {
            let n = document[a]
            d.formUnion(n.local.textDecorations ?? (n.kind == .underline ? [.underline] : []))
        }
        if let p = paragraph(of: run) { d.formUnion(document[p].local.textDecorations ?? []) }
        return d
    }

    /// XD.2.7 `displayDecorations` (adds the Hyperlink style underline, display only).
    public func displayDecorations(_ run: XamlNodeID) -> XamlDecorations {
        var d = modelDecorations(run)
        for a in [run] + document.inlineAncestors(of: run) where document[a].kind == .hyperlink {
            if document[a].local.textDecorations == nil { d.insert(.underline) }
            break
        }
        return d
    }

    /// XD.2.7 `inlineBackground` (editor model → `.backgroundColor`); stops before the Paragraph.
    public func inlineBackground(_ run: XamlNodeID) -> XamlBrush? {
        for a in [run] + document.inlineAncestors(of: run) {
            switch document[a].local.background {
            case .solid(let argb, let op, _)? where Double(argb >> 24) * op > 0: return document[a].local.background
            case .nonSolid?: return document[a].local.background
            default: continue
            }
        }
        return nil
    }

    /// XD.2.7 `blockFill`: the block's own Background; the root wrapper never has one.
    public func blockFill(_ block: XamlNodeID) -> XamlBrush? {
        guard block.index != rootIndex else { return nil }
        switch document[block].kind {
        case .paragraph, .listItem, .list, .section, .table, .tableRowGroup, .tableRow, .tableCell:
            return document[block].local.background
        default: return nil
        }
    }

    /// XD.2.7 / 11 §3.5.6 `EffectiveBackground`: first non-null brush from the Run up to and including the Paragraph.
    public func pdfEffectiveBackground(_ run: XamlNodeID) -> XamlBrush? {
        for a in [run] + document.ancestors(of: run) {
            if a.index == rootIndex { break }
            if let b = document[a].local.background { return b }
            if document[a].kind == .paragraph { break }
        }
        return nil
    }

    /// XD.2.7 / CONT-159 lock resolution.
    public func lockSource(_ run: XamlNodeID) -> XamlLockSource? {
        if XamlValues.isSentinel(document[run].local.background) { return .inlineRun }
        let inl = document.inlineAncestors(of: run)
        for a in inl where XamlValues.isSentinel(document[a].local.background) {
            return XamlValues.isSentinel(inlineBackground(run)) ? .inlineRun : .inlineAncestor
        }
        var cur = (inl.last ?? run)
        while let p = document[cur].parent, p.index != rootIndex {
            switch document[p].kind {
            case .paragraph, .listItem, .list, .tableCell, .tableRow, .tableRowGroup, .table, .section, .figure, .floater:
                if XamlValues.isSentinel(document[p].local.background) { return .block }
            default: break
            }
            cur = p
        }
        return nil
    }

    /// XD.2.7 `isLinkStyled`: inside a Hyperlink H and nothing in [run … H] sets Foreground locally.
    public func isLinkStyled(_ run: XamlNodeID) -> Bool {
        var cur: XamlNodeID? = run
        while let c = cur {
            let n = document[c]
            if n.local.foreground != nil { return false }
            if n.kind == .hyperlink { return true }
            switch n.kind {
            case .paragraph, .section, .flowDocument, .listItem, .tableCell: return false
            default: cur = n.parent
            }
        }
        return false
    }

    /// XD.2.7 `baselineShift`: +1 superscript, −1 subscript, 0 otherwise.
    public func baselineShift(_ run: XamlNodeID) -> Int {
        for a in [run] + document.inlineAncestors(of: run) {
            if let b = document[a].local.baselineAlignment, b != .baseline {
                switch b {
                case .superscript: return 1
                case .subscript: return -1
                default: return 0
                }
            }
        }
        switch computed(run).typography["Typography.Variants"].map({ $0.lowercased() }) {
        case "superscript"?: return 1
        case "subscript"?: return -1
        default: return 0
        }
    }

    /// The raw BaselineAlignment token that decided `baselineShift`, if any.
    func baselineToken(_ run: XamlNodeID) -> String? {
        for a in [run] + document.inlineAncestors(of: run) {
            if let b = document[a].local.baselineAlignment, b != .baseline {
                return document[a].rawAttributes.first { $0.qualifiedName == "BaselineAlignment" }
                    .map { NetText.trim($0.value) } ?? b.rawValue
            }
        }
        return nil
    }

    func paragraph(of id: XamlNodeID) -> XamlNodeID? {
        var cur = document[id].parent
        while let p = cur {
            if document[p].kind == .paragraph { return p }
            switch document[p].kind {
            case .span, .bold, .italic, .underline, .hyperlink, .run: cur = document[p].parent
            default: return nil
            }
        }
        return nil
    }
}
