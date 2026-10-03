// Tests for 02 §7.14 / 08 §7.3 (quick-switcher scoring, T-QS-1…10), DECISIONS 08 OQ-8 (locked descriptions gated),
// 02 §7.8 (reminders), REPO-112 (dedup key, notification body).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct SvcSwitcherReminderTests {
    private func row(_ name: String, _ kind: ItemKind = .task, tags: [String] = [], description: String = "") -> QuickSwitcherScoring.Row {
        QuickSwitcherScoring.Row(id: UUID(), name: name, kind: kind, kindLabel: AppStore.kindLabel(kind), tags: tags,
                                 description: description)
    }

    private func score(_ r: QuickSwitcherScoring.Row, _ q: String) -> Int {
        QuickSwitcherScoring.score(r, query: QuickSwitcherScoring.normalizeQuery(q))
    }

    @Test func scoringVectors() {
        // TV: 02 §7.14; 08 T-QS-1…7
        #expect(score(row("Main Engine", tags: ["engine"]), "eng") == 105)
        #expect(score(row("Equipment Pump", .equipment), "eqpump") == 25)
        #expect(score(row("Pump"), "#pu") == 120)
        #expect(score(row("Anything"), "") == 1)
        #expect(score(row("Pump room", tags: ["pumps"]), "pump") == 165)
        #expect(score(row("Main pump"), "pump") == 60)
        #expect(score(row("Fire drill"), "task") == 8)
        #expect(score(row("Deck", .equipment), "area") == 8)
        #expect(score(row("Aurora", .vessel, description: "Aframax tanker"), "tanker") == 5)
        #expect(QuickSwitcherScoring.normalizeQuery("##Safety") == "Safety")
        #expect(score(row("x", tags: ["safety-walk"]), "##Safety") == 45)
        #expect(QuickSwitcherScoring.normalizeQuery("  #pump ") == "pump")
    }

    @Test func rankingAndSubsequence() {
        // TV: 08 T-QS-8, T-QS-9, T-QS-10
        let rows = [row("b pump"), row("A pump"), row("zeta"), row("Alpha")]
        #expect(QuickSwitcherScoring.rank(rows, query: "pump").map(\.name) == ["A pump", "b pump"])
        #expect(QuickSwitcherScoring.rank(rows, query: "#").map(\.name) == ["A pump", "Alpha", "b pump", "zeta"])
        let many = (0..<100).map { row("item \($0)") }
        #expect(QuickSwitcherScoring.rank(many, query: "").count == 80)
        #expect(QuickSwitcherScoring.rank(many, query: "", limit: 5).count == 5)
        #expect(QuickSwitcherScoring.isSubsequence("", of: "x"))
        #expect(!QuickSwitcherScoring.isSubsequence("ab", of: "ba"))
        #expect(QuickSwitcherScoring.isSubsequence("MP", of: "main pump"))
    }

    @Test func rowsFromStoreGateLockedDescriptions() {
        // DECISIONS 08 OQ-8
        let made = StoreFactory.make(); let store = made.store
        let open = TaskItem(name: "Open"); open.description = "valve"; open.tags = ["a"]
        let locked = TaskItem(name: "Locked"); locked.description = "valve codes"
        locked.lockHash = "h"; locked.lockSalt = "s"
        let e = Equipment(name: "E")
        store.data.equipment = [e]; store.data.tasks = [open, locked]
        let rows = QuickSwitcherScoring.rows(store: store)
        #expect(rows.map(\.name) == ["E", "Open", "Locked"])
        #expect(rows[0].kindLabel == "Equipment/Area" && rows[1].tags == ["a"])
        #expect(rows[1].description == "valve" && rows[2].description == "")
        #expect(QuickSwitcherScoring.rank(rows, query: "valve").map(\.name) == ["Open"])
        let unlocked = QuickSwitcherScoring.rows(store: store, isGated: { _ in false })
        #expect(unlocked[2].description == "valve codes")
    }

    @Test func reminderCounts() {
        // TV: 02 §7.8
        let made = StoreFactory.make(); let store = made.store
        func day(_ s: String) -> NetDateTime { NetDateTime.calendarDate(CivilDate(iso: s)!) }
        let t1 = TaskItem(name: "T1"); t1.deadline = day("2026-09-28")
        let s1 = TaskItem(name: "S1"); s1.deadline = day("2026-09-29"); t1.subtasks = [s1]
        let t2 = TaskItem(name: "T2"); t2.deadline = day("2026-10-06")
        let t3 = TaskItem(name: "T3"); t3.deadline = day("2026-10-07")
        let t4 = TaskItem(name: "T4"); t4.deadline = day("2026-09-20"); t4.isComplete = true
        let t5 = TaskItem(name: "T5"); t5.rangeStart = day("2026-09-25"); t5.deadline = day("2026-10-02")
        let p1 = Procedure(name: "P1"); p1.status = .inProgress; p1.deadline = day("2026-09-29")
        let p1s = ChecklistStep(title: "p1s"); p1s.deadline = day("2026-09-30"); p1.steps = [p1s]
        let p2 = Procedure(name: "P2"); p2.status = .done; p2.deadline = day("2026-09-01")
        let p2s = ChecklistStep(title: "p2s"); p2s.deadline = day("2026-09-02"); p2.steps = [p2s]
        let c = CrewMember(); let cs = ChecklistStep(title: "cs"); cs.deadline = day("2026-09-29"); cs.done = true
        c.checklist = [cs]
        store.data.tasks = [t1, t2, t3, t4, t5]; store.data.procedures = [p1, p2]; store.data.crew = [c]
        let today = CivilDate(iso: "2026-09-29")!
        let s = ReminderService.compute(store: store, today: today)
        // Overdue T1, P2's step; today S1, P1; this week T2, P1's step, T5 (by its deadline). T3 (10-07) is day 8.
        #expect(s == ReminderSummary(overdue: 2, dueToday: 2, dueWeek: 3))
        #expect(s.headline() == "2 overdue  \u{00B7}  2 due today  \u{00B7}  3 due this week")
        #expect(ReminderService.dedupKey(s, crewExpiring: 4, today: today) == "2026-09-29|2|2|3|4")
        #expect(ReminderService.notificationBody(s, crewExpiring: 0) == s.headline())
        #expect(ReminderService.notificationBody(s, crewExpiring: 2)
                == "2 overdue  \u{00B7}  2 due today  \u{00B7}  3 due this week  \u{00B7}  2 crew contract(s) expiring")
        #expect(ReminderSummary().headline() == "Nothing due." && !ReminderSummary().any)
        #expect(ReminderSummary(dueWeek: 1).headline() == "1 due this week")
        #expect(ReminderSummary(overdue: 1, dueToday: 2, dueWeek: 3).total == 6)
        // Subtasks below a completed parent still count (recursion continues).
        t1.isComplete = true
        #expect(ReminderService.compute(store: store, today: today) == ReminderSummary(overdue: 1, dueToday: 2, dueWeek: 3))
    }
}
