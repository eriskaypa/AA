// TV: 11 §7.16 (PDFKit integration: page size, Page N / M, header on every page, link annotations, no link for
//     mid-token www., repeated table header rows, KeepWithNext, no U+0336, Title/Author, 40k-char performance),
//     PDF-100 (pagination rules: page-top SpaceBefore, max-collapse, widow/orphan, row-atomic tables), DEV-08 (tall
//     rows split), "text never clips horizontally".
import CoreText
import Foundation
import PDFKit
import Testing
@testable import AACore

@MainActor
@Suite("W-PDF rendering (PDFKit)")
struct PdfRenderTests {
    let stamp = "2026-09-29 14:05"

    func pdf(_ doc: PdfDoc) throws -> PDFDocument { try #require(PDFDocument(data: PdfRenderer.render(doc))) }
    func pageTexts(_ d: PDFDocument) -> [String] { (0..<d.pageCount).map { d.page(at: $0)?.string ?? "" } }

    func longTaskDoc() -> PdfDoc {
        var t = PdfTaskSnapshot(name: "Cargo tank inspection", description: "Annual survey")
        t.subtasks = (1...70).map { PdfTaskSnapshot(name: "Inspect tank section \($0)", description: "Record readings and photos") }
        let s = PdfItemSnapshot(kind: .task, name: "Cargo tank inspection", description: "Annual survey", specifics: .task(t))
        return PdfItemBuilder.build(s, stamp: stamp)
    }

    // TV: 11 §7.16 #1, #2, #8
    @Test func pagesFootersHeadersAndInfo() throws {
        let d = try pdf(longTaskDoc())
        #expect(d.pageCount >= 2)
        let texts = pageTexts(d)
        for i in 0..<d.pageCount {
            let box = try #require(d.page(at: i)).bounds(for: .mediaBox)
            #expect(abs(box.width - 595.28) < 0.05 && abs(box.height - 841.89) < 0.05)
            #expect(texts[i].contains("Page \(i + 1) / \(d.pageCount)"))
            #expect(texts[i].contains("Task: Cargo tank inspection"))
            #expect(texts[i].contains(stamp))
        }
        let attrs = d.documentAttributes ?? [:]
        #expect(attrs[PDFDocumentAttribute.titleAttribute] as? String == "Task - Cargo tank inspection")
        #expect(attrs[PDFDocumentAttribute.authorAttribute] as? String == "AA")
        // All 70 subtasks are printed, none lost at page breaks.
        let all = texts.joined(separator: "\n")
        for n in [1, 35, 70] { #expect(all.contains("Inspect tank section \(n)")) }
    }

    // TV: 11 §7.16 #2, #5 — checklist: no running header, header row repeated on every page
    @Test func checklistRepeatsHeadingRow() throws {
        let steps = (1...60).map { PdfStepSnapshot(title: "Step \($0) check and record", done: $0 % 2 == 0) }
        let d = try pdf(PdfChecklistBuilder.build(PdfChecklistSnapshot(name: "Long list", steps: steps, lookup: PdfLookup())))
        #expect(d.pageCount >= 2)
        let attrs = d.documentAttributes ?? [:]
        #expect(attrs[PDFDocumentAttribute.titleAttribute] as? String == "Checklist - Long list")
        for (i, t) in pageTexts(d).enumerated() {
            #expect(t.contains("Tasks / Equipment-Area"))
            #expect(t.contains("Page \(i + 1) / \(d.pageCount)"))
            #expect(!t.contains(stamp))
        }
        let all = pageTexts(d).joined()
        #expect(all.contains("Step 1 check") && all.contains("Step 60 check"))
    }

    // TV: 11 §7.16 #3, #4 — bare URL, e-mail, www. and a formal hyperlink become /URI link annotations
    @Test func linkAnnotations() throws {
        let doc = PdfX.doc(.section([
            .p([.r("Plain https://a.example.com/x and ops@ship.co.uk and www.imo.org/en here "),
                .link("https://formal.example/target", [.r("formal")])]),
            .p([.r("Not linked: backup_www.tar.gz")]),
        ]))
        var d = PdfDoc(title: "Links", styles: .pdfExporter, pageSetup: .pdfExporter)
        d.body = PdfRichText.blocks(of: doc)
        let p = try pdf(d)
        let urls = (try #require(p.page(at: 0))).annotations.filter { $0.type == "Link" }.compactMap { $0.url?.absoluteString }
        #expect(urls.count >= 4)
        #expect(Set(urls) == ["https://a.example.com/x", "mailto:ops@ship.co.uk", "https://www.imo.org/en",
                              "https://formal.example/target"])
        #expect(!urls.contains { $0.contains("backup") || $0.contains("tar.gz") })
    }

    // TV: 11 §7.16 #6 — a KeepWithNext heading is never the last line on a page
    @Test func keepWithNextHeadings() throws {
        for n in stride(from: 36, through: 50, by: 1) {
            var d = PdfDoc(title: "KWN", styles: .pdfExporter, pageSetup: .pdfExporter)
            d.body = (1...n).map { .paragraph(PdfParagraph("Filler line \($0)")) }
                + [.paragraph(PdfParagraph("HEADING-X", style: .h1)), .paragraph(PdfParagraph("after-heading"))]
            let texts = pageTexts(try pdf(d))
            let pageOfHeading = try #require(texts.firstIndex { $0.contains("HEADING-X") })
            #expect(texts[pageOfHeading].contains("after-heading"), "n = \(n)")
        }
    }

    // TV: 11 §7.16 #7 (DEV-04) — struck text extracts without U+0336
    @Test func strikeHasNoCombiningOverlay() throws {
        var d = PdfDoc(title: "Strike", styles: .pdfExporter, pageSetup: .pdfExporter)
        d.body = [.paragraph(PdfParagraph(style: .normal, inlines: [.text("old value", PdfCharFormat(strike: true)),
                                                                   .text(" new", .plain)]))]
        let t = pageTexts(try pdf(d)).joined()
        #expect(t.contains("old value new"))
        #expect(!t.unicodeScalars.contains("\u{0336}"))
    }

    // TV: 11 §7.16 #10, PDF-073 performance — a 40k-character single token
    @Test func fortyThousandCharacterToken() throws {
        let token = String(repeating: "x", count: 40_000)
        let doc = PdfX.doc(.section([.p([.r(token)])]))
        let t0 = Date()
        var d = PdfDoc(title: "Perf", styles: .pdfExporter, pageSetup: .pdfExporter)
        d.body = PdfRichText.blocks(of: doc)
        let data = PdfRenderer.render(d)
        #expect(Date().timeIntervalSince(t0) < 1.0)
        let p = try #require(PDFDocument(data: data))
        #expect(p.pageCount > 1)
        #expect(pageTexts(p).joined().filter { $0 == "x" }.count == 40_000)                 // nothing lost or clipped
    }

    // DEV-08 — a table row taller than a page is split at line boundaries; nothing is lost
    @Test func tallRowIsSplit() throws {
        let lines = (1...160).map { "line \($0)" }.joined(separator: "\n")
        var t = PdfTable(columns: [8, 8], borders: PdfBorder(width: 0.5, color: PdfColor(180, 180, 180)),
                         padding: PdfPadding(left: 3, right: 3, top: 2, bottom: 2))
        t.rows = [PdfRow(headingFormat: true, shading: .tableHeader, cells: [PdfCell("HEAD-A"), PdfCell("HEAD-B")]),
                  PdfRow(cells: [PdfCell(lines), PdfCell("short")])]
        var d = PdfDoc(title: "Tall", styles: .pdfExporter, pageSetup: .pdfExporter)
        d.body = [.paragraph(PdfParagraph("Intro")), .table(t)]
        let texts = pageTexts(try pdf(d))
        #expect(texts.count >= 3)
        let printed = texts.joined(separator: "\n").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(Set(printed).isSuperset(of: (1...160).map { "line \($0)" }))
        #expect(texts.dropFirst().allSatisfy { $0.contains("HEAD-A") })                       // heading repeated
    }

    // PDF-100 "text never clips horizontally": every drawn line stays inside the page's printable band
    @Test func linesStayInsideMargins() {
        let docs = [PdfEngineDemo.document(), longTaskDoc()]
        for doc in docs {
            let laid = PdfLayoutEngine(doc: doc).layout()
            let left = PdfLayoutEngine.pt(doc.pageSetup.left), right = laid.pageSize.width - PdfLayoutEngine.pt(doc.pageSetup.right)
            for page in laid.pages {
                for op in page {
                    guard case .line(let line, let origin) = op else { continue }
                    let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
                    #expect(origin.x >= left - 4)
                    #expect(origin.x + w <= right + 4, "line ends at \(origin.x + w) > \(right)")
                    #expect(origin.y > 0 && origin.y < laid.pageSize.height)
                }
            }
        }
    }

    // MARK: Paginator rules (synthetic slices)

    /// Each slice draws a 1×1 marker so its page and y can be read back.
    func para(_ id: UInt8, lines: Int, h: CGFloat = 10, before: CGFloat = 0, after: CGFloat = 0, kwn: Bool = false) -> PdfFlowItem {
        .para(PdfParaLayout(spaceBefore: before, spaceAfter: after, keepWithNext: kwn, widowControl: true,
                            lines: (0..<lines).map { _ in PdfSlice(height: h, ops: [.fill(CGRect(x: 0, y: 0, width: 1, height: 1), PdfColor(id, 0, 0))]) }))
    }

    func positions(_ pages: [[PdfDrawOp]], _ id: UInt8) -> [(page: Int, y: CGFloat)] {
        var out: [(Int, CGFloat)] = []
        for (i, p) in pages.enumerated() {
            for op in p { if case .fill(let r, let c) = op, c.r == id { out.append((i, r.minY)) } }
        }
        return out
    }

    // TV: 11 §3.2 rules 5 and 6
    @Test func spaceBeforeAndCollapse() {
        let pages = PdfPaginator(height: 100).paginate([para(1, lines: 1, before: 16, after: 3), para(2, lines: 1, before: 16),
                                                       para(3, lines: 1, before: 2, after: 0)])
        #expect(positions(pages, 1).first?.y == 0)                                         // dropped at the page top
        #expect(positions(pages, 2).first?.y == 26)                                        // 10 + max(3, 16)
        #expect(positions(pages, 3).first?.y == 38)                                        // 36 + max(0, 2)
    }

    // TV: 11 §3.2 widow/orphan control (2 lines at each end)
    @Test func widowOrphanControl() {
        // 9 lines of filler, then a 5-line paragraph: only 1 line fits → the whole paragraph moves.
        var pages = PdfPaginator(height: 100).paginate([para(1, lines: 9), para(2, lines: 5)])
        #expect(positions(pages, 2).map(\.page) == [1, 1, 1, 1, 1])
        // 6 lines of filler: 4 of 5 fit → 3 stay, 2 move (no widow).
        pages = PdfPaginator(height: 100).paginate([para(1, lines: 6), para(2, lines: 5)])
        #expect(positions(pages, 2).map(\.page) == [0, 0, 0, 1, 1])
        // 8 lines of filler: 2 fit → 2 stay, 3 move.
        pages = PdfPaginator(height: 100).paginate([para(1, lines: 8), para(2, lines: 5)])
        #expect(positions(pages, 2).map(\.page) == [0, 0, 1, 1, 1])
    }

    // TV: 11 §3.2 rule 7 — a KWN chain moves together with the first line of the next element
    @Test func keepWithNextChain() {
        let pages = PdfPaginator(height: 100).paginate([para(1, lines: 9), para(2, lines: 1, kwn: true), para(3, lines: 4)])
        #expect(positions(pages, 2).first?.page == 1)
        #expect(positions(pages, 3).first?.page == 1)
        // At a page top the chain is placed even if it cannot fit.
        let tall = PdfPaginator(height: 100).paginate([para(4, lines: 1, kwn: true), para(5, lines: 12)])
        #expect(positions(tall, 4).first?.page == 0)
    }
}
