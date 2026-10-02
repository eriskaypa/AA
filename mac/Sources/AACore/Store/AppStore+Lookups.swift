// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §5.3
// Spec: 02 §2.B, §3.24 (REPO-010…015). Compiling stub created by F1; F2 replaces this file in place (same path,
// same public signatures). Stubs return benign defaults and never mutate, crash or write files (ARCH §11).
import Foundation

/// Who owns a checklist step (templates hold `ChecklistTemplateItem` values, never `ChecklistStep`).
public enum StepOwner: Sendable, Hashable { case procedure(UUID), crew(UUID) }

extension AppStore {
    /// REPO-010: Equipment, Tasks, Procedures, Vessels order.
    public func allItems() -> [HierarchyItem] {
        // PLACEHOLDER(F2)
        []
    }

    public func items(of kind: ItemKind) -> [HierarchyItem] {
        // PLACEHOLDER(F2)
        []
    }

    /// REPO-011 FindById (first wins; top level only).
    public func item(id: UUID) -> HierarchyItem? {
        // PLACEHOLDER(F2)
        nil
    }

    /// Recursive, including subtasks (Board / Planner / editors).
    public func task(id: UUID) -> TaskItem? {
        // PLACEHOLDER(F2)
        nil
    }

    /// nil for a top-level task.
    public func parentTask(of subtaskID: UUID) -> TaskItem? {
        // PLACEHOLDER(F2)
        nil
    }

    public func topLevelTask(containing taskID: UUID) -> TaskItem? {
        // PLACEHOLDER(F2)
        nil
    }

    public func step(id: UUID) -> (step: ChecklistStep, owner: StepOwner)? {
        // PLACEHOLDER(F2)
        nil
    }

    public func component(id: UUID) -> (component: Component, equipment: Equipment)? {
        // PLACEHOLDER(F2)
        nil
    }

    public func crewMember(id: UUID) -> CrewMember? {
        // PLACEHOLDER(F2)
        nil
    }

    public func template(id: UUID) -> ChecklistTemplate? {
        // PLACEHOLDER(F2)
        nil
    }

    public func bucket(id: UUID) -> QuickBucket? {
        // PLACEHOLDER(F2)
        nil
    }

    public func vessel(id: UUID) -> Vessel? {
        // PLACEHOLDER(F2)
        nil
    }

    /// Search / navigation: the top-level owner of any id (item, subtask, step, component) and the child id.
    public func topLevelOwner(ofAnyID id: UUID) -> (owner: HierarchyItem, childID: UUID?)? {
        // PLACEHOLDER(F2)
        nil
    }

    /// REPO-012 order.
    public func allContainers() -> [Container] {
        // PLACEHOLDER(F2)
        []
    }

    /// REPO-013 order.
    public func allJobs() -> [any SchedulableJob] {
        // PLACEHOLDER(F2)
        []
    }

    /// "Task" / "Subtask" / "Procedure" / "Step" / "Crew".
    public func jobOwnerLabel(_ job: any SchedulableJob) -> String {
        // PLACEHOLDER(F2)
        ""
    }

    /// REPO-014: "(missing)" | "[Kind] Name".
    public func label(for id: UUID) -> String {
        // PLACEHOLDER(F2)
        ""
    }

    /// REPO-015.
    public nonisolated static func kindLabel(_ kind: ItemKind) -> String {
        // PLACEHOLDER(F2)
        ""
    }
}
