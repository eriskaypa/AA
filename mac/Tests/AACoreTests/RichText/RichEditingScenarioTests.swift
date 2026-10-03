// TV: 05 §6.4 / §6.6 (RTF-pasted lists and tables are AppKit-native: NSTextList / NSTextTable without W-RICH
//     structure), CONT-161 (copy as XAML → paste as a fragment), CONT-163 "Paragraph identity" (Return copies the
//     paragraph's attributes), §6.4 (the paragraph after a final table), §4.3.7 rules 6–7 (writer from TextKit
//     structures).
import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct RichEditingScenarioTests {
    static let base = RichEditTree.defaultCharacterAttributes

    static func write(_ s: NSAttributedString, _ m: RichTextMetadata = RichTextMetadata(context: .containerEditor)) -> String {
        RichTest.body(XamlWriter.write(s, metadata: m, context: .containerEditor))
    }

    @Test func appKitNativeListsAreWrittenAsLists() {
        let list = NSTextList(markerFormat: .decimal, options: 0)
        let ps = NSMutableParagraphStyle()
        ps.textLists = [list]
        var a = Self.base
        a[.paragraphStyle] = ps
        let s = NSMutableAttributedString(string: "\t1.\tOne\n\t2.\tTwo\n", attributes: a)
        s.append(NSAttributedString(string: "after\n", attributes: Self.base))
        #expect(Self.write(s) == ##"<List MarkerStyle="Decimal"><ListItem><Paragraph><Run>One</Run></Paragraph></ListItem><ListItem><Paragraph><Run>Two</Run></Paragraph></ListItem></List><Paragraph><Run>after</Run></Paragraph>"##)
        // Normalising such a list gives it the full W-RICH structure.
        let storage = NSTextStorage(attributedString: s)
        RichListFormatter.normalise(storage)
        #expect(storage.string == "\t1.\tOne\n\t2.\tTwo\nafter\n")
        #expect(Self.write(storage).hasPrefix(##"<List MarkerStyle="Decimal" Margin="0,6,0,6" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1">"##))
    }

    @Test func appKitNativeTablesAreWrittenAsTables() {
        let t = NSTextTable()
        t.numberOfColumns = 2
        t.collapsesBorders = true
        let s = NSMutableAttributedString()
        for (k, text) in ["A", "B", "C", "D"].enumerated() {
            let cell = NSTextTableBlock(table: t, startingRow: k / 2, rowSpan: 1, startingColumn: k % 2, columnSpan: 1)
            cell.setWidth(1, type: .absoluteValueType, for: .border)
            cell.setBorderColor(.black)
            let ps = NSMutableParagraphStyle()
            ps.textBlocks = [cell]
            var a = Self.base
            a[.paragraphStyle] = ps
            s.append(NSAttributedString(string: text + "\n", attributes: a))
        }
        let out = Self.write(s)
        #expect(out.hasPrefix(##"<Table CellSpacing="0"><Table.Columns><TableColumn /><TableColumn /></Table.Columns><TableRowGroup><TableRow><TableCell BorderBrush="#FF000000" BorderThickness="1,1,1,1"><Paragraph><Run>A</Run></Paragraph></TableCell>"##), "\(out)")
        #expect(out.components(separatedBy: "<TableRow>").count == 3)
        #expect(out.hasSuffix("</TableRowGroup></Table>"))
    }

    @Test func returnInOrdinaryTextCopiesTheParagraphsAttributes() {
        let (s, m) = RichTest.read(RichTest.doc(##"<Section Tag="s"><Paragraph FontSize="20" TextAlignment="Center"><Run>one</Run></Paragraph></Section>"##))
        let e = NSMutableAttributedString(attributedString: s)
        // What NSTextView does on Return at the end of "one": insert "\n" with the typing attributes, then type.
        let typing = e.attributes(at: 2, effectiveRange: nil)
        e.insert(NSAttributedString(string: "\ntwo", attributes: typing), at: 3)
        #expect(Self.write(e, m) == ##"<Section Tag="s"><Paragraph FontSize="20" TextAlignment="Center"><Run>one</Run></Paragraph><Paragraph FontSize="20" TextAlignment="Center"><Run>two</Run></Paragraph></Section>"##)
    }

    @Test func copyAsXamlAndPasteAsAFragment() throws {
        let (s, m) = RichTest.read(RichTest.doc(##"<Paragraph><Run>intro</Run></Paragraph><List MarkerStyle="Decimal" Margin="0,6,0,6" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run FontWeight="Bold">first</Run></Paragraph></ListItem><ListItem><Paragraph Margin="0,1,0,1"><Run>second</Run></Paragraph></ListItem></List>"##))
        let ns = s.string as NSString
        let from = ns.range(of: "\t1.").location
        let copied = XamlWriter.write(s.attributedSubstring(from: NSRange(location: from, length: s.length - from)),
                                      metadata: m, context: .containerEditor)
        #expect(copied.hasPrefix(RichTest.s1))                       // the source document's completed root (CONT-161)
        let pasted = try #require(XamlReader.readFragment(copied, destinationContext: .sirePane))
        #expect(RichTest.paragraphs(pasted) == ["first", "second"])
        #expect(RichFontResolver.isBoldish(RichTest.attrs(pasted, at: "first")[.font] as! NSFont))
        #expect(RichTest.attrs(pasted, at: "first")[.aaFontFamilyName] as? String == "Consolas")
        let ids = Set(["first", "second"].compactMap { RichTest.attrs(pasted, at: $0)[.aaListItemID] as? String })
        #expect(ids.count == 2)
        // Pasting the same fragment twice into one document keeps two separate lists.
        let doc = NSMutableAttributedString(attributedString: pasted)
        doc.append(NSAttributedString(string: "between\n", attributes: Self.base))
        doc.append(try #require(XamlReader.readFragment(copied, destinationContext: .containerEditor)))
        #expect(Self.write(doc).components(separatedBy: "<List ").count == 3)
    }

    @Test func typingIntoTheParagraphAfterAFinalTableIsWritten() throws {
        let (s, m) = RichTest.read(try RichTest.sample("S-04-table-2x2.xaml"))
        #expect(!Self.write(s, m).hasSuffix("<Paragraph />"))         // the synthetic paragraph stays invisible
        let e = NSMutableAttributedString(attributedString: s)
        e.insert(NSAttributedString(string: "notes", attributes: e.attributes(at: e.length - 1, effectiveRange: nil)), at: e.length - 1)
        #expect(Self.write(e, m).hasSuffix("</Table><Paragraph><Run>notes</Run></Paragraph>"))
    }

    @Test func listOperationsInsideATableKeepTheTable() {
        let (s, m) = RichTest.read(RichTest.doc(##"<Table CellSpacing="0"><Table.Columns><TableColumn /><TableColumn /></Table.Columns><TableRowGroup><TableRow><TableCell><Paragraph><Run>a</Run></Paragraph><Paragraph><Run>b</Run></Paragraph></TableCell><TableCell><Paragraph><Run>c</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table><Paragraph><Run>after</Run></Paragraph>"##))
        let storage = NSTextStorage(attributedString: s)
        let r = (storage.string as NSString).range(of: "a\nb")
        _ = RichListFormatter.toggleList(.bullets, in: storage, selection: r)
        let out = Self.write(storage, m)
        #expect(out.contains(##"<TableCell><List MarkerStyle="Disc" Margin="0,6,0,6" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>a</Run></Paragraph></ListItem><ListItem><Paragraph Margin="0,1,0,1"><Run>b</Run></Paragraph></ListItem></List></TableCell><TableCell><Paragraph><Run>c</Run></Paragraph></TableCell>"##), "\(out)")
        let blocks = (0..<storage.length).compactMap {
            ((storage.attribute(.paragraphStyle, at: $0, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock)?.table
        }
        #expect(Set(blocks.map(ObjectIdentifier.init)).count == 1)  // still one table after the re-render
    }

    @Test func deletingEverythingWritesTheEmptyDocument() throws {
        let (s, m) = RichTest.read(try RichTest.sample("S-01-editor-save.xaml"))
        let e = NSMutableAttributedString(attributedString: s)
        e.deleteCharacters(in: NSRange(location: 0, length: e.length))
        #expect(XamlWriter.write(e, metadata: m, context: .containerEditor) == "")
    }
}
