// Spec: 04 HIER-013 (SortAZ), HIER-015 (GroupExpanded, write only on change), HIER-021 (+ New), HIER-025…027
//       (rename / description / tags), HIER-030…034 (groups), HIER-070/072/073 (components and links), HIER-080…083
//       (task schedule against the MODEL's partner value), HIER-086 (subtasks), HIER-090, HIER-121 (selection keys),
//       M01 (drag to group); 02 REPO-023…026, REPO-051; 01 §4.2.20 (Ui keys). Pure model operations behind the views,
//       so they are unit-tested; persistence (MarkDirty / Save / Flush) is the caller's, as each feature says.
import Foundation

/// The per-kind `Ui` keys the hierarchy pages own (DATA-217).
@MainActor
public enum HierUiState {
    /// `Ui.SortAZ` key: `"Equipment"`, `"Task"`, `"Procedure"`, `"Vessel"` (the enum name).
    public static func sortAZ(_ ui: UiState, kind: ItemKind) -> Bool { ui.sortAZ[kind.name] ?? false }

    /// HIER-013: writes the flag; returns true when it changed (the caller marks dirty).
    @discardableResult
    public static func setSortAZ(_ ui: UiState, kind: ItemKind, _ on: Bool) -> Bool {
        if ui.sortAZ[kind.name] == on { return false }
        ui.sortAZ[kind.name] = on
        return true
    }

    /// HIER-015: a missing key means expanded.
    public static func isExpanded(_ ui: UiState, key: String) -> Bool { ui.groupExpanded[key] ?? true }

    /// HIER-015: writes only when the effective value changes; returns true when written (caller marks dirty).
    @discardableResult
    public static func setExpanded(_ ui: UiState, key: String, _ expanded: Bool) -> Bool {
        guard isExpanded(ui, key: key) != expanded else { return false }
        ui.groupExpanded[key] = expanded
        return true
    }

    /// HIER-121 `Ui.Selected{Kind}Id`.
    public static func selectedID(_ ui: UiState, kind: ItemKind) -> UUID? {
        switch kind {
        case .equipment: return ui.selectedEquipmentId
        case .task: return ui.selectedTaskId
        case .procedure: return ui.selectedProcedureId
        case .vessel: return ui.selectedVesselId
        default: return nil
        }
    }

    /// HIER-121: per-device, written when the page's current item changes (no dirty mark — the shell's next save
    /// carries it, like Windows' CaptureUiState).
    public static func setSelectedID(_ ui: UiState, kind: ItemKind, _ id: UUID?) {
        switch kind {
        case .equipment: if ui.selectedEquipmentId != id { ui.selectedEquipmentId = id }
        case .task: if ui.selectedTaskId != id { ui.selectedTaskId = id }
        case .procedure: if ui.selectedProcedureId != id { ui.selectedProcedureId = id }
        case .vessel: if ui.selectedVesselId != id { ui.selectedVesselId = id }
        default: break
        }
    }
}

/// Model edits of the hierarchy pages.
@MainActor
public enum HierPageOps {
    // MARK: Header (HIER-025…027)

    /// HIER-025: `item.Name = text` (no trimming; empty allowed). Returns true on change (caller marks dirty).
    @discardableResult
    public static func setName(_ item: HierarchyItem, _ text: String) -> Bool {
        guard !Ordinal.equals(item.name, text) else { return false }
        item.name = text
        return true
    }

    /// HIER-026.
    @discardableResult
    public static func setDescription(_ item: HierarchyItem, _ text: String) -> Bool {
        guard !Ordinal.equals(item.description, text) else { return false }
        item.description = text
        return true
    }

    /// HIER-027 / REPO-106: `Tags` replaced by `TagParser.parse(text)`; true when the list changed.
    @discardableResult
    public static func setTags(_ item: HierarchyItem, fromText text: String) -> Bool {
        let parsed = TagParser.parse(text)
        guard !sameOrdinal(item.tags, parsed) else { return false }
        item.tags = parsed
        return true
    }

    static func sameOrdinal(_ a: [String], _ b: [String]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { Ordinal.equals($0, $1) }
    }

    // MARK: Groups (HIER-030…034, M01)

    /// HIER-030: nil when the name is blank (nothing created); else the trimmed group (duplicates allowed).
    public static func createGroup(store: AppStore, kind: ItemKind, name: String) -> ItemGroup? {
        guard !NetText.isBlank(name) else { return nil }
        return store.createGroup(kind: kind, name: name)
    }

    /// HIER-031 / M01: sets `GroupId` on every item (nil = ungrouped); returns how many changed.
    @discardableResult
    public static func assign(store: AppStore, _ items: [HierarchyItem], to groupID: UUID?) -> Int {
        let n = items.filter { $0.groupId != groupID }.count
        store.assign(items, toGroup: groupID)
        return n
    }

    /// HIER-032: ungroups the grouped items; returns how many changed (0 → nothing is saved).
    @discardableResult
    public static func removeFromGroup(store: AppStore, _ items: [HierarchyItem]) -> Int {
        assign(store: store, items.filter { $0.groupId != nil }, to: nil)
    }

    // MARK: Equipment (HIER-070, 072, 073)

    /// HIER-070 `+ Add`: nil for a blank name; else a component named exactly `name` (not trimmed).
    public static func addComponent(store: AppStore, named name: String, to equipment: Equipment) -> Component? {
        guard !NetText.isBlank(name) else { return nil }
        return store.addComponent(named: name, to: equipment)
    }

    /// HIER-072 `+ New procedure` (REPO-025); nil for a blank name.
    public static func newLinkedProcedure(store: AppStore, named name: String, for equipment: Equipment) -> Procedure? {
        guard !NetText.isBlank(name) else { return nil }
        return store.createLinkedProcedure(named: name, for: equipment)
    }

    /// HIER-073 `+ New task` (REPO-026); nil for a blank name.
    public static func newLinkedTask(store: AppStore, named name: String, for equipment: Equipment) -> TaskItem? {
        guard !NetText.isBlank(name) else { return nil }
        return store.createLinkedTask(named: name, for: equipment)
    }

    /// HIER-072 `Pick…` OK: replace `ProcedureIds` with the picker's selection (VIEW-215 normalised).
    public static func replaceProcedureLinks(store: AppStore, _ picked: [UUID], on equipment: Equipment) {
        store.linkProcedures(HierLinkPicker.normalized(picked, candidates: HierLinkPicker.procedureCandidates(store: store)),
                             to: equipment)
    }

    /// HIER-073 `Pick…` OK: replace `TaskIds`.
    public static func replaceTaskLinks(store: AppStore, _ picked: [UUID], on equipment: Equipment) {
        store.linkTasks(HierLinkPicker.normalized(picked, candidates: HierLinkPicker.taskCandidates(store: store)),
                        to: equipment)
    }

    // MARK: Task schedule (HIER-080…083, REPO-051)

    /// HIER-080 deadline picker changed: coerce against the MODEL's `RangeStart` (never a sibling control).
    /// Returns true when either stored value changed (caller marks dirty).
    @discardableResult
    public static func setTaskDeadline(_ t: TaskItem, _ deadline: NetDateTime?) -> Bool {
        let (s, nd) = WorkRange.coerce(start: t.rangeStart, deadline: deadline, editedStart: false)
        return applyRange(t, start: s, deadline: nd)
    }

    /// HIER-080 start picker changed: coerce against the MODEL's `Deadline`.
    @discardableResult
    public static func setTaskStart(_ t: TaskItem, _ start: NetDateTime?) -> Bool {
        let (ns, nd) = WorkRange.coerce(start: start, deadline: t.deadline, editedStart: true)
        return applyRange(t, start: ns, deadline: nd)
    }

    static func applyRange(_ t: TaskItem, start: NetDateTime?, deadline: NetDateTime?) -> Bool {
        var changed = false
        if !sameDate(t.rangeStart, start) { t.rangeStart = start; changed = true }
        if !sameDate(t.deadline, deadline) { t.deadline = deadline; changed = true }
        return changed
    }

    /// Unchanged values keep their stored text (DECISIONS Q-6): equal ticks are not rewritten.
    static func sameDate(_ a: NetDateTime?, _ b: NetDateTime?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return x == y
        default: return false
        }
    }

    /// HIER-083 / HIER-090 duration text: writes only a valid value > 0 that differs; returns true when written.
    @discardableResult
    public static func setDuration(_ text: String, current: Int, write: (Int) -> Void) -> Bool {
        guard let m = HierDuration.parse(text), m != current else { return false }
        write(m)
        return true
    }

    // MARK: Navigation to a child (DECISIONS 02 Q-11)

    /// The DIRECT subtask of `task` that is, or contains (at any depth, cycle-guarded), `childID` — the row the
    /// Schedule & Subtasks table selects when a search hit names a nested subtask. nil when not in the tree.
    public static func directSubtask(of task: TaskItem, revealing childID: UUID) -> TaskItem? {
        for s in task.subtasks {
            if s.id == childID { return s }
            var seen = Set<ObjectIdentifier>([ObjectIdentifier(s)])
            var stack = Array(s.subtasks)
            while let n = stack.popLast() {
                guard seen.insert(ObjectIdentifier(n)).inserted else { continue }
                if n.id == childID { return s }
                stack.append(contentsOf: n.subtasks)
            }
        }
        return nil
    }

    /// The component of `equipment` with `childID`, if any.
    public static func component(of equipment: Equipment, id childID: UUID) -> Component? {
        equipment.components.first { $0.id == childID }
    }

    // MARK: Subtasks (HIER-086)

    /// `+ Add`: nil for a blank name; logged `Added / "Subtask" / name / {parent}` (REPO-035).
    public static func addSubtask(store: AppStore, named name: String, to parent: TaskItem) -> TaskItem? {
        guard !NetText.isBlank(name) else { return nil }
        return store.addSubtask(named: name, to: parent)
    }
}
