// Spec: 02 §2.K, §3.3 (REPO-110, REPO-111; REPO-112 dedup key and balloon text), §7.8.
import Foundation

/// Overdue / due-today / due-this-week counts (REPO-111 `Summary`).
public struct ReminderSummary: Sendable, Equatable {
    public var overdue: Int
    public var dueToday: Int
    public var dueWeek: Int

    public init(overdue: Int = 0, dueToday: Int = 0, dueWeek: Int = 0) {
        self.overdue = overdue; self.dueToday = dueToday; self.dueWeek = dueWeek
    }

    public var total: Int { overdue + dueToday + dueWeek }
    public var any: Bool { total > 0 }

    /// The non-zero parts joined with `"  ·  "`: `"{n} overdue"`, `"{n} due today"`, `"{n} due this week"`;
    /// `"Nothing due."` when all are zero.
    public func headline() -> String {
        var parts: [String] = []
        if overdue > 0 { parts.append("\(overdue) overdue") }
        if dueToday > 0 { parts.append("\(dueToday) due today") }
        if dueWeek > 0 { parts.append("\(dueWeek) due this week") }
        return parts.isEmpty ? "Nothing due." : parts.joined(separator: "  \u{00B7}  ")
    }
}

@MainActor public enum ReminderService {
    /// REPO-110: counts each dated, not-done deadline once — every top-level task and, recursively, every nested
    /// subtask that is not complete (recursion continues below completed parents); every procedure that is not
    /// Done; every procedure step that is not done (even inside a Done procedure); every crew checklist step that
    /// is not done. Bucketed by the deadline's day: before `today` → overdue, `today` → due today, up to 7 days
    /// ahead → due this week. Ranged tasks count by their deadline only.
    public static func compute(store: AppStore, today: CivilDate) -> ReminderSummary {
        var s = ReminderSummary()
        let weekEnd = today.addingDays(7)
        func count(_ d: NetDateTime?) {
            guard let d else { return }
            let day = d.civilDate
            if day < today { s.overdue += 1 } else if day == today { s.dueToday += 1 } else if day <= weekEnd { s.dueWeek += 1 }
        }
        store.repoWalkTasks { t, _ in
            if !t.isComplete { count(t.deadline) }
            return true
        }
        for p in store.data.procedures {
            if p.status != .done { count(p.deadline) }
            for st in p.steps where !st.done { count(st.deadline) }
        }
        for c in store.data.crew {
            for st in c.checklist where !st.done { count(st.deadline) }
        }
        return s
    }

    /// REPO-112: `"{today:yyyy-MM-dd}|{Overdue}|{DueToday}|{DueWeek}|{crew}"`.
    public static func dedupKey(_ s: ReminderSummary, crewExpiring: Int, today: CivilDate) -> String {
        "\(today.iso)|\(s.overdue)|\(s.dueToday)|\(s.dueWeek)|\(crewExpiring)"
    }

    /// REPO-112: the headline, plus `"  ·  {crew} crew contract(s) expiring"` when crew > 0.
    public static func notificationBody(_ s: ReminderSummary, crewExpiring: Int) -> String {
        s.headline() + (crewExpiring > 0 ? "  \u{00B7}  \(crewExpiring) crew contract(s) expiring" : "")
    }
}
