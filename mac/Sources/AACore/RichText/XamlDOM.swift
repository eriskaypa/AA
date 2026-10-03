// Contract: ARCHITECTURE.md §6.7 (05 Addendum §XD.4 as completed and amended there).
// Spec: 05 §XD.2.1 (parse pipeline), §XD.2.2 (value parsers), §XD.2.3 (inheritable properties), §XD.2.12
// (loadability), §XD.4, CONT-151…155 (node kinds, parent links, raw + parsed attributes, property elements, roots).
// The arena is an immutable value (XD.5): nodes in pre-order (a parent always precedes its children), integer
// parent links, `Sendable`, so the PDF exporter can parse and resolve off the main actor.
import Foundation

public enum XamlNodeKind: Sendable, Hashable {
    case section, flowDocument, paragraph, list, listItem, table, tableColumn, tableRowGroup, tableRow, tableCell,
         blockUIContainer, figure, floater, run, span, bold, italic, underline, hyperlink, lineBreak,
         inlineUIContainer, text, unknown(String)
}

public struct XamlNodeID: Hashable, Sendable {
    public let index: Int32
    public init(index: Int32) { self.index = index }
}

public struct XamlRawAttribute: Hashable, Sendable {
    public let qualifiedName: String
    public let namespaceURI: String?
    public let value: String

    public init(qualifiedName: String, namespaceURI: String?, value: String) {
        self.qualifiedName = qualifiedName; self.namespaceURI = namespaceURI; self.value = value
    }
}

public enum XamlBrush: Hashable, Sendable {
    case solid(argb: UInt32, opacity: Double, isScRgb: Bool)
    case nonSolid(rawXML: String)
    case null                    // {x:Null}
    case linkDefault             // Hyperlink style layer (symbolic)
}

/// "No root yet" (XD.2.11 `.none`, a new document) is `rootRole: XamlRootRole?` == nil wherever a role is stored.
public enum XamlRootRole: Sendable, Hashable { case wrapper(XamlNodeKind), content(XamlNodeKind) }

public enum XamlFontStyle: String, Sendable, Hashable, CaseIterable { case normal = "Normal", italic = "Italic", oblique = "Oblique" }

public enum XamlTextAlignment: String, Sendable, Hashable, CaseIterable {
    case left = "Left", right = "Right", center = "Center", justify = "Justify"
}

public enum XamlLineStacking: String, Sendable, Hashable, CaseIterable { case maxHeight = "MaxHeight", blockLineHeight = "BlockLineHeight" }

public enum XamlFlowDirection: String, Sendable, Hashable, CaseIterable { case leftToRight = "LeftToRight", rightToLeft = "RightToLeft" }

public enum XamlBaselineAlignment: String, Sendable, Hashable, CaseIterable {
    case top = "Top", center = "Center", bottom = "Bottom", baseline = "Baseline", textTop = "TextTop",
         textBottom = "TextBottom", `subscript` = "Subscript", superscript = "Superscript"
}

/// Written in this fixed order (XD.2.2).
public struct XamlDecorations: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let underline = XamlDecorations(rawValue: 1 << 0)
    public static let strikethrough = XamlDecorations(rawValue: 1 << 1)
    public static let overLine = XamlDecorations(rawValue: 1 << 2)
    public static let baseline = XamlDecorations(rawValue: 1 << 3)
}

/// CONT-159.
public enum XamlLockSource: String, Sendable, Hashable { case inlineRun, inlineAncestor, block }

public struct XamlFontFamily: Sendable, Hashable {
    /// Token as written (the writer's canonical token).
    public let raw: String
    /// Split on ",", trimmed, empties dropped, invariant lower-case, joined ",".
    public let canon: String

    public init(raw: String) {
        self.raw = raw
        self.canon = raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { NetText.toLowerInvariant(NetText.trim(String($0))) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
    }
}

/// Pixels.
public struct XamlThickness: Sendable, Hashable {
    public var left, top, right, bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
}

/// Inheritable properties (XD.2.3 rows 1–14).
public enum XamlProperty: String, Sendable, Hashable, CaseIterable {
    case fontFamily, fontSize, fontWeight, fontStyle, fontStretch, foreground, textAlignment, lineHeight,
         lineStackingStrategy, flowDirection, language, isHyphenationEnabled, typography, numberSubstitution
}

/// Typed local values of one element (XD.2.2 parsers); nil = not set locally. Invalid values are not stored here —
/// they produce an `.invalidValue` issue and stay in `rawAttributes`.
public struct XamlLocalValues: Sendable, Hashable {
    public var fontFamily: XamlFontFamily?
    public var fontSize: Double?
    public var fontWeight: Int?
    public var fontWeightToken: String?
    public var fontStyle: XamlFontStyle?
    public var fontStyleToken: String?
    public var fontStretch: Int?
    public var foreground: XamlBrush?
    public var textAlignment: XamlTextAlignment?
    /// NaN = Auto.
    public var lineHeight: Double?
    public var lineStackingStrategy: XamlLineStacking?
    public var flowDirection: XamlFlowDirection?
    public var language: String?
    public var isHyphenationEnabled: Bool?
    public var typography: [String: String]
    public var numberSubstitution: [String: String]
    public var background: XamlBrush?
    public var textDecorations: XamlDecorations?
    public var baselineAlignment: XamlBaselineAlignment?
    public var margin: XamlThickness?
    public var padding: XamlThickness?
    public var borderThickness: XamlThickness?
    public var borderBrush: XamlBrush?
    public var textIndent: Double?
    public var keepTogether: Bool?
    public var markerStyle: String?
    public var startIndex: Int?
    public var markerOffset: Double?
    public var cellSpacing: Double?
    public var columnSpan: Int?
    public var rowSpan: Int?
    /// TableColumn (NaN = Auto).
    public var width: Double?
    public var navigateUri: String?
    public var targetName: String?

    public init() {
        typography = [:]
        numberSubstitution = [:]
    }
}

/// CONT-154 "Owner.Prop" child element.
public struct XamlPropertyElement: Sendable, Hashable {
    public let ownerName: String
    public let propertyName: String
    /// Verbatim source, preserved when unchanged.
    public let rawXML: String
    /// Parsed when it is a brush property.
    public let brush: XamlBrush?

    public init(ownerName: String, propertyName: String, rawXML: String, brush: XamlBrush?) {
        self.ownerName = ownerName; self.propertyName = propertyName; self.rawXML = rawXML; self.brush = brush
    }
}

/// XD.2.1 steps 5–7, XD.2.12.
public enum XamlIssue: Sendable, Hashable {
    case unknownElement(String), invalidNesting(String), textInBlockContainer,
         invalidValue(property: String, value: String), duplicateProperty(String), runTextAndContent,
         markupExtension(String), unknownAttribute(String)
}

public enum XamlFatalError: Error, Sendable, Hashable {
    case malformedXML(String), dtdPresent, wrongRootNamespace(String?)
}

public enum XamlLoadability: Sendable, Hashable { case loadable, notLoadable([XamlIssue]), unconfirmed(String) }

public struct XamlNode: Sendable, Hashable {
    public let kind: XamlNodeKind
    public let qualifiedName: String
    public let rawAttributes: [XamlRawAttribute]
    public let namespaceDeclarations: [XamlRawAttribute]
    /// Typed, with tokens.
    public let local: XamlLocalValues
    public let propertyElements: [XamlPropertyElement]
    /// `.text` nodes / Run text.
    public let text: String?
    public let isImplicit: Bool
    /// UTF-16 offsets into `XamlDocument.source`.
    public let sourceRange: Range<Int>?
    public let parent: XamlNodeID?
    public let children: [XamlNodeID]

    public init(kind: XamlNodeKind, qualifiedName: String, rawAttributes: [XamlRawAttribute] = [],
                namespaceDeclarations: [XamlRawAttribute] = [], local: XamlLocalValues = XamlLocalValues(),
                propertyElements: [XamlPropertyElement] = [], text: String? = nil, isImplicit: Bool = false,
                sourceRange: Range<Int>? = nil, parent: XamlNodeID? = nil, children: [XamlNodeID] = []) {
        self.kind = kind; self.qualifiedName = qualifiedName; self.rawAttributes = rawAttributes
        self.namespaceDeclarations = namespaceDeclarations; self.local = local
        self.propertyElements = propertyElements; self.text = text; self.isImplicit = isImplicit
        self.sourceRange = sourceRange; self.parent = parent; self.children = children
    }
}

/// Immutable arena of nodes with integer parent links (XD.5).
public struct XamlDocument: Sendable, Hashable {
    public let source: String
    public let nodes: [XamlNode]
    /// Wrapper (possibly implicit).
    public let root: XamlNodeID
    public let rootRole: XamlRootRole?
    public let loadability: XamlLoadability
    public let issues: [XamlIssue]

    public init(source: String, nodes: [XamlNode], root: XamlNodeID, rootRole: XamlRootRole?,
                loadability: XamlLoadability, issues: [XamlIssue]) {
        self.source = source; self.nodes = nodes; self.root = root; self.rootRole = rootRole
        self.loadability = loadability; self.issues = issues
    }

    public subscript(_ id: XamlNodeID) -> XamlNode {
        let i = Int(id.index)
        return nodes.indices.contains(i) ? nodes[i] : XamlNode(kind: .unknown(""), qualifiedName: "")
    }

    /// Nearest first, root last (CONT-152).
    public func ancestors(of id: XamlNodeID) -> [XamlNodeID] {
        var out: [XamlNodeID] = []
        var cur = self[id].parent
        while let p = cur {
            out.append(p)
            cur = self[p].parent
        }
        return out
    }

    /// The inline containers (Span, Bold, Italic, Underline, Hyperlink) between a Run and its Paragraph, nearest
    /// first (CONT-152).
    public func inlineAncestors(of run: XamlNodeID) -> [XamlNodeID] {
        var out: [XamlNodeID] = []
        var cur = self[run].parent
        while let p = cur {
            switch self[p].kind {
            case .span, .bold, .italic, .underline, .hyperlink: out.append(p)
            default: return out
            }
            cur = self[p].parent
        }
        return out
    }

    public func parent(of id: XamlNodeID) -> XamlNodeID? { self[id].parent }
    public func children(of id: XamlNodeID) -> [XamlNodeID] { self[id].children }

    /// Nearest ancestor-or-self of `kind`.
    public func nearest(_ kind: XamlNodeKind, from id: XamlNodeID) -> XamlNodeID? {
        var cur: XamlNodeID? = id
        while let c = cur {
            if self[c].kind == kind { return c }
            cur = self[c].parent
        }
        return nil
    }

    public func enclosingParagraph(of id: XamlNodeID) -> XamlNodeID? { nearest(.paragraph, from: id) }

    /// Nearest Hyperlink ancestor-or-self, never crossing the enclosing Paragraph.
    public func enclosingHyperlink(of id: XamlNodeID) -> XamlNodeID? {
        var cur: XamlNodeID? = id
        while let c = cur {
            switch self[c].kind {
            case .hyperlink: return c
            case .paragraph, .section, .flowDocument, .listItem, .tableCell: return nil
            default: cur = self[c].parent
            }
        }
        return nil
    }

    /// The UTF-16 slice of `source` covered by a node (opaque preservation, §4.3.7 rule 10).
    public func sourceText(of id: XamlNodeID) -> String? {
        guard let r = self[id].sourceRange else { return nil }
        let u = source.utf16
        guard r.lowerBound >= 0, r.upperBound <= u.count else { return nil }
        let a = u.index(u.startIndex, offsetBy: r.lowerBound), b = u.index(u.startIndex, offsetBy: r.upperBound)
        return String(u[a..<b])
    }

    /// Every node id in arena (pre-) order.
    public var allNodeIDs: [XamlNodeID] { (0..<nodes.count).map { XamlNodeID(index: Int32($0)) } }
}

public enum XamlDOM {
    /// CONT-151…155, XD.2.1. Fatal problems (malformed XML, a DTD, a root outside the presentation namespace) are a
    /// failure; everything else is tolerated and reported through `issues` and `loadability` (XD.2.12).
    public static func parse(_ xaml: String) -> Result<XamlDocument, XamlFatalError> {
        switch XamlXMLScanner.scan(xaml) {
        case .failure(let f): return .failure(f)
        case .success(let tree): return XamlDOMBuilder.build(source: xaml, tree: tree)
        }
    }
}
