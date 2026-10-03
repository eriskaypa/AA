// Tests for 04 §7.11 (relationships), HIER-021/025…027/030…034/061/070/072/073/080…083/086 model operations,
// HIER-031 group picker, VIEW-212 rows 11–12 / VIEW-215 (replace-semantics pickers), DECISIONS 04 Q-B, REPO-051
// (coerce against the model's partner), HIER-141 log lines.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct HierPageOpsTests {
    static let clock = FixedClock(local: "2026-09-29T11:15:30", zone: TZ.athens)

    func make() -> StoreFactory.Made { StoreFactory.make(clock: Self.clock) }

    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> NetDateTime {
        NetDateTime(year: y, month: m, day: d, hour: h, minute: mi, kind: .unspecified)
    }

    // TV: 04 §7.11 — two-way add/remove, RelatedItems de-dup order, ReferencedBy order, Label
    @Test func relationshipVectors() throws {
        let made = make(); let store = made.store
        let a = store.createItem(kind: .task, name: "A"), b = store.createItem(kind: .task, name: "B")
        store.addRelation(a, b)
        #expect(a.relatedIds == [b.id] && b.relatedIds == [a.id])
        store.removeRelation(a, b)
        #expect(a.relatedIds.isEmpty && b.relatedIds.isEmpty)

        let e = try #require(store.createItem(kind: .equipment, name: "E") as? Equipment)
        let p = store.createItem(kind: .procedure, name: "P"), t = store.createItem(kind: .task, name: "T")
        e.procedureIds = [p.id]
        e.relatedIds = [p.id, t.id]
        #expect(store.relatedItems(of: e).map(\.id) == [p.id, t.id])
        let rows = HierRelations.relatedRows(store: store, item: e)
        #expect(rows.map(\.isOneWay) == [false, false])

        let q = try #require(store.createItem(kind: .procedure, name: "Q") as? Procedure)
        q.steps = [ChecklistStep(title: "s")]
        q.steps[0].taskIds = [t.id]
        e.taskIds = [t.id]
        e.relatedIds = []
        #expect(HierRelations.backlinkRows(store: store, item: t).map(\.item.id) == [e.id, q.id])
        #expect(store.label(for: UUID()) == "(missing)")
        #expect(store.label(for: e.id) == "[Equipment] E")
        #expect(HierText.label(HierRelations.summary(e)) == "[Equipment] E")
    }

    // DECISIONS 04 Q-B — rows only present through ProcedureIds / TaskIds are one-way
    @Test func oneWayRows() throws {
        let made = make(); let store = made.store
        let e = try #require(store.createItem(kind: .equipment, name: "E") as? Equipment)
        let p = store.createItem(kind: .procedure, name: "P"), t = store.createItem(kind: .task, name: "T")
        let v = store.createItem(kind: .vessel, name: "V")
        store.addRelation(e, v)
        e.procedureIds = [p.id]; e.taskIds = [t.id, v.id]
        let rows = HierRelations.relatedRows(store: store, item: e)
        #expect(rows.map(\.item.name) == ["V", "P", "T"])
        #expect(rows.map(\.isOneWay) == [false, true, true])
        #expect(rows[1].label == "[Procedure] P")
    }

    // TV: 04 §7.11 — Add-relationship candidates: kind, then name (ordinal ignore-case), self excluded
    @Test func relationshipCandidates() {
        let made = make(); let store = made.store
        let me = store.createItem(kind: .equipment, name: "me")
        _ = store.createItem(kind: .vessel, name: "a")
        _ = store.createItem(kind: .task, name: "B")
        _ = store.createItem(kind: .equipment, name: "c")
        _ = store.createItem(kind: .task, name: "a")
        let c = HierRelations.candidates(store: store, excluding: me).map(HierText.label)
        #expect(c == ["[Equipment] c", "[Task] a", "[Task] B", "[Vessel] a"])
    }

    // HIER-061 — add in selection order, two-way, no duplicates, self ignored
    @Test func addRelations() {
        let made = make(); let store = made.store
        let me = store.createItem(kind: .task, name: "me"), x = store.createItem(kind: .task, name: "x")
        let y = store.createItem(kind: .procedure, name: "y")
        #expect(HierRelations.addRelations(store: store, item: me, pickedIDs: [y.id, x.id, me.id, UUID()]) == 2)
        #expect(me.relatedIds == [y.id, x.id] && x.relatedIds == [me.id] && y.relatedIds == [me.id])
        #expect(HierRelations.addRelations(store: store, item: me, pickedIDs: [x.id]) == 0)
        #expect(me.relatedIds == [y.id, x.id])
    }

    // HIER-031 / VIEW-212 row 7 — picker rows, common-group preselection, empty-GUID tag
    @Test func groupPicker() {
        let made = make(); let store = made.store
        let g1 = store.createGroup(kind: .task, name: "Zulu"), g2 = store.createGroup(kind: .task, name: "Alpha")
        _ = store.createGroup(kind: .equipment, name: "Other kind")
        let choices = HierGroupPicker.assignChoices(store: store, kind: .task)
        #expect(choices.map(\.display) == ["(Ungrouped)", "Zulu", "Alpha"])            // creation order
        #expect(choices[0].tag == .netEmpty && choices[1].tag == g1.id)
        let a = store.createItem(kind: .task, name: "a"), b = store.createItem(kind: .task, name: "b")
        #expect(HierGroupPicker.commonGroup([a, b], store: store, kind: .task) == .netEmpty)
        a.groupId = g2.id
        #expect(HierGroupPicker.commonGroup([a, b], store: store, kind: .task) == nil)
        b.groupId = g2.id
        #expect(HierGroupPicker.commonGroup([a, b], store: store, kind: .task) == g2.id)
        b.groupId = UUID()                                                                // dangling = ungrouped
        a.groupId = nil
        #expect(HierGroupPicker.commonGroup([a, b], store: store, kind: .task) == .netEmpty)
        #expect(HierGroupPicker.groupID(fromTag: .netEmpty) == nil && HierGroupPicker.groupID(fromTag: g1.id) == g1.id)
    }

    // HIER-030…034 — create (trimmed, blank → nothing), assign / remove, rename, delete ungroups every kind
    @Test func groupOperations() throws {
        let made = make(); let store = made.store
        #expect(HierPageOps.createGroup(store: store, kind: .task, name: "   ") == nil)
        let g = try #require(HierPageOps.createGroup(store: store, kind: .task, name: "  Engine room "))
        #expect(g.name == "Engine room" && g.kind == .task && g.expanded)
        let a = store.createItem(kind: .task, name: "a"), b = store.createItem(kind: .task, name: "b")
        #expect(HierPageOps.assign(store: store, [a, b], to: g.id) == 2)
        #expect(HierPageOps.assign(store: store, [a, b], to: g.id) == 0)
        #expect(HierPageOps.removeFromGroup(store: store, [a]) == 1 && a.groupId == nil && b.groupId == g.id)
        #expect(HierPageOps.removeFromGroup(store: store, [a]) == 0)
        store.renameGroup(g, to: "  Deck ")
        #expect(g.name == "Deck")
        let e = store.createItem(kind: .equipment, name: "e")
        e.groupId = g.id                                                                  // cross-kind reference
        store.deleteGroup(g)
        #expect(store.data.groups.isEmpty && b.groupId == nil && e.groupId == nil)
    }

    // HIER-021 / HIER-141 — + New default names, appended, logged with the kind label
    @Test func newItems() {
        let made = make(); let store = made.store
        let names = ItemKind.allKinds.map { store.createItem(kind: $0).name }
        #expect(names == ["New Equipment/Area", "New Task", "New Procedure", "New Vessel"])
        #expect(store.data.log.map(\.kind) == ["Equipment/Area", "Task", "Procedure", "Vessel"])
        #expect(store.data.log.allSatisfy { $0.action == "Added" && $0.detail == "" })
    }

    // HIER-025…027 — header edits
    @Test func headerEdits() {
        let made = make(); let store = made.store
        let t = store.createItem(kind: .task, name: "x")
        #expect(HierPageOps.setName(t, "  spaced  ") && t.name == "  spaced  ")
        #expect(!HierPageOps.setName(t, "  spaced  "))
        #expect(HierPageOps.setName(t, "") && t.name == "")
        #expect(HierPageOps.setDescription(t, "line"))
        #expect(HierPageOps.setTags(t, fromText: "pump, #Engine;  main\tpump") && t.tags == ["pump", "Engine", "main"])
        #expect(!HierPageOps.setTags(t, fromText: "pump Engine main"))
        #expect(HierPageOps.setTags(t, fromText: "") && t.tags.isEmpty)
    }

    // HIER-070/072/073 — components, linked creation (logged), replace-semantics pickers (VIEW-215)
    @Test func equipmentSpecifics() throws {
        let made = make(); let store = made.store
        let e = try #require(store.createItem(kind: .equipment, name: "Engine room") as? Equipment)
        #expect(HierPageOps.addComponent(store: store, named: "  ", to: e) == nil)
        let c = try #require(HierPageOps.addComponent(store: store, named: " Bowl ", to: e))
        #expect(c.name == " Bowl " && e.components.count == 1)
        let logCount = store.data.log.count
        store.removeComponent(c, from: e)
        #expect(e.components.isEmpty && store.data.log.count == logCount)                // components are not logged

        let p = try #require(HierPageOps.newLinkedProcedure(store: store, named: "Overhaul", for: e))
        #expect(e.procedureIds == [p.id] && store.data.procedures.last === p)
        #expect(store.data.log.last?.detail == "linked to Engine room" && store.data.log.last?.kind == "Procedure")
        let t = try #require(HierPageOps.newLinkedTask(store: store, named: "Check", for: e))
        #expect(e.taskIds == [t.id] && store.data.log.last?.kind == "Task")
        #expect(HierPageOps.newLinkedTask(store: store, named: " ", for: e) == nil)

        let p2 = store.createItem(kind: .procedure, name: "Second")
        let missing = UUID()
        e.procedureIds = [p.id, missing, p.id]
        HierPageOps.replaceProcedureLinks(store: store, [p2.id, p.id, missing, p2.id], on: e)
        #expect(e.procedureIds == [p2.id, p.id])                                           // selection order kept
        let sub = store.addSubtask(named: "sub", to: t)
        HierPageOps.replaceTaskLinks(store: store, [sub.id, t.id], on: e)                  // subtasks are not candidates
        #expect(e.taskIds == [t.id])
        #expect(HierLinkPicker.procedureCandidates(store: store).map(\.display) == ["Overhaul", "Second"])
        let labels = HierLinkPicker.labels(store: store, ids: [p.id, missing])
        #expect(labels.map(\.label) == ["[Procedure] Overhaul", "(missing)"] && labels.map(\.exists) == [true, false])
    }

    // HIER-080 / REPO-051 — coerce against the MODEL's partner value
    @Test func taskRangeAgainstModel() throws {
        let made = make(); let store = made.store
        let t = try #require(store.createItem(kind: .task, name: "t") as? TaskItem)
        #expect(HierPageOps.setTaskStart(t, day(2026, 1, 5)))                              // start alone → one-day range
        #expect(t.rangeStart == day(2026, 1, 5) && t.deadline == day(2026, 1, 5))
        #expect(HierPageOps.setTaskDeadline(t, day(2026, 1, 9)))
        #expect(t.rangeStart == day(2026, 1, 5) && t.deadline == day(2026, 1, 9) && t.whenText == "2026-01-05 → 2026-01-09")
        #expect(HierPageOps.setTaskStart(t, day(2026, 1, 12)))                             // start after → deadline follows
        #expect(t.deadline == day(2026, 1, 12))
        #expect(HierPageOps.setTaskDeadline(t, day(2026, 1, 10)))                          // deadline before → start pulled
        #expect(t.rangeStart == day(2026, 1, 10) && t.deadline == day(2026, 1, 10))
        #expect(!HierPageOps.setTaskDeadline(t, nil))                                      // cleared with a start → re-set
        #expect(t.deadline == day(2026, 1, 10))
        #expect(HierPageOps.setTaskStart(t, nil) && t.rangeStart == nil)
        #expect(HierPageOps.setTaskDeadline(t, nil) && t.deadline == nil)
        #expect(HierPageOps.setTaskDeadline(t, day(2026, 1, 7, 15, 30)))                   // time dropped
        #expect(t.deadline == day(2026, 1, 7) && t.deadline?.kind == .unspecified)
        // A batch deadline elsewhere moved the model; the page coerces against the model, never a stale control.
        t.rangeStart = day(2026, 1, 3); t.deadline = day(2026, 1, 4)
        #expect(HierPageOps.setTaskDeadline(t, day(2026, 1, 6)))
        #expect(t.rangeStart == day(2026, 1, 3) && t.deadline == day(2026, 1, 6))
    }

    // HIER-082 / HIER-083 — status ⇄ completed, duration text
    @Test func statusAndDuration() throws {
        let made = make(); let store = made.store
        let t = try #require(store.createItem(kind: .task, name: "t") as? TaskItem)
        t.status = .inProgress
        t.isComplete = false
        #expect(t.status == .inProgress)                                                    // no-op on status
        t.isComplete = true
        #expect(t.status == .done)
        t.isComplete = false
        #expect(t.status == .todo)
        t.status = .done
        #expect(t.isComplete)
        t.status = .blocked
        #expect(!t.isComplete)
        var written: Int?
        #expect(!HierPageOps.setDuration("abc", current: 60) { written = $0 } && written == nil)
        #expect(!HierPageOps.setDuration("60", current: 60) { written = $0 })
        #expect(HierPageOps.setDuration(" 90 ", current: 60) { written = $0 } && written == 90)
    }

    // HIER-086 / HIER-141 — subtask add/remove log lines
    @Test func subtasks() throws {
        let made = make(); let store = made.store
        let t = try #require(store.createItem(kind: .task, name: "Parent") as? TaskItem)
        #expect(HierPageOps.addSubtask(store: store, named: "\t", to: t) == nil)
        let s = try #require(HierPageOps.addSubtask(store: store, named: "Child", to: t))
        #expect(t.subtasks.count == 1 && store.data.log.last?.kind == "Subtask" && store.data.log.last?.detail == "Parent")
        store.removeSubtask(s, from: t)
        #expect(t.subtasks.isEmpty && store.data.log.last?.action == "Removed")
    }

    // DECISIONS 02 Q-11 — a navigation naming a child selects its row: the direct subtask containing a nested hit
    // (cycle-guarded), or the named component
    @Test func childReveal() throws {
        let made = make(); let store = made.store
        let t = try #require(store.createItem(kind: .task, name: "Parent") as? TaskItem)
        let a = store.addSubtask(named: "A", to: t)
        let b = store.addSubtask(named: "B", to: t)
        let b1 = store.addSubtask(named: "B1", to: b)
        let b2 = store.addSubtask(named: "B2", to: b1)
        #expect(HierPageOps.directSubtask(of: t, revealing: a.id) === a)
        #expect(HierPageOps.directSubtask(of: t, revealing: b2.id) === b)
        #expect(HierPageOps.directSubtask(of: t, revealing: UUID()) == nil)
        b2.subtasks.append(b1)                                                   // malformed cycle: no hang
        #expect(HierPageOps.directSubtask(of: t, revealing: UUID()) == nil)
        let e = try #require(store.createItem(kind: .equipment, name: "Pump") as? Equipment)
        let c = store.addComponent(named: "Seal", to: e)
        #expect(HierPageOps.component(of: e, id: c.id) === c)
        #expect(HierPageOps.component(of: e, id: UUID()) == nil)
    }
}
