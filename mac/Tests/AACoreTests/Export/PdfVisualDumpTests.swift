// Visual verification helper (11 §7.16 "verify generated PDFs visually"): when AA_PDF_DUMP_DIR is set, writes
// the sample exports and one PNG per page (rendered with CoreGraphics at 2×) into that folder. Skipped otherwise.
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AACore

enum PdfDump {
    static var dir: URL? {
        guard let p = ProcessInfo.processInfo.environment["AA_PDF_DUMP_DIR"], !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p, isDirectory: true)
    }

    static func write(_ data: Data, name: String) throws {
        guard let dir else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appending(path: "\(name).pdf"))
        guard let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider) else { return }
        for i in 1...max(1, pdf.numberOfPages) {
            guard let page = pdf.page(at: i) else { continue }
            let box = page.getBoxRect(.mediaBox)
            let scale: CGFloat = 2
            guard let ctx = CGContext(data: nil, width: Int(box.width * scale), height: Int(box.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: box.width * scale, height: box.height * scale))
            ctx.scaleBy(x: scale, y: scale)
            ctx.drawPDFPage(page)
            guard let img = ctx.makeImage() else { continue }
            let url = dir.appending(path: "\(name)-p\(i).png")
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, img, nil)
                CGImageDestinationFinalize(dest)
            }
        }
    }
}

@MainActor
@Suite("W-PDF visual dump", .enabled(if: PdfDump.dir != nil))
struct PdfVisualDumpTests {
    @Test func dumpSamples() throws {
        let g = PdfTestData.golden()
        let store = g.made.store
        let stamp = "2026-10-02 14:05"
        for item in [g.pumpRoom as HierarchyItem, g.overhaul, g.loto, g.aurora] {
            let s = PdfSnapshotBuilder.item(item, store: store, isGated: { _ in false })
            try PdfDump.write(PdfExport.itemPDF(s, stamp: stamp), name: "item-\(item.kind.name)")
        }
        let cl = PdfSnapshotBuilder.checklist(g.loto, store: store)
        try PdfDump.write(PdfExport.checklistPDF(cl), name: "checklist-LOTO")

        // A 60-step checklist (heading repeat on every page).
        let big = Procedure(name: "Pre-arrival checks — cargo, deck and engine")
        for i in 1...60 {
            let s = ChecklistStep(title: "Step \(i): verify item number \(i) of the pre-arrival list and record readings in the log")
            s.done = i % 3 == 0
            if i % 4 == 0 { s.deadline = PdfTestData.day(2026, 10, i % 28 + 1) }
            if i % 5 == 0 { s.taskIds = [g.overhaul.id]; s.equipmentIds = [g.pumpRoom.id] }
            big.steps.append(s)
        }
        store.data.procedures.append(big)
        try PdfDump.write(PdfExport.checklistPDF(PdfSnapshotBuilder.checklist(big, store: store)), name: "checklist-60")
        try PdfDump.write(PdfExport.itemPDF(PdfSnapshotBuilder.item(big, store: store, isGated: { _ in false }), stamp: stamp),
                          name: "item-Procedure-60")

        let lists = PdfTestData.savedLists()
        let made = StoreFactory.make(data: lists)
        if case .entries(let title, let entries) = PdfExport.savedListsSelection(.all, data: made.store.data) {
            try PdfDump.write(PdfExport.savedListsPDF(title: title, entries: entries, numbered: false, stamp: stamp),
                              name: "saved-all-bulleted")
            try PdfDump.write(PdfExport.savedListsPDF(title: title, entries: entries, numbered: true, stamp: stamp),
                              name: "saved-all-numbered")
        }
        try PdfDump.write(PdfRenderer.render(PdfEngineDemo.document()), name: "engine-demo")

        // The showcase data folder (copied to Fixtures/ui/w-pdf/sample-data.json) and its exports.
        let show = StoreFactory.make(data: PdfTestData.showcase())
        if let dir = PdfDump.dir {
            try show.dataStore.serializeForSave(show.store.data).write(to: dir.appending(path: "sample-data.json"))
        }
        for item in show.store.allItems() {
            let s = PdfSnapshotBuilder.item(item, store: show.store, isGated: { _ in false })
            try PdfDump.write(PdfExport.itemPDF(s, stamp: stamp), name: "show-\(item.kind.name)-\(item.name.prefix(12))")
        }
        if case .entries(let title, let entries) = PdfExport.savedListsSelection(.all, data: show.store.data) {
            try PdfDump.write(PdfExport.savedListsPDF(title: title, entries: entries, numbered: false, stamp: stamp),
                              name: "show-saved-all")
        }
    }
}

/// A document exercising every engine feature directly at the DOM level (fonts, colours, sizes, alignment,
/// indents, lists, tables with merges/borders/shading, nested tables, links, strike, highlight, tabs, breaks).
enum PdfEngineDemo {
    static func document() -> PdfDoc {
        var doc = PdfDoc(title: "Engine demo", styles: .pdfExporter, pageSetup: .pdfExporter)
        doc.header = [PdfScaffold.header("Task: Engine demo with a fairly long name to test the tab", stamp: "2026-10-02 14:05")]
        doc.footer = [PdfScaffold.footer()]
        var b: [PdfBlock] = []
        b.append(.paragraph(PdfParagraph("Engine demo", style: .title)))
        b.append(.paragraph(PdfParagraph("Task", style: .subtitle)))
        b.append(.paragraph(PdfParagraph("A description in BodyItalic.\nSecond line after a break.", style: .bodyItalic)))
        b.append(.paragraph(PdfParagraph("Notes", style: .h1)))
        let consolas = PdfCharFormat(fontFamily: "Consolas", size: 10.5, bold: false, color: PdfColor(26, 26, 26))
        var p = PdfParagraph()
        p.inlines = [.text("Warn", PdfCharFormat(fontFamily: "Consolas", size: 10.5, bold: false, color: PdfColor(192, 0, 0))),
                     .text("ing", PdfCharFormat(fontFamily: "Consolas", size: 10.5, bold: true, color: PdfColor(0, 0, 255))),
                     .text(" ok — see ", consolas),
                     .link(url: "https://www.imo.org", [.text("IMO", consolas.overlaid(PdfCharFormat(underline: true, color: .link)))]),
                     .text(" or mail ", consolas),
                     .link(url: "mailto:ops@ship.co.uk", [.text("ops@ship.co.uk", consolas.overlaid(PdfCharFormat(underline: true, color: .link)))]),
                     .lineBreak,
                     .text("old value", consolas.overlaid(PdfCharFormat(strike: true))),
                     .text(" new value", consolas)]
        b.append(.paragraph(p))
        var hl = PdfParagraph("A whole-line highlighted paragraph that is long enough to wrap onto a second line so the shading covers both lines between the indents.")
        hl.format.shading = PdfColor(255, 255, 0)
        b.append(.paragraph(hl))
        var c = PdfParagraph("Centered paragraph"); c.format.alignment = .center; b.append(.paragraph(c))
        var r = PdfParagraph("Right-aligned paragraph"); r.format.alignment = .right; b.append(.paragraph(r))
        var j = PdfParagraph(String(repeating: "Justified text runs to both margins when it wraps. ", count: 4))
        j.format.alignment = .justify; b.append(.paragraph(j))
        var ind = PdfParagraph("Indented 0.635 cm (Margin 24 px) with a hanging first line of −0.3175 cm that wraps around to show the hanging indent clearly on the following line.")
        ind.format.leftIndent = 0.635; ind.format.firstLineIndent = -0.3175; b.append(.paragraph(ind))
        for (i, t) in ["First bullet item", "Second bullet item which is long enough to wrap and show the hanging indent under the text"].enumerated() {
            var li = PdfParagraph(); li.format.leftIndent = 0.6; li.format.firstLineIndent = -0.4
            li.inlines = [.text("\u{2022} ", PdfCharFormat()), .text(t, consolas)]
            _ = i; b.append(.paragraph(li))
        }
        for (i, t) in ["Nested numbered one", "Nested numbered two"].enumerated() {
            var li = PdfParagraph(); li.format.leftIndent = 1.2; li.format.firstLineIndent = -0.4
            li.inlines = [.text("\(i + 1). ", PdfCharFormat()), .text(t, consolas)]
            b.append(.paragraph(li))
        }
        var tab = PdfParagraph(); tab.inlines = [.text("Tab", consolas), .tab, .text("stop", consolas), .tab, .text("again", consolas)]
        b.append(.paragraph(tab))
        // Rich table: 3 columns, merged header, borders 0.6 #9AA0A6, bold header row, shading, nested table.
        let border = PdfCellBorders.border(PdfBorder(width: 0.6, color: PdfColor(154, 160, 166)))
        func cell(_ s: String, bold: Bool = false, mr: Int = 0, md: Int = 0, shade: PdfColor? = nil, blocks: [PdfBlock]? = nil) -> PdfCell {
            PdfCell(mergeRight: mr, mergeDown: md, borders: border, shading: shade, format: PdfCharFormat(bold: bold ? true : nil),
                    blocks: blocks ?? [.paragraph(PdfParagraph(style: .normal, inlines: PdfText.inlines(s, consolas)))])
        }
        var nested = PdfTable(columns: [2, 2], borders: PdfBorder(width: 0.5, color: PdfColor(180, 180, 180)))
        nested.rows = [PdfRow(cells: [PdfCell("n1"), PdfCell("n2")]), PdfRow(cells: [PdfCell("n3"), PdfCell("n4")])]
        var t = PdfTable(columns: [16.0 / 3, 16.0 / 3, 16.0 / 3], borders: nil)
        t.rows = [
            PdfRow(cells: [cell("Head spanning two", bold: true, mr: 1), PdfCell(), cell("Head 3", bold: true)]),
            PdfRow(cells: [cell("Rowspan A", md: 1, shade: PdfColor(255, 255, 0)), cell("B"), cell("C")]),
            PdfRow(cells: [PdfCell(), cell("D with a long text that wraps inside the cell to make the row taller"),
                           cell("", blocks: [.paragraph(PdfParagraph("Nested:")), .table(nested)])]),
        ]
        b.append(.table(t))
        b.append(.paragraph(PdfParagraph("Relationships (2)", style: .h1)))
        b.append(.paragraph(PdfParagraph("Items linked to this one, grouped by tab.", style: .bodyItalic)))
        b.append(.paragraph(PdfParagraph("Equipment/Area (1)", style: .h2)))
        b.append(.paragraph(PdfParagraph(style: .bullet, inlines: PdfText.inlines("Pump room", .bold) + PdfText.inlines(" \u{2014} Aft"))))
        b.append(.paragraph(PdfParagraph("H3 heading", style: .h3)))
        b.append(.paragraph(PdfParagraph("Muted paragraph text", style: .muted)))
        b.append(.paragraph(PdfParagraph("Emoji and CJK fallback: 😀 ⚓ 日本語 — and a 40-char token: " + String(repeating: "x", count: 120))))
        for i in 1...30 { b.append(.paragraph(PdfParagraph("Filler paragraph \(i) to force pagination across several pages of the document."))) }
        doc.body = b
        return doc
    }
}
