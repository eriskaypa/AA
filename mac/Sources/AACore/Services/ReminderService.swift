// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 02 REPO-110/111 (reminder summary, dedup key, notification body). Compiling stub created by F1; F2
// replaces this file in place. The stubs report nothing due (ARCH §11).
import Foundation

public struct ReminderSummary: Sendable, Equatable {
    public var overdue: Int
    public var dueToday: Int
    public var dueWeek: Int

    public init(overdue: Int = 0, dueToday: Int = 0, dueWeek: Int = 0) {
        self.overdue = overdue; self.dueToday = dueToday; self.dueWeek = dueWeek
    }

    public var total: Int { overdue + dueToday + dueWeek }
    public var any: Bool { total > 0 }

    /// Parts joined with "  ·  "; "Nothing due." when empty.
    public func headline() -> String {
        // PLACEHOLDER(F2)
        ""
    }
}

@MainActor public enum ReminderService {
    public static func compute(store: AppStore, today: CivilDate) -> ReminderSummary {
        // PLACEHOLDER(F2)
        ReminderSummary()
    }

    public static func dedupKey(_ s: ReminderSummary, crewExpiring: Int, today: CivilDate) -> String {
        // PLACEHOLDER(F2)
        ""
    }

    public static func notificationBody(_ s: ReminderSummary, crewExpiring: Int) -> String {
        // PLACEHOLDER(F2)
        ""
    }
}
