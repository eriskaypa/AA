// TV: 05 CONT-161 (fragment insertion: destination context; first and last paragraphs touched keep the destination
//     paragraph's attributes; middle blocks keep their own), CONT-035 + §6.6 (HTML and own-XAML paste: no stray
//     paragraph break), §3.1 `InsertListAtCaret` (blocks go into the caret paragraph's own collection: document, list
//     item, table cell), §6.4 "Paragraph" read in reverse for AppKit-native (RTF) paragraphs.
import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct RichFragmentInsertionTests {
    static let one = RichTest.doc(##"<Paragraph><Run FontWeight="Bold">X</Run></Paragraph>"##)
    static let two = RichTest.doc(##"<Paragraph><Run FontWeight="Bold">P1</Run></Paragraph><Paragraph><Run>P2</Run></Paragraph>"##)
    static let list = RichTest.doc(##"<List MarkerStyle="Decimal"><ListItem><Paragraph><Run>L1</Run></Paragraph></ListItem></List>"##)
    static let centred = ##"<Paragraph TextAlignment="Center" FontSize="20"><Run>abcd</Run></Paragraph>"##
    static let bullets = ##"<List MarkerStyle="Disc" Margin="0,6,0,6" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>Alpha</Run></Paragraph></ListItem><ListItem><Paragraph Margin="0,1,0,1"><Run>Beta</Run></Paragraph></ListItem></List><Paragraph><Run>after</Run></Paragraph>"##
    static let cell = ##"<Table CellSpacing="0"><TableRowGroup><TableRow><TableCell><Paragraph><Run>cell</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table><Paragraph><Run>z</Run></Paragraph>"##

    /// Inserts `fragment` into the S-1 document `body` at `needle` + `delta` (replacing `length` characters); returns
    /// the written body and the text from the returned caret on.
    static func insert(_ body: String, _ fragment: String, at needle: String, delta: Int = 0,
                       length: Int = 0) -> (body: String, caret: String) {
        let (s, m) = RichTest.read(RichTest.doc(body))
        let storage = NSTextStorage(attributedString: s)
        let loc = (storage.string as NSString).range(of: needle).location + delta
        guard let r = XamlReader.insertFragment(fragment, into: storage, replacing: NSRange(location: loc, length: length),
                                                base: .containerEditor) else { return ("nil", "") }
        let rest = (storage.string as NSString).substring(from: r.location)
        return (RichTest.body(XamlWriter.write(storage, metadata: m, context: .containerEditor)), String(rest.prefix(4)))
    }

    @Test func readFragmentCarriesNoFinalBreakAfterAParagraph() throws {
        #expect(try #require(XamlReader.readFragment(Self.one, destinationContext: .containerEditor)).string == "X")
        #expect(try #require(XamlReader.readFragment(Self.two, destinationContext: .containerEditor)).string == "P1\nP2")
        // A fragment ending with a structure keeps it (the structure stays a block of its own).
        #expect(try #require(XamlReader.readFragment(Self.list, destinationContext: .containerEditor)).string == "\t1.\tL1\n")
        let s2 = try #require(XamlReader.readFragment(try RichTest.sample("S-02-nested-bullets.xaml"),
                                                       destinationContext: .containerEditor))
        #expect(s2.string.hasSuffix("Beta\n"))
        // Inline web selection: `<b>Hi</b>` pastes as "Hi", no new line (CONT-035).
        #expect(try #require(XamlReader.readFragment(HTMLToXAML.convert("<b>Hi</b>"), destinationContext: .containerEditor)).string == "Hi")
    }

    @Test func singleParagraphMergesIntoTheDestination() {
        let mid = Self.insert(Self.centred, Self.one, at: "abcd", delta: 2)
        #expect(mid.body == ##"<Paragraph FontSize="20" TextAlignment="Center"><Run>ab</Run><Run FontWeight="Bold" FontSize="14">X</Run><Run>cd</Run></Paragraph>"##)
        #expect(mid.caret == "cd\n")
        // At the paragraph start the paragraph still keeps its own attributes (CONT-161), not the fragment's.
        let start = Self.insert(Self.centred, Self.one, at: "abcd")
        #expect(start.body == ##"<Paragraph FontSize="20" TextAlignment="Center"><Run FontWeight="Bold" FontSize="14">X</Run><Run>abcd</Run></Paragraph>"##)
        // A context-less HTML fragment takes the destination paragraph's computed style.
        let html = Self.insert(Self.centred, HTMLToXAML.convert("<b>web</b> text"), at: "abcd", delta: 2)
        #expect(html.body == ##"<Paragraph FontSize="20" TextAlignment="Center"><Run>ab</Run><Run FontWeight="Bold">web</Run><Run> textcd</Run></Paragraph>"##)
    }

    @Test func paragraphsPastedIntoAListItemStayInTheItem() {
        let r = Self.insert(Self.bullets, Self.two, at: "Beta", delta: 2)
        #expect(r.body == ##"<List MarkerStyle="Disc" Margin="0,6,0,6" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>Alpha</Run></Paragraph></ListItem><ListItem><Paragraph Margin="0,1,0,1"><Run>Be</Run><Run FontWeight="Bold">P1</Run></Paragraph><Paragraph Margin="0,1,0,1"><Run>P2ta</Run></Paragraph></ListItem></List><Paragraph><Run>after</Run></Paragraph>"##)
        #expect(r.caret == "ta\na")
        // A web list pasted at the end of an item nests inside that item.
        let h = Self.insert(Self.bullets, HTMLToXAML.convert("<p>p</p><ul><li>u1</li></ul>"), at: "Beta", delta: 4)
        #expect(h.body.contains(##"<ListItem><Paragraph Margin="0,1,0,1"><Run>Betap</Run></Paragraph><List MarkerStyle="Disc"><ListItem><Paragraph><Run>u1</Run></Paragraph></ListItem></List>"##))
    }

    @Test func structuresSplitTheDestinationParagraph() throws {
        let c = Self.insert(Self.centred, Self.list, at: "abcd", delta: 2)
        #expect(c.body == ##"<Paragraph FontSize="20" TextAlignment="Center"><Run>ab</Run></Paragraph><List MarkerStyle="Decimal"><ListItem><Paragraph><Run>L1</Run></Paragraph></ListItem></List><Paragraph FontSize="20" TextAlignment="Center"><Run>cd</Run></Paragraph>"##)
        #expect(c.caret == "cd\n")
        // A table pasted at a paragraph start goes before it (no empty paragraph left behind).
        let table = try RichTest.sample("S-04-table-2x2.xaml")
        let d = Self.insert(Self.centred, table, at: "abcd")
        #expect(d.body.hasPrefix("<Table ") && d.body.hasSuffix(##"</Table><Paragraph FontSize="20" TextAlignment="Center"><Run>abcd</Run></Paragraph>"##))
        // …and at its end leaves an empty paragraph for the caret after it.
        let e = Self.insert(Self.centred, table, at: "abcd", delta: 4)
        #expect(e.body.hasPrefix(##"<Paragraph FontSize="20" TextAlignment="Center"><Run>abcd</Run></Paragraph><Table "##))
        #expect(e.body.hasSuffix(##"</Table><Paragraph TextAlignment="Center" FontSize="20" />"##) && e.caret == "\n")
    }

    @Test func pastesIntoATableCellStayInTheCell() {
        let p = Self.insert(Self.cell, Self.two, at: "cell", delta: 2)
        #expect(p.body == ##"<Table CellSpacing="0"><Table.Columns><TableColumn /></Table.Columns><TableRowGroup><TableRow><TableCell><Paragraph><Run>ce</Run><Run FontWeight="Bold">P1</Run></Paragraph><Paragraph><Run>P2ll</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table><Paragraph><Run>z</Run></Paragraph>"##)
        let l = Self.insert(Self.cell, Self.list, at: "cell", delta: 2)
        #expect(l.body.contains(##"<TableCell><Paragraph><Run>ce</Run></Paragraph><List MarkerStyle="Decimal"><ListItem><Paragraph><Run>L1</Run></Paragraph></ListItem></List><Paragraph><Run>ll</Run></Paragraph></TableCell>"##))
    }

    @Test func replacesTheSelectionAndFillsAnEmptyDocument() throws {
        let g = Self.insert(Self.centred, Self.two, at: "abcd", delta: 1, length: 2)
        #expect(g.body == ##"<Paragraph FontSize="20" TextAlignment="Center"><Run>a</Run><Run FontWeight="Bold" FontSize="14">P1</Run></Paragraph><Paragraph FontSize="20" TextAlignment="Center"><Run FontSize="14">P2</Run><Run>d</Run></Paragraph>"##)
        let empty = NSTextStorage()
        let r = try #require(XamlReader.insertFragment(Self.two, into: empty, replacing: NSRange(location: 0, length: 0),
                                                       base: .containerEditor))
        #expect(empty.string == "P1\nP2\n" && r == NSRange(location: 5, length: 0))
        #expect(XamlReader.insertFragment("<Section", into: empty, replacing: NSRange(location: 0, length: 0),
                                          base: .containerEditor) == nil)
        #expect(XamlReader.insertFragment("  ", into: empty, replacing: NSRange(location: 0, length: 0),
                                          base: .containerEditor) == nil)
        #expect(empty.string == "P1\nP2\n")
    }

    @Test func nativeParagraphIndentsAreWrittenAsMargins() throws {
        let rtf = #"{\rtf1\ansi{\fonttbl\f0 Helvetica;}\f0\fs24\li720\fi-360 indented\par\pard plain\par}"#
        let s = try NSAttributedString(data: Data(rtf.utf8), options: [.documentType: NSAttributedString.DocumentType.rtf],
                                       documentAttributes: nil)
        let out = RichTest.body(XamlWriter.write(s, metadata: RichTextMetadata(context: .containerEditor), context: .containerEditor))
        #expect(out == ##"<Paragraph Margin="36,Auto,Auto,Auto" TextIndent="-18"><Run FontFamily="Helvetica" FontSize="12">indented</Run></Paragraph><Paragraph><Run FontFamily="Helvetica" FontSize="12">plain</Run></Paragraph>"##)
        // Read back, the indent is modelled: a second write is identical.
        let (back, m) = RichTest.read(RichTest.doc(out))
        #expect(RichTest.body(XamlWriter.write(back, metadata: m, context: .containerEditor)) == out)
        // Text typed into a fresh document (renderer paragraph style, no model) never gains a margin.
        let typed = NSAttributedString(string: "x\ny\n", attributes: XamlReader.typingAttributes(for: RichTextMetadata(context: .containerEditor)))
        #expect(RichTest.body(XamlWriter.write(typed, metadata: RichTextMetadata(context: .containerEditor), context: .containerEditor))
                == "<Paragraph><Run>x</Run></Paragraph><Paragraph><Run>y</Run></Paragraph>")
    }
}
