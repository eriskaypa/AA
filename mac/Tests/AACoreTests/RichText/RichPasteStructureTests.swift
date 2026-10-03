// TV: 05 CONT-035/036/037 (HTML, own-XAML and RTF paste keep every list item and table cell), CONT-161 (fragment
//     insertion splits the destination paragraph; blocks go into its block collection), §6.4 "Always keep an
//     ordinary paragraph after a table", DEVIATIONS RICH-I03 (lists and tables survive in-app copy/paste).
// Round-2 finding V2-J3 "Pasting a list or table into a non-empty paragraph breaks its structure": the W-RICH half —
// `XamlReader.insertFragment` (XAML / HTML) and `insertFragment(attributed:)` (RTF / RTFD) give the WPF paste shape
// for every journey case the verifier recorded; W-CONT / W-SIRE route their paste pipelines through them.
import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct RichPasteStructureTests {
    static var base: [NSAttributedString.Key: Any] { XamlReader.typingAttributes(for: RichTextMetadata(context: .containerEditor)) }
    static let htmlTable = "<table><tr><td>a</td><td>b</td></tr></table>"
    static let bullets = ##"<List MarkerStyle="Disc"><ListItem><Paragraph><Run>One</Run></Paragraph></ListItem><ListItem><Paragraph><Run>Two</Run></Paragraph></ListItem><ListItem><Paragraph><Run>Three</Run></Paragraph></ListItem></List>"##

    static func storage(_ text: String) -> NSTextStorage { NSTextStorage(string: text, attributes: base) }

    static func loc(_ s: NSAttributedString, _ sub: String) -> Int {
        let r = (s.string as NSString).range(of: sub)
        precondition(r.location != NSNotFound, "missing \(sub)")
        return r.location
    }

    static func inList(_ s: NSAttributedString, _ sub: String) -> Bool {
        ((s.attribute(.paragraphStyle, at: loc(s, sub), effectiveRange: nil) as? NSParagraphStyle)?.textLists.isEmpty) == false
    }

    static func inTable(_ s: NSAttributedString, _ sub: String) -> Bool { EditorBlocks.isTableParagraph(s, at: loc(s, sub)) }

    static func written(_ s: NSAttributedString) -> String {
        RichTest.body(XamlWriter.write(s, metadata: RichTextMetadata(context: .containerEditor), context: .containerEditor))
    }

    /// A real TextKit 1 NSTextView over `s` (Return and typing as the user does them).
    static var views: [NSTextView] = []
    static func textView(_ s: NSTextStorage) -> NSTextView {
        let lm = NSLayoutManager()
        s.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: 500, height: 1e7))
        lm.addTextContainer(tc)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500), textContainer: tc)
        tv.isRichText = true
        tv.isEditable = true
        tv.smartInsertDeleteEnabled = false
        views.append(tv)
        return tv
    }

    /// Verifier journey `pastedTableAtEnd` / `htmlTablePasteThroughController`: a web table pasted at the end of
    /// "Intro" keeps both cells, "Intro" stays an ordinary paragraph, and Return + typing after it lands below the table.
    @Test func htmlTableAtTheEndOfAParagraph() throws {
        let s = Self.storage("Intro")
        let caret = try #require(XamlReader.insertFragment(HTMLToXAML.convert(Self.htmlTable), into: s,
                                                          replacing: NSRange(location: 5, length: 0), base: .containerEditor))
        #expect(!Self.inTable(s, "Intro") && Self.inTable(s, "a") && Self.inTable(s, "b"), "\(s.string.debugDescription)")
        let body = Self.written(s)
        #expect(body.hasPrefix("<Paragraph><Run>Intro</Run></Paragraph><Table"), "\(body)")
        #expect(body.contains("<Run>a</Run>") && body.contains("<Run>b</Run>") && !body.contains("Introa"), "\(body)")
        // The caret lands in the ordinary paragraph after the table (§6.4), not in the last cell.
        #expect(caret.location > Self.loc(s, "b") && !EditorBlocks.isTableParagraph(s, at: min(caret.location, s.length - 1)))
        let tv = Self.textView(s)
        tv.setSelectedRange(caret)
        tv.insertText("plainA", replacementRange: tv.selectedRange())
        tv.setSelectedRange(NSRange(location: s.length, length: 0))
        tv.insertNewline(nil)
        tv.insertText("plainB", replacementRange: tv.selectedRange())
        #expect(!Self.inTable(s, "plainA") && !Self.inTable(s, "plainB"), "\(s.string.debugDescription)")
        let after = Self.written(s)
        #expect(after.contains("</Table><Paragraph><Run>plainA</Run></Paragraph>"), "\(after)")
    }

    /// Verifier journey `pasteStructureMidParagraph`: a web list / table pasted mid-paragraph splits the paragraph
    /// ("Intro" before, " tail" after) and keeps every item / cell.
    @Test func htmlListAndTableMidParagraph() throws {
        for (html, first, second) in [("<ul><li>x1</li><li>x2</li></ul>", "x1", "x2"), (Self.htmlTable, "a", "b")] {
            let s = Self.storage("Intro tail")
            #expect(XamlReader.insertFragment(HTMLToXAML.convert(html), into: s, replacing: NSRange(location: 5, length: 0),
                                              base: .containerEditor) != nil)
            let isList = first == "x1"
            let structured = { (sub: String) in isList ? Self.inList(s, sub) : Self.inTable(s, sub) }
            #expect(structured(first) && structured(second), "\(s.string.debugDescription)")
            #expect(!structured("Intro") && !structured(" tail"))
            let body = Self.written(s)
            #expect(body.hasPrefix("<Paragraph><Run>Intro</Run></Paragraph>"), "\(body)")
            #expect(body.hasSuffix("<Paragraph><Run> tail</Run></Paragraph>"), "\(body)")
            let (r, _) = RichTest.read(RichTest.doc(body))
            #expect(RichTest.paragraphs(r).filter { !$0.isEmpty } == ["Intro", first, second, " tail"])
        }
    }

    /// Verifier journey `copyPasteOwnXamlList`: an AA list copied as the own XAML type (the editor's `selectedXaml`
    /// is `XamlWriter.write` of the selection) and pasted after "Intro" keeps all three items.
    @Test func ownXamlListCopyPaste() throws {
        let (src, _) = RichTest.read(RichTest.doc(Self.bullets))
        let copied = XamlWriter.write(src, metadata: RichTextMetadata(context: .containerEditor), context: .containerEditor)
        let s = Self.storage("Intro")
        #expect(XamlReader.insertFragment(copied, into: s, replacing: NSRange(location: 5, length: 0), base: .containerEditor) != nil)
        #expect(!Self.inList(s, "Intro") && Self.inList(s, "One") && Self.inList(s, "Two") && Self.inList(s, "Three"))
        let body = Self.written(s)
        #expect(!body.contains("IntroOne"), "\(body)")
        #expect(body.hasPrefix(##"<Paragraph><Run>Intro</Run></Paragraph><List MarkerStyle="Disc""##), "\(body)")
        #expect(body.components(separatedBy: "<ListItem>").count == 4, "\(body)")
    }

    /// Verifier journey `rtfTablePaste`: a Word / Pages table (AppKit-native `NSTextTable`) pasted after "Intro"
    /// through `insertFragment(attributed:)` keeps its first cell, is stored as a XAML Table and is followed by an
    /// ordinary paragraph.
    @Test func rtfTableMidParagraph() throws {
        let table = EditorTableBuilder.makeTable(rows: 1, columns: 2, base: EditorFormatting.plainBaseAttributes(from: Self.base))
        let t = NSMutableAttributedString(attributedString: table)
        t.insert(NSAttributedString(string: "r1", attributes: t.attributes(at: 0, effectiveRange: nil)), at: 0)
        let rtf = try t.data(from: NSRange(location: 0, length: t.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let pasted = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        let (clean, _) = EditorRichSanitiser.sanitise(pasted, base: EditorFormatting.plainBaseAttributes(from: Self.base))
        let s = Self.storage("Intro")
        let caret = try #require(XamlReader.insertFragment(attributed: clean, into: s, replacing: NSRange(location: 5, length: 0),
                                                          base: .containerEditor))
        #expect(!Self.inTable(s, "Intro") && Self.inTable(s, "r1"), "\(s.string.debugDescription)")
        let body = Self.written(s)
        #expect(!body.contains("Intror1") && body.contains("<Table") && body.contains(">r1</Run>"), "\(body)")
        #expect(!EditorBlocks.isTableParagraph(s, at: min(caret.location, s.length - 1)), "caret after the table")
    }

    /// RTF paragraphs: a single run merges into the destination paragraph; a fragment ending with a paragraph mark
    /// keeps that break (the text after the caret starts its own paragraph), as before.
    @Test func rtfParagraphsKeepTheirBreaks() throws {
        func paste(_ text: String, bold: Bool = false) throws -> String {
            var a = EditorFormatting.plainBaseAttributes(from: Self.base)
            if bold { a[.font] = NSFontManager.shared.convert(a[.font] as! NSFont, toHaveTrait: .boldFontMask) }
            let s = Self.storage("Intro tail")
            let caret = try #require(XamlReader.insertFragment(attributed: NSAttributedString(string: text, attributes: a), into: s,
                                                              replacing: NSRange(location: 5, length: 0), base: .containerEditor))
            #expect((s.string as NSString).substring(from: caret.location).hasPrefix(" tail"))
            let (r, _) = RichTest.read(RichTest.doc(Self.written(s)))
            return RichTest.paragraphs(r).filter { !$0.isEmpty }.joined(separator: "|")
        }
        #expect(try paste("X") == "IntroX tail")
        #expect(try paste("P1\nP2") == "IntroP1|P2 tail")
        #expect(try paste("P1\nP2\n") == "IntroP1|P2| tail")
        #expect(try paste("W", bold: true) == "IntroW tail")
        #expect(XamlReader.insertFragment(attributed: NSAttributedString(), into: Self.storage("Intro"),
                                          replacing: NSRange(location: 5, length: 0), base: .containerEditor) == nil)
    }

    /// In-app copy of a table pasted right after itself: the copy is a second table (fresh element ids), never fused
    /// with its source.
    @Test func pastedCopyOfATableStaysSeparate() throws {
        let doc = RichTest.doc(##"<Table CellSpacing="0"><TableRowGroup><TableRow><TableCell><Paragraph><Run>c1</Run></Paragraph></TableCell><TableCell><Paragraph><Run>c2</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table><Paragraph><Run>z</Run></Paragraph>"##)
        let (src, _) = RichTest.read(doc)
        let s = NSTextStorage(attributedString: src)
        let z = Self.loc(s, "z")
        let copy = s.attributedSubstring(from: NSRange(location: 0, length: z))
        #expect(XamlReader.insertFragment(attributed: copy, into: s, replacing: NSRange(location: z, length: 0),
                                          base: .containerEditor) != nil)
        let body = Self.written(s)
        #expect(body.components(separatedBy: "<Table ").count == 3, "\(body)")
        #expect(body.hasSuffix("<Paragraph><Run>z</Run></Paragraph>"), "\(body)")
    }
}
