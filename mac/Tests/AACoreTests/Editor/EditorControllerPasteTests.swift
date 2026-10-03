// TV: 05 §6.6 (paste of the own XAML type, HTML via HTMLToXAML, RTF/RTFD), CONT-161 (fragment insertion keeps lists,
//     tables and sections whole), CONT-035 (fallback). Stage V round 2, V2-J3: drives the real EditorController (AA
//     target) — the paste pipeline now inserts through `XamlReader.insertFragment`. Adopted from the V2-J3 verifier.
import AppKit
import Testing
@testable import AACore
@testable import AA

@MainActor @Suite(.serialized) struct EditorControllerPasteTests {
    static func controller(_ text: String) -> EditorController {
        let c = EditorController()
        let base = EditorController.emptyTypingAttributes()
        c.showPreview(NSAttributedString(string: text, attributes: base),
                      selection: NSRange(location: text.utf16.count, length: 0))
        return c
    }

    /// A private named pasteboard (never the general one), released by the caller.
    static func pasteboard() -> NSPasteboard {
        let p = NSPasteboard(name: NSPasteboard.Name("aa.tests.paste.\(UUID().uuidString)"))
        p.clearContents()
        return p
    }

    static func xaml(_ c: EditorController) -> String {
        XamlWriter.write(c.textView.textStorage!, metadata: RichTextMetadata(context: .containerEditor),
                         context: .containerEditor)
    }

    @Test func htmlTablePasteThroughController() throws {
        let c = Self.controller("Intro")
        let pb = Self.pasteboard(); defer { pb.releaseGlobally() }
        pb.setString("<table><tr><td>a</td><td>b</td></tr></table>", forType: .html)
        pb.setString("a\tb", forType: .string)
        c.textView.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(c.paste(from: pb, type: EditorPaste.htmlType))
        let s = c.textView.textStorage!
        let aLoc = (s.string as NSString).range(of: "a").location
        #expect(EditorBlocks.isTableParagraph(s, at: aLoc), "first pasted cell stays a cell: \(s.string.debugDescription)")
        // The caret can leave the pasted table: text typed below is an ordinary paragraph.
        c.textView.setSelectedRange(NSRange(location: s.length, length: 0))
        c.textView.insertNewline(nil)
        c.textView.insertText("Below", replacementRange: c.textView.selectedRange())
        #expect(!EditorBlocks.isTableParagraph(s, at: (s.string as NSString).range(of: "Below").location))
    }

    @Test func copyPasteOwnXamlList() throws {
        let c = Self.controller("One\nTwo\nThree")
        let tv = c.textView
        tv.setSelectedRange(NSRange(location: 0, length: tv.string.utf16.count))
        c.perform(.bulletedList)
        let s = tv.textStorage!
        tv.setSelectedRange(NSRange(location: 0, length: s.length))
        let copied = try #require(c.selectedXaml())
        let d = Self.controller("Intro")
        let p = Self.pasteboard(); defer { p.releaseGlobally() }
        p.setString(copied, forType: EditorPaste.xamlType)
        p.setString("One Two Three", forType: .string)
        d.textView.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(d.paste(from: p, type: EditorPaste.xamlType))
        let ds = d.textView.textStorage!
        let one = (ds.string as NSString).range(of: "One").location
        let st = ds.attribute(.paragraphStyle, at: one, effectiveRange: nil) as? NSParagraphStyle
        #expect(st?.textLists.isEmpty == false, "first copied item stays a list item: \(Self.xaml(d))")
    }

    @Test func rtfTablePaste() throws {
        // A Word/Pages-like RTF table (NSTextTable) pasted mid-paragraph.
        let table = EditorTableBuilder.makeTable(rows: 1, columns: 2,
                                                 base: EditorFormatting.plainBaseAttributes(from: EditorController.emptyTypingAttributes()))
        let t = NSMutableAttributedString(attributedString: table)
        t.insert(NSAttributedString(string: "r1", attributes: t.attributes(at: 0, effectiveRange: nil)), at: 0)
        let rtf = try t.data(from: NSRange(location: 0, length: t.length),
                             documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let c = Self.controller("Intro")
        let p = Self.pasteboard(); defer { p.releaseGlobally() }
        p.setData(rtf, forType: .rtf)
        c.textView.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(c.paste(from: p, type: EditorPaste.rtfType))
        let s = c.textView.textStorage!
        let loc = (s.string as NSString).range(of: "r1").location
        #expect(loc != NSNotFound)
        if loc != NSNotFound {
            #expect(EditorBlocks.isTableParagraph(s, at: loc), "RTF table first cell stays a cell: \(s.string.debugDescription)")
        }
        let x = Self.xaml(c)
        #expect(x.contains("<Table"), "an RTF table is stored as a XAML Table")
        #expect(x.contains(">r1</Run>"))                                  // the first cell is written bold
    }

    @Test func lockedTextRefusesAStructuredPaste() throws {
        let c = Self.controller("abc DEF ghi")
        let tv = c.textView
        tv.setSelectedRange(NSRange(location: 4, length: 3))
        c.applyChar(.highlight(EditorLocking.sentinelColor), name: "Lock")
        let p = Self.pasteboard(); defer { p.releaseGlobally() }
        p.setString("<table><tr><td>a</td></tr></table>", forType: .html)
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(!c.paste(from: p, type: EditorPaste.htmlType))
        #expect(tv.string == "abc DEF ghi")
    }
}
