// Contract: ARCHITECTURE.md §6.7.
// Spec: 05 §6.1 + §XD.3 (in-memory attribute keys; never persisted as such) — the union of both lists. Raw values
// follow the XD.3 table ("aa.<name>"); value types as XD.3. Every value is a property-list type, so it survives
// undo snapshots and in-app copy/paste. W-RICH adds the `rich…` structural keys below (ARCH §12.2 prefix).
import AppKit

public extension NSAttributedString.Key {
    /// Derived from `.aaLockSource` (CONT-159).
    static let aaLocked = NSAttributedString.Key("aa.locked")
    /// String: `inlineRun`, `inlineAncestor`, `block`.
    static let aaLockSource = NSAttributedString.Key("aa.lockSource")
    /// String — the marker text (`•`, `3.`) on the TextKit 1 `\t{marker}\t` characters; never written as text.
    static let aaListMarker = NSAttributedString.Key("aa.listMarker")
    /// String — the innermost ListItem's element id, on every character of its paragraphs.
    static let aaListItemID = NSAttributedString.Key("aa.listItemID")
    /// Bool — true on a ListItem's paragraphs after its first block (no marker).
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
    /// `[String]` — element ids of the nested Sections around the paragraph, outermost first.
    static let aaSectionPath = NSAttributedString.Key("aa.sectionPath")
    /// String — the TableRowGroup element id of a table-cell paragraph.
    static let aaTableRowGroup = NSAttributedString.Key("aa.tableRowGroup")
    /// String — the verbatim XML of an opaque element, on its attachment character (§4.3.7 rule 10).
    static let aaPreservedXaml = NSAttributedString.Key("aa.preservedXaml")
    /// String — `"\n"`, `"\r\n"` or `"\r"` (CONT-166).
    static let aaInRunNewline = NSAttributedString.Key("aa.inRunNewline")
}

public extension NSAttributedString.Key {
    /// `[[String]]` — the block containers around a paragraph, outermost first; each entry is
    /// `[kind, id, name, namespace, value, …]` with modelled values under `@`-prefixed names (W-RICH structure).
    static let richContainerPath = NSAttributedString.Key("aa.rich.containerPath")
    /// `[String: String]` — the paragraph's modelled tokens (`Margin`, `TextIndent`, `Padding`, `BorderThickness`,
    /// `BorderBrush`, `Background`, `LineHeight`, `LineStackingStrategy`) and the computed display values (`c.…`).
    static let richParagraphModel = NSAttributedString.Key("aa.rich.paragraphModel")
    /// `[[String]]` (name, namespace, value) — the carried attributes of the Hyperlink around these characters.
    static let richHyperlinkAttributes = NSAttributedString.Key("aa.rich.hyperlinkAttributes")
    /// String `#AARRGGBB` — the colour shown when `.aaForegroundBrushXml` was read (writer consistency check).
    static let richForegroundBrushDisplay = NSAttributedString.Key("aa.rich.foregroundBrushDisplay")
    /// String `#AARRGGBB` or `none` — the highlight shown when `.aaBackgroundBrushXml` was read.
    static let richBackgroundBrushDisplay = NSAttributedString.Key("aa.rich.backgroundBrushDisplay")
}
