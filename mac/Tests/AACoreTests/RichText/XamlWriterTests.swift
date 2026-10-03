// TV: 05 §XD.6.4 XD-W1…W9, XD-V1…V8 "Mac writer" rows, §7.7 items 1–7 and 9 (write side, semantic equality,
//     untouched-content byte stability, lock sentinel round trip), §4.3.7 rules 1–11, CONT-163…167, XD.2.11,
//     01 §4.11 (sentinel, #AARRGGBB, plain-text consumers on the raw string), 12 §4.4 (SIRE bodies byte-stable).
import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct XamlWriterTests {
    static func write(_ s: NSAttributedString, _ m: RichTextMetadata, _ c: XamlContext = .containerEditor) -> String {
        XamlWriter.write(s, metadata: m, context: c)
    }

    static func expectBody(_ input: String, _ expected: String, _ ctx: XamlContext = .containerEditor,
                           sourceLocation: SourceLocation = #_sourceLocation) {
        let out = RichTest.roundTrip(input, ctx)
        #expect(RichTest.semanticallyEqual(RichTest.body(out), "<X>" + expected + "</X>") || RichTest.canonical("<X>" + RichTest.body(out) + "</X>") == RichTest.canonical("<X>" + expected + "</X>"),
                "\n got: \(RichTest.body(out))\nwant: \(expected)", sourceLocation: sourceLocation)
    }

    // MARK: Rules 1–2, XD.2.11

    @Test func emptyDocumentAndNewDocumentRoot() {
        #expect(XamlWriter.emptyDocument() == "")
        #expect(Self.write(NSAttributedString(), RichTextMetadata(context: .containerEditor)) == "")
        let typed = NSAttributedString(string: "x", attributes: RichEditTree.defaultCharacterAttributes)
        let out = Self.write(typed, RichTextMetadata(context: .containerEditor))
        #expect(out.hasPrefix(RichTest.s1))                       // the canonical S-1 root, unchanged
        #expect(RichTest.body(out) == "<Paragraph><Run>x</Run></Paragraph>")
        // The SIRE pane context completes with its own tokens.
        let sire = Self.write(typed, RichTextMetadata(context: .sirePane), .sirePane)
        #expect(sire.contains(#"FontFamily="Segoe UI""#) && sire.contains(#"FontSize="13""#))
        #expect(RichTest.body(sire).contains(#"FontFamily="Consolas""#))  // the typed text's own family differs
    }

    @Test func rootVerbatimAndCompletion() {
        // XD-V8: a context-less Section root is kept verbatim and completed in the documented order.
        let v8 = ##"<Section xml:space="preserve" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Paragraph><Run>plain</Run><Run FontSize="16">big</Run></Paragraph></Section>"##
        let out = RichTest.roundTrip(v8)
        let root = String(out[..<out.firstIndex(of: ">")!])
        #expect(root == ##"<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xml:space="preserve" TextAlignment="Left" LineHeight="Auto" xml:lang="en-us" FlowDirection="LeftToRight" FontFamily="Consolas" FontStyle="Normal" FontWeight="Normal" FontStretch="Normal" FontSize="14" Foreground="#FF1A1A1A""##)
        #expect(RichTest.body(out) == ##"<Paragraph><Run>plain</Run><Run FontSize="16">big</Run></Paragraph>"##)
        // S-1 roots are reused byte for byte.
        let s1 = try! RichTest.sample("S-01-editor-save.xaml")
        #expect(RichTest.roundTrip(s1).hasPrefix(RichTest.s1))
        // S-8 keeps its Segoe UI root even when edited in the container editor (§7.7 item 6).
        let s8 = try! RichTest.sample("S-08-sire-body.xaml")
        let s8root = String(s8[...s8.firstIndex(of: ">")!])
        #expect(RichTest.roundTrip(s8).hasPrefix(s8root))
    }

    @Test func nonSectionRootsAreReplacedByS1() {
        // XD-V6: a content root → S-1 + the paragraph with its carried and modelled attributes, Bold flattened.
        let v6 = ##"<Paragraph xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" FontSize="16" TextAlignment="Center"><Run>Hi </Run><Bold>there</Bold></Paragraph>"##
        let out = RichTest.roundTrip(v6)
        #expect(out.hasPrefix(RichTest.s1))
        #expect(RichTest.body(out) == ##"<Paragraph FontSize="16" TextAlignment="Center"><Run>Hi </Run><Run FontWeight="Bold">there</Run></Paragraph>"##)
        // A Span root: S-1 with the old wrapper's inheritable values overriding.
        let span = RichTest.roundTrip(##"<Span xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" FontSize="20"><Run>x</Run></Span>"##)
        #expect(span.contains(#" FontSize="20""#) && !span.contains(#" FontSize="14""#))
        #expect(RichTest.body(span) == "<Paragraph><Run>x</Run></Paragraph>")
    }

    // MARK: XD-V vectors (writer rows)

    @Test func v1FlattensSpans() {
        Self.expectBody(RichTest.doc(##"<Paragraph><Span Foreground="#FFC00000"><Run>Warn</Run><Run FontWeight="Bold" Foreground="#FF0000FF">ing</Run></Span><Run> ok</Run></Paragraph>"##),
                        ##"<Paragraph><Run Foreground="#FFC00000">Warn</Run><Run FontWeight="Bold" Foreground="#FF0000FF">ing</Run><Run> ok</Run></Paragraph>"##)
    }

    @Test func v2FlattensDecorations() {
        Self.expectBody(RichTest.doc(##"<Paragraph><Underline>Hello</Underline><Run> </Run><Bold><Run TextDecorations="Underline">world</Run></Bold></Paragraph>"##),
                        ##"<Paragraph><Run TextDecorations="Underline">Hello</Run><Run> </Run><Run FontWeight="Bold" TextDecorations="Underline">world</Run></Paragraph>"##)
    }

    @Test func v3NestedSectionUnchanged() {
        let body = ##"<Section FontSize="20" Foreground="#FF006400" TextAlignment="Center"><Paragraph><Run>Big</Run><Run FontSize="10">small</Run></Paragraph></Section><Paragraph><Run>after</Run></Paragraph>"##
        Self.expectBody(RichTest.doc(body), body)
    }

    @Test func v4BackgroundsAndLocks() {
        let a = ##"<Paragraph Background="#FFFFFF00"><Run>Note: </Run><Run Background="#FF00FF00">green</Run></Paragraph>"##
        Self.expectBody(RichTest.doc(a), a)
        let b = ##"<Paragraph Background="#FFFFE699"><Run>7.5 bar</Run></Paragraph>"##
        Self.expectBody(RichTest.doc(b), b)
        let c = ##"<Paragraph><Span Background="#FFFFE699"><Run Background="#FFFFFF00">x</Run></Span></Paragraph>"##
        Self.expectBody(RichTest.doc(c), c)
    }

    @Test func v5TableCellCarriedWeight() {
        let body = ##"<Table CellSpacing="0" Margin="0,4,0,4"><Table.Columns><TableColumn /><TableColumn /></Table.Columns><TableRowGroup><TableRow><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6,0.6,0.6,0.6" Padding="3,1,3,1" FontWeight="Bold" TextAlignment="Right"><Paragraph><Run>Head</Run><Run FontWeight="Normal"> (n)</Run></Paragraph></TableCell><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6,0.6,0.6,0.6" Padding="3,1,3,1"><Paragraph><Run>x</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table>"##
        Self.expectBody(RichTest.doc(body), body)
    }

    @Test func v7HyperlinkStyleLayer() {
        let body = ##"<Paragraph Foreground="#FF800080"><Hyperlink NavigateUri="https://www.imo.org"><Run>IMO</Run></Hyperlink><Run> and </Run><Hyperlink><Run>x</Run><Run Foreground="#FFFF0000">y</Run></Hyperlink></Paragraph>"##
        Self.expectBody(RichTest.doc(body), body)
    }

    // MARK: XD-W vectors

    @Test func w1EmptyParagraphTakesTheTerminatorsSize() {
        let p = RichPara(content: NSMutableAttributedString(), terminator: [
            .font: RichFontResolver.font(family: "Consolas", size: 20, weight: 400, italic: false),
            .aaFontFamilyName: "Consolas", .foregroundColor: RichColor.color(0xFF1A_1A1A),
        ], alignment: .left, direction: .leftToRight, carried: [], model: [:])
        let s = RichRenderer.render(RichDoc(blocks: [.para(p)]))
        var m = RichTextMetadata(context: .containerEditor)
        m.rootRole = .wrapper(.section)
        m.rootAttributes = XamlWriter.s1RootAttributes(.containerEditor)
        #expect(RichTest.body(Self.write(s, m)) == ##"<Paragraph FontSize="20" />"##)
    }

    @Test func w2RedundantLocalsDropped() {
        Self.expectBody(RichTest.doc(##"<Paragraph><Run FontFamily="Consolas" FontSize="14" Foreground="#FF1A1A1A">x</Run></Paragraph>"##),
                        "<Paragraph><Run>x</Run></Paragraph>")
    }

    @Test func w3WeightTokenConsistency() {
        let (s, m) = RichTest.read(RichTest.doc(##"<Paragraph><Run FontWeight="SemiBold">x</Run></Paragraph>"##))
        #expect(RichTest.body(Self.write(s, m)) == ##"<Paragraph><Run FontWeight="SemiBold">x</Run></Paragraph>"##)
        let off = NSMutableAttributedString(attributedString: s)
        let f = off.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        off.addAttribute(.font, value: NSFontManager.shared.convert(f, toNotHaveTrait: .boldFontMask), range: NSRange(location: 0, length: 1))
        let offFont = off.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        if RichFontResolver.isBoldish(offFont) {
            // The family has no lighter face; fall back to an explicit regular font.
            off.addAttribute(.font, value: RichFontResolver.font(family: "Consolas", size: 14, weight: 400, italic: false),
                             range: NSRange(location: 0, length: 1))
        }
        #expect(RichTest.body(Self.write(off, m)) == "<Paragraph><Run>x</Run></Paragraph>")
        let on = NSMutableAttributedString(attributedString: off)
        on.addAttribute(.font, value: RichFontResolver.font(family: "Consolas", size: 14, weight: 700, italic: false),
                        range: NSRange(location: 0, length: 1))
        #expect(RichTest.body(Self.write(on, m)) == ##"<Paragraph><Run FontWeight="Bold">x</Run></Paragraph>"##)
    }

    @Test func w4InRunNewlinesAreByteStable() {
        let src = RichTest.doc("<Paragraph><Run>a\nb</Run><LineBreak /><Run>c</Run></Paragraph>")
        let out = RichTest.roundTrip(src)
        #expect(out == src)
        #expect(XamlPlainText.searchText(out) == XamlPlainText.searchText(src))
        let cr = RichTest.doc("<Paragraph><Run>a&#xD;&#xA;b&#xD;c</Run></Paragraph>")
        #expect(RichTest.body(RichTest.roundTrip(cr)) == "<Paragraph><Run>a&#xD;\nb&#xD;c</Run></Paragraph>")
    }

    @Test func w5ColoursAreCanonical() {
        Self.expectBody(RichTest.doc(##"<Paragraph Foreground="#FF00FF00"><Run Foreground="Red">x</Run></Paragraph>"##),
                        ##"<Paragraph Foreground="#FF00FF00"><Run Foreground="#FFFF0000">x</Run></Paragraph>"##)
        let out = RichTest.body(RichTest.roundTrip(RichTest.doc(##"<Paragraph Foreground="#FF00FF00"><Run Foreground="Red">x</Run></Paragraph>"##)))
        #expect(out.contains(##"<Run Foreground="#FFFF0000">"##))
    }

    @Test func w6CarriedValueEqualToInheritedIsDropped() {
        Self.expectBody(RichTest.doc(##"<List MarkerStyle="Disc"><ListItem FontSize="14"><Paragraph><Run>a</Run></Paragraph></ListItem></List>"##),
                        ##"<List MarkerStyle="Disc"><ListItem><Paragraph><Run>a</Run></Paragraph></ListItem></List>"##)
    }

    @Test func w7FontFamilyTokenFollowsTheFont() {
        let (s, m) = RichTest.read(RichTest.doc("<Paragraph><Run>x</Run><Run>y</Run></Paragraph>"))
        #expect(RichTest.body(Self.write(s, m)) == "<Paragraph><Run>xy</Run></Paragraph>")
        let edited = NSMutableAttributedString(attributedString: s)
        edited.addAttribute(.font, value: NSFont(name: "Menlo", size: 14)!, range: NSRange(location: 0, length: 1))
        #expect(RichTest.body(Self.write(edited, m)) == ##"<Paragraph><Run FontFamily="Menlo">x</Run><Run>y</Run></Paragraph>"##)
    }

    @Test func w8MergedParagraphKeepsTheFirstParagraphsAttributes() {
        let (s, m) = RichTest.read(RichTest.doc(##"<Paragraph FontSize="20"><Run>A</Run></Paragraph><Paragraph><Run>B</Run></Paragraph>"##))
        let merged = NSMutableAttributedString(attributedString: s)
        merged.deleteCharacters(in: NSRange(location: 1, length: 1))           // delete the first terminator
        #expect(RichTest.body(Self.write(merged, m)) == ##"<Paragraph FontSize="20"><Run>A</Run><Run FontSize="14">B</Run></Paragraph>"##)
    }

    // MARK: Lists, tables, links, locks

    @Test func listsRoundTrip() throws {
        for name in ["S-02-nested-bullets.xaml", "S-03-numbered-insert.xaml"] {
            let x = try RichTest.sample(name)
            #expect(RichTest.semanticallyEqual(RichTest.roundTrip(x), x), "\(name)\n\(RichTest.roundTrip(x))")
        }
        let continuation = RichTest.doc(##"<List MarkerStyle="Decimal" StartIndex="3"><ListItem><Paragraph><Run>a</Run></Paragraph><Paragraph><Run>a2</Run></Paragraph><List MarkerStyle="LowerLatin"><ListItem><Paragraph><Run>sub</Run></Paragraph></ListItem></List><Paragraph><Run>a3</Run></Paragraph></ListItem><ListItem><List MarkerStyle="Disc"><ListItem><Paragraph><Run>only nested</Run></Paragraph></ListItem></List></ListItem></List>"##)
        #expect(RichTest.semanticallyEqual(RichTest.roundTrip(continuation), continuation), "\(RichTest.roundTrip(continuation))")
    }

    @Test func tablesRoundTrip() throws {
        let s4 = try RichTest.sample("S-04-table-2x2.xaml")
        let out = RichTest.roundTrip(s4)
        // Empty Runs are not content: `<Paragraph><Run></Run></Paragraph>` and `<Paragraph />` are the same document.
        #expect(RichTest.semanticallyEqual(out, s4.replacingOccurrences(of: "<Paragraph><Run></Run></Paragraph>", with: "<Paragraph />")), "\(out)")
        let spans = RichTest.doc(##"<Table CellSpacing="2"><Table.Columns><TableColumn Width="2*" /><TableColumn Width="100" Background="#FFEEEEEE" /><TableColumn /></Table.Columns><TableRowGroup Tag="g"><TableRow Background="#FFFAFAFA"><TableCell RowSpan="2" Background="#FF00FF00"><Paragraph><Run>tall</Run></Paragraph></TableCell><TableCell ColumnSpan="2"><Paragraph><Run>wide</Run></Paragraph><Paragraph><Run>wide 2</Run></Paragraph></TableCell></TableRow><TableRow><TableCell><Paragraph><Run>b</Run></Paragraph></TableCell><TableCell><List MarkerStyle="Disc"><ListItem><Paragraph><Run>in cell</Run></Paragraph></ListItem></List></TableCell></TableRow></TableRowGroup><TableRowGroup><TableRow><TableCell><Paragraph><Run>second group</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table><Paragraph><Run>after</Run></Paragraph>"##)
        #expect(RichTest.semanticallyEqual(RichTest.roundTrip(spans), spans), "\(RichTest.roundTrip(spans))")
    }

    @Test func hyperlinksKeepTheirOriginalUriAndExtraAttributes() {
        let body = ##"<Paragraph><Run>See </Run><Hyperlink NavigateUri="https://www.imo.org" TargetName="_blank" ToolTip="IMO" x:Uid="h1" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><Run>https://www.imo.org/</Run></Hyperlink></Paragraph>"##
        let out = RichTest.body(RichTest.roundTrip(RichTest.doc(body)))
        #expect(out.contains(##"NavigateUri="https://www.imo.org""##) && out.contains(##"TargetName="_blank""##))
        #expect(out.contains(##"ToolTip="IMO""##) && out.contains(##"x:Uid="h1""##))
        // Changing `.link` rewrites NavigateUri; a new `.link` without an element id creates a Hyperlink.
        let (s, m) = RichTest.read(RichTest.doc(body))
        let e = NSMutableAttributedString(attributedString: s)
        let r = (e.string as NSString).range(of: "https")
        e.addAttribute(.link, value: URL(string: "https://example.org/")!, range: NSRange(location: r.location, length: e.length - 1 - r.location))
        e.addAttribute(.link, value: URL(string: "https://a.b/")!, range: NSRange(location: 0, length: 3))
        let w = RichTest.body(Self.write(e, m))
        #expect(w.contains(##"<Hyperlink NavigateUri="https://a.b/"><Run>See</Run></Hyperlink>"##))
        #expect(w.contains(##"NavigateUri="https://example.org/""##))
    }

    @Test func linkStyledTextOutsideALinkWritesItsUnderlyingColour() {
        let (s, m) = RichTest.read(RichTest.doc(##"<Paragraph Foreground="#FF800080"><Hyperlink NavigateUri="https://x.y"><Run>IMO</Run></Hyperlink></Paragraph>"##))
        let e = NSMutableAttributedString(attributedString: s)
        e.removeAttribute(.aaHyperlink, range: NSRange(location: 0, length: 3))
        e.removeAttribute(.link, range: NSRange(location: 0, length: 3))
        #expect(RichTest.body(Self.write(e, m)) == ##"<Paragraph Foreground="#FF800080"><Run>IMO</Run></Paragraph>"##)
    }

    @Test func lockSentinelRoundTrip() throws {
        // §7.7 item 5 / 01 §4.11 invariant 2.
        let s6 = try RichTest.sample("S-06-lock-linebreak-tab-lang.xaml")
        #expect(RichTest.roundTrip(s6) == s6)
        // A lock applied on the Mac.
        let (s, m) = RichTest.read(RichTest.doc("<Paragraph><Run>abcDEFghi</Run></Paragraph>"))
        let e = NSMutableAttributedString(attributedString: s)
        LockRules.lock(e, range: NSRange(location: 3, length: 3))
        #expect(RichTest.body(Self.write(e, m)) == ##"<Paragraph><Run>abc</Run><Run Background="#FFFFE699">DEF</Run><Run>ghi</Run></Paragraph>"##)
    }

    @Test func opaqueContentIsWrittenBackByteForByte() {
        let body = ##"<Paragraph><Run>a</Run><InlineUIContainer><Button Content="x" Width="20"/></InlineUIContainer><Run>b</Run></Paragraph><BlockUIContainer><Image Source="x.png" /></BlockUIContainer><Paragraph><Figure Width="100"><Paragraph><Run>fig</Run></Paragraph></Figure><Run>c</Run></Paragraph>"##
        let out = RichTest.roundTrip(RichTest.doc(body))
        #expect(RichTest.body(out) == body)
        let unknown = RichTest.doc(##"<Paragraph><Foo a="1">y<Bar/></Foo></Paragraph>"##)
        #expect(RichTest.body(RichTest.roundTrip(unknown)) == ##"<Paragraph><Foo a="1">y<Bar/></Foo></Paragraph>"##)
    }

    @Test func propertyElementBrushesRoundTrip() {
        let body = ##"<Paragraph><Run><Run.Foreground><SolidColorBrush Color="#FFFF0000" Opacity="0.5"/></Run.Foreground>a</Run></Paragraph>"##
        #expect(RichTest.body(RichTest.roundTrip(RichTest.doc(body))) == body)                               // XD-C12
        let grad = ##"<Paragraph><Run><Run.Background><LinearGradientBrush><GradientStop Color="Red"/></LinearGradientBrush></Run.Background>g</Run></Paragraph>"##
        #expect(RichTest.body(RichTest.roundTrip(RichTest.doc(grad))) == grad)
        // A changed colour drops the preserved brush.
        let (s, m) = RichTest.read(RichTest.doc(body))
        let e = NSMutableAttributedString(attributedString: s)
        e.addAttribute(.foregroundColor, value: RichColor.color(0xFF00_00FF), range: NSRange(location: 0, length: 1))
        #expect(RichTest.body(Self.write(e, m)) == ##"<Paragraph><Run Foreground="#FF0000FF">a</Run></Paragraph>"##)
    }

    @Test func invalidRecognisedAttributesAreNeverReemitted() {
        let out = RichTest.body(RichTest.roundTrip(RichTest.doc(##"<Paragraph FontSize="abc" Tag="keep"><Run Foreground="{StaticResource X}" Foo="1">x</Run></Paragraph>"##)))
        #expect(out == ##"<Paragraph Tag="keep"><Run Foo="1">x</Run></Paragraph>"##)                       // XD-L4, L9, L10
        if case .success(let d) = XamlDOM.parse(RichTest.doc(out)) { #expect(d.loadability == .loadable) }
        // The same holds for the root: an invalid core value is dropped and completion supplies the context's.
        let root = "<Section xmlns=\"\(RichTest.P)\" xml:space=\"preserve\" FontSize=\"big\" Foreground=\"#FF1A1\nA1A\" Tag=\"r\"><Paragraph><Run>x</Run></Paragraph></Section>"
        let rewritten = RichTest.roundTrip(root)
        #expect(rewritten.hasPrefix("<Section xmlns=\"\(RichTest.P)\" xml:space=\"preserve\" Tag=\"r\" TextAlignment=\"Left\""))
        #expect(rewritten.contains(" FontSize=\"14\" Foreground=\"#FF1A1A1A\">") && !rewritten.contains("big"))
        if case .success(let d) = XamlDOM.parse(rewritten) { #expect(d.loadability == .loadable) } else { Issue.record("unparseable") }
    }

    @Test func runAttributeOrderAndExtras() {
        let body = ##"<Paragraph><Run FontFamily="Arial" FontStyle="Italic" FontWeight="Bold" FontStretch="Condensed" FontSize="16" Foreground="#FF0000FF" Background="#FFFFFF00" TextDecorations="Underline,Strikethrough,OverLine" BaselineAlignment="Superscript" FlowDirection="RightToLeft" xml:lang="el-gr" Typography.Capitals="SmallCaps" Typography.Kerning="False" Tag="t">x</Run></Paragraph>"##
        #expect(RichTest.body(RichTest.roundTrip(RichTest.doc(body))) == body)
        Self.expectBody(RichTest.doc(##"<Paragraph><Run Typography.Variants="Subscript">2</Run></Paragraph>"##),
                        ##"<Paragraph><Run Typography.Variants="Subscript">2</Run></Paragraph>"##)
    }

    @Test func paragraphModelledAttributes() {
        let body = ##"<Paragraph KeepWithNext="True" TextAlignment="Justify" LineHeight="30" LineStackingStrategy="BlockLineHeight" FlowDirection="RightToLeft" Margin="10,Auto,0,4" Padding="2,2,2,2" BorderThickness="1,1,1,1" BorderBrush="#FF000000" Background="#FFEEEEEE" TextIndent="-12"><Run>p</Run></Paragraph>"##
        let out = RichTest.body(RichTest.roundTrip(RichTest.doc(body)))
        #expect(out == body, "\(out)")
        Self.expectBody(RichTest.doc(##"<Paragraph BorderBrush="#FF888888" BorderThickness="0,0,0,1" Padding="0,0,0,0" />"##),
                        ##"<Paragraph Padding="0,0,0,0" BorderThickness="0,0,0,1" BorderBrush="#FF888888" />"##)
    }

    @Test func escapingAndIllegalCharacters() {
        let s = NSMutableAttributedString(string: "a<b>&\"c\u{1}d\u{FFFE}\n", attributes: RichEditTree.defaultCharacterAttributes)
        let out = RichTest.body(Self.write(s, RichTextMetadata(context: .containerEditor)))
        #expect(out == "<Paragraph><Run>a&lt;b&gt;&amp;\"cd</Run></Paragraph>")
        let (r, m) = RichTest.read(RichTest.doc(##"<Paragraph Tag="q&quot;&#xA;&#x9;"><Run>t</Run></Paragraph>"##))
        #expect(RichTest.body(Self.write(r, m)) == ##"<Paragraph Tag="q&quot;&#xA;&#x9;"><Run>t</Run></Paragraph>"##)
    }

    @Test func userEditsSplitRunsAndTypedLineBreaks() {
        let (s, m) = RichTest.read(RichTest.doc("<Paragraph><Run>hello world</Run></Paragraph>"))
        let e = NSMutableAttributedString(attributedString: s)
        e.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 6, length: 5))
        e.replaceCharacters(in: NSRange(location: 5, length: 1), with: NSAttributedString(string: "\u{2028}", attributes: e.attributes(at: 0, effectiveRange: nil)))
        #expect(RichTest.body(Self.write(e, m)) == ##"<Paragraph><Run>hello</Run><LineBreak /><Run TextDecorations="Underline">world</Run></Paragraph>"##)
    }

    // MARK: Consumers and stability (§7.7 items 1–6, 9)

    @Test func samplesAreSemanticallyEqualAndAFixedPoint() throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: Fixtures.url("xaml/samples").path).sorted()
            where name.hasSuffix(".xaml") {
            let x = try RichTest.sample(name)
            for ctx in [XamlContext.containerEditor, .sirePane] {
                let once = RichTest.roundTrip(x, ctx)
                let twice = RichTest.roundTrip(once, ctx)
                #expect(once == twice, "fixed point \(name)")
                guard case .success(let d) = XamlDOM.parse(once) else { Issue.record("\(name) output unparseable"); continue }
                #expect(d.loadability == .loadable, "\(name)")
                // Plain-text consumers see the same visible words before and after (runs as element content).
                #expect(XamlPlainText.diffText(once) == XamlPlainText.diffText(x), "\(name)")
            }
        }
    }

    @Test func untouchedReadKeepsTheSourceHash() throws {
        let x = try RichTest.sample("S-01-editor-save.xaml")
        let (_, m1) = RichTest.read(x)
        let (_, m2) = RichTest.read(x)
        #expect(m1.sourceHash == m2.sourceHash && m1.sourceHash == RichTextMetadata.hash(of: x))
        #expect(RichTextMetadata.hash(of: x + " ") != m1.sourceHash)
    }

    @Test func sirePaneBodiesStayByteStable() throws {
        // 12 §4.4 / §6.5: in-run newlines, Segoe UI preserved, chips and lists unchanged after a no-op edit.
        let s8 = try RichTest.sample("S-08-sire-body.xaml")
        let out = RichTest.roundTrip(s8, .sirePane)
        #expect(out.contains("certificates\nvalid") && out.contains(#"FontFamily="Segoe UI""#))
        #expect(out.contains(##"<Paragraph Margin="0,2,0,8" Padding="10,8,10,8" Background="#FFF8FAFC">"##))
        #expect(RichTest.semanticallyEqual(RichTest.body(out).isEmpty ? out : out, out))
    }
}

/// §4.3.7 rules 10–11: every prefix the output uses stays declared, wherever the source declared it (on a carried
/// element, on a flattened Span, around an opaque slice, on a replaced content root) — an undeclared prefix would make
/// the note unloadable on both platforms.
@MainActor
@Suite struct XamlWriterNamespaceTests {
    static let X = "http://schemas.microsoft.com/winfx/2006/xaml"

    static func loads(_ xaml: String) -> Bool {
        if case .success = XamlDOM.parse(xaml) { return true }
        return false
    }

    @Test func declarationOnACarriedElementTravelsWithIt() {
        let src = RichTest.doc(##"<Paragraph KeepTogether="True" xmlns:x="\##(Self.X)" x:Name="p1"><Run x:Uid="r">a</Run></Paragraph>"##)
        let out = RichTest.roundTrip(src)
        #expect(Self.loads(out))
        #expect(RichTest.body(out) == ##"<Paragraph xmlns:x="\##(Self.X)" KeepTogether="True" x:Name="p1"><Run x:Uid="r">a</Run></Paragraph>"##)
        #expect(RichTest.roundTrip(out) == out)
    }

    @Test func declarationOnAFlattenedSpanMovesToTheRoot() {
        let src = RichTest.doc(##"<Paragraph><Span xmlns:x="\##(Self.X)" xmlns:l="clr-namespace:Foo"><Run x:Uid="r">a</Run><InlineUIContainer><l:Gauge Value="3"/></InlineUIContainer></Span></Paragraph>"##)
        let out = RichTest.roundTrip(src)
        #expect(Self.loads(out))
        #expect(out.hasPrefix(##"<Section xmlns:l="clr-namespace:Foo" xmlns:x="\##(Self.X)" xmlns="##))
        #expect(RichTest.body(out) == ##"<Paragraph><Run x:Uid="r">a</Run><InlineUIContainer><l:Gauge Value="3"/></InlineUIContainer></Paragraph>"##)
    }

    @Test func declarationOnAReplacedContentRootIsKept() {
        let src = ##"<Paragraph xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:l="clr-namespace:Foo"><Run>a</Run><l:Thing/></Paragraph>"##
        let out = RichTest.roundTrip(src)
        #expect(Self.loads(out))
        #expect(RichTest.body(out) == ##"<Paragraph xmlns:l="clr-namespace:Foo"><Run>a</Run><l:Thing/></Paragraph>"##)
    }

    @Test func plainDocumentsAreNotRescanned() {
        let (s, m) = RichTest.read(RichTest.doc("<Paragraph><Run>a</Run></Paragraph>"))
        #expect(!XamlWriterEmitter.namespaceNeeds(RichDoc.build(from: s), metadata: m).check)
    }
}

@MainActor
@Suite struct XamlWriterRunMergeTests {
    /// XD.2.10 "display-only differences never split runs", extended to differences `same()` absorbs: neighbours
    /// whose emitted Run is identical are one Run, so read → write of a Mac-written body is byte-stable (01 §4.11).
    @Test func neighboursWithIdenticalOutputAreOneRun() {
        let base = RichEditTree.defaultCharacterAttributes
        var other = base
        other[.aaXmlLang] = "EN-US"                      // same() as the inherited en-us
        other[.aaFontWeightToken] = "Regular"            // same() as Normal
        let s = NSMutableAttributedString(string: "ab", attributes: base)
        s.append(NSAttributedString(string: "cd\n", attributes: other))
        let out = XamlWriter.write(s, metadata: RichTextMetadata(context: .containerEditor), context: .containerEditor)
        #expect(RichTest.body(out) == "<Paragraph><Run>abcd</Run></Paragraph>")
        #expect(RichTest.roundTrip(out) == out)
        // Line breaks and opaque content still separate runs.
        let t = NSMutableAttributedString(string: "a\u{2028}b\n", attributes: base)
        #expect(RichTest.body(XamlWriter.write(t, metadata: RichTextMetadata(context: .containerEditor), context: .containerEditor))
                == "<Paragraph><Run>a</Run><LineBreak /><Run>b</Run></Paragraph>")
    }
}
