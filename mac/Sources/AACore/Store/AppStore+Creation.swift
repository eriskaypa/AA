// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §5.3
// Spec: 02 REPO-025…027, REPO-035, REPO-036 (creation catalogue). Compiling stub created by F1; F2 replaces this
// file in place. The stubs return a new DETACHED object (never inserted into the data, never logged, nothing
// marked dirty) so call sites type-check; removals are no-ops (ARCH §11).
import Foundation

extension AppStore {
    /// "+ New": default names "New Equipment/Area" / "New Task" / "New Procedure" / "New Vessel".
    @discardableResult public func createItem(kind: ItemKind, name: String? = nil) -> HierarchyItem {
        // PLACEHOLDER(F2)
        switch kind {
        case .task: return TaskItem(name: name ?? "")
        case .procedure: return Procedure(name: name ?? "")
        case .vessel: return Vessel(name: name ?? "")
        default: return Equipment(name: name ?? "")
        }
    }

    /// REPO-025.
    @discardableResult public func createLinkedProcedure(named: String, for equipment: Equipment) -> Procedure {
        // PLACEHOLDER(F2)
        Procedure(name: named)
    }

    /// REPO-026.
    @discardableResult public func createLinkedTask(named: String, for equipment: Equipment) -> TaskItem {
        // PLACEHOLDER(F2)
        TaskItem(name: named)
    }

    /// REPO-027.
    @discardableResult public func createLinkedTask(named: String, for step: ChecklistStep) -> TaskItem {
        // PLACEHOLDER(F2)
        TaskItem(name: named)
    }

    @discardableResult public func addSubtask(named: String, to parent: TaskItem, log: Bool = true) -> TaskItem {
        // PLACEHOLDER(F2)
        TaskItem(name: named)
    }

    @discardableResult public func addStep(titled: String, to procedure: Procedure, log: Bool = true) -> ChecklistStep {
        // PLACEHOLDER(F2)
        ChecklistStep(title: titled)
    }

    /// Not logged.
    @discardableResult public func addComponent(named: String, to equipment: Equipment) -> Component {
        // PLACEHOLDER(F2)
        Component(name: named)
    }

    /// Board / Ctrl+N.
    @discardableResult public func createTopLevelTask(named: String, logKind: String? = "Task") -> TaskItem {
        // PLACEHOLDER(F2)
        TaskItem(name: named)
    }

    /// Ctrl+N.
    @discardableResult public func createTopLevelProcedure(named: String) -> Procedure {
        // PLACEHOLDER(F2)
        Procedure(name: named)
    }

    /// Hard removal, no reference scrub (REPO-036).
    public func removeSubtask(_ subtask: TaskItem, from parent: TaskItem, log: Bool = true) {
        // PLACEHOLDER(F2)
    }

    public func removeStep(_ step: ChecklistStep, from procedure: Procedure, log: Bool = true) {
        // PLACEHOLDER(F2)
    }

    public func removeComponent(_ c: Component, from equipment: Equipment) {
        // PLACEHOLDER(F2)
    }
}
