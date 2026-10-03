// Tests (post-merge, gated on W-RICH — ARCHITECTURE.md §10.5; OWNERSHIP W-SIRE post-merge acceptance): 12 SIRE-023
//        body persistence round trip through the W-RICH reader/writer with the `.sirePane` context, §4.4 (quick-add
//        container bodies load in the container editor), SIRE-022 (an insertion survives the round trip).
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
