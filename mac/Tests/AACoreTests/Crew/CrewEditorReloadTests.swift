// Tests for the crew editor's Save after a reload (09 CREW-074, DECISIONS 06 R1 "never orphan edits"): rows the user
// did not touch keep values that arrived while the editor was open; edited rows win; without a reload Save behaves
// exactly as the Windows apply-all (trimming / date normalisation of untouched rows included).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct CrewEditorReloadTests {
    func member() -> CrewMember {
        let m = CrewMember()
        m.firstName = "JUAN"; m.lastName = "DELA CRUZ"; m.vessel = "MT EXAMPLE STAR"
        m.signOffDate = "2026-09-25"; m.signOnDate = "1-May-2026"; m.nationality = " Philippines "
        return m
    }

    @Test func untouchedRowKeepsReloadedValue() {
        let m = member()
        let original = CrewEditorForm.draft(of: m)
        var d = original
        d["Vessel"] = "MT OTHER STAR"                         // the only edit
        m.signOffDate = "2026-12-10"                          // arrived through a reload while the sheet was open
        let kept = CrewEditorForm.apply(d, original: original, to: m)
        #expect(m.vessel == "MT OTHER STAR")
        #expect(m.signOffDate == "2026-12-10")
        #expect(kept == ["SignOffDate"])
    }

    @Test func editedRowWinsOverReloadedValue() {
        let m = member()
        let original = CrewEditorForm.draft(of: m)
        var d = original
        d["SignOffDate"] = "2027-01-15"
        m.signOffDate = "2026-12-10"
        CrewEditorForm.apply(d, original: original, to: m)
        #expect(m.signOffDate == "2027-01-15")
    }

    @Test func withoutReloadSameAsApplyAll() {
        let a = member(), b = member()
        let original = CrewEditorForm.draft(of: a)
        var d = original
        d["FirstName"] = " Juan Carlos "
        CrewEditorForm.apply(d, original: original, to: a)
        CrewEditorForm.apply(d, to: b)
        for f in CrewEditorForm.allFields { #expect(a.stringField(f.key) == b.stringField(f.key), "\(f.key)") }
        #expect(a.signOnDate == "2026-05-01")                 // untouched legacy date still normalised (parity)
        #expect(a.nationality == "Philippines")               // untouched text still trimmed
    }

    @Test func rebaseShowsFreshValuesAndKeepsEdits() {
        let m = member()
        var original = CrewEditorForm.draft(of: m)
        var d = original
        d["Vessel"] = "MT OTHER STAR"
        m.signOffDate = "2026-12-10"
        m.vessel = "MT THIRD STAR"
        CrewEditorForm.rebase(draft: &d, original: &original, onto: m)
        #expect(d["SignOffDate"] == "2026-12-10")
        #expect(d["Vessel"] == "MT OTHER STAR")
        #expect(original["Vessel"] == "MT THIRD STAR")
        CrewEditorForm.apply(d, original: original, to: m)
        #expect(m.vessel == "MT OTHER STAR" && m.signOffDate == "2026-12-10")
    }
}
