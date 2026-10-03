// Tests (post-merge, gated on W-RICH — ARCHITECTURE.md §10.5; OWNERSHIP W-SIRE post-merge acceptance): 12 SIRE-023
//        body persistence round trip through the W-RICH reader/writer with the `.sirePane` context, §4.4 (quick-add
//        container bodies load in the container editor), SIRE-022 (an insertion survives the round trip), §4.4 stored
//        shape of a pane body written on the Mac (root Foreground pane #FF000000 vs container #FF334155, FontFamily
//        Segoe UI, chip / section-label Paragraph Background + Padding, Disc List with a nested Circle List inside the
//        ListItem, an intra-Run LF kept inside one Run — U+2028 written back as LF).
import AppKit
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct SireRichTextIntegrationTests {
    @Test(.enabled(if: ContractStatus.isImplemented(.wRich)))
    func paneBodyRoundTrip() throws {
        let q = SireTestBank.q("2.1.1")
        let original = SireFlowXaml.write(SireFlow.buildQuestion(q, body: SireFlow.black))
        guard case .document(let text, let meta) = XamlReader.read(original, context: .sirePane) else {
            Issue.record("the generated pane document must be readable"); return
        }
        #expect(!meta.isPlaceholderResult)
        #expect(text.string.contains("Q 2.1.1") && text.string.contains(q.shortQuestionText))
        let v = SireInsertionTextView(textKit1Frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        v.sireLoad(text)
        let at = (v.string as NSString).range(of: q.shortQuestionText).location
        v.setSelectedRange(NSRange(location: at, length: 4))
        v.insertText("NOTE ", replacementRange: NSRange(location: NSNotFound, length: 0))
        let storage = try #require(v.textStorage)
        let xaml = XamlWriter.write(storage, metadata: meta, context: .sirePane)
        #expect(xaml.hasPrefix("<Section") && xaml.contains("Segoe UI") && xaml.contains("NOTE "))
        guard case .document(let back, _) = XamlReader.read(xaml, context: .sirePane) else {
            Issue.record("the stored body must read back"); return
        }
        #expect(back.string.contains("NOTE " + q.shortQuestionText))
        #expect(back.string.contains("SUGGESTED INSPECTOR ACTIONS"))
    }

    // MARK: §4.4 stored shape (what Windows reloads from `QuestionBodies` / container bodies written on the Mac)

    /// Every descendant element named `name` (document order).
    private static func elements(_ node: XMLNode, _ name: String) -> [XMLElement] {
        var out: [XMLElement] = []
        for child in node.children ?? [] {
            if let e = child as? XMLElement {
                if e.localName == name { out.append(e) }
                out += elements(e, name)
            }
        }
        return out
    }

    private static func attr(_ e: XMLElement, _ name: String) -> String? { e.attribute(forName: name)?.stringValue }

    /// An inheritable attribute resolved the way WPF does (§4.4: a value equal to the inherited one may be omitted).
    private static func effective(_ e: XMLElement, _ name: String) -> String? {
        var node: XMLNode? = e
        while let el = node as? XMLElement {
            if let v = attr(el, name) { return v }
            node = el.parent
        }
        return nil
    }

    /// The concatenated Run text of a Paragraph.
    private static func runText(_ p: XMLElement) -> String { elements(p, "Run").map { $0.stringValue ?? "" }.joined() }

    private static func parse(_ xaml: String) throws -> XMLElement {
        let doc = try XMLDocument(xmlString: xaml, options: [.nodePreserveWhitespace])
        return try #require(doc.rootElement())
    }

    /// A bank question whose suggested inspector actions carry a bullet with a sub-bullet (§3.6 → a Disc List with a
    /// nested Circle List inside the ListItem). The bank itself has no "    o " sub-bullets, so the text is synthetic.
    private static func nestedListQuestion() -> SireQuestion {
        var q = SireTestBank.q("2.1.1")
        q.suggestedInspectorActions = "Prior to boarding:\n• Review the CSSR.\n    o Copy the details.\n• Verify the dates."
        return q
    }

    /// Asserts the §4.4 inventory on a written body (`rootForeground` = pane black or container slate).
    private static func expectShape(_ xaml: String, q: SireQuestion, rootForeground: String) throws {
        let root = try parse(xaml)
        #expect(root.localName == "Section")
        #expect(attr(root, "Foreground") == rootForeground)
        #expect(attr(root, "FontFamily") == "Segoe UI")
        #expect(attr(root, "FontSize") == "13")
        #expect(attr(root, "xml:space") == "preserve")
        #expect(!xaml.contains("\u{2028}"), "U+2028 must be written back as LF")
        let paras = elements(root, "Paragraph")
        // The full-question chip: Background + Padding, its LF-bearing text inside ONE Run (not split into paragraphs).
        let chip = try #require(paras.first { attr($0, "Background") == "#FFF8FAFC" })
        #expect(attr(chip, "Padding") == "10,8,10,8")
        #expect(attr(chip, "Margin") == "0,2,0,8")
        let chipRuns = elements(chip, "Run")
        #expect(chipRuns.count == 1)
        #expect(chipRuns.first?.stringValue == q.fullQuestionText)
        #expect(q.fullQuestionText.contains("\n"))
        #expect(chipRuns.first.flatMap { effective($0, "Foreground") } == "#FF334155")
        // The SUGGESTED INSPECTOR ACTIONS section label: amber chip with its Padding and Run colour.
        let label = try #require(paras.first { runText($0) == "SUGGESTED INSPECTOR ACTIONS" })
        #expect(attr(label, "Background") == "#FFFEF3C7")
        #expect(attr(label, "Padding") == "8,4,8,4")
        #expect(attr(label, "Margin") == "0,10,0,4")
        #expect(attr(label, "FontSize") == "12")
        #expect(elements(label, "Run").first.flatMap { effective($0, "Foreground") } == "#FF92400E")
        // A grey section label keeps its own background.
        let pubs = try #require(paras.first { runText($0) == "PUBLICATIONS" })
        #expect(attr(pubs, "Background") == "#FFF1F5F9" && attr(pubs, "Padding") == "8,4,8,4")
        // The heading lines.
        let heading = try #require(paras.first { runText($0) == "Q 2.1.1" })
        #expect(attr(heading, "FontSize") == "20")
        #expect(elements(heading, "Run").first.flatMap { effective($0, "Foreground") } == "#FF1E40AF")
        // Disc List → ListItem → (Paragraph, nested Circle List).
        let lists = elements(root, "List")
        let disc = try #require(lists.first { attr($0, "MarkerStyle") == "Disc" && runText($0).contains("Review the CSSR.") })
        let firstItem = try #require(disc.elements(forName: "ListItem").first)
        let nested = try #require(firstItem.elements(forName: "List").first)
        #expect(attr(nested, "MarkerStyle") == "Circle")
        let nestedItems = nested.elements(forName: "ListItem")
        #expect(nestedItems.count == 1)
        #expect(nestedItems.first.map { runText($0) } == "Copy the details.")
        #expect(disc.elements(forName: "ListItem").count == 2)
        #expect(firstItem.elements(forName: "Paragraph").first.flatMap { attr($0, "Margin") } == "0,1,0,1")
    }

    @Test(.enabled(if: ContractStatus.isImplemented(.wRich)))
    func paneBodyStoredShape() throws {
        let q = Self.nestedListQuestion()
        let original = SireFlowXaml.write(SireFlow.buildQuestion(q, body: SireFlow.black))
        try Self.expectShape(original, q: q, rootForeground: "#FF000000")          // the generator itself
        guard case .document(let text, let meta) = XamlReader.read(original, context: .sirePane) else {
            Issue.record("the generated pane document must be readable"); return
        }
        // An insertion (SIRE-022) then the W-RICH writer with the pane context.
        let v = SireInsertionTextView(textKit1Frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        v.sireLoad(text)
        #expect(v.string.contains("\u{2028}") || !v.string.contains("\n\n"), "intra-Run LF loads as a line separator")
        // Right after the list item's `\t•\t` marker: the typed text must not inherit `.aaListMarker` (which the
        // writer drops — the insertion would silently vanish from the stored body).
        let at = (v.string as NSString).range(of: "Verify the dates.").location
        v.setSelectedRange(NSRange(location: at, length: 0))
        v.insertText("NOTE ", replacementRange: NSRange(location: NSNotFound, length: 0))
        let storage = try #require(v.textStorage)
        let xaml = XamlWriter.write(storage, metadata: meta, context: .sirePane)
        try Self.expectShape(xaml, q: q, rootForeground: "#FF000000")
        let runs = Self.elements(try Self.parse(xaml), "Run").map { $0.stringValue ?? "" }
        #expect(runs.joined().contains("NOTE Verify the dates."), "\(runs.filter { $0.contains("NOTE") || $0.contains("Verify the dates") })")
        // And it reads back to the same shape again (a second Mac save is stable).
        guard case .document(let back, let meta2) = XamlReader.read(xaml, context: .sirePane) else {
            Issue.record("the stored body must read back"); return
        }
        try Self.expectShape(XamlWriter.write(back, metadata: meta2, context: .sirePane), q: q, rootForeground: "#FF000000")
    }

    @Test(.enabled(if: ContractStatus.isImplemented(.wRich)))
    func containerBodyStoredShape() throws {
        let q = Self.nestedListQuestion()
        let original = SireFlowXaml.questionXaml(q)
        try Self.expectShape(original, q: q, rootForeground: "#FF334155")
        guard case .document(let text, let meta) = XamlReader.read(original, context: .containerEditor) else {
            Issue.record("the quick-add body must load in the container editor"); return
        }
        try Self.expectShape(XamlWriter.write(text, metadata: meta, context: .containerEditor), q: q,
                             rootForeground: "#FF334155")
    }

    @Test(.enabled(if: ContractStatus.isImplemented(.wRich)))
    func quickAddBodiesLoadInTheContainerEditor() {
        for n in ["1.1.1", "2.1.1", "11.1.2"] {
            let q = SireTestBank.q(n)
            guard case .document(let text, let meta) = XamlReader.read(SireFlowXaml.questionXaml(q), context: .containerEditor) else {
                Issue.record("\(n) must load"); continue
            }
            #expect(text.string.contains("Q \(n)"), "\(n)")
            if case .notLoadable = meta.loadability { Issue.record("\(n) reported not loadable") }
        }
        let ov = SireFlowXaml.overviewXaml(title: "SIRE Section 7.1", questions: SireTestBank.contents.inSection("7.1"))
        guard case .document(let text, _) = XamlReader.read(ov, context: .containerViewer) else {
            Issue.record("the overview must load"); return
        }
        #expect(text.string.contains("SIRE Section 7.1"))
    }
}
