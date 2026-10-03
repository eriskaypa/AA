// TV: 05 §XD.6.2 XD-C2/C3/C4/C10/C11/C13/C17/C18 (the NSAttributedString and Mac-writer columns the resolver-level
//     XamlStyleTests do not reach), §XD.6.5 XD-L2/L7/L8/L9 (editor column + writer), CONT-163 (Hyperlink keeps only
//     non-formatting attributes), CONT-165 (Span root → S-1 with the wrapper's inheritable values), CONT-166 (CR
//     sequences written back as `&#xD;`), 12 §6.5 (SIRE pane: collapsed margins, nested `.circle` lists, Segoe UI
//     token kept, body unchanged by a rewrite).
import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct RichVectorRowTests {
    static func font(_ a: [NSAttributedString.Key: Any]) -> NSFont { a[.font] as! NSFont }
    static func style(_ a: [NSAttributedString.Key: Any]) -> NSParagraphStyle { a[.paragraphStyle] as! NSParagraphStyle }

    /// Read, append one character to the first paragraph's text (an edit), write.
    static func editedWrite(_ xaml: String, _ ctx: XamlContext = .containerEditor, prefix: String = "z") -> String {
        let (s, m) = RichTest.read(xaml, ctx)
        let e = NSMutableAttributedString(attributedString: s)
        e.insert(NSAttributedString(string: prefix, attributes: e.attributes(at: 0, effectiveRange: nil)), at: 0)
        return XamlWriter.write(e, metadata: m, context: ctx)
    }

    @Test func c2LightFaceWithoutBoldTrait() {
        let src = RichTest.doc(##"<Paragraph><Bold><Run FontWeight="Light">a</Run></Bold></Paragraph>"##)
        let a = RichTest.attrs(RichTest.read(src).0, at: "a")
        #expect(!Self.font(a).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(a[.aaFontWeightToken] as? String == "Light")
        #expect(RichTest.body(RichTest.roundTrip(src)) == ##"<Paragraph><Run FontWeight="Light">a</Run></Paragraph>"##)
    }

    @Test func c3c4c11FlattenedDecorationsAndWeights() {
        #expect(RichTest.body(RichTest.roundTrip(RichTest.doc("<Paragraph><Italic><Bold>a</Bold></Italic></Paragraph>")))
                == ##"<Paragraph><Run FontStyle="Italic" FontWeight="Bold">a</Run></Paragraph>"##)
        #expect(RichTest.body(RichTest.roundTrip(RichTest.doc(##"<Paragraph><Underline TextDecorations="Strikethrough">a</Underline></Paragraph>"##)))
                == ##"<Paragraph><Run TextDecorations="Strikethrough">a</Run></Paragraph>"##)
        let c11 = RichTest.doc(##"<Paragraph TextDecorations="Strikethrough"><Run TextDecorations="Underline">a</Run></Paragraph>"##)
        let a = RichTest.attrs(RichTest.read(c11).0, at: "a")
        #expect(a[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(a[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
        // Paragraph.TextDecorations is flattened onto the Run (CONT-163).
        #expect(RichTest.body(RichTest.roundTrip(c11)) == ##"<Paragraph><Run TextDecorations="Underline,Strikethrough">a</Run></Paragraph>"##)
    }

    @Test func c10HalfAlphaGoldAndC13TransparentInk() {
        let (s, _) = RichTest.read(RichTest.doc(##"<Paragraph><Run Background="#80FFE699">a</Run><Run Foreground="Transparent">b</Run></Paragraph>"##))
        let a = RichTest.attrs(s, at: "a")
        #expect(a[.aaLockSource] == nil && !LockRules.isLocked(s, at: 0))
        #expect((a[.backgroundColor] as? NSColor).map { abs($0.alphaComponent - 0.5) < 0.01 } == true)
        #expect((RichTest.attrs(s, at: "b")[.foregroundColor] as? NSColor)?.alphaComponent == 0)
    }

    @Test func c17SireChipWriterDropsTheRedundantRunForeground() {
        let root = "<Section xmlns=\"\(RichTest.P)\" xml:space=\"preserve\" FontFamily=\"Segoe UI\" FontSize=\"13\" FontWeight=\"Normal\" Foreground=\"#FF334155\">"
        let src = root + ##"<Paragraph Margin="0,2,0,8" Padding="10,8,10,8" Background="#FFF8FAFC"><Run Foreground="#FF334155">full</Run></Paragraph></Section>"##
        let a = RichTest.attrs(RichTest.read(src, .sirePane).0, at: "full")
        #expect(Self.font(a).pointSize == 13 && a[.aaFontFamilyName] as? String == "Segoe UI")
        #expect(RichTest.argb(a[.foregroundColor]) == 0xFF33_4155)
        let block = Self.style(a).textBlocks.first
        #expect(block.flatMap { RichTest.argb($0.backgroundColor) } == 0xFFF8_FAFC)
        #expect(block.map { [$0.width(for: .padding, edge: .minX), $0.width(for: .padding, edge: .minY),
                             $0.width(for: .padding, edge: .maxX), $0.width(for: .padding, edge: .maxY)] } == [10, 8, 10, 8])
        let out = Self.editedWrite(src, .sirePane, prefix: "x")
        #expect(out.hasSuffix(##"<Paragraph Margin="0,2,0,8" Padding="10,8,10,8" Background="#FFF8FAFC"><Run>xfull</Run></Paragraph></Section>"##))
    }

    @Test func c18SpanRootReadsAsOneParagraphAndWritesAnS1Root() {
        let src = "<Span xmlns=\"\(RichTest.P)\" FontWeight=\"Bold\"><Run>x</Run></Span>"
        let (s, _) = RichTest.read(src)
        #expect(RichTest.paragraphs(s) == ["x"])
        #expect(Self.font(RichTest.attrs(s, at: "x")).fontDescriptor.symbolicTraits.contains(.bold))
        let out = Self.editedWrite(src)
        #expect(out.hasPrefix("<Section ") && out.contains(##" FontWeight="Bold" "##))       // the wrapper's value wins over S-1
        #expect(RichTest.body(out) == "<Paragraph><Run>zx</Run></Paragraph>")
    }

    @Test func loadabilityVectorsInTheEditorAndWriter() {
        let P = RichTest.P
        let cases: [(String, String)] = [
            ("<Section xmlns=\"\(P)\"><Run>x</Run></Section>", "x"),                                                    // L2
            ("<Section xmlns=\"\(P)\"><Paragraph><Run Text=\"a\">b</Run></Paragraph></Section>", "b"),                  // L7
            ("<Section xmlns=\"\(P)\"><Paragraph><Run Foreground=\"#FF00FF00\"><Run.Foreground><SolidColorBrush Color=\"Red\"/></Run.Foreground>x</Run></Paragraph></Section>", "x"), // L8
            ("<Section xmlns=\"\(P)\"><Paragraph><Run Foreground=\"{StaticResource Fg}\">x</Run></Paragraph></Section>", "x"), // L9
        ]
        for (src, text) in cases {
            let (s, m) = RichTest.read(src)
            #expect(RichTest.paragraphs(s) == [text])
            if case .notLoadable = m.loadability {} else { Issue.record("expected notLoadable: \(src)") }
            // The rewrite is loadable: nothing invalid is re-emitted.
            let out = RichTest.roundTrip(src)
            if case .success(let d) = XamlDOM.parse(out) { #expect(d.loadability == .loadable, "\(out)") } else { Issue.record("unparseable \(out)") }
        }
        #expect(RichTest.argb(RichTest.attrs(RichTest.read(cases[2].0).0, at: "x")[.foregroundColor]) == 0xFFFF_0000)
        #expect(RichTest.argb(RichTest.attrs(RichTest.read(cases[3].0).0, at: "x")[.foregroundColor]) == 0xFF1A_1A1A)
        #expect(RichTest.body(RichTest.roundTrip(cases[1].0)) == "<Paragraph><Run>b</Run></Paragraph>")
        #expect(RichTest.body(RichTest.roundTrip(cases[2].0)) == ##"<Paragraph><Run Foreground="#FFFF0000">x</Run></Paragraph>"##)
        #expect(RichTest.body(RichTest.roundTrip(cases[3].0)) == "<Paragraph><Run>x</Run></Paragraph>")
    }

    @Test func carriageReturnSequencesAreWrittenBackAsCharacterReferences() {
        let out = RichTest.body(Self.editedWrite(RichTest.doc("<Paragraph><Run>a&#xD;&#xA;b&#xD;c</Run></Paragraph>")))
        #expect(out == "<Paragraph><Run>za&#xD;\nb&#xD;c</Run></Paragraph>")
        // Reading that back gives the same sequences again.
        let (s, _) = RichTest.read(RichTest.doc(out))
        let seqs = (0..<s.length).compactMap { s.attribute(.aaInRunNewline, at: $0, effectiveRange: nil) as? String }
        #expect(seqs == ["\r\n", "\r"])
    }

    @Test func hyperlinkWrapperCarriesOnlyNonFormattingAttributes() {
        let body = ##"<Paragraph><Hyperlink NavigateUri="https://a.b" FontWeight="Bold" Foreground="#FF008000" ToolTip="t"><Run>a</Run></Hyperlink></Paragraph>"##
        let out = RichTest.body(Self.editedWrite(RichTest.doc(body)))
        #expect(out == ##"<Paragraph><Hyperlink NavigateUri="https://a.b" ToolTip="t"><Run FontWeight="Bold" Foreground="#FF008000">za</Run></Hyperlink></Paragraph>"##)
    }

    @Test func sirePaneMarginsListsAndFontToken() {
        let root = "<Section xmlns=\"\(RichTest.P)\" xml:space=\"preserve\" FontFamily=\"Segoe UI\" FontSize=\"13\" Foreground=\"#FF000000\">"
        let src = root + ##"<Paragraph Margin="0,4,0,10"><Run>a</Run></Paragraph><Paragraph Margin="0,16,0,2"><Run>b</Run></Paragraph><List MarkerStyle="Disc"><ListItem><Paragraph Margin="0,1,0,1"><Run>i1</Run></Paragraph><List MarkerStyle="Circle"><ListItem><Paragraph Margin="0,1,0,1"><Run>n1</Run></Paragraph></ListItem></List></ListItem></List></Section>"##
        let (s, _) = RichTest.read(src, .sirePane)
        // WPF collapses adjacent margins: max(prev.bottom, top) apart = after 10 + before max(0, 16 − 10).
        #expect(Self.style(RichTest.attrs(s, at: "a")).paragraphSpacing == 10)
        #expect(Self.style(RichTest.attrs(s, at: "b")).paragraphSpacingBefore == 6)
        let n1 = Self.style(RichTest.attrs(s, at: "n1"))
        #expect(n1.textLists.count == 2 && n1.textLists.first?.markerFormat == .disc && n1.textLists.last?.markerFormat == .circle)
        #expect(RichTest.attrs(s, at: "a")[.aaFontFamilyName] as? String == "Segoe UI")
        #expect(RichTest.argb(RichTest.attrs(s, at: "a")[.foregroundColor]) == 0xFF00_0000)
        // Only the root is completed (CONT-165); the body is written back unchanged.
        #expect(RichTest.body(RichTest.roundTrip(src, .sirePane)) == RichTest.body(src))
    }
}
