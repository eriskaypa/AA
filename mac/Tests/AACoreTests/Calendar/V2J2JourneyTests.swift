// V2-J2 journey (Stage V round 2; adopted by the integrator for W-PLAN from the verifier's scratch copy): task lifecycle across Calendar / Board / Planner / Buckets / Quick work / Due dates, then a
// recurring completion, save, reload (no duplicate spawn).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct V2J2JourneyTests {
    static let zone = TZ.athens
    static let clock = FixedClock(local: "2026-10-03T10:00:00", zone: zone)
    static let today = CivilDate(iso: "2026-10-03")!

    func day(_ s: String) -> NetDateTime { NetDateTime.calendarDate(CivilDate(iso: s)!) }
    func winLocal(_ s: String) -> NetDateTime { NetDateTime(parsing: s, zone: Self.zone)! }

    /// Builds the journey data: a weekly recurring job with a range, nested subtasks (2 levels), two buckets, a pin.
    func seed(_ store: AppStore) -> (t: TaskItem, s1: TaskItem, s11: TaskItem, b: [QuickBucket]) {
        let b1 = QuickBucket(name: "Engine room", category: "Location", createdUtc: Self.clock.utcNow())
        let b2 = QuickBucket(name: "Chief Engineer", category: "Rank", createdUtc: Self.clock.utcNow())
        let b3 = QuickBucket(name: "Deck", category: "Location", createdUtc: Self.clock.utcNow())
        store.data.quickBuckets = [b1, b2, b3]
        let t = TaskItem(name: "Weekly gas test")
        t.recurrence = .weekly
        t.deadline = winLocal("2026-10-02T00:00:00+03:00")      // as written by Windows (Local kind)
        t.rangeStart = winLocal("2026-09-30T00:00:00+03:00")
        t.isJob = true; t.durationMinutes = 90
        let s1 = TaskItem(name: "Bump test portables"); s1.deadline = day("2026-10-01"); s1.rangeStart = day("2026-09-30")
        let s11 = TaskItem(name: "Meter #1"); s11.deadline = day("2026-10-02"); s11.status = .inProgress
        s1.subtasks = [s11]
        t.subtasks = [s1]
        store.data.tasks.append(t)
        store.data.ui.quickViewPinIds = [t.id]
        return (t, s1, s11, [b1, b2, b3])
    }

    @Test func fullLifecycle() throws {
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        let (t, s1, s11, b) = seed(store)
        try store.save()

        // Buckets: 3 picked → first two in selection order kept, at every level.
        let r = QuickWorkActions.applyBuckets([b[2].id, b[0].id, b[1].id], to: t)
        #expect(r.capped && t.bucketIds == [b[2].id, b[0].id])
        _ = QuickWorkActions.applyBuckets([b[1].id], to: s11)
        #expect(s11.bucketIds == [b[1].id])
        let groups = BucketsModel.groups(store.data)
        let deckRow = groups.flatMap(\.rows).first { $0.bucket.id == b[2].id }
        #expect(deckRow?.count == 1)
        #expect(BucketsModel.members(of: b[1].id, in: BucketsModel.memberRows(store.data)).map(\.text)
                == ["[Subtask]  Meter #1   \u{2014}   in Bump test portables"])

        // Calendar: Day view on each covered day; overdue group in All / Agenda.
        for d in ["2026-09-30", "2026-10-01", "2026-10-02"] {
            let s = CalendarRowBuilder.build(data: store.data, mode: .day, selected: CivilDate(iso: d)!, today: Self.today)
            #expect(s.rows.contains { $0.itemID == t.id }, "ranged task on \(d)")
        }
        let all = CalendarRowBuilder.build(data: store.data, mode: .all, selected: Self.today, today: Self.today)
        #expect(all.groups.first?.role == .overdue)
        #expect(Set(all.groups.first!.rows.map(\.itemID)) == Set([t.id, s1.id, s11.id]))

        // Board: drag to Done and back to In Progress keeps IsComplete in sync.
        #expect(BoardModel.setStatus(s11, .done) && s11.isComplete)
        #expect(BoardModel.setStatus(s11, .inProgress) && !s11.isComplete)

        // Planner: drop the job on the hour grid two days AFTER its deadline → range extended, Unspecified.
        PlannerPlacement.dropOnHourGrid(t, day: CivilDate(iso: "2026-10-05")!, minutes: 540)
        #expect(t.scheduledStart?.kind == .unspecified && t.scheduledStart?.format(.isoMinute) == "2026-10-05 09:00")
        #expect(t.deadline?.format(.isoDate) == "2026-10-05" && t.deadline?.kind == .unspecified)
        #expect(t.rangeStart?.format(.isoDate) == "2026-09-30")
        PlannerPlacement.dropOnPool(t)
        #expect(t.scheduledStart == nil && t.deadline != nil)
        #expect(!PlannerPlacement.pool(store: store, query: "").contains { $0.job.id == t.id })
        try store.save()

        // Due-dates panel: the ranged job is "Task · ongoing" today? (today 10-03 inside 09-30…10-05)
        let due = DueListBuilder.build(store: store, today: Self.today, locale: Locale(identifier: "en_US"))
        let todayRows = due.sections.first { $0.kind == .today }!.rows
        #expect(todayRows.contains { $0.title == "Weekly gas test" && $0.subtitle == "Task \u{00B7} ongoing" })

        // Complete from the panel → save → reconcile (the env's `saved` hook) → exactly one next occurrence.
        var spawned = 0
        let sub = store.saved.subscribe { if store.reconcileRecurrences() { spawned += 1 } }
        defer { sub.cancel() }
        let row = todayRows.first { $0.title == "Weekly gas test" }!
        #expect(DueListBuilder.setDone(row.completable, done: true, store: store))
        store.markDirty(); try store.flushIfDirty()
        #expect(spawned == 1)
        try store.save()                 // second save: reconcile finds nothing
        #expect(spawned == 1)
        let tops = store.data.tasks.filter { $0.name == "Weekly gas test" }
        #expect(tops.count == 2)
        let c = tops[1]
        #expect(c.deadline?.format(.isoDate) == "2026-10-12" && c.deadline?.kind == .unspecified)
        #expect(c.rangeStart?.format(.isoDate) == "2026-10-07")
        #expect(c.isJob && c.durationMinutes == 90 && c.bucketIds == t.bucketIds)
        #expect(c.subtasks[0].deadline?.format(.isoDate) == "2026-10-08")
        #expect(c.subtasks[0].subtasks[0].status == .inProgress)
        #expect(c.subtasks[0].subtasks[0].bucketIds == [b[1].id])
        #expect(store.data.ui.quickViewPinIds == [t.id])

        // Quick work: completed source struck (isDone), clone active, both under the Deck bucket group first.
        let qw = QuickWorkRows.build(store: store, filter: .all, query: "Weekly", today: Self.today)
        let srcRows = qw.rows.filter { $0.itemID == t.id }
        #expect(srcRows.allSatisfy { $0.isDone })
        let cRows = qw.rows.filter { $0.itemID == c.id }
        #expect(cRows.allSatisfy { !$0.isDone })

        // Reload from disk → no duplicate spawn.
        let text = try String(contentsOf: made.dataStore.currentDataFile, encoding: .utf8)
        #expect(text.contains("\"Deadline\":\"2026-10-12T00:00:00\""))
        let reloaded = made.dataStore.load()
        store.replaceData(reloaded, reason: .reloadFromDisk)
        #expect(!store.reconcileRecurrences())
        #expect(store.data.tasks.filter { $0.name == "Weekly gas test" }.count == 2)
        let src = store.data.tasks.first { $0.id == t.id }!
        #expect(src.recurrenceSpawned && src.isComplete)
    }

    /// Monthly / yearly / daily completions from each surface give exactly one spawn with a calendar-date deadline.
    @Test func kindsFromEverySurface() throws {
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        let m = TaskItem(name: "Monthly"); m.recurrence = .monthly; m.deadline = day("2026-01-31")
        let y = TaskItem(name: "Yearly"); y.recurrence = .yearly; y.deadline = day("2024-02-29")
        let d = TaskItem(name: "Daily"); d.recurrence = .daily
        store.data.tasks = [m, y, d]
        _ = BoardModel.setStatus(m, .done)                                     // Board drop
        QuickWorkActions.setItemDone(y, done: true, store: store)              // ⌘N tile
        let row = CalendarRowBuilder.allRows(store.data)                        // Daily has no deadline → not on calendar
        #expect(!row.contains { $0.itemID == d.id })
        QuickWorkActions.setStatus(d, .done, store: store)                     // ⌘N status combo
        #expect(store.reconcileRecurrences(today: Self.today))
        #expect(!store.reconcileRecurrences(today: Self.today))
        let names = store.data.tasks.map(\.name)
        #expect(names == ["Monthly", "Yearly", "Daily", "Monthly", "Yearly", "Daily"])
        #expect(store.data.tasks[3].deadline?.format(.isoDate) == "2026-02-28")
        #expect(store.data.tasks[4].deadline?.format(.isoDate) == "2025-02-28")
        #expect(store.data.tasks[5].deadline?.format(.isoDate) == "2026-10-04")
        #expect(store.data.tasks[3...].allSatisfy { $0.deadline?.kind == .unspecified })
    }
}

@MainActor
@Suite struct V2J2BucketLog {
    @Test func newBucketLogsTrimmedName() throws {
        let made = StoreFactory.make(clock: V2J2JourneyTests.clock); let store = made.store
        let b = try #require(BucketsModel.create(name: "  Pump room ", category: " Location ", store: store))
        #expect(b.name == "Pump room" && b.category == "Location")
        let log = try #require(store.data.log.last)
        #expect(log.name == "Pump room")          // C# BucketsPage.xaml.cs:134 logs bucket.Name (trimmed)
        #expect(log.detail == "Location")
    }
}
