// Tests for 06 BUILD-A1…A5, BUILD-004, BUILD-013, BUILD-053 and the 06 §7.3 / §7.7 vectors (W-BUILD).
import Foundation
import Testing
@testable import AACore

@Suite struct BuilderAlgorithmTests {
    private func letters(_ s: String) -> [String] { s.map(String.init) }
    private func idx(_ list: [String], _ picks: String) -> [Int] { picks.map { list.firstIndex(of: String($0))! } }

    @Test func reorderVectors() {
        // TV: 06 §7.3 (flat list A B C D E)
        func up(_ p: String) -> String { var a = letters("ABCDE"); BuilderReorder.moveUp(&a, picks: idx(a, p)); return a.joined() }
        func down(_ p: String) -> String { var a = letters("ABCDE"); BuilderReorder.moveDown(&a, picks: idx(a, p)); return a.joined() }
        func to(_ p: String, _ t: Int) -> String {
            var a = letters("ABCDE"); BuilderReorder.moveTo(&a, picks: idx(a, p), target: t); return a.joined()
        }
        #expect(up("BC") == "BCADE")
        #expect(up("BD") == "BADCE")
        #expect(up("AC") == "ABCDE")
        #expect(down("BD") == "ACBED")
        #expect(down("CE") == "ABCDE")
        #expect(to("BD", 4) == "ACBDE")
        #expect(to("BD", 0) == "BDACE")
        #expect(to("BD", 5) == "ACEBD")
        #expect(to("E", 1) == "AEBCD")
        #expect(to("AB", 3) == "CABDE")
    }

    @Test func moveToReturnsTheMovedBlock() {
        var a = letters("ABCDE")
        #expect(BuilderReorder.moveTo(&a, picks: [1, 3], target: 4) == [2, 3])
        #expect(a[2] == "B" && a[3] == "D")
        var b = letters("AB")
        #expect(BuilderReorder.moveTo(&b, picks: [], target: 0).isEmpty)
        #expect(!BuilderReorder.moveUp(&b, picks: []))
    }

    @Test func moveToOptionsVector() {
        // TV: 06 §7.3 — options for A B C D E with B, D selected; title "Move 2 items to..."
        let o = BuilderReorder.moveToOptions(titles: letters("ABCDE"), selected: [1, 3])
        #expect(o.map(\.display) == ["(Move to top)", "Before: A", "Before: C", "Before: E", "(Move to bottom)"])
        #expect(o.map(\.target) == [0, 0, 2, 4, 5])
        #expect(BuilderWording.moveTitle(2, noun: "item") == "Move 2 items to...")
        #expect(BuilderWording.moveTitle(1, noun: "item") == "Move 1 item to...")
        #expect(BuilderWording.moveTitle(1, noun: "subtask") == "Move 1 subtask to...")
        #expect(BuilderWording.moveTitle(3, noun: "list") == "Move 3 lists to...")
        #expect(BuilderWording.deleteQuestion(1, noun: "item") == "Delete 1 item?")
        #expect(BuilderWording.deleteQuestion(2, noun: "subtask") == "Delete 2 subtasks?")
    }

    @Test func tKB32RowsMoveUpAsABlock() {
        // TV: 03 T-KB-32 — rows [2,3] of 5 selected, Move Up → rows [1,2] (BUILD ↑ semantics)
        var a = letters("ABCDE")
        #expect(BuilderReorder.moveUp(&a, picks: [2, 3]))
        #expect(a.joined() == "ACDBE")
        #expect(a.firstIndex(of: "C") == 1 && a.firstIndex(of: "D") == 2)
    }

    @Test func insertIndex() {
        // BUILD-007/008
        #expect(BuilderReorder.insertIndex(before: true, picks: [3, 1], count: 5) == 1)
        #expect(BuilderReorder.insertIndex(before: true, picks: [], count: 5) == 0)
        #expect(BuilderReorder.insertIndex(before: false, picks: [3, 1], count: 5) == 4)
        #expect(BuilderReorder.insertIndex(before: false, picks: [], count: 5) == 5)
    }

    @Test func dropMoveEqualsMoveTo() {
        var a = letters("ABCDE")
        BuilderReorder.dropMove(&a, from: IndexSet([1, 3]), to: 5)
        #expect(a.joined() == "ACEBD")
    }

    @Test func shortenVectors() {
        // TV: 06 §7.7
        #expect(BuilderShorten.builder("", max: 60) == "")
        #expect(BuilderShorten.builder(nil, max: 60) == "")
        #expect(BuilderShorten.builder("Line1\r\nLine2", max: 60) == "Line1  Line2")
        let long = BuilderShorten.builder(String(repeating: "a", count: 61), max: 60)
        #expect(long == String(repeating: "a", count: 59) + "…")
        #expect(long.count == 60)
        #expect(BuilderShorten.builder(String(repeating: "a", count: 60), max: 60).count == 60)
        #expect(BuilderShorten.savedLists(nil, max: 60) == "(unnamed)")
        #expect(BuilderShorten.savedLists("   ", max: 60) == "(unnamed)")
        #expect(BuilderShorten.savedLists("  Deck  ", max: 60) == "Deck")
    }

    @Test func durationParsing() {
        // BUILD-A5
        #expect(BuilderDuration.parse("45") == 45)
        #expect(BuilderDuration.parse(" 45 ") == 45)
        #expect(BuilderDuration.parse("+0005") == 5)
        #expect(BuilderDuration.parse("0") == nil)
        #expect(BuilderDuration.parse("-5") == nil)
        #expect(BuilderDuration.parse("1,000") == nil)
        #expect(BuilderDuration.parse("1.5") == nil)
        #expect(BuilderDuration.parse("") == nil)
        #expect(BuilderDuration.parse("abc") == nil)
        #expect(BuilderDuration.parse("٣٠") == nil)
        #expect(BuilderDuration.parse("2147483647") == 2_147_483_647)
        #expect(BuilderDuration.parse("2147483648") == nil)
    }

    @Test func bulkLines() {
        // BUILD-004
        #expect(BuilderBulk.lines("  A \r\nB\n\n  \nC") == ["A", "B", "C"])
        #expect(BuilderBulk.lines("   \n\n").isEmpty)
    }

    @Test func rangeHint() {
        // TV: 06 §7.1 range hint
        let d8 = NetDateTime(year: 2026, month: 7, day: 8, kind: .unspecified)
        let d10 = NetDateTime(year: 2026, month: 7, day: 10, kind: .unspecified)
        #expect(BuilderRange.hint(start: d8, deadline: d10) == "range · 3 days")
        #expect(BuilderRange.hint(start: d10, deadline: d10) == "")
        #expect(BuilderRange.hint(start: nil, deadline: d10) == "")
    }

    @Test func wordingStrings() {
        #expect(BuilderWording.insertQuestion(name: "Deck", count: 3, subtasks: false)
                == "Insert 'Deck' (3 item(s)).\n\nYes = replace the current items\nNo = append to the end\nCancel = do nothing")
        #expect(BuilderWording.insertQuestion(name: "Deck", count: 3, subtasks: true)
                == "Insert 'Deck' (3 item(s)).\n\nYes = replace the current subtasks\nNo = append to the end\nCancel = do nothing")
        #expect(BuilderWording.savedListMessage(name: "Deck", count: 1)
                == "Saved 'Deck' (1 item(s)). You can reuse it from any checklist builder.")
        #expect(BuilderWording.manageListQuestion(name: "Deck", count: 2)
                == "'Deck' (2 item(s)).\n\nYes = rename\nNo = delete\nCancel = nothing")
        #expect(BuilderWording.deleteListQuestion(name: "Deck")
                == "Delete saved list 'Deck'? This does not affect any checklist already built from it.")
    }
}
