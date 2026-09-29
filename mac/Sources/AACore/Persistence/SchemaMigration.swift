// Spec: 01 DATA-022–023, 02 REPO-064 (v0 → v1: completed recurring tasks incl. nested subtasks and Done
//       recurring procedures are marked RecurrenceSpawned); ARCHITECTURE.md §6.2.
import Foundation

public enum SchemaMigration {
    @MainActor public static func migrate(_ data: AppData) {
        guard data.schemaVersion < 1 else { return }
        func mark(_ t: TaskItem, _ seen: inout Set<ObjectIdentifier>) {
            guard seen.insert(ObjectIdentifier(t)).inserted else { return }
            if t.recurrence != .none && t.isComplete { t.recurrenceSpawned = true }
            for s in t.subtasks { mark(s, &seen) }
        }
        var seen = Set<ObjectIdentifier>()
        for t in data.tasks { mark(t, &seen) }
        for p in data.procedures where p.recurrence != .none && p.status == .done { p.recurrenceSpawned = true }
    }
}
