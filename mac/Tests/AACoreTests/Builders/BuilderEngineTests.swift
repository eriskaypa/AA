// Tests for 06 §A / §D builder operations and their activity-log lines (BUILD-004, 006…016, 044, 135), the step
// editor / task editor rules (BUILD-021, 022, 052…055), and the procedure checklist area (BUILD-032…036) (W-BUILD).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct BuilderEngineTests {
    private func stepsEngine(_ store: AppStore, _ p: Procedure) -> BuilderEngine<ChecklistStep> {
        BuilderEngine(store: store, kind: .steps, logKind: "Checklist step", owner: { p.name },
                      read: { p.steps }, write: { p.steps = $0 })
    }

    private func titles(_ p: Procedure) -> [String] { p.steps.map(\.title) }

    @Test func bulkAddAppendsAndLogs() {
        // BUILD-004 + BUILD-135 row 1
        let made = StoreFactory.make(); let store = made.store
        let p = Procedure(name: "Bunkering"); p.steps = [ChecklistStep(title: "Old")]
        store.data.procedures = [p]
        let e = stepsEngine(store, p)
        let ids = e.addAll(text: "  A\r\nB\n\n C ", replace: false)
        #expect(ids.count == 3)
        #expect(titles(p) == ["Old", "A", "B", "C"])
        #expect(p.steps[1].durationMinutes == 60 && !p.steps[1].done && !p.steps[1].isJob)
        let log = store.data.log.last!
        #expect(log.action == "Added" && log.kind == "Checklist step" && log.name == "3 added (bulk)" && log.detail == "Bunkering")
        #expect(store.isDirty)
        // Replace existing: no confirmation, removed items are not logged.
        let before = store.data.log.count
        e.addAll(text: "X", replace: true)
        #expect(titles(p) == ["X"])
        #expect(store.data.log.count == before + 1)
        // Blank text → no-op.
        #expect(e.addAll(text: " \n ", replace: true).isEmpty)
        #expect(titles(p) == ["X"])
    }

    @Test func insertKeepsTheTitleRawAndLogs() {
        // BUILD-006…008, Addendum #17 (raw)
        let made = StoreFactory.make(); let store = made.store
        let p = Procedure(name: "P"); p.steps = ["A", "B", "C"].map { ChecklistStep(title: $0) }
        store.data.procedures = [p]
        let e = stepsEngine(store, p)
        let sel: Set<UUID> = [p.steps[1].id, p.steps[2].id]
        e.insert(title: "  before ", at: e.insertIndex(before: true, selection: sel))
        #expect(titles(p) == ["A", "  before ", "B", "C"])
        let sel2: Set<UUID> = [p.steps[2].id]
        e.insert(title: "after", at: e.insertIndex(before: false, selection: sel2))
        #expect(titles(p) == ["A", "  before ", "B", "after", "C"])
        #expect(store.data.log.last!.name == "after" && store.data.log.last!.detail == "P")
        #expect(store.data.log[store.data.log.count - 2].name == "before")   // the log trims the name
        e.insert(title: "end", at: 999)
        #expect(titles(p).last == "end")
    }

    @Test func moveAndDelete() {
        // BUILD-011…014, BUILD-135 Removed row
        let made = StoreFactory.make(); let store = made.store
        let p = Procedure(name: "P"); p.steps = ["A", "B", "C", "D", "E"].map { ChecklistStep(title: $0) }
        store.data.procedures = [p]
        let e = stepsEngine(store, p)
        let b = p.steps[1].id, d = p.steps[3].id
        #expect(e.canMoveUp([b, d]) && e.canMoveDown([b, d]))
        #expect(e.moveUp([b, d]))
        #expect(titles(p) == ["B", "A", "D", "C", "E"])
        #expect(!e.moveUp([b]))                      // B is at the top
        let opts = e.moveToOptions([b, d])
        #expect(opts.map(\.display) == ["(Move to top)", "Before: A", "Before: C", "Before: E", "(Move to bottom)"])
        let moved = e.moveTo([b, d], target: 5)
        #expect(titles(p) == ["A", "C", "E", "B", "D"])
        #expect(moved == [b, d])
        #expect(e.delete([b, d]) == 2)
        #expect(titles(p) == ["A", "C", "E"])
        let log = store.data.log.last!
        #expect(log.action == "Removed" && log.name == "2 removed" && log.detail == "P")
        #expect(store.data.trash.isEmpty)           // builder deletes are permanent
    }

    @Test func saveAsListAndLoad() {
        // BUILD-015 / BUILD-016 / REPO-142 / REPO-147
        let made = StoreFactory.make(); let store = made.store
        let p = Procedure(name: "Bunkering")
        let s = ChecklistStep(title: "Check A"); s.done = true; s.isJob = true; s.durationMinutes = 45
        s.deadline = NetDateTime(year: 2026, month: 7, day: 10, kind: .unspecified)
        p.steps = [s]
        store.data.procedures = [p]
        let e = stepsEngine(store, p)
        let tpl = e.saveAsList(name: "  Deck  ")
        #expect(tpl.name == "Deck" && tpl.groupId == nil && tpl.items.count == 1)
        #expect(store.data.checklistTemplates.last === tpl)
        let log = store.data.log.last!
        #expect(log.kind == "Saved list" && log.name == "Deck" && log.detail == "1 item(s)")
        let n = e.apply(tpl, replace: false)
        #expect(n == 1 && p.steps.count == 2)
        let applied = p.steps[1]
        #expect(applied.title == "Check A" && !applied.done && applied.deadline == nil && applied.isJob)
        #expect(applied.durationMinutes == 45 && applied.id != s.id)
        #expect(store.data.log.last!.name == "1 added (from saved list 'Deck')" && store.data.log.last!.detail == "Bunkering")
        e.apply(tpl, replace: true)
        #expect(p.steps.count == 1 && p.steps[0].id != s.id)
    }

    @Test func subtaskEngineUsesSubtaskWording() {
        // BUILD-044 / BUILD-045
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "Parent")
        let child = TaskItem(name: "Child"); child.subtasks = [TaskItem(name: "Grandchild")]
        t.subtasks = [child]
        store.data.tasks = [t]
        let e = BuilderEngine(store: store, kind: .subtasks, logKind: "Subtask", owner: { t.name },
                              read: { t.subtasks }, write: { t.subtasks = $0 })
        e.addAll(text: "One\nTwo", replace: false)
        #expect(t.subtasks.map(\.name) == ["Child", "One", "Two"])
        #expect(t.subtasks[1].status == .todo && !t.subtasks[1].isComplete && t.subtasks[1].recurrence == .none)
        #expect(store.data.log.last!.kind == "Subtask" && store.data.log.last!.detail == "Parent")
        // Deeper levels travel with their parent.
        e.moveTo([child.id], target: 3)
        #expect(t.subtasks.last === child && child.subtasks.count == 1)
        // CaptureFromSubtasks drops grandchildren.
        let tpl = e.saveAsList(name: "Subs")
        #expect(tpl.items.map(\.title) == ["One", "Two", "Child"])
    }

    @Test func unboundEngineNoOps() {
        // BUILD-001: every action silently no-ops when not bound (owner vanished).
        let made = StoreFactory.make(); let store = made.store
        let e = BuilderEngine<ChecklistStep>(store: store, kind: .steps, logKind: "Checklist step", owner: { "" },
                                             read: { nil }, write: { _ in Issue.record("must not write") })
        #expect(!e.isBound)
        #expect(e.addAll(text: "A", replace: false).isEmpty)
        #expect(e.insert(title: "A", at: 0) == nil)
        #expect(e.delete([UUID()]) == 0)
        #expect(store.data.log.isEmpty)
    }

    @Test func stepEditorRules() {
        // BUILD-021 / 022: live writes; no-op writes do not dirty; invalid durations leave the model unchanged.
        let made = StoreFactory.make(); let store = made.store
        let s = ChecklistStep(title: "A")
        BuilderEditing.setTitle(store, s, "A")
        #expect(!store.isDirty)
        BuilderEditing.setTitle(store, s, "")
        #expect(s.title == "" && store.isDirty)
        #expect(!BuilderEditing.setDuration(store, s, text: "0"))
        #expect(s.durationMinutes == 60)
        #expect(BuilderEditing.setDuration(store, s, text: " 90 "))
        #expect(s.durationMinutes == 90)
        BuilderEditing.setDone(store, s, true)
        BuilderEditing.setJob(store, s, true)
        #expect(s.done && s.isJob)
    }

    @Test func taskEditorRangeAndStatus() {
        // BUILD-052 / 053 / 055, 06 §7.1
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "T")
        func d(_ day: Int) -> NetDateTime { NetDateTime(year: 2026, month: 7, day: day, kind: .unspecified) }
        BuilderEditing.setStart(store, t, d(10))
        #expect(t.rangeStart == d(10) && t.deadline == d(10))           // a start without deadline → one-day range
        BuilderEditing.setDeadline(store, t, d(15))
        #expect(t.rangeStart == d(10) && t.deadline == d(15))
        BuilderEditing.setStart(store, t, d(20))
        #expect(t.rangeStart == d(20) && t.deadline == d(20))           // edited start pushes the deadline
        BuilderEditing.setDeadline(store, t, d(12))
        #expect(t.rangeStart == d(12) && t.deadline == d(12))           // earlier deadline pulls the start
        BuilderEditing.setDeadline(store, t, nil)
        #expect(t.deadline == d(12))                                     // clearing refills from the start
        BuilderEditing.clearRange(store, t)
        #expect(t.rangeStart == nil && t.deadline == d(12))
        BuilderEditing.setDeadline(store, t, nil)
        #expect(t.deadline == nil)
        #expect(BuilderEditing.deadlineEarliest(t) == nil)
        BuilderEditing.setStatus(store, t, .done)
        #expect(t.isComplete)
        BuilderEditing.setStatus(store, t, .blocked)
        #expect(!t.isComplete)
        BuilderEditing.setComplete(store, t, true)
        #expect(t.status == .done)
        BuilderEditing.setComplete(store, t, false)
        #expect(t.status == .todo)
        BuilderEditing.setRecurrence(store, t, .weekly)
        #expect(t.recurrence == .weekly)
    }

    @Test func procedureStepArea() {
        // BUILD-032…036, REPO-027, Addendum #15/#16 (raw names; blank = no-op)
        let made = StoreFactory.make(); let store = made.store
        let p = Procedure(name: "Bunkering")
        let t1 = TaskItem(name: "T1"), t2 = TaskItem(name: "T2"); t1.subtasks = [TaskItem(name: "Sub")]
        let e1 = Equipment(name: "Pump")
        store.data.procedures = [p]; store.data.tasks = [t1, t2]; store.data.equipment = [e1]
        #expect(BuilderProcedureSteps.addStep(store, to: p, rawTitle: "   ") == nil)
        let s = BuilderProcedureSteps.addStep(store, to: p, rawTitle: " Step 1 ")!
        #expect(s.title == " Step 1 ")
        #expect(store.data.log.last!.kind == "Checklist step" && store.data.log.last!.detail == "Bunkering")
        #expect(BuilderProcedureSteps.taskPickerRows(store.data).map(\.display) == ["T1", "T2"])   // no subtasks
        BuilderProcedureSteps.linkTasks(store, [t2.id, t1.id], to: s)
        #expect(s.taskIds == [t2.id, t1.id])                        // selection order
        BuilderProcedureSteps.linkEquipment(store, [e1.id], to: s)
        #expect(s.equipmentIds == [e1.id])
        let nt = BuilderProcedureSteps.newLinkedTask(store, rawName: " New ", for: s)!
        #expect(nt.name == " New " && store.data.tasks.last === nt && s.taskIds.last == nt.id)
        #expect(store.data.log.last!.detail == "linked to step ' Step 1 '")
        #expect(BuilderProcedureSteps.newLinkedTask(store, rawName: "", for: s) == nil)
        let rows = BuilderProcedureSteps.rows(p)
        #expect(rows.count == 1 && rows[0].deadline == "")
        let linked = BuilderProcedureSteps.linkedSummary(store, step: s)
        #expect(linked.tasks == ["T2", "T1", " New "] && linked.equipment == ["Pump"])
        BuilderProcedureSteps.remove(store, step: s, from: p)
        #expect(p.steps.isEmpty && store.data.log.last!.action == "Removed")
        // TV: 06 §7.8 checklist export name
        #expect("checklist-\(BuilderProcedureSteps.safeName("Pump: A/B")).pdf" == "checklist-Pump_ A_B.pdf")
        #expect(BuilderProcedureSteps.safeName(nil) == "procedure")
    }

    @Test func uiFixtureLoads() throws {
        // The snapshot data folder must be a valid data file (Fixtures/ui/w-build).
        let made = StoreFactory.make()
        let data = try made.dataStore.loadFrom(Fixtures.url("ui/w-build/sample-data.json"))
        #expect(data.procedures.count == 2 && data.checklistTemplates.count == 8 && data.listGroups.count == 4)
        #expect(data.tasks.first?.subtasks.count == 4)
    }
}
