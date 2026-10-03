// Spec: 05 CONT-032 (insert table: size prompt, regex, clamps, cell look, header row, caret in the first cell),
//       §7.3 (size vectors incl. the Mac overflow fix), K-15 (Mac inserts after the caret's block and keeps a trailing
//       paragraph), §6.4 (tables as NSTextTable / NSTextTableBlock, TextKit 1); 06 BUILD-145 B5 (blank = default 3×3,
//       non-ASCII digits = no match).
import AppKit

/// One programmatic edit the text view applies through `shouldChangeText` (so it is undoable and lock-gated).
public struct EditorTextEdit {
    /// The range of the CURRENT text that is replaced (length 0 = pure insertion).
    public var range: NSRange
    public var replacement: NSAttributedString
    /// The selection to set after the edit, in the coordinates of the edited text.
    public var selectionAfter: NSRange

    public init(range: NSRange, replacement: NSAttributedString, selectionAfter: NSRange) {
        self.range = range; self.replacement = replacement; self.selectionAfter = selectionAfter
    }
}

/// CONT-032 / B5 size parsing — `^\s*(\d+)\s*[xX*]\s*(\d+)\s*$`, rows clamped 1…50, columns 1…20, no match → 3×3.
public enum EditorTablePlan {
    public static let defaultRows = 3, defaultColumns = 3
    public static let maxRows = 50, maxColumns = 20

    /// The prompt's exact texts (06 Add. row 33).
    public static let promptTitle = "Insert table"
    public static let promptLabel = "Size as rows x columns (e.g. 3x4):"
    public static let promptInitial = "3x3"

    public static func parse(_ text: String?) -> (rows: Int, columns: Int) {
        let fallback = (rows: defaultRows, columns: defaultColumns)
        let u = Array((text ?? "").utf16)
        var i = 0
        func skipSpace() { while i < u.count, NetText.isWhiteSpace(u[i]) { i += 1 } }
        /// An ASCII digit run, saturated (non-ASCII digits are "no match", B5); nil when empty.
        func digits() -> Int? {
            let start = i
            var value = 0
            while i < u.count, u[i] >= 0x30, u[i] <= 0x39 {
                if value < 1_000_000_000 { value = value * 10 + Int(u[i] - 0x30) }
                i += 1
            }
            return i > start ? value : nil
        }
        skipSpace()
        guard let rows = digits() else { return fallback }
        skipSpace()
        guard i < u.count, u[i] == 0x78 || u[i] == 0x58 || u[i] == 0x2A else { return fallback }   // x X *
        i += 1
        skipSpace()
        guard let cols = digits() else { return fallback }
        skipSpace()
        guard i == u.count else { return fallback }
        return (min(max(rows, 1), maxRows), min(max(cols, 1), maxColumns))
    }
}

/// Builds and places a WPF-shaped table (CellSpacing 0, Margin 0,4,0,4, borders #FF9AA0A6 0.6, padding 3,1,3,1,
/// header row bold) as TextKit 1 table blocks.
@MainActor public enum EditorTableBuilder {
    public static let borderColor = NSColor(srgbRed: 0x9A / 255.0, green: 0xA0 / 255.0, blue: 0xA6 / 255.0, alpha: 1)
    public static let borderWidth: CGFloat = 0.6
    /// Left, top, right, bottom (WPF `Padding="3,1,3,1"`).
    public static let cellPadding: (left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) = (3, 1, 3, 1)
    /// Top / bottom table margin (WPF `Margin="0,4,0,4"`).
    public static let tableMarginVertical: CGFloat = 4

    /// WPF `Table.Margin` (`0,4,0,4`).
    public static let tableMargin = "0,4,0,4"

    /// The table's cells: one empty paragraph per cell, row-major; every cell paragraph ends with "\n".
    /// Built as the W-RICH block tree (Table CellSpacing 0 / Margin 0,4,0,4 → TableRowGroup → TableRow → TableCell
    /// with BorderBrush, BorderThickness, Padding, and `FontWeight="Bold"` on the row-0 cells) and rendered by the
    /// same renderer the reader uses, so the table is written exactly in the 05 S-4 shape and looks as it will after
    /// a reload (V-05: an AppKit-only table lost its Margin and put the header bold on the paragraphs).
    public static func makeTable(rows: Int, columns: Int, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let rows = max(1, rows), columns = max(1, columns)
        var plain = base
        for k in RichParagraphKeys.all { plain[k] = nil }
        plain[.paragraphStyle] = nil
        let baseStyle = (base[.paragraphStyle] as? NSParagraphStyle) ?? NSParagraphStyle.default
        let table = RichContainer(RichContainerInfo(kind: .table, id: RichIDs.fresh(),
                                                    model: ["Columns": String(columns), "CellSpacing": "0",
                                                            "Margin": tableMargin]))
        let group = RichContainer(RichContainerInfo(kind: .rowGroup, id: RichIDs.fresh()))
        table.children = [.container(group)]
        let border = XamlValues.formatThickness(XamlThickness(left: Double(borderWidth), top: Double(borderWidth),
                                                              right: Double(borderWidth), bottom: Double(borderWidth)))
        let padding = XamlValues.formatThickness(XamlThickness(left: Double(cellPadding.left),
                                                               top: Double(cellPadding.top),
                                                               right: Double(cellPadding.right),
                                                               bottom: Double(cellPadding.bottom)))
        let brush = XamlValues.formatColor(RichColor.argb(borderColor))
        for r in 0..<rows {
            let row = RichContainer(RichContainerInfo(kind: .row, id: RichIDs.fresh()))
            for _ in 0..<columns {
                var attrs = plain
                var carried: [XamlRawAttribute] = []
                if r == 0 {                                                    // header row (cell FontWeight)
                    attrs[.font] = EditorFormatting.font(attrs[.font] as? NSFont, bold: true)
                    carried.append(XamlRawAttribute(qualifiedName: "FontWeight", namespaceURI: nil, value: "Bold"))
                }
                let cell = RichContainer(RichContainerInfo(kind: .cell, id: RichIDs.fresh(), carried: carried,
                                                           model: ["BorderBrush": brush, "BorderThickness": border,
                                                                   "Padding": padding]))
                let para = RichPara(content: NSMutableAttributedString(), terminator: attrs, alignment: .left,
                                    direction: baseStyle.baseWritingDirection, carried: [], model: [:])
                cell.children = [.para(para)]
                row.children.append(.container(cell))
            }
            group.children.append(.container(row))
        }
        return RichRenderer.render(RichDoc(blocks: [.container(table)]))
    }

    /// K-15 placement: after the block the caret is in (the whole list when the caret is in a list, the whole table
    /// when it is in a table, else the caret's paragraph), with a trailing ordinary paragraph when the table would
    /// otherwise end the document or touch another table. The caret goes to the first cell.
    public static func insertion(rows: Int, columns: Int, in s: NSAttributedString, selection: NSRange,
                                 base: [NSAttributedString.Key: Any]) -> EditorTextEdit {
        let text = s.string as NSString
        let len = text.length
        let caret = min(max(0, NSMaxRange(selection)), len)
        var location = len
        var leadingBreak = false
        if len > 0 {
            location = EditorBlocks.blockEnd(in: s, at: caret)
            if location == len, text.character(at: len - 1) != 0x0A { leadingBreak = true }
        }
        let tableString = makeTable(rows: rows, columns: columns, base: base)
        let replacement = NSMutableAttributedString()
        if leadingBreak {
            // The terminator of the caret's last paragraph keeps that paragraph's attributes.
            replacement.append(NSAttributedString(string: "\n", attributes: s.attributes(at: len - 1, effectiveRange: nil)))
        }
        replacement.append(tableString)
        let followedByText = location < len && !EditorBlocks.isTableParagraph(s, at: location)
        if !followedByText {
            var plain = base
            plain[.paragraphStyle] = EditorBlocks.plainParagraphStyle(from: base[.paragraphStyle] as? NSParagraphStyle)
            replacement.append(NSAttributedString(string: "\n", attributes: plain))
        }
        let firstCell = location + (leadingBreak ? 1 : 0)
        return EditorTextEdit(range: NSRange(location: location, length: 0), replacement: replacement,
                              selectionAfter: NSRange(location: firstCell, length: 0))
    }
}

/// Paragraph / block geometry over the TextKit 1 attributed model (lists = `textLists`, tables = `textBlocks`).
public enum EditorBlocks {
    public static func paragraphStyle(_ s: NSAttributedString, at i: Int) -> NSParagraphStyle? {
        guard s.length > 0 else { return nil }
        return s.attribute(.paragraphStyle, at: min(max(0, i), s.length - 1), effectiveRange: nil) as? NSParagraphStyle
    }

    /// The outermost table the paragraph at `i` belongs to, if any.
    public static func table(_ s: NSAttributedString, at i: Int) -> NSTextTable? {
        guard let st = paragraphStyle(s, at: i) else { return nil }
        for b in st.textBlocks { if let tb = b as? NSTextTableBlock { return tb.table } }
        return nil
    }

    public static func isTableParagraph(_ s: NSAttributedString, at i: Int) -> Bool { table(s, at: i) != nil }

    /// The outermost list the paragraph at `i` belongs to, if any.
    public static func topList(_ s: NSAttributedString, at i: Int) -> NSTextList? {
        paragraphStyle(s, at: i)?.textLists.first
    }

    /// Every paragraph range that intersects `range` (the caret's paragraph for an empty range). A selection that
    /// ends exactly at the start of a paragraph does not touch it (a triple-clicked line includes its newline).
    public static func paragraphRanges(_ s: NSAttributedString, touching range: NSRange) -> [NSRange] {
        let text = s.string as NSString
        let len = text.length
        if len == 0 { return [NSRange(location: 0, length: 0)] }
        let start = min(max(0, range.location), len)
        let end = min(max(start, NSMaxRange(range)), len)
        var out: [NSRange] = []
        var loc = start
        repeat {
            let p = text.paragraphRange(for: NSRange(location: min(loc, len), length: 0))
            out.append(p)
            if NSMaxRange(p) <= loc { break }
            loc = NSMaxRange(p)
        } while loc < end && loc < len
        return out
    }

    /// End (exclusive) of the block the caret is in: the whole outermost table, the whole top-level list, or the
    /// caret's own paragraph.
    public static func blockEnd(in s: NSAttributedString, at caret: Int) -> Int {
        let text = s.string as NSString
        let len = text.length
        guard len > 0 else { return 0 }
        let probe = min(caret, len - 1)
        var p = text.paragraphRange(for: NSRange(location: caret == len && caret > 0 ? caret - 1 : probe, length: 0))
        if caret == len, caret > 0, text.character(at: len - 1) == 0x0A {
            // The caret sits on the empty last line after a final newline: insert at the very end.
            return len
        }
        if let table = table(s, at: p.location) {
            while NSMaxRange(p) < len, self.table(s, at: NSMaxRange(p)) === table {
                p = text.paragraphRange(for: NSRange(location: NSMaxRange(p), length: 0))
            }
            return NSMaxRange(p)
        }
        if let list = topList(s, at: p.location) {
            while NSMaxRange(p) < len, topList(s, at: NSMaxRange(p)) === list {
                p = text.paragraphRange(for: NSRange(location: NSMaxRange(p), length: 0))
            }
            return NSMaxRange(p)
        }
        return NSMaxRange(p)
    }

    /// A copy of `style` without lists, blocks or indents (an ordinary paragraph after a table).
    public static func plainParagraphStyle(from style: NSParagraphStyle?) -> NSParagraphStyle {
        guard let m = style?.mutableCopy() as? NSMutableParagraphStyle else { return NSParagraphStyle.default }
        m.textBlocks = []
        m.textLists = []
        m.headIndent = 0
        m.firstLineHeadIndent = 0
        m.tailIndent = 0
        m.alignment = .left
        return m
    }
}
