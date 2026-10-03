// TV: 05 §6.2 (TextKit 1 text view on light paper), §6.4 (lists, tables, paragraph blocks), 12 §6.5 (SIRE chips):
//     the reader's output laid out by a real NSTextView. The PNG export runs only with RICH_SNAPSHOT_DIR set (visual
//     review, ARCH §9.6 spirit); the layout assertions always run.
import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct RichRenderSnapshotTests {
    static func layout(_ s: NSAttributedString, width: CGFloat = 560) -> NSTextView {
        let tv = NSTextView(usingTextLayoutManager: false)
        tv.frame = NSRect(x: 0, y: 0, width: width, height: 200)
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.appearance = NSAppearance(named: .aqua)
        tv.drawsBackground = true
        tv.backgroundColor = NSColor(srgbRed: 0xFC / 255, green: 0xFC / 255, blue: 0xFC / 255, alpha: 1)
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.textStorage?.setAttributedString(s)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        tv.frame.size.height = tv.layoutManager!.usedRect(for: tv.textContainer!).height + 24
        return tv
    }

    /// Paragraph blocks (SIRE chips) span the container instead of shrink-wrapping to one glyph per line.
    @Test func paragraphBlocksSpanTheContainer() throws {
        let (s, _) = RichTest.read(try RichTest.sample("S-08-sire-body.xaml"), .sirePane)
        let tv = Self.layout(s)
        let lm = tv.layoutManager!
        let chip = (s.string as NSString).range(of: "Were all statutory")
        let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: chip.location, length: 30), actualCharacterRange: nil)
        var lines = 0
        lm.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in lines += 1 }
        #expect(lines == 1)
        let table = Self.layout(RichTest.read(try RichTest.sample("S-04-table-2x2.xaml")).0)
        #expect(table.frame.height > 30)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RICH_SNAPSHOT_DIR"] != nil)) func snapshots() throws {
        let out = ProcessInfo.processInfo.environment["RICH_SNAPSHOT_DIR"]!
        var docs: [(String, String, XamlContext)] = []
        for name in ["S-01-editor-save", "S-02-nested-bullets", "S-04-table-2x2", "S-06-lock-linebreak-tab-lang", "S-08-sire-body"] {
            docs.append((name, try RichTest.sample(name + ".xaml"), name.contains("sire") ? .sirePane : .containerEditor))
        }
        docs.append(("html-paste", XamlWriter.write(XamlReader.readFragment(HTMLToXAML.convert(try Fixtures.string("html/chrome-article.html")) , destinationContext: .containerEditor)!, metadata: RichTextMetadata(context: .containerEditor), context: .containerEditor), .containerEditor))
        docs.append(("excel-paste", XamlWriter.write(XamlReader.readFragment(HTMLToXAML.convert(try Fixtures.string("html/excel-table.html")) , destinationContext: .containerEditor)!, metadata: RichTextMetadata(context: .containerEditor), context: .containerEditor), .containerEditor))
        for (name, xaml, ctx) in docs {
            let (s, _) = RichTest.read(xaml, ctx)
            let tv = Self.layout(s)
            let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds)!
            tv.cacheDisplay(in: tv.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/" + name + ".png"))
        }
    }
}
