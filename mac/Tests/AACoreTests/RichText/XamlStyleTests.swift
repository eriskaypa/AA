// TV: 05 §XD.6.2 XD-C1…C18 (computed-style unit vectors, editor context inside R), §XD.2.5 (contexts), §XD.2.6
//     (precedence: local → style layer → inherited → root / context; setter ids), §XD.2.7 (modelDecorations,
//     displayDecorations, inlineBackground, blockFill, pdfEffectiveBackground, lockSource, isLinkStyled,
//     baselineShift), CONT-155 (root non-inheritables ignored), CONT-156 (inheritance through tables).
import Foundation
import Testing
@testable import AACore

@Suite struct XamlStyleTests {
    static func resolve(_ body: String, wrap: Bool = true, _ ctx: XamlContext = .containerEditor) throws -> (XamlDocument, XamlStyleResolver) {
        let src = wrap ? RichTest.doc(body) : body
        guard case .success(let d) = XamlDOM.parse(src) else { throw XamlStyleTestsError.parse }
        return (d, XamlStyleResolver(d, context: ctx))
    }

    enum XamlStyleTestsError: Error { case parse }

    /// The id of the run whose text is `t`.
    static func run(_ d: XamlDocument, _ t: String) -> XamlNodeID {
        d.allNodeIDs.first { d[$0].kind == .run && d[$0].text == t }!
    }

    @Test func contexts() {
        let e = XamlContext.containerEditor
        #expect(e.fontFamily == "Consolas" && e.fontSize == 14 && e.foreground == 0xFF1A_1A1A && e.language == "en-us")
        #expect(e.typography["Typography.Kerning"] == "True" && e.typography.count == 43)
        #expect(e.numberSubstitution == ["NumberSubstitution.CultureSource": "User", "NumberSubstitution.Substitution": "AsCulture"])
        #expect(XamlContext.pdf.fontFamily == "Segoe UI" && XamlContext.pdf.fontSize == 12 && XamlContext.pdf.foreground == 0xFF00_0000)
        #expect(XamlContext.sirePane.fontSize == 13 && XamlContext.sirePane.foreground == 0xFF1A_1A1A)
        #expect(e.linkDisplayColor == 0xFF00_66CC && e.lineHeight.isNaN && !e.isHyphenationEnabled)
    }

    @Test func c1LocalBeatsStyleLayer() throws {
        let (d, r) = try Self.resolve("<Paragraph><Bold FontWeight=\"Normal\"><Run>a</Run></Bold></Paragraph>")
        #expect(r.computed(Self.run(d, "a")).fontWeight == 400)
    }

    @Test func c2LightInsideBold() throws {
        let (d, r) = try Self.resolve("<Paragraph><Bold><Run FontWeight=\"Light\">a</Run></Bold></Paragraph>")
        let a = Self.run(d, "a")
        #expect(r.computed(a).fontWeight == 300)
        #expect(r.computed(a).setter[.fontWeight] == a)
    }

    @Test func c3ItalicAndBoldLayers() throws {
        let (d, r) = try Self.resolve("<Paragraph><Italic><Bold>a</Bold></Italic></Paragraph>")
        let c = r.computed(Self.run(d, "a"))
        #expect(c.fontWeight == 700 && c.fontStyle == .italic)
    }

    @Test func c4UnderlineElementWithLocalDecorations() throws {
        let (d, r) = try Self.resolve("<Paragraph><Underline TextDecorations=\"Strikethrough\">a</Underline></Paragraph>")
        let a = Self.run(d, "a")
        #expect(r.modelDecorations(a) == [.strikethrough])
        #expect(d[a].local.textDecorations == nil)                      // PDF (own value only): neither
    }

    @Test func c5ListAlignmentInherits() throws {
        let (d, r) = try Self.resolve("<List TextAlignment=\"Right\"><ListItem><Paragraph><Run>a</Run></Paragraph></ListItem></List>")
        let p = d.enclosingParagraph(of: Self.run(d, "a"))!
        #expect(r.computed(p).textAlignment == .right)
    }

    @Test func c6LocalAutoBeatsInheritedLineHeight() throws {
        let (d, r) = try Self.resolve("<Section LineHeight=\"30\"><Paragraph><Run>a</Run></Paragraph><Paragraph LineHeight=\"Auto\"><Run>b</Run></Paragraph></Section>")
        #expect(r.computed(d.enclosingParagraph(of: Self.run(d, "a"))!).lineHeight == 30)
        #expect(r.computed(d.enclosingParagraph(of: Self.run(d, "b"))!).lineHeight.isNaN)
    }

    @Test func c7TableInheritanceAndColumns() throws {
        let (d, r) = try Self.resolve("<Table FontSize=\"10\"><Table.Columns><TableColumn Background=\"#FFFF0000\"/></Table.Columns><TableRowGroup><TableRow><TableCell><Paragraph><Run>a</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table>")
        let a = Self.run(d, "a")
        #expect(r.computed(a).fontSize == 10)
        let cell = d.allNodeIDs.first { d[$0].kind == .tableCell }!
        #expect(r.blockFill(cell) == nil && r.inlineBackground(a) == nil && r.pdfEffectiveBackground(a) == nil)
    }

    @Test func c8Language() throws {
        let (d, r) = try Self.resolve("<Paragraph xml:lang=\"el-gr\"><Run>a</Run><Run xml:lang=\"EN-GB\">b</Run></Paragraph>")
        #expect(r.computed(Self.run(d, "a")).language == "el-gr")
        #expect(r.computed(Self.run(d, "b")).language == "en-gb")
    }

    @Test func c9TransparentInnerBackground() throws {
        let (d, r) = try Self.resolve("<Paragraph><Span Background=\"#FFFFFF00\"><Run Background=\"#00FFFFFF\">a</Run></Span></Paragraph>")
        let a = Self.run(d, "a")
        #expect(r.inlineBackground(a) == .solid(argb: 0xFFFF_FF00, opacity: 1, isScRgb: false))
        #expect(r.pdfEffectiveBackground(a) == .solid(argb: 0x00FF_FFFF, opacity: 1, isScRgb: false))
    }

    @Test func c10HalfAlphaGoldIsNotALock() throws {
        let (d, r) = try Self.resolve("<Paragraph><Run Background=\"#80FFE699\">a</Run></Paragraph>")
        let a = Self.run(d, "a")
        #expect(r.lockSource(a) == nil)
        #expect(r.inlineBackground(a) == .solid(argb: 0x80FF_E699, opacity: 1, isScRgb: false))
    }

    @Test func c11ParagraphDecorations() throws {
        let (d, r) = try Self.resolve("<Paragraph TextDecorations=\"Strikethrough\"><Run TextDecorations=\"Underline\">a</Run></Paragraph>")
        let a = Self.run(d, "a")
        #expect(r.modelDecorations(a) == [.underline, .strikethrough])
        #expect(d[a].local.textDecorations == [.underline])
    }

    @Test func c12PropertyElementBrush() throws {
        let (d, r) = try Self.resolve("<Paragraph><Run><Run.Foreground><SolidColorBrush Color=\"#FFFF0000\" Opacity=\"0.5\"/></Run.Foreground>a</Run></Paragraph>")
        #expect(r.computed(Self.run(d, "a")).foreground == .solid(argb: 0xFFFF_0000, opacity: 0.5, isScRgb: false))
    }

    @Test func c13TransparentForeground() throws {
        let (d, r) = try Self.resolve("<Paragraph><Run Foreground=\"Transparent\">a</Run></Paragraph>")
        #expect(r.computed(Self.run(d, "a")).foreground == .solid(argb: 0x00FF_FFFF, opacity: 1, isScRgb: false))
    }

    @Test func c14SectionWeightReachesCells() throws {
        let (d, r) = try Self.resolve("<Section FontWeight=\"Bold\"><Table><TableRowGroup><TableRow><TableCell><Paragraph><Run>a</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table></Section>")
        let cell = d.allNodeIDs.first { d[$0].kind == .tableCell }!
        #expect(r.computed(cell).fontWeight == 700 && r.computed(Self.run(d, "a")).fontWeight == 700)
    }

    @Test func c15RootNonInheritablesAreIgnored() throws {
        let src = "<Section xmlns=\"\(RichTest.P)\" xml:space=\"preserve\" Background=\"#FFFFE699\"><Paragraph><Run>a</Run></Paragraph></Section>"
        let (d, r) = try Self.resolve(src, wrap: false)
        let a = Self.run(d, "a")
        #expect(r.lockSource(a) == nil && r.blockFill(d.root) == nil && r.pdfEffectiveBackground(a) == nil)
        #expect(!LockRules.quickHasAnyLock(src))
    }

    @Test func c16HyperlinkWithLocalForeground() throws {
        let (d, r) = try Self.resolve("<Paragraph><Hyperlink Foreground=\"#FF008000\" NavigateUri=\"https://a.b\"><Run>a</Run></Hyperlink></Paragraph>")
        let a = Self.run(d, "a")
        #expect(r.computed(a).foreground == .solid(argb: 0xFF00_8000, opacity: 1, isScRgb: false))
        #expect(!r.isLinkStyled(a))
    }

    @Test func c17SireRoot() throws {
        let sire = try RichTest.sample("S-08-sire-body.xaml")
        guard case .success(let d) = XamlDOM.parse(sire) else { Issue.record("parse"); return }
        let r = XamlStyleResolver(d, context: .sirePane)
        let full = d.allNodeIDs.first { d[$0].kind == .run && (d[$0].text ?? "").hasPrefix("Were all") }!
        let c = r.computed(full)
        #expect(c.fontFamily.raw == "Segoe UI" && c.fontSize == 13 && c.foreground == .solid(argb: 0xFF33_4155, opacity: 1, isScRgb: false))
        let p = d.enclosingParagraph(of: full)!
        #expect(r.blockFill(p) == .solid(argb: 0xFFF8_FAFC, opacity: 1, isScRgb: false))
        #expect(r.pdfEffectiveBackground(full) == .solid(argb: 0xFFF8_FAFC, opacity: 1, isScRgb: false))
    }

    @Test func c18SpanRoot() throws {
        let (d, r) = try Self.resolve("<Span xmlns=\"\(RichTest.P)\" FontWeight=\"Bold\"><Run>x</Run></Span>", wrap: false)
        #expect(r.computed(Self.run(d, "x")).fontWeight == 700)
    }

    @Test func precedenceAndSetters() throws {
        let (d, r) = try Self.resolve("<Paragraph Foreground=\"#FF800080\"><Span FontSize=\"20\"><Span FontSize=\"18\"><Run>a</Run></Span></Span><Run>b</Run></Paragraph>")
        let a = Self.run(d, "a"), b = Self.run(d, "b")
        #expect(r.computed(a).fontSize == 18 && r.computed(b).fontSize == 14)
        let p = d.enclosingParagraph(of: a)!
        #expect(r.computed(a).setter[.foreground] == p)
        #expect(r.computed(b).setter[.fontSize] == d.root)            // supplied by the S-1 root
        // Context only: a context-less root leaves no setter.
        let (d2, r2) = try Self.resolve("<Section xmlns=\"\(RichTest.P)\"><Paragraph><Run>c</Run></Paragraph></Section>", wrap: false)
        #expect(r2.computed(Self.run(d2, "c")).setter[.fontSize] == nil)
        #expect(r2.computed(Self.run(d2, "c")).fontFamily.raw == "Consolas")
        let r3 = XamlStyleResolver(d2, context: .pdf)
        #expect(r3.computed(Self.run(d2, "c")).fontSize == 12)            // XD-V8 PDF consumer
    }

    @Test func decorationsAndLinkUnderline() throws {
        let (d, r) = try Self.resolve("<Paragraph><Hyperlink NavigateUri=\"u\"><Run>a</Run></Hyperlink><Hyperlink TextDecorations=\"None\"><Run>b</Run></Hyperlink><Span TextDecorations=\"Underline\"><Run TextDecorations=\"None\">c</Run></Span></Paragraph>")
        #expect(r.modelDecorations(Self.run(d, "a")) == [])
        #expect(r.displayDecorations(Self.run(d, "a")) == [.underline])
        #expect(r.displayDecorations(Self.run(d, "b")) == [])
        #expect(r.modelDecorations(Self.run(d, "c")) == [.underline])  // union: None does not cancel (XD-Q7)
    }

    @Test func lockSources() throws {
        let (d, r) = try Self.resolve("<Paragraph><Run Background=\"#FFFFE699\">a</Run><Span Background=\"#FFFFE699\"><Run>b</Run><Run Background=\"#FFFFFF00\">c</Run></Span></Paragraph><Paragraph Background=\"#FFFFE699\"><Run>d</Run></Paragraph><List><ListItem Background=\"#FFE699\"><Paragraph><Run>e</Run></Paragraph></ListItem></List><Paragraph><Run><Run.Background><SolidColorBrush Color=\"#FFFFE699\" Opacity=\"0.3\"/></Run.Background>f</Run><Run Background=\"sc#1,1,0.79,0.32\">g</Run></Paragraph>")
        #expect(r.lockSource(Self.run(d, "a")) == .inlineRun)
        #expect(r.lockSource(Self.run(d, "b")) == .inlineRun)               // the Span's sentinel is what shows
        #expect(r.lockSource(Self.run(d, "c")) == .inlineAncestor)          // V4c
        #expect(r.lockSource(Self.run(d, "d")) == .block)                   // V4b
        #expect(r.lockSource(Self.run(d, "e")) == .block)
        #expect(r.lockSource(Self.run(d, "f")) == .inlineRun)               // opacity ignored
        #expect(r.lockSource(Self.run(d, "g")) == nil)                      // scRGB never counts
    }

    @Test func baselineShifts() throws {
        let (d, r) = try Self.resolve("<Paragraph><Run Typography.Variants=\"Subscript\">a</Run><Span BaselineAlignment=\"Superscript\"><Run>b</Run></Span><Run BaselineAlignment=\"Top\">c</Run><Run>d</Run></Paragraph>")
        #expect(r.baselineShift(Self.run(d, "a")) == -1)
        #expect(r.baselineShift(Self.run(d, "b")) == 1)
        #expect(r.baselineShift(Self.run(d, "c")) == 0)
        #expect(r.baselineShift(Self.run(d, "d")) == 0)
    }

    @Test func freshContextPerLoad() throws {
        // CONT-155: nothing carries over between loads (each resolver starts from its own context).
        let (d1, r1) = try Self.resolve("<Section xmlns=\"\(RichTest.P)\" FontSize=\"30\"><Paragraph><Run>x</Run></Paragraph></Section>", wrap: false)
        let (d2, r2) = try Self.resolve("<Section xmlns=\"\(RichTest.P)\"><Paragraph><Run>y</Run></Paragraph></Section>", wrap: false)
        #expect(r1.computed(Self.run(d1, "x")).fontSize == 30 && r2.computed(Self.run(d2, "y")).fontSize == 14)
    }
}
