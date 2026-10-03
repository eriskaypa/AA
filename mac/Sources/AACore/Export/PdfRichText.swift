// Spec: 11 §2.6 PDF-060…077 (rich-text fidelity), §3.5 (WriteContainerBody, RenderBlock, ApplyParagraphFormat,
//       RenderInline, AddRun/AddLinkedText, highlight helpers, ApplyStrike → DEV-04, RenderTable, TrueColumnCount,
//       ComputeColumnWidthsCm), §3.4.2 (StripXamlTags), §6.3 (work from the stored XAML through the shared DOM,
//       never NSAttributedString), DEV-02 (document order inside targeted links), DEV-13; 05 CONT-150, CONT-158,
//       CONT-159 (PDF highlight walk), CONT-162 (notLoadable → fallback), XD.2.9 (PDF projection);
//       DECISIONS 11 Q1/Q3 parity (Run-own decorations, partial highlights dropped), Q4 (nested tables rendered),
//       Q5 (legacy `enc:` bodies print "(locked content)").
import Foundation

/// Stored rich text → PdfDOM blocks (product E).
public enum PdfRichText {
    /// RGB(0,102,204): the `linkDefault` colour of a targetless link's children (05 XD.2.9, XD-Q5).
    static let linkDefaultColor = PdfColor(0, 102, 204)
    /// RGB(120,120,120): default cell border colour (PDF-070).
    static let defaultCellBorder = PdfColor(120, 120, 120)
    /// The DECISIONS 11 Q5 placeholder printed for a legacy whole-document `enc:` body.
    public static let lockedContentText = "(locked content)"

    // MARK: WriteContainerBody (11 §3.5.1)

    /// `WriteContainerBody(sec, c, heading, leftIndent)`: nothing for a blank body; otherwise an optional H1
    /// `heading` followed by the rendered body, every top-level paragraph shifted by `leftIndentCm` (PDF-074).
    public static func body(_ xaml: String, heading: String, leftIndentCm: Double? = nil) -> [PdfBlock] {
        guard !NetText.isBlank(xaml) else { return [] }
        var out: [PdfBlock] = []
        if NetText.trim(xaml).hasPrefix("enc:") {
            // DECISIONS 11 Q5: never print a legacy ciphertext.
            if !heading.isEmpty { out.append(.paragraph(PdfParagraph(heading, style: .h1))) }
            out.append(.paragraph(PdfParagraph(lockedContentText)))
        } else if case .success(let doc) = XamlDOM.parse(xaml), !isNotLoadable(doc.loadability) {
            if isBlank(doc) { return [] }
            if !heading.isEmpty { out.append(.paragraph(PdfParagraph(heading, style: .h1))) }
            out.append(contentsOf: blocks(of: doc))
        } else {
            let plain = stripXamlTags(xaml)
            if NetText.isBlank(plain) { return [] }
            if !heading.isEmpty { out.append(.paragraph(PdfParagraph(heading, style: .h1))) }
            for line in plain.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            where !NetText.isBlank(line) {
                out.append(.paragraph(PdfParagraph(line)))            // untrimmed, Normal style
            }
        }
        if let base = leftIndentCm {
            out = out.map { b in
                guard case .paragraph(var p) = b else { return b }
                p.format.leftIndent = base + (p.format.leftIndent ?? 0)
                return .paragraph(p)
            }
        }
        return out
    }

    static func isNotLoadable(_ l: XamlLoadability) -> Bool {
        if case .notLoadable = l { return true }
        return false
    }

    // MARK: StripXamlTags (11 §3.4.2, exact)

    public static func stripXamlTags(_ xaml: String) -> String {
        guard !xaml.isEmpty else { return "" }
        var out: [UInt16] = []
        out.reserveCapacity(xaml.utf16.count)
        var inTag = false
        for u in xaml.utf16 {
            if u == 0x3C { inTag = true; continue }                       // <
            if u == 0x3E { inTag = false; out.append(0x20); continue }    // > → a space for every '>'
            if !inTag { out.append(u) }
        }
        return NetText.trim(SvcHtmlEntities.decode(String(decoding: out, as: UTF16.self)))
    }

    // MARK: DOM path

    /// "No Run/Hyperlink text contains a non-whitespace character" (11 §3.5.1).
    static func isBlank(_ doc: XamlDocument) -> Bool {
        var stack = [doc.root]
        while let id = stack.popLast() {
            let n = doc[id]
            switch n.kind {
            case .run, .text:
                if !NetText.isBlank(runText(n, doc)) { return false }
            default:
                stack.append(contentsOf: n.children)
            }
        }
        return true
    }

    static func runText(_ n: XamlNode, _ doc: XamlDocument) -> String {
        if let t = n.text { return t }
        var s = ""
        for c in n.children where doc[c].kind == .text { s += doc[c].text ?? "" }
        return s
    }

    /// Renders the document's blocks (the root wrapper is transparent, 11 §3.5.1 load semantics).
    public static func blocks(of doc: XamlDocument) -> [PdfBlock] {
        let ctx = Ctx(doc: doc, resolver: XamlStyleResolver(doc, context: .pdf))
        var out: [PdfBlock] = []
        let root = doc[doc.root]
        switch root.kind {
        case .paragraph, .list, .table:
            ctx.renderBlock(&out, doc.root, 0)
        default:
            for c in root.children { ctx.renderBlock(&out, c, 0) }
        }
        return out
    }

    /// Solid colour with alpha ≠ 0 (PDF-077); opacity and alpha otherwise ignored.
    static func solid(_ b: XamlBrush?) -> PdfColor? {
        guard case .solid(let argb, _, _)? = b, (argb >> 24) != 0 else { return nil }
        return PdfColor(UInt8((argb >> 16) & 0xFF), UInt8((argb >> 8) & 0xFF), UInt8(argb & 0xFF))
    }

    /// The element's own Background: the attribute, else a `X.Background` property element (CONT-154).
    static func ownBackground(_ n: XamlNode) -> XamlBrush? {
        if let b = n.local.background { return b }
        return n.propertyElements.first { $0.propertyName == "Background" }?.brush
    }

    private struct Ctx {
        let doc: XamlDocument
        let resolver: XamlStyleResolver

        func node(_ id: XamlNodeID) -> XamlNode { doc[id] }

        // MARK: RenderBlock (11 §3.5.2)

        func renderBlock(_ target: inout [PdfBlock], _ id: XamlNodeID, _ listLevelCm: Double) {
            let n = node(id)
            switch n.kind {
            case .paragraph:
                var par = PdfParagraph()
                applyParagraphFormat(&par, n, id)
                if let hi = uniformInlineBackground(id) { par.format.shading = hi }
                var any = false
                for c in n.children { any = renderInline(&par.inlines, c) || any }
                if !any { par.inlines.append(.text(" ", PdfCharFormat())) }
                target.append(.paragraph(par))
            case .list:
                let marker = NetText.toLowerInvariant(n.local.markerStyle ?? "Disc")
                let numbered = !["none", "disc", "box", "circle", "square"].contains(marker)
                let levelLeft = 0.6 + listLevelCm
                var idx = 1
                for li in n.children where node(li).kind == .listItem {
                    for b in node(li).children {
                        let bn = node(b)
                        switch bn.kind {
                        case .paragraph:
                            var par = PdfParagraph()
                            applyParagraphFormat(&par, bn, b)
                            par.format.leftIndent = levelLeft
                            par.format.firstLineIndent = -0.4
                            par.inlines.append(.text(numbered ? "\(idx). " : "\u{2022} ", PdfCharFormat()))
                            if numbered { idx += 1 }
                            for c in bn.children { _ = renderInline(&par.inlines, c) }
                            target.append(.paragraph(par))
                        case .list:
                            renderBlock(&target, b, listLevelCm + 0.6)
                        default:
                            renderBlock(&target, b, listLevelCm)
                        }
                    }
                }
            case .table:
                if let t = renderTable(id) { target.append(.table(t)) }
            case .section:
                for c in n.children { renderBlock(&target, c, listLevelCm) }
            default:
                break                                                   // BlockUIContainer, unknown → dropped
            }
        }

        // MARK: ApplyParagraphFormat (11 §3.5.3)

        func applyParagraphFormat(_ par: inout PdfParagraph, _ n: XamlNode, _ id: XamlNodeID) {
            switch resolver.computed(id).textAlignment {
            case .center: par.format.alignment = .center
            case .right: par.format.alignment = .right
            case .justify: par.format.alignment = .justify
            case .left: par.format.alignment = .left
            }
            if let bg = PdfRichText.solid(PdfRichText.ownBackground(n)) { par.format.shading = bg }
            let k = PdfUnits.cmPerPx
            let margin = n.local.margin
            func val(_ d: Double?) -> Double { guard let d, d.isFinite else { return 0 }; return d }
            var leftCm = val(margin?.left) > 0 ? val(margin?.left) * k : 0
            var firstCm = 0.0
            let ti = val(n.local.textIndent)
            if ti > 0 { leftCm += ti * k } else if ti < 0 { firstCm = ti * k }
            if leftCm > 0 { par.format.leftIndent = leftCm }
            if firstCm != 0 { par.format.firstLineIndent = firstCm }
            if val(margin?.right) > 0 { par.format.rightIndent = val(margin?.right) * k }
        }

        // MARK: RenderInline (11 §3.5.4) — Hyperlink before Span

        func renderInline(_ out: inout [PdfInline], _ id: XamlNodeID) -> Bool {
            let n = node(id)
            switch n.kind {
            case .run, .text:
                let text = PdfRichText.runText(n, doc)
                if text.isEmpty { return false }
                return addRunAutoLinked(&out, id, text)
            case .lineBreak:
                out.append(.lineBreak)
                return true
            case .hyperlink:
                guard let uri = PdfLinkScanner.normalizeLinkUri(n.local.navigateUri) else {
                    var any = false
                    for c in n.children { any = renderInline(&out, c) || any }     // PDF-072
                    return any
                }
                // DEV-02: every text descendant, in document order, is part of the link (no auto-scan inside).
                var inner: [PdfInline] = []
                let any = addLinkedDescendants(&inner, n.children)
                out.append(.link(url: uri, inner))
                return any
            case .span, .bold, .italic, .underline:
                var any = false
                for c in n.children { any = renderInline(&out, c) || any }
                return any
            default:
                return false                                            // InlineUIContainer, Figure, Floater, …
            }
        }

        func addLinkedDescendants(_ out: inout [PdfInline], _ ids: [XamlNodeID]) -> Bool {
            var any = false
            for id in ids {
                let n = node(id)
                switch n.kind {
                case .run, .text:
                    let t = PdfRichText.runText(n, doc)
                    if !t.isEmpty { out.append(contentsOf: PdfText.inlines(t, linkedFormat(id))); any = true }
                case .lineBreak:
                    out.append(.lineBreak); any = true
                case .hyperlink, .span, .bold, .italic, .underline:
                    any = addLinkedDescendants(&out, n.children) || any
                default:
                    break
                }
            }
            return any
        }

        // MARK: AddRun / AddLinkedText (11 §3.5.5, XD.2.9)

        func runFormat(_ id: XamlNodeID) -> PdfCharFormat {
            let cs = resolver.computed(id)
            let own = node(id).local.textDecorations ?? []
            var f = PdfCharFormat()
            f.bold = cs.fontWeight >= 600                                       // NotBold is explicit
            if cs.fontStyle == .italic || cs.fontStyle == .oblique { f.italic = true }
            if own.contains(.underline) { f.underline = true }                  // the Run's OWN value (DEV-01)
            if own.contains(.strikethrough) { f.strike = true }                 // DEV-04
            switch cs.foreground {
            case .solid(let argb, _, _) where (argb >> 24) != 0:
                f.color = PdfColor(UInt8((argb >> 16) & 0xFF), UInt8((argb >> 8) & 0xFF), UInt8(argb & 0xFF))
            case .linkDefault:
                f.color = PdfRichText.linkDefaultColor
            default:
                break
            }
            f.fontFamily = cs.fontFamily.raw
            if cs.fontSize > 0 { f.size = cs.fontSize * 0.75 }
            return f
        }

        func linkedFormat(_ id: XamlNodeID) -> PdfCharFormat {
            var f = runFormat(id)
            f.underline = true
            f.color = .link
            return f
        }

        /// `AddRunAutoLinked` (11 §3.5.11): bare URLs / e-mails of this run become links.
        func addRunAutoLinked(_ out: inout [PdfInline], _ id: XamlNodeID, _ text: String) -> Bool {
            var any = false
            for seg in PdfLinkScanner.scan(text) where !seg.text.isEmpty {
                if let uri = seg.uri {
                    out.append(.link(url: uri, PdfText.inlines(seg.text, linkedFormat(id))))
                } else {
                    out.append(contentsOf: PdfText.inlines(seg.text, runFormat(id)))
                }
                any = true
            }
            return any
        }

        // MARK: Highlight helpers (11 §3.5.6)

        /// `EffectiveBackground`: the run, then its ancestors, stopping after the Paragraph; first non-nil brush.
        func effectiveBackground(_ run: XamlNodeID) -> XamlBrush? {
            var cur: XamlNodeID? = run
            while let id = cur {
                let n = node(id)
                if let b = PdfRichText.ownBackground(n) { return b }
                if n.kind == .paragraph || id == doc.root { break }
                cur = n.parent
            }
            return nil
        }

        func enumRuns(_ ids: [XamlNodeID], _ out: inout [XamlNodeID]) {
            for id in ids {
                switch node(id).kind {
                case .run, .text: out.append(id)
                case .span, .bold, .italic, .underline, .hyperlink: enumRuns(node(id).children, &out)
                default: break
                }
            }
        }

        func uniformInlineBackground(_ paragraph: XamlNodeID) -> PdfColor? {
            var runs: [XamlNodeID] = []
            enumRuns(node(paragraph).children, &runs)
            var found: PdfColor?
            var anyText = false
            for r in runs where !PdfRichText.runText(node(r), doc).isEmpty {
                anyText = true
                guard let c = PdfRichText.solid(effectiveBackground(r)) else { return nil }
                if let f = found { if f != c { return nil } } else { found = c }
            }
            guard anyText, let fc = found else { return nil }
            if fc == .lockSentinel { return nil }                       // RGB compare only (CONT-159)
            return fc
        }

        // MARK: Tables (11 §3.5.8–3.5.10)

        func renderTable(_ id: XamlNodeID) -> PdfTable? {
            let t = node(id)
            var rows: [XamlNodeID] = []
            var columns: [XamlNodeID] = []
            for c in t.children {
                switch node(c).kind {
                case .tableRowGroup: rows.append(contentsOf: node(c).children.filter { node($0).kind == .tableRow })
                case .tableColumn: columns.append(c)
                default: break
                }
            }
            if rows.isEmpty { return nil }
            let cellsPerRow: [[XamlNodeID]] = rows.map { r in node(r).children.filter { node($0).kind == .tableCell } }
            let spans: [[(cs: Int, rs: Int)]] = cellsPerRow.map { cells in
                cells.map { (max(1, node($0).local.columnSpan ?? 1), max(1, node($0).local.rowSpan ?? 1)) }
            }
            var colCount = max(columns.count, PdfRichText.trueColumnCount(spans))
            if colCount < 1 { colCount = 1 }
            let widthsPx: [Double?] = columns.map { node($0).local.width }
            let widths = PdfRichText.columnWidthsCm(widthsPx, colCount: colCount, totalCm: 16.0)
            var table = PdfTable(columns: widths, borders: nil, padding: .migraDocDefault,
                                 rows: Array(repeating: PdfRow(cells: Array(repeating: PdfCell(), count: colCount)),
                                             count: rows.count))
            var occupied = Array(repeating: Array(repeating: false, count: colCount), count: rows.count)
            for r in rows.indices {
                var col = 0
                for (k, wc) in cellsPerRow[r].enumerated() {
                    while col < colCount && occupied[r][col] { col += 1 }
                    if col >= colCount { break }
                    let cs = min(max(1, spans[r][k].cs), colCount - col)
                    let rs = min(max(1, spans[r][k].rs), rows.count - r)
                    var cell = PdfCell(mergeRight: cs - 1, mergeDown: rs - 1)
                    let cn = node(wc)
                    if let th = cn.local.borderThickness {
                        let w = max(max(th.left, th.right), max(th.top, th.bottom))
                        if w.isFinite && w > 0 {
                            cell.borders = .border(PdfBorder(width: w, color: PdfRichText.solid(cn.local.borderBrush)
                                                             ?? PdfRichText.defaultCellBorder))
                        } else {
                            cell.borders = .none
                        }
                    } else {
                        cell.borders = .none
                    }
                    if let bg = PdfRichText.solid(PdfRichText.ownBackground(cn)) { cell.shading = bg }
                    if resolver.computed(wc).fontWeight >= 600 { cell.format.bold = true }
                    var content: [PdfBlock] = []
                    for b in cn.children { renderBlock(&content, b, 0) }
                    if content.isEmpty { content = [.paragraph(PdfParagraph())] }
                    cell.blocks = content
                    table.rows[r].cells[col] = cell
                    for dr in 0..<rs { for dc in 0..<cs { occupied[r + dr][col + dc] = true } }
                    col += cs
                }
            }
            return table
        }
    }

    /// `TrueColumnCount` over (ColumnSpan, RowSpan) per cell, row by row (11 §3.5.9; unbounded grid).
    public static func trueColumnCount(_ rows: [[(cs: Int, rs: Int)]]) -> Int {
        var occupied = Set<[Int]>()
        var maxCol = 0
        for (r, cells) in rows.enumerated() {
            var col = 0
            for c in cells {
                while occupied.contains([r, col]) { col += 1 }
                let cs = max(1, c.cs), rs = max(1, c.rs)
                for dr in 0..<rs { for dc in 0..<cs { occupied.insert([r + dr, col + dc]) } }
                col += cs
                maxCol = max(maxCol, col)
            }
        }
        return maxCol
    }

    /// `ComputeColumnWidthsCm` (11 §3.5.10): `widthsPx[c]` = the absolute px width of `Table.Columns[c]`
    /// (nil / NaN / ≤ 0 = not absolute).
    public static func columnWidthsCm(_ widthsPx: [Double?], colCount: Int, totalCm: Double = 16.0) -> [Double] {
        var w = Array(repeating: 0.0, count: colCount)
        var anyAbs = false
        for c in 0..<min(colCount, widthsPx.count) {
            if let v = widthsPx[c], v.isFinite, v > 0 { w[c] = v * PdfUnits.cmPerPx; anyAbs = true }
        }
        if !anyAbs { return Array(repeating: totalCm / Double(colCount), count: colCount) }
        let known = w.filter { $0 > 0 }.reduce(0, +)
        let missing = w.filter { $0 <= 0 }.count
        let each = missing > 0 ? max(1.0, (totalCm - known) / Double(missing)) : 0
        for c in 0..<colCount where w[c] <= 0 { w[c] = each }
        let tot = w.reduce(0, +)
        if tot > totalCm { let k = totalCm / tot; w = w.map { $0 * k } }
        return w
    }
}

/// The DEV-04 strike predicate (11 §3.5.7): a character is struck unless its first UTF-16 unit is whitespace
/// (.NET `char.IsWhiteSpace`) or a control character (`Cc`).
public enum PdfStrike {
    public static func strikes(_ ch: Character) -> Bool {
        guard let first = String(ch).utf16.first else { return false }
        if NetText.isWhiteSpace(first) { return false }
        if first < 0x20 || (first >= 0x7F && first <= 0x9F) { return false }
        return true
    }

    /// The Windows reference output (U+0336 after each struck code point) — used only by tests to pin the
    /// predicate to the Windows behaviour.
    public static func windowsApplyStrike(_ text: String) -> String {
        let u = Array(text.utf16)
        var out: [UInt16] = []
        var i = 0
        while i < u.count {
            let n = (UTF16.isLeadSurrogate(u[i]) && i + 1 < u.count && UTF16.isTrailSurrogate(u[i + 1])) ? 2 : 1
            out.append(contentsOf: u[i..<(i + n)])
            let c = u[i]
            let control = c < 0x20 || (c >= 0x7F && c <= 0x9F)
            if !control && !NetText.isWhiteSpace(c) { out.append(0x0336) }
            i += n
        }
        return String(decoding: out, as: UTF16.self)
    }
}
