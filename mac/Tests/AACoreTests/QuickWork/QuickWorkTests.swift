// Tests for 08 §7.2 (T-QW-1…13), 08 QUICK-043…081, QUICK-231; 07 VIEW-153 / VIEW-213 (bucket cap in selection
// order); 06 BUILD-102; DECISIONS 02 Q-4 (the Ctrl+N delete goes through the Trash). Today = Tue 2026-09-29.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct QuickWorkTests {
    nonisolated static let today = CivilDate(year: 2026, month: 9, day: 29)!
    nonisolated static let en = Locale(identifier: "en_US")

    func day(_ m: Int, _ d: Int) -> NetDateTime { NetDateTime(year: 2026, month: m, day: d, kind: .unspecified) }

    func listing(_ store: AppStore, _ filter: QuickWorkFilter = .all, _ q: String = "") -> QuickWorkListing {
        QuickWorkRows.build(store: store, filter: filter, query: q, today: Self.today, locale: Self.en)
    }

    @Test func subtitles() {
        // TV: 08 T-QW-1
        let done = TaskItem(name: "Done"); done.isComplete = true; done.deadline = day(9, 25)
        done.subtasks = [TaskItem(name: "1"), TaskItem(name: "2"), TaskItem(name: "3")]
        #expect(QuickWorkRows.subtitle(done, today: Self.today)
                == "Task  \u{00B7}  \u{2713} completed  \u{00B7}  due 2026-09-25 (OVERDUE 4d)  \u{00B7}  3 subtask(s)")
        let p = Procedure(name: "P"); p.deadline = day(9, 29)
        #expect(QuickWorkRows.subtitle(p, today: Self.today) == "Procedure  \u{00B7}  due today")
        let t = TaskItem(name: "T"); t.deadline = day(10, 4)
        #expect(QuickWorkRows.subtitle(t, today: Self.today) == "Task  \u{00B7}  due 2026-10-04 (in 5d)")
        let p1 = Procedure(name: "P1"); p1.steps = [ChecklistStep(title: "s")]
        #expect(QuickWorkRows.subtitle(p1, today: Self.today) == "Procedure  \u{00B7}  1 step(s)")
    }

    @Test func sortWithoutBuckets() {
        // TV: 08 T-QW-2
        let made = StoreFactory.make(); let store = made.store
        let a = TaskItem(name: "A"); a.deadline = day(10, 1)
        let b = TaskItem(name: "B")
        let c = TaskItem(name: "C"); c.deadline = day(9, 1); c.isComplete = true
        let d = TaskItem(name: "D"); d.deadline = day(9, 30)
        store.data.tasks = [a, b, c, d]
        let l = listing(store)
        #expect(l.rows.map(\.title) == ["D", "A", "B", "C"])
        #expect(!l.isGrouped && l.groups.isEmpty)
        #expect(l.rows.last?.isDone == true)
    }

    @Test func groupingByBucketID() {
        // TV: 08 T-QW-3
        let made = StoreFactory.make(); let store = made.store
        let b1 = QuickBucket(id: UUID(netString: "00000000-0000-0000-0000-000000000002")!, name: "Deck")
        let b2 = QuickBucket(id: UUID(netString: "00000000-0000-0000-0000-000000000001")!, name: "deck")
        let b3 = QuickBucket(name: "Engine")
        store.data.quickBuckets = [b1, b2, b3]
        let x = TaskItem(name: "X"); x.bucketIds = [b2.id, b1.id]
        let y = TaskItem(name: "Y")
        store.data.tasks = [x, y]
        let l = listing(store)
        #expect(l.isGrouped)
        #expect(l.groups.map(\.name) == ["deck", "Deck", "(No bucket)"])
        #expect(l.groups.map(\.key) == [b2.id.netString, b1.id.netString, ""])
        #expect(l.groups[0].rows.map(\.title) == ["X"] && l.groups[1].rows.map(\.title) == ["X"])
        #expect(l.groups[2].rows.map(\.title) == ["Y"])
        #expect(l.countLine == "2 item(s).")
        #expect(l.groups[0].header == "\u{1FAA3} deck (1)")
        #expect(Set(l.rows.map(\.id)).count == 3)
    }

    @Test func staleBucketID() {
        // TV: 08 T-QW-4
        let made = StoreFactory.make(); let store = made.store
        store.data.quickBuckets = [QuickBucket(name: "Deck")]
        let t = TaskItem(name: "T"); t.bucketIds = [UUID(), UUID()]
        store.data.tasks = [t]
        let l = listing(store)
        #expect(l.groups.map(\.name) == ["(No bucket)"])
    }

    @Test func countLine() {
        // TV: 08 T-QW-5
        let made = StoreFactory.make(); let store = made.store
        store.data.tasks = (0..<12).map { k in let t = TaskItem(name: "t\(k)"); t.isComplete = k < 3; return t }
        #expect(listing(store).countLine == "12 item(s) \u{2014} 9 active, 3 completed/done.")
        for t in store.data.tasks { t.isComplete = false }
        #expect(listing(store).countLine == "12 item(s).")
    }

    @Test func filterAndSearch() {
        // TV: 08 QUICK-043 (all items incl. completed; name contains the trimmed query, OrdinalIgnoreCase)
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "Main PUMP overhaul"); t.isComplete = true
        let p = Procedure(name: "Pump room entry")
        let blank = TaskItem(name: "  ")
        store.data.tasks = [t, blank]; store.data.procedures = [p]
        #expect(listing(store, .all, "  pump ").rows.map(\.title) == ["Pump room entry", "Main PUMP overhaul"])
        #expect(listing(store, .tasks).rows.map(\.title).contains("(unnamed)"))
        #expect(listing(store, .procedures).rows.map(\.kind) == [.procedure])
    }

    @Test func tileProgressAndChip() {
        // TV: 08 T-QW-6
        let t = TaskItem(name: "T"); let s1 = TaskItem(name: "1"); s1.isComplete = true
        t.subtasks = [s1, TaskItem(name: "2"), TaskItem(name: "3")]
        #expect(QuickWorkRows.tile(t, today: Self.today).progressText == "1/3 subtasks done")
        #expect(QuickWorkRows.tile(t, today: Self.today).fraction == 1.0 / 3.0)
        let p = Procedure(name: "P"); p.steps = [ChecklistStep(title: "s")]
        #expect(QuickWorkRows.tile(p, today: Self.today).progressText == "0/1 step done")
        let done = TaskItem(name: "D"); done.isComplete = true
        #expect(QuickWorkRows.tile(done, today: Self.today).progressText == "completed")
        let active = TaskItem(name: "A"); active.deadline = day(9, 28)
        let ta = QuickWorkRows.tile(active, today: Self.today)
        #expect(ta.progressText == "no items yet" && ta.deadlineText == "OVERDUE 09-28" && ta.deadlineIsOverdue)
        active.isComplete = true
        let td = QuickWorkRows.tile(active, today: Self.today)
        #expect(td.deadlineText == "due 09-28" && !td.deadlineIsOverdue)
    }

    @Test func deadlineRangeCoercionAgainstTheModel() {
        // TV: 08 T-QW-7
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "T"); t.deadline = day(10, 5)
        store.data.tasks = [t]
        QuickWorkActions.setRangeStart(t, picked: day(10, 8), store: store)
        #expect(t.rangeStart == day(10, 8) && t.deadline == day(10, 8))
        QuickWorkActions.setDeadline(t, picked: day(10, 1), store: store)
        #expect(t.rangeStart == day(10, 1) && t.deadline == day(10, 1))
        t.rangeStart = day(10, 1); t.deadline = day(10, 5)
        QuickWorkActions.setDeadline(t, picked: nil, store: store)
        #expect(t.deadline == day(10, 1) && t.rangeStart == day(10, 1))
        QuickWorkActions.setRangeStart(t, picked: nil, store: store)
        #expect(t.rangeStart == nil && t.deadline == day(10, 1))
        #expect(store.isDirty)
    }

    @Test func batchDeadlineAndDone() {
        // TV: 08 T-QW-8 (through F2's BatchDeadline / BatchDone as the context menu uses them)
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "T"); t.rangeStart = day(9, 25); t.deadline = day(9, 30)
        let p = Procedure(name: "P"); p.status = .inProgress
        store.data.tasks = [t]; store.data.procedures = [p]
        #expect(BatchDeadline.setDeadlineAll([t], date: day(9, 20)) == 1)
        #expect(t.rangeStart == day(9, 20) && t.deadline == day(9, 20))
        #expect(BatchDeadline.setDeadlineAll([t], date: nil) == 1)
        #expect(t.rangeStart == nil && t.deadline == nil)
        #expect(BatchDone.setDoneAll([p], done: false) == 0 && p.status == .inProgress)
        #expect(QuickWorkText.setDeadlinePrompt(1) == "Apply one deadline to 1 selected item:")
        #expect(QuickWorkText.setDeadlinePrompt(3) == "Apply one deadline to 3 selected items:")
    }

    @Test func bulkAdd() {
        // TV: 08 T-QW-9
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "Owner"); t.subtasks = [TaskItem(name: "keep")]
        store.data.tasks = [t]
        #expect(QuickWorkActions.bulkLines("  a \r\n\r\nb\n  \n c") == ["a", "b", "c"])
        #expect(QuickWorkActions.bulkAdd("  a \r\n\r\nb\n  \n c", replace: false, to: t, store: store) == 3)
        #expect(t.subtasks.map(\.name) == ["keep", "a", "b", "c"])
        let log = store.data.log.last
        #expect(log?.action == "Added" && log?.kind == "Subtask" && log?.name == "3 added (bulk)" && log?.detail == "Owner")
        #expect(QuickWorkActions.bulkAdd(" \n ", replace: true, to: t, store: store) == 0 && t.subtasks.count == 4)
        let p = Procedure(name: "P"); p.steps = [ChecklistStep(title: "old")]
        store.data.procedures = [p]
        #expect(QuickWorkActions.bulkAdd("x\ny", replace: true, to: p, store: store) == 2)
        #expect(p.steps.map(\.title) == ["x", "y"] && store.data.log.last?.kind == "Step")
    }

    @Test func moveSemantics() {
        // TV: 08 T-QW-10; QUICK-078
        let s = ["s0", "s1", "s2", "s3"]
        #expect(QuickWorkActions.moved(s, selected: [1, 3], up: true) == ["s1", "s0", "s3", "s2"])
        #expect(QuickWorkActions.moved(s, selected: [0, 2], up: true) == nil)
        #expect(QuickWorkActions.moved(s, selected: [3], up: false) == nil)
        #expect(QuickWorkActions.moved(s, selected: [0, 1], up: false) == ["s2", "s0", "s1", "s3"])
        #expect(QuickWorkActions.moved(s, selected: [], up: true) == nil)

        let made = StoreFactory.make(); let store = made.store
        let p = Procedure(name: "P"); p.steps = s.map { ChecklistStep(title: $0) }
        store.data.procedures = [p]
        #expect(QuickWorkActions.moveChildren([p.steps[1].id, p.steps[3].id], in: p, up: true, store: store))
        #expect(p.steps.map(\.title) == ["s1", "s0", "s3", "s2"])
        QuickWorkActions.moveChildren(fromOffsets: IndexSet([0]), toOffset: 4, in: p, store: store)
        #expect(p.steps.map(\.title) == ["s0", "s3", "s2", "s1"])
    }

    @Test func bucketCapInSelectionOrder() {
        // TV: 08 T-QW-11; 07 VIEW-213
        let made = StoreFactory.make(); let store = made.store
        let b1 = QuickBucket(name: "b1", category: "Deck"), b2 = QuickBucket(name: "b2"), b3 = QuickBucket(name: "")
        store.data.quickBuckets = [b1, b2, b3]
        let t = TaskItem(name: "T"); t.bucketIds = [b2.id]
        #expect(QuickWorkActions.preselectedBuckets(for: t, store: store) == [b2.id])
        #expect(QuickWorkActions.bucketChoices(store: store).map(\.display) == ["b1  \u{00B7}  Deck", "b2", "(unnamed)"])
        let r = QuickWorkActions.applyBuckets([b3.id, b1.id, b2.id], to: t)
        #expect(r.capped && r.ids == [b3.id, b1.id] && t.bucketIds == [b3.id, b1.id])
        #expect(QuickWorkActions.applyBuckets([], to: t).ids.isEmpty && t.bucketIds.isEmpty)
        #expect(QuickWorkText.bucketPrompt("T") == "Sort 'T' into buckets (pick up to 2)")
        let step = ChecklistStep(title: "")
        #expect(QuickWorkText.bucketPrompt(step.title) == "Sort '' into buckets (pick up to 2)")
        t.bucketIds = [b1.id]
        QuickWorkActions.removeFromBuckets(t)
        #expect(t.bucketIds.isEmpty)
    }

    @Test func pinPruning() {
        // TV: 08 T-QW-12; QUICK-061 ordering
        let made = StoreFactory.make(); let store = made.store
        let t1 = TaskItem(name: "beta"), p1 = Procedure(name: "Alpha"); p1.status = .done
        let t2 = TaskItem(name: "alpha")
        let e = Equipment(name: "not pinnable")
        store.data.tasks = [t1, t2]; store.data.procedures = [p1]; store.data.equipment = [e]
        store.data.ui.quickViewPinIds = [t1.id, UUID(), p1.id, e.id, t2.id]
        #expect(!store.isDirty)
        let tiles = QuickWorkRows.pinnedTiles(store: store, today: Self.today)
        #expect(store.data.ui.quickViewPinIds == [t1.id, p1.id, t2.id])
        #expect(store.isDirty)
        #expect(tiles.map(\.name) == ["alpha", "beta", "Alpha"])
        #expect(QuickWorkActions.togglePin(t1.id, store: store) == false)
        #expect(QuickWorkActions.togglePin(t1.id, store: store) == true)
        #expect(store.data.ui.quickViewPinIds.last == t1.id)
    }

    @Test func deleteGoesThroughTheTrash() throws {
        // TV: 08 T-QW-13 adapted by DECISIONS 02 Q-4 (Trash, undoable; pin removed; Put Back restores the links)
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "T"); let e = Equipment(name: "E"); e.taskIds = [t.id]
        store.data.tasks = [t]; store.data.equipment = [e]; store.data.ui.quickViewPinIds = [t.id]
        let entry = try #require(QuickWorkActions.moveToTrash(t, store: store))
        #expect(store.data.tasks.isEmpty && store.data.ui.quickViewPinIds.isEmpty)
        #expect(store.data.trash.count == 1 && entry.itemId == t.id)
        #expect(store.data.log.last?.action == "Removed" && store.data.log.last?.detail == "moved to Trash")
        #expect(store.undoLastDelete() == [.task])
        #expect(store.data.tasks.map(\.id) == [t.id] && e.taskIds == [t.id])
        #expect(QuickWorkText.deleteMessage("T").hasPrefix("Delete 'T' and everything under it? This removes it everywhere"))
    }

    @Test func createAddDeleteChildrenAndLogs() {
        // TV: 08 QUICK-055, QUICK-077 and the §4.5 log lines
        let made = StoreFactory.make(); let store = made.store
        #expect(QuickWorkActions.createTask(named: "   ", store: store) == nil)
        let t = QuickWorkActions.createTask(named: " Fire drill ", store: store)
        #expect(t?.name == " Fire drill " && store.data.tasks.count == 1)
        #expect(store.data.log.last?.kind == "Task" && store.data.log.last?.name == "Fire drill")
        let p = QuickWorkActions.createProcedure(named: "Bunkering", store: store)!
        #expect(store.data.log.last?.kind == "Procedure")
        let sid = QuickWorkActions.addChild(named: "Hoses", to: p, store: store)
        #expect(sid == p.steps.first?.id)
        #expect(store.data.log.last?.kind == "Step" && store.data.log.last?.name == "Hoses" && store.data.log.last?.detail == "Bunkering")
        _ = QuickWorkActions.addChild(named: "Sub", to: t!, store: store)
        #expect(store.data.log.last?.kind == "Subtask" && store.data.log.last?.detail == " Fire drill ")
        #expect(QuickWorkActions.deleteChildren([p.steps[0].id], from: p, store: store) == 1)
        #expect(p.steps.isEmpty && store.data.log.last?.action == "Removed" && store.data.log.last?.name == "1 removed")
        #expect(QuickWorkActions.deleteChildren([UUID()], from: p, store: store) == 0)
        #expect(QuickWorkText.deleteChildrenMessage(2, noun: "step") == "Delete 2 step(s)?")
    }

    @Test func saveAndInsertSavedLists() throws {
        // TV: 08 QUICK-080, QUICK-081; 06 BUILD-102
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "Owner")
        let a = TaskItem(name: "a"); a.deadline = day(10, 1); a.isComplete = true; a.durationMinutes = 30
        t.subtasks = [a, TaskItem(name: "b")]
        store.data.tasks = [t]
        let tpl = try #require(QuickWorkActions.saveAsList(named: "Drill list", from: t, store: store))
        #expect(store.data.checklistTemplates.last === tpl && tpl.items.map(\.title) == ["a", "b"])
        #expect(tpl.items[0].durationMinutes == 30)
        #expect(store.data.log.last?.kind == "Saved list" && store.data.log.last?.detail == "2 item(s)")
        #expect(QuickWorkText.savedList("Drill list", 2) == "Saved 'Drill list' (2 item(s)). You can reuse it from any checklist builder.")

        let p = Procedure(name: "P"); p.steps = [ChecklistStep(title: "old")]
        store.data.procedures = [p]
        #expect(QuickWorkActions.insertList(tpl, into: p, replace: false, store: store) == 2)
        #expect(p.steps.map(\.title) == ["old", "a", "b"] && p.steps.allSatisfy { !$0.done && $0.deadline == nil })
        #expect(store.data.log.last?.kind == "Checklist step"
                && store.data.log.last?.name == "2 added (from saved list 'Drill list')" && store.data.log.last?.detail == "P")
        #expect(QuickWorkActions.insertList(tpl, into: t, replace: true, store: store) == 2)
        #expect(t.subtasks.map(\.name) == ["a", "b"] && t.subtasks.allSatisfy { !$0.isComplete && $0.deadline == nil })
        #expect(store.data.log.last?.kind == "Subtask")
    }

    @Test func statusRecurrenceNameAndTileDone() {
        // TV: 08 QUICK-062 (tile Done), QUICK-074 (status syncs IsComplete)
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "T"); let p = Procedure(name: "P"); p.status = .blocked
        store.data.tasks = [t]; store.data.procedures = [p]
        QuickWorkActions.setStatus(t, .done, store: store)
        #expect(t.isComplete)
        QuickWorkActions.setItemDone(t, done: false, store: store)
        #expect(!t.isComplete && t.status == .todo)
        QuickWorkActions.setItemDone(p, done: true, store: store)
        #expect(p.status == .done)
        QuickWorkActions.setItemDone(p, done: false, store: store)
        #expect(p.status == .todo)
        QuickWorkActions.setRecurrence(p, .weekly, store: store)
        #expect(QuickWorkRows.recurrence(p) == .weekly)
        QuickWorkActions.setName(t, "Renamed", store: store)
        #expect(t.name == "Renamed")
    }
}
