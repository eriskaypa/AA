// Tests for 02 §7.9 (T-ORD-1…17, per-group assertions — OC-16), 06 §7.4 (flat results; row 2 read per OC-16) and
// 06 §7.5 (export ordering); DECISIONS 02 Q-1 (the fixed nudge).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct SvcSavedListOrderTests {
    /// Builds `all` from a notation like "A:g X:h B:g C:-" (group ids per letter; "-" = ungrouped).
    private func lists(_ spec: String) -> (all: [ChecklistTemplate], by: [String: ChecklistTemplate], groups: [String: UUID]) {
        var groups: [String: UUID] = [:]
        var all: [ChecklistTemplate] = []
        var by: [String: ChecklistTemplate] = [:]
        for token in spec.split(separator: " ") {
            let parts = token.split(separator: ":").map(String.init)
            let g: UUID? = parts[1] == "-" ? nil : {
                if let x = groups[parts[1]] { return x }
                let x = UUID(); groups[parts[1]] = x; return x
            }()
            let t = ChecklistTemplate(name: parts[0], groupId: g)
            all.append(t); by[parts[0]] = t
        }
        return (all, by, groups)
    }

    private func names(_ all: [ChecklistTemplate]) -> String { all.map(\.name).joined(separator: " ") }

    private func group(_ all: [ChecklistTemplate], _ g: UUID?) -> String {
        names(all.filter { $0.groupId == g })
    }

    @Test func groupSpan() {
        // REPO-131
        let (all, _, g) = lists("A:g X:h B:g C:-")
        #expect(SavedListOrder.groupSpan(all, groupID: g["g"]) == [0, 2])
        #expect(SavedListOrder.groupSpan(all, groupID: nil) == [3])
    }

    @Test func nudgeVectors() {
        // TV: 02 T-ORD-1…7 (per-group subsequences; T-ORD-6/7 = the intended order, 02 §8 D-1 fixed)
        var (all, by, g) = lists("A:g B:g C:g")
        #expect(SavedListOrder.nudge(&all, picks: [by["B"]!, by["C"]!], up: true))
        #expect(group(all, g["g"]) == "B C A")

        (all, by, g) = lists("A:g B:g C:g")
        #expect(!SavedListOrder.nudge(&all, picks: [by["A"]!], up: true))
        #expect(!SavedListOrder.nudge(&all, picks: [by["C"]!], up: false))
        #expect(names(all) == "A B C")

        (all, by, g) = lists("A:g X:h")
        #expect(!SavedListOrder.nudge(&all, picks: [by["A"]!, by["X"]!], up: true))
        (all, by, g) = lists("A:g")
        #expect(!SavedListOrder.nudge(&all, picks: [by["A"]!], up: false))
        #expect(!SavedListOrder.nudge(&all, picks: [], up: true))

        (all, by, g) = lists("A:g X:h B:g")
        #expect(SavedListOrder.nudge(&all, picks: [by["B"]!], up: true))
        #expect(group(all, g["g"]) == "B A" && group(all, g["h"]) == "X")

        (all, by, g) = lists("A:g X:h B:g C:g")
        #expect(SavedListOrder.nudge(&all, picks: [by["B"]!, by["C"]!], up: true))
        #expect(group(all, g["g"]) == "B C A" && group(all, g["h"]) == "X")

        (all, by, g) = lists("A:g B:g X:h C:g")
        #expect(SavedListOrder.nudge(&all, picks: [by["A"]!, by["B"]!], up: false))
        #expect(group(all, g["g"]) == "C A B" && group(all, g["h"]) == "X")
    }

    @Test func nudgeSpecSixRows() {
        // TV: 06 §7.4 nudge rows (row 2 per OC-16: g1 C A B, flat C X A B with the fixed nudge)
        var (all, by, g) = lists("A:1 X:2 B:1 C:1")
        #expect(SavedListOrder.nudge(&all, picks: [by["C"]!], up: true) && names(all) == "A X C B")
        (all, by, g) = lists("A:1 X:2 B:1 C:1")
        #expect(SavedListOrder.nudge(&all, picks: [by["A"]!, by["B"]!], up: false))
        #expect(group(all, g["1"]) == "C A B" && group(all, g["2"]) == "X" && names(all) == "C X A B")
        (all, by, g) = lists("A:1 X:2 B:1 C:1")
        #expect(!SavedListOrder.nudge(&all, picks: [by["A"]!], up: true))
        #expect(!SavedListOrder.nudge(&all, picks: [by["A"]!, by["X"]!], up: true))
        #expect(!SavedListOrder.nudge(&all, picks: [by["X"]!], up: true) && names(all) == "A X B C")
        (all, by, g) = lists("A:1 B:1 C:1 D:1")
        #expect(SavedListOrder.nudge(&all, picks: [by["B"]!, by["D"]!], up: true) && names(all) == "B A D C")
        (all, by, g) = lists("A:1 B:1 C:1 D:1")
        #expect(SavedListOrder.nudge(&all, picks: [by["A"]!, by["C"]!], up: false) && names(all) == "B A D C")
        (all, by, g) = lists("U:- A:1 V:- X:2 B:1")
        #expect(SavedListOrder.nudge(&all, picks: [by["V"]!], up: true) && names(all) == "V U A X B")
        _ = g
    }

    @Test func moveToVectors() {
        // TV: 02 T-ORD-8…13; 06 §7.4 MoveTo rows (flat results identical to Windows)
        var (all, by, g) = lists("A:g X:h B:g")
        #expect(SavedListOrder.moveTo(&all, picks: [by["B"]!], targetInGroup: 0))
        #expect(group(all, g["g"]) == "B A" && names(all) == "B X A")
        (all, by, g) = lists("A:g B:g C:g D:g")
        #expect(SavedListOrder.moveTo(&all, picks: [by["A"]!, by["C"]!], targetInGroup: 4) && names(all) == "B D A C")
        (all, by, g) = lists("A:g B:g C:g D:g")
        #expect(SavedListOrder.moveTo(&all, picks: [by["D"]!], targetInGroup: 1) && names(all) == "A D B C")
        (all, by, g) = lists("A:g B:g C:g D:g")
        #expect(SavedListOrder.moveTo(&all, picks: [by["B"]!], targetInGroup: 2) && names(all) == "A B C D")
        (all, by, g) = lists("A:g B:g C:g")
        #expect(SavedListOrder.moveTo(&all, picks: [by["A"]!], targetInGroup: 99) && names(all) == "B C A")
        #expect(!SavedListOrder.moveTo(&all, picks: [], targetInGroup: 0))
        #expect(!SavedListOrder.moveTo(&all, picks: [ChecklistTemplate(name: "Z", groupId: g["g"])], targetInGroup: 0))

        (all, by, g) = lists("A:1 B:1 C:1 D:1")
        #expect(SavedListOrder.moveTo(&all, picks: [by["B"]!, by["D"]!], targetInGroup: 2) && names(all) == "A B D C")
        (all, by, g) = lists("A:1 B:1 C:1 D:1")
        #expect(SavedListOrder.moveTo(&all, picks: [by["B"]!, by["D"]!], targetInGroup: 0) && names(all) == "B D A C")
        (all, by, g) = lists("A:1 B:1 C:1 D:1")
        #expect(SavedListOrder.moveTo(&all, picks: [by["B"]!, by["D"]!], targetInGroup: 4) && names(all) == "A C B D")
        (all, by, g) = lists("A:1 X:2 B:1 Y:2 C:1 D:1")
        #expect(SavedListOrder.moveTo(&all, picks: [by["D"]!], targetInGroup: 0) && names(all) == "D X A Y B C")
        (all, by, g) = lists("A:1 X:2 B:1 Y:2 C:1 D:1")
        #expect(SavedListOrder.moveTo(&all, picks: [by["A"]!, by["C"]!], targetInGroup: 4) && names(all) == "B D X Y A C")
        (all, by, g) = lists("A:1 X:2 B:1 Y:2 C:1 D:1")
        #expect(SavedListOrder.moveTo(&all, picks: [by["A"]!, by["B"]!], targetInGroup: 3) && names(all) == "C X A Y B D")
        (all, by, g) = lists("A:1 X:2 B:1")
        #expect(!SavedListOrder.moveTo(&all, picks: [by["A"]!, by["X"]!], targetInGroup: 0) && names(all) == "A X B")
    }

    @Test func permutationInvariantFuzz() {
        // 06 §7.4 invariants: permutation; other groups untouched; moved group equals the documented target
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            let count = Int.random(in: 2...8, using: &rng)
            let groupIDs = [UUID(), UUID(), nil]
            var all = (0..<count).map { ChecklistTemplate(name: "L\($0)", groupId: groupIDs[Int.random(in: 0...2, using: &rng)]) }
            let gid = all[Int.random(in: 0..<count, using: &rng)].groupId
            let members = all.filter { $0.groupId == gid }
            let picks = members.filter { _ in Bool.random(using: &rng) }
            let before = all.map(ObjectIdentifier.init)
            let others = all.filter { $0.groupId != gid }.map(ObjectIdentifier.init)
            let up = Bool.random(using: &rng)
            var expected = members
            let at = picks.compactMap { p in members.firstIndex { $0 === p } }.sorted()
            let ok = !at.isEmpty && members.count >= 2 && !(up && at.first == 0) && !(!up && at.last == members.count - 1)
            if ok { for pos in (up ? at : at.reversed()) { expected.swapAt(pos, up ? pos - 1 : pos + 1) } }
            let changed = SavedListOrder.nudge(&all, picks: picks, up: up)
            #expect(changed == ok)
            #expect(Set(all.map(ObjectIdentifier.init)) == Set(before))
            #expect(all.filter { $0.groupId != gid }.map(ObjectIdentifier.init) == others)
            #expect(all.filter { $0.groupId == gid }.map(ObjectIdentifier.init) == expected.map(ObjectIdentifier.init))
        }
    }

    @Test func exportEntries() {
        // TV: 02 T-ORD-14, T-ORD-15, T-ORD-16; 06 §7.5
        let data = AppData()
        let g1 = ListGroup(name: "alpha"), g2 = ListGroup(name: "Beta")
        data.listGroups = [g1, g2]
        let t1 = ChecklistTemplate(name: "T1", groupId: g2.id), t2 = ChecklistTemplate(name: "T2")
        let t3 = ChecklistTemplate(name: "T3", groupId: g1.id), t4 = ChecklistTemplate(name: "T4", groupId: g2.id)
        let t5 = ChecklistTemplate(name: "T5", groupId: g1.id)
        data.checklistTemplates = [t1, t2, t3, t4, t5]
        let all = SavedListOrder.allEntries(data)
        #expect(all.map(\.template.name) == ["T3", "T5", "T1", "T4", "T2"])
        #expect(all.map(\.group) == ["alpha", "alpha", "Beta", "Beta", nil])
        let t6 = ChecklistTemplate(name: "T6", groupId: UUID())
        data.checklistTemplates.append(t6)
        let withDangling = SavedListOrder.allEntries(data)
        #expect(withDangling.first?.template.name == "T6" && withDangling.first?.group == "")

        let beta = SavedListOrder.groupEntries(data, groupID: g2.id) ?? []
        #expect(beta.map(\.template.name) == ["T1", "T4"] && beta.allSatisfy { $0.group == "Beta" })
        let ungrouped = SavedListOrder.groupEntries(data, groupID: nil) ?? []
        #expect(ungrouped.map(\.template.name) == ["T2"] && ungrouped.allSatisfy { $0.group == nil })
        let empty = ListGroup(name: "")
        data.listGroups.append(empty)
        let te = ChecklistTemplate(name: "TE", groupId: empty.id)
        data.checklistTemplates.append(te)
        #expect((SavedListOrder.groupEntries(data, groupID: empty.id) ?? []).map(\.group) == [nil])

        // 06 §7.5: Beta (b), alpha (a); T1(b) T2(-) T3(a) T4(b) T5(-)
        let d2 = AppData()
        let b = ListGroup(name: "Beta"), a = ListGroup(name: "alpha")
        d2.listGroups = [b, a]
        d2.checklistTemplates = [ChecklistTemplate(name: "T1", groupId: b.id), ChecklistTemplate(name: "T2"),
                                 ChecklistTemplate(name: "T3", groupId: a.id), ChecklistTemplate(name: "T4", groupId: b.id),
                                 ChecklistTemplate(name: "T5")]
        let e2 = SavedListOrder.allEntries(d2)
        #expect(e2.map(\.template.name) == ["T3", "T1", "T4", "T2", "T5"])
        #expect(e2.map(\.group) == ["alpha", "Beta", "Beta", nil, nil])
    }

    @Test func orderSurvivesJSON() throws {
        // TV: 02 T-ORD-17
        let data = AppData()
        data.checklistTemplates = ["C", "A", "B"].map { ChecklistTemplate(name: $0) }
        let text = try JSONWriter.string(ModelCodec.encodeAppData(data))
        let back = try ModelCodec.decodeAppData(try JSONParser.parse(text), context: .standard)
        #expect(back.checklistTemplates.map(\.name) == ["C", "A", "B"])
    }
}
