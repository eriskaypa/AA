// Tests for 07 §A.7 picker vectors P5 / P6 / P12 / P13, the corrected bucket vectors K7b…K7g (through the quick-work
// bucket path: `QuickWorkActions.preselectedBuckets` → the picker's `ShellPickerSelection` → `applyBuckets`), the
// saved-list add SL2 (picker + `BoardSavedListAdd.apply`), 07 §8.2 B9 (Board drag to Done → save → recurrence
// reconcile), and 01 DATA-174 for the Trash buttons (read-only copy help text).
import Foundation
import Testing
@testable import AACore

/// Drives the picker exactly as `DialogPresenter.pickItems` does: preselected tags → candidate indices, then the
/// sheet's `ShellPickerSelection`, then the result mapped back to tags.
@MainActor
private struct PickerDriver<Tag: Hashable> {
    let tags: [Tag]
    var sel: ShellPickerSelection

    init(rows: [(display: String, tag: Tag)], preselected: [Tag], candidateOrder: Bool = false) {
        tags = rows.map(\.tag)
        let pre = Set(preselected)
        let idx = Set(rows.indices.filter { pre.contains(rows[$0].tag) })
        sel = ShellPickerSelection(displays: rows.map(\.display), preselected: idx, single: false)
        self.candidateOrder = candidateOrder
    }

    let candidateOrder: Bool

    mutating func tick(_ tag: Tag) { if let i = tags.firstIndex(of: tag) { sel.toggle(i) } }
    mutating func query(_ q: String) { sel.query = q }
    var ok: [Tag] { sel.result(candidateOrder: candidateOrder).map { tags[$0] } }
}

@MainActor
@Suite struct QuickWorkPickerVectorTests {
    // Candidates [A, B, C, D] = "Alpha", "Bravo", "Charlie", "Delta" (07 §A.7).
    let displays = ["Alpha", "Bravo", "Charlie", "Delta"]

    @Test func p5HiddenFirstPickStaysFirst() {
        // TV: 07 P5
        var s = ShellPickerSelection(displays: displays, preselected: [], single: false)
        s.toggle(2)                                   // C
        s.query = "elt"
        #expect(s.visible == [3])
        s.toggle(3)                                   // D
        s.query = "alp"
        #expect(s.visible == [0])
        s.toggle(0)                                   // A
        s.query = ""
        #expect(s.result(candidateOrder: false) == [2, 3, 0])
    }

    @Test func p6PreselectNotACandidate() {
        // TV: 07 P6 — a preselected tag that is not a candidate maps to no index.
        var p = PickerDriver(rows: displays.map { ($0, $0) }, preselected: ["X"])
        #expect(p.sel.order.isEmpty)
        #expect(p.ok.isEmpty)
        p.query("")
        #expect(p.ok.isEmpty)
    }

    @Test func p12SpacesOnlyShowsAll() {
        // TV: 07 P12
        var s = ShellPickerSelection(displays: displays, preselected: [], single: false)
        s.query = "  "
        #expect(s.visible == [0, 1, 2, 3])
    }

    @Test func p13OrdinalIgnoreCase() {
        // TV: 07 P13
        var s = ShellPickerSelection(displays: displays, preselected: [], single: false)
        s.query = "ALPHA"
        #expect(s.visible == [0])
    }

    // MARK: Buckets (07 K7b…K7g; QuickBuckets = [b1 "Bridge", b2 "Engine room", b3 "Galley"])

    private struct Buckets {
        let store: AppStore
        let made: StoreFactory.Made
        let b1: QuickBucket, b2: QuickBucket, b3: QuickBucket
    }

    private func buckets() -> Buckets {
        let made = StoreFactory.make()
        let b1 = QuickBucket(name: "Bridge"), b2 = QuickBucket(name: "Engine room"), b3 = QuickBucket(name: "Galley")
        made.store.data.quickBuckets = [b1, b2, b3]
        return Buckets(store: made.store, made: made, b1: b1, b2: b2, b3: b3)
    }

    /// The quick-work flow (`QuickWorkFlows.sortIntoBuckets`): rows, preselect, picker steps, live filter, apply.
    private func run(_ t: TaskItem, _ k: Buckets, steps: (inout PickerDriver<UUID>) -> Void) -> (ids: [UUID], capped: Bool) {
        let rows = QuickWorkActions.bucketChoices(store: k.store).map { (display: $0.display, tag: $0.id) }
        var p = PickerDriver(rows: rows, preselected: QuickWorkActions.preselectedBuckets(for: t, store: k.store))
        steps(&p)
        let live = Set(k.store.data.quickBuckets.map(\.id))
        return QuickWorkActions.applyBuckets(p.ok.filter { live.contains($0) }, to: t)
    }

    @Test func k7bUnchangedOkNormalises() {
        // TV: 07 K7b — [b2, b1], OK unchanged → no message, [b1, b2] (the JSON array changes, so Flash Sync ships it)
        let k = buckets()
        let t = TaskItem(name: "T"); t.bucketIds = [k.b2.id, k.b1.id]
        let before = t.bucketIds
        let r = run(t, k) { _ in }
        #expect(!r.capped)
        #expect(t.bucketIds == [k.b1.id, k.b2.id])
        #expect(t.bucketIds != before)
    }

    @Test func k7cThirdTickDiscarded() {
        // TV: 07 K7c
        let k = buckets()
        let t = TaskItem(name: "T"); t.bucketIds = [k.b1.id, k.b2.id]
        let r = run(t, k) { $0.tick(k.b3.id) }
        #expect(r.capped)
        #expect(t.bucketIds == [k.b1.id, k.b2.id])
    }

    @Test func k7dSwapWithinCap() {
        // TV: 07 K7d
        let k = buckets()
        let t = TaskItem(name: "T"); t.bucketIds = [k.b1.id, k.b2.id]
        let r = run(t, k) { $0.tick(k.b2.id); $0.tick(k.b3.id) }
        #expect(!r.capped)
        #expect(t.bucketIds == [k.b1.id, k.b3.id])
    }

    @Test func k7eMergedThreeBuckets() {
        // TV: 07 K7e — merged data with three buckets: preselect in list order, capped to the first two.
        let k = buckets()
        let t = TaskItem(name: "T"); t.bucketIds = [k.b3.id, k.b1.id, k.b2.id]
        let r = run(t, k) { _ in }
        #expect(r.capped)
        #expect(QuickWorkText.bucketCap == "An item can be in at most two buckets \u{2014} keeping the first two you picked.")
        #expect(t.bucketIds == [k.b1.id, k.b2.id])
    }

    @Test func k7fDanglingIdDropped() {
        // TV: 07 K7f
        let k = buckets()
        let t = TaskItem(name: "T"); t.bucketIds = [UUID(), k.b2.id]
        #expect(QuickWorkActions.preselectedBuckets(for: t, store: k.store) == [k.b2.id])
        let r = run(t, k) { _ in }
        #expect(!r.capped)
        #expect(t.bucketIds == [k.b2.id])
    }

    @Test func k7gHiddenSelectionKeptAcrossSearch() {
        // TV: 07 K7g (Mac) — b1 hidden by the "gal" query is kept: [b1, b3] (Windows dropped it).
        let k = buckets()
        let t = TaskItem(name: "T"); t.bucketIds = [k.b1.id]
        let r = run(t, k) { p in
            p.query("gal")
            #expect(p.sel.visible == [2])
            p.tick(k.b3.id)
            #expect(p.sel.footer == "2 selected \u{00B7} 1 hidden by search")
            p.query("")
        }
        #expect(!r.capped)
        #expect(t.bucketIds == [k.b1.id, k.b3.id])
    }

    // MARK: Saved-list add (07 SL2)

    @Test func sl2TicksUnderDifferentSearchesAllAdded() {
        // TV: 07 SL2 (Mac) — Pump ticked under "pump", Winch under "winch": both added, in tick order.
        let d = AppData()
        let engine = ChecklistTemplate(name: "Engine", items: [ChecklistTemplateItem(title: "Pump"),
                                                               ChecklistTemplateItem(title: "Valve")])
        let deck = ChecklistTemplate(name: "Deck", items: [ChecklistTemplateItem(title: "Winch", durationMinutes: 30,
                                                                                 isJob: true)])
        d.checklistTemplates = [engine, deck]
        let existing = TaskItem(name: "existing")
        d.tasks = [existing]
        let made = StoreFactory.make(data: d)
        guard case .rows(let rows) = BoardSavedListAdd.candidates(made.store.data) else {
            Issue.record("expected rows"); return
        }
        #expect(rows.map(\.display) == ["Engine  \u{203A}  Pump", "Engine  \u{203A}  Valve",
                                        "Deck  \u{203A}  Winch   \u{00B7} schedulable"])
        var p = PickerDriver(rows: rows, preselected: [])
        p.query("pump")
        #expect(p.sel.visible == [0])
        p.tick(rows[0].tag)
        p.query("winch")
        #expect(p.sel.visible == [2])
        p.tick(rows[2].tag)
        let created = BoardSavedListAdd.apply(p.ok, store: made.store)
        #expect(created.map(\.name) == ["Pump", "Winch"])
        #expect(made.store.data.tasks.map(\.name) == ["existing", "Pump", "Winch"])
    }

    // MARK: Board (07 B9)

    @Test func b9DragRecurringToDoneSavesAndSpawnsNext() throws {
        // TV: 07 B9 — Status 3, IsComplete true, saved immediately; the save's recurrence reconcile (SHELL-055 /
        // REPO-063, run by AppEnvironment after every save) creates the next occurrence.
        let t = TaskItem(name: "Weekly rounds")
        t.deadline = NetDateTime.calendarDate(CivilDate(iso: "2026-10-02")!)
        t.recurrence = .weekly
        let d = AppData(); d.tasks = [t]
        let made = StoreFactory.make(data: d)
        let store = made.store
        #expect(BoardModel.setStatus(t, .done))
        #expect(t.status.rawValue == 3 && t.isComplete)
        try store.save()
        #expect(!store.isDirty)
        #expect(store.reconcileRecurrences(today: CivilDate(iso: "2026-10-03")!))
        #expect(store.data.tasks.count == 2)
        let next = try #require(store.data.tasks.last)
        #expect(next !== t && next.id != t.id)
        #expect(next.name == "Weekly rounds" && next.status == .todo && !next.isComplete)
        #expect(next.deadline?.civilDate == CivilDate(iso: "2026-10-09")!)
        #expect(t.recurrenceSpawned)
        // A second save + reconcile does not spawn again.
        try store.save()
        #expect(!store.reconcileRecurrences(today: CivilDate(iso: "2026-10-03")!))
        #expect(store.data.tasks.count == 2)
    }

    // MARK: Trash in a read-only copy (01 DATA-174)

    @Test func trashButtonsHelpInReadOnlyCopy() {
        // TV: 01 DATA-174 — Trash ▸ Restore / Delete Permanently / Empty Trash: "Not available in a read-only copy of AA."
        #expect(TrashText.help(TrashText.putBackHelp, readOnly: false) == TrashText.putBackHelp)
        for h in [TrashText.putBackHelp, TrashText.deleteImmediatelyHelp, TrashText.emptyTrashHelp] {
            #expect(TrashText.help(h, readOnly: true) == "Not available in a read-only copy of AA.")
        }
    }
}
