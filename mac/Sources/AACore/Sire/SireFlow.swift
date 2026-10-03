// Spec: 12 SIRE-020/021, §3.6 (SireFlow: colours, building blocks, BuildQuestion, BuildOverview, ParseBlocks — ported
//       exactly), §4.4 (the WPF block/attribute inventory), §6.1 (a small block model with two renderers: the XAML
//       writer for container bodies and NSAttributedString for display), §7.6 vectors.
import Foundation

/// WPF `Thickness` (left, top, right, bottom).
public struct SireThickness: Sendable, Hashable {
    public var left, top, right, bottom: Double
    public init(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
}

/// One WPF `Run`.
public struct SireFlowRun: Sendable, Hashable {
    public var text: String
    public var foreground: ARGB?
    public init(_ text: String, foreground: ARGB? = nil) { self.text = text; self.foreground = foreground }
}

/// One WPF `Paragraph`.
public struct SireFlowParagraph: Sendable, Hashable {
    public var runs: [SireFlowRun]
    public var fontSize: Double?
    public var italic: Bool
    public var margin: SireThickness?
    public var padding: SireThickness?
    public var background: ARGB?

    public init(runs: [SireFlowRun], fontSize: Double? = nil, italic: Bool = false, margin: SireThickness? = nil,
                padding: SireThickness? = nil, background: ARGB? = nil) {
        self.runs = runs; self.fontSize = fontSize; self.italic = italic; self.margin = margin
        self.padding = padding; self.background = background
    }

    /// The paragraph's plain text (runs concatenated).
    public var text: String { runs.map(\.text).joined() }
}

public enum SireListMarker: String, Sendable, Hashable { case disc = "Disc", circle = "Circle" }

/// One WPF `List`.
public struct SireFlowList: Sendable, Hashable {
    public var marker: SireListMarker
    public var margin: SireThickness?
    public var items: [SireFlowListItem]
    public init(marker: SireListMarker, margin: SireThickness? = nil, items: [SireFlowListItem] = []) {
        self.marker = marker; self.margin = margin; self.items = items
    }
}

/// One WPF `ListItem` (its paragraph, optionally followed by a nested list).
public struct SireFlowListItem: Sendable, Hashable {
    public var paragraph: SireFlowParagraph
    public var nested: SireFlowList?
    public init(paragraph: SireFlowParagraph, nested: SireFlowList? = nil) { self.paragraph = paragraph; self.nested = nested }
}

public indirect enum SireFlowBlock: Sendable, Hashable {
    case paragraph(SireFlowParagraph)
    case list(SireFlowList)
}

/// A `FlowDocument` built by SireFlow: Segoe UI 13, normal weight, root foreground `bodyBrush ?? Slate`.
public struct SireFlowDocument: Sendable, Hashable {
    public static let fontFamily = "Segoe UI"
    public static let fontSize: Double = 13
    public var foreground: ARGB
    public var blocks: [SireFlowBlock]
    public init(foreground: ARGB, blocks: [SireFlowBlock] = []) { self.foreground = foreground; self.blocks = blocks }
}

/// The SireFlow renderer of the C# app (§3.6).
public enum SireFlow {
    // MARK: Colours (§3.6, alpha always FF)

    public static let primary = ARGB(r: 0x1E, g: 0x40, b: 0xAF)
    public static let muted = ARGB(r: 0x64, g: 0x74, b: 0x8B)
    public static let slate = ARGB(r: 0x33, g: 0x41, b: 0x55)
    public static let chipBg = ARGB(r: 0xF8, g: 0xFA, b: 0xFC)
    public static let black = ARGB(r: 0, g: 0, b: 0)

    public struct Scheme: Sendable, Hashable { public let bg: ARGB; public let fg: ARGB }
    public static let defaultScheme = Scheme(bg: ARGB(r: 0xF1, g: 0xF5, b: 0xF9), fg: ARGB(r: 0x47, g: 0x55, b: 0x69))
    public static let amber = Scheme(bg: ARGB(r: 0xFE, g: 0xF3, b: 0xC7), fg: ARGB(r: 0x92, g: 0x40, b: 0x0E))
    public static let green = Scheme(bg: ARGB(r: 0xDC, g: 0xFC, b: 0xE7), fg: ARGB(r: 0x16, g: 0x65, b: 0x34))
    public static let red = Scheme(bg: ARGB(r: 0xFE, g: 0xE2, b: 0xE2), fg: ARGB(r: 0x99, g: 0x1B, b: 0x1B))

    /// The ten-section order of `BuildQuestion` step 6 (label, value, scheme).
    public static func sections(_ q: SireQuestion) -> [(label: String, body: String, scheme: Scheme)] {
        [("DATA SOURCE", q.dataSource, defaultScheme), ("PUBLICATIONS", q.publications, defaultScheme),
         ("OBJECTIVE", q.objective, defaultScheme), ("INDUSTRY GUIDANCE", q.industryGuidance, defaultScheme),
         ("INSPECTION GUIDANCE", q.inspectionGuidance, defaultScheme),
         ("SUGGESTED INSPECTOR ACTIONS", q.suggestedInspectorActions, amber),
         ("EXPECTED EVIDENCE", q.expectedEvidence, green),
         ("POTENTIAL GROUNDS FOR A NEGATIVE OBSERVATION", q.potentialNegativeObservationGrounds, red)]
    }

    // MARK: Building blocks (nothing is ever bold)

    static func heading(_ text: String, _ size: Double, _ fg: ARGB) -> SireFlowBlock {
        .paragraph(SireFlowParagraph(runs: [SireFlowRun(text, foreground: fg)], fontSize: size,
                                     margin: SireThickness(0, 0, 0, 4)))
    }

    static func line(_ text: String, _ size: Double, _ fg: ARGB, italic: Bool = false) -> SireFlowBlock {
        .paragraph(SireFlowParagraph(runs: [SireFlowRun(text, foreground: fg)], fontSize: size, italic: italic,
                                     margin: SireThickness(0, 0, 0, 6)))
    }

    static func chip(_ text: String, _ bg: ARGB, _ fg: ARGB) -> SireFlowBlock {
        .paragraph(SireFlowParagraph(runs: [SireFlowRun(text, foreground: fg)], margin: SireThickness(0, 2, 0, 8),
                                     padding: SireThickness(10, 8, 10, 8), background: bg))
    }

    static func addSection(_ blocks: inout [SireFlowBlock], _ label: String, _ body: String, _ scheme: Scheme) {
        if NetText.isBlank(body) { return }
        blocks.append(.paragraph(SireFlowParagraph(runs: [SireFlowRun(label, foreground: scheme.fg)], fontSize: 12,
                                                   margin: SireThickness(0, 10, 0, 4),
                                                   padding: SireThickness(8, 4, 8, 4), background: scheme.bg)))
        blocks.append(contentsOf: parseBlocks(body))
    }

    // MARK: Documents

    /// `BuildQuestion(q, bodyBrush)`: the pane passes black, quick-add nothing (→ slate).
    public static func buildQuestion(_ q: SireQuestion, body: ARGB? = nil) -> SireFlowDocument {
        var b: [SireFlowBlock] = []
        b.append(heading("Q \(q.questionNumber)", 20, primary))
        b.append(line("\(q.chapterDisplay)   ·   Section \(q.section)   ·   \(q.questionTypeDisplay)", 11, muted, italic: true))
        if !NetText.isBlank(q.shortQuestionText) { b.append(heading(q.shortQuestionText, 15, slate)) }
        if !NetText.isBlank(q.fullQuestionText) { b.append(chip(q.fullQuestionText, chipBg, slate)) }
        let meta = "Vessel: \(q.vesselTypesDisplay)" + (NetText.isBlank(q.roviqSequence) ? "" : "      ROVIQ: \(q.roviqSequence)")
        b.append(line(meta, 11, primary))
        for s in sections(q) { addSection(&b, s.label, s.body, s.scheme) }
        if !q.evidenceTags.isEmpty {
            b.append(line("Smart tags: " + q.evidenceTags.joined(separator: "   ·   "), 10, muted))
        }
        return SireFlowDocument(foreground: body ?? slate, blocks: b)
    }

    /// `BuildOverview(title, qs)` for a section / chapter parent.
    public static func buildOverview(title: String, questions qs: [SireQuestion], body: ARGB? = nil) -> SireFlowDocument {
        var b: [SireFlowBlock] = []
        b.append(heading(title, 18, primary))
        b.append(line("\(qs.count) SIRE 2.0 question(s). Imported from the SIRE 2.0 Knowledge Bank.", 11, muted, italic: true))
        var list = SireFlowList(marker: .disc, margin: SireThickness(0, 4, 0, 0))
        for q in qs {
            list.items.append(SireFlowListItem(paragraph: SireFlowParagraph(
                runs: [SireFlowRun("Q \(q.questionNumber) — \(q.shortQuestionText)")], margin: SireThickness(0, 1, 0, 1))))
        }
        b.append(.list(list))
        return SireFlowDocument(foreground: body ?? slate, blocks: b)
    }

    // MARK: ParseBlocks (port exactly — §3.6)

    static let bulletStarts: Set<UInt16> = [0x2022, 0x00B7, 0x2013, 0x2014]          // • · – —
    static let bulletPrefixes = ["• ", "•", "· ", "– ", "— ", "- ", "o ", "○ "]

    /// The PDF-bullet renderer: paragraphs and (nested) disc/circle lists.
    public static func parseBlocks(_ text: String) -> [SireFlowBlock] {
        var blocks: [SireFlowBlock] = []
        if NetText.isBlank(text) { return blocks }
        var normalized = SireText.units(text)
        normalized = SireText.replaceOrdinal(normalized, [0x0D, 0x0A], [0x0A])
        normalized = normalized.map { $0 == 0x0D ? 0x0A : $0 }
        let lines = SireText.split(normalized, on: [0x0A], removeEmpty: false)

        var currentPara: SireFlowParagraph?
        var inList = false
        var list = SireFlowList(marker: .disc)

        func flushPara() { if let p = currentPara { blocks.append(.paragraph(p)); currentPara = nil } }
        func flushList() { if inList { blocks.append(.list(list)); inList = false } }

        for rawLine in lines {
            let line = SireText.trimEnd(rawLine)
            let trimmed = SireText.trimStart(line)
            var isBullet = false, isSub = false
            if trimmed.count > 1 {
                if bulletStarts.contains(trimmed[0]) { isBullet = true }
                else if SireText.startsWith(trimmed, "- ") { isBullet = true }
            }
            if !isBullet && (SireText.startsWith(line, "    o ") || SireText.startsWith(line, "\to ")
                             || SireText.startsWith(trimmed, "○ ")) {
                isBullet = true; isSub = true
            }
            if isBullet && (SireText.startsWith(line, "    ") || SireText.startsWith(line, "\t")) { isSub = true }

            if isBullet {
                flushPara()
                if !inList { list = SireFlowList(marker: .disc); inList = true }
                var bulletText = trimmed
                for prefix in bulletPrefixes where SireText.startsWith(bulletText, prefix) {
                    bulletText = SireText.trimStart(Array(bulletText[prefix.utf16.count...]))
                    break
                }
                let para = SireFlowParagraph(runs: [SireFlowRun(SireText.string(bulletText))],
                                             margin: SireThickness(0, 1, 0, 1))
                if isSub, !list.items.isEmpty {
                    let last = list.items.count - 1
                    var sub = list.items[last].nested ?? SireFlowList(marker: .circle)
                    sub.items.append(SireFlowListItem(paragraph: para))
                    list.items[last].nested = sub
                } else {
                    list.items.append(SireFlowListItem(paragraph: para))
                }
            } else {
                flushList()
                if SireText.isBlank(line) {
                    flushPara()
                } else {
                    if currentPara == nil {
                        currentPara = SireFlowParagraph(runs: [], margin: SireThickness(0, 0, 0, 6))
                    } else {
                        currentPara!.runs.append(SireFlowRun(" "))
                    }
                    currentPara!.runs.append(SireFlowRun(SireText.string(trimmed)))
                }
            }
        }
        flushList()
        flushPara()
        if blocks.isEmpty { blocks.append(.paragraph(SireFlowParagraph(runs: [SireFlowRun(text)]))) }
        return blocks
    }
}
