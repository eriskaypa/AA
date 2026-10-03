// Spec: 05 §6.4 "Paragraph" (TextAlignment → alignment; Margin.Left (+ list/section indents) → headIndent and
//       firstLineHeadIndent (+ TextIndent); Margin.Right → tailIndent; Margin.Top/Bottom → spacing with WPF margin
//       collapse `max(prevBottom, top)`; LineHeight → min/max line height; block Background/Padding/BorderThickness/
//       BorderBrush → NSTextBlock), "Lists" (MarkerStyle → NSTextList.MarkerFormat with WPF punctuation, StartIndex,
//       level content at List Padding.Left beyond the list's own left edge, marker in the hanging area as TextKit 1
//       `\t{marker}\t` text tagged `.aaListMarker`, continuation paragraphs), "Tables" (NSTextTable, NSTextTableBlock
//       spans, per-edge borders/padding, backgrounds, column widths, collapsesBorders when CellSpacing = 0),
//       §6.2 (paragraph spacing ≈ one line for Auto margins), 12 §6.5 (SIRE chips as NSTextBlock), §3.2 (IndentStep).
// One renderer for the reader and the list engine, so a normalised document looks the same however it was produced.
import AppKit

@MainActor
final class RichRenderer {
    private let out = NSMutableAttributedString()
    private var records: [Rec] = []
    private var usedIDs: Set<String> = []
    private var pendingTop: CGFloat = 0
    private var resetNext = true
    private var prevBottomOverride: CGFloat?

    /// WPF's default list padding (an un-normalised list, "≈ 49 px").
    static let defaultListPadding: CGFloat = 49

    private struct Rec {
        var range: NSRange
        var head: CGFloat = 0, first: CGFloat = 0, tail: CGFloat = 0
        var topValue: CGFloat?, bottomValue: CGFloat?
        var pendingTop: CGFloat = 0
        var autoLine: CGFloat = 16
        var resetBefore = false, endsCell = false
        var prevBottomOverride: CGFloat?
        var tabs: [NSTextTab]?
        var lists: [NSTextList] = []
        var blocks: [NSTextBlock] = []
        var ownBlock: XamlParagraphBlock?
        var alignment: NSTextAlignment = .natural
        var direction: NSWritingDirection = .natural
        var minLineHeight: CGFloat = 0, maxLineHeight: CGFloat = 0
        var hyphenation: Float = 0
    }

    private struct Ctx {
        var path: [RichContainerInfo] = []
        var sectionPath: [String] = []
        var rowGroup: String?
        var itemID: String?
        var indent: CGFloat = 0, tail: CGFloat = 0
        var blocks: [NSTextBlock] = []
        var lists: [NSTextList] = []
    }

    /// Renders a block tree into attributed text; every paragraph is terminated by `\n`.
    static func render(_ doc: RichDoc) -> NSMutableAttributedString {
        let r = RichRenderer()
        var ctx = Ctx()
        r.walk(doc.blocks, &ctx)
        r.finish()
        return r.out
    }

    // MARK: - Walk

    private func uniqueID(_ info: inout RichContainerInfo) {
        if info.id.isEmpty || usedIDs.contains(info.id) { info.id = RichIDs.fresh() }
        usedIDs.insert(info.id)
    }

    private func walk(_ nodes: [RichNode], _ ctx: inout Ctx) {
        for node in nodes {
            switch node {
            case .para(let p): emit(p, ctx, marker: nil, continuation: ctx.itemID != nil)
            case .container(let c): container(c, ctx)
            }
        }
    }

    private func container(_ c: RichContainer, _ ctx: Ctx) {
        uniqueID(&c.info)
        switch c.info.kind {
        case .section: section(c, ctx)
        case .list: list(c, ctx)
        case .table: table(c, ctx)
        case .listItem, .rowGroup, .row, .cell:                   // misplaced (grammar repaired by the builder)
            var child = ctx
            child.path.append(c.info)
            walk(c.children, &child)
        }
    }

    private static func thickness(_ s: String?) -> XamlThickness? { s.flatMap(XamlValues.parseThickness) }
    private static func fin(_ v: Double?) -> CGFloat { guard let v, v.isFinite else { return 0 }; return CGFloat(v) }

    private func section(_ c: RichContainer, _ ctx: Ctx) {
        var child = ctx
        child.path.append(c.info)
        child.sectionPath.append(c.info.id)
        let m = Self.thickness(c.info.carriedValue("Margin"))
        let pad = Self.thickness(c.info.carriedValue("Padding"))
        let bt = Self.thickness(c.info.carriedValue("BorderThickness"))
        let bg = c.info.carriedValue("Background").flatMap(XamlValues.parseBrush)
        let bb = c.info.carriedValue("BorderBrush").flatMap(XamlValues.parseBrush)
        let start = records.count
        if Self.needsBlock(bg: bg, border: bt, padding: pad) {
            let b = XamlContainerBlock()
            Self.style(b, margin: m, indent: ctx.indent, tail: ctx.tail, border: bt, borderBrush: bb, padding: pad,
                       background: bg)
            child.blocks.append(b)
            child.indent = 0; child.tail = 0
        } else {
            child.indent += Self.fin(m?.left); child.tail += Self.fin(m?.right)
            pendingTop = max(pendingTop, Self.fin(m?.top))
        }
        walk(c.children, &child)
        if records.count > start, bg == nil, !Self.needsBlock(bg: bg, border: bt, padding: pad) {
            let b = Self.fin(m?.bottom)
            records[records.count - 1].bottomValue = max(records[records.count - 1].bottomValue ?? 0, b)
        }
    }

    private static func needsBlock(bg: XamlBrush?, border: XamlThickness?, padding: XamlThickness?) -> Bool {
        if case .solid? = bg { return true }
        let any: (XamlThickness?) -> Bool = { t in
            guard let t else { return false }
            return [t.left, t.top, t.right, t.bottom].contains { $0.isFinite && $0 > 0 }
        }
        return any(border) || any(padding)
    }

    private static func style(_ b: NSTextBlock, margin m: XamlThickness?, indent: CGFloat, tail: CGFloat,
                              border: XamlThickness?, borderBrush: XamlBrush?, padding: XamlThickness?,
                              background: XamlBrush?) {
        b.setWidth(indent + fin(m?.left), type: .absoluteValueType, for: .margin, edge: .minX)
        b.setWidth(tail + fin(m?.right), type: .absoluteValueType, for: .margin, edge: .maxX)
        b.setWidth(fin(m?.top), type: .absoluteValueType, for: .margin, edge: .minY)
        b.setWidth(fin(m?.bottom), type: .absoluteValueType, for: .margin, edge: .maxY)
        applyEdges(b, border: border, borderBrush: borderBrush, padding: padding, background: background)
    }

    private static func applyEdges(_ b: NSTextBlock, border: XamlThickness?, borderBrush: XamlBrush?,
                                   padding: XamlThickness?, background: XamlBrush?) {
        if let t = border {
            for (edge, v) in [(NSRectEdge.minX, t.left), (.minY, t.top), (.maxX, t.right), (.maxY, t.bottom)] {
                b.setWidth(fin(v), type: .absoluteValueType, for: .border, edge: edge)
            }
            if case .solid(let argb, let op, _)? = borderBrush {
                b.setBorderColor(RichColor.color(argb, opacity: op))
            } else {
                b.setBorderColor(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            }
        }
        if let t = padding {
            for (edge, v) in [(NSRectEdge.minX, t.left), (.minY, t.top), (.maxX, t.right), (.maxY, t.bottom)] {
                b.setWidth(fin(v), type: .absoluteValueType, for: .padding, edge: edge)
            }
        }
        if case .solid(let argb, let op, _)? = background { b.backgroundColor = RichColor.color(argb, opacity: op) }
    }

    /// `List.MarkerStyle` → TextKit marker format with the WPF punctuation (05 §6.4).
    static func markerFormat(_ style: String) -> NSTextList.MarkerFormat? {
        switch style {
        case "Disc": return .disc
        case "Circle": return .circle
        case "Square": return .square
        case "Box": return .box
        case "Decimal": return NSTextList.MarkerFormat("{decimal}.")
        case "LowerLatin": return NSTextList.MarkerFormat("{lower-alpha}.")
        case "UpperLatin": return NSTextList.MarkerFormat("{upper-alpha}.")
        case "LowerRoman": return NSTextList.MarkerFormat("{lower-roman}.")
        case "UpperRoman": return NSTextList.MarkerFormat("{upper-roman}.")
        default: return nil
        }
    }

    private func list(_ c: RichContainer, _ ctx: Ctx) {
        let style = c.info.model["MarkerStyle"] ?? "Disc"
        let start = Int(c.info.model["StartIndex"] ?? "") ?? 1
        let m = Self.thickness(c.info.model["Margin"])
        let pad = Self.thickness(c.info.model["Padding"])
        let padLeft = pad.map { Self.fin($0.left) } ?? Self.defaultListPadding
        let listLeft = ctx.indent + Self.fin(m?.left)
        let contentIndent = listLeft + padLeft
        let format = Self.markerFormat(style)
        let nsList = NSTextList(markerFormat: format ?? NSTextList.MarkerFormat(""), options: 0)
        nsList.startingItemNumber = start
        var child = ctx
        child.path.append(c.info)
        child.lists.append(nsList)
        child.indent = contentIndent
        child.tail = ctx.tail + Self.fin(m?.right)
        if case .solid? = c.info.carriedValue("Background").flatMap(XamlValues.parseBrush) {
            let b = XamlContainerBlock()
            Self.style(b, margin: m, indent: ctx.indent, tail: ctx.tail, border: nil, borderBrush: nil, padding: nil,
                       background: c.info.carriedValue("Background").flatMap(XamlValues.parseBrush))
            child.blocks.append(b)
            child.indent = padLeft
            child.tail = 0
        }
        let markerLeft = child.blocks.count > ctx.blocks.count ? 0 : listLeft
        pendingTop = max(pendingTop, Self.fin(m?.top))
        let startRec = records.count
        var number = start
        for node in c.children {
            guard case .container(let item) = node, item.info.kind == .listItem else {
                var tmp = child
                walk([node], &tmp)
                continue
            }
            uniqueID(&item.info)
            var ic = child
            ic.path.append(item.info)
            ic.itemID = item.info.id
            let im = Self.thickness(item.info.carriedValue("Margin"))
            let ip = Self.thickness(item.info.carriedValue("Padding"))
            ic.indent += Self.fin(im?.left) + Self.fin(ip?.left)
            ic.tail += Self.fin(im?.right) + Self.fin(ip?.right)
            let markerText = format.map { _ in nsList.marker(forItemNumber: number) }
            for (k, n) in item.children.enumerated() {
                if k == 0, case .para(let p) = n {
                    emit(p, ic, marker: (markerText, markerLeft), continuation: false)
                } else {
                    var tmp = ic
                    walk([n], &tmp)
                }
            }
            number += 1
        }
        if records.count > startRec {
            records[records.count - 1].bottomValue = max(records[records.count - 1].bottomValue ?? 0, Self.fin(m?.bottom))
        }
    }

    private func table(_ c: RichContainer, _ ctx: Ctx) {
        let spacing = Double(c.info.model["CellSpacing"] ?? "") ?? 2
        let m = Self.thickness(c.info.model["Margin"])
        // Rows in order, through every row group.
        var rows: [(group: RichContainer, row: RichContainer)] = []
        var strays: [RichNode] = []
        for g in c.children {
            guard case .container(let gc) = g, gc.info.kind == .rowGroup else { strays.append(g); continue }
            uniqueID(&gc.info)
            for r in gc.children {
                if case .container(let rc) = r, rc.info.kind == .row { uniqueID(&rc.info); rows.append((gc, rc)) }
            }
        }
        // Grid placement (row spans occupy following rows).
        var occupied: [[Bool]] = []
        var placements: [(cell: RichContainer, row: Int, col: Int, rs: Int, cs: Int)] = []
        for (ri, entry) in rows.enumerated() {
            for n in entry.row.children {
                guard case .container(let cell) = n, cell.info.kind == .cell else { continue }
                let cs = max(1, Int(cell.info.model["ColumnSpan"] ?? "") ?? 1)
                let rs = max(1, Int(cell.info.model["RowSpan"] ?? "") ?? 1)
                while occupied.count < ri + rs { occupied.append([]) }
                var col = 0
                while col < occupied[ri].count, occupied[ri][col] { col += 1 }
                for r in ri..<(ri + rs) {
                    while occupied[r].count < col + cs { occupied[r].append(false) }
                    for k in col..<(col + cs) { occupied[r][k] = true }
                }
                placements.append((cell, ri, col, rs, cs))
            }
        }
        let declared = Int(c.info.model["Columns"] ?? "") ?? 0
        let columns = max(1, declared, occupied.map(\.count).max() ?? 0)
        let t = NSTextTable()
        t.numberOfColumns = columns
        t.collapsesBorders = spacing == 0
        t.hidesEmptyCells = false
        t.setWidth(ctx.indent + Self.fin(m?.left), type: .absoluteValueType, for: .margin, edge: .minX)
        t.setWidth(ctx.tail + Self.fin(m?.right), type: .absoluteValueType, for: .margin, edge: .maxX)
        t.setWidth(Self.fin(m?.top), type: .absoluteValueType, for: .margin, edge: .minY)
        t.setWidth(Self.fin(m?.bottom), type: .absoluteValueType, for: .margin, edge: .maxY)
        t.setValue(100, type: .percentageValueType, for: .width)
        let widths = (0..<columns).map { XamlGridLength.parse(c.info.model["Col\($0).Width"] ?? "*") ?? .star(1) }
        let starTotal = widths.reduce(0.0) { s, w in
            switch w { case .star(let v): return s + v; case .auto: return s + 1; case .pixel: return s }
        }
        let allRelative = widths.allSatisfy { if case .pixel = $0 { return false }; return true }
        let allPixel = widths.allSatisfy { if case .pixel = $0 { return true }; return false }
        var tablePath = ctx.path
        tablePath.append(c.info)
        for p in placements {
            let block = NSTextTableBlock(table: t, startingRow: p.row, rowSpan: p.rs, startingColumn: p.col,
                                         columnSpan: p.cs)
            let entry = rows[p.row]
            let model = p.cell.info.model
            let bg = (model["Background"] ?? entry.row.info.carriedValue("Background")
                      ?? entry.group.info.carriedValue("Background")).flatMap(XamlValues.parseBrush)
            Self.applyEdges(block, border: Self.thickness(model["BorderThickness"]),
                            borderBrush: model["BorderBrush"].flatMap(XamlValues.parseBrush),
                            padding: Self.thickness(model["Padding"]), background: bg)
            if spacing > 0 {
                for e in [NSRectEdge.minX, .minY, .maxX, .maxY] {
                    block.setWidth(CGFloat(spacing / 2), type: .absoluteValueType, for: .margin, edge: e)
                }
            }
            if allRelative, starTotal > 0 {
                var share = 0.0
                for k in p.col..<min(columns, p.col + p.cs) {
                    switch widths[k] { case .star(let v): share += v; case .auto: share += 1; default: break }
                }
                block.setValue(CGFloat(share / starTotal * 100), type: .percentageValueType, for: .width)
            } else if allPixel {
                var w = 0.0
                for k in p.col..<min(columns, p.col + p.cs) { if case .pixel(let v) = widths[k] { w += v } }
                block.setValue(CGFloat(w), type: .absoluteValueType, for: .width)
            }
            var cc = ctx
            cc.path = tablePath + [entry.group.info, entry.row.info]
            uniqueID(&p.cell.info)
            cc.path.append(p.cell.info)
            cc.rowGroup = entry.group.info.id
            cc.itemID = nil
            cc.lists = []
            cc.blocks = ctx.blocks + [block]
            cc.indent = 0; cc.tail = 0
            resetNext = true
            pendingTop = 0
            let before = records.count
            walk(p.cell.children, &cc)
            if records.count > before { records[records.count - 1].endsCell = true }
        }
        resetNext = false
        pendingTop = 0
        prevBottomOverride = Self.fin(m?.bottom)
        var sc = ctx
        walk(strays, &sc)
    }

    // MARK: - Paragraphs

    private static func autoLine(_ font: NSFont?) -> CGFloat {
        guard let f = font else { return 16 }
        return ceil(f.ascender - f.descender + f.leading)
    }

    private func emit(_ p: RichPara, _ ctx: Ctx, marker: (text: String?, left: CGFloat)?, continuation: Bool) {
        let start = out.length
        p.newStart = start
        let model = p.model
        let m = Self.thickness(model["Margin"])
        let textIndent = CGFloat(Double(model["TextIndent"] ?? "") ?? 0)
        var rec = Rec(range: NSRange(location: start, length: 0))
        rec.alignment = p.alignment
        rec.direction = p.direction
        rec.lists = ctx.lists
        rec.blocks = ctx.blocks
        let termFont = p.terminator[.font] as? NSFont
        rec.autoLine = Self.autoLine(termFont)
        if let t = m?.top, t.isFinite { rec.topValue = CGFloat(t) }
        if let b = m?.bottom, b.isFinite { rec.bottomValue = CGFloat(b) }
        rec.pendingTop = pendingTop
        pendingTop = 0
        rec.resetBefore = resetNext
        resetNext = false
        rec.prevBottomOverride = prevBottomOverride
        prevBottomOverride = nil
        if let lh = Double(model["c.LineHeight"] ?? ""), lh.isFinite, lh > 0 {
            rec.minLineHeight = CGFloat(lh)
            if model["c.LineStackingStrategy"] == "BlockLineHeight" { rec.maxLineHeight = CGFloat(lh) }
        } else if let mlh = p.minimumLineHeight, mlh > 0, model["c.LineHeight"] == nil {
            rec.minLineHeight = mlh
        }
        rec.hyphenation = model["c.IsHyphenationEnabled"] == "True" ? 0.9 : 0
        let pad = Self.thickness(model["Padding"]), bt = Self.thickness(model["BorderThickness"])
        let bg = model["Background"].flatMap(XamlValues.parseBrush)
        if Self.needsBlock(bg: bg, border: bt, padding: pad) {
            let b = XamlParagraphBlock()
            b.setWidth(ctx.indent + Self.fin(m?.left), type: .absoluteValueType, for: .margin, edge: .minX)
            b.setWidth(ctx.tail + Self.fin(m?.right), type: .absoluteValueType, for: .margin, edge: .maxX)
            Self.applyEdges(b, border: bt, borderBrush: model["BorderBrush"].flatMap(XamlValues.parseBrush),
                            padding: pad, background: bg)
            rec.ownBlock = b
            rec.blocks.append(b)
            rec.head = 0; rec.first = textIndent; rec.tail = 0
        } else {
            rec.head = ctx.indent + Self.fin(m?.left)
            rec.first = rec.head + textIndent
            rec.tail = ctx.tail + Self.fin(m?.right)
        }
        // Text: marker, content, terminator.
        let base = p.content.length > 0 ? p.content.attributes(at: 0, effectiveRange: nil) : p.terminator
        if let mk = marker {
            rec.first = mk.left
            let markerRight = max(mk.left + 1, rec.head - 6)
            rec.tabs = [NSTextTab(textAlignment: .right, location: markerRight, options: [:]),
                        NSTextTab(textAlignment: .left, location: rec.head, options: [:])]
            if let text = mk.text {
                var ma: [NSAttributedString.Key: Any] = [:]
                ma[.font] = base[.font] ?? p.terminator[.font]
                ma[.foregroundColor] = (base[.aaLinkStyled] as? Bool == true ? base[.aaUnderlyingForeground] : nil)
                    ?? base[.foregroundColor] ?? p.terminator[.foregroundColor]
                ma[.aaFontFamilyName] = base[.aaFontFamilyName]
                ma[.aaListMarker] = text
                out.append(NSAttributedString(string: "\t" + text + "\t", attributes: ma))
            }
        }
        p.newContentStart = out.length
        if p.content.length > 0 { out.append(p.content) }
        var term = p.terminator
        for k in RichParagraphKeys.all { term[k] = nil }
        out.append(NSAttributedString(string: "\n", attributes: term))
        let range = NSRange(location: start, length: out.length - start)
        rec.range = range
        // Paragraph-level keys on every character.
        for k in RichParagraphKeys.all where k != .aaListMarker && k != .paragraphStyle {
            out.removeAttribute(k, range: range)
        }
        var pa: [NSAttributedString.Key: Any] = [:]
        if !p.carried.isEmpty { pa[.aaParagraphAttrs] = RichAttributeCoding.encode(p.carried) }
        if !model.isEmpty { pa[.richParagraphModel] = model }
        if !ctx.path.isEmpty { pa[.richContainerPath] = ctx.path.map(\.plist) }
        if !ctx.sectionPath.isEmpty { pa[.aaSectionPath] = ctx.sectionPath }
        if let id = ctx.itemID {
            pa[.aaListItemID] = id
            if continuation { pa[.aaListContinuation] = true }
        }
        if let g = ctx.rowGroup { pa[.aaTableRowGroup] = g }
        if !pa.isEmpty { out.addAttributes(pa, range: range) }
        records.append(rec)
    }

    // MARK: - Spacing and paragraph styles

    private func finish() {
        var prevBottom: CGFloat = 0
        for r in records {
            if r.resetBefore { prevBottom = 0 }
            if let o = r.prevBottomOverride { prevBottom = o }
            let top = max(r.topValue ?? (r.resetBefore ? 0 : r.autoLine), r.pendingTop)
            let before = max(0, top - prevBottom)
            let after = r.bottomValue ?? (r.endsCell ? 0 : r.autoLine)
            prevBottom = after
            let ps = NSMutableParagraphStyle()
            ps.alignment = r.alignment
            ps.baseWritingDirection = r.direction
            ps.headIndent = r.head
            ps.firstLineHeadIndent = r.first
            ps.tailIndent = r.tail > 0 ? -r.tail : 0
            if let b = r.ownBlock {
                b.setWidth(before, type: .absoluteValueType, for: .margin, edge: .minY)
                b.setWidth(after, type: .absoluteValueType, for: .margin, edge: .maxY)
            } else {
                ps.paragraphSpacingBefore = before
                ps.paragraphSpacing = after
            }
            ps.minimumLineHeight = r.minLineHeight
            ps.maximumLineHeight = r.maxLineHeight
            ps.hyphenationFactor = r.hyphenation
            ps.textLists = r.lists
            ps.textBlocks = r.blocks
            if let tabs = r.tabs { ps.tabStops = tabs; ps.defaultTabInterval = 28 }
            out.addAttribute(.paragraphStyle, value: ps.copy(), range: r.range)
        }
    }
}
