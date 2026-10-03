// Spec: 11 §2.5 PDF-050…055 (saved-lists PDF), PDF-052 / 06 BUILD-A17 (heading state machine), §2.7 PDF-080…084
//       (checklist-only PDF), 06 §4.7 (BUILD-C1), §4.9 (BUILD-C3), 04 §3.9 (HIER-092); §7.12, §7.13.
import Foundation

/// The saved-lists PDF (product B): `ExportSavedLists(docTitle, entries, numbered)`.
public enum PdfSavedListsBuilder {
    /// `numbered` deliberately has no default (PDF-023): the caller must have asked.
    public static func build(title docTitle: String, entries: [PdfSavedListEntry], numbered: Bool, stamp: String) -> PdfDoc {
        var doc = PdfDoc(title: docTitle, styles: .pdfExporter, pageSetup: .pdfExporter)
        doc.header = [PdfScaffold.header("Saved lists: \(docTitle)", stamp: stamp)]
        doc.footer = [PdfScaffold.footer()]
        var b: [PdfBlock] = [
            .paragraph(PdfParagraph(docTitle, style: .title)),
            .paragraph(PdfParagraph("Saved checklists  \u{00B7}  \(entries.count) list\(entries.count == 1 ? "" : "s")",
                                    style: .subtitle)),
        ]
        var lastGroup: String?
        var started = false
        for e in entries {
            let g: String? = NetText.isBlank(e.group) ? nil : e.group
            if !started || !ordinalEqual(g, lastGroup) {                    // ordinal compare (PDF-052)
                if let g { b.append(.paragraph(PdfParagraph(g, style: .h1))) }
                else if started { b.append(.paragraph(PdfParagraph("Ungrouped", style: .h1))) }
                lastGroup = g
                started = true
            }
            let name = NetText.isBlank(e.name) ? "(unnamed list)" : e.name
            b.append(.paragraph(PdfParagraph("\(name)   (\(e.items.count) item\(e.items.count == 1 ? "" : "s"))", style: .h2)))
            for (i, it) in e.items.enumerated() {
                var p = PdfParagraph(style: .bullet)
                p.inlines = PdfText.inlines(numbered ? "\(i + 1). " : "\u{2022}  ", .bold) + PdfText.inlines(it.title)
                if it.isJob {
                    p.inlines += PdfText.inlines("  ") + PdfText.inlines("(schedulable)", PdfCharFormat(italic: true, color: .muted))
                }
                b.append(.paragraph(p))
                b += PdfRichText.body(it.container.xaml, heading: "", leftIndentCm: 0.6)
                if !it.container.files.isEmpty {
                    var f = PdfParagraph(style: .muted)
                    f.format.leftIndent = 0.6
                    f.inlines = PdfText.inlines("Files: ", .italic)
                        + PdfText.inlines(it.container.files.map(\.name).joined(separator: ", "))
                    b.append(.paragraph(f))
                }
            }
        }
        doc.body = b
        return doc
    }

    /// .NET `string ==` (ordinal, UTF-16 unit by unit): unlike Swift `==`, canonically equivalent spellings
    /// (precomposed vs. decomposed accents) are different groups, as on Windows (BUILD-A17 "exact string equality").
    static func ordinalEqual(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return x.utf16.elementsEqual(y.utf16)
        default: return false
        }
    }
}

/// The checklist-only PDF (product C) — ChecklistExporter.ExportPdf.
public enum PdfChecklistBuilder {
    /// Rows of the `Tasks / Equipment-Area` cell: `T: {name}` per resolvable task id, then `E/A: {name}` per
    /// resolvable equipment id (any kind resolves), one per line (PDF-084).
    public static func refs(_ s: PdfStepSnapshot, lookup: PdfLookup) -> [String] {
        s.taskIds.compactMap { lookup.find($0).map { "T: " + $0.name } }
            + s.equipmentIds.compactMap { lookup.find($0).map { "E/A: " + $0.name } }
    }

    public static func build(_ s: PdfChecklistSnapshot) -> PdfDoc {
        var doc = PdfDoc(title: "Checklist - \(s.name)", styles: .checklist, pageSetup: .checklist)
        doc.footer = [PdfScaffold.footer()]
        var b: [PdfBlock] = [
            .paragraph(PdfParagraph(style: .normal, format: PdfParagraphFormat(spaceAfter: 2, font: PdfCharFormat(size: 22, bold: true)),
                                    inlines: PdfText.inlines(s.name))),
            .paragraph(PdfParagraph(style: .normal, format: PdfParagraphFormat(spaceAfter: 10, font: PdfCharFormat(color: .muted)),
                                    inlines: PdfText.inlines("Checklist"))),
        ]
        if s.steps.isEmpty {
            b.append(.paragraph(PdfParagraph(style: .normal, format: PdfParagraphFormat(font: .italic),
                                             inlines: PdfText.inlines("(no steps)"))))
            doc.body = b
            return doc
        }
        let bold = PdfParagraphFormat(font: .bold)
        var t = PdfTable(columns: [0.9, 1.0, 7.2, 2.2, 5.0], borders: PdfBorder(width: 0.5, color: PdfColor(180, 180, 180)),
                         padding: PdfPadding(left: 3, right: 3, top: 3, bottom: 3))
        t.rows.append(PdfRow(headingFormat: true, shading: .tableHeader, cells: [
            PdfCell("#", format: bold), PdfCell("Done", format: bold), PdfCell("Step", format: bold),
            PdfCell("Due", format: bold), PdfCell("Tasks / Equipment-Area", format: bold)]))
        for (i, st) in s.steps.enumerated() {
            t.rows.append(PdfRow(cells: [
                PdfCell(String(i + 1)), PdfCell(st.done ? "[x]" : "[  ]"), PdfCell(st.title),
                PdfCell(st.deadline?.iso ?? ""), PdfCell(refs(st, lookup: s.lookup).joined(separator: "\n")),
            ]))
        }
        b.append(.table(t))
        doc.body = b
        return doc
    }
}
