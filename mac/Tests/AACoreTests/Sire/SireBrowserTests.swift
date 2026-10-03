// Tests: 12 §7.9 (filters over the §7.10 synthetic bank), SIRE-005…013 (search fields, sorts, reset, stats),
//        §7.8 TV-ST-1…5 (SireState operations and JSON round trip).
import Foundation
import Testing
@testable import AACore

@Suite struct SireBrowserTests {
    let browser = SireBrowser(SireSynthetic.contents)
    let session = SireExportFixture.session

    func numbers(_ c: SireFilterCriteria) -> [String] { browser.apply(c, session: session).map(\.questionNumber) }

    // TV: 12 §7.9
    @Test func vesselFilterKeepsQuestionsWithoutTypes() {
        let unchecked = Set(["LNG", "LPG", "Oil"].map(SireFilterCriteria.vesselKey))
        #expect(numbers(SireFilterCriteria(uncheckedVessels: unchecked)) == ["1.1.1", "2.1.2"])
        #expect(numbers(SireFilterCriteria(uncheckedVessels: [SireFilterCriteria.vesselKey("chemical")])) == ["1.1.1", "2.1.10"])
    }

    @Test func statusFilters() {
        #expect(numbers(SireFilterCriteria(status: .hasTasks)) == ["2.1.2", "2.1.10"])
        #expect(numbers(SireFilterCriteria(status: .noStatus)) == ["2.1.2"])
        #expect(numbers(SireFilterCriteria(status: .bookmarked)) == ["2.1.2"])
        #expect(numbers(SireFilterCriteria(status: .forExport)) == ["2.1.10"])
        #expect(numbers(SireFilterCriteria(status: .checked)) == ["2.1.10"])
        #expect(numbers(SireFilterCriteria(status: .inProgress)) == ["1.1.1"])
        #expect(numbers(SireFilterCriteria(status: .notApplicable)) == [])
    }

    @Test func search() {
        #expect(numbers(SireFilterCriteria(search: "ALPHA")) == ["2.1.2"])
        #expect(numbers(SireFilterCriteria(search: "1.1")) == ["1.1.1", "2.1.10"])
        #expect(numbers(SireFilterCriteria(search: "  obj b  ")) == ["2.1.10"])
        #expect(numbers(SireFilterCriteria(search: "Documentation")) == ["2.1.10"])          // ROVIQ is searched
        #expect(numbers(SireFilterCriteria(search: "Certs")) == [])                          // chapter name is not
        #expect(numbers(SireFilterCriteria(search: "Chemical")) == [])                       // vessel types are not
        #expect(numbers(SireFilterCriteria(search: "   ")).count == 3)
    }

    @Test func sorts() {
        #expect(numbers(SireFilterCriteria(sort: .shortQuestionText)) == ["1.1.1", "2.1.2", "2.1.10"])
        #expect(numbers(SireFilterCriteria(sort: .questionNumber)) == ["1.1.1", "2.1.2", "2.1.10"])
        #expect(numbers(SireFilterCriteria(sort: .vesselTypes)) == ["1.1.1", "2.1.2", "2.1.10"])   // All < Chemical < Oil, LNG
        #expect(numbers(SireFilterCriteria(sort: .roviqSequence)) == ["1.1.1", "2.1.10", "2.1.2"])  // "" < Bridge < Main Deck
        #expect(numbers(SireFilterCriteria(sort: .questionType)) == ["1.1.1", "2.1.2", "2.1.10"])
        #expect(numbers(SireFilterCriteria(sort: .chapter)) == ["1.1.1", "2.1.2", "2.1.10"])
    }

    @Test func boxFilters() {
        #expect(numbers(SireFilterCriteria(uncheckedChapters: ["2"])) == ["1.1.1"])
        #expect(numbers(SireFilterCriteria(uncheckedChapters: ["1", "2"])) == [])
        #expect(numbers(SireFilterCriteria(uncheckedTypes: ["Inspection"])) == ["1.1.1"])
        #expect(browser.chapterOptions.map(\.label) == ["Ch 1: Particulars (1)", "Ch 2: Certs (2)"])
        #expect(browser.vesselOptions.map(\.label) == ["Chemical", "LNG", "Oil"])
        #expect(browser.typeOptions.map(\.label) == ["Data Field", "Inspection"])
        #expect(SireFilterCriteria.reset == SireFilterCriteria())
    }

    @Test func evidenceFilterUsesTagPrefix() {
        var q = SireSynthetic.q212
        q.evidenceTags = ["Equipment: fire pump"]
        let b = SireBrowser(SireBankContents(questions: [q, SireSynthetic.q2110]))
        #expect(b.apply(SireFilterCriteria(evidence: "Equipment"), session: SireSessionSnapshot()).map(\.questionNumber) == ["2.1.2"])
        #expect(b.apply(SireFilterCriteria(evidence: "Record"), session: SireSessionSnapshot()).isEmpty)
    }

    @Test func stats() {
        #expect(browser.statsText(session: session) == "3 questions · 3 auto-identified tasks\nSession — ✓ 1  ⧗ 1  N/A 0  ★ 1  tasks 3")
    }
}

@MainActor @Suite struct SireStateTests {
    // TV: 12 TV-ST-1
    @Test func setStatus() {
        let s = SireState()
        s.setStatus(.checked, for: "1.1.1")
        #expect(s.questionStatuses["1.1.1"] == "Checked")
        s.setStatus(.none, for: "1.1.1")
        #expect(!s.questionStatuses.containsKey("1.1.1"))
    }

    // TV: 12 TV-ST-2
    @Test func getStatusParsing() {
        let s = SireState()
        s.questionStatuses["a"] = "InProgress"; s.questionStatuses["b"] = "inprogress"
        s.questionStatuses["c"] = "2"; s.questionStatuses["d"] = "bogus"
        #expect(s.status(for: "a") == .inProgress && s.status(for: "b") == .none)
        #expect(s.status(for: "c") == .checked && s.status(for: "d") == .none && s.status(for: "zz") == .none)
        #expect(s.questionStatuses["d"] == "bogus")                    // raw value kept until set
    }

    // TV: 12 TV-ST-3
    @Test func toggles() {
        let s = SireState()
        s.bookmarks = ["a", "b", "a"]
        s.toggleBookmark("a")
        #expect(s.bookmarks == ["b", "a"] && s.isBookmarked("a"))
        let t = SireState()
        t.toggleForExport("x"); t.toggleForExport("x")
        #expect(t.forExport.isEmpty)
    }

    // TV: 12 TV-ST-4 / TV-ST-5
    @Test func jsonRoundTrip() throws {
        let sample = #"{"QuestionStatuses":{"2.1.10":"Checked","1.1.1":"InProgress"},"Bookmarks":["2.1.2"],"ForExport":["2.1.10"],"Tasks":[{"Id":"0f8fad5b-d9cb-469f-a165-70867728950e","QuestionNumber":"2.1.10","Text":"Check log","IsCompleted":true,"CreatedAt":"2026-09-30T10:00:00.1234567+02:00"},{"Id":"0f8fad5b-d9cb-469f-a165-70867728950f","QuestionNumber":"2.1.2","Text":"Z","IsCompleted":false,"CreatedAt":"2026-09-30T08:00:00Z"},{"Id":"0f8fad5b-d9cb-469f-a165-708677289510","QuestionNumber":"2.1.2","Text":"Y","IsCompleted":false,"CreatedAt":"2026-09-30T10:00:00"},{"Id":"0f8fad5b-d9cb-469f-a165-708677289511","QuestionNumber":"2.1.2","Text":"X","IsCompleted":false,"CreatedAt":"2026-09-30T10:00:00+02:00"}],"QuestionBodies":{"2.1.10":"\u003CSection xmlns=\u0022http://schemas.microsoft.com/winfx/2006/xaml/presentation\u0022\u003E\u003CParagraph\u003E\u003CRun\u003Ex\u003C/Run\u003E\u003C/Paragraph\u003E\u003C/Section\u003E"}}"#
        guard case .object(let o) = try JSONParser.parse(sample) else { Issue.record("object"); return }
        let ctx = JSONDecodeContext()
        let s = try SireState(json: o, context: ctx)
        #expect(s.tasks.count == 4 && s.questionBodies.count == 1 && s.bookmarks == ["2.1.2"])
        #expect(s.questionBodies["2.1.10"]?.hasPrefix("<Section xmlns=\"http://") == true)
        let out = try JSONWriter.string(.object(s.toJSON()))
        #expect(out == sample)
        let empty = try SireState(json: JSONObject(), context: ctx)
        #expect(try JSONWriter.string(.object(empty.toJSON()))
                == #"{"QuestionStatuses":{},"Bookmarks":[],"ForExport":[],"Tasks":[],"QuestionBodies":{}}"#)
        guard case .object(let noBodies) = try JSONParser.parse(#"{"QuestionStatuses":{},"Tasks":[]}"#) else { return }
        #expect(try SireState(json: noBodies, context: ctx).questionBodies.isEmpty)
    }
}
