// Spec: 05 CONT-161 (fragment insertion: resolved in the destination paragraph's computed style; after an insertion
//       the first and last paragraphs touched keep the destination paragraph's carried attributes, middle paragraphs
//       inserted whole keep their own), §6.6 (paste of the own XAML type and of HTML via HTMLToXAML), CONT-035, §3.1
//       `InsertListAtCaret` (blocks go into the caret paragraph's own block collection: document, list item, table
//       cell or section).
// Additive W-RICH API (ARCH §12.2) for W-CONT's paste pipeline: the WPF paste shape on the block tree, so a pasted
// fragment never breaks a list item, a table cell or a section apart and never adds a stray paragraph break.
import AppKit

public extension XamlReader {
    /// Pastes `xaml` (the own pasteboard type, `HTMLToXAML.convert` output, an inserted hyperlink/table fragment) into
    /// `storage`, replacing `range`, the way WPF's `TextRange` paste does:
    /// * the fragment is resolved in the computed style of the destination paragraph (`destinationContext`);
    /// * its first paragraph merges with the text before the caret and its last paragraph with the text after it,
    ///   both keeping the destination paragraph's own attributes (alignment, margins, list item, cell, section);
    /// * everything in between (whole paragraphs, lists, tables, sections) is inserted into the destination
    ///   paragraph's block collection with its own attributes;
    /// * a fragment that starts (ends) with a list, table or section leaves the text before (after) the caret as a
    ///   paragraph of its own; an empty one before a leading structure at the document / section level is dropped.
    /// The storage is replaced in one `beginEditing`/`endEditing` (the caller wraps the call in one undo group and runs
    /// the lock check first, 05 §6.8). Returns the caret after the inserted content, or nil when `xaml` is blank or
    /// unparseable (the caller falls back to plain text, CONT-035).
    @discardableResult
    static func insertFragment(_ xaml: String, into storage: NSTextStorage, replacing range: NSRange,
                               base: XamlContext) -> NSRange? {
        guard !NetText.isBlank(xaml) else { return nil }
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        let caret = min(range.location, storage.length)
        let work = NSMutableAttributedString(attributedString: storage)
        if clamped.length > 0 { work.deleteCharacters(in: clamped) }
        let context = destinationContext(in: work, at: caret, base: base)
        guard let fragment = fragmentTree(xaml, destinationContext: context) else { return nil }
        let tree = RichEditTree(RichDoc.build(from: work))
        var blocks = fragment
        // A fragment's trailing empty paragraph after a structure is only the caret's landing place in its source.
        if blocks.count > 1, case .para(let p)? = blocks.last, p.isEmpty, !p.isOpaqueBlock,
           case .container = blocks[blocks.count - 2] {
            blocks.removeLast()
        }
        guard !blocks.isEmpty else { return NSRange(location: caret, length: 0) }

        guard let dest = tree.paragraph(at: caret), let host = tree.parentOf(.para(dest)),
              let index = host.children.firstIndex(where: { $0.isSame(.para(dest)) }) else {
            // An empty document: the fragment is the document.
            tree.root.children = blocks
            tree.reindex()
            return replace(storage, with: tree, caretIn: tree.lastParagraph, offset: tree.lastParagraph?.content.length ?? 0)
        }
        let offset = dest.oldContentStart < 0 ? 0 : max(0, min(caret - dest.oldContentStart, dest.content.length))
        let left = dest.content.attributedSubstring(from: NSRange(location: 0, length: offset))
        let right = dest.content.attributedSubstring(from: NSRange(location: offset, length: dest.content.length - offset))

        func mergeable(_ n: RichNode) -> RichPara? {
            if case .para(let p) = n, !p.isOpaqueBlock { return p }
            return nil
        }

        if blocks.count == 1, let only = mergeable(blocks[0]) {
            let merged = NSMutableAttributedString(attributedString: left)
            merged.append(only.content)
            let caretOffset = merged.length
            merged.append(right)
            dest.content = merged
            return replace(storage, with: tree, caretIn: dest, offset: caretOffset)
        }

        var middle = blocks
        var replacement: [RichNode] = []
        // First paragraph touched: the destination paragraph (its own attributes), extended by the fragment's first
        // paragraph when there is one. Before a leading structure an empty one is dropped (WPF inserts the block
        // before the paragraph), except at a list item's start, which keeps the item's marker paragraph.
        let head = NSMutableAttributedString(attributedString: left)
        let firstMerged = mergeable(middle[0])
        if let first = firstMerged {
            head.append(first.content)
            middle.removeFirst()
        }
        if firstMerged != nil || head.length > 0 || (host.info.kind == .listItem && index == 0) {
            dest.content = head
            replacement.append(.para(dest))
        }
        // Last paragraph touched: a copy of the destination paragraph (WPF splits it), extended at the front by the
        // fragment's last paragraph when there is one. Inside a list item it continues the same item.
        let tail = dest.copy()
        let tailContent = NSMutableAttributedString()
        if let lastNode = middle.last, let last = mergeable(lastNode) {
            tailContent.append(last.content)
            middle.removeLast()
        }
        let caretOffset = tailContent.length
        tailContent.append(right)
        tail.content = tailContent
        replacement.append(contentsOf: middle)
        replacement.append(.para(tail))
        host.children.replaceSubrange(index...index, with: replacement)
        tree.reindex()
        return replace(storage, with: tree, caretIn: tail, offset: caretOffset)
    }

    /// The fragment's block tree resolved in `destinationContext` (no synthetic paragraph after a final table).
    internal static func fragmentTree(_ xaml: String, destinationContext: XamlContext) -> [RichNode]? {
        guard !NetText.isBlank(xaml) else { return nil }
        var result = XamlDOM.parse(xaml)
        if case .failure(.wrongRootNamespace(nil)) = result, let fixed = injectNamespace(xaml) {
            result = XamlDOM.parse(fixed)
        }
        guard case .success(let doc) = result else { return nil }
        var b = XamlReaderBuilder(doc: doc, context: destinationContext, fragment: true)
        return b.readTree()
    }

    private static func replace(_ storage: NSTextStorage, with tree: RichEditTree, caretIn para: RichPara?,
                                offset: Int) -> NSRange {
        let rendered = RichRenderer.render(RichDoc(blocks: tree.root.children))
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: rendered)
        storage.endEditing()
        guard let p = para, p.newContentStart >= 0 else { return NSRange(location: rendered.length, length: 0) }
        return NSRange(location: min(rendered.length, p.newContentStart + offset), length: 0)
    }
}
