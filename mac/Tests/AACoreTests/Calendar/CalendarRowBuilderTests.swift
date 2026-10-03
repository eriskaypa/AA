// Tests for 07 §8.1 (C1…C21), VIEW-002…021, CREW-091, DECISIONS 07 Q-09 / Q-12, W-02 / W-03, T-KB-26 / T-KB-27.
import Foundation
import Testing
@testable import AACore

/// Test helpers for the Calendar suites (namespaced, ARCH §12.2).
@MainActor
enum CalTestData {
    static let today = CivilDate(year: 2026, month: 9, day: 29)!          // Tuesday (07 §8)
    static let enUS = Locale(identifier: "en_US")

    static func day(_ iso: String) -> CivilDate { CivilDate(iso: iso)! }
    static func date(_ iso: String) -> NetDateTime { NetDateTime.calendarDate(day(iso)) }

    static func task(_ name: String, start: String? = nil, deadline: String? = nil) -> TaskItem {
        let t = TaskItem(name: name)
        t.rangeStart = start.map(date)
        t.deadline = deadline.map(date)
        return t
    }

    static func data(tasks: [TaskItem] = [], procedures: [Procedure] = [], crew: [CrewMember] = []) -> AppData {
        let d = AppData()
        d.tasks = tasks
        d.procedures = procedures
        d.crew = crew
        return d
    }

    static func names(_ s: CalSchedule) -> [String] { s.rows.map(\.name) }
}

@MainActor
@Suite struct CalendarRowBuilderTests {
    typealias D = CalTestData

    @Test func rangedTaskShowsOnEveryCoveredDay() {
        // TV: 07 C1, VIEW-005, VIEW-018
        let data = D.data(tasks: [D.task("T", start: "2026-10-03", deadline: "2026-10-05")])
        for (iso, present) in [("2026-10-02", false), ("2026-10-03", true), ("2026-10-04", true), ("2026-10-05", true),
                               ("2026-10-06", false)] {
            let s = CalendarRowBuilder.build(data: data, mode: .day, selected: D.day(iso), today: D.today)
            #expect(s.rows.count == (present ? 1 : 0), "\(iso)")
        }
        let s = CalendarRowBuilder.build(data: data, mode: .day, selected: D.day("2026-10-04"), today: D.today)
        #expect(s.rows.first?.rangeDisplay == "2026-10-03 \u{2192} 2026-10-05")
        #expect(s.title == "Schedule \u{2014} 2026-10-04")
    }

    @Test func outOfOrderAndSingleDayRanges() throws {
        // TV: 07 C2, C3, C4
        let rows = CalendarRowBuilder.allRows(D.data(tasks: [
            D.task("C2", start: "2026-10-08", deadline: "2026-10-05"),
            D.task("C3", start: "2026-10-05", deadline: "2026-10-05"),
            D.task("C4", start: "2026-10-05"),
        ]))
        #expect(rows.map(\.name) == ["C2", "C3"])
        let c2 = rows[0]
        #expect(!c2.isRanged && c2.effectiveStart.civilDate == D.day("2026-10-05"))
        #expect(c2.covers(D.day("2026-10-05")) && !c2.covers(D.day("2026-10-06")) && !c2.covers(D.day("2026-10-08")))
        #expect(c2.rangeDisplay == "2026-10-05")
        #expect(!rows[1].isRanged && rows[1].rangeDisplay == "2026-10-05")
    }

    @Test func weekView() {
        // TV: 07 C5, VIEW-006 (Sunday start)
        let data = D.data(tasks: [
            D.task("range", start: "2026-09-20", deadline: "2026-09-27"),
            D.task("p1004", deadline: "2026-10-04"),
            D.task("p0927", deadline: "2026-09-27"),
            D.task("p1003", deadline: "2026-10-03"),
        ])
        let s = CalendarRowBuilder.build(data: data, mode: .week, selected: D.today, today: D.today)
        #expect(s.title == "Schedule \u{2014} week of 2026-09-27")
        #expect(Set(D.names(s)) == ["range", "p0927", "p1003"])
    }

    @Test func monthView() {
        // TV: 07 C6, VIEW-007
        let data = D.data(tasks: [
            D.task("range", start: "2026-08-25", deadline: "2026-09-02"),
            D.task("p1001", deadline: "2026-10-01"),
        ])
        let s = CalendarRowBuilder.build(data: data, mode: .month, selected: D.day("2026-09-15"), today: D.today)
        #expect(s.title == "Schedule \u{2014} 2026-09")
        #expect(D.names(s) == ["range"])
    }

    @Test func allUpcomingAndTheOverdueGroup() {
        // TV: 07 C7, VIEW-008, DECISIONS 07 Q-12 (the past-due, not-done task moves to an Overdue group)
        let late = D.task("late", deadline: "2026-09-28")
        let doneToday = D.task("doneToday", deadline: "2026-09-29")
        doneToday.isComplete = true
        let range = D.task("range", start: "2026-09-20", deadline: "2026-09-29")
        let lateDone = D.task("lateDone", deadline: "2026-09-27")
        lateDone.isComplete = true
        let data = D.data(tasks: [late, doneToday, range, lateDone])
        let s = CalendarRowBuilder.build(data: data, mode: .all, selected: D.today, today: D.today)
        #expect(s.title == "Schedule \u{2014} all upcoming")
        #expect(s.groups.map(\.label) == ["Overdue", "Upcoming"])
        #expect(s.groups[0].rows.map(\.name) == ["late"])
        #expect(s.groups[1].rows.map(\.name) == ["range", "doneToday"])
        // Without overdue items the list stays flat (Windows parity).
        let flat = CalendarRowBuilder.build(data: D.data(tasks: [doneToday, range]), mode: .all, selected: D.today,
                                            today: D.today)
        #expect(!flat.isGrouped && flat.groups.count == 1)
    }

    @Test func agendaFanOutAndDayLabels() {
        // TV: 07 C8, VIEW-010, §4.1.5 (en-US pinned, DECISIONS 07 Q-09)
        let data = D.data(tasks: [D.task("R", start: "2026-09-25", deadline: "2026-10-01")])
        let s = CalendarRowBuilder.build(data: data, mode: .agenda, selected: D.today, today: D.today, locale: D.enUS)
        #expect(s.title == "Agenda \u{2014} upcoming by day")
        #expect(s.groups.map(\.label) == ["Today", "Tomorrow", "Thu, 2026-10-01"])
        #expect(s.groups.map(\.countText) == [" (1)", " (1)", " (1)"])
        #expect(Set(s.rows.map(\.id)).count == 3)
    }

    @Test func agendaLongRangesCollapse() {
        // TV: 07 C9, C10
        let c9 = CalendarRowBuilder.build(data: D.data(tasks: [D.task("R", start: "2026-09-29", deadline: "2026-10-31")]),
                                          mode: .agenda, selected: D.today, today: D.today, locale: D.enUS)
        #expect(c9.rows.count == 1 && c9.groups.map(\.label) == ["Sat, 2026-10-31"])
        let c10 = CalendarRowBuilder.build(data: D.data(tasks: [D.task("R", start: "2026-09-29", deadline: "2026-10-30")]),
                                           mode: .agenda, selected: D.today, today: D.today, locale: D.enUS)
        #expect(c10.rows.count == 32)
        #expect(c10.rows.first?.occurrenceDate == D.day("2026-09-29") && c10.rows.last?.occurrenceDate == D.day("2026-10-30"))
    }

    @Test func agendaSortsByNameWithTheCultureComparer() {
        // TV: 07 C11
        let data = D.data(tasks: [D.task("b", deadline: "2026-10-02"), D.task("A", deadline: "2026-10-02")])
        let s = CalendarRowBuilder.build(data: data, mode: .agenda, selected: D.today, today: D.today, locale: D.enUS)
        #expect(D.names(s) == ["A", "b"])
    }

    @Test func agendaOverdueGroupComesFirst() {
        // DECISIONS 07 Q-12 (additive): one row per overdue item, never fanned out, then the day groups.
        let late = D.task("late range", start: "2026-09-10", deadline: "2026-09-20")
        let data = D.data(tasks: [late, D.task("x", deadline: "2026-09-30")])
        let s = CalendarRowBuilder.build(data: data, mode: .agenda, selected: D.today, today: D.today, locale: D.enUS)
        #expect(s.groups.map(\.label) == ["Overdue", "Tomorrow"])
        #expect(s.groups[0].rows.count == 1 && s.groups[0].role == .overdue)
        late.isComplete = true
        let after = CalendarRowBuilder.build(data: data, mode: .agenda, selected: D.today, today: D.today, locale: D.enUS)
        #expect(after.groups.map(\.label) == ["Tomorrow"])
    }

    @Test func stepAndCrewRows() throws {
        // TV: 07 C12, C13; 09 CREW-091
        let p = Procedure(name: "Engine")
        let s = ChecklistStep(title: "Check oil")
        s.deadline = D.date("2026-10-02")
        p.steps = [s]
        let c = CrewMember()
        let cs = ChecklistStep(title: "Sign contract")
        cs.deadline = D.date("2026-10-02")
        c.checklist = [cs]
        let rows = CalendarRowBuilder.allRows(D.data(procedures: [p], crew: [c]))
        #expect(rows.map(\.name) == ["Check oil   \u{00B7}  [Engine]", "Sign contract   \u{00B7}  \u{1F464} (unnamed)"])
        let step = rows[0]
        #expect(step.status == "Step" && step.recurrence == "" && step.kind == .step && step.ownerID == p.id)
        #expect(step.setComplete(true))
        #expect(step.status == "Done" && step.isComplete && s.done)
        #expect(rows[1].kind == .crewStep && rows[1].ownerID == c.id)
        c.firstName = "Ana"; c.lastName = "Reyes"
        #expect(CalendarRowBuilder.allRows(D.data(crew: [c])).first?.name == "Sign contract   \u{00B7}  \u{1F464} Ana Reyes")
    }

    @Test func taskStatusAndRecurrenceNames() {
        // TV: 07 C14, VIEW-012
        let t = D.task("t", deadline: "2026-10-02")
        t.status = .inProgress
        let r = CalendarRowBuilder.allRows(D.data(tasks: [t]))[0]
        #expect(r.status == "InProgress" && r.recurrence == "None")
        t.recurrence = .weekly
        #expect(CalendarRowBuilder.allRows(D.data(tasks: [t]))[0].recurrence == "Weekly")
    }

    @Test func procedureDoneToggle() {
        // TV: 07 C15, VIEW-013
        let p = Procedure(name: "P")
        p.deadline = D.date("2026-10-02")
        p.status = .blocked
        let r = CalendarRowBuilder.allRows(D.data(procedures: [p]))[0]
        #expect(!r.isComplete)
        #expect(r.setComplete(true) && p.status.rawValue == 3)
        #expect(r.setComplete(false) && p.status.rawValue == 0)
        #expect(!r.setComplete(false))
    }

    @Test func agendaOccurrencesShareTheLiveDoneState() {
        // W-03: every occurrence reads the model, so ticking one updates its siblings.
        let t = D.task("R", start: "2026-09-29", deadline: "2026-10-01")
        let s = CalendarRowBuilder.build(data: D.data(tasks: [t]), mode: .agenda, selected: D.today, today: D.today)
        #expect(s.rows.count == 3)
        s.rows[1].setComplete(true)
        #expect(s.rows.allSatisfy(\.isComplete) && s.rows.allSatisfy { $0.status == "Done" })
    }

    @Test func fontScaleStepping() {
        // TV: 07 C16, C17, C18; T-KB-26, T-KB-27 (the value the router hands to setCalendarFontScale)
        var v = CalFontScale.initial(stored: nil)
        #expect(v == 15)
        var seen: [Double] = []
        for _ in 0..<9 { v = CalFontScale.stepped(v, bigger: true); seen.append(v) }
        #expect(seen == [16.5, 18, 19.5, 21, 22.5, 24, 25.5, 27, 28])
        #expect(CalFontScale.stepped(28, bigger: true) == 28)
        #expect(CalFontScale.stepped(12, bigger: false) == 11)
        #expect(CalFontScale.initial(stored: 9) == 15 && CalFontScale.initial(stored: 10) == 10)
        #expect(CalFontScale.initial(stored: 30) == 30 && CalFontScale.initial(stored: 31) == 15)
        #expect(CalFontScale.initial(stored: .nan) == 15)
        #expect(CalFontScale.stepped(30, bigger: true) == 28 && CalFontScale.stepped(10, bigger: false) == 11)
    }

    @Test func storedViewModeIsMatchedExactly() {
        // TV: 07 C19, VIEW-004
        #expect(CalViewMode(stored: "day") == .day && CalViewMode(stored: "week") == .day)
        #expect(CalViewMode(stored: "Week") == .week && CalViewMode(stored: "Month") == .month)
        #expect(CalViewMode(stored: "All") == .all && CalViewMode(stored: "Agenda") == .agenda)
        #expect(CalViewMode(stored: nil) == .day && CalViewMode(stored: "Day") == .day)
        #expect(CalViewMode.allCases.map(\.label) == ["Day", "Week", "Month", "All Upcoming", "Agenda"])
        #expect(CalViewMode.agenda.help == "All upcoming tasks grouped by day.")
    }

    @Test func orderingIsStableOverFullValues() {
        // TV: 07 C20, VIEW-009
        let first = D.task("point A", deadline: "2026-10-02")
        let ranged = D.task("ranged", start: "2026-09-30", deadline: "2026-10-05")
        let second = D.task("point B", deadline: "2026-10-02")
        let s = CalendarRowBuilder.build(data: D.data(tasks: [first, ranged, second]), mode: .week,
                                         selected: D.day("2026-10-02"), today: D.today)
        #expect(D.names(s) == ["ranged", "point A", "point B"])
        // A point row's effective start is its raw deadline, time included.
        let timed = TaskItem(name: "timed")
        timed.deadline = NetDateTime.calendarDateTime(D.day("2026-10-02"), minutes: 9 * 60)
        let early = TaskItem(name: "early")
        early.deadline = NetDateTime.calendarDateTime(D.day("2026-10-02"), minutes: 8 * 60)
        let s2 = CalendarRowBuilder.build(data: D.data(tasks: [timed, early]), mode: .day,
                                          selected: D.day("2026-10-02"), today: D.today)
        #expect(D.names(s2) == ["early", "timed"])
    }

    @Test func batchDeadlineOnRepeatedAgendaRows() {
        // TV: 07 C21 — the prompt counts rows, the service changes the item once.
        let t = D.task("R", start: "2026-09-29", deadline: "2026-10-01")
        let s = CalendarRowBuilder.build(data: D.data(tasks: [t]), mode: .agenda, selected: D.today, today: D.today)
        let selection: [AnyObject] = s.rows.map(\.item)
        #expect(selection.count == 3)
        #expect(BatchDeadline.setDeadlineAll(selection, date: D.date("2026-10-10")) == 1)
    }

    @Test func enumerationOrderAndNestedSubtasks() {
        // 07 §2.1 / §2.2: tasks pre-order with nested subtasks, then procedure + its steps, then crew items.
        let t = D.task("parent", deadline: "2026-10-01")
        let sub = D.task("sub", deadline: "2026-10-01")
        let subsub = D.task("subsub", deadline: "2026-10-01")
        sub.subtasks = [subsub]
        t.subtasks = [sub, D.task("undated")]
        let p = Procedure(name: "proc")
        p.deadline = D.date("2026-10-01")
        let st = ChecklistStep(title: "step")
        st.deadline = D.date("2026-10-01")
        p.steps = [st]
        let rows = CalendarRowBuilder.allRows(D.data(tasks: [t], procedures: [p]))
        #expect(rows.map(\.name) == ["parent", "sub", "subsub", "proc", "step   \u{00B7}  [proc]"])
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test func weekAndMonthHelpers() {
        #expect(CalendarRowBuilder.weekStart(D.day("2026-09-27")) == D.day("2026-09-27"))
        #expect(CalendarRowBuilder.weekStart(D.day("2026-10-03")) == D.day("2026-09-27"))
        #expect(CalendarRowBuilder.monthStart(D.day("2026-09-15")) == D.day("2026-09-01"))
        #expect(CalendarRowBuilder.initialTitle == "Schedule Matrix")
        #expect(CalendarRowBuilder.dayLabel(D.day("2026-10-02"), today: D.today, locale: D.enUS) == "Fri, 2026-10-02")
    }
}
