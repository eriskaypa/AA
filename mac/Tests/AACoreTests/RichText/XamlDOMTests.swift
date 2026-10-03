// TV: 05 §XD.2.1 (parse pipeline), CONT-151…155 (kinds, parent links, raw + parsed attributes, property elements,
//     roots), §XD.6.5 XD-L1…L10 (loadability), §4.3.1 (reading tolerance), §XD.5 (UTF-16 source ranges).
import Foundation
import Testing
@testable import AACore

@Suite struct XamlDOMTests {
    static let P = RichTest.P

    static func parse(_ s: String) -> XamlDocument? {
        if case .success(let d) = XamlDOM.parse(s) { return d }
        return nil
    }

    static func wrap(_ body: String) -> String { "<Section xmlns=\"\(P)\" xml:space=\"preserve\">" + body + "</Section>" }

    static func kinds(_ d: XamlDocument) -> [XamlNodeKind] { d.nodes.map(\.kind) }

    // MARK: Fatal errors

    @Test func fatalErrors() {
        #expect(XamlDOM.parse("<Section><Paragraph>Hi</Paragraph></Section>") == .failure(.wrongRootNamespace(nil)))   // XD-L1
        #expect(XamlDOM.parse("<Section xmlns=\"urn:x\"/>") == .failure(.wrongRootNamespace("urn:x")))
        #expect(XamlDOM.parse("<!DOCTYPE x><Section xmlns=\"\(Self.P)\"/>") == .failure(.dtdPresent))                 // XD-L5
        for bad in ["<Section><Paragraph>", "", "   ", "text", "<Section xmlns=\"\(Self.P)\">&nbsp;</Section>",
                    "<Section xmlns=\"\(Self.P)\"></Paragraph>", "<Section xmlns=\"\(Self.P)\"/><Section xmlns=\"\(Self.P)\"/>",
                    "<Section xmlns=\"\(Self.P)\" a=\"1\" a=\"2\"/>", "<Section xmlns=\"\(Self.P)\" a=\"<\"/>",
                    "<Section xmlns=\"\(Self.P)\"><p:Run/></Section>", "<Section xmlns=\"\(Self.P)\">]]></Section>",
                    "<Section xmlns=\"\(Self.P)\">&#0;</Section>", "<Section xmlns=\"\(Self.P)\">\u{1}</Section>",
                    "<Section xmlns=\"\(Self.P)\"/>trailing", "enc:AAAA"] {
            guard case .failure(let e) = XamlDOM.parse(bad) else { Issue.record("parsed: \(bad)"); continue }
            if case .malformedXML = e {} else if case .wrongRootNamespace = e {} else { Issue.record("\(bad): \(e)") }
        }
    }

    @Test func toleratesBomDeclarationWhitespaceAndComments() throws {
        let s = "\u{FEFF}  <?xml version=\"1.0\" encoding=\"utf-8\"?>\n<!-- c --><Section xmlns=\"\(Self.P)\"><!--x--><Paragraph><Run>a</Run></Paragraph></Section>\n"
        let d = try #require(Self.parse(s))
        #expect(d.rootRole == .wrapper(.section))
        #expect(d.loadability == .loadable)
        #expect(Self.kinds(d) == [.section, .paragraph, .run])
        #expect(d.nodes[2].text == "a")
    }

    // MARK: Kinds, implicit nodes, text

    @Test func implicitRunsAndTextAttribute() throws {
        let d = try #require(Self.parse(Self.wrap("<Paragraph>bare <Bold>bold</Bold><Run Text=\"attr\"/><LineBreak/>tail</Paragraph>")))
        let p = d.nodes[1]
        #expect(p.kind == .paragraph && p.children.count == 5)
        let texts = p.children.map { d[$0] }
        #expect(texts[0].kind == .run && texts[0].isImplicit && texts[0].text == "bare ")
        #expect(texts[1].kind == .bold && d[texts[1].children[0]].text == "bold" && d[texts[1].children[0]].isImplicit)
        #expect(texts[2].kind == .run && !texts[2].isImplicit && texts[2].text == "attr")
        #expect(texts[3].kind == .lineBreak)
        #expect(texts[4].text == "tail")
        #expect(d.loadability == .loadable)
    }

    @Test func runTextAndContent() throws {
        let d = try #require(Self.parse(Self.wrap("<Paragraph><Run Text=\"a\">b</Run></Paragraph>")))         // XD-L7
        #expect(d.nodes[2].text == "b")
        #expect(d.issues.contains(.runTextAndContent))
        if case .notLoadable = d.loadability {} else { Issue.record("expected notLoadable") }
    }

    @Test func entitiesNewlinesAndCharacterReferences() throws {
        let d = try #require(Self.parse(Self.wrap("<Paragraph><Run>a &amp; b &lt;&gt;&quot;&apos; &#169;&#x263A;\r\nx\ry&#xD;&#xA;z</Run></Paragraph>")))
        #expect(d.nodes[2].text == "a & b <>\"' ©☺\nx\ny\r\nz")
        let a = try #require(Self.parse("<Section xmlns=\"\(Self.P)\" Tag=\"a\tb\nc&#xA;d\"/>"))
        #expect(a.nodes[0].rawAttributes.first { $0.qualifiedName == "Tag" }?.value == "a b c\nd")
    }

    @Test func whitespaceRules() throws {
        // Whitespace between blocks is insignificant; inside inlines (xml:space=preserve) it is content.
        let d = try #require(Self.parse(Self.wrap("\n  <Paragraph> <Run> x </Run> </Paragraph>\n")))
        #expect(Self.kinds(d) == [.section, .paragraph, .run, .run, .run])
        #expect(d.nodes[2].text == " " && d.nodes[3].text == " x " && d.nodes[4].text == " ")
        // Without xml:space the XAML default normalisation collapses and trims.
        let n = try #require(Self.parse("<Section xmlns=\"\(Self.P)\"><Paragraph>  a   <Run>  b  c </Run>  d <LineBreak/>  e  </Paragraph></Section>"))
        let runs = n.nodes.filter { $0.kind == .run }.map { $0.text ?? "" }
        #expect(runs == ["a ", " b c ", " d", "e"])
    }

    @Test func textAndInlinesInBlockContainers() throws {
        let d = try #require(Self.parse(Self.wrap("<Run>x</Run>")))                                              // XD-L2
        #expect(Self.kinds(d) == [.section, .paragraph, .run])
        #expect(d.nodes[1].isImplicit)
        #expect(d.issues.contains { if case .invalidNesting = $0 { return true }; return false })
        if case .notLoadable = d.loadability {} else { Issue.record("expected notLoadable") }
        let t = try #require(Self.parse(Self.wrap("loose <Paragraph/>")))
        #expect(t.issues.contains(.textInBlockContainer))
        #expect(t.nodes.filter { $0.kind == .paragraph }.count == 2)
    }

    @Test func listsAndTablesStructure() throws {
        let d = try #require(Self.parse(Self.wrap("<List MarkerStyle=\"decimal\" StartIndex=\"3\"><ListItem><Paragraph><Run>a</Run></Paragraph></ListItem></List><Table CellSpacing=\"0\"><Table.Columns><TableColumn Width=\"2*\"/><TableColumn Width=\"Auto\"/></Table.Columns><TableRowGroup><TableRow><TableCell ColumnSpan=\"2\"><Paragraph/></TableCell></TableRow></TableRowGroup></Table>")))
        let list = try #require(d.nodes.first { $0.kind == .list })
        #expect(list.local.markerStyle == "Decimal" && list.local.startIndex == 3)
        let table = try #require(d.nodes.first { $0.kind == .table })
        #expect(table.local.cellSpacing == 0)
        let cols = table.children.map { d[$0] }.filter { $0.kind == .tableColumn }
        #expect(cols.count == 2 && cols[1].local.width?.isNaN == true && cols[0].local.width == nil)
        #expect(table.propertyElements.map(\.propertyName) == ["Columns"])
        let cell = try #require(d.nodes.first { $0.kind == .tableCell })
        #expect(cell.local.columnSpan == 2)
        #expect(d.loadability == .loadable)
    }

    @Test func transparentCollectionPropertyElements() throws {
        let d = try #require(Self.parse(Self.wrap("<Paragraph><Paragraph.Inlines><Run>a</Run></Paragraph.Inlines></Paragraph><List><List.ListItems><ListItem><ListItem.Blocks><Paragraph/></ListItem.Blocks></ListItem></List.ListItems></List>")))
        #expect(Self.kinds(d) == [.section, .paragraph, .run, .list, .listItem, .paragraph])
        #expect(d.nodes[1].propertyElements.isEmpty)
    }

    // MARK: Attributes (CONT-153, XD.2.2)

    @Test func rawAndTypedAttributes() throws {
        let d = try #require(Self.parse(Self.wrap("<Paragraph xml:lang=\"EN-GB\" FontWeight=\" semibold \" FontStyle=\"oblique\" FontStretch=\"Condensed\" FontSize=\"12pt\" Margin=\"1,2\" Typography.Kerning=\" False \" x:Uid=\"u1\" Foo=\"1\" xmlns:x=\"http://schemas.microsoft.com/winfx/2006/xaml\"><Run/></Paragraph>")))
        let p = d.nodes[1]
        #expect(p.local.language == "en-gb")
        #expect(p.local.fontWeight == 600 && p.local.fontWeightToken == "semibold")
        #expect(p.local.fontStyle == .oblique && p.local.fontStretch == 3)
        #expect(p.local.fontSize == 16)
        #expect(p.local.margin == XamlThickness(left: 1, top: 2, right: 1, bottom: 2))
        #expect(p.local.typography["Typography.Kerning"] == "False")
        #expect(p.rawAttributes.map(\.qualifiedName) == ["xml:lang", "FontWeight", "FontStyle", "FontStretch", "FontSize",
                                                         "Margin", "Typography.Kerning", "x:Uid", "Foo"])
        #expect(p.namespaceDeclarations.map(\.qualifiedName) == ["xmlns:x"])
        #expect(d.issues == [.unknownAttribute("Foo")])
        #expect(d.loadability == .loadable)                                                                    // XD-L10
    }

    @Test func invalidValuesAndMarkupExtensions() throws {
        let d = try #require(Self.parse(Self.wrap("<Paragraph FontSize=\"abc\"><Run Foreground=\"{StaticResource Fg}\" Background=\"{x:Null}\">x</Run></Paragraph>")))
        #expect(d.nodes[1].local.fontSize == nil)
        #expect(d.issues.contains(.invalidValue(property: "FontSize", value: "abc")))                           // XD-L4
        #expect(d.issues.contains(.markupExtension("Foreground")))                                               // XD-L9
        #expect(d.nodes[2].local.background == .null && d.nodes[2].local.foreground == nil)
        #expect(XamlAttributeTable.isInvalid(d.nodes[1].rawAttributes[0], on: .paragraph))
    }

    // MARK: Property elements (CONT-154)

    @Test func brushPropertyElements() throws {
        let d = try #require(Self.parse(Self.wrap("<Paragraph><Run><Run.Foreground><SolidColorBrush Color=\"#FFFF0000\" Opacity=\"0.5\"/></Run.Foreground>a</Run><Run><Run.Background><LinearGradientBrush><GradientStop Color=\"Red\"/></LinearGradientBrush></Run.Background>b</Run><Run><Run.TextDecorations><TextDecorationCollection><TextDecoration Location=\"OverLine\"/><TextDecoration/></TextDecorationCollection></Run.TextDecorations>c</Run></Paragraph>")))
        let runs = d.nodes.filter { $0.kind == .run }
        #expect(runs[0].local.foreground == .solid(argb: 0xFFFF_0000, opacity: 0.5, isScRgb: false))
        #expect(runs[0].text == "a")
        if case .nonSolid(let raw)? = runs[1].local.background { #expect(raw.hasPrefix("<LinearGradientBrush>")) }
        else { Issue.record("expected nonSolid") }
        #expect(runs[2].local.textDecorations == [.overLine, .underline])
        #expect(runs[0].propertyElements.first?.rawXML == "<Run.Foreground><SolidColorBrush Color=\"#FFFF0000\" Opacity=\"0.5\"/></Run.Foreground>")
        #expect(d.loadability == .loadable)
    }

    @Test func duplicatePropertyPrefersThePropertyElement() throws {
        let d = try #require(Self.parse(Self.wrap("<Paragraph><Run Foreground=\"#FF00FF00\"><Run.Foreground><SolidColorBrush Color=\"Red\"/></Run.Foreground>x</Run></Paragraph>")))   // XD-L8
        #expect(d.nodes[2].local.foreground == .solid(argb: 0xFFFF_0000, opacity: 1, isScRgb: false))
        #expect(d.issues.contains(.duplicateProperty("Foreground")))
        if case .notLoadable = d.loadability {} else { Issue.record("expected notLoadable") }
    }

    // MARK: Roots (CONT-155)

    @Test func contentRootGetsAnImplicitWrapper() throws {
        let v6 = "<Paragraph xmlns=\"\(Self.P)\" FontSize=\"16\" TextAlignment=\"Center\"><Run>Hi </Run><Bold>there</Bold></Paragraph>"
        let d = try #require(Self.parse(v6))
        #expect(d.rootRole == .content(.paragraph))
        #expect(d[d.root].isImplicit && d[d.root].kind == .section)
        #expect(d.loadability == .unconfirmed("A Paragraph root is not a Section (XD-Q1)."))                     // XD-L6
        #expect(d.nodes[1].local.fontSize == 16)
        #expect(d.issues.isEmpty)
    }

    @Test func spanAndFlowDocumentRoots() throws {
        let s = try #require(Self.parse("<Span xmlns=\"\(Self.P)\" FontWeight=\"Bold\"><Run>x</Run></Span>"))
        #expect(s.rootRole == .wrapper(.span))
        #expect(Self.kinds(s) == [.span, .paragraph, .run] && s.nodes[1].isImplicit)
        #expect(s.loadability == .loadable)
        let f = try #require(Self.parse("<FlowDocument xmlns=\"\(Self.P)\"><Paragraph/></FlowDocument>"))
        #expect(f.rootRole == .wrapper(.flowDocument))
        if case .unconfirmed = f.loadability {} else { Issue.record("expected unconfirmed") }
    }

    // MARK: Opaque content and source ranges

    @Test func unknownAndUIContainersArePreservedRaw() throws {
        let src = Self.wrap("<Paragraph><InlineUIContainer><Button>x</Button></InlineUIContainer><Foo a=\"1\">y</Foo></Paragraph><BlockUIContainer><Image/></BlockUIContainer>")
        let d = try #require(Self.parse(src))
        let iui = try #require(d.allNodeIDs.first { d[$0].kind == .inlineUIContainer })
        #expect(d.sourceText(of: iui) == "<InlineUIContainer><Button>x</Button></InlineUIContainer>")
        #expect(d[iui].children.isEmpty)
        let foo = try #require(d.allNodeIDs.first { d[$0].kind == .unknown("Foo") })
        #expect(d.sourceText(of: foo) == "<Foo a=\"1\">y</Foo>")
        let bui = try #require(d.allNodeIDs.first { d[$0].kind == .blockUIContainer })
        #expect(d.sourceText(of: bui) == "<BlockUIContainer><Image/></BlockUIContainer>")
        #expect(d.issues == [.unknownElement("Foo")])                                                              // XD-L3
        if case .notLoadable = d.loadability {} else { Issue.record("expected notLoadable") }
    }

    @Test func navigation() throws {
        let d = try #require(Self.parse(Self.wrap("<Paragraph><Span><Hyperlink NavigateUri=\"u\"><Italic><Run>x</Run></Italic></Hyperlink></Span></Paragraph>")))
        let run = try #require(d.allNodeIDs.first { d[$0].kind == .run })
        #expect(d.inlineAncestors(of: run).map { d[$0].kind } == [.italic, .hyperlink, .span])
        #expect(d.ancestors(of: run).map { d[$0].kind } == [.italic, .hyperlink, .span, .paragraph, .section])
        #expect(d.enclosingHyperlink(of: run).map { d[$0].local.navigateUri } == "u")
        #expect(d.enclosingParagraph(of: run).map { d[$0].kind } == .paragraph)
        #expect(d.nearest(.section, from: run) == d.root)
        for (i, n) in d.nodes.enumerated() { if let p = n.parent { #expect(Int(p.index) < i) } }   // pre-order arena
    }

    @Test func surrogatesAndNonBMP() throws {
        let d = try #require(Self.parse(Self.wrap("<Paragraph><Run>😀 &#x1F600;</Run></Paragraph>")))
        #expect(d.nodes[2].text == "😀 😀")
        let r = try #require(d.nodes[2].sourceRange)
        #expect(d.sourceText(of: XamlNodeID(index: 2)) == "<Run>😀 &#x1F600;</Run>")
        #expect(r.count == "<Run>😀 &#x1F600;</Run>".utf16.count)
    }
}

@Suite struct XamlValuesTests {
    @Test func lengths() {
        #expect(XamlValues.parseLength("14", allowAuto: false) == 14)
        #expect(XamlValues.parseLength(" 1in ", allowAuto: false) == 96)
        #expect(XamlValues.parseLength("2.54cm", allowAuto: false).map { abs($0 - 96) < 1e-9 } == true)
        #expect(XamlValues.parseLength("72pt", allowAuto: false) == 96)
        #expect(XamlValues.parseLength("12PX", allowAuto: false) == 12)
        #expect(XamlValues.parseLength("1e1", allowAuto: false) == 10)
        #expect(XamlValues.parseLength(".5", allowAuto: false) == 0.5)
        #expect(XamlValues.parseLength("Auto", allowAuto: true)?.isNaN == true)
        #expect(XamlValues.parseLength("Auto", allowAuto: false) == nil)
        #expect(XamlValues.parseLength("abc", allowAuto: true) == nil)
        #expect(XamlValues.parseFontSize("0") == nil && XamlValues.parseFontSize("40000") == nil)
        #expect(XamlValues.formatLength(14) == "14" && XamlValues.formatLength(14.666666666666666) == "14.666666666666666")
        #expect(XamlValues.formatLength(.nan) == "Auto" && XamlValues.formatLength(0.6) == "0.6")
        #expect(XamlValues.formatLength(1e-5) == "0.00001" && XamlValues.formatLength(1e21) == "1000000000000000000000")
        #expect(XamlValues.formatLength(-24) == "-24")
    }

    @Test func thickness() {
        #expect(XamlValues.parseThickness("5") == XamlThickness(left: 5, top: 5, right: 5, bottom: 5))
        #expect(XamlValues.parseThickness("1 2") == XamlThickness(left: 1, top: 2, right: 1, bottom: 2))
        #expect(XamlValues.parseThickness("1,2,3,4") == XamlThickness(left: 1, top: 2, right: 3, bottom: 4))
        #expect(XamlValues.parseThickness("1,2,3") == nil)
        let auto = XamlValues.parseThickness("24,Auto,Auto,Auto")
        #expect(auto?.left == 24 && auto?.top.isNaN == true)
        #expect(XamlValues.formatThickness(XamlThickness(left: 0.6, top: 0.6, right: 0.6, bottom: 0.6)) == "0.6,0.6,0.6,0.6")
        #expect(XamlValues.formatThickness(auto!) == "24,Auto,Auto,Auto")
    }

    @Test func fontTokens() {
        let w: [(String, Int)] = [("Thin", 100), ("extralight", 200), ("UltraLight", 200), ("Light", 300), ("Normal", 400),
                                  ("Regular", 400), ("Medium", 500), ("DemiBold", 600), ("SemiBold", 600), ("Bold", 700),
                                  ("ExtraBold", 800), ("UltraBold", 800), ("Black", 900), ("Heavy", 900),
                                  ("ExtraBlack", 950), ("UltraBlack", 950), ("650", 650)]
        for (t, v) in w { #expect(XamlValues.parseFontWeight(t) == v, "\(t)") }
        #expect(XamlValues.parseFontWeight("0") == nil && XamlValues.parseFontWeight("1000") == nil)
        #expect(XamlValues.fontWeightToken(600) == "SemiBold" && XamlValues.fontWeightToken(650) == "650")
        #expect(XamlValues.parseFontStretch("Medium") == 5 && XamlValues.parseFontStretch("9") == 9)
        #expect(XamlValues.fontStretchToken(5) == "Normal" && XamlValues.fontStretchToken(3) == "Condensed")
        #expect(XamlValues.parseFontStyle("ITALIC") == .italic && XamlValues.parseFontStyle("x") == nil)
    }

    @Test func brushes() {
        #expect(XamlValues.parseBrush("#FFE699") == .solid(argb: 0xFFFF_E699, opacity: 1, isScRgb: false))
        #expect(XamlValues.parseBrush("#80FFE699") == .solid(argb: 0x80FF_E699, opacity: 1, isScRgb: false))
        #expect(XamlValues.parseBrush("#F00") == .solid(argb: 0xFFFF_0000, opacity: 1, isScRgb: false))
        #expect(XamlValues.parseBrush("#8F00") == .solid(argb: 0x88FF_0000, opacity: 1, isScRgb: false))
        #expect(XamlValues.parseBrush("red") == .solid(argb: 0xFFFF_0000, opacity: 1, isScRgb: false))
        #expect(XamlValues.parseBrush("Transparent") == .solid(argb: 0x00FF_FFFF, opacity: 1, isScRgb: false))
        if case .solid(_, _, true)? = XamlValues.parseBrush("sc#1,1,0,0") {} else { Issue.record("scRGB flag") }
        #expect(XamlValues.parseBrush("{x:Null}") == .null && XamlValues.parseBrush("{Binding}") == nil)
        #expect(XamlValues.parseBrush("lightgrey") == nil)
        #expect(XamlValues.isSentinel(.solid(argb: 0xFFFF_E699, opacity: 0.3, isScRgb: false)))
        #expect(!XamlValues.isSentinel(.solid(argb: 0x80FF_E699, opacity: 1, isScRgb: false)))
        #expect(!XamlValues.isSentinel(.solid(argb: 0xFFFF_E699, opacity: 1, isScRgb: true)))
    }

    @Test func decorations() {
        #expect(XamlValues.parseDecorations("None") == [])
        #expect(XamlValues.parseDecorations("underline, Strikethrough") == [.underline, .strikethrough])
        #expect(XamlValues.parseDecorations("Baseline,OverLine") == [.baseline, .overLine])
        #expect(XamlValues.parseDecorations("Wavy") == nil)
        #expect(XamlValues.formatDecorations([.strikethrough, .underline, .baseline, .overLine])
                == "Underline,Strikethrough,OverLine,Baseline")
        #expect(XamlValues.formatDecorations([]) == "None")
    }

    // XD.6.3 same() vectors.
    @Test func sameVectors() {
        var s = XamlComputedStyle(context: .containerEditor)
        func same(_ n: String, _ a: String, _ b: String) -> Bool {
            var st = s
            XamlInheritable.apply(n, b, to: &st)
            return XamlInheritable.same(n, a, st)
        }
        #expect(same("FontWeight", "Bold", "700"))                       // E1
        #expect(same("FontWeight", "Regular", "Normal"))                 // E2
        #expect(same("FontWeight", "SemiBold", "DemiBold"))              // E3
        #expect(!same("FontWeight", "Medium", "Normal"))                 // E4
        #expect(same("FontSize", "12pt", "16"))                          // E5
        #expect(same("FontSize", "16px", "16"))                          // E6
        #expect(same("FontSize", "14.666666666666666", "14.6666666666667"))   // E7
        #expect(!same("FontSize", "14", "14.00001"))                     // E8
        #expect(same("FontFamily", "Segoe UI, Arial", "segoe ui,Arial")) // E9
        #expect(!same("FontFamily", "Consolas", "Consolas, Courier New"))// E10
        #expect(same("Foreground", "Red", "#FFFF0000") && same("Foreground", "Red", "#F00"))   // E11
        #expect(!same("Foreground", "#80FF0000", "#FFFF0000"))           // E12
        #expect(same("Foreground", "Transparent", "#00FFFFFF"))          // E13
        #expect(!same("Foreground", "#00000000", "Transparent"))         // E14
        s.foreground = .linkDefault
        #expect(!XamlInheritable.same("Foreground", "#FF0066CC", s))     // E15
        s = XamlComputedStyle(context: .containerEditor)
        #expect(same("LineHeight", "Auto", "NaN"))                       // E16
        #expect(!same("LineHeight", "Auto", "20"))                       // E17
        #expect(same("xml:lang", "en-US", "en-us"))                      // E18
        #expect(same("Typography.Kerning", "True", "true"))              // E19
        #expect(!same("FontStyle", "Oblique", "Italic"))                 // E20
    }
}
