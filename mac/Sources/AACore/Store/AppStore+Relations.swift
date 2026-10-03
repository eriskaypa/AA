// Spec: 02 §2.C, §3.1.3 (REPO-020…029), 01 §3.24 (DATA-137), DECISIONS 02 Q-3 (PurgeReferences widened, P2:
//       all occurrences, nested subtasks, crew step links, schedule RefIds, pins, Ui selection ids);
//       ARCHITECTURE.md §5.3. None of these save or mark dirty — callers do (02 §3.1.3).
import Foundation

extension AppStore {
    /// REPO-020: two-way relation. No-op for the same id; each id is appended to the other's `RelatedIds` only
    /// if absent (append order preserved, no duplicates).
    public func addRelation(_ a: HierarchyItem, _ b: HierarchyItem) {
        guard a.id != b.id else { return }
        if !a.relatedIds.contains(b.id) { a.relatedIds.append(b.id) }
        if !b.relatedIds.contains(a.id) { b.relatedIds.append(a.id) }
    }

    /// REPO-020: removes the first occurrence of each id from the other's `RelatedIds` (no-op if absent).
    public func removeRelation(_ a: HierarchyItem, _ b: HierarchyItem) {
        if let k = a.relatedIds.firstIndex(of: b.id) { a.relatedIds.remove(at: k) }
        if let k = b.relatedIds.firstIndex(of: a.id) { b.relatedIds.remove(at: k) }
    }

    /// REPO-021: `RelatedIds` (in order), then — Equipment only — `ProcedureIds`, then `TaskIds`; de-duplicated in
    /// insertion order and resolved with `item(id:)`, missing ones skipped. A procedure's step links are not
    /// relations.
    public func relatedItems(of item: HierarchyItem) -> [HierarchyItem] {
        var ids: [UUID] = []
        var seen = Set<UUID>()
        func add(_ list: [UUID]) { for id in list where seen.insert(id).inserted { ids.append(id) } }
        add(item.relatedIds)
        if let e = item as? Equipment {
            add(e.procedureIds)
            add(e.taskIds)
        }
        let index = repoTopLevelIndex()
        return ids.compactMap { index[$0] }
    }

    /// REPO-022 backlinks: every top-level item other than `target` (in `allItems()` order) that references it via
    /// its `RelatedIds`, Equipment `ProcedureIds`/`TaskIds`, or a Procedure step's `TaskIds`/`EquipmentIds`.
    public func referencedBy(_ target: HierarchyItem) -> [HierarchyItem] {
        let id = target.id
        return allItems().filter { i in
            guard i.id != id else { return false }
            if i.relatedIds.contains(id) { return true }
            if let e = i as? Equipment { return e.procedureIds.contains(id) || e.taskIds.contains(id) }
            if let p = i as? Procedure {
                return p.steps.contains { $0.taskIds.contains(id) || $0.equipmentIds.contains(id) }
            }
            return false
        }
    }

    /// REPO-029, widened per DECISIONS 02 Q-3 (P2, recorded in Deviations/F2.md): removes **every** occurrence of
    /// `deletedID` from every top-level item's `RelatedIds`, Equipment `ProcedureIds`/`TaskIds`, procedure step
    /// `TaskIds`/`EquipmentIds`, every file's `LinkedItemIds` in `allContainers()`, and additionally from nested
    /// subtasks' `RelatedIds`, crew checklist steps' `TaskIds`/`EquipmentIds`, crew schedule and saved-schedule
    /// `RefId`s (set to nil), `Ui.QuickViewPinIds`, `Ui.Selected*Id` and `Ui.MapFocusedItemId`. Never saves.
    public func purgeReferences(to deletedID: UUID) {
        let d = deletedID
        for i in allItems() {
            Self.repoScrub(i, \.relatedIds, d)
            if let e = i as? Equipment {
                Self.repoScrub(e, \.procedureIds, d)
                Self.repoScrub(e, \.taskIds, d)
            } else if let p = i as? Procedure {
                for s in p.steps {
                    Self.repoScrub(s, \.taskIds, d)
                    Self.repoScrub(s, \.equipmentIds, d)
                }
            }
        }
        for c in allContainers() {
            for f in c.files { Self.repoScrub(f, \.linkedItemIds, d) }
        }
        // Widened scope (DECISIONS 02 Q-3).
        repoWalkTasks { t, root in
            if t !== root { Self.repoScrub(t, \.relatedIds, d) }
            return true
        }
        for m in data.crew {
            for s in m.checklist {
                Self.repoScrub(s, \.taskIds, d)
                Self.repoScrub(s, \.equipmentIds, d)
            }
            for e in m.schedule where e.refId == d { e.refId = nil }
        }
        for t in data.scheduleTemplates {
            for e in t.entries where e.refId == d { e.refId = nil }
        }
        let ui = data.ui
        Self.repoScrub(ui, \.quickViewPinIds, d)
        if ui.selectedEquipmentId == d { ui.selectedEquipmentId = nil }
        if ui.selectedTaskId == d { ui.selectedTaskId = nil }
        if ui.selectedProcedureId == d { ui.selectedProcedureId = nil }
        if ui.selectedVesselId == d { ui.selectedVesselId = nil }
        if ui.mapFocusedItemId == d { ui.mapFocusedItemId = nil }
    }

    /// REPO-023 replace semantics: `ProcedureIds` becomes exactly `ids` (callers save).
    public func linkProcedures(_ ids: [UUID], to equipment: Equipment) {
        equipment.procedureIds = ids
    }

    /// REPO-024 replace semantics (the task is not related back).
    public func linkTasks(_ ids: [UUID], to equipment: Equipment) {
        equipment.taskIds = ids
    }

    /// REPO-027 replace semantics into the step's `TaskIds`.
    public func linkTasks(_ ids: [UUID], to step: ChecklistStep) {
        step.taskIds = ids
    }

    /// REPO-027 "Link equipment/area…" replace semantics into the step's `EquipmentIds`.
    public func linkEquipment(_ ids: [UUID], to step: ChecklistStep) {
        step.equipmentIds = ids
    }

    // MARK: Internal helpers

    /// id → first top-level item with that id (E, T, P, V order — first wins, like `item(id:)`).
    func repoTopLevelIndex() -> [UUID: HierarchyItem] {
        var index: [UUID: HierarchyItem] = [:]
        for i in allItems() where index[i.id] == nil { index[i.id] = i }
        return index
    }

    /// Removes every occurrence of `id` from `object[keyPath: list]`, touching the (observed) property only when
    /// it actually contains the id.
    static func repoScrub<T: AnyObject>(_ object: T, _ list: ReferenceWritableKeyPath<T, [UUID]>, _ id: UUID) {
        if object[keyPath: list].contains(id) { object[keyPath: list].removeAll { $0 == id } }
    }
}
