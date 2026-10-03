// Tests for 02 §7.2/§7.3 (T-DONE, T-RNG, T-DL), 04 §7.2, §7.4, §7.5, 06 §7.1; DECISIONS Q-6 (changed dates come
// out `.unspecified`, kept dates keep their originalText).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct SvcWorkRangeBatchTests {
    private func d(_ s: String) -> NetDateTime { NetDateTime.calendarDate(CivilDate(iso: s)!) }
    private func dt(_ s: String) -> NetDateTime { NetDateTime(parsing: s, zone: TZ.athens)! }
    private func iso(_ x: NetDateTime?) -> String? { x?.format(.isoMinute) }

    @Test func coerceVectors() {
        // TV: 02 T-RNG-1…7; 04 §7.2; 06 §7.1
        func c(_ s: String?, _ e: String?, _ edited: Bool) -> [String?] {
            let r = WorkRange.coerce(start: s.map(dt), deadline: e.map(dt), editedStart: edited)
            return [iso(r.start), iso(r.deadline)]
        }
        #expect(c(nil, nil, true) == [nil, nil])
        #expect(c(nil, "2026-10-05", false) == [nil, "2026-10-05 00:00"])
        #expect(c("2026-10-01", nil, true) == ["2026-10-01 00:00", "2026-10-01 00:00"])
        #expect(c("2026-10-01", nil, false) == ["2026-10-01 00:00", "2026-10-01 00:00"])
        #expect(c("2026-10-01", "2026-10-05", true) == ["2026-10-01 00:00", "2026-10-05 00:00"])
        #expect(c("2026-10-07", "2026-10-05", true) == ["2026-10-07 00:00", "2026-10-07 00:00"])
        #expect(c("2026-10-07", "2026-10-05", false) == ["2026-10-05 00:00", "2026-10-05 00:00"])
        #expect(c("2026-10-01T15:30", "2026-10-05T08:00", true) == ["2026-10-01 00:00", "2026-10-05 00:00"])
        #expect(c("2026-07-10T09:30", "2026-07-10T18:00", false) == ["2026-07-10 00:00", "2026-07-10 00:00"])
        #expect(c("2026-01-03", nil, false) == ["2026-01-03 00:00", "2026-01-03 00:00"])
    }

    @Test func coerceKeepsUnchangedTextAndMakesChangedDatesCalendarDates() {
        // ARCHITECTURE.md §3.4 calendar-date rule
        let start = NetDateTime(parsing: "2026-10-01T00:00:00+03:00", zone: TZ.athens)!
        let end = NetDateTime(parsing: "2026-10-05T00:00:00", zone: TZ.athens)!
        let kept = WorkRange.coerce(start: start, deadline: end, editedStart: true)
        #expect(kept.start?.originalText == "2026-10-01T00:00:00+03:00")
        #expect(kept.deadline?.originalText == "2026-10-05T00:00:00")
        let moved = WorkRange.coerce(start: start, deadline: nil, editedStart: true)
        #expect(moved.deadline?.kind == .unspecified && moved.deadline?.originalText == nil)
        let stripped = WorkRange.coerce(start: dt("2026-10-01T15:30"), deadline: nil, editedStart: true)
        #expect(stripped.start?.kind == .unspecified && stripped.start?.originalText == nil)
    }

    @Test func taskRangeHelpers() {
        // TV: 02 T-RNG-8, T-RNG-9 (F1 model helpers, asserted here with the service vectors)
        let t = TaskItem(name: "t"); t.rangeStart = d("2026-10-01"); t.deadline = d("2026-10-05")
        #expect(t.hasRange && t.rangeFirst == d("2026-10-01") && t.whenText == "2026-10-01 \u{2192} 2026-10-05")
        #expect(t.coversDay(CivilDate(iso: "2026-10-03")!) && !t.coversDay(CivilDate(iso: "2026-10-06")!))
        t.rangeStart = d("2026-10-07")
        #expect(t.coversDay(CivilDate(iso: "2026-10-05")!) && !t.coversDay(CivilDate(iso: "2026-10-06")!))
        #expect(!t.hasRange && t.whenText == "2026-10-05")
    }

    @Test func setDeadlineOnTasks() {
        // TV: 02 T-DL-1…5, T-DL-8; 04 §7.4
        let t = TaskItem(name: "t")
        #expect(!BatchDeadline.setDeadline(t, date: nil))
        t.rangeStart = d("2026-10-01"); t.deadline = d("2026-10-05")
        #expect(BatchDeadline.setDeadline(t, date: d("2026-10-03")))
        #expect(iso(t.rangeStart) == "2026-10-01 00:00" && iso(t.deadline) == "2026-10-03 00:00")
        #expect(BatchDeadline.setDeadline(t, date: d("2026-09-28")))
        #expect(iso(t.rangeStart) == "2026-09-28 00:00" && iso(t.deadline) == "2026-09-28 00:00")
        #expect(BatchDeadline.setDeadline(t, date: nil))
        #expect(t.rangeStart == nil && t.deadline == nil)
        #expect(!BatchDeadline.setDeadline(t, date: nil))

        let u = TaskItem(name: "u"); u.deadline = d("2026-10-05")
        #expect(!BatchDeadline.setDeadline(u, date: dt("2026-10-05T14:00")))
        let local = TaskItem(name: "l"); local.deadline = NetDateTime(parsing: "2026-10-05T00:00:00+03:00", zone: TZ.athens)
        #expect(!BatchDeadline.setDeadline(local, date: d("2026-10-05")))
        #expect(local.deadline?.originalText == "2026-10-05T00:00:00+03:00")

        // 04 §7.4
        let r = TaskItem(name: "r"); r.rangeStart = d("2026-01-10"); r.deadline = d("2026-01-12")
        #expect(BatchDeadline.setDeadline(r, date: d("2026-01-08")))
        #expect(iso(r.rangeStart) == "2026-01-08 00:00" && iso(r.deadline) == "2026-01-08 00:00")
        let r2 = TaskItem(name: "r2"); r2.rangeStart = d("2026-01-10"); r2.deadline = d("2026-01-12")
        #expect(BatchDeadline.setDeadline(r2, date: d("2026-01-11")))
        #expect(iso(r2.rangeStart) == "2026-01-10 00:00" && iso(r2.deadline) == "2026-01-11 00:00")
        #expect(r2.deadline?.kind == .unspecified)
    }

    @Test func setDeadlineOnOtherKinds() {
        // TV: 02 T-DL-6, T-DL-7; 04 §7.4 mixed selection
        let p = Procedure(name: "p"); p.deadline = d("2026-10-05")
        #expect(!BatchDeadline.setDeadline(p, date: d("2026-10-05")))
        #expect(!BatchDeadline.setDeadline(p, date: dt("2026-10-05T13:00")))
        #expect(BatchDeadline.setDeadline(p, date: nil) && p.deadline == nil)
        #expect(!BatchDeadline.setDeadline(Equipment(name: "e"), date: d("2026-10-05")))
        #expect(!BatchDeadline.setDeadline(nil, date: d("2026-10-05")))
        let items: [AnyObject] = [TaskItem(name: "t"), ChecklistStep(title: "s"), Procedure(name: "p"), "string" as NSString]
        #expect(BatchDeadline.setDeadlineAll(items, date: d("2026-02-01")) == 3)
    }

    @Test func sharedDeadlinePrefill() {
        // TV: 04 §7.4 prefill; REPO-053
        let a = TaskItem(name: "a"), b = TaskItem(name: "b")
        #expect(BatchDeadline.sharedDeadline(of: [a, b]) == .some(nil))
        a.deadline = d("2026-01-05"); b.deadline = d("2026-01-05")
        #expect(BatchDeadline.sharedDeadline(of: [a, b]) == .some(d("2026-01-05")))
        b.deadline = nil
        #expect(BatchDeadline.sharedDeadline(of: [a, b]) == nil)
        #expect(BatchDeadline.sharedDeadline(of: [a, Equipment(name: "e")]) == nil)
    }

    @Test func batchDoneVectors() {
        // TV: 02 T-DONE-1…9; 04 §7.5
        let t = TaskItem(name: "t"); t.status = .inProgress
        #expect(BatchDone.setDone(t, done: true) && t.isComplete && t.status == .done)
        let b = TaskItem(name: "b"); b.status = .blocked
        #expect(!BatchDone.setDone(b, done: false) && b.status == .blocked)
        let c = TaskItem(name: "c"); c.isComplete = true
        #expect(BatchDone.setDone(c, done: false) && !c.isComplete && c.status == .todo)
        let e = TaskItem(name: "e"); e.isComplete = true; e.status = .inProgress
        #expect(!e.isComplete)
        let p = Procedure(name: "p"); p.status = .inProgress
        #expect(!BatchDone.setDone(p, done: false) && p.status == .inProgress)
        p.status = .done
        #expect(BatchDone.setDone(p, done: false) && p.status == .todo)
        p.status = .blocked
        #expect(BatchDone.setDone(p, done: true) && p.status == .done)
        #expect(!BatchDone.setDone(p, done: true))
        let s = ChecklistStep(title: "s"); s.done = true
        #expect(!BatchDone.setDone(s, done: true))
        #expect(BatchDone.setDone(s, done: false) && !s.done)
        let doneStep = ChecklistStep(title: "d"); doneStep.done = true
        let doneProc = Procedure(name: "dp"); doneProc.status = .done
        let items: [AnyObject] = [TaskItem(name: "x"), doneStep, doneProc, "x" as NSString]
        #expect(BatchDone.setDoneAll(items, done: true) == 1)
        #expect(!BatchDone.setDone(nil, done: true) && !BatchDone.setDone(Vessel(name: "v"), done: true))
    }

    @Test func rowWrappersAreUnwrapped() {
        // REPO-074 / 02 §5.3 (row wrappers expose the model)
        final class Row: SvcModelRow { let model: TaskItem; init(_ m: TaskItem) { model = m }
            var svcRowModel: AnyObject? { model } }
        final class LegacyRow { let item: TaskItem; init(_ m: TaskItem) { item = m } }
        let t = TaskItem(name: "t"), u = TaskItem(name: "u")
        #expect(BatchDone.setDone(Row(t), done: true) && t.isComplete)
        #expect(BatchDone.setDone(LegacyRow(u), done: true) && u.isComplete)
    }
}
