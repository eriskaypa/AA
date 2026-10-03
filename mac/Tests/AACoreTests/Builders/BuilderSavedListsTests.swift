// Tests for 06 §G (BUILD-071…090), BUILD-A10 and the 06 §7.5 / §7.6 / §7.14 vectors; 02 REPO-134 guards (W-BUILD).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct BuilderSavedListsTests {
    /// 06 §7.5: groups Beta (b), alpha (a); collection T1(b) T2(-) T3(a) T4(b) T5(-).
    private func vectorData() -> AppData {
        let d = AppData()
        let beta = ListGroup(name: "Beta"), alpha = ListGroup(name: "alpha")
        d.listGroups = [beta, alpha]
        func t(_ n: String, _ g: ListGroup?) -> ChecklistTemplate {
            let x = ChecklistTemplate(name: n); x.groupId = g?.id; return x
        }
        d.checklistTemplates = [t("T1", beta), t("T2", nil), t("T3", alpha), t("T4", beta), t("T5", nil)]
        return d
    }

    @Test func tabSectionsVector() {
        // TV: 06 §7.5 — sections alpha[T3], Beta[T1,T4], Ungrouped[T2,T5]; status "5 saved list(s)  ·  2 group(s)"
        let d = vectorData()
        let s = BuilderSavedLists.sections(d, sortAZ: false)
        #expect(s.map(\.title) == ["alpha", "Beta", "Ungrouped"])
        #expect(s.map { $0.rows.map(\.name) } == [["T3"], ["T1", "T4"], ["T2", "T5"]])
        #expect(s.map(\.count) == [1, 2, 2])
        #expect(BuilderSavedLists.statusLine(lists: 5, groups: 2) == "5 saved list(s)  ·  2 group(s)")
        #expect(BuilderSavedLists.statusLine(lists: 0, groups: 3)
                == "No saved lists yet. Build a checklist anywhere and click 'Save as list...', or click '+ List'.")
    }

    @Test func sortAZAndArrangedOrder() {
        // BUILD-072 / BUILD-088: A-Z sorts within a group; the arrangement underneath is untouched.
        let d = AppData()
        let names = ["delta", "Alpha", "", "charlie"]
        d.checklistTemplates = names.map { ChecklistTemplate(name: $0) }
        let arranged = BuilderSavedLists.sections(d, sortAZ: false)[0].rows.map(\.name)
        #expect(arranged == ["delta", "Alpha", "(unnamed)", "charlie"])
        let az = BuilderSavedLists.sections(d, sortAZ: true)[0].rows.map(\.name)
        #expect(az == ["(unnamed)", "Alpha", "charlie", "delta"])
        #expect(d.checklistTemplates.map(\.name) == names)
        #expect(BuilderSavedLists.sections(d, sortAZ: false)[0].rows.map(\.countText) == ["0 items", "0 items", "0 items", "0 items"])
    }

    @Test func groupsByIdAndHidesEmptyGroups() {
        // 06 §8 D1: equally named groups stay separate; a dangling group id shows under Ungrouped; empty groups hidden.
        let d = AppData()
        let g1 = ListGroup(name: "Deck"), g2 = ListGroup(name: "Deck"), empty = ListGroup(name: "Empty"), unnamed = ListGroup(name: "")
        d.listGroups = [g1, g2, empty, unnamed]
        let a = ChecklistTemplate(name: "A"); a.groupId = g1.id
        let b = ChecklistTemplate(name: "B"); b.groupId = g2.id
        let c = ChecklistTemplate(name: "C"); c.groupId = UUID()
        let u = ChecklistTemplate(name: "U"); u.groupId = unnamed.id
        d.checklistTemplates = [a, b, c, u]
        let s = BuilderSavedLists.sections(d, sortAZ: false)
        #expect(s.map(\.title) == ["(unnamed group)", "Deck", "Deck", "Ungrouped"])
        #expect(s[1].groupID == g1.id && s[2].groupID == g2.id)
        #expect(s.last!.rows.map(\.name) == ["C"])
    }

    @Test func detailAndItemTexts() {
        // TV: 06 §7.6 — DetailSub, item meta, Display
        withTimeZone("Europe/Berlin") { zone in
            let g = ListGroup(name: "Deck")
            let t = ChecklistTemplate(name: "Rounds",
                                      items: [ChecklistTemplateItem(title: "a"), ChecklistTemplateItem(title: "b"),
                                              ChecklistTemplateItem(title: "c")])
            t.groupId = g.id
            t.createdUtc = NetDateTime(year: 2026, month: 7, day: 8, hour: 23, minute: 30, kind: .utc)
            #expect(BuilderSavedLists.detailSub(t, groups: [g], zone: zone) == "3 item(s)  ·  group: Deck  ·  created 2026-07-09")
            t.groupId = nil
            #expect(BuilderSavedLists.detailSub(t, groups: [g], zone: zone) == "3 item(s)  ·  ungrouped  ·  created 2026-07-09")
        }
        let it = ChecklistTemplateItem(title: "", isJob: true)
        it.container.richTextXaml = "<Section/>"
        it.container.files = [FileItem(name: "a"), FileItem(name: "b")]
        #expect(BuilderSavedLists.itemMeta(it) == "job  ·  notes  ·  2 files")
        #expect(BuilderSavedLists.itemTitle(it) == "(untitled)")
        let one = ChecklistTemplateItem(title: "x"); one.container.files = [FileItem(name: "a")]
        #expect(BuilderSavedLists.itemMeta(one) == "1 file")
        #expect(BuilderSavedLists.itemMeta(ChecklistTemplateItem(title: "y")) == "")
        let blank = ChecklistTemplateItem(title: "z"); blank.container.richTextXaml = "  "
        #expect(BuilderSavedLists.itemMeta(blank) == "")
        #expect(ChecklistTemplate(name: "Deck rounds", items: [ChecklistTemplateItem()]).display == "Deck rounds  ·  1 item")
        #expect(ChecklistTemplate(name: "").display == "(unnamed)  ·  0 items")
        #expect(BuilderSavedLists.viewerSubtitle(listName: "Deck")
                == "Saved-list item · Deck — read-only. Click a link to open it; double-click a file to open it.")
        #expect(BuilderSavedLists.viewerSubtitle(listName: " ")
                == "Saved-list item — read-only. Click a link to open it; double-click a file to open it.")
    }

    @Test func reorderGuards() {
        // BUILD-089 / REPO-134 (incl. T-KB-33: nothing arranges while Sort A-Z is on)
        let d = vectorData()
        let ids = { (names: [String]) in Set(d.checklistTemplates.filter { names.contains($0.name) }.map(\.id)) }
        guard case .noSelection = BuilderSavedLists.checkReorder(d, ids: []) else { Issue.record("no selection"); return }
        guard case .mixedGroups = BuilderSavedLists.checkReorder(d, ids: ids(["T1", "T2"])) else { Issue.record("mixed"); return }
        guard case .groupOfOne = BuilderSavedLists.checkReorder(d, ids: ids(["T3"])) else { Issue.record("one"); return }
        guard case .ok(let picks) = BuilderSavedLists.checkReorder(d, ids: ids(["T4", "T1"])) else { Issue.record("ok"); return }
        #expect(picks.map(\.name) == ["T1", "T4"])                      // collection order
        d.ui.sortAZ[BuilderSavedLists.sortAZKey] = true
        guard case .sortAZ = BuilderSavedLists.checkReorder(d, ids: ids(["T1"])) else { Issue.record("sortAZ"); return }
    }

    @Test func moveToPositionOptions() {
        // BUILD-087
        let d = AppData()
        let g = ListGroup(name: "g1"); d.listGroups = [g]
        let names = ["A", "X", "B", "C"]
        d.checklistTemplates = names.map { ChecklistTemplate(name: $0) }
        for t in d.checklistTemplates where t.name != "X" { t.groupId = g.id }
        let picks = [d.checklistTemplates[2]]
        let o = BuilderSavedLists.moveToPositionOptions(d, picks: picks)
        #expect(o.map(\.display) == ["(Move to top of group)", "Before: A", "Before: C", "(Move to bottom of group)"])
        #expect(o.map(\.target) == [0, 0, 2, 3])
        // Drag target inside a section: before C (row 2) → position 2; past the end → group size.
        let rowIDs = [d.checklistTemplates[0].id, d.checklistTemplates[2].id, d.checklistTemplates[3].id]
        #expect(BuilderSavedLists.dropTarget(sectionRowIDs: rowIDs, destination: 2, data: d) == 2)
        #expect(BuilderSavedLists.dropTarget(sectionRowIDs: rowIDs, destination: 3, data: d) == 3)
    }

    @Test func danglingGroupArrangesInsideUngrouped() {
        // D1 + REPO-132…134: a list whose GroupId names a deleted group is shown under "Ungrouped" and is arranged
        // there too; its stored GroupId is never changed (pure permutation, Windows-compatible).
        let d = AppData()
        let g = ListGroup(name: "g1"); d.listGroups = [g]
        let gone = UUID()
        d.checklistTemplates = ["U1", "G1", "D", "U2", "G2"].map { ChecklistTemplate(name: $0) }
        let by = Dictionary(uniqueKeysWithValues: d.checklistTemplates.map { ($0.name, $0) })
        by["G1"]!.groupId = g.id; by["G2"]!.groupId = g.id; by["D"]!.groupId = gone
        let names = { d.checklistTemplates.map(\.name).joined(separator: " ") }
        #expect(BuilderSavedLists.arrangeSpan(d, groupID: nil) == [0, 2, 3])
        #expect(BuilderSavedLists.arrangeSpan(d, groupID: g.id) == SavedListOrder.groupSpan(d.checklistTemplates, groupID: g.id))
        // The dangling list alone is in a group of three, not one.
        guard case .ok = BuilderSavedLists.checkReorder(d, ids: [by["D"]!.id]) else { Issue.record("dangling alone"); return }
        // Together with a genuinely ungrouped list it is the same group, not "different groups".
        guard case .ok(let picks) = BuilderSavedLists.checkReorder(d, ids: [by["D"]!.id, by["U2"]!.id]) else {
            Issue.record("dangling + ungrouped"); return
        }
        #expect(picks.map(\.name) == ["D", "U2"])
        let avail = BuilderSavedLists.reorderAvailability(d, picks: [by["D"]!])
        #expect(avail.up && avail.down)
        // ↑ moves it above U1 inside Ungrouped; the named group's slots are untouched.
        #expect(BuilderSavedLists.nudge(d, picks: [by["D"]!], up: true))
        #expect(names() == "D U1 G1 U2 G2")
        #expect(by["D"]!.groupId == gone)
        // Move to position offers the dangling list as a "Before:" target of an ungrouped list.
        let o = BuilderSavedLists.moveToPositionOptions(d, picks: [by["U2"]!])
        #expect(o.map(\.display) == ["(Move to top of group)", "Before: D", "Before: U1", "(Move to bottom of group)"])
        #expect(BuilderSavedLists.moveTo(d, picks: [by["U2"]!], targetInGroup: 0))
        #expect(names() == "U2 D G1 U1 G2")                             // MoveTo re-anchoring (REPO-133)
        // A drag inside the "Ungrouped" section resolves the dangling row's position too.
        let rows = BuilderSavedLists.sections(d, sortAZ: false).first { $0.groupID == nil }!.rows.map(\.id)
        #expect(rows == [by["U2"]!.id, by["D"]!.id, by["U1"]!.id])
        #expect(BuilderSavedLists.dropTarget(sectionRowIDs: rows, destination: 1, data: d) == 1)
        #expect(BuilderSavedLists.dropTarget(sectionRowIDs: rows, destination: 3, data: d) == 3)
        #expect(BuilderSavedLists.moveTo(d, picks: [by["U2"]!], targetInGroup: 3))
        #expect(names() == "D U1 G1 U2 G2")
        // Mixed named + dangling is still refused.
        guard case .mixedGroups = BuilderSavedLists.checkReorder(d, ids: [by["D"]!.id, by["G1"]!.id]) else {
            Issue.record("mixed"); return
        }
    }

    @Test func resolvedArrangeMatchesSavedListOrderWithoutDanglingIDs() {
        // With no dangling ids the resolved operations are F2's SavedListOrder (06 §7.4 byte-identical order).
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            let groups = [ListGroup(name: "a"), ListGroup(name: "b")]
            let n = Int.random(in: 2...7, using: &rng)
            let spec: [UUID?] = (0..<n).map { _ in [nil, groups[0].id, groups[1].id].randomElement(using: &rng)! }
            let build = { () -> AppData in
                let d = AppData(); d.listGroups = groups
                d.checklistTemplates = spec.enumerated().map { ChecklistTemplate(name: "L\($0.offset)", groupId: $0.element) }
                return d
            }
            let gid = spec.randomElement(using: &rng)!
            let span = SavedListOrder.groupSpan(build().checklistTemplates, groupID: gid)
            let pickPositions = span.indices.filter { _ in Bool.random(using: &rng) }
            let up = Bool.random(using: &rng)
            let target = Int.random(in: 0...span.count, using: &rng)
            // nudge
            let d1 = build(); var ref1 = build().checklistTemplates
            let refPicks1 = pickPositions.map { ref1[span[$0]] }
            let r1 = SavedListOrder.nudge(&ref1, picks: refPicks1, up: up)
            let m1 = BuilderSavedLists.nudge(d1, picks: pickPositions.map { d1.checklistTemplates[span[$0]] }, up: up)
            #expect(r1 == m1)
            #expect(d1.checklistTemplates.map(\.name) == ref1.map(\.name))
            // moveTo
            let d2 = build(); var ref2 = build().checklistTemplates
            let refPicks2 = pickPositions.map { ref2[span[$0]] }
            let r2 = SavedListOrder.moveTo(&ref2, picks: refPicks2, targetInGroup: target)
            let m2 = BuilderSavedLists.moveTo(d2, picks: pickPositions.map { d2.checklistTemplates[span[$0]] },
                                              targetInGroup: target)
            #expect(r2 == m2)
            #expect(d2.checklistTemplates.map(\.name) == ref2.map(\.name))
        }
    }

    @Test func listAndGroupOperations() {
        // BUILD-077…083 (+ BUILD-135 log rows), Addendum TV-PR-47
        let made = StoreFactory.make(); let store = made.store
        #expect(BuilderSavedLists.newList(store, rawName: "   ") == nil)
        let t = BuilderSavedLists.newList(store, rawName: "  Deck rounds ")!
        #expect(t.name == "Deck rounds" && t.items.isEmpty && t.groupId == nil)
        #expect(store.data.log.last!.kind == "Saved list" && store.data.log.last!.detail == "empty")
        #expect(BuilderSavedLists.rename(store, t, rawName: " Rounds ") && t.name == "Rounds")
        #expect(!BuilderSavedLists.rename(store, t, rawName: ""))
        let g = BuilderSavedLists.newGroup(store, rawName: " Deck ")!
        #expect(g.name == "Deck" && store.data.listGroups.count == 1)
        #expect(BuilderSavedLists.newGroup(store, rawName: " ") == nil)
        BuilderSavedLists.assign(store, t, toGroup: g.id)
        #expect(t.groupId == g.id)
        t.items = [ChecklistTemplateItem(title: "a")]
        let copy = BuilderSavedLists.duplicate(store, t)
        #expect(copy.name == "Rounds (copy)" && copy.groupId == g.id && copy.id != t.id)
        #expect(store.data.checklistTemplates.last === copy)
        #expect(store.data.log.last!.detail == "1 item(s)")
        let logsBefore = store.data.log.count
        #expect(BuilderSavedLists.renameGroup(store, g, rawName: " Bridge "))
        #expect(g.name == "Bridge" && store.data.log.count == logsBefore)       // groups are not logged
        #expect(BuilderSavedLists.manageGroupRows(store.data).map(\.display) == ["Bridge  ·  2 list(s)"])
        #expect(BuilderSavedLists.moveToGroupRows(store.data).map(\.display) == ["(No group — ungrouped)", "Bridge"])
        BuilderSavedLists.deleteGroup(store, g)
        #expect(store.data.listGroups.isEmpty && t.groupId == nil && copy.groupId == nil)
        #expect(store.data.checklistTemplates.map(\.name) == ["Rounds", "Rounds (copy)"])     // flat positions kept
        BuilderSavedLists.delete(store, t)
        #expect(store.data.checklistTemplates.count == 1)
        #expect(store.data.log.last!.action == "Removed" && store.data.log.last!.name == "Rounds" && store.data.log.last!.detail == "")
        BuilderSavedLists.setSortAZ(store, true)
        #expect(BuilderSavedLists.isSortAZ(store.data) && store.data.ui.sortAZ["savedlists"] == true)
    }

    @Test func templateEditorRoundTripKeepsIdsWhenUnchanged() {
        // BUILD-063 + §8 D3 / DECISIONS 02 Q-12: an unchanged edit session does not rewrite the template.
        let t = ChecklistTemplate(name: "Deck", items: [ChecklistTemplateItem(title: "A")])
        let containerID = t.items[0].container.id
        let steps = ChecklistTemplateService.toSteps(t)
        #expect(!ChecklistTemplateService.hasChanges(t, steps: steps))
        ChecklistTemplateService.writeBackFromSteps(t, steps: steps)
        #expect(t.items[0].container.id == containerID)
        steps[0].deadline = NetDateTime(year: 2026, month: 1, day: 1, kind: .unspecified)   // never stored
        #expect(!ChecklistTemplateService.hasChanges(t, steps: steps))
        steps[0].title = "B"
        ChecklistTemplateService.writeBackFromSteps(t, steps: steps)
        #expect(t.items.map(\.title) == ["B"])
    }

    @Test func jsonRoundTripKeepsOrderDanglingGroupAndSortAZ() throws {
        // TV: 06 §7.14 — non-alphabetical order, dangling GroupId, SortAZ, an offset-bearing step deadline
        let made = StoreFactory.make()
        let url = Fixtures.url("ui/w-build/sample-data.json")
        let data = try made.dataStore.loadFrom(url)
        let names = data.checklistTemplates.map(\.name)
        let dangling = data.checklistTemplates.first { $0.name == "Old list from a deleted group" }?.groupId
        data.ui.sortAZ["savedlists"] = true
        data.procedures[0].steps[0].deadline = NetDateTime(parsing: "2026-10-03T00:00:00+02:00")
        let bytes = try made.dataStore.serializeForSave(data)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains("2026-10-03T00:00:00+02:00"))
        let out = try made.folder.write("roundtrip.data-json", bytes)
        let back = try made.dataStore.loadFrom(out)
        #expect(back.checklistTemplates.map(\.name) == names)
        #expect(back.checklistTemplates.first { $0.name == "Old list from a deleted group" }?.groupId == dangling)
        #expect(back.ui.sortAZ["savedlists"] == true)
        #expect(!text.contains("\"GroupId\":null"))
    }
}
