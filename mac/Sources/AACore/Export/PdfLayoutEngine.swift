// Spec: 11 §6.1 "Engine rules" (CoreText measurement and line breaking, tabs every 1.25 cm from the paragraph's
//       left edge, line height = multiple × (ascent + descent + leading), top-down pagination, two passes for the
//       page count), §3.2 (MigraDoc behaviours: space-before suppressed at a page top, max-collapse of spacing,
//       KeepWithNext chains, widow/orphan control of 2 lines, row-atomic tables, merged rows kept together,
//       HeadingFormat rows repeated, paragraph shading between the indents, H1 bottom border), PDF-100,
//       DEV-04 (native strike on the predicate's characters), DEV-07 (CoreText cascade), DEV-08 (a row taller than
//       a page is split at line boundaries), DECISIONS 11 Q4 (nested tables).
import CoreGraphics
import CoreText
import Foundation

// MARK: - Display list

/// One drawing operation in top-down page coordinates (origin = top-left of the page or of a slice).
enum PdfDrawOp {
    /// A CoreText line drawn with its baseline origin at the point.
    case line(CTLine, CGPoint)
    case fill(CGRect, PdfColor)
    case stroke(CGPoint, CGPoint, CGFloat, PdfColor)
    case link(CGRect, URL)

    func offset(_ dx: CGFloat, _ dy: CGFloat) -> PdfDrawOp {
        switch self {
        case .line(let l, let p): return .line(l, CGPoint(x: p.x + dx, y: p.y + dy))
        case .fill(let r, let c): return .fill(r.offsetBy(dx: dx, dy: dy), c)
        case .stroke(let a, let b, let w, let c):
            return .stroke(CGPoint(x: a.x + dx, y: a.y + dy), CGPoint(x: b.x + dx, y: b.y + dy), w, c)
        case .link(let r, let u): return .link(r.offsetBy(dx: dx, dy: dy), u)
        }
    }

    /// Drawing layer: fills under text, borders over everything.
    var layer: Int {
        switch self {
        case .fill: return 0
        case .line, .link: return 1
        case .stroke: return 2
        }
    }
}

/// A vertical atom of the flow: one paragraph line, one spacer, or one table row group.
struct PdfSlice {
    var height: CGFloat
    var ops: [PdfDrawOp]
    static func spacer(_ h: CGFloat) -> PdfSlice { PdfSlice(height: h, ops: []) }
}

/// A laid-out paragraph: its lines plus the spacing/pagination attributes MigraDoc honours.
struct PdfParaLayout {
    var spaceBefore: CGFloat
    var spaceAfter: CGFloat
    var keepWithNext: Bool
    var widowControl: Bool
    var lines: [PdfSlice]
    var height: CGFloat { lines.reduce(0) { $0 + $1.height } }
}

/// One cell's laid-out content inside a table (positions relative to the table's left edge).
struct PdfCellBox {
    var row: Int, rowSpan: Int
    var x: CGFloat, width: CGFloat
    var content: [PdfSlice]
    var contentHeight: CGFloat
    var shading: PdfColor?
    var border: PdfBorder?
}

/// Rows linked by MergeDown, kept together on one page (§3.2 rule 8).
struct PdfRowGroup {
    var firstRow: Int
    var rowHeights: [CGFloat]
    var boxes: [PdfCellBox]
    var isHeading: Bool
    var padding: PdfPadding
    var height: CGFloat { rowHeights.reduce(0, +) }
}

struct PdfTableFlow {
    var groups: [PdfRowGroup]
    /// Leading HeadingFormat groups, repeated at the top of every continuation page.
    var headingGroups: Int
    /// Left shift so cell text aligns with body text (MigraDoc places the border outside by the left padding).
    var xOffset: CGFloat
    var headingHeight: CGFloat { groups.prefix(headingGroups).reduce(0) { $0 + $1.height } }
}

enum PdfFlowItem {
    case para(PdfParaLayout)
    case table(PdfTableFlow)
}

/// The result of laying out one document: per-page display lists (body, header and footer included).
struct PdfLaidDocument {
    var pageSize: CGSize
    var pages: [[PdfDrawOp]]
}

// MARK: - Engine

/// Lays a `PdfDoc` out on A4 pages (one pass for the body; header and footer per page once the total is known).
final class PdfLayoutEngine {
    let doc: PdfDoc
    let resolver: PdfFontResolver
    let fonts: PdfFontCache
    let pageSize = CGSize(width: PdfUnits.a4Width, height: PdfUnits.a4Height)

    private var resolvedFamilies: [String: PdfResolvedFont] = [:]

    init(doc: PdfDoc, resolver: PdfFontResolver = .system) {
        self.doc = doc
        self.resolver = resolver
        self.fonts = PdfFontCache(resolver: resolver)
    }

    static func pt(_ cm: Double) -> CGFloat { CGFloat(PdfUnits.pt(cm: cm)) }

    var contentLeft: CGFloat { Self.pt(doc.pageSetup.left) }
    var contentTop: CGFloat { Self.pt(doc.pageSetup.top) }
    var contentWidth: CGFloat { pageSize.width - Self.pt(doc.pageSetup.left) - Self.pt(doc.pageSetup.right) }
    var contentHeight: CGFloat { pageSize.height - Self.pt(doc.pageSetup.top) - Self.pt(doc.pageSetup.bottom) }

    // MARK: Whole document

    func layout() -> PdfLaidDocument {
        let items = flowItems(doc.body, width: contentWidth, cellFormat: nil)
        var pages = PdfPaginator(height: contentHeight).paginate(items)
        if pages.isEmpty { pages = [[]] }
        let total = pages.count
        var out: [[PdfDrawOp]] = []
        for (i, body) in pages.enumerated() {
            var ops = body.map { $0.offset(contentLeft, contentTop) }
            ops += headerFooterOps(page: i + 1, of: total)
            out.append(ops.sorted { $0.layer < $1.layer })
        }
        return PdfLaidDocument(pageSize: pageSize, pages: out)
    }

    /// Header paragraphs from `HeaderDistance` down; footer paragraphs ending at `FooterDistance` from the bottom.
    func headerFooterOps(page: Int, of total: Int) -> [PdfDrawOp] {
        var ops: [PdfDrawOp] = []
        var y = Self.pt(doc.pageSetup.headerDistance)
        for p in doc.header {
            let l = layoutParagraph(p, width: contentWidth, cellFormat: nil, page: (page, total))
            for line in l.lines { ops += line.ops.map { $0.offset(contentLeft, y) }; y += line.height }
        }
        let footers = doc.footer.map { layoutParagraph($0, width: contentWidth, cellFormat: nil, page: (page, total)) }
        var fy = pageSize.height - Self.pt(doc.pageSetup.footerDistance) - footers.reduce(0) { $0 + $1.height }
        for l in footers {
            for line in l.lines { ops += line.ops.map { $0.offset(contentLeft, fy) }; fy += line.height }
        }
        return ops
    }

    // MARK: Blocks → flow items

    func flowItems(_ blocks: [PdfBlock], width: CGFloat, cellFormat: PdfCharFormat?,
                   overflow: CGFloat = 0) -> [PdfFlowItem] {
        blocks.map { b in
            switch b {
            case .paragraph(let p):
                return .para(layoutParagraph(p, width: width, cellFormat: cellFormat, page: nil, overflow: overflow))
            case .table(let t): return .table(layoutTable(t))
            }
        }
    }

    /// Cell content as a flat list of slices (first SpaceBefore suppressed, max-collapsed gaps, last SpaceAfter
    /// kept), so a too-tall row can be split at line boundaries (DEV-08).
    func cellSlices(_ blocks: [PdfBlock], width: CGFloat, cellFormat: PdfCharFormat, overflow: CGFloat) -> [PdfSlice] {
        var out: [PdfSlice] = []
        var pendingAfter: CGFloat = 0
        var first = true
        for item in flowItems(blocks, width: width, cellFormat: cellFormat, overflow: overflow) {
            switch item {
            case .para(let p):
                let gap = first ? 0 : max(pendingAfter, p.spaceBefore)
                if gap > 0 { out.append(.spacer(gap)) }
                out += p.lines
                pendingAfter = p.spaceAfter
            case .table(let t):
                if !first && pendingAfter > 0 { out.append(.spacer(pendingAfter)) }
                for g in t.groups { out.append(PdfGroupRenderer.slice(g, xOffset: t.xOffset)) }
                pendingAfter = 0
            }
            first = false
        }
        if pendingAfter > 0 { out.append(.spacer(pendingAfter)) }
        return out
    }

    // MARK: Paragraphs

    private struct EffParagraph {
        var style: PdfStyle
        var base: PdfCharFormat
        var left: CGFloat, first: CGFloat, right: CGFloat
        var alignment: PdfAlignment
        var shading: PdfColor?
    }

    func family(_ raw: String) -> PdfResolvedFont {
        if let f = resolvedFamilies[raw] { return f }
        let f = resolver.resolveFont(raw)
        resolvedFamilies[raw] = f
        return f
    }

    /// The CoreText face for a fully resolved format; a substitute is drawn at `size × scale` (DECISIONS 11 Q2).
    func face(_ f: PdfCharFormat) -> PdfFontFace {
        let r = family(f.fontFamily ?? "Calibri")
        return fonts.face(family: r.family, size: (f.size ?? 11) * r.scale, bold: f.bold ?? false, italic: f.italic ?? false)
    }

    /// `overflow` = how far a single unbreakable word may run past the available width before it is broken
    /// by character (table cells: into the right padding, never past the border; body text: 0).
    func layoutParagraph(_ p: PdfParagraph, width: CGFloat, cellFormat: PdfCharFormat?,
                         page: (Int, Int)?, overflow: CGFloat = 0) -> PdfParaLayout {
        let style = doc.styles[p.style]
        var base = style.charFormat
        if let cf = cellFormat { base = base.overlaid(cf) }
        base = base.overlaid(p.format.font)
        let eff = EffParagraph(
            style: style, base: base,
            left: Self.pt(p.format.leftIndent ?? style.leftIndent),
            first: Self.pt(p.format.firstLineIndent ?? style.firstLineIndent),
            right: Self.pt(p.format.rightIndent ?? style.rightIndent),
            alignment: p.format.alignment ?? style.alignment,
            shading: p.format.shading)
        let attr = attributed(p, eff, page: page)
        // Line height follows the requested font's size: undo the substitute's metric scale (DECISIONS 11 Q2).
        let baseScale = CGFloat(family(base.fontFamily ?? "Calibri").scale)
        var lines = layoutLines(attr, eff, width: width, tabStops: p.format.tabStops,
                                lineSpacing: CGFloat(style.lineSpacing) / max(0.5, baseScale), overflow: overflow)
        if let border = style.bottomBorder, !lines.isEmpty {
            // §3.2 rule 9: drawn at the paragraph's bottom edge, from the left to the right indent.
            let w = CGFloat(border.width)
            var last = lines.removeLast()
            let y = last.height + w / 2
            last.ops.append(.stroke(CGPoint(x: eff.left, y: y), CGPoint(x: width - eff.right, y: y), w, border.color))
            last.height += w
            lines.append(last)
        }
        return PdfParaLayout(spaceBefore: CGFloat(p.format.spaceBefore ?? style.spaceBefore),
                             spaceAfter: CGFloat(p.format.spaceAfter ?? style.spaceAfter),
                             keepWithNext: p.format.keepWithNext ?? style.keepWithNext,
                             widowControl: style.widowControl, lines: lines)
    }

    // MARK: Attributed text

    private func attributes(_ f: PdfCharFormat, link: String?) -> [NSAttributedString.Key: Any] {
        let fc = face(f)
        let color = f.color ?? .black
        var a: [NSAttributedString.Key: Any] = [
            PdfAttr.ctFont: fc.font,
            PdfAttr.ctColor: Self.cgColor(color),
            PdfAttr.color: color,
        ]
        if fc.syntheticBold {
            a[PdfAttr.ctStrokeWidth] = -3.0 as CGFloat
            a[PdfAttr.ctStrokeColor] = Self.cgColor(color)
        }
        if f.underline == true { a[PdfAttr.underline] = true }
        if let link { a[PdfAttr.link] = link }
        return a
    }

    private func attributed(_ p: PdfParagraph, _ eff: EffParagraph, page: (Int, Int)?) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        func append(_ s: String, _ f: PdfCharFormat, _ link: String?) {
            let attrs = attributes(f, link: link)
            if f.strike == true {
                // DEV-04: strike exactly the characters Windows overlays (not whitespace/control).
                var run = ""
                var runStruck: Bool?
                func flush() {
                    guard !run.isEmpty else { return }
                    var a = attrs
                    if runStruck == true { a[PdfAttr.strike] = true }
                    out.append(NSAttributedString(string: run, attributes: a))
                    run = ""
                }
                for ch in s {
                    let st = PdfStrike.strikes(ch)
                    if runStruck != st { flush(); runStruck = st }
                    run.append(ch)
                }
                flush()
            } else {
                out.append(NSAttributedString(string: s, attributes: attrs))
            }
        }
        func walk(_ inlines: [PdfInline], _ link: String?) {
            for i in inlines {
                switch i {
                case .text(let s, let f): append(s, eff.base.overlaid(f), link)
                case .lineBreak: append("\u{2028}", eff.base, link)
                case .tab: append("\t", eff.base, link)
                case .pageField(let f): append(String(page?.0 ?? 0), eff.base.overlaid(f), link)
                case .numPagesField(let f): append(String(page?.1 ?? 0), eff.base.overlaid(f), link)
                case .link(let url, let inner): walk(inner, url)
                }
            }
        }
        walk(p.inlines, nil)
        // Tabs: explicit stops plus default stops every 1.25 cm (none for Header/Footer, §3.2 rule 2).
        return out
    }

    // MARK: Line breaking

    private func layoutLines(_ attr: NSMutableAttributedString, _ eff: EffParagraph, width: CGFloat,
                             tabStops: [PdfTabStop], lineSpacing: CGFloat, overflow: CGFloat) -> [PdfSlice] {
        let tabs: [CTTextTab] = tabStops.map {
            CTTextTabCreate($0.alignment == .right ? .right : .left, Double(Self.pt($0.positionCm)), nil)
        }
        var interval = CGFloat(Self.pt(eff.style.defaultTabStopsCm ?? 1.25))
        var tabArray = tabs as CFArray
        let paraStyle: CTParagraphStyle = withUnsafePointer(to: &tabArray) { tp in
            withUnsafePointer(to: &interval) { ip in
                let settings = [
                    CTParagraphStyleSetting(spec: .tabStops, valueSize: MemoryLayout<CFArray>.size, value: tp),
                    CTParagraphStyleSetting(spec: .defaultTabInterval, valueSize: MemoryLayout<CGFloat>.size, value: ip),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
        if attr.length > 0 {
            attr.addAttribute(PdfAttr.ctParagraphStyle, value: paraStyle, range: NSRange(location: 0, length: attr.length))
        }
        let baseFont = face(eff.base).font
        let ns = attr.string as NSString
        // Split at hard line breaks (U+2028) into segments; first-line indent applies to the very first line only.
        var segments: [NSRange] = []
        var start = 0
        for i in 0..<ns.length where ns.character(at: i) == 0x2028 {
            segments.append(NSRange(location: start, length: i - start))
            start = i + 1
        }
        segments.append(NSRange(location: start, length: ns.length - start))

        var lines: [PdfSlice] = []
        var firstLine = true
        for seg in segments {
            if seg.length == 0 {
                lines.append(emptyLine(baseFont, eff, width: width, lineSpacing: lineSpacing))
                firstLine = false
                continue
            }
            let sub = attr.attributedSubstring(from: seg)
            let ts = CTTypesetterCreateWithAttributedString(sub as CFAttributedString)
            var pos = 0
            let len = sub.length
            while pos < len {
                let indent = eff.left + (firstLine ? eff.first : 0)
                let avail = max(1, width - indent - eff.right)
                let offset = Double(firstLine ? eff.first : 0)
                var count = CTTypesetterSuggestLineBreakWithOffset(ts, pos, Double(avail), offset)
                if count <= 0 { count = max(1, CTTypesetterSuggestClusterBreakWithOffset(ts, pos, Double(avail), offset)) }
                if overflow > 0 { count = wholeWord(ts, sub.string as NSString, pos, count, avail + overflow, offset) }
                let line = CTTypesetterCreateLineWithOffset(ts, CFRange(location: pos, length: count), offset)
                let isLastOfSegment = pos + count >= len
                lines.append(placeLine(line, indent: indent, avail: avail, eff: eff, width: width,
                                       lineSpacing: lineSpacing, justify: eff.alignment == .justify && !isLastOfSegment))
                pos += count
                firstLine = false
            }
        }
        if lines.isEmpty { lines.append(emptyLine(baseFont, eff, width: width, lineSpacing: lineSpacing)) }
        return lines
    }

    /// When CoreText broke inside a word (the line holds no whitespace and the next character is not whitespace),
    /// keep the whole word on the line if it fits within `limit`.
    private func wholeWord(_ ts: CTTypesetter, _ s: NSString, _ pos: Int, _ count: Int, _ limit: CGFloat,
                           _ offset: Double) -> Int {
        let end = pos + count
        guard end < s.length else { return count }
        func isSpace(_ i: Int) -> Bool { NetText.isWhiteSpace(s.character(at: i)) }
        if isSpace(end) || isSpace(end - 1) { return count }
        for i in pos..<end where isSpace(i) { return count }
        var wordEnd = end
        while wordEnd < s.length && !isSpace(wordEnd) { wordEnd += 1 }
        let line = CTTypesetterCreateLineWithOffset(ts, CFRange(location: pos, length: wordEnd - pos), offset)
        let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return w <= limit ? wordEnd - pos : count
    }

    private func emptyLine(_ font: CTFont, _ eff: EffParagraph, width: CGFloat, lineSpacing: CGFloat) -> PdfSlice {
        let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        let h = natural * lineSpacing
        var ops: [PdfDrawOp] = []
        if let s = eff.shading { ops.append(.fill(CGRect(x: eff.left, y: 0, width: width - eff.left - eff.right, height: h), s)) }
        return PdfSlice(height: h, ops: ops)
    }

    private func placeLine(_ rawLine: CTLine, indent: CGFloat, avail: CGFloat, eff: EffParagraph, width: CGFloat,
                           lineSpacing: CGFloat, justify: Bool) -> PdfSlice {
        var line = rawLine
        if justify, let j = CTLineCreateJustifiedLine(rawLine, 1.0, Double(avail)) { line = j }
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let trailing = CGFloat(CTLineGetTrailingWhitespaceWidth(line))
        let visible = lineWidth - trailing
        let natural = ascent + descent + leading
        let h = natural * lineSpacing
        let baseline = (h - natural) + ascent
        var x = indent
        switch eff.alignment {
        case .center: x += max(0, (avail - visible) / 2)
        case .right: x += max(0, avail - visible)
        case .left, .justify: break
        }
        var ops: [PdfDrawOp] = []
        if let s = eff.shading {
            ops.append(.fill(CGRect(x: eff.left, y: 0, width: width - eff.left - eff.right, height: h), s))
        }
        ops.append(.line(line, CGPoint(x: x, y: baseline)))
        ops += decorations(line, origin: CGPoint(x: x, y: baseline), ascent: ascent, descent: descent)
        return PdfSlice(height: h, ops: ops)
    }

    /// Underline / strike strokes and link rectangles for each glyph run of a line (CoreText draws neither).
    private func decorations(_ line: CTLine, origin: CGPoint, ascent: CGFloat, descent: CGFloat) -> [PdfDrawOp] {
        var ops: [PdfDrawOp] = []
        var linkRect: CGRect?
        var linkTarget: String?
        func flushLink() {
            if let r = linkRect, let t = linkTarget, let url = PdfLinkScanner.annotationURL(t) { ops.append(.link(r, url)) }
            linkRect = nil; linkTarget = nil
        }
        let runs = (CTLineGetGlyphRuns(line) as? [CTRun]) ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attrs = CTRunGetAttributes(run) as NSDictionary
            var pos = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &pos)
            let w = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil))
            let x0 = origin.x + pos.x
            let color = (attrs[PdfAttr.color.rawValue] as? PdfColor) ?? .black
            let runFont = attrs[PdfAttr.ctFont.rawValue].map { $0 as! CTFont }
            let thickness = max(0.5, runFont.map { CTFontGetUnderlineThickness($0) } ?? 0.75)
            if (attrs[PdfAttr.underline.rawValue] as? Bool) == true {
                let upos = runFont.map { CTFontGetUnderlinePosition($0) } ?? -1.5
                let y = origin.y - upos + thickness / 2
                ops.append(.stroke(CGPoint(x: x0, y: y), CGPoint(x: x0 + w, y: y), thickness, color))
            }
            if (attrs[PdfAttr.strike.rawValue] as? Bool) == true {
                let xh = runFont.map { CTFontGetXHeight($0) } ?? 5
                let y = origin.y - xh * 0.55
                ops.append(.stroke(CGPoint(x: x0, y: y), CGPoint(x: x0 + w, y: y), thickness, color))
            }
            let link = attrs[PdfAttr.link.rawValue] as? String
            let rect = CGRect(x: x0, y: origin.y - ascent, width: w, height: ascent + descent)
            if let link {
                if link == linkTarget, let r = linkRect, abs(r.maxX - rect.minX) < 1 {
                    linkRect = r.union(rect)
                } else {
                    flushLink(); linkRect = rect; linkTarget = link
                }
            } else {
                flushLink()
            }
        }
        flushLink()
        return ops
    }

    static func cgColor(_ c: PdfColor) -> CGColor {
        CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }

    // MARK: Tables

    func layoutTable(_ t: PdfTable) -> PdfTableFlow {
        let cols = t.columns.map { Self.pt($0) }
        var colX: [CGFloat] = [0]
        for w in cols { colX.append(colX.last! + w) }
        let nRows = t.rows.count, nCols = cols.count
        var covered = Array(repeating: Array(repeating: false, count: nCols), count: nRows)
        var boxes: [PdfCellBox] = []
        let pad = t.padding
        for r in 0..<nRows {
            let row = t.rows[r]
            for c in 0..<nCols where !covered[r][c] {
                let cell = c < row.cells.count ? row.cells[c] : PdfCell()
                let cs = max(1, min(cell.mergeRight + 1, nCols - c))
                let rs = max(1, min(cell.mergeDown + 1, nRows - r))
                for dr in 0..<rs { for dc in 0..<cs { covered[r + dr][c + dc] = true } }
                let width = colX[c + cs] - colX[c]
                let inner = max(1, width - CGFloat(pad.left) - CGFloat(pad.right))
                let content = cellSlices(cell.blocks, width: inner, cellFormat: cell.format,
                                         overflow: CGFloat(pad.right))
                let border: PdfBorder?
                switch cell.borders {
                case .inherit: border = t.borders
                case .none: border = nil
                case .border(let b): border = b
                }
                boxes.append(PdfCellBox(row: r, rowSpan: rs, x: colX[c], width: width, content: content,
                                        contentHeight: content.reduce(0) { $0 + $1.height },
                                        shading: cell.shading ?? row.shading,
                                        border: (border?.width ?? 0) > 0 ? border : nil))
            }
        }
        var heights = Array(repeating: CGFloat(0), count: nRows)
        let padV = CGFloat(pad.top + pad.bottom)
        for b in boxes where b.rowSpan == 1 { heights[b.row] = max(heights[b.row], b.contentHeight + padV) }
        for b in boxes where b.rowSpan > 1 {
            let need = b.contentHeight + padV
            let have = heights[b.row..<(b.row + b.rowSpan)].reduce(0, +)
            if need > have { heights[b.row + b.rowSpan - 1] += need - have }
        }
        // Groups of rows linked by MergeDown.
        var groups: [PdfRowGroup] = []
        var r = 0
        while r < nRows {
            var end = r
            var k = r
            while k <= end {
                for b in boxes where b.row == k { end = max(end, b.row + b.rowSpan - 1) }
                k += 1
            }
            let gb = boxes.filter { $0.row >= r && $0.row <= end }
            let heading = (r...end).allSatisfy { t.rows[$0].headingFormat }
            groups.append(PdfRowGroup(firstRow: r, rowHeights: Array(heights[r...end]), boxes: gb, isHeading: heading,
                                      padding: pad))
            r = end + 1
        }
        let headingCount = groups.prefix { $0.isHeading }.count
        return PdfTableFlow(groups: groups, headingGroups: headingCount, xOffset: -CGFloat(pad.left))
    }

}

/// Draws table row groups (no engine state needed once the cells are laid out).
enum PdfGroupRenderer {
    /// One row group drawn as a slice (cell fills, contents, borders).
    static func slice(_ g: PdfRowGroup, xOffset: CGFloat) -> PdfSlice {
        var rowTop: [CGFloat] = [0]
        for h in g.rowHeights { rowTop.append(rowTop.last! + h) }
        var fills: [PdfDrawOp] = [], content: [PdfDrawOp] = [], strokes: [PdfDrawOp] = []
        for b in g.boxes {
            let top = rowTop[b.row - g.firstRow]
            let bottom = rowTop[min(b.row - g.firstRow + b.rowSpan, g.rowHeights.count)]
            let rect = CGRect(x: b.x + xOffset, y: top, width: b.width, height: bottom - top)
            cellOps(b, rect: rect, slices: b.content, padding: g.padding, fills: &fills, content: &content, strokes: &strokes)
        }
        return PdfSlice(height: g.height, ops: fills + content + strokes)
    }

    static func cellOps(_ b: PdfCellBox, rect: CGRect, slices: [PdfSlice], padding: PdfPadding,
                 fills: inout [PdfDrawOp], content: inout [PdfDrawOp], strokes: inout [PdfDrawOp]) {
        if let s = b.shading { fills.append(.fill(rect, s)) }
        var y = rect.minY + CGFloat(padding.top)
        for s in slices {
            content += s.ops.map { $0.offset(rect.minX + CGFloat(padding.left), y) }
            y += s.height
        }
        if let br = b.border {
            let w = CGFloat(br.width)
            strokes.append(.stroke(CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), w, br.color))
            strokes.append(.stroke(CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY), w, br.color))
            strokes.append(.stroke(CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), w, br.color))
            strokes.append(.stroke(CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), w, br.color))
        }
    }

    /// DEV-08: a group taller than a page is cut into chunks at slice (line) boundaries; `first` is the space
    /// left on the current page, `full` the space on a fresh page (after repeated heading rows).
    static func split(_ g: PdfRowGroup, xOffset: CGFloat, first: CGFloat, full: CGFloat) -> [PdfSlice] {
        var remaining = g.boxes.map { $0.content[...] }
        var out: [PdfSlice] = []
        var avail = first
        let padV = CGFloat(g.padding.top + g.padding.bottom)
        while remaining.contains(where: { !$0.isEmpty }) {
            var taken: [[PdfSlice]] = Array(repeating: [], count: g.boxes.count)
            var used: CGFloat = 0
            var progressed = false
            for i in g.boxes.indices {
                var h: CGFloat = 0
                while let s = remaining[i].first, h + s.height + padV <= avail {
                    taken[i].append(s); h += s.height; remaining[i] = remaining[i].dropFirst(); progressed = true
                }
                used = max(used, h)
            }
            if !progressed {
                if let i = remaining.firstIndex(where: { !$0.isEmpty }), let s = remaining[i].first {
                    taken[i].append(s); remaining[i] = remaining[i].dropFirst(); used = max(used, s.height)
                }
            }
            let height = used + padV
            var fills: [PdfDrawOp] = [], content: [PdfDrawOp] = [], strokes: [PdfDrawOp] = []
            for (i, b) in g.boxes.enumerated() {
                let rect = CGRect(x: b.x + xOffset, y: 0, width: b.width, height: height)
                cellOps(b, rect: rect, slices: taken[i], padding: g.padding, fills: &fills, content: &content, strokes: &strokes)
            }
            out.append(PdfSlice(height: height, ops: fills + content + strokes))
            avail = full
        }
        return out
    }
}

/// Attribute keys of the layout's attributed strings (CoreText keys plus the engine's own markers).
enum PdfAttr {
    static let ctFont = NSAttributedString.Key(kCTFontAttributeName as String)
    static let ctColor = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    static let ctStrokeWidth = NSAttributedString.Key(kCTStrokeWidthAttributeName as String)
    static let ctStrokeColor = NSAttributedString.Key(kCTStrokeColorAttributeName as String)
    static let ctParagraphStyle = NSAttributedString.Key(kCTParagraphStyleAttributeName as String)
    static let color = NSAttributedString.Key("aa.pdf.color")
    static let underline = NSAttributedString.Key("aa.pdf.underline")
    static let strike = NSAttributedString.Key("aa.pdf.strike")
    static let link = NSAttributedString.Key("aa.pdf.link")
}

// MARK: - Pagination

/// Top-down pagination with the MigraDoc rules of 11 §3.2 / PDF-100.
struct PdfPaginator {
    let height: CGFloat

    private struct State {
        var pages: [[PdfDrawOp]] = [[]]
        var y: CGFloat = 0
        var atTop = true
        var pendingAfter: CGFloat = 0

        mutating func newPage() { pages.append([]); y = 0; atTop = true; pendingAfter = 0 }
        mutating func place(_ s: PdfSlice, dx: CGFloat = 0) {
            pages[pages.count - 1] += s.ops.map { $0.offset(dx, y) }
            y += s.height
            atTop = false
        }
    }

    func paginate(_ items: [PdfFlowItem]) -> [[PdfDrawOp]] {
        var st = State()
        for (idx, item) in items.enumerated() {
            switch item {
            case .para(let p): placeParagraph(p, index: idx, items: items, &st)
            case .table(let t): placeTable(t, &st)
            }
        }
        return st.pages
    }

    /// Height needed below a KeepWithNext element: the following KWN elements in full, then the first line / first
    /// row group of the next non-KWN element (§3.2 rule 7).
    private func chainHeight(after index: Int, items: [PdfFlowItem], previousAfter: CGFloat) -> CGFloat {
        var h: CGFloat = 0
        var after = previousAfter
        var j = index + 1
        while j < items.count {
            switch items[j] {
            case .para(let p):
                h += max(after, p.spaceBefore)
                if p.keepWithNext { h += p.height; after = p.spaceAfter; j += 1; continue }
                h += p.lines.first?.height ?? 0
                return h
            case .table(let t):
                h += after
                let firstBody = t.groups.dropFirst(t.headingGroups).first?.height ?? 0
                return h + t.headingHeight + firstBody
            }
        }
        return h
    }

    private func placeParagraph(_ p: PdfParaLayout, index: Int, items: [PdfFlowItem], _ st: inout State) {
        var gap = st.atTop ? 0 : max(st.pendingAfter, p.spaceBefore)
        if p.keepWithNext && !st.atTop {
            let need = gap + p.height + chainHeight(after: index, items: items, previousAfter: p.spaceAfter)
            if st.y + need > height + 0.01 && need <= height { st.newPage(); gap = 0 }
        }
        if !st.atTop { st.y += gap }
        let n = p.lines.count
        var i = 0
        while i < n {
            let avail = height - st.y
            var k = 0
            var acc: CGFloat = 0
            while i + k < n, acc + p.lines[i + k].height <= avail + 0.01 { acc += p.lines[i + k].height; k += 1 }
            if k < n - i {
                // Widow/orphan control: ≥ 2 lines at each end of a split paragraph.
                if p.widowControl {
                    let remaining = n - i
                    if remaining - k < 2 { k = max(0, remaining - 2) }
                    if i == 0 && k < 2 { k = 0 }
                }
                if k == 0 && st.atTop { k = 1 }                               // a line taller than the page
                if k == 0 { st.newPage(); continue }
            }
            for line in p.lines[i..<(i + k)] { st.place(line) }
            i += k
            if i < n { st.newPage() }
        }
        st.pendingAfter = p.spaceAfter
    }

    private func placeTable(_ t: PdfTableFlow, _ st: inout State) {
        if !st.atTop { st.y += st.pendingAfter }
        let headings = Array(t.groups.prefix(t.headingGroups))
        let headingHeight = t.headingHeight
        // Keep the heading rows with the first body group.
        let firstBody = t.groups.dropFirst(t.headingGroups).first?.height ?? 0
        if !st.atTop && st.y + headingHeight + min(firstBody, height - headingHeight) > height + 0.01 {
            st.newPage()
        }
        let engineSlice = { (g: PdfRowGroup) -> PdfSlice in PdfGroupRenderer.slice(g, xOffset: t.xOffset) }
        for (gi, g) in t.groups.enumerated() {
            let isLeadingHeading = gi < t.headingGroups
            if st.y + g.height <= height + 0.01 {
                st.place(engineSlice(g))
                continue
            }
            if isLeadingHeading && st.atTop {
                st.place(engineSlice(g))                                      // taller than the page: overflow
                continue
            }
            let fullAvail = height - (isLeadingHeading ? 0 : headingHeight)
            if g.height > fullAvail {
                // DEV-08: split at line boundaries, starting on this page when something useful fits.
                var first = height - st.y
                if first < 24 { st.newPage(); if !isLeadingHeading { for h in headings { st.place(engineSlice(h)) } }
                    first = height - st.y }
                let chunks = PdfGroupRenderer.split(g, xOffset: t.xOffset, first: first, full: fullAvail)
                for (ci, c) in chunks.enumerated() {
                    if ci > 0 {
                        st.newPage()
                        if !isLeadingHeading { for h in headings { st.place(engineSlice(h)) } }
                    }
                    st.place(c)
                }
                continue
            }
            st.newPage()
            if !isLeadingHeading { for h in headings { st.place(engineSlice(h)) } }
            st.place(engineSlice(g))
        }
        st.pendingAfter = 0
    }
}
