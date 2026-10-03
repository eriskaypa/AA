// Spec: 02 §2.G, §3.1.6 (REPO-060…063), 01 §3.18 (DATA-120, DATA-121), 01 §7.11; DECISIONS Q-6 / ARCHITECTURE.md
//       §3.4 (every generated or shifted date is a calendar date, written `.unspecified`); 02 §8 D-4 / Q-2 (parity:
//       clones are not re-linked); ARCHITECTURE.md §5.3.
import Foundation

extension AppStore {
    /// REPO-060: Daily +1 day, Weekly +7 days, Monthly +1 calendar month (end-of-month clamp), Yearly +1 year
    /// (Feb 29 → Feb 28), None (or an undefined value) → unchanged. Time of day is kept; the result is a calendar
    /// date (`.unspecified`, DECISIONS Q-6).
    public nonisolated static func nextOccurrence(from date: NetDateTime, _ r: RecurrenceKind) -> NetDateTime {
        switch r {
        case .daily: return date.addingDays(1).asCalendarDate
        case .weekly: return date.addingDays(7).asCalendarDate
        case .monthly: return date.addingMonths(1).asCalendarDate
        case .yearly: return date.addingYears(1).asCalendarDate
        default: return date.asCalendarDate
        }
    }

    /// REPO-061…063: for each TOP-LEVEL task (snapshot) with `Recurrence != None`, complete and not yet spawned —
    /// and each procedure with `Status == Done` — marks the source spawned, deep-clones it, renews the clone (new
    /// ids, not done, no Planner placement), moves its deadline to the next occurrence (from the old deadline, or
    /// from `today` when there was none), keeps a working range's length, shifts nested subtask / step dates by the
    /// same number of days (only when the source had a deadline), logs the spawn and appends the clones after the
    /// loop. Returns true and marks dirty when anything was generated.
    @discardableResult public func reconcileRecurrences(today: CivilDate? = nil) -> Bool {
        let day = NetDateTime.calendarDate(today ?? clock.today())
        let ctx = repoDecodeContext
        var changed = false

        var newTasks: [TaskItem] = []
        for t in Array(data.tasks) {
            guard t.recurrence != .none, t.isComplete, !t.recurrenceSpawned else { continue }
            t.recurrenceSpawned = true
            let clone = ModelCodec.deepClone(t, context: ctx)
            Self.repoRenewTask(clone, visited: [])
            let old = t.deadline
            let next = Self.nextOccurrence(from: old ?? day, t.recurrence)
            if let rs = t.rangeStart, let dl = old, rs.civilDate < dl.civilDate {
                let length = rs.civilDate.days(to: dl.civilDate)
                clone.rangeStart = next.addingDays(-length).asCalendarDate
            } else {
                clone.rangeStart = nil
            }
            clone.deadline = next
            if let od = old {
                Self.repoShiftChildren(of: clone, by: od.civilDate.days(to: next.civilDate), visited: [])
            }
            newTasks.append(clone)
            logAdded(kind: "Task (recurring)", name: clone.name,
                     detail: "next \(t.recurrence.name) occurrence \u{2192} \(next.format(.isoDate))")
            changed = true
        }
        data.tasks.append(contentsOf: newTasks)

        var newProcedures: [Procedure] = []
        for p in Array(data.procedures) {
            guard p.recurrence != .none, p.status == .done, !p.recurrenceSpawned else { continue }
            p.recurrenceSpawned = true
            let clone = ModelCodec.deepClone(p, context: ctx)
            Self.repoRenewProcedure(clone)
            let old = p.deadline
            let next = Self.nextOccurrence(from: old ?? day, p.recurrence)
            clone.deadline = next
            if let od = old {
                let delta = od.civilDate.days(to: next.civilDate)
                for s in clone.steps {
                    if let sd = s.deadline { s.deadline = sd.addingDays(delta).asCalendarDate }
                }
            }
            newProcedures.append(clone)
            logAdded(kind: "Procedure (recurring)", name: clone.name,
                     detail: "next \(p.recurrence.name) occurrence \u{2192} \(next.format(.isoDate))")
            changed = true
        }
        data.procedures.append(contentsOf: newProcedures)

        if changed { markDirty() }
        return changed
    }

    /// `RenewTaskForNextOccurrence`: new Id and Container.Id, not spawned, no ScheduledStart, not complete (Done →
    /// Todo; InProgress/Blocked kept by the IsComplete setter), recursively. File-item ids are kept (REPO-146 note).
    private static func repoRenewTask(_ t: TaskItem, visited seen: Set<ObjectIdentifier>) {
        var seen = seen
        guard seen.insert(ObjectIdentifier(t)).inserted else { return }
        t.id = UUID()
        t.container.id = UUID()
        t.recurrenceSpawned = false
        t.scheduledStart = nil
        t.isComplete = false
        for s in t.subtasks { repoRenewTask(s, visited: seen) }
    }

    private static func repoRenewProcedure(_ p: Procedure) {
        p.id = UUID()
        p.container.id = UUID()
        p.recurrenceSpawned = false
        p.scheduledStart = nil
        p.status = .todo
        for s in p.steps {
            s.id = UUID()
            s.container.id = UUID()
            s.done = false
            s.scheduledStart = nil
        }
    }

    /// Shifts every nested subtask's Deadline and RangeStart (each only if set) by `days`, recursively; shifted
    /// dates are calendar dates (`.unspecified`).
    private static func repoShiftChildren(of t: TaskItem, by days: Int, visited seen: Set<ObjectIdentifier>) {
        var seen = seen
        guard seen.insert(ObjectIdentifier(t)).inserted else { return }
        for s in t.subtasks {
            if let d = s.deadline { s.deadline = d.addingDays(days).asCalendarDate }
            if let r = s.rangeStart { s.rangeStart = r.addingDays(days).asCalendarDate }
            repoShiftChildren(of: s, by: days, visited: seen)
        }
    }
}
