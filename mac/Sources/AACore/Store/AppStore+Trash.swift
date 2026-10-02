// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §5.3
// Spec: 02 §2.H (REPO-070…081), DECISIONS 02 Q-4 (Board & Ctrl+N deletes through the Trash), DECISIONS 09
// ("Clear all" crew = one Trash batch). Compiling stub created by F1; F2 replaces this file in place. The stubs
// move nothing to the Trash and delete nothing (ARCH §11).
import Foundation

extension AppStore {
    public static let maxTrashItems = 200
    public static let trashRetentionDays = 90

    /// REPO-070. TOP-LEVEL items only (Equipment / Tasks / Procedures / Vessels arrays); nil for anything else
    /// (e.g. a nested subtask — use `trashSubtask`).
    @discardableResult public func trash(_ item: HierarchyItem, batchID: UUID? = nil) -> TrashedItem? {
        // PLACEHOLDER(F2)
        nil
    }

    /// DECISIONS 02 Q-4 for Board subtask cards (REPO-081, VIEW-052): ItemType "Task", parent id stored as the
    /// unknown member "ParentTaskId" on the TrashedItem.
    @discardableResult public func trashSubtask(_ subtask: TaskItem, batchID: UUID? = nil) -> TrashedItem? {
        // PLACEHOLDER(F2)
        nil
    }

    /// REPO-072.
    @discardableResult public func trashItems(_ items: [HierarchyItem]) -> Int {
        // PLACEHOLDER(F2)
        0
    }

    /// REPO-071. The stub returns an empty, detached entry (nothing is removed or recorded).
    @discardableResult public func trash(_ member: CrewMember, batchID: UUID? = nil) -> TrashedItem {
        // PLACEHOLDER(F2)
        TrashedItem()
    }

    /// DECISIONS 09: "Clear all" = one Trash batch (undoable); logs Removed / "Crew" / "all {n} member(s)".
    @discardableResult public func trashAllCrew() -> Int {
        // PLACEHOLDER(F2)
        0
    }

    /// REPO-076.
    public func restore(_ entry: TrashedItem) -> TrashItemType? {
        // PLACEHOLDER(F2)
        nil
    }

    /// REPO-080.
    public func purge(_ entry: TrashedItem) {
        // PLACEHOLDER(F2)
    }

    public func emptyTrash() {
        // PLACEHOLDER(F2)
    }

    /// REPO-079.
    @discardableResult public func pruneTrash(now: NetDateTime? = nil) -> Bool {
        // PLACEHOLDER(F2)
        false
    }

    /// REPO-077.
    public func pendingUndoCount() -> Int {
        // PLACEHOLDER(F2)
        0
    }

    /// REPO-077.
    public func undoLastDelete() -> [TrashItemType] {
        // PLACEHOLDER(F2)
        []
    }

    /// Board (REPO-081): recursive removal + purgeReferences; not logged.
    public func hardDeleteTask(_ task: TaskItem) {
        // PLACEHOLDER(F2)
    }

    /// Ctrl+N (REPO-081): logs Removed, removes, purges, unpins.
    public func hardDelete(_ item: HierarchyItem) {
        // PLACEHOLDER(F2)
    }
}
