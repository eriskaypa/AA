// Contract: ARCHITECTURE.md §6.7.
// Spec: 05 §3.2 (ListFormatting: IndentStep 24, BulletCycle Disc→Circle→Square, NumberCycle Decimal→LowerLatin→
//       LowerRoman, Build, Normalise / NormaliseWithin / ApplySpacing, IsNumbered, MoveItem / MoveItems /
//       MoveBlock), §3.1 (ChangeIndent, SelectedParagraphs, SelectedListItems, OutermostBlock, InsertListAtCaret),
//       CONT-040…047, §6.5 (Mac list behaviour: Enter in an item → new item; Enter on an empty item → outdent /
//       leave the list; Tab / ⇧Tab at an item start → nest / un-nest; Backspace at an item start → outdent one level
//       or leave the list; NaN/Auto margins count as 0), §7.2 (vectors).
// Every call edits `s` as one replacement inside beginEditing/endEditing; the caller wraps the call in one undo group
// (snapshot the storage before calling). List structure lives in the block tree (RichDocModel); markers, indents and
// numbering are re-rendered by RichRenderer, exactly as the reader draws them.
import AppKit

@MainActor public enum RichListFormatter {
    nonisolated public enum ListKind: Sendable, Equatable { case bullets, numbered }

    /// 05 §3.2 `IndentStep`.
    public static let indentStep: Double = 24

    /// CONT-040/041: WPF ToggleBullets / ToggleNumbering, then Normalise.
    public static func toggleList(_ kind: ListKind, in s: NSTextStorage, selection: NSRange) -> NSRange {
        edit(s, selection: selection) { t, sel in
            let paras = t.selectedParagraphs(sel)
            guard !paras.isEmpty else { return nil }
            let items = paras.compactMap { t.itemOf($0) }
            if items.count == paras.count {
                let lists = t.unique(items.compactMap { t.parentOf(.container($0)) })
                if lists.allSatisfy({ RichEditTree.matches($0, kind) }) {
                    for l in lists { t.unlist(l, items: Set(items.map(ObjectIdentifier.init))) }
                } else {
                    for l in lists { l.info.model["MarkerStyle"] = kind == .bullets ? "Disc" : "Decimal" }
                }
            } else {
                t.convertToList(paras.filter { t.itemOf($0) == nil }, kind: kind)
            }
            t.normalise()
            return .map
        }
    }

    /// CONT-042.
    public static func normalise(_ s: NSTextStorage) {
        _ = edit(s, selection: NSRange(location: 0, length: 0)) { t, _ in
            t.normalise()
            return .map
        }
    }

    /// CONT-043 Indent: list items nest (IncreaseIndentation); ordinary paragraphs move 24 px right.
    public static func indent(_ s: NSTextStorage, selection: NSRange) -> NSRange {
        edit(s, selection: selection) { t, sel in
            guard let caret = t.paragraph(at: sel.location) else { return nil }
            if t.itemOf(caret) != nil {
                t.indentItems(t.selectedItems(sel))
            } else {
                for p in t.selectedParagraphs(sel) { RichEditTree.shiftMargin(p, by: indentStep) }
            }
            t.normalise()
            return .map
        }
    }

    /// CONT-043 Outdent (DecreaseIndentation / 24 px left, clamped at 0).
    public static func outdent(_ s: NSTextStorage, selection: NSRange) -> NSRange {
        edit(s, selection: selection) { t, sel in
            guard let caret = t.paragraph(at: sel.location) else { return nil }
            if t.itemOf(caret) != nil {
                t.outdentItems(t.selectedItems(sel))
            } else {
                for p in t.selectedParagraphs(sel) { RichEditTree.shiftMargin(p, by: -indentStep) }
            }
            t.normalise()
            return .map
        }
    }

    /// CONT-044: Tab / ⇧Tab at the start of a list item nest / un-nest it; a multi-paragraph selection in a list is
    /// indented / outdented. nil = not handled (the text view inserts a tab).
    public static func handleTab(_ s: NSTextStorage, selection: NSRange, shift: Bool) -> NSRange? {
        if selection.length == 0 {
            guard isAtItemStart(s, location: selection.location) else { return nil }
        } else {
            let t = RichEditTree(RichDoc.build(from: s))
            guard let caret = t.paragraph(at: selection.location), t.itemOf(caret) != nil,
                  t.selectedParagraphs(selection).count > 1 else { return nil }
        }
        return shift ? outdent(s, selection: selection) : indent(s, selection: selection)
    }

    /// §6.5 Return in a list item: on an empty item → outdent (leave the list at top level); otherwise split the
    /// paragraph and start a new item at the same level. nil = not in a list (default newline).
    public static func handleReturn(_ s: NSTextStorage, selection: NSRange) -> NSRange? {
        guard selection.length == 0 else { return nil }
        let pre = RichEditTree(RichDoc.build(from: s))
        guard let p0 = pre.paragraph(at: selection.location), pre.itemOf(p0) != nil else { return nil }
        let result: NSRange = edit(s, selection: selection) { t, sel in
            guard let para = t.paragraph(at: sel.location), let item = t.itemOf(para) else { return nil }
            if para.isEmpty, item.children.first.map({ $0.isSame(.para(para)) }) == true {
                t.outdentItems([item])
                t.normalise()
                return .caret(para, 0)
            }
            let offset = max(0, min(sel.location - para.oldContentStart, para.content.length))
            let right = para.content.attributedSubstring(from: NSRange(location: offset,
                                                                          length: para.content.length - offset))
            para.content.deleteCharacters(in: NSRange(location: offset, length: para.content.length - offset))
            let np = para.copy()
            np.content = NSMutableAttributedString(attributedString: right)
            np.oldStart = -1; np.oldContentStart = -1; np.oldEnd = -1
            if offset == 0, para.content.length == 0, right.length > 0 {
                // Splitting at the very start keeps the attributes of the text for the empty item before it.
                para.terminator = right.attributes(at: 0, effectiveRange: nil).filter { !RichParagraphKeys.all.contains($0.key) }
            }
            if item.children.first.map({ $0.isSame(.para(para)) }) == true, let list = t.parentOf(.container(item)) {
                let ni = RichContainer(RichContainerInfo(kind: .listItem, id: RichIDs.fresh(), carried: item.info.carried))
                let idx = item.children.firstIndex { $0.isSame(.para(para)) } ?? 0
                ni.children = [.para(np)] + item.children[(idx + 1)...]
                item.children = Array(item.children[...idx])
                if let li = list.children.firstIndex(where: { $0.isSame(.container(item)) }) {
                    list.children.insert(.container(ni), at: li + 1)
                }
            } else if let idx = item.children.firstIndex(where: { $0.isSame(.para(para)) }) {
                item.children.insert(.para(np), at: idx + 1)
            }
            t.reindex()
            t.normalise()
            return .caret(np, 0)
        }
        return result
    }

    /// CONT-045: Backspace with the caret at the start of any paragraph of a list item → outdent one level (top level
    /// → ordinary paragraph). nil = not at an item start.
    public static func handleBackspaceAtItemStart(_ s: NSTextStorage, selection: NSRange) -> NSRange? {
        guard selection.length == 0 else { return nil }
        let pre = RichEditTree(RichDoc.build(from: s))
        guard let p0 = pre.paragraph(at: selection.location), pre.itemOf(p0) != nil,
              selection.location >= p0.oldStart, selection.location <= p0.oldContentStart else { return nil }
        return edit(s, selection: selection) { t, sel in
            guard let para = t.paragraph(at: sel.location), let item = t.itemOf(para) else { return nil }
            t.outdentItems([item])
            t.normalise()
            return .caret(para, 0)
        }
    }

    /// CONT-046 Move up / down: sibling list items as a group (sub-items travel), else the outermost block around the
    /// caret among its siblings. nil = nothing moved (at the top / bottom, or no structure).
    public static func moveItem(_ s: NSTextStorage, selection: NSRange, up: Bool) -> NSRange? {
        var moved = false
        let r: NSRange = edit(s, selection: selection) { t, sel in
            guard let caret = t.paragraph(at: sel.location) else { return nil }
            let items = t.selectedListItemsForMove(sel)
            if !items.isEmpty {
                moved = t.moveItems(items, up: up)
            } else {
                moved = t.moveBlock(t.outermostBlock(caret), up: up)
            }
            guard moved else { return nil }
            t.normalise()
            return .map
        }
        return moved ? r : nil
    }

    /// CONT-047 step 5: a saved list inserted into the caret's own block collection, after the block holding the end
    /// of `at` (a live selection is untouched); an empty paragraph follows when the list ends its collection. Returns
    /// the caret (start of the block after the list).
    public static func insertList(lines: [String], kind: ListKind, into s: NSTextStorage, at: NSRange) -> NSRange {
        let clean = lines.map { NetText.trim($0) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return NSRange(location: at.location, length: 0) }
        return edit(s, selection: at) { t, sel in
            if t.root.children.isEmpty {
                let p = RichPara(content: NSMutableAttributedString(), terminator: RichEditTree.defaultCharacterAttributes,
                                 alignment: .natural, direction: .natural, carried: [], model: [:])
                t.root.children = [.para(p)]
                t.reindex()
            }
            guard let anchor = t.paragraph(at: NSMaxRange(sel)) ?? t.lastParagraph, let host = t.parentOf(.para(anchor))
            else { return nil }
            let chars = RichEditTree.insertionAttributes(anchor)
            let list = RichContainer(RichContainerInfo(kind: .list, id: RichIDs.fresh(),
                                                       model: ["MarkerStyle": kind == .numbered ? "Decimal" : "Disc"]))
            for line in clean {
                let p = RichPara(content: NSMutableAttributedString(string: line, attributes: chars), terminator: chars,
                                 alignment: .natural, direction: .natural, carried: [],
                                 model: ["Margin": "0,1,0,1", "c.FontSize": anchor.model["c.FontSize"] ?? ""])
                    .withoutEmptyModelValues()
                let item = RichContainer(RichContainerInfo(kind: .listItem, id: RichIDs.fresh()), children: [.para(p)])
                list.children.append(.container(item))
            }
            RichEditTree.applySpacing(list, depth: 0, numbered: kind == .numbered)    // `ListFormatting.Build`
            let idx = (host.children.firstIndex { $0.isSame(.para(anchor)) } ?? (host.children.count - 1)) + 1
            host.children.insert(.container(list), at: idx)
            if idx == host.children.count - 1 {
                let trailing = RichPara(content: NSMutableAttributedString(), terminator: chars, alignment: .natural,
                                        direction: .natural, carried: [], model: [:])
                host.children.append(.para(trailing))
            }
            t.reindex()
            t.normalise()
            if let next = host.children[idx + 1].paragraphs().first { return .caret(next, 0) }
            return .map
        }
    }

    public static func isAtItemStart(_ s: NSAttributedString, location: Int) -> Bool {
        guard s.length > 0 else { return false }
        let ns = s.string as NSString
        let loc = max(0, min(location, s.length))
        var probe = loc
        if probe == s.length { probe -= 1 }
        let para = ns.paragraphRange(for: NSRange(location: probe, length: 0))
        if loc == s.length, para.length > 0, let last = ns.substring(with: para).unicodeScalars.last,
           last == "\n" || last == "\r" || last == "\u{2029}" { return false }
        let a = s.attributes(at: para.location, effectiveRange: nil)
        let path = RichAttributeCoding.decodePath(a[.richContainerPath])
        let inItem = path.last?.kind == .listItem
            || ((a[.paragraphStyle] as? NSParagraphStyle)?.textLists.isEmpty == false)
        guard inItem, a[.aaListContinuation] as? Bool != true else { return false }
        var contentStart = para.location
        while contentStart < NSMaxRange(para), s.attribute(.aaListMarker, at: contentStart, effectiveRange: nil) != nil {
            contentStart += 1
        }
        return loc >= para.location && loc <= contentStart
    }

    // MARK: - Edit driver

    enum Outcome { case map, caret(RichPara, Int) }

    /// Builds the tree, runs `op`, re-renders the whole storage and maps the selection. `op` returning nil = no change.
    private static func edit(_ s: NSTextStorage, selection: NSRange, _ op: (RichEditTree, NSRange) -> Outcome?) -> NSRange {
        let tree = RichEditTree(RichDoc.build(from: s))
        guard let outcome = op(tree, selection) else { return selection }
        let rendered = RichRenderer.render(RichDoc(blocks: tree.root.children))
        s.beginEditing()
        s.replaceCharacters(in: NSRange(location: 0, length: s.length), with: rendered)
        s.endEditing()
        switch outcome {
        case .caret(let p, let off):
            return NSRange(location: max(0, p.newContentStart) + off, length: 0)
        case .map:
            let a = tree.map(selection.location, newLength: rendered.length)
            let b = tree.map(NSMaxRange(selection), newLength: rendered.length)
            return NSRange(location: a, length: max(0, b - a))
        }
    }
}

private extension RichPara {
    func withoutEmptyModelValues() -> RichPara {
        model = model.filter { !$0.value.isEmpty }
        return self
    }
}

/// The block tree with parent links, and the structural operations of 05 §3.1–§3.2.
@MainActor
final class RichEditTree {
    let root: RichContainer
    private var parents: [ObjectIdentifier: RichContainer] = [:]
    private(set) var paragraphsInOrder: [RichPara] = []

    init(_ doc: RichDoc) {
        root = RichContainer(RichContainerInfo(kind: .section, id: "#root"), children: doc.blocks)
        reindex()
    }

    static let bulletCycle = ["Disc", "Circle", "Square"]
    static let numberCycle = ["Decimal", "LowerLatin", "LowerRoman"]

    static var defaultCharacterAttributes: [NSAttributedString.Key: Any] {
        let c = XamlContext.containerEditor
        return [.font: RichFontResolver.font(family: c.fontFamily, size: c.fontSize, weight: c.fontWeight, italic: false),
                .foregroundColor: RichColor.color(c.foreground), .aaFontFamilyName: c.fontFamily, .aaXmlLang: c.language]
    }

    /// CONT-161: inserted text takes the destination paragraph's own character context (its terminator), never a
    /// link, lock, highlight or decoration.
    static func insertionAttributes(_ p: RichPara) -> [NSAttributedString.Key: Any] {
        var a = p.terminator
        for k in RichParagraphKeys.all { a[k] = nil }
        for k: NSAttributedString.Key in [.link, .aaHyperlink, .richHyperlinkAttributes, .aaLinkStyled,
                                          .aaUnderlyingForeground, .aaLockSource, .aaLocked, .backgroundColor,
                                          .aaBackgroundBrushXml, .richBackgroundBrushDisplay, .underlineStyle,
                                          .strikethroughStyle, .aaExtraDecorations, .superscript, .aaBaselineAlignment,
                                          .aaInRunNewline, .aaExtraAttributes, .aaPreservedXaml, .attachment] {
            a[k] = nil
        }
        if a[.font] == nil { a.merge(defaultCharacterAttributes) { old, _ in old } }
        return a
    }

    func reindex() {
        parents = [:]
        paragraphsInOrder = []
        func walk(_ c: RichContainer) {
            for n in c.children {
                switch n {
                case .para(let p):
                    parents[ObjectIdentifier(p)] = c
                    paragraphsInOrder.append(p)
                case .container(let cc):
                    parents[ObjectIdentifier(cc)] = c
                    walk(cc)
                }
            }
        }
        walk(root)
    }

    func parentOf(_ n: RichNode) -> RichContainer? {
        switch n {
        case .para(let p): return parents[ObjectIdentifier(p)]
        case .container(let c): return parents[ObjectIdentifier(c)]
        }
    }

    func unique(_ cs: [RichContainer]) -> [RichContainer] {
        var seen = Set<ObjectIdentifier>()
        return cs.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    var lastParagraph: RichPara? { paragraphsInOrder.last }

    /// The paragraph holding text position `loc` (the last one at the very end).
    func paragraph(at loc: Int) -> RichPara? {
        for p in paragraphsInOrder where p.oldStart >= 0 && loc >= p.oldStart && loc < p.oldEnd { return p }
        return paragraphsInOrder.last { $0.oldStart >= 0 && loc >= $0.oldStart } ?? paragraphsInOrder.first
    }

    /// §3.1 `SelectedParagraphs`: every paragraph the selection touches; an empty selection → the caret paragraph.
    func selectedParagraphs(_ sel: NSRange) -> [RichPara] {
        guard sel.length > 0 else { return paragraph(at: sel.location).map { [$0] } ?? [] }
        let a = sel.location, b = NSMaxRange(sel)
        let hit = paragraphsInOrder.filter { $0.oldStart >= 0 && $0.oldStart < b && $0.oldEnd > a }
        return hit.isEmpty ? (paragraph(at: a).map { [$0] } ?? []) : hit
    }

    /// The ListItem a paragraph sits *directly* in.
    func itemOf(_ p: RichPara) -> RichContainer? {
        guard let c = parentOf(.para(p)), c.info.kind == .listItem else { return nil }
        return c
    }

    /// Distinct items of the selected paragraphs (document order).
    func selectedItems(_ sel: NSRange) -> [RichContainer] {
        unique(selectedParagraphs(sel).compactMap { itemOf($0) })
    }

    /// §3.1 `SelectedListItems`: empty when the items are not all siblings of the first one.
    func selectedListItemsForMove(_ sel: NSRange) -> [RichContainer] {
        let found = selectedItems(sel)
        guard found.count > 1 else { return found }
        let owner = parentOf(.container(found[0]))
        return found.allSatisfy({ parentOf(.container($0)) === owner }) ? found : []
    }

    static func isNumbered(_ style: String?) -> Bool { XamlValues.isNumberedMarker(style ?? "Disc") }

    static func matches(_ list: RichContainer, _ kind: RichListFormatter.ListKind) -> Bool {
        let numbered = isNumbered(list.info.model["MarkerStyle"])
        return kind == .numbered ? numbered : !numbered
    }

    // MARK: Normalise (05 §3.2)

    func normalise() {
        for n in root.children {
            if case .container(let c) = n, c.info.kind == .list {
                Self.applySpacing(c, depth: 0, numbered: Self.isNumbered(c.info.model["MarkerStyle"]))
            }
        }
        for n in root.children { normaliseWithin(n) }
    }

    private func normaliseWithin(_ n: RichNode) {
        guard case .container(let c) = n else { return }
        switch c.info.kind {
        case .list:
            for item in c.children {
                guard case .container(let ic) = item else { continue }
                for b in ic.children { normaliseWithin(b) }
            }
        case .table:
            for g in c.children {
                guard case .container(let gc) = g else { continue }
                for r in gc.children {
                    guard case .container(let rc) = r else { continue }
                    for cell in rc.children {
                        guard case .container(let cc) = cell else { continue }
                        for b in cc.children {
                            if case .container(let l) = b, l.info.kind == .list {
                                Self.applySpacing(l, depth: 0, numbered: Self.isNumbered(l.info.model["MarkerStyle"]))
                            }
                        }
                        for b in cc.children { normaliseWithin(b) }
                    }
                }
            }
        case .section:
            for b in c.children {
                if case .container(let l) = b, l.info.kind == .list {
                    Self.applySpacing(l, depth: 0, numbered: Self.isNumbered(l.info.model["MarkerStyle"]))
                }
            }
            for b in c.children { normaliseWithin(b) }
        default:
            break
        }
    }

    static func applySpacing(_ list: RichContainer, depth: Int, numbered: Bool) {
        let cycle = numbered ? numberCycle : bulletCycle
        list.info.model["MarkerStyle"] = cycle[depth % cycle.count]
        list.info.model["Padding"] = "24,0,0,0"
        list.info.model["Margin"] = depth == 0 ? "0,6,0,6" : "0,0,0,0"
        for item in list.children {
            guard case .container(let ic) = item else { continue }
            for b in ic.children {
                switch b {
                case .para(let p): p.model["Margin"] = "0,1,0,1"
                case .container(let sub) where sub.info.kind == .list:
                    applySpacing(sub, depth: depth + 1, numbered: numbered || isNumbered(sub.info.model["MarkerStyle"]))
                default: break
                }
            }
        }
    }

    // MARK: Paragraph indent (CONT-043, ordinary text)

    static func shiftMargin(_ p: RichPara, by step: Double) {
        let m = p.model["Margin"].flatMap(XamlValues.parseThickness)
            ?? XamlThickness(left: .nan, top: .nan, right: .nan, bottom: .nan)
        let left = m.left.isFinite ? m.left : 0
        let new = XamlThickness(left: max(0, left + step), top: m.top, right: m.right, bottom: m.bottom)
        p.model["Margin"] = XamlValues.formatThickness(new)
        p.model["TextIndent"] = nil
    }

    // MARK: List conversion (CONT-040/041)

    /// Plain paragraphs become items of new lists (one per run of adjacent siblings), merged with an adjacent sibling
    /// list of the same marker style (WPF `MergeLists`).
    func convertToList(_ paras: [RichPara], kind: RichListFormatter.ListKind) {
        let style = kind == .numbered ? "Decimal" : "Disc"
        var i = 0
        while i < paras.count {
            guard let host = parentOf(.para(paras[i])) else { i += 1; continue }
            var run = [paras[i]]
            var j = i + 1
            while j < paras.count, parentOf(.para(paras[j])) === host,
                  let a = host.children.firstIndex(where: { $0.isSame(.para(run.last!)) }),
                  a + 1 < host.children.count, host.children[a + 1].isSame(.para(paras[j])) {
                run.append(paras[j]); j += 1
            }
            let first = host.children.firstIndex { $0.isSame(.para(run[0])) }!
            let items: [RichNode] = run.map { p in
                .container(RichContainer(RichContainerInfo(kind: .listItem, id: RichIDs.fresh()), children: [.para(p)]))
            }
            host.children.removeSubrange(first..<(first + run.count))
            var merged = false
            if first > 0, case .container(let prev) = host.children[first - 1], prev.info.kind == .list,
               prev.info.model["MarkerStyle"] == style {
                prev.children.append(contentsOf: items)
                merged = true
                if first < host.children.count, case .container(let next) = host.children[first], next.info.kind == .list,
                   next.info.model["MarkerStyle"] == style {
                    prev.children.append(contentsOf: next.children)
                    host.children.remove(at: first)
                }
            } else if first < host.children.count, case .container(let next) = host.children[first],
                      next.info.kind == .list, next.info.model["MarkerStyle"] == style {
                next.children.insert(contentsOf: items, at: 0)
                merged = true
            }
            if !merged {
                let l = RichContainer(RichContainerInfo(kind: .list, id: RichIDs.fresh(), model: ["MarkerStyle": style]),
                                      children: items)
                host.children.insert(.container(l), at: first)
            }
            reindex()
            i = j
        }
    }

    /// Selected items of `list` become ordinary blocks of the list's parent; the list is split around them.
    func unlist(_ list: RichContainer, items selected: Set<ObjectIdentifier>) {
        guard let host = parentOf(.container(list)), let at = host.children.firstIndex(where: { $0.isSame(.container(list)) })
        else { return }
        var out: [RichNode] = []
        var chunk: [RichNode] = []
        var usedOriginal = false
        func flush() {
            guard !chunk.isEmpty else { return }
            let l: RichContainer
            if !usedOriginal { l = list; usedOriginal = true } else {
                l = RichContainer(RichContainerInfo(kind: .list, id: RichIDs.fresh(), carried: list.info.carried,
                                                    model: list.info.model))
            }
            l.children = chunk
            out.append(.container(l))
            chunk = []
        }
        for n in list.children {
            if case .container(let ic) = n, selected.contains(ObjectIdentifier(ic)) {
                flush()
                out.append(contentsOf: ic.children)
            } else {
                chunk.append(n)
            }
        }
        flush()
        host.children.replaceSubrange(at...at, with: out)
        reindex()
    }

    // MARK: Indent / outdent of list items (IncreaseIndentation / DecreaseIndentation)

    /// Contiguous runs of sibling items nest under the item before them (appended to its trailing sub-list, or a new
    /// sub-list with the parent list's marker style). A run with no previous sibling stays put.
    func indentItems(_ items: [RichContainer]) {
        for list in unique(items.compactMap { parentOf(.container($0)) }) {
            let mine = Set(items.filter { parentOf(.container($0)) === list }.map(ObjectIdentifier.init))
            var k = 0
            while k < list.children.count {
                guard case .container(let ic) = list.children[k], mine.contains(ObjectIdentifier(ic)) else { k += 1; continue }
                var e = k
                while e + 1 < list.children.count, case .container(let n) = list.children[e + 1],
                      mine.contains(ObjectIdentifier(n)) { e += 1 }
                guard k > 0, case .container(let prev) = list.children[k - 1], prev.info.kind == .listItem else {
                    k = e + 1; continue
                }
                let run = Array(list.children[k...e])
                list.children.removeSubrange(k...e)
                if case .container(let sub)? = prev.children.last, sub.info.kind == .list {
                    sub.children.append(contentsOf: run)
                } else {
                    let sub = RichContainer(RichContainerInfo(kind: .list, id: RichIDs.fresh(),
                                                              model: ["MarkerStyle": list.info.model["MarkerStyle"] ?? "Disc"]),
                                            children: run)
                    prev.children.append(.container(sub))
                }
            }
        }
        reindex()
    }

    /// Items leave their list one level: from a nested list into the parent list after the parent item (later
    /// siblings become their sub-items); from a top-level list into ordinary blocks (the list is split).
    func outdentItems(_ items: [RichContainer]) {
        for list in unique(items.compactMap { parentOf(.container($0)) }) {
            let mine = Set(items.filter { parentOf(.container($0)) === list }.map(ObjectIdentifier.init))
            if let parentItem = parentOf(.container(list)), parentItem.info.kind == .listItem,
               let outer = parentOf(.container(parentItem)), outer.info.kind == .list {
                guard let first = list.children.firstIndex(where: {
                    if case .container(let c) = $0 { return mine.contains(ObjectIdentifier(c)) }; return false
                }) else { continue }
                let last = list.children.lastIndex(where: {
                    if case .container(let c) = $0 { return mine.contains(ObjectIdentifier(c)) }; return false
                })!
                let moving = Array(list.children[first...last])
                let after = Array(list.children[(last + 1)...])
                list.children.removeSubrange(first...)
                if !after.isEmpty, case .container(let lastMoved)? = moving.last {
                    let sub = RichContainer(RichContainerInfo(kind: .list, id: RichIDs.fresh(), carried: list.info.carried,
                                                              model: list.info.model), children: after)
                    lastMoved.children.append(.container(sub))
                }
                if list.children.isEmpty { parentItem.children.removeAll { $0.isSame(.container(list)) } }
                let pi = outer.children.firstIndex { $0.isSame(.container(parentItem)) }!
                outer.children.insert(contentsOf: moving, at: pi + 1)
                reindex()
            } else {
                unlist(list, items: mine)
            }
        }
        reindex()
    }

    // MARK: Moves (05 §3.2)

    func moveItems(_ items: [RichContainer], up: Bool) -> Bool {
        guard let owner = parentOf(.container(items[0])), items.allSatisfy({ parentOf(.container($0)) === owner }) else {
            return false
        }
        let ordered = owner.children.compactMap { n -> RichContainer? in
            guard case .container(let c) = n, items.contains(where: { $0 === c }) else { return nil }
            return c
        }
        guard let firstIdx = owner.children.firstIndex(where: { $0.isSame(.container(ordered.first!)) }),
              let lastIdx = owner.children.firstIndex(where: { $0.isSame(.container(ordered.last!)) }) else { return false }
        let neighbourIdx = up ? firstIdx - 1 : lastIdx + 1
        guard neighbourIdx >= 0, neighbourIdx < owner.children.count else { return false }
        let neighbour = owner.children[neighbourIdx]
        owner.children.removeAll { n in ordered.contains { n.isSame(.container($0)) } }
        var anchor = owner.children.firstIndex { $0.isSame(neighbour) }!
        if up {
            for (k, c) in ordered.enumerated() { owner.children.insert(.container(c), at: anchor + k) }
        } else {
            for c in ordered { anchor += 1; owner.children.insert(.container(c), at: anchor) }
        }
        reindex()
        return true
    }

    /// §3.1 `OutermostBlock`: climb while the parent is a Section (stops at the document, a ListItem or a TableCell).
    func outermostBlock(_ p: RichPara) -> RichNode {
        var node: RichNode = .para(p)
        while let parent = parentOf(node), parent !== root, parent.info.kind == .section { node = .container(parent) }
        return node
    }

    func moveBlock(_ block: RichNode, up: Bool) -> Bool {
        guard let host = parentOf(block), let i = host.children.firstIndex(where: { $0.isSame(block) }) else { return false }
        let j = up ? i - 1 : i + 1
        guard j >= 0, j < host.children.count else { return false }
        host.children.swapAt(i, j)
        reindex()
        return true
    }

    // MARK: Selection mapping

    /// Old text position → new text position: same offset inside the same paragraph's content.
    func map(_ loc: Int, newLength: Int) -> Int {
        for p in paragraphsInOrder where p.oldStart >= 0 && loc >= p.oldStart && loc < max(p.oldEnd, p.oldStart + 1) {
            guard p.newContentStart >= 0 else { break }
            return min(newLength, p.newContentStart + max(0, min(loc - p.oldContentStart, p.content.length)))
        }
        if let last = paragraphsInOrder.last(where: { $0.oldStart >= 0 && $0.newContentStart >= 0 }), loc >= last.oldEnd {
            return min(newLength, last.newContentStart + last.content.length + (loc > last.oldEnd ? 0 : 1))
        }
        return min(loc, newLength)
    }
}
