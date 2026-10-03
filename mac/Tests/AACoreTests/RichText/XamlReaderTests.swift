// TV: 05 §XD.6.1 XD-V1…V8 (NSAttributedString rows), §XD.2.8 (projection keys), §7.7 items 1–8 (reader side),
//     CONT-006 (unparseable), CONT-161 (fragments), CONT-166 (line-break provenance), CONT-167 (link colour),
//     §6.4 (lists as TextKit 1 markers, tables as NSTextTable, opaque attachments), 12 §4.4 / §6.5 (SIRE shapes).
import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct XamlReaderTests {
    static func font(_ a: [NSAttributedString.Key: Any]) -> NSFont { a[.font] as! NSFont }
    static func style(_ a: [NSAttributedString.Key: Any]) -> NSParagraphStyle { a[.paragraphStyle] as! NSParagraphStyle }

    @Test func outcomes() {
        if case .empty(let m) = XamlReader.read("", context: .containerEditor) {
            #expect(!m.isPlaceholderResult && m.rootRole == nil && m.loadability == .loadable)
        } else { Issue.record("expected empty") }
        if case .empty = XamlReader.read("  \n ", context: .containerEditor) {} else { Issue.record("blank → empty") }
        // §7.7 item 8 / CONT-006: invalid XML → unparseable (the editor shows it raw and withholds saving).
        if case .unparseable(let raw) = XamlReader.read("<Section><Paragraph>", context: .containerEditor) {
            #expect(raw == "<Section><Paragraph>")
        } else { Issue.record("expected unparseable") }
        for bad in ["enc:AAAA", "<Section><Paragraph>Hi</Paragraph></Section>", "<!DOCTYPE x><Section xmlns=\"\(RichTest.P)\"/>"] {
            if case .unparseable = XamlReader.read(bad, context: .containerEditor) {} else { Issue.record("\(bad)") }
        }
    }

    @Test func metadata() throws {
        let x = try RichTest.sample("S-01-editor-save.xaml")
        let (_, m) = RichTest.read(x)
        #expect(m.rootRole == .wrapper(.section) && m.loadability == .loadable && !m.hasAnyLock)
        #expect(m.rootAttributes.first?.qualifiedName == "xmlns" && m.rootAttributes.count == 58)
        #expect(m.sourceHash == RichTextMetadata.hash(of: x) && m.sourceHash != 0)
        #expect(m.context == .containerEditor && !m.isPlaceholderResult)
    }

    // §7.7 item 1 / S-1.
    @Test func s1TwoParagraphs() throws {
        let (s, _) = RichTest.read(try RichTest.sample("S-01-editor-save.xaml"))
        #expect(RichTest.paragraphs(s) == ["Check the main engine oil level.", "Urgent"])
        let regular = RichTest.attrs(s, at: "Check the "), bold = RichTest.attrs(s, at: "main engine")
        #expect(!RichFontResolver.isBoldish(Self.font(regular)) && RichFontResolver.isBoldish(Self.font(bold)))
        #expect(bold[.aaFontWeightToken] as? String == "Bold")
        #expect(regular[.aaFontFamilyName] as? String == "Consolas" && Self.font(regular).pointSize == 14)
        #expect(RichTest.argb(regular[.foregroundColor]) == 0xFF1A_1A1A)
        let urgent = RichTest.attrs(s, at: "Urgent")
        #expect(Self.style(urgent).alignment == .center && Self.style(regular).alignment == .left)
        #expect(RichTest.argb(urgent[.foregroundColor]) == 0xFFFF_0000 && RichTest.argb(urgent[.backgroundColor]) == 0xFFFF_FF00)
        #expect(urgent[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(regular[.aaXmlLang] as? String == "en-us")
    }

    // XD-V1.
    @Test func v1SpanForegroundOverRuns() {
        let (s, _) = RichTest.read(RichTest.doc(##"<Paragraph><Span Foreground="#FFC00000"><Run>Warn</Run><Run FontWeight="Bold" Foreground="#FF0000FF">ing</Run></Span><Run> ok</Run></Paragraph>"##))
        let warn = RichTest.attrs(s, at: "Warn"), ing = RichTest.attrs(s, at: "ing"), ok = RichTest.attrs(s, at: " ok")
        #expect(RichTest.argb(warn[.foregroundColor]) == 0xFFC0_0000 && !RichFontResolver.isBoldish(Self.font(warn)))
        #expect(RichTest.argb(ing[.foregroundColor]) == 0xFF00_00FF && ing[.aaFontWeightToken] as? String == "Bold")
        #expect(RichTest.argb(ok[.foregroundColor]) == 0xFF1A_1A1A)
        #expect(warn[.aaFontFamilyName] as? String == "Consolas")
        #expect(Self.style(warn).alignment == .left && Self.style(warn).textBlocks.isEmpty)
        let expectedFamily = RichFontResolver.displayFamily(for: "Consolas")
        #expect(RichFontResolver.familyKey(of: Self.font(warn)) == expectedFamily)
    }

    // XD-V2.
    @Test func v2UnderlineAndBoldElements() {
        let (s, _) = RichTest.read(RichTest.doc(##"<Paragraph><Underline>Hello</Underline><Run> </Run><Bold><Run TextDecorations="Underline">world</Run></Bold></Paragraph>"##))
        let hello = RichTest.attrs(s, at: "Hello"), world = RichTest.attrs(s, at: "world")
        #expect(hello[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue && !RichFontResolver.isBoldish(Self.font(hello)))
        #expect(world[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue && RichFontResolver.isBoldish(Self.font(world)))
        #expect(world[.aaFontWeightToken] == nil)                   // the Bold style layer has no token
        let space = s.attributes(at: 5, effectiveRange: nil)
        #expect(space[.underlineStyle] == nil)
    }

    // XD-V3.
    @Test func v3NestedSection() {
        let (s, _) = RichTest.read(RichTest.doc(##"<Section FontSize="20" Foreground="#FF006400" TextAlignment="Center"><Paragraph><Run>Big</Run><Run FontSize="10">small</Run></Paragraph></Section><Paragraph><Run>after</Run></Paragraph>"##))
        let big = RichTest.attrs(s, at: "Big"), small = RichTest.attrs(s, at: "small"), after = RichTest.attrs(s, at: "after")
        #expect(Self.font(big).pointSize == 20 && Self.font(small).pointSize == 10 && Self.font(after).pointSize == 14)
        #expect(RichTest.argb(big[.foregroundColor]) == 0xFF00_6400 && RichTest.argb(after[.foregroundColor]) == 0xFF1A_1A1A)
        #expect(Self.style(big).alignment == .center && Self.style(after).alignment == .left)
        #expect((big[.aaSectionPath] as? [String])?.count == 1 && after[.aaSectionPath] == nil)
        #expect(Self.style(big).textBlocks.isEmpty)                  // no background / border / padding
    }

    // XD-V4a–c.
    @Test func v4BackgroundsAndLocks() {
        let (a, ma) = RichTest.read(RichTest.doc(##"<Paragraph Background="#FFFFFF00"><Run>Note: </Run><Run Background="#FF00FF00">green</Run></Paragraph>"##))
        let note = RichTest.attrs(a, at: "Note"), green = RichTest.attrs(a, at: "green")
        #expect(note[.backgroundColor] == nil && RichTest.argb(green[.backgroundColor]) == 0xFF00_FF00)
        let block = Self.style(note).textBlocks.first
        #expect(block is XamlParagraphBlock && block.map { RichColor.argb($0.backgroundColor!) } == 0xFFFF_FF00)
        #expect(note[.aaLockSource] == nil && !ma.hasAnyLock)

        let (b, mb) = RichTest.read(RichTest.doc(##"<Paragraph Background="#FFFFE699"><Run>7.5 bar</Run></Paragraph>"##))
        let bar = RichTest.attrs(b, at: "7.5")
        #expect(bar[.aaLockSource] as? String == "block" && bar[.aaLocked] as? Bool == true && bar[.backgroundColor] == nil)
        #expect(mb.hasAnyLock)
        #expect(Self.style(bar).textBlocks.first.map { RichColor.argb($0.backgroundColor!) } == XamlValues.sentinelARGB)

        let (c, _) = RichTest.read(RichTest.doc(##"<Paragraph><Span Background="#FFFFE699"><Run Background="#FFFFFF00">x</Run></Span></Paragraph>"##))
        let x = RichTest.attrs(c, at: "x")
        #expect(RichTest.argb(x[.backgroundColor]) == 0xFFFF_FF00 && x[.aaLockSource] as? String == "inlineAncestor")
    }

    // XD-V5.
    @Test func v5TableCellWeight() throws {
        let (s, _) = RichTest.read(RichTest.doc(##"<Table CellSpacing="0" Margin="0,4,0,4"><Table.Columns><TableColumn /><TableColumn /></Table.Columns><TableRowGroup><TableRow><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6,0.6,0.6,0.6" Padding="3,1,3,1" FontWeight="Bold" TextAlignment="Right"><Paragraph><Run>Head</Run><Run FontWeight="Normal"> (n)</Run></Paragraph></TableCell><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6,0.6,0.6,0.6" Padding="3,1,3,1"><Paragraph><Run>x</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table>"##))
        let head = RichTest.attrs(s, at: "Head"), n = RichTest.attrs(s, at: " (n)"), x = RichTest.attrs(s, at: "x")
        #expect(RichFontResolver.isBoldish(Self.font(head)) && !RichFontResolver.isBoldish(Self.font(n)))
        #expect(n[.aaFontWeightToken] as? String == "Normal")
        #expect(Self.style(head).alignment == .right && Self.style(x).alignment == .left)
        let b0 = try #require(Self.style(head).textBlocks.first as? NSTextTableBlock)
        let b1 = try #require(Self.style(x).textBlocks.first as? NSTextTableBlock)
        #expect(b0.table === b1.table && b0.table.numberOfColumns == 2 && b0.table.collapsesBorders)
        #expect(b0.startingColumn == 0 && b1.startingColumn == 1 && b0.startingRow == 0)
        #expect(abs(b0.width(for: .border, edge: .minX) - 0.6) < 1e-9 && b0.width(for: .padding, edge: .minX) == 3)
        #expect(b0.borderColor(for: .minX).map(RichColor.argb) == 0xFF9A_A0A6)
        // The synthetic paragraph after a final table (§6.4) is an ordinary, empty, table-less paragraph.
        #expect(s.string.hasSuffix("\n\n") && Self.style(s.attributes(at: s.length - 1, effectiveRange: nil)).textBlocks.isEmpty)
    }

    // XD-V6.
    @Test func v6ContentRootInEveryContext() {
        let v6 = ##"<Paragraph xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" FontSize="16" TextAlignment="Center"><Run>Hi </Run><Bold>there</Bold></Paragraph>"##
        let (s, m) = RichTest.read(v6)
        #expect(m.rootRole == .content(.paragraph))
        let hi = RichTest.attrs(s, at: "Hi"), there = RichTest.attrs(s, at: "there")
        #expect(Self.font(hi).pointSize == 16 && hi[.aaFontFamilyName] as? String == "Consolas")
        #expect(RichTest.argb(hi[.foregroundColor]) == 0xFF1A_1A1A && RichFontResolver.isBoldish(Self.font(there)))
        #expect(Self.style(hi).alignment == .center)
        #expect(RichAttributeCoding.decode(hi[.aaParagraphAttrs]).map(\.qualifiedName) == ["FontSize"])
        let (sp, _) = RichTest.read(v6, .sirePane)
        let shi = RichTest.attrs(sp, at: "Hi")
        #expect(shi[.aaFontFamilyName] as? String == "Segoe UI" && Self.font(shi).pointSize == 16)
        #expect(RichFontResolver.familyKey(of: Self.font(shi)) == RichFontResolver.displayFamily(for: "Segoe UI"))
    }

    // XD-V7 / CONT-167.
    @Test func v7HyperlinkDisplayColour() {
        let (s, m) = RichTest.read(RichTest.doc(##"<Paragraph Foreground="#FF800080"><Hyperlink NavigateUri="https://www.imo.org"><Run>IMO</Run></Hyperlink><Run> and </Run><Hyperlink><Run>x</Run><Run Foreground="#FFFF0000">y</Run></Hyperlink></Paragraph>"##))
        let imo = RichTest.attrs(s, at: "IMO"), and = RichTest.attrs(s, at: " and "), x = RichTest.attrs(s, at: "x"),
            y = RichTest.attrs(s, at: "y")
        #expect(RichTest.argb(imo[.foregroundColor]) == 0xFF00_66CC && imo[.aaLinkStyled] as? Bool == true)
        #expect(RichTest.argb(imo[.aaUnderlyingForeground]) == 0xFF80_0080)
        #expect((imo[.link] as? URL)?.absoluteString == "https://www.imo.org")
        #expect(RichTest.argb(and[.foregroundColor]) == 0xFF80_0080 && and[.aaLinkStyled] == nil)
        #expect(x[.aaLinkStyled] as? Bool == true && x[.link] == nil && x[.aaHyperlink] != nil)
        #expect(RichTest.argb(y[.foregroundColor]) == 0xFFFF_0000 && y[.aaLinkStyled] == nil)
        #expect((x[.aaHyperlink] as? String) == (y[.aaHyperlink] as? String))
        #expect((imo[.aaHyperlink] as? String) != (x[.aaHyperlink] as? String))
        #expect(imo[.underlineStyle] == nil)                         // the link underline is display-only
        #expect(m.hyperlinkAttributes[imo[.aaHyperlink] as! String]?.map(\.qualifiedName) == ["NavigateUri"])
    }

    // XD-V8.
    @Test func v8ContextLessRoot() {
        let x = ##"<Section xml:space="preserve" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Paragraph><Run>plain</Run><Run FontSize="16">big</Run></Paragraph></Section>"##
        let (e, _) = RichTest.read(x)
        #expect(Self.font(RichTest.attrs(e, at: "plain")).pointSize == 14 && Self.font(RichTest.attrs(e, at: "big")).pointSize == 16)
        let (sp, _) = RichTest.read(x, .sirePane)
        #expect(Self.font(RichTest.attrs(sp, at: "plain")).pointSize == 13)
        #expect(RichTest.argb(RichTest.attrs(sp, at: "plain")[.foregroundColor]) == 0xFF1A_1A1A)
    }

    // §7.7 item 2 / S-2: lists.
    @Test func s2NestedListMarkers() throws {
        let (s, _) = RichTest.read(try RichTest.sample("S-02-nested-bullets.xaml"))
        #expect(s.string == "\t•\tAlpha\n\t◦\tAlpha one\n\t•\tBeta\n\n")
        #expect(RichTest.paragraphs(s) == ["Alpha", "Alpha one", "Beta", ""])
        let alpha = Self.style(RichTest.attrs(s, at: "Alpha")), one = Self.style(RichTest.attrs(s, at: "Alpha one")),
            beta = Self.style(RichTest.attrs(s, at: "Beta"))
        #expect(alpha.textLists.count == 1 && one.textLists.count == 2 && beta.textLists.count == 1)
        #expect(alpha.textLists[0] === beta.textLists[0] && one.textLists[0] === alpha.textLists[0])
        #expect(alpha.textLists[0].markerFormat == .disc && one.textLists[1].markerFormat == .circle)
        #expect(alpha.headIndent == 24 && one.headIndent == 48 && alpha.firstLineHeadIndent == 0)
        #expect(s.attribute(.aaListMarker, at: 1, effectiveRange: nil) as? String == "•")
        let ids = ["Alpha", "Alpha one", "Beta"].map { RichTest.attrs(s, at: $0)[.aaListItemID] as? String }
        #expect(Set(ids.compactMap { $0 }).count == 3)
        // Plain text for consumers never contains markers.
        #expect(!XamlPlainText.diffText(RichTest.roundTrip(try RichTest.sample("S-02-nested-bullets.xaml"))).contains("•"))
    }

    @Test func s3NumberedMarkersAndStartIndex() {
        let (s, _) = RichTest.read(RichTest.doc(##"<List MarkerStyle="UpperRoman" StartIndex="4"><ListItem><Paragraph><Run>a</Run></Paragraph></ListItem><ListItem><Paragraph><Run>b</Run></Paragraph><Paragraph><Run>b2</Run></Paragraph></ListItem></List><List MarkerStyle="None"><ListItem><Paragraph><Run>n</Run></Paragraph></ListItem></List>"##))
        #expect(s.string.hasPrefix("\tIV.\ta\n\tV.\tb\nb2\nn\n"))
        let b2 = RichTest.attrs(s, at: "b2")
        #expect(b2[.aaListContinuation] as? Bool == true)
        #expect(b2[.aaListItemID] as? String == RichTest.attrs(s, at: "b\n")[.aaListItemID] as? String)
        #expect(Self.style(b2).headIndent == 49 && Self.style(b2).firstLineHeadIndent == 49)   // WPF default padding
        #expect(Self.style(RichTest.attrs(s, at: "a")).textLists[0].startingItemNumber == 4)
    }

    // §7.7 item 3 / S-4.
    @Test func s4Table() throws {
        let (s, _) = RichTest.read(try RichTest.sample("S-04-table-2x2.xaml"))
        var blocks: [NSTextTableBlock] = []
        for i in 0..<4 { blocks.append((Self.style(s.attributes(at: i, effectiveRange: nil)).textBlocks.first as? NSTextTableBlock)!) }
        #expect(blocks.map(\.startingRow) == [0, 0, 1, 1] && blocks.map(\.startingColumn) == [0, 1, 0, 1])
        #expect(Set(blocks.map { ObjectIdentifier($0.table) }).count == 1)
        #expect(RichFontResolver.isBoldish(Self.font(s.attributes(at: 0, effectiveRange: nil))))     // header row
        #expect(!RichFontResolver.isBoldish(Self.font(s.attributes(at: 2, effectiveRange: nil))))
    }

    // §7.7 item 4 / S-5.
    @Test func s5Hyperlink() throws {
        let (s, _) = RichTest.read(try RichTest.sample("S-05-hyperlink.xaml"))
        let l = RichTest.attrs(s, at: "https://www.imo.org/")
        #expect((l[.link] as? URL)?.absoluteString == "https://www.imo.org")
        #expect(RichTest.paragraphs(s) == ["See https://www.imo.org/"])
    }

    // §7.7 item 5 / S-6.
    @Test func s6LockLineBreakTabLanguage() throws {
        let (s, m) = RichTest.read(try RichTest.sample("S-06-lock-linebreak-tab-lang.xaml"))
        #expect(m.hasAnyLock)
        #expect(s.string == "Pressure: 7.5 bar — do not change\u{2028}\tColour check\n")
        let locked = RichTest.attrs(s, at: "7.5 bar")
        #expect(locked[.aaLockSource] as? String == "inlineRun" && RichTest.argb(locked[.backgroundColor]) == XamlValues.sentinelARGB)
        let ls = (s.string as NSString).range(of: "\u{2028}")
        #expect(s.attribute(.aaInRunNewline, at: ls.location, effectiveRange: nil) == nil)          // a LineBreak element
        #expect(RichTest.attrs(s, at: "\tColour")[.aaXmlLang] as? String == "en-gb")
        #expect(RichTest.attrs(s, at: "Pressure")[.aaLockSource] == nil)
    }

    // §7.7 item 6 / S-8 (SIRE root), 12 §6.5.
    @Test func s8SireBody() throws {
        let (s, m) = RichTest.read(try RichTest.sample("S-08-sire-body.xaml"), .containerEditor)
        #expect(m.rootAttributes.contains { $0.qualifiedName == "FontFamily" && $0.value == "Segoe UI" })
        let q = RichTest.attrs(s, at: "Q 2.1.10")
        #expect(Self.font(q).pointSize == 20 && q[.aaFontFamilyName] as? String == "Segoe UI")
        #expect(RichTest.argb(q[.foregroundColor]) == 0xFF1E_40AF)
        let meta = RichTest.attrs(s, at: "Ch 2")
        #expect(RichFontResolver.isItalic(Self.font(meta)) && Self.font(meta).pointSize == 11)
        // The chip: in-run newline → U+2028 marked "\n"; paragraph block with padding and background.
        let chip = (s.string as NSString).range(of: "certificates\u{2028}valid")
        #expect(chip.location != NSNotFound)
        let nl = chip.location + "certificates".utf16.count
        #expect(s.attribute(.aaInRunNewline, at: nl, effectiveRange: nil) as? String == "\n")
        let block = try #require(Self.style(s.attributes(at: chip.location, effectiveRange: nil)).textBlocks.first)
        #expect(RichColor.argb(block.backgroundColor!) == 0xFFF8_FAFC && block.width(for: .padding, edge: .minX) == 10)
        let tags = RichTest.attrs(s, at: "Smart tags")
        #expect(RichTest.argb(tags[.foregroundColor]) == 0xFF64_748B && Self.font(tags).pointSize == 10)
        let body = RichTest.attrs(s, at: "line one")
        #expect(RichTest.argb(body[.foregroundColor]) == 0xFF33_4155)        // the root foreground (Slate)
        let item = RichTest.attrs(s, at: "Check expiry")
        #expect(Self.style(item).textLists.count == 2)
    }

    // §7.7 item 7: opaque elements.
    @Test func opaqueElements() {
        let src = RichTest.doc("<Paragraph><Run>a</Run><InlineUIContainer><Button>x</Button></InlineUIContainer><Run>b</Run></Paragraph><BlockUIContainer><Image Source=\"x.png\"/></BlockUIContainer><Paragraph><Figure><Paragraph><Run>fig</Run></Paragraph></Figure></Paragraph>")
        let (s, _) = RichTest.read(src)
        let ns = s.string as NSString
        #expect(ns.range(of: "a\u{FFFC}b").location != NSNotFound)
        let att = s.attribute(.attachment, at: 1, effectiveRange: nil) as? XamlPreservedAttachment
        #expect(att?.xml == "<InlineUIContainer><Button>x</Button></InlineUIContainer>" && att?.isBlock == false)
        #expect(s.attribute(.aaPreservedXaml, at: 1, effectiveRange: nil) as? String == att?.xml)
        let paras = RichTest.paragraphs(s)
        #expect(paras.count == 3 && paras[1] == "\u{FFFC}" && paras[2] == "\u{FFFC}")
        let blockAtt = s.attribute(.attachment, at: ns.range(of: "\n").location + 1, effectiveRange: nil) as? XamlPreservedAttachment
        #expect(blockAtt?.isBlock == true && blockAtt?.xml == "<BlockUIContainer><Image Source=\"x.png\"/></BlockUIContainer>")
        #expect(att?.image != nil)
    }

    // CONT-166.
    @Test func lineBreakProvenance() {
        let (s, _) = RichTest.read(RichTest.doc("<Paragraph><Run>a&#xD;&#xA;b&#xD;c\nd</Run><LineBreak /><Run>e</Run></Paragraph>"))
        #expect(s.string == "a\u{2028}b\u{2028}c\u{2028}d\u{2028}e\n")
        let seqs = (0..<s.length).compactMap { s.attribute(.aaInRunNewline, at: $0, effectiveRange: nil) as? String }
        #expect(seqs == ["\r\n", "\r", "\n"])
    }

    @Test func decorationsBaselinesExtrasAndRunAttributes() {
        let (s, _) = RichTest.read(RichTest.doc(##"<Paragraph><Run TextDecorations="OverLine,Strikethrough">o</Run><Run BaselineAlignment="Superscript">2</Run><Run Typography.Variants="Subscript">3</Run><Run FontStretch="Condensed" Typography.Kerning="False">k</Run><Run Tag="t" Foo="1" x:Uid="u" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">e</Run><Run FlowDirection="RightToLeft">r</Run></Paragraph>"##))
        let o = RichTest.attrs(s, at: "o")
        #expect(o[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue && o[.aaExtraDecorations] as? [String] == ["OverLine"])
        let two = RichTest.attrs(s, at: "2"), three = RichTest.attrs(s, at: "3")
        #expect(two[.superscript] as? Int == 1 && two[.aaBaselineAlignment] as? String == "Superscript")
        #expect(three[.superscript] as? Int == -1 && three[.aaBaselineAlignment] == nil)
        #expect((three[.aaInheritedExtras] as? [String: String])?["Typography.Variants"] == "Subscript")
        let k = RichTest.attrs(s, at: "k")
        #expect(k[.aaInheritedExtras] as? [String: String] == ["FontStretch": "Condensed", "Typography.Kerning": "False"])
        let e = RichTest.attrs(s, at: "e")
        #expect(RichAttributeCoding.decode(e[.aaExtraAttributes]).map(\.qualifiedName) == ["Tag", "Foo", "x:Uid"])
        let r = RichTest.attrs(s, at: "r")
        #expect((r[.writingDirection] as? [NSNumber])?.first?.intValue == NSWritingDirection.rightToLeft.rawValue)
        #expect(o[.writingDirection] == nil)
    }

    @Test func brushPropertyElementsProjected() {
        let (s, _) = RichTest.read(RichTest.doc(##"<Paragraph><Run><Run.Foreground><SolidColorBrush Color="#FFFF0000" Opacity="0.5"/></Run.Foreground>a</Run><Run Foreground="{x:Null}">n</Run><Run><Run.Foreground><LinearGradientBrush><GradientStop Color="Red"/></LinearGradientBrush></Run.Foreground>g</Run></Paragraph>"##))
        let a = RichTest.attrs(s, at: "a")
        #expect((a[.foregroundColor] as? NSColor).map { abs($0.alphaComponent - 0.5) < 0.01 } == true)
        #expect(a[.aaForegroundBrushXml] as? String == ##"<SolidColorBrush Color="#FFFF0000" Opacity="0.5"/>"##)
        #expect(RichTest.argb(RichTest.attrs(s, at: "n")[.foregroundColor]) == 0xFF1A_1A1A)          // XD-X8
        let g = RichTest.attrs(s, at: "g")
        #expect(RichTest.argb(g[.foregroundColor]) == 0xFF1A_1A1A && (g[.aaForegroundBrushXml] as? String)?.hasPrefix("<LinearGradientBrush>") == true)
    }

    @Test func invalidValuesAreDisplayedTolerantly() {
        let (s, m) = RichTest.read(RichTest.doc(##"<Paragraph FontSize="abc"><Run>x</Run><Foo>y</Foo></Paragraph>"##))
        #expect(Self.font(RichTest.attrs(s, at: "x")).pointSize == 14)                                  // XD-L4
        if case .notLoadable = m.loadability {} else { Issue.record("notLoadable expected") }
        #expect(s.string.contains("\u{FFFC}"))                                                         // XD-L3 chip
    }

    // CONT-161.
    @Test func fragmentsResolveInTheDestination() throws {
        let html = HTMLToXAML.convert(##"<p>plain <b>bold</b></p><ul><li>one</li></ul>"##)
        let sire = XamlReader.destinationContext(in: NSAttributedString(), at: 0, base: .sirePane)
        let frag = try #require(XamlReader.readFragment(html, destinationContext: sire))
        #expect(RichTest.paragraphs(frag) == ["plain bold", "one"])
        #expect(RichTest.attrs(frag, at: "plain")[.aaFontFamilyName] as? String == "Segoe UI")
        #expect(Self.font(RichTest.attrs(frag, at: "plain")).pointSize == 13)
        #expect(Self.style(RichTest.attrs(frag, at: "one")).textLists.count == 1)
        // A fragment root with its own context overrides the destination.
        let own = try #require(XamlReader.readFragment(RichTest.doc("<Paragraph><Run>c</Run></Paragraph>"), destinationContext: .sirePane))
        #expect(RichTest.attrs(own, at: "c")[.aaFontFamilyName] as? String == "Consolas")
        // A namespace-less fragment is accepted.
        let bare = try #require(XamlReader.readFragment(##"<List MarkerStyle="Decimal"><ListItem><Paragraph><Run>x</Run></Paragraph></ListItem></List>"##, destinationContext: .containerEditor))
        #expect(bare.string == "\t1.\tx\n")
        #expect(XamlReader.readFragment("<a", destinationContext: .containerEditor) == nil)
        #expect(XamlReader.readFragment("", destinationContext: .containerEditor) == nil)
        // Two fragments never share element ids.
        let f1 = try #require(XamlReader.readFragment(bare.string.isEmpty ? "" : ##"<List><ListItem><Paragraph/></ListItem></List>"##, destinationContext: .containerEditor))
        let f2 = try #require(XamlReader.readFragment(##"<List><ListItem><Paragraph/></ListItem></List>"##, destinationContext: .containerEditor))
        #expect(f1.attribute(.aaListItemID, at: 0, effectiveRange: nil) as? String != f2.attribute(.aaListItemID, at: 0, effectiveRange: nil) as? String)
    }

    @Test func destinationContextFromCaretParagraph() {
        let (s, _) = RichTest.read(RichTest.doc(##"<Paragraph FontSize="20" Foreground="#FF00FF00" TextAlignment="Right"><Run>abc</Run></Paragraph>"##))
        let c = XamlReader.destinationContext(in: s, at: 1, base: .containerEditor)
        #expect(c.fontSize == 20 && c.foreground == 0xFF00_FF00 && c.textAlignment == .right && c.fontFamily == "Consolas")
    }
}
