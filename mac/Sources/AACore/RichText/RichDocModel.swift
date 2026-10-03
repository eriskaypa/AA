// Spec: 05 §4.3.7 rules 5–7 (paragraphs, lists, tables as the writer sees them), §6.4 (lists/tables/sections in the
//       attributed string), CONT-163 (flattened / modelled / carried attributes; paragraph identity = the first
//       character), §6.5 (list structure kept through edits).
// The block tree that sits between an `NSAttributedString` and XAML. The reader builds it from the DOM and renders it
// (RichDocRender); the writer and the list engine build it back from an attributed string. Each paragraph's block
// containers are stored on its characters (`.richContainerPath`), so structure survives editing, undo and in-app
// copy/paste; lists and tables created natively by AppKit (RTF paste) are reconciled from `textLists`/`textBlocks`.
import AppKit

enum RichContainerKind: String, Sendable {
    case section = "Section", list = "List", listItem = "ListItem", table = "Table", rowGroup = "TableRowGroup",
         row = "TableRow", cell = "TableCell"

    /// Containers whose content is blocks (paragraphs, lists, tables, sections).
    var holdsBlocks: Bool { self == .section || self == .listItem || self == .cell }

    /// May `child` sit directly inside `self` (nil = the document)?
    static func allows(_ parent: RichContainerKind?, _ child: RichContainerKind) -> Bool {
        switch parent {
        case nil, .section?, .listItem?, .cell?: return child == .section || child == .list || child == .table
        case .list?: return child == .listItem
        case .table?: return child == .rowGroup
        case .rowGroup?: return child == .row
        case .row?: return child == .cell
        }
    }
}

/// One block container on a paragraph's path: carried raw attributes (source order) and modelled tokens.
struct RichContainerInfo: Equatable {
    var kind: RichContainerKind
    var id: String
    var carried: [XamlRawAttribute]
    var model: [String: String]

    init(kind: RichContainerKind, id: String, carried: [XamlRawAttribute] = [], model: [String: String] = [:]) {
        self.kind = kind; self.id = id; self.carried = carried; self.model = model
    }

    var plist: [String] {
        var out = [kind.rawValue, id]
        for a in carried { out += [a.qualifiedName, a.namespaceURI ?? "", a.value] }
        for k in model.keys.sorted() { out += ["@" + k, "", model[k]!] }
        return out
    }

    init?(plist p: [String]) {
        guard p.count >= 2, (p.count - 2) % 3 == 0, let k = RichContainerKind(rawValue: p[0]) else { return nil }
        kind = k
        id = p[1]
        carried = []
        model = [:]
        var i = 2
        while i + 2 < p.count {
            let n = p[i], ns = p[i + 1], v = p[i + 2]
            if n.hasPrefix("@") { model[String(n.dropFirst())] = v } else {
                carried.append(XamlRawAttribute(qualifiedName: n, namespaceURI: ns.isEmpty ? nil : ns, value: v))
            }
            i += 3
        }
    }

    /// A carried attribute's value by plain name.
    func carriedValue(_ name: String) -> String? {
        carried.first { $0.namespaceURI == nil && $0.qualifiedName == name }?.value
    }
}

enum RichAttributeCoding {
    static func encode(_ attrs: [XamlRawAttribute]) -> [[String]] {
        attrs.map { [$0.qualifiedName, $0.namespaceURI ?? "", $0.value] }
    }

    static func decode(_ any: Any?) -> [XamlRawAttribute] {
        guard let rows = any as? [[String]] else { return [] }
        return rows.compactMap { r in
            guard r.count == 3 else { return nil }
            return XamlRawAttribute(qualifiedName: r[0], namespaceURI: r[1].isEmpty ? nil : r[1], value: r[2])
        }
    }

    static func decodePath(_ any: Any?) -> [RichContainerInfo] {
        guard let rows = any as? [[String]] else { return [] }
        return rows.compactMap { RichContainerInfo(plist: $0) }
    }
}

/// Element ids: unique within a process (a per-process random prefix and a counter), so fragments inserted into a
/// document never collide with its own ids.
enum RichIDs {
    nonisolated(unsafe) private static var counter = 0
    private static let lock = NSLock()
    private static let prefix: String = {
        let v = UInt32.random(in: 0..<UInt32.max)
        return "e" + String(v, radix: 36)
    }()

    static func fresh() -> String {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        return prefix + "-" + String(counter, radix: 36)
    }
}

/// One paragraph of the block tree.
final class RichPara {
    /// The paragraph's characters, without list-marker characters and without the terminator.
    var content: NSMutableAttributedString
    /// Character attributes of the terminator (`\n`): the paragraph's own character context (XD.2.8).
    var terminator: [NSAttributedString.Key: Any]
    var alignment: NSTextAlignment
    var direction: NSWritingDirection
    /// Carried raw Paragraph attributes (`.aaParagraphAttrs`).
    var carried: [XamlRawAttribute]
    /// Modelled tokens and computed display values (`.richParagraphModel`).
    var model: [String: String]
    /// Paragraph-style line height read back from the attributed string (0 = Auto); nil = take it from the model.
    var minimumLineHeight: CGFloat?

    // Bookkeeping for selection mapping (list engine).
    var oldStart = -1, oldContentStart = -1, oldEnd = -1
    var newStart = -1, newContentStart = -1

    init(content: NSMutableAttributedString, terminator: [NSAttributedString.Key: Any], alignment: NSTextAlignment,
         direction: NSWritingDirection, carried: [XamlRawAttribute], model: [String: String]) {
        self.content = content; self.terminator = terminator; self.alignment = alignment; self.direction = direction
        self.carried = carried; self.model = model
    }

    var isEmpty: Bool { content.length == 0 }
    var isSynthetic: Bool { model["Synthetic"] == "1" }
    var isOpaqueBlock: Bool { model["OpaqueBlock"] == "1" }

    func copy() -> RichPara {
        let p = RichPara(content: NSMutableAttributedString(attributedString: content), terminator: terminator,
                         alignment: alignment, direction: direction, carried: carried, model: model)
        p.minimumLineHeight = minimumLineHeight
        return p
    }
}

final class RichContainer {
    var info: RichContainerInfo
    var children: [RichNode]
    init(_ info: RichContainerInfo, children: [RichNode] = []) { self.info = info; self.children = children }
}

enum RichNode {
    case para(RichPara)
    case container(RichContainer)

    var asContainer: RichContainer? { if case .container(let c) = self { return c }; return nil }
    var asPara: RichPara? { if case .para(let p) = self { return p }; return nil }

    /// Every paragraph in document order.
    func paragraphs() -> [RichPara] {
        switch self {
        case .para(let p): return [p]
        case .container(let c): return c.children.flatMap { $0.paragraphs() }
        }
    }

    func isSame(_ other: RichNode) -> Bool {
        switch (self, other) {
        case let (.para(a), .para(b)): return a === b
        case let (.container(a), .container(b)): return a === b
        default: return false
        }
    }
}

/// The paragraph-level keys the renderer owns; they are rewritten on every character of a paragraph.
enum RichParagraphKeys {
    static let all: [NSAttributedString.Key] = [.paragraphStyle, .aaParagraphAttrs, .richParagraphModel,
                                                .richContainerPath, .aaSectionPath, .aaListItemID,
                                                .aaListContinuation, .aaTableRowGroup, .aaListMarker]
}

final class RichDoc {
    var blocks: [RichNode]
    init(blocks: [RichNode] = []) { self.blocks = blocks }

    var paragraphs: [RichPara] { blocks.flatMap { $0.paragraphs() } }

    // MARK: - Build from an attributed string

    /// Paragraph ranges: (start, contentEnd, end) where `end` includes the terminator (`\n`, `\r`, `\r\n`, U+2029).
    static func paragraphRanges(_ s: NSString) -> [(start: Int, contentEnd: Int, end: Int)] {
        var out: [(Int, Int, Int)] = []
        let n = s.length
        var start = 0
        var i = 0
        while i < n {
            let c = s.character(at: i)
            if c == 0x0A || c == 0x2029 {
                out.append((start, i, i + 1)); i += 1; start = i
            } else if c == 0x0D {
                let e = (i + 1 < n && s.character(at: i + 1) == 0x0A) ? i + 2 : i + 1
                out.append((start, i, e)); i = e; start = i
            } else { i += 1 }
        }
        if start < n { out.append((start, n, n)) }
        return out
    }

    /// Builds the tree from attributed text (writer, list engine). Structure comes from `.richContainerPath`,
    /// reconciled with the paragraph style's `textLists`/`textBlocks` (AppKit-native lists and tables).
    static func build(from text: NSAttributedString) -> RichDoc {
        let ns = text.string as NSString
        var identity: [ObjectIdentifier: String] = [:]
        func idFor(_ o: AnyObject, _ prefix: String) -> String {
            let k = ObjectIdentifier(o)
            if let v = identity[k] { return v }
            let v = prefix + RichIDs.fresh()
            identity[k] = v
            return v
        }
        let doc = RichDoc()
        var stack: [RichContainer] = []
        func appendNode(_ node: RichNode) {
            if let top = stack.last { top.children.append(node) } else { doc.blocks.append(node) }
        }
        for r in paragraphRanges(ns) {
            let full = NSRange(location: r.start, length: r.end - r.start)
            guard full.length > 0 else { continue }
            let first = text.attributes(at: r.start, effectiveRange: nil)
            // Markers: leading characters tagged `.aaListMarker`.
            var cs = r.start
            while cs < r.contentEnd, text.attribute(.aaListMarker, at: cs, effectiveRange: nil) != nil { cs += 1 }
            let style = first[.paragraphStyle] as? NSParagraphStyle
            var path = RichAttributeCoding.decodePath(first[.richContainerPath])
            path = reconcile(path, style: style, idFor: idFor)
            // AppKit-native list markers (no `.aaListMarker`): `\t…\t` at the start of a native list paragraph.
            if cs == r.start, let st = style, !st.textLists.isEmpty,
               first[.richContainerPath] == nil || RichAttributeCoding.decodePath(first[.richContainerPath])
                   .filter({ $0.kind == .list }).count < st.textLists.count {
                cs += nativeMarkerLength(ns, from: r.start, to: r.contentEnd)
            }
            let content = NSMutableAttributedString(attributedString:
                text.attributedSubstring(from: NSRange(location: cs, length: r.contentEnd - cs)))
            var term: [NSAttributedString.Key: Any]
            if r.end > r.contentEnd {
                term = text.attributes(at: r.contentEnd, effectiveRange: nil)
            } else if r.contentEnd > cs {
                term = text.attributes(at: r.contentEnd - 1, effectiveRange: nil)
            } else { term = first }
            for k in RichParagraphKeys.all { term[k] = nil }
            let para = RichPara(content: content, terminator: term,
                                alignment: style?.alignment ?? .natural,
                                direction: style?.baseWritingDirection ?? .natural,
                                carried: RichAttributeCoding.decode(first[.aaParagraphAttrs]),
                                model: (first[.richParagraphModel] as? [String: String]) ?? [:])
            para.minimumLineHeight = style?.minimumLineHeight ?? 0
            if first[.richParagraphModel] == nil, path.isEmpty, let st = style { adoptNativeIndents(st, into: para) }
            para.oldStart = r.start; para.oldContentStart = cs; para.oldEnd = r.end
            let isContinuation = (first[.aaListContinuation] as? Bool) == true
            // Nest by container ids.
            var k = 0
            while k < stack.count, k < path.count, stack[k].info.id == path[k].id, stack[k].info.kind == path[k].kind {
                k += 1
            }
            if let j = path.lastIndex(where: { $0.kind == .listItem }), j < k, !isContinuation,
               !stack[j].children.isEmpty, path.count == j + 1 {
                k = j                                                   // an item start with a reused id → new item
            }
            stack.removeSubrange(k...)
            var m = k
            while m < path.count {
                let c = RichContainer(path[m])
                appendNode(.container(c))
                stack.append(c)
                m += 1
            }
            appendNode(.para(para))
        }
        return doc
    }

    /// An AppKit-native paragraph (RTF from Word, Pages or TextEdit; no W-RICH model on its characters) at the document
    /// level keeps its indents the way WPF's RTF converter keeps them: `headIndent` → `Margin.Left`,
    /// `-tailIndent` → `Margin.Right`, `firstLineHeadIndent − headIndent` → `TextIndent` (05 §6.4 "Paragraph", read in
    /// reverse; top/bottom stay `Auto`). Paragraphs W-RICH rendered always carry `.richParagraphModel` or sit at zero
    /// indent, so they never pass through here with a non-zero indent.
    static func adoptNativeIndents(_ st: NSParagraphStyle, into p: RichPara) {
        guard st.textLists.isEmpty, st.textBlocks.isEmpty else { return }
        let head = Double(st.headIndent), first = Double(st.firstLineHeadIndent), tail = Double(st.tailIndent)
        let right = tail < 0 ? -tail : 0
        if head > 0 || right > 0 {
            p.model["Margin"] = XamlValues.formatThickness(XamlThickness(left: max(0, head), top: .nan,
                                                                         right: right > 0 ? right : .nan, bottom: .nan))
        }
        if first - head != 0, first >= 0 { p.model["TextIndent"] = XamlValues.formatLength(first - head) }
    }

    /// Length of an AppKit-native `\t{marker}\t` prefix, or 0.
    private static func nativeMarkerLength(_ s: NSString, from a: Int, to b: Int) -> Int {
        guard a < b, s.character(at: a) == 0x09 else { return 0 }
        var i = a + 1
        while i < b, i - a <= 14 {
            if s.character(at: i) == 0x09 { return i - a + 1 }
            i += 1
        }
        return 0
    }

    /// Makes a stored path consistent with the paragraph style and the container grammar.
    static func reconcile(_ stored: [RichContainerInfo], style: NSParagraphStyle?,
                          idFor: (AnyObject, String) -> String) -> [RichContainerInfo] {
        var path: [RichContainerInfo] = []
        // Grammar: truncate at the first invalid transition.
        for info in stored {
            guard RichContainerKind.allows(path.last?.kind, info.kind) else { break }
            path.append(info)
        }
        let textLists = style?.textLists ?? []
        let tableBlocks = (style?.textBlocks ?? []).compactMap { $0 as? NSTextTableBlock }
        // Tables: AppKit removed a table level → cut there; AppKit-native table → derive entries.
        let tableIdx = path.indices.filter { path[$0].kind == .table }
        if tableBlocks.count < tableIdx.count { path.removeSubrange(tableIdx[tableBlocks.count]...) }
        // Lists.
        let listIdx = path.indices.filter { path[$0].kind == .list }
        if textLists.count < listIdx.count { path.removeSubrange(listIdx[textLists.count]...) }
        while let last = path.last, !last.kind.holdsBlocks { path.removeLast() }
        let haveTables = path.filter { $0.kind == .table }.count
        if tableBlocks.count > haveTables {
            for b in tableBlocks[haveTables...] {
                let tid = idFor(b.table, "t")
                var tm: [String: String] = ["Columns": String(b.table.numberOfColumns)]
                tm["CellSpacing"] = b.table.collapsesBorders ? "0" : nil
                path.append(RichContainerInfo(kind: .table, id: tid, model: tm))
                path.append(RichContainerInfo(kind: .rowGroup, id: tid + "g"))
                path.append(RichContainerInfo(kind: .row, id: tid + "r" + String(b.startingRow)))
                path.append(RichContainerInfo(kind: .cell, id: idFor(b, "c"), model: cellModel(from: b)))
            }
        }
        let haveLists = path.filter { $0.kind == .list }.count
        if textLists.count > haveLists {
            for l in textLists[haveLists...] {
                path.append(RichContainerInfo(kind: .list, id: idFor(l, "l"),
                                              model: ["MarkerStyle": markerStyle(of: l)]))
                path.append(RichContainerInfo(kind: .listItem, id: RichIDs.fresh()))
            }
        }
        return path
    }

    static func markerStyle(of l: NSTextList) -> String {
        let f = l.markerFormat.rawValue
        if f.contains("{decimal}") { return "Decimal" }
        if f.contains("{lower-alpha}") || f.contains("{lower-latin}") { return "LowerLatin" }
        if f.contains("{upper-alpha}") || f.contains("{upper-latin}") { return "UpperLatin" }
        if f.contains("{lower-roman}") { return "LowerRoman" }
        if f.contains("{upper-roman}") { return "UpperRoman" }
        if f.contains("{circle}") { return "Circle" }
        if f.contains("{square}") { return "Square" }
        if f.contains("{box}") { return "Box" }
        if f.contains("{disc}") || f.contains("{hyphen}") || f.contains("{diamond}") || f.contains("{check}") { return "Disc" }
        return f.isEmpty ? "None" : "Disc"
    }

    /// Modelled cell tokens read from an AppKit table block (RTF-pasted tables).
    static func cellModel(from b: NSTextTableBlock) -> [String: String] {
        var m: [String: String] = [:]
        if b.columnSpan > 1 { m["ColumnSpan"] = String(b.columnSpan) }
        if b.rowSpan > 1 { m["RowSpan"] = String(b.rowSpan) }
        let edges: [NSRectEdge] = [.minX, .minY, .maxX, .maxY]
        let border = edges.map { Double(b.width(for: .border, edge: $0)) }
        if border.contains(where: { $0 > 0 }) {
            m["BorderThickness"] = XamlValues.formatThickness(XamlThickness(left: border[0], top: border[1],
                                                                            right: border[2], bottom: border[3]))
            if let c = b.borderColor(for: .minX) { m["BorderBrush"] = XamlValues.formatColor(RichColor.argb(c)) }
        }
        let pad = edges.map { Double(b.width(for: .padding, edge: $0)) }
        if pad.contains(where: { $0 > 0 }) {
            m["Padding"] = XamlValues.formatThickness(XamlThickness(left: pad[0], top: pad[1], right: pad[2],
                                                                    bottom: pad[3]))
        }
        if let bg = b.backgroundColor { m["Background"] = XamlValues.formatColor(RichColor.argb(bg)) }
        return m
    }
}

/// sRGB conversions (CONT-168: fixed sRGB, `round(c × 255)`).
enum RichColor {
    static func color(_ argb: UInt32, opacity: Double = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat(Double((argb >> 24) & 0xFF) / 255 * opacity))
    }

    static func argb(_ c: NSColor) -> UInt32 {
        func ch(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (Double(v) * 255).rounded()))) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard let s = c.usingColorSpace(.sRGB) ?? c.usingType(.componentBased)?.usingColorSpace(.sRGB) else {
            return 0xFF00_0000
        }
        s.getRed(&r, green: &g, blue: &b, alpha: &a)
        return ch(a) << 24 | ch(r) << 16 | ch(g) << 8 | ch(b)
    }
}
