// Tests for 02 §2.G (REPO-060…064), 01 §3.18 / §7.11 (DATA-120/121); DECISIONS Q-6 / ARCHITECTURE.md §3.4: every
// generated or shifted date is `.unspecified` (supersedes 02 T-REC-7's "Local" and 01 §7.11's "Local").
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct RepoRecurrenceTests {
    static let clock = FixedClock(local: "2026-09-29T14:05:00", zone: TZ.athens)

    private func day(_ s: String) -> NetDateTime { NetDateTime.calendarDate(CivilDate(iso: s)!) }
    private func local(_ s: String) -> NetDateTime { NetDateTime(parsing: s, zone: TZ.athens)! }

    @Test func nextOccurrenceArithmetic() {
        // TV: 02 T-REC-1…4
        #expect(AppStore.nextOccurrence(from: day("2026-01-31"), .monthly).format(.isoDate) == "2026-02-28")
        #expect(AppStore.nextOccurrence(from: day("2024-02-29"), .yearly).format(.isoDate) == "2025-02-28")
        #expect(AppStore.nextOccurrence(from: day("2026-12-31"), .daily).format(.isoDate) == "2027-01-01")
        #expect(AppStore.nextOccurrence(from: day("2026-09-29"), .weekly).format(.isoDate) == "2026-10-06")
        #expect(AppStore.nextOccurrence(from: day("2026-09-29"), .none) == day("2026-09-29"))
        let t = AppStore.nextOccurrence(from: NetDateTime(year: 2026, month: 3, day: 31, hour: 9, minute: 30, kind: .unspecified), .monthly)
        #expect(t.format(.isoMinute) == "2026-04-30 09:30")
        // DECISIONS Q-6: the result is a calendar date even from a Local / read-back value.
        let fromLocal = AppStore.nextOccurrence(from: local("2026-09-29T00:00:00+03:00"), .daily)
        #expect(fromLocal.kind == .unspecified && fromLocal.originalText == nil)
        #expect(fromLocal.jsonString(zone: TZ.athens) == "2026-09-30T00:00:00")
    }

    @Test func monthlyTaskWithRangeAndSubtasks() throws {
        // TV: 02 T-REC-5, T-REC-6; 01 §7.11 recurrence bullets
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        let t = TaskItem(name: "Fire drill")
        t.recurrence = .monthly; t.deadline = day("2026-01-31"); t.rangeStart = day("2026-01-29")
        t.scheduledStart = NetDateTime.calendarDateTime(CivilDate(iso: "2026-01-30")!, minutes: 600)
        t.container.files = [FileItem(name: "sop.pdf", path: "files/x_sop.pdf")]
        let s = TaskItem(name: "S"); s.deadline = day("2026-01-30"); s.rangeStart = day("2026-01-28"); s.isComplete = true
        let u = TaskItem(name: "U"); u.status = .inProgress
        t.subtasks = [s, u]
        t.isComplete = true
        store.data.tasks = [t]

        #expect(store.reconcileRecurrences())
        #expect(t.recurrenceSpawned && t.isComplete && t.deadline?.format(.isoDate) == "2026-01-31")
        #expect(store.data.tasks.count == 2)
        let c = store.data.tasks[1]
        #expect(c.id != t.id && c.container.id != t.container.id)
        #expect(c.container.files.map(\.id) == t.container.files.map(\.id))
        #expect(c.deadline?.format(.isoDate) == "2026-02-28" && c.deadline?.kind == .unspecified)
        #expect(c.rangeStart?.format(.isoDate) == "2026-02-26" && c.rangeStart?.kind == .unspecified)
        #expect(!c.isComplete && c.status == .todo && !c.recurrenceSpawned && c.scheduledStart == nil)
        let s2 = c.subtasks[0], u2 = c.subtasks[1]
        #expect(s2.id != s.id && s2.deadline?.format(.isoDate) == "2026-02-27" && s2.rangeStart?.format(.isoDate) == "2026-02-25")
        #expect(s2.status == .todo && s2.deadline?.kind == .unspecified)
        #expect(u2.id != u.id && u2.status == .inProgress)
        let log = try #require(store.data.log.last)
        #expect(log.action == "Added" && log.kind == "Task (recurring)" && log.name == "Fire drill")
        #expect(log.detail == "next Monthly occurrence \u{2192} 2026-02-28")
        #expect(store.isDirty)
        #expect(!store.reconcileRecurrences())
        #expect(store.data.tasks.count == 2)
        // The written JSON of the clone's dates has no offset (calendar dates).
        let json = try JSONWriter.string(.object(c.toJSON(options: JSONEncodeOptions(zone: TZ.athens))))
        #expect(json.contains("\"Deadline\":\"2026-02-28T00:00:00\""))
    }

    @Test func undatedDailyTaskUsesToday() {
        // TV: 02 T-REC-7 (as amended: the generated deadline is Unspecified, not Local); 01 §7.11
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        let t = TaskItem(name: "Daily"); t.recurrence = .daily
        let sub = TaskItem(name: "sub"); sub.deadline = day("2026-09-01"); t.subtasks = [sub]
        t.isComplete = true
        store.data.tasks = [t]
        #expect(store.reconcileRecurrences(today: CivilDate(iso: "2026-09-29")))
        let c = store.data.tasks[1]
        #expect(c.deadline?.format(.isoDate) == "2026-09-30" && c.deadline?.kind == .unspecified)
        #expect(c.subtasks[0].deadline?.format(.isoDate) == "2026-09-01")
        #expect(c.rangeStart == nil)
        // Default `today` comes from the store clock.
        let t2 = TaskItem(name: "Daily2"); t2.recurrence = .daily; t2.isComplete = true
        store.data.tasks.append(t2)
        #expect(store.reconcileRecurrences())
        #expect(store.data.tasks.last?.deadline?.format(.isoDate) == "2026-09-30")
    }

    @Test func degenerateRangeAndWeekly() {
        // TV: 02 T-REC-8; 01 §7.11 ranged weekly (S=10-01, D=10-05 → 10-08/10-12, subtask 10-03 → 10-10)
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        let t = TaskItem(name: "R"); t.recurrence = .weekly; t.rangeStart = day("2026-10-05"); t.deadline = day("2026-10-05")
        t.isComplete = true
        let w = TaskItem(name: "W"); w.recurrence = .weekly; w.rangeStart = day("2026-10-01"); w.deadline = day("2026-10-05")
        let ws = TaskItem(name: "ws"); ws.deadline = day("2026-10-03"); w.subtasks = [ws]
        w.isComplete = true
        store.data.tasks = [t, w]
        #expect(store.reconcileRecurrences())
        let ct = store.data.tasks[2], cw = store.data.tasks[3]
        #expect(ct.rangeStart == nil && ct.deadline?.format(.isoDate) == "2026-10-12")
        #expect(cw.rangeStart?.format(.isoDate) == "2026-10-08" && cw.deadline?.format(.isoDate) == "2026-10-12")
        #expect(cw.subtasks[0].deadline?.format(.isoDate) == "2026-10-10")
    }

    @Test func procedureRecurrence() throws {
        // TV: 02 T-REC-9
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        let p = Procedure(name: "Weekly checks"); p.recurrence = .weekly; p.deadline = day("2026-09-28"); p.status = .done
        let task = UUID()
        let s1 = ChecklistStep(title: "one"); s1.done = true; s1.deadline = day("2026-09-27"); s1.taskIds = [task]
        s1.scheduledStart = day("2026-09-26")
        let s2 = ChecklistStep(title: "two")
        p.steps = [s1, s2]
        store.data.procedures = [p]
        #expect(store.reconcileRecurrences())
        #expect(p.recurrenceSpawned)
        let c = store.data.procedures[1]
        #expect(c.status == .todo && c.deadline?.format(.isoDate) == "2026-10-05" && c.id != p.id)
        #expect(c.steps[0].id != s1.id && !c.steps[0].done && c.steps[0].deadline?.format(.isoDate) == "2026-10-04")
        #expect(c.steps[0].taskIds == [task] && c.steps[0].scheduledStart == nil)
        #expect(c.steps[0].container.id != s1.container.id)
        #expect(c.steps[1].deadline == nil)
        #expect(store.data.log.last?.detail == "next Weekly occurrence \u{2192} 2026-10-05")
        #expect(store.data.log.last?.kind == "Procedure (recurring)")
    }

    @Test func nothingSpawnsWhenNotEligible() {
        // TV: 02 T-REC-10, T-REC-11, T-REC-12
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        let spawned = TaskItem(name: "A"); spawned.recurrence = .monthly; spawned.isComplete = true; spawned.recurrenceSpawned = true
        let open = TaskItem(name: "B"); open.recurrence = .monthly
        let parent = TaskItem(name: "C"); let sub = TaskItem(name: "sub"); sub.recurrence = .daily; sub.isComplete = true
        parent.subtasks = [sub]
        store.data.tasks = [spawned, open, parent]
        #expect(!store.reconcileRecurrences())
        #expect(store.data.tasks.count == 3 && !store.isDirty)
    }

    @Test func clonesAreNotRelinked() {
        // TV: 02 T-REC-13, T-REC-14 (02 §8 D-4 / Q-2: parity)
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        let x = Equipment(name: "X")
        let src = TaskItem(name: "Src"); src.recurrence = .daily; src.deadline = day("2026-09-29")
        store.data.equipment = [x]; store.data.tasks = [src]
        store.addRelation(src, x)
        x.taskIds = [src.id]
        store.data.ui.quickViewPinIds = [src.id]
        src.isComplete = true
        #expect(store.reconcileRecurrences())
        let clone = store.data.tasks[1]
        #expect(clone.relatedIds == [x.id])
        #expect(x.relatedIds == [src.id])
        #expect(store.referencedBy(x).map(\.id).contains(clone.id))
        #expect(x.taskIds == [src.id] && store.data.ui.quickViewPinIds == [src.id])
    }

    @Test func migrationBlocksRetroSpawn() throws {
        // TV: 02 T-REC-15; 01 §7.11 migration bullet (F1's loader migration + F2's reconcile)
        let text = #"{"Tasks":[{"Id":"00000000-0000-0000-0000-000000000001","Name":"M","Recurrence":3,"IsComplete":true,"Status":3,"Subtasks":[{"Id":"00000000-0000-0000-0000-000000000002","Name":"W","Recurrence":2,"IsComplete":true,"Status":3}]}],"Procedures":[{"Id":"00000000-0000-0000-0000-000000000003","Name":"P","Recurrence":2,"Status":3}]}"#
        let made = StoreFactory.make(clock: Self.clock)
        let url = try made.folder.write("legacy-v0.json", text)
        let loaded = try made.dataStore.loadFrom(url)
        let store = AppStore(dataStore: made.dataStore, data: loaded, clock: Self.clock)
        #expect(store.data.tasks[0].recurrenceSpawned && store.data.tasks[0].subtasks[0].recurrenceSpawned)
        #expect(store.data.procedures[0].recurrenceSpawned)
        #expect(!store.reconcileRecurrences())
    }
}
