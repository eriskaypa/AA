// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §5.3
// Spec: 02 §2.C (REPO-020…029; PurgeReferences widened per DECISIONS 02 Q-3). Compiling stub created by F1; F2
// replaces this file in place. Stubs are no-ops / empty results (ARCH §11).
import Foundation

extension AppStore {
    /// REPO-020.
    public func addRelation(_ a: HierarchyItem, _ b: HierarchyItem) {
        // PLACEHOLDER(F2)
    }

    public func removeRelation(_ a: HierarchyItem, _ b: HierarchyItem) {
        // PLACEHOLDER(F2)
    }

    /// REPO-021.
    public func relatedItems(of item: HierarchyItem) -> [HierarchyItem] {
        // PLACEHOLDER(F2)
        []
    }

    /// REPO-022.
    public func referencedBy(_ target: HierarchyItem) -> [HierarchyItem] {
        // PLACEHOLDER(F2)
        []
    }

    /// REPO-029, widened per DECISIONS 02 Q-3 (nested subtasks' RelatedIds, crew step links, ScheduleEntry.RefId,
    /// QuickViewPinIds, Selected*Id, MapFocusedItemId).
    public func purgeReferences(to deletedID: UUID) {
        // PLACEHOLDER(F2)
    }

    /// REPO-023 replace semantics (callers save).
    public func linkProcedures(_ ids: [UUID], to equipment: Equipment) {
        // PLACEHOLDER(F2)
    }

    /// REPO-024.
    public func linkTasks(_ ids: [UUID], to equipment: Equipment) {
        // PLACEHOLDER(F2)
    }

    /// REPO-027.
    public func linkTasks(_ ids: [UUID], to step: ChecklistStep) {
        // PLACEHOLDER(F2)
    }

    public func linkEquipment(_ ids: [UUID], to step: ChecklistStep) {
        // PLACEHOLDER(F2)
    }
}
