// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §5.3
// Spec: 02 §2.G (REPO-060…063), DECISIONS Q-6 (generated dates are calendar dates, `.unspecified`). Compiling
// stub created by F1; F2 replaces this file in place (ARCH §11).
import Foundation

extension AppStore {
    /// REPO-060; the real result is `.asCalendarDate` (`.unspecified`). The stub returns `date` unchanged.
    public nonisolated static func nextOccurrence(from date: NetDateTime, _ r: RecurrenceKind) -> NetDateTime {
        // PLACEHOLDER(F2)
        date
    }

    /// REPO-061…063. The stub generates nothing and reports no change.
    @discardableResult public func reconcileRecurrences(today: CivilDate? = nil) -> Bool {
        // PLACEHOLDER(F2)
        false
    }
}
