// Spec: 11 §3.3 (DefineStyles, PdfExporter.cs L243-298), §3.2 rules 2–3 (Header/Footer styles, MigraDoc Normal
//       defaults), PDF-081 (ChecklistExporter's Normal: Calibri 11, no SpaceAfter, single spacing).
import Foundation

public enum PdfStyleName: String, Sendable, Hashable, CaseIterable {
    case normal = "Normal", title = "Title", subtitle = "Subtitle", h1 = "H1", h2 = "H2", h3 = "H3",
         bodyItalic = "BodyItalic", bullet = "Bullet", muted = "Muted", header = "Header", footer = "Footer"
}

/// The fully resolved values of one style (MigraDoc styles inherit from Normal; the sheet stores them flattened).
public struct PdfStyle: Sendable, Hashable {
    /// The requested font family (resolved by `PdfFontResolver`).
    public var fontFamily: String
    public var size: Double
    public var bold: Bool
    public var italic: Bool
    public var color: PdfColor
    public var spaceBefore: Double            // pt
    public var spaceAfter: Double             // pt
    /// `LineSpacingRule.Multiple` factor (1.0 = single).
    public var lineSpacing: Double
    public var leftIndent: Double             // cm
    public var firstLineIndent: Double        // cm
    public var rightIndent: Double            // cm
    public var keepWithNext: Bool
    public var widowControl: Bool
    public var alignment: PdfAlignment
    public var bottomBorder: PdfBorder?
    /// MigraDoc default tab stops every 1.25 cm (none for Header/Footer, §3.2 rule 2).
    public var defaultTabStopsCm: Double?

    public init(fontFamily: String, size: Double, bold: Bool = false, italic: Bool = false,
                color: PdfColor = .black, spaceBefore: Double = 0, spaceAfter: Double = 0, lineSpacing: Double = 1,
                leftIndent: Double = 0, firstLineIndent: Double = 0, rightIndent: Double = 0,
                keepWithNext: Bool = false, widowControl: Bool = true, alignment: PdfAlignment = .left,
                bottomBorder: PdfBorder? = nil, defaultTabStopsCm: Double? = 1.25) {
        self.fontFamily = fontFamily; self.size = size; self.bold = bold; self.italic = italic; self.color = color
        self.spaceBefore = spaceBefore; self.spaceAfter = spaceAfter; self.lineSpacing = lineSpacing
        self.leftIndent = leftIndent; self.firstLineIndent = firstLineIndent; self.rightIndent = rightIndent
        self.keepWithNext = keepWithNext; self.widowControl = widowControl; self.alignment = alignment
        self.bottomBorder = bottomBorder; self.defaultTabStopsCm = defaultTabStopsCm
    }

    public var charFormat: PdfCharFormat {
        PdfCharFormat(fontFamily: fontFamily, size: size, bold: bold, italic: italic, underline: false, strike: false,
                      color: color)
    }
}

public struct PdfStyleSheet: Sendable, Hashable {
    public var styles: [PdfStyleName: PdfStyle]

    public init(styles: [PdfStyleName: PdfStyle]) { self.styles = styles }

    public subscript(_ name: PdfStyleName) -> PdfStyle { styles[name] ?? styles[.normal]! }

    /// PdfExporter's `DefineStyles` (11 §3.3). Normal = `ResolveFontName("Calibri")` 11 pt, SpaceAfter 3 pt,
    /// line spacing ×1.15, widow control; every other style derives from it.
    public static let pdfExporter: PdfStyleSheet = {
        let normal = PdfStyle(fontFamily: "Calibri", size: 11, spaceAfter: 3, lineSpacing: 1.15)
        var s: [PdfStyleName: PdfStyle] = [.normal: normal]
        var title = normal; title.size = 26; title.bold = true; title.color = PdfColor(20, 20, 20); title.spaceAfter = 4
        s[.title] = title
        var subtitle = normal; subtitle.size = 12; subtitle.color = .muted; subtitle.spaceAfter = 12
        s[.subtitle] = subtitle
        var h1 = normal; h1.size = 16; h1.bold = true; h1.spaceBefore = 16; h1.spaceAfter = 6; h1.keepWithNext = true
        h1.bottomBorder = PdfBorder(width: 0.75, color: PdfColor(60, 60, 60))
        s[.h1] = h1
        var h2 = normal; h2.size = 13; h2.bold = true; h2.spaceBefore = 10; h2.spaceAfter = 4; h2.keepWithNext = true
        s[.h2] = h2
        var h3 = normal; h3.size = 11; h3.bold = true; h3.color = PdfColor(60, 60, 60); h3.spaceBefore = 6
        h3.spaceAfter = 2; h3.keepWithNext = true
        s[.h3] = h3
        var bodyItalic = normal; bodyItalic.italic = true; bodyItalic.color = PdfColor(80, 80, 80)
        s[.bodyItalic] = bodyItalic
        var bullet = normal; bullet.leftIndent = 0.6; bullet.firstLineIndent = -0.4
        s[.bullet] = bullet
        var muted = normal; muted.color = .muted; muted.size = 10
        s[.muted] = muted
        var header = normal; header.defaultTabStopsCm = nil
        s[.header] = header
        var footer = normal; footer.defaultTabStopsCm = nil
        s[.footer] = footer
        return PdfStyleSheet(styles: s)
    }()

    /// ChecklistExporter (PDF-081): Normal is "Calibri" 11 pt with MigraDoc's default spacing (0/0, single); no
    /// other styles are defined (Header/Footer inherit Normal).
    public static let checklist: PdfStyleSheet = {
        let normal = PdfStyle(fontFamily: "Calibri", size: 11)
        var header = normal; header.defaultTabStopsCm = nil
        return PdfStyleSheet(styles: [.normal: normal, .header: header, .footer: header])
    }()
}
