// Tests for 07 §8.3 (P1…P23), VIEW-080…108, §8.7 (JSON round trip), T-KB-22 / T-KB-23, DECISIONS 07 Q-06 / Q-07,
// DECISIONS Q-6 (placements written as Unspecified calendar values).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct PlannerTests {
    typealias D = CalTestData

    @Test func durationFormat() {
        // TV: 07 P1
        #expect([0, 45, 60, 90, 125, -5].map(PlannerGeometry.durFmt) == ["0m", "45m", "1h", "1h 30m", "2h 5m", "-5m"])
    }

    @Test func blockHeightsAndSubtitles() {
        // TV: 07 P2, P3
        #expect(PlannerGeometry.blockHeight(duration: 10) == 20)
        #expect(!PlannerGeometry.showsSubtitle(height: 20))
        let h44 = PlannerGeometry.blockHeight(duration: 44)
        #expect(abs(h44 - 33.7333) < 1e-3 && !PlannerGeometry.showsSubtitle(height: h44))
        #expect(PlannerGeometry.blockHeight(duration: 45) == 34.5 && PlannerGeometry.showsSubtitle(height: 34.5))
        #expect(PlannerGeometry.blockHeight(duration: 60) == 46)
        #expect(PlannerGeometry.blockHeight(duration: 30) == 23)
        let t = TaskItem(name: "x")
        t.durationMinutes = 10
        t.scheduledStart = NetDateTime.calendarDateTime(D.day("2026-10-01"), minutes: 9 * 60)
        #expect(PlannerPlacement.jobEnd(t)?.format(.time) == "09:15")
    }

    @Test func snapUsesBankersRounding() {
        // TV: 07 P4, §4.3.7
        #expect(PlannerGeometry.snappedMinutes(y: 0) == 0)
        #expect(PlannerGeometry.snappedMinutes(y: 100) == 135)
        #expect(PlannerGeometry.snappedMinutes(y: 28.75) == 30)
        #expect(PlannerGeometry.snappedMinutes(y: 51.75) == 60)
        #expect(PlannerGeometry.snappedMinutes(y: 1104) == 1425)
        #expect(PlannerGeometry.snappedMinutes(y: -40) == 0)
    }

    @Test func overlapLayout() {
        // TV: 07 P5, P6, P7, §4.3.4
        let p5 = PlannerGeometry.layoutDay([
            PlannerInterval(start: 540, end: 600), PlannerInterval(start: 570, end: 630),
            PlannerInterval(start: 600, end: 660), PlannerInterval(start: 660, end: 690),
        ], dayWidth: 700)
        #expect(p5.map(\.column) == [0, 1, 0, 0])
        #expect(p5.map(\.columns) == [2, 2, 2, 1])
        #expect(p5[0].width == 346 && p5[1].left == 350 && p5[3].width == 695 && p5[3].left == 1)
        let p6 = PlannerGeometry.layoutDay([PlannerInterval(start: 540, end: 600), PlannerInterval(start: 600, end: 660)],
                                           dayWidth: 700)
        #expect(p6.map(\.columns) == [1, 1] && p6.allSatisfy { $0.width == 695 })
        // P7: a 0-minute job lays out as 15 minutes, so 09:00 and 09:10 overlap.
        let a = TaskItem(name: "a"), b = TaskItem(name: "b")
        a.durationMinutes = 0; b.durationMinutes = 60
        a.scheduledStart = NetDateTime.calendarDateTime(D.day("2026-10-01"), minutes: 540)
        b.scheduledStart = NetDateTime.calendarDateTime(D.day("2026-10-01"), minutes: 550)
        let blocks = PlannerPlacement.blocks([a, b], day: D.day("2026-10-01"), dayWidth: 700)
        #expect(blocks.map(\.slot.columns) == [2, 2])
        #expect(blocks[0].slot.top == 9 * 46)
    }

    @Test func blocksAreClippedAtMidnight() {
        // W-18
        let slots = PlannerGeometry.layoutDay([PlannerInterval(start: 23 * 60, end: 23 * 60 + 180)], dayWidth: 700)
        #expect(slots[0].top + slots[0].height == PlannerGeometry.gridHeight)
        #expect(slots[0].showsSubtitle)
    }

    @Test func labelsAndDays() {
        // TV: 07 P8, P9, P10 (en-US pinned)
        let week = PlannerGeometry.days(mode: .week, anchor: D.today)
        #expect(week.first == D.day("2026-09-27") && week.last == D.day("2026-10-03") && week.count == 7)
        #expect(PlannerGeometry.rangeLabel(mode: .week, anchor: D.today, locale: D.enUS) == "Week of 2026-09-27")
        #expect(PlannerGeometry.dayHeader(mode: .week, day: D.day("2026-09-27"), locale: D.enUS) == "Sun\nSep 27")
        #expect(PlannerGeometry.rangeLabel(mode: .day, anchor: D.today, locale: D.enUS) == "Tuesday, 2026-09-29")
        #expect(PlannerGeometry.dayHeader(mode: .day, day: D.today, locale: D.enUS) == "Tuesday, Sep 29")
        #expect(PlannerGeometry.rangeLabel(mode: .month, anchor: D.today, locale: D.enUS) == "September 2026")
        let cells = PlannerGeometry.monthCells(anchor: D.today)
        #expect(cells.count == 42 && cells.first == D.day("2026-08-30") && cells.last == D.day("2026-10-10"))
        #expect(PlannerGeometry.monthHeader(locale: D.enUS) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        #expect(PlannerGeometry.hourLabels.count == 25 && PlannerGeometry.hourLabels.last == "24:00")
        #expect(PlannerGeometry.initialScrollY == 322 && PlannerGeometry.gridHeight == 1104)
    }

    @Test func navigation() {
        // TV: 07 P11, VIEW-081; 03 T-KB-23 (⌘← / ⌘→ in Week and Month)
        #expect(PlannerGeometry.step(D.day("2027-01-31"), mode: .month, forward: true) == D.day("2027-02-28"))
        #expect(PlannerGeometry.step(D.day("2026-09-30"), mode: .week, forward: false) == D.day("2026-09-23"))
        #expect(PlannerGeometry.step(D.day("2026-09-30"), mode: .week, forward: true) == D.day("2026-10-07"))
        #expect(PlannerGeometry.step(D.day("2026-01-31"), mode: .month, forward: true) == D.day("2026-02-28"))
        #expect(PlannerGeometry.step(D.today, mode: .day, forward: true) == D.day("2026-09-30"))
    }

    @Test func rangedChipsInTheAllDayStrip() throws {
        // TV: 07 P12, VIEW-089…091, VIEW-099
        let t = D.task("name", start: "2026-10-03", deadline: "2026-10-05")
        let placed = PlannerPlacement.placed(D.data(tasks: [t]))
        let c3 = try #require(PlannerPlacement.allDayChips(placed, day: D.day("2026-10-03")).first)
        let c4 = try #require(PlannerPlacement.allDayChips(placed, day: D.day("2026-10-04")).first)
        let c5 = try #require(PlannerPlacement.allDayChips(placed, day: D.day("2026-10-05")).first)
        #expect(c3.text == "\u{25B8} name" && c3.opacity == 0.6 && !c3.isBold)
        #expect(c4.text == "\u{00B7} name" && c4.opacity == 0.6)
        #expect(c5.text == "\u{2691} name" && c5.opacity == 1 && c5.isBold)
        #expect(c5.tooltip == "name\n2026-10-03 \u{2192} 2026-10-05  (3 days)\nDrag in Month to move the whole range \u{2022} double-click to edit")
        #expect(c3.ref.anchor == D.day("2026-10-03"))
        #expect(PlannerPlacement.allDayChips(placed, day: D.day("2026-10-06")).isEmpty)
        // Month ghosts use 0.55.
        #expect(PlannerPlacement.monthChips(placed, day: D.day("2026-10-04")).first?.opacity == 0.55)
        // A point item: bullet + "due … (no time)".
        let p = Procedure(name: "proc")
        p.deadline = D.date("2026-10-03")
        let chip = try #require(PlannerPlacement.allDayChips([p], day: D.day("2026-10-03")).first)
        #expect(chip.text == "\u{2022} proc")
        #expect(chip.tooltip == "proc\ndue 2026-10-03 (no time)\nDrag onto the grid to give it a time \u{2022} double-click to edit")
    }

    @Test func monthDropSlidesTheWholeRange() {
        // TV: 07 P13, VIEW-101
        let t = D.task("name", start: "2026-10-03", deadline: "2026-10-05")
        PlannerPlacement.dropOnMonthCell(t, cell: D.day("2026-10-10"), anchor: D.day("2026-10-04"))
        #expect(t.rangeStart?.civilDate == D.day("2026-10-09") && t.deadline?.civilDate == D.day("2026-10-11"))
        #expect(t.rangeStart?.kind == .unspecified && t.deadline?.kind == .unspecified)
        // No anchor (not reachable from the UI): the window ends on the cell, length kept.
        PlannerPlacement.dropOnMonthCell(t, cell: D.day("2026-10-20"), anchor: nil)
        #expect(t.deadline?.civilDate == D.day("2026-10-20") && t.rangeStart?.civilDate == D.day("2026-10-18"))
    }

    @Test func hourGridDropExtendsTheRange() {
        // TV: 07 P14, P15, VIEW-100
        let t = D.task("t", start: "2026-10-03", deadline: "2026-10-05")
        PlannerPlacement.dropOnHourGrid(t, day: D.day("2026-10-08"), y: 414)
        #expect(t.scheduledStart?.civilDate == D.day("2026-10-08") && t.scheduledStart?.format(.time) == "09:00")
        #expect(t.deadline?.civilDate == D.day("2026-10-08") && t.rangeStart?.civilDate == D.day("2026-10-03"))
        let u = D.task("u", start: "2026-10-03", deadline: "2026-10-05")
        PlannerPlacement.dropOnHourGrid(u, day: D.day("2026-10-01"), y: 414)
        #expect(u.rangeStart?.civilDate == D.day("2026-10-01") && u.deadline?.civilDate == D.day("2026-10-05"))
        let v = D.task("v", deadline: "2026-10-05")
        let before = v.deadline
        PlannerPlacement.dropOnHourGrid(v, day: D.day("2026-10-08"), y: 414)
        #expect(v.scheduledStart != nil && v.deadline == before && v.deadline?.originalText == before?.originalText)
    }

    @Test func monthDropsForTimedAndPointItems() {
        // TV: 07 P16, P17, P18
        let timed = D.task("timed", deadline: "2026-10-01")
        timed.scheduledStart = NetDateTime.calendarDateTime(D.day("2026-10-03"), minutes: 14 * 60 + 30)
        PlannerPlacement.dropOnMonthCell(timed, cell: D.day("2026-10-07"), anchor: nil)
        #expect(timed.scheduledStart?.format(.isoMinute) == "2026-10-07 14:30" && timed.deadline?.civilDate == D.day("2026-10-01"))
        let p = Procedure(name: "p")
        p.deadline = D.date("2026-10-03")
        PlannerPlacement.dropOnMonthCell(p, cell: D.day("2026-10-07"), anchor: D.day("2026-10-03"))
        #expect(p.deadline?.civilDate == D.day("2026-10-07"))
        let job = TaskItem(name: "job")
        job.isJob = true
        let made = StoreFactory.make(data: D.data(tasks: [job]))
        #expect(PlannerPlacement.pool(store: made.store, query: "").count == 1)
        PlannerPlacement.dropOnMonthCell(job, cell: D.day("2026-10-07"), anchor: nil)
        #expect(job.deadline?.civilDate == D.day("2026-10-07"))
        #expect(PlannerPlacement.pool(store: made.store, query: "").isEmpty)
    }

    @Test func poolDropUnschedules() {
        // TV: 07 P19, VIEW-102
        let t = D.task("t", deadline: "2026-10-05")
        t.isJob = true
        t.scheduledStart = NetDateTime.calendarDateTime(D.day("2026-10-01"), minutes: 600)
        let made = StoreFactory.make(data: D.data(tasks: [t]))
        PlannerPlacement.dropOnPool(t)
        #expect(t.scheduledStart == nil)
        #expect(PlannerPlacement.pool(store: made.store, query: "").isEmpty)
        #expect(PlannerPlacement.allDayChips(PlannerPlacement.placed(made.store.data), day: D.day("2026-10-05")).count == 1)
    }

    @Test func poolFilter() {
        // TV: 07 P20, VIEW-084
        let a = TaskItem(name: "Fuel pump"); a.isJob = true
        let b = D.task("dated job", deadline: "2026-10-05"); b.isJob = true
        let c = TaskItem(name: "not a job")
        let d = TaskItem(name: "done job"); d.isJob = true; d.isComplete = true
        let p = Procedure(name: "proc job"); p.isJob = true; p.durationMinutes = 90
        let made = StoreFactory.make(data: D.data(tasks: [a, b, c, d], procedures: [p]))
        let rows = PlannerPlacement.pool(store: made.store, query: "")
        #expect(rows.map(\.job.jobName) == ["Fuel pump", "done job", "proc job"])
        #expect(rows[2].text == "proc job   \u{00B7}   1h 30m" && rows[1].isDone)
        #expect(PlannerPlacement.pool(store: made.store, query: "  PUMP ").map(\.job.jobName) == ["Fuel pump"])
    }

    @Test func timedItemsNeverShowInTheDueStrip() {
        // TV: 07 P21, VIEW-085
        let t = D.task("name", deadline: "2026-10-05")
        t.scheduledStart = NetDateTime.calendarDateTime(D.day("2026-10-01"), minutes: 540)
        let placed = PlannerPlacement.placed(D.data(tasks: [t]))
        #expect(PlannerPlacement.blocks(placed, day: D.day("2026-10-01"), dayWidth: 700).count == 1)
        #expect(PlannerPlacement.allDayChips(placed, day: D.day("2026-10-05")).isEmpty)
        #expect(PlannerPlacement.monthChips(placed, day: D.day("2026-10-01")).map(\.text) == ["09:00 name"])
        #expect(PlannerPlacement.monthChips(placed, day: D.day("2026-10-05")).isEmpty)
    }

    @Test func monthChipOrdering() {
        // TV: 07 P22
        let beta = D.task("beta", deadline: "2026-10-05")
        let zeta = TaskItem(name: "zeta")
        zeta.scheduledStart = NetDateTime.calendarDateTime(D.day("2026-10-05"), minutes: 8 * 60)
        let alpha = D.task("Alpha", deadline: "2026-10-05")
        let x = TaskItem(name: "x")
        x.scheduledStart = NetDateTime.calendarDateTime(D.day("2026-10-05"), minutes: 7 * 60)
        let chips = PlannerPlacement.monthChips(PlannerPlacement.placed(D.data(tasks: [beta, zeta, alpha, x])),
                                                day: D.day("2026-10-05"))
        #expect(chips.map(\.text) == ["07:00 x", "08:00 zeta", "\u{2022} Alpha", "\u{2022} beta"])
    }

    @Test func allDayOrdering() {
        // TV: 07 P23
        let b = D.task("b", deadline: "2026-10-05")
        let a = D.task("a", start: "2026-10-03", deadline: "2026-10-05")
        let chips = PlannerPlacement.allDayChips(PlannerPlacement.placed(D.data(tasks: [b, a])), day: D.day("2026-10-05"))
        #expect(chips.map(\.job.jobName) == ["a", "b"])
    }

    @Test func completedItemsGreyAndEditorTargets() {
        // DECISIONS 07 Q-06 (grey every completed kind), Q-07 (procedure double-click navigates)
        let p = Procedure(name: "p"); p.status = .done
        let s = ChecklistStep(title: "s"); s.done = true
        let t = TaskItem(name: "t")
        #expect(PlannerPlacement.isDone(p) && PlannerPlacement.isDone(s) && !PlannerPlacement.isDone(t))
        #expect(PlannerPlacement.editorTarget(t) == .task(t.id))
        #expect(PlannerPlacement.editorTarget(p) == .navigate(p.id))
        #expect(PlannerPlacement.editorTarget(s) == .step(s.id))
    }

    @Test func blockTexts() {
        // VIEW-095 subtitle and tooltip
        let t = TaskItem(name: "Overhaul pump")
        t.durationMinutes = 90
        t.scheduledStart = NetDateTime.calendarDateTime(D.day("2026-10-08"), minutes: 9 * 60 + 15)
        #expect(PlannerPlacement.blockSubtitle(t) == "09:15\u{2013}10:45  (1h 30m)")
        #expect(PlannerPlacement.blockTooltip(t) == "Overhaul pump\n09:15\u{2013}10:45 (1h 30m)\nDrag to move \u{2022} double-click to edit")
        #expect(PlannerPlacement.chipTooltip(t) == "Overhaul pump\n09:15 (1h 30m)")
    }

    @Test func refsResolveAcrossEveryFamily() throws {
        // 07 §7.3 payload: resolved by id at drop time.
        let t = TaskItem(name: "t"); let sub = TaskItem(name: "sub"); t.subtasks = [sub]
        let p = Procedure(name: "p"); let st = ChecklistStep(title: "st"); p.steps = [st]
        let c = CrewMember(); let cs = ChecklistStep(title: "cs"); c.checklist = [cs]
        let made = StoreFactory.make(data: D.data(tasks: [t], procedures: [p], crew: [c]))
        for job in [sub, p, st, cs] as [any SchedulableJob] {
            let ref = PlannerPlacement.ref(job, anchor: D.today)
            let data = try JSONEncoder().encode(ref)
            let back = try JSONDecoder().decode(PlannerJobRef.self, from: data)
            #expect(back == ref && back.anchor == D.today)
            #expect(PlannerPlacement.resolve(back, store: made.store) === job)
        }
        #expect(PlannerPlacement.resolve(PlannerJobRef(id: UUID(), family: .task), store: made.store) == nil)
    }

    @Test func placementsWriteUnspecifiedValues() throws {
        // 07 §8.7 as amended by DECISIONS Q-6: a day drop writes no offset; an unedited value keeps its text.
        let raw = #"{"Name":"t","IsJob":true,"Deadline":"2026-10-05T00:00:00+03:00","RangeStart":"2026-10-02T00:00:00+03:00"}"#
        let ctx = JSONDecodeContext(zone: TZ.athens, clock: FixedClock(local: "2026-09-29T10:00:00", zone: TZ.athens))
        let t = try TaskItem(json: try #require(try JSONParser.parse(raw).objectValue), context: ctx)
        PlannerPlacement.dropOnHourGrid(t, day: D.day("2026-10-03"), y: 9 * 46)
        #expect(t.scheduledStart?.jsonString(zone: TZ.athens) == "2026-10-03T09:00:00")
        #expect(t.deadline?.jsonString(zone: TZ.athens) == "2026-10-05T00:00:00+03:00")
        PlannerPlacement.dropOnHourGrid(t, day: D.day("2026-10-08"), y: 0)
        #expect(t.deadline?.jsonString(zone: TZ.athens) == "2026-10-08T00:00:00")
        #expect(t.rangeStart?.jsonString(zone: TZ.athens) == "2026-10-02T00:00:00+03:00")
        // CalendarFontScale 18 / 16.5 serialise as 18 / 16.5.
        let ui = UiState()
        ui.calendarFontScale = 18
        #expect(try JSONWriter.string(.object(ui.toJSON())).contains("\"CalendarFontScale\":18,"))
        ui.calendarFontScale = 16.5
        #expect(try JSONWriter.string(.object(ui.toJSON())).contains("\"CalendarFontScale\":16.5,"))
    }
}
