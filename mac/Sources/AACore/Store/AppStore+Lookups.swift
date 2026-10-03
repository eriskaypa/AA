// Spec: 02 §2.B, §3.1.2 (REPO-010…015), 01 §3.24 (DATA-138); ARCHITECTURE.md §5.3.
// Lookups never mutate and never save. Every walk over nested subtasks is cycle-guarded (a malformed file that
// made a task its own ancestor must not hang the app).
import Foundation

/// Who owns a checklist step (templates hold `ChecklistTemplateItem` values, never `ChecklistStep`).
public enum StepOwner: Sendable, Hashable { case procedure(UUID), crew(UUID) }

extension AppStore {
    /// REPO-010: every top-level item — all Equipment, then Tasks, then Procedures, then Vessels, each in
    /// collection order. Nested subtasks, steps and components are not included.
    public func allItems() -> [HierarchyItem] {
        var out: [HierarchyItem] = []
        out.reserveCapacity(data.equipment.count + data.tasks.count + data.procedures.count + data.vessels.count)
        out.append(contentsOf: data.equipment as [HierarchyItem])
        out.append(contentsOf: data.tasks as [HierarchyItem])
        out.append(contentsOf: data.procedures as [HierarchyItem])
        out.append(contentsOf: data.vessels as [HierarchyItem])
        return out
    }

    /// The top-level items of one kind, in collection order.
    public func items(of kind: ItemKind) -> [HierarchyItem] {
        switch kind {
        case .equipment: return data.equipment
        case .task: return data.tasks
        case .procedure: return data.procedures
        case .vessel: return data.vessels
        default: return []
        }
    }

    /// REPO-011 FindById: the first top-level item (Equipment, Task, Procedure, Vessel order) with that id.
    /// Subtasks are not found here (use `task(id:)`).
    public func item(id: UUID) -> HierarchyItem? {
        if let e = data.equipment.first(where: { $0.id == id }) { return e }
        if let t = data.tasks.first(where: { $0.id == id }) { return t }
        if let p = data.procedures.first(where: { $0.id == id }) { return p }
        return data.vessels.first(where: { $0.id == id })
    }

    /// Any task with that id: top-level first, then nested subtasks (pre-order, first match wins).
    public func task(id: UUID) -> TaskItem? {
        var found: TaskItem?
        repoWalkTasks { t, _ in
            if t.id == id { found = t; return false }
            return true
        }
        return found
    }

    /// The task whose `Subtasks` directly contains `subtaskID`; nil for a top-level task or an unknown id.
    public func parentTask(of subtaskID: UUID) -> TaskItem? {
        var found: TaskItem?
        repoWalkTasks { t, _ in
            if t.subtasks.contains(where: { $0.id == subtaskID }) { found = t; return false }
            return true
        }
        return found
    }

    /// The top-level task that is, or contains (at any depth), the task with that id.
    public func topLevelTask(containing taskID: UUID) -> TaskItem? {
        var found: TaskItem?
        repoWalkTasks { t, root in
            if t.id == taskID { found = root; return false }
            return true
        }
        return found
    }

    /// A checklist step anywhere: procedure steps first, then crew checklist items.
    public func step(id: UUID) -> (step: ChecklistStep, owner: StepOwner)? {
        for p in data.procedures {
            if let s = p.steps.first(where: { $0.id == id }) { return (s, .procedure(p.id)) }
        }
        for c in data.crew {
            if let s = c.checklist.first(where: { $0.id == id }) { return (s, .crew(c.id)) }
        }
        return nil
    }

    public func component(id: UUID) -> (component: Component, equipment: Equipment)? {
        for e in data.equipment {
            if let c = e.components.first(where: { $0.id == id }) { return (c, e) }
        }
        return nil
    }

    public func crewMember(id: UUID) -> CrewMember? { data.crew.first { $0.id == id } }

    public func template(id: UUID) -> ChecklistTemplate? { data.checklistTemplates.first { $0.id == id } }

    public func bucket(id: UUID) -> QuickBucket? { data.quickBuckets.first { $0.id == id } }

    public func vessel(id: UUID) -> Vessel? { data.vessels.first { $0.id == id } }

    /// Search / navigation (DECISIONS 02 Q-11): the top-level owner of any id — an item (`childID` nil), or the
    /// item that holds a nested subtask, a procedure step or an equipment component (`childID` = that id).
    /// Crew checklist steps have no hierarchy owner (nil).
    public func topLevelOwner(ofAnyID id: UUID) -> (owner: HierarchyItem, childID: UUID?)? {
        if let i = item(id: id) { return (i, nil) }
        if let root = topLevelTask(containing: id) { return (root, id) }
        for p in data.procedures where p.steps.contains(where: { $0.id == id }) { return (p, id) }
        for e in data.equipment where e.components.contains(where: { $0.id == id }) { return (e, id) }
        return nil
    }

    /// REPO-012: every container in this order — each Equipment's container then its components'; each top-level
    /// task's container then, pre-order, every nested subtask's; each Procedure's then its steps'; each Vessel's;
    /// each crew member's checklist steps'; each saved list's items'.
    public func allContainers() -> [Container] {
        var out: [Container] = []
        for e in data.equipment {
            out.append(e.container)
            for c in e.components { out.append(c.container) }
        }
        repoWalkTasks { t, _ in out.append(t.container); return true }
        for p in data.procedures {
            out.append(p.container)
            for s in p.steps { out.append(s.container) }
        }
        for v in data.vessels { out.append(v.container) }
        for c in data.crew { for s in c.checklist { out.append(s.container) } }
        for t in data.checklistTemplates { for it in t.items { out.append(it.container) } }
        return out
    }

    /// REPO-013: every schedulable job (`IsJob`) — tasks pre-order with all nested subtasks; then per procedure
    /// the procedure itself, then its steps; then each crew member's checklist steps.
    public func allJobs() -> [any SchedulableJob] {
        var out: [any SchedulableJob] = []
        repoWalkTasks { t, _ in
            if t.isJob { out.append(t) }
            return true
        }
        for p in data.procedures {
            if p.isJob { out.append(p) }
            for s in p.steps where s.isJob { out.append(s) }
        }
        for c in data.crew {
            for s in c.checklist where s.isJob { out.append(s) }
        }
        return out
    }

    /// "Task" (top level) / "Subtask" / "Procedure" / "Step" (procedure step) / "Crew" (crew checklist item).
    public func jobOwnerLabel(_ job: any SchedulableJob) -> String {
        switch job {
        case let t as TaskItem:
            return data.tasks.contains(where: { $0 === t }) ? "Task" : "Subtask"
        case is Procedure:
            return "Procedure"
        case let s as ChecklistStep:
            if data.procedures.contains(where: { p in p.steps.contains { $0 === s } }) { return "Step" }
            if data.crew.contains(where: { c in c.checklist.contains { $0 === s } }) { return "Crew" }
            return "Step"
        default:
            return ""
        }
    }

    /// REPO-014: `"(missing)"` when `item(id:)` is nil, else `"[{Kind}] {Name}"` with the enum name
    /// (`Equipment`, `Task`, `Procedure`, `Vessel`) — not the friendly label.
    public func label(for id: UUID) -> String {
        guard let i = item(id: id) else { return "(missing)" }
        return "[\(i.kind.name)] \(i.name)"
    }

    /// REPO-015: Equipment → "Equipment/Area", Task → "Task", Procedure → "Procedure", Vessel → "Vessel",
    /// otherwise the enum name.
    public nonisolated static func kindLabel(_ kind: ItemKind) -> String {
        kind == .equipment ? "Equipment/Area" : kind.name
    }

    // MARK: Internal walks

    /// Pre-order walk over every top-level task and all nested subtasks (cycle-guarded by object identity).
    /// `visit(task, rootTask)` returns false to stop the walk.
    func repoWalkTasks(_ visit: (TaskItem, TaskItem) -> Bool) {
        var seen = Set<ObjectIdentifier>()
        func walk(_ t: TaskItem, _ root: TaskItem) -> Bool {
            guard seen.insert(ObjectIdentifier(t)).inserted else { return true }
            if !visit(t, root) { return false }
            for s in t.subtasks where !walk(s, root) { return false }
            return true
        }
        for t in data.tasks where !walk(t, t) { return }
    }

    /// The decode context used for Trash payloads and deep clones (the store's clock and zone).
    var repoDecodeContext: JSONDecodeContext {
        JSONDecodeContext(zone: clock.timeZone, clock: clock)
    }
}

extension TaskItem {
    /// Nested subtasks (pre-order) — cycle-guarded by id as `BatchDelete.Descendants` is (02 §3.7).
    func repoDescendantsByID() -> [TaskItem] {
        var out: [TaskItem] = []
        var seen = Set<UUID>()
        var stack: [TaskItem] = subtasks.reversed()
        while let t = stack.popLast() {
            guard seen.insert(t.id).inserted else { continue }
            out.append(t)
            stack.append(contentsOf: t.subtasks.reversed())
        }
        return out
    }
}
