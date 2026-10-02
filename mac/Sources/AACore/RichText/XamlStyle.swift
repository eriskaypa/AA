// PLACEHOLDER(W-RICH) — contract: ARCHITECTURE.md §6.7 (05 §XD.4 XamlStyle.swift)
// Spec: 05 §XD.2.5 (default contexts), §XD.2.6 (computed style), §XD.2.7 (rendered functions). Compiling stub
// created by F1; W-RICH replaces this file in place. The stub resolver returns the context values for every node
// and no decorations / backgrounds / locks (ARCH §11).
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
    public var typography: [String: String]
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

    // XD.2.5 values. Typography.* / NumberSubstitution.* carry the S-1 root values in the real implementation;
    // PLACEHOLDER(W-RICH): the stub leaves both maps empty rather than guess their key form.
    public static let containerEditor = XamlContext(
        fontFamily: "Consolas", fontSize: 14, fontWeight: 400, fontStyle: .normal, fontStretch: 5,
        foreground: 0xFF1A_1A1A, textAlignment: .left, lineHeight: .nan, lineStackingStrategy: .maxHeight,
        flowDirection: .leftToRight, language: "en-us", isHyphenationEnabled: false, typography: [:],
        numberSubstitution: [:], linkDisplayColor: 0xFF00_66CC)
    public static let containerViewer = containerEditor
    public static let pdf = XamlContext(
        fontFamily: "Segoe UI", fontSize: 12, fontWeight: 400, fontStyle: .normal, fontStretch: 5,
        foreground: 0xFF00_0000, textAlignment: .left, lineHeight: .nan, lineStackingStrategy: .maxHeight,
        flowDirection: .leftToRight, language: "en-us", isHyphenationEnabled: false, typography: [:],
        numberSubstitution: [:], linkDisplayColor: 0xFF00_66CC)
    public static let sirePane = XamlContext(
        fontFamily: "Segoe UI", fontSize: 13, fontWeight: 400, fontStyle: .normal, fontStretch: 5,
        foreground: 0xFF1A_1A1A, textAlignment: .left, lineHeight: .nan, lineStackingStrategy: .maxHeight,
        flowDirection: .leftToRight, language: "en-us", isHyphenationEnabled: false, typography: [:],
        numberSubstitution: [:], linkDisplayColor: 0xFF00_66CC)
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
}

public struct XamlStyleResolver: Sendable {
    private let context: XamlContext

    /// O(n) pre-order pass.
    public init(_ doc: XamlDocument, context: XamlContext) {
        // PLACEHOLDER(W-RICH)
        self.context = context
    }

    /// O(1).
    public func computed(_ id: XamlNodeID) -> XamlComputedStyle {
        // PLACEHOLDER(W-RICH)
        XamlComputedStyle(
            fontFamily: XamlFontFamily(raw: context.fontFamily), fontSize: context.fontSize,
            fontWeight: context.fontWeight, fontStyle: context.fontStyle, fontStretch: context.fontStretch,
            foreground: .solid(argb: context.foreground, opacity: 1, isScRgb: false),
            textAlignment: context.textAlignment, lineHeight: context.lineHeight,
            lineStackingStrategy: context.lineStackingStrategy, flowDirection: context.flowDirection,
            language: context.language, isHyphenationEnabled: context.isHyphenationEnabled,
            typography: context.typography, numberSubstitution: context.numberSubstitution)
    }

    public func modelDecorations(_ run: XamlNodeID) -> XamlDecorations {
        // PLACEHOLDER(W-RICH)
        []
    }

    public func displayDecorations(_ run: XamlNodeID) -> XamlDecorations {
        // PLACEHOLDER(W-RICH)
        []
    }

    public func inlineBackground(_ run: XamlNodeID) -> XamlBrush? {
        // PLACEHOLDER(W-RICH)
        nil
    }

    public func blockFill(_ block: XamlNodeID) -> XamlBrush? {
        // PLACEHOLDER(W-RICH)
        nil
    }

    public func pdfEffectiveBackground(_ run: XamlNodeID) -> XamlBrush? {
        // PLACEHOLDER(W-RICH)
        nil
    }

    public func lockSource(_ run: XamlNodeID) -> XamlLockSource? {
        // PLACEHOLDER(W-RICH)
        nil
    }

    public func isLinkStyled(_ run: XamlNodeID) -> Bool {
        // PLACEHOLDER(W-RICH)
        false
    }

    public func baselineShift(_ run: XamlNodeID) -> Int {
        // PLACEHOLDER(W-RICH)
        0
    }
}
