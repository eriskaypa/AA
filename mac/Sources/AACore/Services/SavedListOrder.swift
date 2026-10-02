// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 02 REPO-130…136 (§3.8; Nudge = the fixed algorithm, DECISIONS 02 Q-1, OC-16). Compiling stub created by
// F1; F2 replaces this file in place. The stubs move nothing (ARCH §11).
import Foundation

@MainActor public enum SavedListOrder {
    public static func groupSpan(_ all: [ChecklistTemplate], groupID: UUID?) -> [Int] {
        // PLACEHOLDER(F2)
        []
    }

    public static func nudge(_ all: inout [ChecklistTemplate], picks: [ChecklistTemplate], up: Bool) -> Bool {
        // PLACEHOLDER(F2)
        false
    }

    public static func moveTo(_ all: inout [ChecklistTemplate], picks: [ChecklistTemplate], targetInGroup: Int) -> Bool {
        // PLACEHOLDER(F2)
        false
    }

    public static func groupEntries(_ data: AppData, groupID: UUID?) -> [(template: ChecklistTemplate, group: String?)]? {
        // PLACEHOLDER(F2)
        nil
    }

    public static func allEntries(_ data: AppData) -> [(template: ChecklistTemplate, group: String?)] {
        // PLACEHOLDER(F2)
        []
    }
}
