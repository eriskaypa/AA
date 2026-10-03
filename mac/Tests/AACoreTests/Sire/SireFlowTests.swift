// Tests: 12 §7.6 (TV-FLOW-1…4, TV-FLOW-Q), §4.4 / 05 S-1, S-8 (Section XAML shape of quick-add bodies), §6.5
//        (display renderer: U+2028 inside one paragraph, chip backgrounds as NSTextBlock, disc/circle lists).
import AppKit
import Foundation
import Testing
@testable import AACore

private func P(_ runs: String...) -> SireFlowBlock {
    .paragraph(SireFlowParagraph(runs: runs.map { SireFlowRun($0) }, margin: SireThickness(0, 0, 0, 6)))
}
private func item(_ t: String, _ nested: SireFlowList? = nil) -> SireFlowListItem {
    SireFlowListItem(paragraph: SireFlowParagraph(runs: [SireFlowRun(t)], margin: SireThickness(0, 1, 0, 1)), nested: nested)
}

/// The §7.10 synthetic bank (also used by the export, filter and quick-add suites).
enum SireSynthetic {
    static let q111 = SireQuestion(questionNumber: "1.1.1", chapter: "1", section: "1.1", chapterName: "Particulars",
                                   type: "data_field", fullQuestionText: "Name of the vessel")
    static let q212 = SireQuestion(questionNumber: "2.1.2", chapter: "2", section: "2.1", chapterName: "Certs",
                                   type: "inspection_question", fullQuestionText: "Is alpha ok?", shortQuestionText: "Alpha check",
                                   vesselTypes: ["Chemical"], roviqSequence: "Main Deck", objective: "Obj A",
                                   roviqLocations: ["Main Deck"])
    static let q2110 = SireQuestion(questionNumber: "2.1.10", chapter: "2", section: "2.1", chapterName: "Certs",
                                    type: "inspection_question", fullQuestionText: "Is beta ok?", shortQuestionText: "Beta check",
                                    vesselTypes: ["Oil", "LNG"], roviqSequence: "Bridge, Documentation", objective: "Obj B",
                                    expectedEvidence: "Ev B", potentialNegativeObservationGrounds: "Neg B",
                                    roviqLocations: ["Bridge", "Documentation"])
    static let questions = [q111, q212, q2110]
    static let identified = SireIdentifiedTasks([("2.1.2", ["Verify Y", "Verify Z"]), ("2.1.10", ["Verify X"])])
    static var contents: SireBankContents { SireBankContents(questions: questions, identified: identified) }
}

@Suite struct SireFlowTests {
    // TV: 12 TV-FLOW-1
    @Test func bulletsListsAndParagraphs() {
        let text = "Intro line one\nintro line two\n\n• First bullet\n    o nested a\n\to nested b\n• Second bullet wraps\ncontinuation text\n- dash item\n– en dash item\n· middle dot item\n○ circle sub\n\u{F0A7} wingding line\no letter-o line"
        let blocks = SireFlow.parseBlocks(text)
        #expect(blocks == [
            P("Intro line one", " ", "intro line two"),
            .list(SireFlowList(marker: .disc, items: [
                item("First bullet", SireFlowList(marker: .circle, items: [item("nested a"), item("nested b")])),
                item("Second bullet wraps")])),
            P("continuation text"),
            .list(SireFlowList(marker: .disc, items: [
                item("dash item"), item("en dash item"),
                item("middle dot item", SireFlowList(marker: .circle, items: [item("circle sub")]))])),
            P("\u{F0A7} wingding line", " ", "o letter-o line"),
        ])
    }

    // TV: 12 TV-FLOW-2
    @Test func singleCharacterBulletsAreText() {
        #expect(SireFlow.parseBlocks("•\n• \n•x\n-x\n- \nplain") == [
            P("•", " ", "•"),
            .list(SireFlowList(marker: .disc, items: [item("x")])),
            P("-x", " ", "-", " ", "plain"),
        ])
    }

    // TV: 12 TV-FLOW-3
    @Test func blankBodyIsOmitted() {
        #expect(SireFlow.parseBlocks("   \n\n").isEmpty)
        var b: [SireFlowBlock] = []
        SireFlow.addSection(&b, "OBJECTIVE", "   \n\n", SireFlow.defaultScheme)
        #expect(b.isEmpty)
    }

    // TV: 12 TV-FLOW-4
    @Test func pdfWrappedBulletIsSplit() {
        #expect(SireFlow.parseBlocks("• First half of a long\nsecond half.\n• Next") == [
            .list(SireFlowList(marker: .disc, items: [item("First half of a long")])),
            P("second half."),
            .list(SireFlowList(marker: .disc, items: [item("Next")])),
        ])
        #expect(SireFlow.parseBlocks("a\r\nb\rc") == [P("a", " ", "b", " ", "c")])
    }

    // TV: 12 TV-FLOW-Q
    @Test func buildQuestion() {
        let pane = SireFlow.buildQuestion(SireSynthetic.q2110, body: SireFlow.black)
        #expect(pane.foreground == SireFlow.black)
        #expect(SireFlow.buildQuestion(SireSynthetic.q2110).foreground == SireFlow.slate)
        let b = pane.blocks
        #expect(b[0] == .paragraph(SireFlowParagraph(runs: [SireFlowRun("Q 2.1.10", foreground: ARGB(r: 0x1E, g: 0x40, b: 0xAF))],
                                                     fontSize: 20, margin: SireThickness(0, 0, 0, 4))))
        #expect(b[1] == .paragraph(SireFlowParagraph(runs: [SireFlowRun("Ch 2: Certs   ·   Section 2.1   ·   Inspection",
                                                                         foreground: ARGB(r: 0x64, g: 0x74, b: 0x8B))],
                                                     fontSize: 11, italic: true, margin: SireThickness(0, 0, 0, 6))))
        #expect(b[2] == .paragraph(SireFlowParagraph(runs: [SireFlowRun("Beta check", foreground: SireFlow.slate)], fontSize: 15,
                                                     margin: SireThickness(0, 0, 0, 4))))
        #expect(b[3] == .paragraph(SireFlowParagraph(runs: [SireFlowRun("Is beta ok?", foreground: SireFlow.slate)],
                                                     margin: SireThickness(0, 2, 0, 8), padding: SireThickness(10, 8, 10, 8),
                                                     background: SireFlow.chipBg)))
        #expect(b[4] == .paragraph(SireFlowParagraph(runs: [SireFlowRun("Vessel: Oil, LNG      ROVIQ: Bridge, Documentation",
                                                                         foreground: SireFlow.primary)],
                                                     fontSize: 11, margin: SireThickness(0, 0, 0, 6))))
        #expect(b[5] == .paragraph(SireFlowParagraph(runs: [SireFlowRun("OBJECTIVE", foreground: ARGB(r: 0x47, g: 0x55, b: 0x69))],
                                                     fontSize: 12, margin: SireThickness(0, 10, 0, 4),
                                                     padding: SireThickness(8, 4, 8, 4), background: ARGB(r: 0xF1, g: 0xF5, b: 0xF9))))
        #expect(b[6] == P("Obj B"))
        // EVIDENCE / NEG sections follow for 2.1.10; no smart-tags line (no tags).
        #expect(b.count == 11)
        if case .paragraph(let last) = b[10] { #expect(last.text == "Neg B") } else { Issue.record("last block") }
    }

    @Test func dataFieldHasNoShortHeadingAndNoRoviq() {
        let b = SireFlow.buildQuestion(SireSynthetic.q111).blocks
        if case .paragraph(let meta) = b[3] { #expect(meta.text == "Vessel: All") } else { Issue.record("meta") }
        #expect(b.count == 4)
    }

    @Test func overview() {
        let doc = SireFlow.buildOverview(title: "SIRE Section 2.1", questions: [SireSynthetic.q212, SireSynthetic.q2110])
        #expect(doc.blocks.count == 3)
        if case .paragraph(let sub) = doc.blocks[1] {
            #expect(sub.text == "2 SIRE 2.0 question(s). Imported from the SIRE 2.0 Knowledge Bank." && sub.italic)
        }
        #expect(doc.blocks[2] == .list(SireFlowList(marker: .disc, margin: SireThickness(0, 4, 0, 0), items: [
            item("Q 2.1.2 — Alpha check"), item("Q 2.1.10 — Beta check")])))
    }

    // TV: 12 §4.4 / 05 S-8 — the container XAML shape.
    @Test func containerXamlShape() {
        var q = SireSynthetic.q2110
        q.suggestedInspectorActions = "• Check A & B < C\n    o sub item\nwrapped"
        q.fullQuestionText = "Line one\nline two"
        let x = SireFlowXaml.questionXaml(q)
        #expect(x.hasPrefix(##"<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xml:space="preserve" TextAlignment="Left" LineHeight="Auto" IsHyphenationEnabled="False" xml:lang="en-us" FlowDirection="LeftToRight" NumberSubstitution.CultureSource="User" NumberSubstitution.Substitution="AsCulture" FontFamily="Segoe UI" FontStyle="Normal" FontWeight="Normal" FontStretch="Normal" FontSize="13" Foreground="#FF334155" Typography.StandardLigatures="True""##))
        #expect(x.contains(#"Typography.StylisticSet20="False""#) && x.contains(#"Typography.StylisticAlternates="0">"#))
        #expect(x.contains(##"<Paragraph FontSize="20" Margin="0,0,0,4"><Run Foreground="#FF1E40AF">Q 2.1.10</Run></Paragraph>"##))
        #expect(x.contains(##"<Paragraph FontStyle="Italic" FontSize="11" Margin="0,0,0,6"><Run Foreground="#FF64748B">Ch 2: Certs   ·   Section 2.1   ·   Inspection</Run></Paragraph>"##))
        #expect(x.contains("<Paragraph Margin=\"0,2,0,8\" Padding=\"10,8,10,8\" Background=\"#FFF8FAFC\"><Run Foreground=\"#FF334155\">Line one\nline two</Run></Paragraph>"))
        #expect(x.contains(##"<Paragraph FontSize="12" Margin="0,10,0,4" Padding="8,4,8,4" Background="#FFFEF3C7"><Run Foreground="#FF92400E">SUGGESTED INSPECTOR ACTIONS</Run></Paragraph>"##))
        #expect(x.contains(#"<List MarkerStyle="Disc"><ListItem><Paragraph Margin="0,1,0,1"><Run>Check A &amp; B &lt; C</Run></Paragraph><List MarkerStyle="Circle"><ListItem><Paragraph Margin="0,1,0,1"><Run>sub item</Run></Paragraph></ListItem></List></ListItem></List><Paragraph Margin="0,0,0,6"><Run>wrapped</Run></Paragraph>"#))
        #expect(x.hasSuffix("</Section>"))
        #expect(!x.contains("> <") && !x.contains(">\n<"))
        // Pane variant: black root, byte-stable.
        let pane = SireFlowXaml.write(SireFlow.buildQuestion(q, body: SireFlow.black))
        #expect(pane.contains(##"Foreground="#FF000000""##))
        #expect(pane == SireFlowXaml.write(SireFlow.buildQuestion(q, body: SireFlow.black)))
        let ov = SireFlowXaml.overviewXaml(title: "SIRE Ch2 — Certs", questions: [SireSynthetic.q212])
        #expect(ov.contains(#"<List MarkerStyle="Disc" Margin="0,4,0,0"><ListItem><Paragraph Margin="0,1,0,1"><Run>Q 2.1.2 — Alpha check</Run></Paragraph></ListItem></List>"#))
        #expect(ov.contains(##"<Paragraph FontSize="18" Margin="0,0,0,4"><Run Foreground="#FF1E40AF">SIRE Ch2 — Certs</Run></Paragraph>"##))
    }

    @MainActor @Test func displayRenderer() {
        var q = SireSynthetic.q2110
        q.fullQuestionText = "Line one\nline two"
        q.suggestedInspectorActions = "• Parent\n    o child"
        let s = SireFlowRenderer.render(SireFlow.buildQuestion(q, body: SireFlow.black))
        let text = s.string
        #expect(text.hasPrefix("Q 2.1.10\nCh 2: Certs"))
        #expect(text.contains("Line one\u{2028}line two"))
        #expect(!text.contains("Line one\nline two"))
        #expect(text.contains("\t•\tParent") && text.contains("\t◦\tchild"))
        let chipLoc = (text as NSString).range(of: "Line one").location
        let style = s.attribute(.paragraphStyle, at: chipLoc, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.textBlocks.first?.backgroundColor != nil)
        let childLoc = (text as NSString).range(of: "child").location
        let childStyle = s.attribute(.paragraphStyle, at: childLoc, effectiveRange: nil) as? NSParagraphStyle
        #expect(childStyle?.textLists.count == 2)
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == 20)
        #expect(font.map { !$0.fontDescriptor.symbolicTraits.contains(.bold) } == true)
        let metaLoc = (text as NSString).range(of: "Ch 2").location
        let metaFont = s.attribute(.font, at: metaLoc, effectiveRange: nil) as? NSFont
        #expect(metaFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }
}
