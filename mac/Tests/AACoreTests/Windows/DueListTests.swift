// Tests for 08 §7.1 (T-DUE-1…18), 08 QUICK-007…022, 09 CREW-090, 02 REPO-044; Q-3 fix (subtask job → root task).
// All vectors: Europe/Athens, en_US, today = Tue 2026-09-29.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct DueListTests {
    nonisolated static let today = CivilDate(year: 2026, month: 9, day: 29)!
    nonisolated static let en = Locale(identifier: "en_US")

    func day(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> NetDateTime {
        NetDateTime(year: 2026, month: m, day: d, hour: h, minute: min, kind: .unspecified)
    }

    func build(_ store: AppStore, today: CivilDate = DueListTests.today) -> DueList {
        DueListBuilder.build(store: store, today: today, locale: Self.en)
    }

    func section(_ l: DueList, _ k: DueSectionKind) -> DueSection? { l.sections.first { $0.kind == k } }

    @Test func overdueTask() {
        // TV: 08 T-DUE-1
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "Hull survey"); t.deadline = day(9, 27)
        store.data.tasks = [t]
        let l = build(store)
        let o = section(l, .overdue)
        #expect(o?.header == "OVERDUE   (1)")
        let r = o?.rows.first
        #expect(r?.icon == .task && r?.icon.glyph == "\u{2713}" && r?.accent == .overdue)
        #expect(r?.title == "Hull survey")
        #expect(r?.subtitle == "Task \u{00B7} 2d overdue (was due Sun, 27 Sep)")
        #expect(r?.target == .item(t.id, child: nil) && r?.completable == .task(t.id))
        #expect(l.headerSubtitle.hasPrefix("1 overdue  \u{00B7}  "))
        #expect(l.headerSubtitle == "1 overdue  \u{00B7}  Today Tue, 29 Sep  \u{00B7}  Tomorrow Wed, 30 Sep")
    }

    @Test func overdueOrdering() {
        // TV: 08 T-DUE-2
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "T"); t.deadline = day(9, 25)
        let p = Procedure(name: "P"); let s = ChecklistStep(title: "S"); s.deadline = day(9, 20); p.steps = [s]
        store.data.tasks = [t]; store.data.procedures = [p]
        let rows = section(build(store), .overdue)?.rows ?? []
        #expect(rows.map(\.title) == ["S", "T"])
        #expect(rows.first?.subtitle == "Checklist step \u{00B7} P \u{00B7} 9d overdue (was due Sun, 20 Sep)")
        #expect(rows.first?.icon == .step && rows.first?.target == .item(p.id, child: s.id))
    }

    @Test func rangedTaskOngoingAndStarting() {
        // TV: 08 T-DUE-3, T-DUE-4
        let made = StoreFactory.make(); let store = made.store
        let a = TaskItem(name: "A"); a.rangeStart = day(9, 28); a.deadline = day(9, 30)
        let b = TaskItem(name: "B"); b.rangeStart = day(9, 29); b.deadline = day(10, 2)
        store.data.tasks = [a, b]
        let l = build(store)
        #expect(section(l, .overdue) == nil)
        #expect(section(l, .today)?.rows.map(\.subtitle) == ["Task \u{00B7} ongoing", "Task \u{00B7} starts today"])
        #expect(section(l, .tomorrow)?.rows.map(\.subtitle) == ["Task \u{00B7} ends today", "Task \u{00B7} ongoing"])
        #expect(section(l, .nextSevenDays) == nil)
    }

    @Test func futureRangeOnlyInNextSeven() {
        // TV: 08 T-DUE-5
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "Future"); t.rangeStart = day(10, 1); t.deadline = day(10, 3)
        store.data.tasks = [t]
        let l = build(store)
        #expect(section(l, .today)?.rows.isEmpty == true && section(l, .tomorrow)?.rows.isEmpty == true)
        let n = section(l, .nextSevenDays)?.rows ?? []
        #expect(n.count == 1)
        #expect(n.first?.subtitle == "Task \u{00B7} starts today \u{00B7} due Thu, 01 Oct")
    }

    @Test func subtaskOwnerAndCompletedParent() {
        // TV: 08 T-DUE-6, T-DUE-7
        let made = StoreFactory.make(); let store = made.store
        let engine = TaskItem(name: "Engine")
        let filters = TaskItem(name: "Filters")
        let gasket = TaskItem(name: "Replace gasket"); gasket.deadline = day(9, 29)
        filters.subtasks = [gasket]; engine.subtasks = [filters]
        let drill = TaskItem(name: "Drill"); drill.isComplete = true
        let open = TaskItem(name: "Open sub"); open.deadline = day(9, 29)
        let closed = TaskItem(name: "Closed sub"); closed.deadline = day(9, 29); closed.isComplete = true
        drill.subtasks = [open, closed]
        store.data.tasks = [engine, drill]
        let rows = section(build(store), .today)?.rows ?? []
        #expect(rows.map(\.title) == ["Replace gasket", "Open sub"])
        #expect(rows[0].icon == .subtask && rows[0].icon.glyph == "\u{21B3}")
        #expect(rows[0].subtitle == "Subtask \u{00B7} Engine")
        #expect(rows[0].target == .item(engine.id, child: gasket.id))
        #expect(rows[1].subtitle == "Subtask \u{00B7} Drill")
    }

    @Test func doneProcedureOpenStep() {
        // TV: 08 T-DUE-8
        let made = StoreFactory.make(); let store = made.store
        let p = Procedure(name: "P"); p.status = .done; p.deadline = day(9, 29)
        let s = ChecklistStep(title: "S"); s.deadline = day(9, 29); p.steps = [s]
        store.data.procedures = [p]
        let rows = section(build(store), .today)?.rows ?? []
        #expect(rows.map(\.title) == ["S"])
        #expect(rows.first?.subtitle == "Checklist step \u{00B7} P" && rows.first?.accent == .procedure)
    }

    @Test func jobAndDeadlineSameDayAndNextDay() {
        // TV: 08 T-DUE-9, T-DUE-10
        let made = StoreFactory.make(); let store = made.store
        let j = TaskItem(name: "J"); j.isJob = true; j.scheduledStart = day(9, 29, 14, 30); j.deadline = day(9, 29)
        store.data.tasks = [j]
        var l = build(store)
        #expect(section(l, .today)?.rows.map(\.subtitle) == ["Task"])
        #expect(section(l, .today)?.rows.first?.icon == .task)

        j.deadline = day(9, 30)
        l = build(store)
        let today = section(l, .today)?.rows ?? []
        #expect(today.count == 1 && today.first?.icon == .job && today.first?.icon.glyph == "\u{1F552}")
        #expect(today.first?.subtitle == "Scheduled 14:30 \u{00B7} Task job" && today.first?.accent == .job)
        #expect(section(l, .tomorrow)?.rows.map(\.subtitle) == ["Task"])
        #expect(Set(today.map(\.id)).isDisjoint(with: Set(section(l, .tomorrow)!.rows.map(\.id))))
    }

    @Test func crewStepAndCrewJob() {
        // TV: 08 T-DUE-11, T-DUE-12; 09 CREW-090
        let made = StoreFactory.make(); let store = made.store
        let unnamed = CrewMember()
        let medical = ChecklistStep(title: "Medical"); medical.deadline = day(9, 30)
        unnamed.checklist = [medical]
        let ann = CrewMember(); ann.firstName = "Ann"; ann.lastName = "Lee"
        let job = ChecklistStep(title: "Gangway watch"); job.isJob = true; job.scheduledStart = day(10, 2, 8, 0)
        ann.checklist = [job]
        store.data.crew = [unnamed, ann]
        let l = build(store)
        let tm = section(l, .tomorrow)?.rows.first
        #expect(tm?.icon == .crew && tm?.icon.glyph == "\u{1F9D1}\u{200D}\u{2708}\u{FE0F}")
        #expect(tm?.subtitle == "Crew checklist \u{00B7} (unnamed)" && tm?.accent == .crew && tm?.target == .crew(unnamed.id))
        let n = section(l, .nextSevenDays)?.rows.first
        #expect(n?.icon == .job)
        #expect(n?.subtitle == "Scheduled 08:00 \u{00B7} Crew step job \u{00B7} Ann Lee \u{00B7} due Fri, 02 Oct")
        #expect(n?.target == .crew(ann.id))
    }

    @Test func timeOfDayDeadlinesUseTheDate() {
        // TV: 08 T-DUE-13
        let made = StoreFactory.make(); let store = made.store
        let a = TaskItem(name: "late today"); a.deadline = day(9, 29, 23, 59)
        let b = TaskItem(name: "late yesterday"); b.deadline = day(9, 28, 23, 59)
        store.data.tasks = [a, b]
        let l = build(store)
        #expect(section(l, .today)?.rows.map(\.title) == ["late today"])
        #expect(section(l, .overdue)?.rows.first?.subtitle == "Task \u{00B7} 1d overdue (was due Mon, 28 Sep)")
    }

    @Test func nothingDue() {
        // TV: 08 T-DUE-14
        let made = StoreFactory.make()
        let l = build(made.store)
        #expect(l.sections.map(\.header) == ["TODAY   (0)", "TOMORROW   (0)"])
        #expect(l.sections.allSatisfy { $0.showsNothingLine })
        #expect(l.isEverythingEmpty)
        #expect(DueList.emptyMessage == "Nothing overdue, or due in the next 7 days \u{1F389}")
        #expect(DueList.nothingLine == "\u{2014} nothing \u{2014}")
        #expect(l.headerSubtitle == "Today Tue, 29 Sep  \u{00B7}  Tomorrow Wed, 30 Sep")
    }

    @Test func dstNightDayCount() {
        // TV: 08 T-DUE-15 (DST ends 2026-10-25 in Athens)
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "T"); t.deadline = day(10, 24)
        store.data.tasks = [t]
        let l = withTimeZone("Europe/Athens") { _ in build(store, today: CivilDate(year: 2026, month: 10, day: 26)!) }
        #expect(section(l, .overdue)?.rows.first?.subtitle == "Task \u{00B7} 2d overdue (was due Sat, 24 Oct)")
    }

    @Test func tickDoneFromTheWindow() throws {
        // TV: 08 T-DUE-16; 02 REPO-044
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "Hull survey"); t.deadline = day(9, 27)
        store.data.tasks = [t]
        let row = try #require(section(build(store), .overdue)?.rows.first)
        #expect(DueListBuilder.setDone(row.completable, done: true, store: store))
        #expect(t.isComplete && t.status == .done)
        let after = build(store)
        #expect(section(after, .overdue) == nil && !after.headerSubtitle.contains("overdue"))
        #expect(!DueListBuilder.setDone(row.completable, done: true, store: store))       // no change → no save
    }

    @Test func procedureAndStepCompletion() {
        // TV: 08 QUICK-022 (procedures: Status = Done; steps: Done = true; undone keeps InProgress)
        let made = StoreFactory.make(); let store = made.store
        let p = Procedure(name: "P"); p.status = .inProgress
        let s = ChecklistStep(title: "S"); p.steps = [s]
        store.data.procedures = [p]
        #expect(DueListBuilder.setDone(.procedure(p.id), done: false, store: store) == false)
        #expect(p.status == .inProgress)
        #expect(DueListBuilder.setDone(.procedure(p.id), done: true, store: store) && p.status == .done)
        #expect(DueListBuilder.setDone(.step(s.id), done: true, store: store) && s.done)
        #expect(DueListBuilder.setDone(.task(UUID()), done: true, store: store) == false)
    }

    @Test func sizeRestore() {
        // TV: 08 T-DUE-17; QUICK-004
        #expect(DueWindowGeometry.restoredSize(width: 200, height: nil) == (350, 480))
        #expect(DueWindowGeometry.restoredSize(width: 400, height: 219) == (400, 480))
        #expect(DueWindowGeometry.restoredSize(width: 400, height: 220) == (400, 220))
        #expect(DueWindowGeometry.restoredSize(width: 5000, height: 3000, maxWidth: 1440, maxHeight: 875) == (1440, 875))
        let o = DueWindowGeometry.initialOrigin(visibleX: 0, visibleY: 25, visibleWidth: 1440, width: 350)
        #expect(o.x == 1074 && o.y == 41)
    }

    @Test func nextSevenBoundary() {
        // TV: 08 T-DUE-18
        let made = StoreFactory.make(); let store = made.store
        let a = TaskItem(name: "day 7"); a.deadline = day(10, 6)
        let b = TaskItem(name: "day 8"); b.deadline = day(10, 7)
        store.data.tasks = [a, b]
        let l = build(store)
        #expect(section(l, .nextSevenDays)?.rows.map(\.title) == ["day 7"])
        #expect(section(l, .nextSevenDays)?.rows.first?.subtitle == "Task \u{00B7} due Tue, 06 Oct")
    }

    @Test func subtaskJobNavigatesToRootAndOrphanStepJob() {
        // TV: 08 Q-3 (P2 fix) and QUICK-016 orphan step job
        let made = StoreFactory.make(); let store = made.store
        let root = TaskItem(name: "Root")
        let sub = TaskItem(name: "Sub job"); sub.isJob = true; sub.scheduledStart = day(9, 29, 9, 0)
        root.subtasks = [sub]
        let p = Procedure(name: "Bunkering"); p.isJob = true; p.scheduledStart = day(9, 29, 10, 15)
        let step = ChecklistStep(title: "Step job"); step.isJob = true; step.scheduledStart = day(9, 29, 11, 0)
        p.steps = [step]
        store.data.tasks = [root]; store.data.procedures = [p]
        let rows = section(build(store), .today)?.rows ?? []
        #expect(rows.map(\.subtitle) == ["Scheduled 09:00 \u{00B7} Task job", "Scheduled 10:15 \u{00B7} Procedure job",
                                         "Scheduled 11:00 \u{00B7} Step job \u{00B7} Bunkering"])
        #expect(rows[0].target == .item(root.id, child: sub.id))
        #expect(rows[2].target == .item(p.id, child: step.id))
    }

    @Test func todayAndTomorrowCanShareAnObjectWithDistinctRowIDs() {
        // TV: 08 QUICK-017 (TODAY and TOMORROW are independent), §6.3 row ids
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "Span"); t.rangeStart = day(9, 29); t.deadline = day(9, 30)
        store.data.tasks = [t]
        let l = build(store)
        let a = section(l, .today)!.rows[0], b = section(l, .tomorrow)!.rows[0]
        #expect(a.id != b.id && a.completable == b.completable)
        #expect(a.id == "TODAY|\(t.id.netString)")
    }

    @Test func dayTextUsesTheLocale() {
        // TV: 08 Q-17 (ddd, dd MMM in the current culture)
        let d = CivilDate(year: 2026, month: 10, day: 2)!
        #expect(DueListBuilder.dayText(d, locale: Locale(identifier: "en_US")) == "Fri, 02 Oct")
        #expect(DueListBuilder.dayText(d, locale: Locale(identifier: "de_DE")).contains("02"))
    }
}
