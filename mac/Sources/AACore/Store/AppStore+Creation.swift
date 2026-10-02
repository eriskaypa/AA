// Spec: 02 §2.D (REPO-035 creation catalogue, REPO-036 removal paths), REPO-025…027, REPO-091 (Kind strings),
//       DECISIONS 07 Q-03 (Board / saved-list task creation is logged); ARCHITECTURE.md §5.3.
// Every create appends at the END of its collection. Logged operations mark the store dirty through the log; the
// caller then `Save()`s where 02 says so (none of these save).
import Foundation

extension AppStore {
    /// Hierarchy "+ New": `"New Equipment/Area"` / `"New Task"` / `"New Procedure"` / `"New Vessel"` (or `name`),
    /// appended to its collection and logged `Added / KindLabel / name / ""`.
    @discardableResult public func createItem(kind: ItemKind, name: String? = nil) -> HierarchyItem {
        let item: HierarchyItem
        switch kind {
        case .task:
            let t = TaskItem(name: name ?? "New Task"); data.tasks.append(t); item = t
        case .procedure:
            let p = Procedure(name: name ?? "New Procedure"); data.procedures.append(p); item = p
        case .vessel:
            let v = Vessel(name: name ?? "New Vessel"); data.vessels.append(v); item = v
        default:
            let e = Equipment(name: name ?? "New Equipment/Area"); data.equipment.append(e); item = e
        }
        logAdded(kind: Self.kindLabel(item.kind), name: item.name, detail: "")
        return item
    }

    /// REPO-025: a top-level procedure named `named` (not trimmed), linked from the equipment's `ProcedureIds`,
    /// logged `Added / "Procedure" / name / "linked to {eq.Name}"`.
    @discardableResult public func createLinkedProcedure(named: String, for equipment: Equipment) -> Procedure {
        let p = Procedure(name: named)
        data.procedures.append(p)
        equipment.procedureIds.append(p.id)
        logAdded(kind: "Procedure", name: named, detail: "linked to \(equipment.name)")
        return p
    }

    /// REPO-026: a top-level task linked from the equipment's `TaskIds` (the task is not related back), logged
    /// `Added / "Task" / name / "linked to {eq.Name}"`.
    @discardableResult public func createLinkedTask(named: String, for equipment: Equipment) -> TaskItem {
        let t = TaskItem(name: named)
        data.tasks.append(t)
        equipment.taskIds.append(t.id)
        logAdded(kind: "Task", name: named, detail: "linked to \(equipment.name)")
        return t
    }

    /// REPO-027: a top-level task linked from the step's `TaskIds`, logged
    /// `Added / "Task" / name / "linked to step '{step.Title}'"`.
    @discardableResult public func createLinkedTask(named: String, for step: ChecklistStep) -> TaskItem {
        let t = TaskItem(name: named)
        data.tasks.append(t)
        step.taskIds.append(t.id)
        logAdded(kind: "Task", name: named, detail: "linked to step '\(step.title)'")
        return t
    }

    /// Task Specifics "+ Add" (REPO-035): appended to `parent.Subtasks`; logged `Added / "Subtask" / name /
    /// {parent name}` unless `log` is false (builders log their own bulk lines).
    @discardableResult public func addSubtask(named: String, to parent: TaskItem, log: Bool = true) -> TaskItem {
        let t = TaskItem(name: named)
        parent.subtasks.append(t)
        if log { logAdded(kind: "Subtask", name: named, detail: parent.name) } else { markDirty() }
        return t
    }

    /// Procedure "+ Step" (REPO-035): appended to `procedure.Steps`; logged `Added / "Checklist step" / title /
    /// {procedure name}` unless `log` is false.
    @discardableResult public func addStep(titled: String, to procedure: Procedure, log: Bool = true) -> ChecklistStep {
        let s = ChecklistStep(title: titled)
        procedure.steps.append(s)
        if log { logAdded(kind: "Checklist step", name: titled, detail: procedure.name) } else { markDirty() }
        return s
    }

    /// Equipment components "+ Add" (REPO-035): appended; not logged.
    @discardableResult public func addComponent(named: String, to equipment: Equipment) -> Component {
        let c = Component(name: named)
        equipment.components.append(c)
        markDirty()
        return c
    }

    /// Board / Ctrl+N "New task": a top-level task, logged `Added / {logKind} / name / ""` when `logKind` is set
    /// (DECISIONS 07 Q-03: the Board logs as "Task"; pass nil only for the unlogged saved-list path).
    @discardableResult public func createTopLevelTask(named: String, logKind: String? = "Task") -> TaskItem {
        let t = TaskItem(name: named)
        data.tasks.append(t)
        if let logKind { logAdded(kind: logKind, name: named, detail: "") } else { markDirty() }
        return t
    }

    /// Ctrl+N "New procedure": a top-level procedure logged `Added / "Procedure" / name / ""`.
    @discardableResult public func createTopLevelProcedure(named: String) -> Procedure {
        let p = Procedure(name: named)
        data.procedures.append(p)
        logAdded(kind: "Procedure", name: named, detail: "")
        return p
    }

    /// REPO-036: hard removal from the owning collection (no Trash, no reference scrub); logged
    /// `Removed / "Subtask" / name / {parent name}` unless `log` is false.
    public func removeSubtask(_ subtask: TaskItem, from parent: TaskItem, log: Bool = true) {
        guard let k = parent.subtasks.firstIndex(where: { $0 === subtask }) else { return }
        parent.subtasks.remove(at: k)
        if log { logRemoved(kind: "Subtask", name: subtask.name, detail: parent.name) } else { markDirty() }
    }

    /// REPO-036: hard removal; logged `Removed / "Checklist step" / title / {procedure name}` unless `log` is false.
    public func removeStep(_ step: ChecklistStep, from procedure: Procedure, log: Bool = true) {
        guard let k = procedure.steps.firstIndex(where: { $0 === step }) else { return }
        procedure.steps.remove(at: k)
        if log { logRemoved(kind: "Checklist step", name: step.title, detail: procedure.name) } else { markDirty() }
    }

    /// REPO-036: hard removal; not logged.
    public func removeComponent(_ c: Component, from equipment: Equipment) {
        guard let k = equipment.components.firstIndex(where: { $0 === c }) else { return }
        equipment.components.remove(at: k)
        markDirty()
    }
}
