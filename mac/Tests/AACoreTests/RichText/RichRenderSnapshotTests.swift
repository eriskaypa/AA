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
        for name in ["S-03-numbered-insert", "S-05-hyperlink", "S-07-hr", "S-09-subscript"] {
            docs.append((name, try RichTest.sample(name + ".xaml"), .containerEditor))
        }
        docs.append(("mixed-structures", RichTest.doc(##"<Paragraph TextAlignment="Center" FontSize="18" FontWeight="Bold"><Run>Bunkering checklist</Run></Paragraph><List MarkerStyle="Decimal" Margin="0,6,0,6" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>Sound tanks before </Run><Run Background="#FFFFE699">and after</Run><Run> transfer</Run></Paragraph><Paragraph Margin="0,1,0,1"><Run Foreground="#FF64748B">Continuation paragraph of the same item.</Run></Paragraph><List MarkerStyle="LowerLatin" Margin="0,0,0,0" Padding="24,0,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>Port side</Run></Paragraph></ListItem><ListItem><Paragraph Margin="0,1,0,1"><Run>Starboard side</Run></Paragraph></ListItem></List></ListItem><ListItem><Paragraph Margin="0,1,0,1"><Run>Embedded control </Run><InlineUIContainer><Button>B</Button></InlineUIContainer><Run> kept as is</Run></Paragraph></ListItem></List><Section Background="#FFEFF6FF" Padding="8,6,8,6" BorderBrush="#FF93C5FD" BorderThickness="1"><Paragraph><Run FontStyle="Italic">Nested section with a background, border and padding.</Run></Paragraph></Section><Table CellSpacing="0" Margin="0,4,0,4"><Table.Columns><TableColumn Width="120"/><TableColumn Width="*"/><TableColumn Width="*"/></Table.Columns><TableRowGroup><TableRow Background="#FFF1F5F9"><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6" Padding="3,1,3,1" RowSpan="2"><Paragraph><Run FontWeight="Bold">Tank</Run></Paragraph></TableCell><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6" Padding="3,1,3,1" ColumnSpan="2"><Paragraph TextAlignment="Center"><Run FontWeight="Bold">Sounding</Run></Paragraph></TableCell></TableRow><TableRow><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6" Padding="3,1,3,1"><Paragraph><Run>Before</Run></Paragraph></TableCell><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6" Padding="3,1,3,1"><Paragraph><Run>After</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table><BlockUIContainer><Image Source="x.png"/></BlockUIContainer><Paragraph><Run>See </Run><Hyperlink NavigateUri="https://www.imo.org"><Run>IMO</Run></Hyperlink><Run> · H</Run><Run BaselineAlignment="Subscript">2</Run><Run>O · m</Run><Run BaselineAlignment="Superscript">3</Run><Run TextDecorations="Strikethrough"> struck</Run></Paragraph>"##), .containerEditor))
        for (name, xaml, ctx) in docs {
            let (s, _) = RichTest.read(xaml, ctx)
            // The paper stays light (aqua) whatever the app appearance (05 §6.2, CONT-168): render under both.
            for (suffix, appName) in [("", NSAppearance.Name.aqua), ("-dark", NSAppearance.Name.darkAqua)] {
                var data: Data?
                NSAppearance(named: appName)!.performAsCurrentDrawingAppearance {
                    let tv = Self.layout(s)
                    let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds)!
                    tv.cacheDisplay(in: tv.bounds, to: rep)
                    data = rep.representation(using: .png, properties: [:])
                }
                try data!.write(to: URL(fileURLWithPath: out + "/" + name + suffix + ".png"))
            }
        }
    }
}
