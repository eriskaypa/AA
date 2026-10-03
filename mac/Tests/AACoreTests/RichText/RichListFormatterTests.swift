// TV: 05 §7.2 (list engine vectors 1–10), §3.2 (Build / Normalise / ApplySpacing / MoveItem(s) / MoveBlock),
//     CONT-040…047, §6.5 (Return / Tab / ⇧Tab / Backspace at an item start), §3.1 (InsertListAtCaret, OutermostBlock).
import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct RichListFormatterTests {
    @MainActor final class Doc {
        let storage: NSTextStorage
        let meta: RichTextMetadata
        init(_ body: String) {
            let (s, m) = RichTest.read(RichTest.doc(body))
            storage = NSTextStorage(attributedString: s)
            meta = m
        }
        var xaml: String { RichTest.body(XamlWriter.write(storage, metadata: meta, context: .containerEditor)) }
        func at(_ text: String, offset: Int = 0) -> NSRange {
            let r = (storage.string as NSString).range(of: text)
            precondition(r.location != NSNotFound, "missing \(text)")
            return NSRange(location: r.location + offset, length: 0)
        }
        func span(_ from: String, _ to: String) -> NSRange {
            let a = at(from).location, b = NSMaxRange((storage.string as NSString).range(of: to))
            return NSRange(location: a, length: b - a)
        }
        var paragraphs: [String] { RichTest.paragraphs(storage) }
    }

    static let item = ##"<Paragraph Margin="0,1,0,1">"##

    static func list(_ style: String, _ items: [String], margin: String = "0,6,0,6") -> String {
        "<List MarkerStyle=\"\(style)\" Margin=\"\(margin)\" Padding=\"24,0,0,0\">"
            + items.map { "<ListItem>" + Self.item + "<Run>\($0)</Run></Paragraph></ListItem>" }.joined() + "</List>"
    }

    // §7.2-1 Build.
    @Test func buildDropsBlanksAndTrims() {
        let d = Doc("<Paragraph><Run>x</Run></Paragraph>")
        let caret = RichListFormatter.insertList(lines: ["  Alpha ", "", "   ", "Beta"], kind: .bullets, into: d.storage,
                                                 at: d.at("x", offset: 1))
        #expect(d.xaml == "<Paragraph><Run>x</Run></Paragraph>" + Self.list("Disc", ["Alpha", "Beta"]) + "<Paragraph />")
        #expect(d.paragraphs == ["x", "Alpha", "Beta", ""])
        #expect(caret.location == d.storage.length - 1)                 // start of the block after the list
        #expect(RichListFormatter.insertList(lines: ["", "  "], kind: .numbered, into: d.storage, at: NSRange(location: 0, length: 0))
                == NSRange(location: 0, length: 0))
    }

    // §7.2-2 cycles.
    @Test func normaliseCycles() {
        let d = Doc(##"<List MarkerStyle="Decimal"><ListItem><Paragraph><Run>1</Run></Paragraph><List MarkerStyle="Disc"><ListItem><Paragraph><Run>a</Run></Paragraph><List MarkerStyle="Disc"><ListItem><Paragraph><Run>i</Run></Paragraph></ListItem></List></ListItem></List></ListItem></List>"##)
        RichListFormatter.normalise(d.storage)
        #expect(d.xaml == ##"<List MarkerStyle="Decimal" Margin="0,6,0,6" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>1</Run></Paragraph><List MarkerStyle="LowerLatin" Margin="0,0,0,0" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>a</Run></Paragraph><List MarkerStyle="LowerRoman" Margin="0,0,0,0" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>i</Run></Paragraph></ListItem></List></ListItem></List></ListItem></List>"##)
        #expect(d.storage.string.hasPrefix("\t1.\t1\n\ta.\ta\n\ti.\ti\n"))
        var nested = "<List MarkerStyle=\"Box\"><ListItem><Paragraph><Run>4</Run></Paragraph></ListItem></List>"
        for k in (0..<4).reversed() {
            nested = "<List MarkerStyle=\"Disc\"><ListItem><Paragraph><Run>\(k)</Run></Paragraph>" + nested + "</ListItem></List>"
        }
        let b = Doc(nested)
        RichListFormatter.normalise(b.storage)
        let styles = b.xaml.components(separatedBy: "MarkerStyle=\"").dropFirst().map { $0.prefix { $0 != "\"" } }
        #expect(styles.map(String.init) == ["Disc", "Circle", "Square", "Disc", "Circle"])
        let top = Doc(##"<List MarkerStyle="Box"><ListItem><Paragraph><Run>b</Run></Paragraph></ListItem></List><List MarkerStyle="UpperRoman"><ListItem><Paragraph><Run>r</Run></Paragraph></ListItem></List>"##)
        RichListFormatter.normalise(top.storage)
        #expect(top.xaml.contains(##"<List MarkerStyle="Disc" Margin="0,6,0,6""##) && top.xaml.contains(##"<List MarkerStyle="Decimal" Margin="0,6,0,6""##))
    }

    // §7.2-3.
    @Test func listInATableCellIsDepthZero() {
        let d = Doc(##"<List MarkerStyle="Disc"><ListItem><Paragraph><Run>outer</Run></Paragraph></ListItem></List><Table><TableRowGroup><TableRow><TableCell><List MarkerStyle="Square"><ListItem><Paragraph><Run>c</Run></Paragraph></ListItem></List></TableCell></TableRow></TableRowGroup></Table><Section><List MarkerStyle="LowerRoman"><ListItem><Paragraph><Run>s</Run></Paragraph></ListItem></List></Section>"##)
        RichListFormatter.normalise(d.storage)
        #expect(d.xaml.contains(##"<TableCell><List MarkerStyle="Disc" Margin="0,6,0,6" Padding="24,0,0,0">"##))
        #expect(d.xaml.contains(##"<Section><List MarkerStyle="Decimal" Margin="0,6,0,6" Padding="24,0,0,0">"##))
    }

    // §7.2-4.
    @Test func moveSingleItems() {
        let d = Doc(Self.list("Disc", ["A", "B", "C"]))
        let r = RichListFormatter.moveItem(d.storage, selection: d.at("B", offset: 1), up: true)
        #expect(d.paragraphs.prefix(3) == ["B", "A", "C"])
        #expect(r == d.at("B", offset: 1))                              // caret stays in the moved text
        #expect(RichListFormatter.moveItem(d.storage, selection: d.at("B"), up: true) == nil)
        #expect(RichListFormatter.moveItem(d.storage, selection: d.at("C"), up: false) == nil)
        #expect(d.paragraphs.prefix(3) == ["B", "A", "C"])
    }

    // §7.2-5.
    @Test func subItemsTravel() {
        let d = Doc(##"<List MarkerStyle="Disc"><ListItem><Paragraph><Run>A</Run></Paragraph><List MarkerStyle="Circle"><ListItem><Paragraph><Run>a1</Run></Paragraph></ListItem><ListItem><Paragraph><Run>a2</Run></Paragraph></ListItem></List></ListItem><ListItem><Paragraph><Run>B</Run></Paragraph></ListItem></List>"##)
        #expect(RichListFormatter.moveItem(d.storage, selection: d.at("A"), up: false) != nil)
        #expect(d.paragraphs.prefix(4) == ["B", "A", "a1", "a2"])
        #expect(d.storage.string.hasPrefix("\t•\tB\n\t•\tA\n\t◦\ta1\n"))
    }

    // §7.2-6.
    @Test func groupMoves() {
        let d = Doc(Self.list("Decimal", ["A", "B", "C"]))
        #expect(RichListFormatter.moveItem(d.storage, selection: d.span("B", "C"), up: true) != nil)
        #expect(d.paragraphs.prefix(3) == ["B", "C", "A"])
        #expect(d.storage.string.hasPrefix("\t1.\tB\n\t2.\tC\n\t3.\tA\n"))       // numbers renumber
        let e = Doc(Self.list("Disc", ["A", "B", "C"]))
        #expect(RichListFormatter.moveItem(e.storage, selection: e.span("A", "B"), up: false) != nil)
        #expect(e.paragraphs.prefix(3) == ["C", "A", "B"])
    }

    // §7.2-7 / -8.
    @Test func blockMoves() {
        let two = Doc(Self.list("Disc", ["A"]) + "<Paragraph><Run>mid</Run></Paragraph>" + Self.list("Disc", ["B"]))
        // Items of two different lists → the caret's outermost block (its paragraph inside its item) moves: nowhere.
        #expect(RichListFormatter.moveItem(two.storage, selection: two.span("A", "B"), up: false) == nil)
        let d = Doc("<Paragraph><Run>P1</Run></Paragraph><Paragraph><Run>P2</Run></Paragraph>" + Self.list("Disc", ["L"]))
        #expect(RichListFormatter.moveItem(d.storage, selection: d.at("P2"), up: false) != nil)
        #expect(d.paragraphs == ["P1", "L", "P2"])
        let u = Doc("<Paragraph><Run>P1</Run></Paragraph><Paragraph><Run>P2</Run></Paragraph>" + Self.list("Disc", ["L"]))
        #expect(RichListFormatter.moveItem(u.storage, selection: u.at("P2"), up: true) != nil)
        #expect(u.paragraphs == ["P2", "P1", "L"])
        // A paragraph in a nested Section moves the whole section.
        let s = Doc("<Section><Paragraph><Run>S1</Run></Paragraph><Paragraph><Run>S2</Run></Paragraph></Section><Paragraph><Run>after</Run></Paragraph>")
        #expect(RichListFormatter.moveItem(s.storage, selection: s.at("S2"), up: false) != nil)
        #expect(s.paragraphs == ["after", "S1", "S2"])
    }

    // §7.2-9 (non-contiguous items can only reach MoveItems through the tree API).
    @Test func nonContiguousMove() {
        let d = Doc(Self.list("Disc", ["A", "B", "C", "D"]))
        let t = RichEditTree(RichDoc.build(from: d.storage))
        let list = t.root.children.compactMap(\.asContainer).first!
        let items = list.children.compactMap(\.asContainer)
        #expect(t.moveItems([items[0], items[2]], up: false))
        #expect(list.children.compactMap { $0.asContainer?.children.first?.asPara?.content.string } == ["B", "D", "A", "C"])
    }

    // §7.2-10.
    @Test func paragraphIndentSteps() {
        let d = Doc("<Paragraph><Run>p</Run></Paragraph>")
        _ = RichListFormatter.indent(d.storage, selection: d.at("p"))
        #expect(d.xaml == ##"<Paragraph Margin="24,Auto,Auto,Auto"><Run>p</Run></Paragraph>"##)
        _ = RichListFormatter.indent(d.storage, selection: d.at("p"))
        #expect(d.xaml == ##"<Paragraph Margin="48,Auto,Auto,Auto"><Run>p</Run></Paragraph>"##)
        #expect((d.storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle).headIndent == 48)
        let o = Doc(##"<Paragraph Margin="10,0,0,0" TextIndent="20"><Run>p</Run></Paragraph>"##)
        _ = RichListFormatter.outdent(o.storage, selection: o.at("p"))
        #expect(o.xaml == ##"<Paragraph Margin="0,0,0,0"><Run>p</Run></Paragraph>"##)
        let a = Doc(##"<Paragraph Margin="Auto"><Run>p</Run></Paragraph>"##)
        _ = RichListFormatter.indent(a.storage, selection: a.at("p"))
        #expect(a.xaml == ##"<Paragraph Margin="24,Auto,Auto,Auto"><Run>p</Run></Paragraph>"##)
        // Every touched paragraph, not only the caret's.
        let m = Doc("<Paragraph><Run>one</Run></Paragraph><Paragraph><Run>two</Run></Paragraph>")
        _ = RichListFormatter.indent(m.storage, selection: m.span("one", "two"))
        #expect(m.xaml.components(separatedBy: "Margin=\"24").count == 3)
    }

    // CONT-040 / 041.
    @Test func toggleLists() {
        let d = Doc("<Paragraph><Run>a</Run></Paragraph><Paragraph><Run>b</Run></Paragraph><Paragraph><Run>c</Run></Paragraph>")
        let sel = RichListFormatter.toggleList(.bullets, in: d.storage, selection: d.span("a", "c"))
        #expect(d.xaml == Self.list("Disc", ["a", "b", "c"]))
        #expect((d.storage.string as NSString).substring(with: sel) == "a\n\t•\tb\n\t•\tc")
        _ = RichListFormatter.toggleList(.numbered, in: d.storage, selection: d.at("b"))
        #expect(d.xaml == Self.list("Decimal", ["a", "b", "c"]))       // a numbered toggle on a bullet list switches it
        _ = RichListFormatter.toggleList(.numbered, in: d.storage, selection: d.at("b"))
        #expect(d.xaml == Self.list("Decimal", ["a"]) + ##"<Paragraph Margin="0,1,0,1"><Run>b</Run></Paragraph>"## + Self.list("Decimal", ["c"]))
        // A plain paragraph next to a list of the same style joins it (WPF MergeLists).
        _ = RichListFormatter.toggleList(.numbered, in: d.storage, selection: d.at("b"))
        #expect(d.xaml == Self.list("Decimal", ["a", "b", "c"]))
    }

    // CONT-043 / 044 / §6.5.
    @Test func tabAndShiftTabAtItemStart() {
        let d = Doc(Self.list("Disc", ["A", "B", "C"]))
        #expect(RichListFormatter.isAtItemStart(d.storage, location: d.at("B").location))
        #expect(!RichListFormatter.isAtItemStart(d.storage, location: d.at("B", offset: 1).location))
        #expect(RichListFormatter.handleTab(d.storage, selection: d.at("B", offset: 1), shift: false) == nil)
        let r = RichListFormatter.handleTab(d.storage, selection: d.at("B"), shift: false)
        #expect(r == d.at("B"))
        #expect(d.xaml == ##"<List MarkerStyle="Disc" Margin="0,6,0,6" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>A</Run></Paragraph><List MarkerStyle="Circle" Margin="0,0,0,0" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>B</Run></Paragraph></ListItem></List></ListItem><ListItem><Paragraph Margin="0,1,0,1"><Run>C</Run></Paragraph></ListItem></List>"##)
        // C nests into A's existing sub-list.
        _ = RichListFormatter.handleTab(d.storage, selection: d.at("C"), shift: false)
        #expect(d.storage.string.hasPrefix("\t•\tA\n\t◦\tB\n\t◦\tC\n"))
        // The first item cannot nest (no previous sibling): handled, unchanged.
        let before = d.xaml
        _ = RichListFormatter.handleTab(d.storage, selection: d.at("A"), shift: false)
        #expect(d.xaml == before)
        // ⇧Tab on B: back to level 1, and C (its later sibling) becomes B's sub-item.
        _ = RichListFormatter.handleTab(d.storage, selection: d.at("B"), shift: true)
        #expect(d.storage.string.hasPrefix("\t•\tA\n\t•\tB\n\t◦\tC\n"))
        // ⇧Tab at the top level leaves the list.
        _ = RichListFormatter.handleTab(d.storage, selection: d.at("A"), shift: true)
        #expect(d.paragraphs.prefix(3) == ["A", "B", "C"])
        #expect(d.xaml.hasPrefix(##"<Paragraph Margin="0,1,0,1"><Run>A</Run></Paragraph><List MarkerStyle="Disc""##))
    }

    @Test func returnInAListItem() {
        let d = Doc(Self.list("Decimal", ["Alpha", "Beta"]))
        let r = RichListFormatter.handleReturn(d.storage, selection: d.at("Alpha", offset: 2))
        #expect(d.paragraphs.prefix(3) == ["Al", "pha", "Beta"])
        #expect(d.storage.string.hasPrefix("\t1.\tAl\n\t2.\tpha\n\t3.\tBeta\n"))
        #expect(r == d.at("pha"))
        // Return on an empty item leaves the list.
        let e = Doc(Self.list("Disc", ["x"]) + "<Paragraph><Run>after</Run></Paragraph>")
        let r1 = RichListFormatter.handleReturn(e.storage, selection: e.at("x", offset: 1))!
        #expect(e.paragraphs.prefix(2) == ["x", ""])
        let r2 = RichListFormatter.handleReturn(e.storage, selection: r1)
        #expect(r2 != nil)
        #expect(e.xaml.hasPrefix(Self.list("Disc", ["x"]) + ##"<Paragraph Margin="0,1,0,1" />"##))
        // Outside a list: not handled.
        #expect(RichListFormatter.handleReturn(e.storage, selection: e.at("after")) == nil)
        // Splitting an item that has sub-items moves them under the new item.
        let s = Doc(##"<List MarkerStyle="Disc"><ListItem><Paragraph><Run>AB</Run></Paragraph><List MarkerStyle="Circle"><ListItem><Paragraph><Run>sub</Run></Paragraph></ListItem></List></ListItem></List>"##)
        _ = RichListFormatter.handleReturn(s.storage, selection: s.at("AB", offset: 1))
        #expect(s.storage.string.hasPrefix("\t•\tA\n\t•\tB\n\t◦\tsub\n"))
    }

    @Test func backspaceAtItemStart() {
        let d = Doc(##"<List MarkerStyle="Disc"><ListItem><Paragraph><Run>A</Run></Paragraph><List MarkerStyle="Circle"><ListItem><Paragraph><Run>B</Run></Paragraph></ListItem></List></ListItem></List>"##)
        #expect(RichListFormatter.handleBackspaceAtItemStart(d.storage, selection: d.at("B", offset: 1)) == nil)
        let r = RichListFormatter.handleBackspaceAtItemStart(d.storage, selection: d.at("B"))
        #expect(r == d.at("B"))
        #expect(d.storage.string.hasPrefix("\t•\tA\n\t•\tB\n"))
        _ = RichListFormatter.handleBackspaceAtItemStart(d.storage, selection: d.at("B"))
        #expect(d.paragraphs.prefix(2) == ["A", "B"])
        #expect(d.storage.string.hasPrefix("\t•\tA\nB\n"))
        #expect(RichListFormatter.handleBackspaceAtItemStart(d.storage, selection: d.at("B")) == nil)
    }

    // CONT-047 step 5.
    @Test func insertListIntoItemsCellsAndEmptyDocuments() {
        let item = Doc(Self.list("Disc", ["host", "next"]))
        _ = RichListFormatter.insertList(lines: ["n1", "n2"], kind: .numbered, into: item.storage, at: item.at("host", offset: 2))
        // A numbered list nested in a bullet item takes the number cycle at depth 1 (a., b.); the list ends the
        // item's block collection, so an empty paragraph follows it inside the item.
        #expect(item.storage.string.hasPrefix("\t•\thost\n\ta.\tn1\n\tb.\tn2\n\n\t•\tnext\n"))
        let cell = Doc(##"<Table><TableRowGroup><TableRow><TableCell><Paragraph><Run>c</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table><Paragraph><Run>after</Run></Paragraph>"##)
        let caret = RichListFormatter.insertList(lines: ["x"], kind: .bullets, into: cell.storage, at: cell.at("c"))
        #expect(cell.xaml.contains(##"<TableCell><Paragraph><Run>c</Run></Paragraph><List MarkerStyle="Disc" Margin="0,6,0,6" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>x</Run></Paragraph></ListItem></List><Paragraph /></TableCell>"##))
        let cellPara = (cell.storage.string as NSString).range(of: "x\n").location + 2
        #expect(caret.location == cellPara)
        let empty = NSTextStorage()
        let e = RichListFormatter.insertList(lines: ["a"], kind: .bullets, into: empty, at: NSRange(location: 0, length: 0))
        #expect(empty.string == "\n\t•\ta\n\n" && e.location == empty.length - 1)
        // A live selection is left alone; the list goes after the selection's end paragraph.
        let sel = Doc("<Paragraph><Run>one</Run></Paragraph><Paragraph><Run>two</Run></Paragraph>")
        _ = RichListFormatter.insertList(lines: ["L"], kind: .bullets, into: sel.storage, at: sel.span("one", "tw"))
        #expect(sel.paragraphs == ["one", "two", "L", ""])
        // Inserted text takes the destination paragraph's character context, not its link or lock.
        let ctx = Doc(##"<Paragraph FontSize="20"><Run Background="#FFFFE699">locked</Run></Paragraph>"##)
        _ = RichListFormatter.insertList(lines: ["new"], kind: .bullets, into: ctx.storage, at: ctx.at("locked"))
        let a = RichTest.attrs(ctx.storage, at: "new")
        #expect((a[.font] as! NSFont).pointSize == 20 && a[.backgroundColor] == nil && a[.aaLockSource] == nil)
    }

    @Test func selectionMappingAcrossRenumbering() {
        let d = Doc("<Paragraph><Run>alpha</Run></Paragraph><Paragraph><Run>beta</Run></Paragraph>")
        let r = RichListFormatter.toggleList(.bullets, in: d.storage, selection: NSRange(location: d.at("beta").location + 2, length: 1))
        #expect((d.storage.string as NSString).substring(with: r) == "t")
    }
}
