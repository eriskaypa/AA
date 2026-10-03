// TV: 11 §7.6 (indentation), §7.7 (lists), §7.8 (tables), §7.9 (highlight), §7.11 (fallback parsing), §7.2
//     (targetless links), PDF-060…077, DEV-02, DECISIONS 11 Q4/Q5. The DOM-structure vectors drive
//     `PdfRichText.blocks(of:)` with hand-built `XamlDocument`s; vectors that need the W-RICH parser or cascade are
//     gated on `ContractStatus.isImplemented(.wRich)` (ARCHITECTURE.md §10.5).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite("W-PDF rich text → PdfDOM")
struct PdfRichTextTests {
    func paras(_ blocks: [PdfBlock]) -> [PdfParagraph] { blocks.compactMap(\.paragraph) }

    // MARK: §7.11 fallback

    // TV: 11 §7.11 rows 1, 4, 6; PDF-061
    @Test func fallbackParsing() {
        #expect(PdfRichText.body("", heading: "Notes").isEmpty)
        #expect(PdfRichText.body("   ", heading: "Notes").isEmpty)
        let two = paras(PdfRichText.body("plain text\r\nline2\r\n\r\n", heading: ""))
        #expect(two.map(\.plainText) == ["plain text", "line2"])
        #expect(two.allSatisfy { $0.style == .normal })
        #expect(paras(PdfRichText.body("<b>x</b> > y", heading: "")).map(\.plainText) == ["x    y"])
        #expect(PdfRichText.stripXamlTags("<b>x</b> > y") == "x    y")
    }

    // TV: 11 §7.11 row 3 — no xmlns → load failure (stub and real parser alike) → fallback, heading first
    @Test func fallbackWithoutNamespaceKeepsHeading() {
        let b = paras(PdfRichText.body("<Section><Paragraph>Hi &amp; bye</Paragraph></Section>", heading: "Notes"))
        #expect(b.map(\.plainText) == ["Notes", "Hi & bye"])
        #expect(b.map(\.style) == [.h1, .normal])
    }

    // TV: 11 §7.11 row 5 / DECISIONS 11 Q5
    @Test func legacyEncryptedBodyPrintsPlaceholder() {
        let b = paras(PdfRichText.body("enc:QUJDREVGRw==", heading: "Notes"))
        #expect(b.map(\.plainText) == ["Notes", "(locked content)"])
        #expect(paras(PdfRichText.body("enc:QUJD", heading: "")).map(\.plainText) == ["(locked content)"])
    }

    // TV: 11 PDF-074 — every top-level paragraph shifted by the context indent (fallback path)
    @Test func contextIndentShiftsParagraphs() {
        let b = paras(PdfRichText.body("one\ntwo", heading: "", leftIndentCm: 0.6))
        #expect(b.map(\.format.leftIndent) == [0.6, 0.6])
    }

    @Test func htmlEntitiesDecoded() {
        #expect(PdfRichText.stripXamlTags("a &lt;b&gt; &amp; &quot;c&quot; &#65;&#x42; &nbsp;z") == "a <b> & \"c\" AB \u{00A0}z")
    }

    // MARK: DOM path (hand-built documents)

    // TV: 11 §7.7
    @Test func lists() {
        let doc = PdfX.doc(.section([
            .list("Disc", [[.p([.r("a")])], [.p([.r("b")])]]),
            .list("Decimal", [[.p([.r("a")])], [.p([.r("b")])]]),
            .list("LowerLatin", [[.p([.r("a")])]]),
            .list("None", [[.p([.r("a")])]]),
            .list("Decimal", [[.p([.r("a")]), .list("LowerLatin", [[.p([.r("x")])], [.p([.r("y")])]])], [.p([.r("b")])]]),
            .list("Decimal", [[.p([.r("p1")]), .p([.r("p2")])], [.p([.r("q")])]]),
        ]))
        let p = paras(PdfRichText.blocks(of: doc))
        #expect(p.map(\.plainText) == ["\u{2022} a", "\u{2022} b", "1. a", "2. b", "1. a", "\u{2022} a",
                                       "1. a", "1. x", "2. y", "2. b", "1. p1", "2. p2", "3. q"])
        #expect(p[0].format.leftIndent == 0.6 && p[0].format.firstLineIndent == -0.4)
        #expect(p[7].format.leftIndent == 1.2 && p[8].format.leftIndent == 1.2)
        #expect(p[9].format.leftIndent == 0.6)
        // The marker is Normal-style text (no own format), the item keeps its run format.
        if case .text(let m, let f) = p[0].inlines[0] { #expect(m == "\u{2022} " && f == PdfCharFormat()) }
        else { Issue.record("marker missing") }
    }

    // TV: 11 §7.7 — a table inside a list item: rendered, no marker, not indented
    @Test func tableInsideListItem() {
        let table = PdfX.el(.table, XamlLocalValues(), [.el(.tableRowGroup, XamlLocalValues(), [
            .el(.tableRow, XamlLocalValues(), [.el(.tableCell, XamlLocalValues(), [.p([.r("cell")])])])])])
        let blocks = PdfRichText.blocks(of: PdfX.doc(.section([.list("Disc", [[table]])])))
        #expect(blocks.count == 1)
        #expect(blocks[0].table?.rows.first?.cells.first?.blocks.first?.paragraph?.plainText == "cell")
    }

    // TV: 11 §7.6
    @Test func indentation() {
        func para(_ f: (inout XamlLocalValues) -> Void) -> PdfParagraph {
            paras(PdfRichText.blocks(of: PdfX.doc(.section([.p([.r("x")], .pdfWith(f))]))))[0]
        }
        func close(_ a: Double?, _ b: Double?) -> Bool {
            switch (a, b) { case (nil, nil): return true; case let (x?, y?): return abs(x - y) < 1e-3; default: return false }
        }
        var p = para { $0.margin = XamlThickness(left: 24, top: 0, right: 0, bottom: 0) }
        #expect(close(p.format.leftIndent, 0.635) && p.format.firstLineIndent == nil)
        p = para { $0.textIndent = 24 }
        #expect(close(p.format.leftIndent, 0.635))
        p = para { $0.margin = XamlThickness(left: 24, top: 0, right: 0, bottom: 0); $0.textIndent = -12 }
        #expect(close(p.format.leftIndent, 0.635) && close(p.format.firstLineIndent, -0.3175))
        p = para { $0.margin = XamlThickness(left: 48, top: 0, right: 0, bottom: 0); $0.textIndent = 24 }
        #expect(close(p.format.leftIndent, 1.905))
        p = para { $0.margin = XamlThickness(left: 0, top: 0, right: 20, bottom: 0) }
        #expect(close(p.format.rightIndent, 0.529) && p.format.leftIndent == nil)
        p = para { $0.margin = XamlThickness(left: .nan, top: 0, right: .nan, bottom: 0) }
        #expect(p.format.leftIndent == nil && p.format.rightIndent == nil)
    }

    // TV: 11 §7.9
    @Test func highlight() {
        func bg(_ argb: UInt32) -> XamlLocalValues { .pdfWith { $0.background = .solid(argb: argb, opacity: 1, isScRgb: false) } }
        func shading(_ p: PdfX) -> PdfColor? { paras(PdfRichText.blocks(of: PdfX.doc(.section([p]))))[0].format.shading }
        #expect(shading(.p([.r("a", bg(0xFFFF_FF00)), .r("b", bg(0xFFFF_FF00))])) == PdfColor(255, 255, 0))
        #expect(shading(.p([.r("a", bg(0xFFFF_FF00)), .r("b")])) == nil)
        #expect(shading(.p([.r("a", bg(0xFFFF_E699))])) == nil)
        #expect(shading(.p([.r("a", bg(0xFFFF_FF00)), .r("b", bg(0xFF00_FF00))])) == nil)
        #expect(shading(.p([.el(.span, bg(0xFFFF_FF00), [.r("a"), .r("b")])])) == PdfColor(255, 255, 0))
        #expect(shading(.p([.r("a")], bg(0xFFFF_E699))) == PdfColor(255, 230, 153))     // rule (a) has no exclusion
        let empty = paras(PdfRichText.blocks(of: PdfX.doc(.section([.p([])]))))[0]
        #expect(empty.format.shading == nil && empty.plainText == " ")
        #expect(shading(.p([.r("a", bg(0x00FF_FF00))])) == nil)                         // transparent = none
        // (e) list-item paragraphs get no whole-line highlight
        let li = paras(PdfRichText.blocks(of: PdfX.doc(.section([.list("Disc", [[.p([.r("a", bg(0xFFFF_FF00))])]])]))))[0]
        #expect(li.format.shading == nil)
    }

    // TV: 11 §7.8
    @Test func tables() {
        func cell(_ t: String, _ f: (inout XamlLocalValues) -> Void = { _ in }) -> PdfX {
            .el(.tableCell, .pdfWith(f), t.isEmpty ? [] : [.p([.r(t)])])
        }
        func row(_ c: [PdfX]) -> PdfX { .el(.tableRow, XamlLocalValues(), c) }
        func table(cols: [Double?], _ rows: [PdfX]) -> PdfTable? {
            let columns = cols.map { w in PdfX.el(.tableColumn, .pdfWith { $0.width = w }, []) }
            let t = PdfX.el(.table, XamlLocalValues(), columns + [.el(.tableRowGroup, XamlLocalValues(), rows)])
            return PdfRichText.blocks(of: PdfX.doc(.section([t]))).first?.table
        }
        let border: (inout XamlLocalValues) -> Void = {
            $0.borderThickness = XamlThickness(left: 0.6, top: 0.6, right: 0.6, bottom: 0.6)
            $0.borderBrush = .solid(argb: 0xFF9A_A0A6, opacity: 1, isScRgb: false)
        }
        // Editor 3×3 insert.
        let t3 = table(cols: [], (0..<3).map { r in row((0..<3).map { _ in cell(r == 0 ? "H" : "", border) }) })!
        #expect(t3.columns.count == 3 && t3.columns.allSatisfy { abs($0 - 16.0 / 3) < 1e-9 })
        #expect(t3.borders == nil)
        #expect(t3.rows[1].cells[0].borders == .border(PdfBorder(width: 0.6, color: PdfColor(154, 160, 166))))
        #expect(t3.rows[1].cells[0].blocks == [.paragraph(PdfParagraph())])               // empty cell keeps a paragraph
        // Widths.
        func widths(_ c: [Double?], colCount n: Int) -> [Double] { PdfRichText.columnWidthsCm(c, colCount: n) }
        func near(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-3 } }
        #expect(near(widths([96, nil, nil], colCount: 3), [2.54, 6.73, 6.73]))
        #expect(near(widths([480, 480], colCount: 2), [8.0, 8.0]))
        #expect(near(widths([600, nil], colCount: 2), [15.0519, 0.9481]))
        #expect(near(widths([96, 96], colCount: 4), [2.54, 2.54, 5.46, 5.46]))
        // Spans.
        #expect(PdfRichText.trueColumnCount([[(1, 2), (1, 1)], [(1, 1), (1, 1)]]) == 3)
        let spanned = table(cols: [nil, nil], [row([cell("A") { $0.rowSpan = 2 }, cell("B")]), row([cell("C"), cell("D")])])!
        #expect(spanned.columns.count == 3)
        #expect(spanned.rows[0].cells[0].mergeDown == 1)
        #expect(spanned.rows[0].cells[1].blocks.first?.paragraph?.plainText == "B")
        #expect(spanned.rows[1].cells[1].blocks.first?.paragraph?.plainText == "C")
        #expect(spanned.rows[1].cells[2].blocks.first?.paragraph?.plainText == "D")
        let wide = table(cols: [nil, nil], [row([cell("A") { $0.columnSpan = 5 }])])!
        #expect(wide.columns.count == 5 && wide.columns.allSatisfy { abs($0 - 3.2) < 1e-9 })
        #expect(wide.rows[0].cells[0].mergeRight == 4)
        // Borders and shading.
        let b0 = table(cols: [], [row([cell("x") { $0.borderThickness = XamlThickness(left: 0, top: 0, right: 0, bottom: 0) }])])!
        #expect(b0.rows[0].cells[0].borders == PdfCellBorders.none)
        let b2 = table(cols: [], [row([cell("x") { $0.borderThickness = XamlThickness(left: 1, top: 2, right: 1, bottom: 1) }])])!
        #expect(b2.rows[0].cells[0].borders == .border(PdfBorder(width: 2, color: PdfColor(120, 120, 120))))
        let yellow = table(cols: [], [row([cell("x") { $0.background = .solid(argb: 0xFFFF_FF00, opacity: 1, isScRgb: false) }])])!
        #expect(yellow.rows[0].cells[0].shading == PdfColor(255, 255, 0))
        let clear = table(cols: [], [row([cell("x") { $0.background = .solid(argb: 0x00FF_FFFF, opacity: 1, isScRgb: false) }])])!
        #expect(clear.rows[0].cells[0].shading == nil)
        #expect(table(cols: [nil], []) == nil)                                             // 0 rows → nothing
    }

    // DECISIONS 11 Q4 — a table inside a cell is rendered inside the cell
    @Test func nestedTable() {
        let inner = PdfX.el(.table, XamlLocalValues(), [.el(.tableRowGroup, XamlLocalValues(), [
            .el(.tableRow, XamlLocalValues(), [.el(.tableCell, XamlLocalValues(), [.p([.r("inner")])])])])])
        let outer = PdfX.el(.table, XamlLocalValues(), [.el(.tableRowGroup, XamlLocalValues(), [
            .el(.tableRow, XamlLocalValues(), [.el(.tableCell, XamlLocalValues(), [inner])])])])
        let t = PdfRichText.blocks(of: PdfX.doc(.section([outer]))).first?.table
        #expect(t?.rows[0].cells[0].blocks.first?.table?.rows[0].cells[0].blocks.first?.paragraph?.plainText == "inner")
    }

    // TV: 11 §7.2 (targetless link), PDF-071, PDF-073, DEV-02
    @Test func links() {
        let formal = paras(PdfRichText.blocks(of: PdfX.doc(.section([
            .p([.r("Go "), .link("www.imo.org", [.r("IMO"), .el(.span, XamlLocalValues(), [.r(" site")]), .r("!")])]),
        ]))))[0]
        #expect(formal.inlines.count == 2)
        guard case .link(let url, let inner) = formal.inlines[1] else { Issue.record("no link"); return }
        #expect(url == "https://www.imo.org")
        #expect(PdfText.plain(inner) == "IMO site!")                                       // DEV-02: document order
        if case .text(_, let f) = inner[0] { #expect(f.underline == true && f.color == .link) }

        let targetless = paras(PdfRichText.blocks(of: PdfX.doc(.section([
            .p([.link(nil, [.r("see https://a.b now")])]),
        ]))))[0]
        #expect(targetless.inlines.count == 3)
        if case .text(let t, _) = targetless.inlines[0] { #expect(t == "see ") }
        if case .link(let u, let i) = targetless.inlines[1] { #expect(u == "https://a.b" && PdfText.plain(i) == "https://a.b") }
        if case .text(let t, _) = targetless.inlines[2] { #expect(t == " now") }

        let mid = paras(PdfRichText.blocks(of: PdfX.doc(.section([.p([.r("backup_www.tar.gz")])]))))[0]
        #expect(!mid.inlines.contains { if case .link = $0 { return true } else { return false } })

        // A link whose runs are all empty: an empty link element plus the blank-line space.
        let emptyLink = paras(PdfRichText.blocks(of: PdfX.doc(.section([.p([.link("https://a.b", [.r("")])])]))))[0]
        #expect(emptyLink.inlines == [.link(url: "https://a.b", []), .text(" ", PdfCharFormat())])
    }

    // PDF-066/067/068: run formats (strike / underline are the Run's own), line breaks, sizes (×0.75)
    @Test func runFormats() {
        let doc = PdfX.doc(.section([.p([
            .r("struck", .pdfWith { $0.textDecorations = .strikethrough }),
            .br,
            .r("under", .pdfWith { $0.textDecorations = .underline }),
            .el(.underline, XamlLocalValues(), [.r("spanned")]),
            .r("multi\nline"),
        ])]))
        let p = paras(PdfRichText.blocks(of: doc))[0]
        guard case .text("struck", let f1) = p.inlines[0] else { Issue.record("struck"); return }
        #expect(f1.strike == true && f1.underline == nil)
        #expect(p.inlines[1] == .lineBreak)
        guard case .text("under", let f2) = p.inlines[2] else { Issue.record("under"); return }
        #expect(f2.underline == true)
        guard case .text("spanned", let f3) = p.inlines[3] else { Issue.record("spanned"); return }
        #expect(f3.underline == nil)                                                       // DEV-01 parity
        #expect(p.inlines[5] == .lineBreak)
        // Every run carries an explicit bold flag and a size (context 12 px → 9 pt when nothing sets FontSize).
        #expect(f1.bold != nil && f1.size != nil)
    }

    // PDF-060: a placeholder / malformed document never leaks markup
    @Test func neverLeaksMarkup() {
        let xaml = PdfTestData.xaml(["Hello & <world>".replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")])
        let text = paras(PdfRichText.body(xaml, heading: "")).map(\.plainText).joined(separator: "\n")
        #expect(!text.contains("<Section") && !text.contains("<Run"))
        #expect(text.contains("Hello & <world>"))
    }

    // MARK: Post-merge (needs W-RICH's parser and cascade)

    // TV: 11 §7.11 row 2; 05 XD.2.9; 11 §7.10 font sizes
    @Test(.enabled(if: ContractStatus.isImplemented(.wRich)))
    func realParserEditorDocument() {
        let ns = PdfTestData.xmlns
        #expect(PdfRichText.body("<Section xmlns=\"\(ns)\"><Paragraph><Run>  </Run></Paragraph></Section>", heading: "Notes").isEmpty)
        let xaml = "<Section xmlns=\"\(ns)\" xml:space=\"preserve\" FontFamily=\"Consolas\" FontSize=\"14\" Foreground=\"#FF1A1A1A\">"
            + "<Paragraph TextAlignment=\"Center\" Margin=\"24,0,0,0\"><Run FontWeight=\"Bold\" Foreground=\"#FFC00000\">Warn</Run>"
            + "<Run> see </Run><Hyperlink NavigateUri=\"https://www.imo.org/\"><Run>IMO</Run></Hyperlink><LineBreak/>"
            + "<Run TextDecorations=\"Strikethrough\">old</Run></Paragraph>"
            + "<List MarkerStyle=\"Decimal\"><ListItem><Paragraph><Run>one</Run></Paragraph></ListItem></List>"
            + "<Paragraph><Run FontSize=\"16\">big</Run><Run FontSize=\"12pt\">pt</Run><Run FontSize=\"22\">h</Run></Paragraph></Section>"
        let b = paras(PdfRichText.body(xaml, heading: "Notes"))
        #expect(b.first?.plainText == "Notes")
        let p = b[1]
        #expect(p.format.alignment == .center)
        #expect(abs((p.format.leftIndent ?? 0) - 0.635) < 1e-3)
        guard case .text("Warn", let f) = p.inlines[0] else { Issue.record("Warn"); return }
        #expect(f.bold == true && f.color == PdfColor(192, 0, 0) && f.size == 10.5 && f.fontFamily == "Consolas")
        #expect(p.inlines.contains(.link(url: "https://www.imo.org/", [.text("IMO", PdfCharFormat(
            fontFamily: "Consolas", size: 10.5, bold: false, underline: true, color: .link))])))
        #expect(b[2].plainText == "1. one")
        let sizes = b[3].inlines.compactMap { i -> Double? in if case .text(_, let f) = i { return f.size }; return nil }
        #expect(sizes == [12, 12, 16.5])
    }

    // TV: 11 §7.7 row "inside notes of a saved-list item" — `• a` at 1.2 cm
    @Test(.enabled(if: ContractStatus.isImplemented(.wRich)))
    func realParserListUnderContextIndent() {
        let xaml = "<Section xmlns=\"\(PdfTestData.xmlns)\"><List MarkerStyle=\"Disc\"><ListItem><Paragraph><Run>a</Run>"
            + "</Paragraph></ListItem></List></Section>"
        let p = paras(PdfRichText.body(xaml, heading: "", leftIndentCm: 0.6))
        #expect(p.map(\.plainText) == ["\u{2022} a"])
        #expect(abs((p[0].format.leftIndent ?? 0) - 1.2) < 1e-9)
    }

    // TV: 11 §7.6 last row — Margin 24 under a step → 1.235 cm
    @Test(.enabled(if: ContractStatus.isImplemented(.wRich)))
    func realParserMarginUnderStep() {
        let xaml = "<Section xmlns=\"\(PdfTestData.xmlns)\"><Paragraph Margin=\"24,0,0,0\"><Run>x</Run></Paragraph></Section>"
        let p = paras(PdfRichText.body(xaml, heading: "", leftIndentCm: 0.6))
        #expect(abs((p[0].format.leftIndent ?? 0) - 1.235) < 1e-3)
    }
}
