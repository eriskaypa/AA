// PLACEHOLDER(W-RICH) — contract: ARCHITECTURE.md §6.7
// Spec: 05 §6.1 + §XD.3 (in-memory attribute keys; never persisted as such) — the union of both lists. Raw values
// follow the XD.3 table ("aa.<name>"); value types as XD.3. Created by F1; W-RICH owns and may extend this file.
import AppKit

public extension NSAttributedString.Key {
    /// Derived from `.aaLockSource` (CONT-159).
    static let aaLocked = NSAttributedString.Key("aa.locked")
    /// String: `inlineRun`, `inlineAncestor`, `block`.
    static let aaLockSource = NSAttributedString.Key("aa.lockSource")
    static let aaListMarker = NSAttributedString.Key("aa.listMarker")
    static let aaListItemID = NSAttributedString.Key("aa.listItemID")
    static let aaListContinuation = NSAttributedString.Key("aa.listContinuation")
    /// String (element id) — link wrapper identity.
    static let aaHyperlink = NSAttributedString.Key("aa.hyperlink")
    /// String — lower-case language tag.
    static let aaXmlLang = NSAttributedString.Key("aa.xmlLang")
    /// String — WPF family token (12 §6.5 `.xamlFontFamily` is the same key).
    static let aaFontFamilyName = NSAttributedString.Key("aa.fontFamilyName")
    static let aaFontWeightToken = NSAttributedString.Key("aa.fontWeightToken")
    static let aaFontStyleToken = NSAttributedString.Key("aa.fontStyleToken")
    /// `[String: String]` — FontStretch, Typography.*, NumberSubstitution.* that differ from the root.
    static let aaInheritedExtras = NSAttributedString.Key("aa.inheritedExtras")
    /// Bool (CONT-167).
    static let aaLinkStyled = NSAttributedString.Key("aa.linkStyled")
    /// NSColor (sRGB) — the colour when not a link.
    static let aaUnderlyingForeground = NSAttributedString.Key("aa.underlyingForeground")
    static let aaForegroundBrushXml = NSAttributedString.Key("aa.foregroundBrushXml")
    static let aaBackgroundBrushXml = NSAttributedString.Key("aa.backgroundBrushXml")
    /// `[String]` — `OverLine`, `Baseline`.
    static let aaExtraDecorations = NSAttributedString.Key("aa.extraDecorations")
    /// String — raw `BaselineAlignment` token.
    static let aaBaselineAlignment = NSAttributedString.Key("aa.baselineAlignment")
    /// `[[String]]` (name, namespace, value) — carried Paragraph attributes.
    static let aaParagraphAttrs = NSAttributedString.Key("aa.paragraphAttrs")
    /// `[[String]]` — unrecognised Run attributes.
    static let aaExtraAttributes = NSAttributedString.Key("aa.extraAttributes")
    static let aaSectionPath = NSAttributedString.Key("aa.sectionPath")
    static let aaTableRowGroup = NSAttributedString.Key("aa.tableRowGroup")
    static let aaPreservedXaml = NSAttributedString.Key("aa.preservedXaml")
    /// String — `"\n"`, `"\r\n"` or `"\r"` (CONT-166).
    static let aaInRunNewline = NSAttributedString.Key("aa.inRunNewline")
}
