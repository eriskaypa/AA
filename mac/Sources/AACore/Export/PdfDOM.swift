// Spec: 11 §6.1 (PdfDOM: a MigraDoc-like document model), §3.2 (MigraDoc behaviours the layout reproduces),
//       PDF-101 (AddText splitting on \n and \t; DEV-13 CR/CRLF → LF), §3.1 (units).
// Pure Sendable value types: the builders produce them from model snapshots, the layout engine consumes them, and
// the tests assert on them (11 §7 "DOM-level" vectors).
import Foundation

/// An sRGB colour as the Windows exporter writes it (`new Color(r, g, b)`; alpha is never used).
public struct PdfColor: Sendable, Hashable, CustomStringConvertible {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    public static let black = PdfColor(0, 0, 0)
    /// RGB(120,120,120) — header, footer, meta, Subtitle, Muted (11 §3.1).
    public static let muted = PdfColor(120, 120, 120)
    /// RGB(235,235,235) — table header shading (components, files, checklist).
    public static let tableHeader = PdfColor(235, 235, 235)
    /// RGB(11,97,164) — `LinkBlue` (PDF-071).
    public static let link = PdfColor(11, 97, 164)
    /// RGB(255,230,153) — the edit-lock sentinel (PDF-064d).
    public static let lockSentinel = PdfColor(255, 230, 153)

    public var description: String { "RGB(\(r),\(g),\(b))" }
}

/// Unit conversions (11 §3.1).
public enum PdfUnits {
    /// 1 cm in PDF points.
    public static let pointsPerCm = 72.0 / 2.54
    /// 1 WPF px (1/96 in) in cm.
    public static let cmPerPx = 2.54 / 96.0
    public static func pt(cm: Double) -> Double { cm * pointsPerCm }
    public static func cm(px: Double) -> Double { px * cmPerPx }
    /// A4 portrait in points (21.0 × 29.7 cm).
    public static let a4Width = 21.0 * pointsPerCm
    public static let a4Height = 29.7 * pointsPerCm
}

/// Character formatting with MigraDoc semantics: `nil` = inherited from the paragraph / cell / style.
/// `bold == false` is MigraDoc's explicit `TextFormat.NotBold`.
public struct PdfCharFormat: Sendable, Hashable {
    /// The requested family as written (a WPF `FontFamily` source or a style font such as "Calibri");
    /// resolved by `PdfFontResolver` at layout time (PDF-076, 11 §6.4).
    public var fontFamily: String?
    public var size: Double?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    /// Mac strikethrough (DEV-04): drawn on every character the `PdfStrike` predicate selects.
    public var strike: Bool?
    public var color: PdfColor?

    public init(fontFamily: String? = nil, size: Double? = nil, bold: Bool? = nil, italic: Bool? = nil,
                underline: Bool? = nil, strike: Bool? = nil, color: PdfColor? = nil) {
        self.fontFamily = fontFamily; self.size = size; self.bold = bold; self.italic = italic
        self.underline = underline; self.strike = strike; self.color = color
    }

    public static let plain = PdfCharFormat()
    public static let bold = PdfCharFormat(bold: true)
    public static let italic = PdfCharFormat(italic: true)

    /// `self` overlaid with every non-nil field of `o`.
    public func overlaid(_ o: PdfCharFormat) -> PdfCharFormat {
        PdfCharFormat(fontFamily: o.fontFamily ?? fontFamily, size: o.size ?? size, bold: o.bold ?? bold,
                      italic: o.italic ?? italic, underline: o.underline ?? underline, strike: o.strike ?? strike,
                      color: o.color ?? color)
    }
}

/// Inline content of a paragraph (11 §6.1).
public indirect enum PdfInline: Sendable, Hashable {
    case text(String, PdfCharFormat)
    case lineBreak
    case tab
    /// `AddPageField()` — the current page number.
    case pageField(PdfCharFormat)
    /// `AddNumPagesField()` — the total page count.
    case numPagesField(PdfCharFormat)
    /// `AddHyperlink(url, Web)` — every inline inside is clickable (PDF-071, §3.2 rule 12).
    case link(url: String, [PdfInline])
}

public enum PdfAlignment: String, Sendable, Hashable { case left, center, right, justify }

public struct PdfTabStop: Sendable, Hashable {
    public enum Alignment: Sendable, Hashable { case left, right }
    public var positionCm: Double
    public var alignment: Alignment
    public init(positionCm: Double, alignment: Alignment) { self.positionCm = positionCm; self.alignment = alignment }
}

public struct PdfBorder: Sendable, Hashable {
    public var width: Double          // points
    public var color: PdfColor
    public init(width: Double, color: PdfColor) { self.width = width; self.color = color }
}

/// Paragraph format overrides (nil = from the style). Lengths in cm, spacing in points.
public struct PdfParagraphFormat: Sendable, Hashable {
    public var alignment: PdfAlignment?
    public var leftIndent: Double?
    public var firstLineIndent: Double?
    public var rightIndent: Double?
    public var spaceBefore: Double?
    public var spaceAfter: Double?
    public var keepWithNext: Bool?
    public var shading: PdfColor?
    /// `par.Format.Font.*` overrides.
    public var font: PdfCharFormat
    public var tabStops: [PdfTabStop]

    public init(alignment: PdfAlignment? = nil, leftIndent: Double? = nil, firstLineIndent: Double? = nil,
                rightIndent: Double? = nil, spaceBefore: Double? = nil, spaceAfter: Double? = nil,
                keepWithNext: Bool? = nil, shading: PdfColor? = nil, font: PdfCharFormat = PdfCharFormat(),
                tabStops: [PdfTabStop] = []) {
        self.alignment = alignment; self.leftIndent = leftIndent; self.firstLineIndent = firstLineIndent
        self.rightIndent = rightIndent; self.spaceBefore = spaceBefore; self.spaceAfter = spaceAfter
        self.keepWithNext = keepWithNext; self.shading = shading; self.font = font; self.tabStops = tabStops
    }
}

public struct PdfParagraph: Sendable, Hashable {
    public var style: PdfStyleName
    public var format: PdfParagraphFormat
    public var inlines: [PdfInline]

    public init(style: PdfStyleName = .normal, format: PdfParagraphFormat = PdfParagraphFormat(),
                inlines: [PdfInline] = []) {
        self.style = style; self.format = format; self.inlines = inlines
    }

    /// `sec.AddParagraph(text)` + style (11 §3.4.1 H1/H2/H3/Italic helpers): the text goes through AddText.
    public init(_ text: String, style: PdfStyleName = .normal) {
        self.init(style: style, inlines: PdfText.inlines(text))
    }

    /// The paragraph's plain text (fields as `#`, breaks as `\n`, tabs as `\t`) — used by tests and the
    /// "is blank" checks.
    public var plainText: String { PdfText.plain(inlines) }
}

public enum PdfCellBorders: Sendable, Hashable {
    /// The table's borders.
    case inherit
    /// `Borders.Visible = false`.
    case none
    case border(PdfBorder)
}

/// One table cell. `blocks` empty means an empty cell (the layout still gives it one line of the Normal font).
public struct PdfCell: Sendable, Hashable {
    public var mergeRight: Int
    public var mergeDown: Int
    /// Cell-level border override (`ApplyCellBorders`, PDF-070).
    public var borders: PdfCellBorders
    public var shading: PdfColor?
    /// `cell.Format.Font.*` (e.g. whole-cell bold for a rich-text header row, PDF-070).
    public var format: PdfCharFormat
    public var blocks: [PdfBlock]

    public init(mergeRight: Int = 0, mergeDown: Int = 0, borders: PdfCellBorders = .inherit, shading: PdfColor? = nil,
                format: PdfCharFormat = PdfCharFormat(), blocks: [PdfBlock] = []) {
        self.mergeRight = mergeRight; self.mergeDown = mergeDown; self.borders = borders; self.shading = shading
        self.format = format; self.blocks = blocks
    }

    /// A cell holding one paragraph (`cell.AddParagraph(text)`), optionally with paragraph format overrides.
    public init(_ text: String, format: PdfParagraphFormat = PdfParagraphFormat()) {
        self.init(blocks: [.paragraph(PdfParagraph(style: .normal, format: format, inlines: PdfText.inlines(text)))])
    }
}

public struct PdfRow: Sendable, Hashable {
    /// `HeadingFormat = true` — repeated at the top of every continuation page (§3.2 rule 8).
    public var headingFormat: Bool
    public var shading: PdfColor?
    public var cells: [PdfCell]
    public init(headingFormat: Bool = false, shading: PdfColor? = nil, cells: [PdfCell]) {
        self.headingFormat = headingFormat; self.shading = shading; self.cells = cells
    }
}

public struct PdfPadding: Sendable, Hashable {
    public var left: Double, right: Double, top: Double, bottom: Double   // points
    public init(left: Double, right: Double, top: Double, bottom: Double) {
        self.left = left; self.right = right; self.top = top; self.bottom = bottom
    }
    /// MigraDoc default cell padding: 1.2 mm left/right, 0 top/bottom (§3.2 rule 8).
    public static let migraDocDefault = PdfPadding(left: 1.2 / 10 * PdfUnits.pointsPerCm,
                                                   right: 1.2 / 10 * PdfUnits.pointsPerCm, top: 0, bottom: 0)
}

public struct PdfTable: Sendable, Hashable {
    /// Column widths in cm.
    public var columns: [Double]
    /// Table-level borders (applied to every cell without its own override); nil = no borders.
    public var borders: PdfBorder?
    public var padding: PdfPadding
    public var rows: [PdfRow]
    public init(columns: [Double], borders: PdfBorder?, padding: PdfPadding = .migraDocDefault, rows: [PdfRow] = []) {
        self.columns = columns; self.borders = borders; self.padding = padding; self.rows = rows
    }
}

public indirect enum PdfBlock: Sendable, Hashable {
    case paragraph(PdfParagraph)
    case table(PdfTable)

    public var paragraph: PdfParagraph? { if case .paragraph(let p) = self { return p }; return nil }
    public var table: PdfTable? { if case .table(let t) = self { return t }; return nil }
}

public struct PdfPageSetup: Sendable, Hashable {
    /// Margins and header/footer distances in cm.
    public var top: Double, bottom: Double, left: Double, right: Double
    public var headerDistance: Double, footerDistance: Double
    public init(top: Double = 2, bottom: Double = 2, left: Double = 2, right: Double = 2,
                headerDistance: Double = 1.25, footerDistance: Double = 1.25) {
        self.top = top; self.bottom = bottom; self.left = left; self.right = right
        self.headerDistance = headerDistance; self.footerDistance = footerDistance
    }
    /// A4 portrait, 2 cm margins; PdfExporter sets header/footer distance 1 cm (PDF-030).
    public static let pdfExporter = PdfPageSetup(headerDistance: 1, footerDistance: 1)
    /// ChecklistExporter leaves MigraDoc's 1.25 cm defaults (PDF-080, §3.2 rule 1).
    public static let checklist = PdfPageSetup()

    public var printableWidthCm: Double { 21.0 - left - right }
}

/// One MigraDoc document with a single section (11 §6.1).
public struct PdfDoc: Sendable, Hashable {
    public var title: String
    public var author: String
    public var styles: PdfStyleSheet
    public var pageSetup: PdfPageSetup
    public var header: [PdfParagraph]
    public var footer: [PdfParagraph]
    public var body: [PdfBlock]

    public init(title: String, author: String = "AA", styles: PdfStyleSheet, pageSetup: PdfPageSetup,
                header: [PdfParagraph] = [], footer: [PdfParagraph] = [], body: [PdfBlock] = []) {
        self.title = title; self.author = author; self.styles = styles; self.pageSetup = pageSetup
        self.header = header; self.footer = footer; self.body = body
    }

    /// Every paragraph of the body in document order, descending into table cells (row by row) — for tests.
    public var allParagraphs: [PdfParagraph] {
        var out: [PdfParagraph] = []
        func walk(_ blocks: [PdfBlock]) {
            for b in blocks {
                switch b {
                case .paragraph(let p): out.append(p)
                case .table(let t): for r in t.rows { for c in r.cells { walk(c.blocks) } }
                }
            }
        }
        walk(body)
        return out
    }
}

/// MigraDoc `AddText` semantics (PDF-101, §3.2 rule 4) and plain-text helpers.
public enum PdfText {
    /// CRLF and lone CR become LF (DEV-13).
    public static func normalizeNewlines(_ s: String) -> String {
        guard s.utf8.contains(0x0D) else { return s }
        return s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// `AddText(s)`: `\n` → line break, `\t` → tab, empty segments add nothing.
    public static func inlines(_ s: String, _ format: PdfCharFormat = PdfCharFormat()) -> [PdfInline] {
        let text = normalizeNewlines(s)
        var out: [PdfInline] = []
        var current = ""
        for ch in text {
            switch ch {
            case "\n":
                if !current.isEmpty { out.append(.text(current, format)); current = "" }
                out.append(.lineBreak)
            case "\t":
                if !current.isEmpty { out.append(.text(current, format)); current = "" }
                out.append(.tab)
            default:
                current.append(ch)
            }
        }
        if !current.isEmpty { out.append(.text(current, format)) }
        return out
    }

    public static func plain(_ inlines: [PdfInline]) -> String {
        var s = ""
        for i in inlines {
            switch i {
            case .text(let t, _): s += t
            case .lineBreak: s += "\n"
            case .tab: s += "\t"
            case .pageField: s += "#"
            case .numPagesField: s += "#"
            case .link(_, let inner): s += plain(inner)
            }
        }
        return s
    }
}
