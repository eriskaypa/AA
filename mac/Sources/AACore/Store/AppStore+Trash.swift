// Spec: 02 §2.H, §3.1.5 (REPO-070…081), 01 §3.17 (DATA-110…114), 08 §3.6, 10 VESSEL-280; DECISIONS 02 Q-4
//       (Board & Ctrl+N deletes route through the Trash), DECISIONS 07 Q-02 (purge the whole deleted subtree),
//       DECISIONS 09 ("Clear all" crew = one Trash batch); 02 §8 D-2 (P2: nothing is trashed unless it was
//       actually removed); ARCHITECTURE.md §5.3. Every Trash mutation sends `trashChanged`.
import Foundation

extension AppStore {
    /// REPO-079 / DATA-114: at most 200 entries …
    public static let maxTrashItems = 200
    /// … and 90 days by `DeletedUtc`.
    public static let trashRetentionDays = 90

    /// REPO-070. Soft-deletes a TOP-LEVEL item (Equipment / Tasks / Procedures / Vessels array): the entry carries the
    /// item's full JSON (runtime type, whole subtree), the item leaves its collection, the Trash is pruned, the
    /// delete is logged (`Removed / KindLabel / name / "moved to Trash"`) and the store is marked dirty. References
    /// are NOT scrubbed, so a restore is lossless. Returns nil for anything that is not a top-level item of the live
    /// data (e.g. a nested subtask — use `trashSubtask` — or a detached object; 02 §8 D-2, P2).
    /// `deletedUtc` stamps the entry (default: one clock read). A batch caller reads the clock ONCE and passes the
    /// same stamp for every entry, so the REPO-077 undo (DeletedUtc descending, ties → collection order) re-appends
    /// the batch in its original order instead of reversing it (Stage V2 V2-J1; same rule as `trashAllCrew`).
    @discardableResult public func trash(_ item: HierarchyItem, batchID: UUID? = nil,
                                         deletedUtc: NetDateTime? = nil) -> TrashedItem? {
        guard let type = Self.repoTrashType(item.kind) else { return nil }
        let payload = TrashPayload.encode(item)
        guard repoRemoveTopLevel(item) else { return nil }
        let label = Self.kindLabel(item.kind)
        let entry = TrashedItem(itemType: type.rawValue, itemId: item.id, batchId: batchID ?? .netEmpty,
                                name: item.name, kindLabel: label, deletedUtc: deletedUtc ?? clock.utcNow(),
                                payloadJson: payload)
        repoAddToTrash(entry)
        logRemoved(kind: label, name: item.name, detail: "moved to Trash")
        markDirty()
        trashChanged.send(())
        return entry
    }

    /// DECISIONS 02 Q-4 for Board subtask cards (REPO-081, VIEW-052): ItemType "Task", the parent id stored as the
    /// unknown member `"ParentTaskId"` on the entry (Windows ignores and preserves it). Removes the subtask from its
    /// parent, purges references to it and its descendants, logs like a task delete and sends `trashChanged`.
    /// A top-level task is forwarded to `trash(_:)`; an object that is not in the live tree → nil. `deletedUtc` as
    /// for `trash(_:batchID:deletedUtc:)` (one stamp per batch).
    @discardableResult public func trashSubtask(_ subtask: TaskItem, batchID: UUID? = nil,
                                                deletedUtc: NetDateTime? = nil) -> TrashedItem? {
        if data.tasks.contains(where: { $0 === subtask }) {
            return trash(subtask, batchID: batchID, deletedUtc: deletedUtc)
        }
        guard let parent = repoParent(ofIdentical: subtask),
              let k = parent.subtasks.firstIndex(where: { $0 === subtask }) else { return nil }
        let payload = TrashPayload.encode(subtask)
        let doomed = [subtask.id] + subtask.repoDescendantsByID().map(\.id)
        parent.subtasks.remove(at: k)
        var entry = TrashedItem(itemType: TrashItemType.task.rawValue, itemId: subtask.id,
                                batchId: batchID ?? .netEmpty, name: subtask.name,
                                kindLabel: Self.kindLabel(.task), deletedUtc: deletedUtc ?? clock.utcNow(),
                                payloadJson: payload)
        entry.extra.set(Self.repoParentTaskKey, .string(parent.id.netString))
        for id in doomed { purgeReferences(to: id) }
        repoAddToTrash(entry)
        logRemoved(kind: Self.kindLabel(.task), name: subtask.name, detail: "moved to Trash")
        markDirty()
        trashChanged.send(())
        return entry
    }

    /// REPO-072: trashes every trashable top-level item of a snapshot of `items` as ONE batch (one new `BatchId`
    /// shared by every resulting entry). Returns how many were trashed. The caller has confirmed. Every entry carries
    /// the SAME `DeletedUtc` (one clock read), so ⌘Z restores the items in their original data order (V2-J1).
    @discardableResult public func trashItems(_ items: [HierarchyItem]) -> Int {
        trashBatch(items, includeSubtasks: false).count
    }

    /// One undo batch over `items` in order: one new `BatchId` and ONE `DeletedUtc` for every entry (V2-J1,
    /// REPO-072/077). With `includeSubtasks` a `TaskItem` goes through `trashSubtask` (nested Board/sidebar
    /// subtasks, DECISIONS 02 Q-4); otherwise only top-level items are trashed. Returns the items actually trashed,
    /// in order. The caller has confirmed (and flushed editors / saves afterwards).
    @discardableResult public func trashBatch(_ items: [HierarchyItem],
                                              includeSubtasks: Bool = true) -> [HierarchyItem] {
        let batch = UUID()
        let stamp = clock.utcNow()
        var trashed: [HierarchyItem] = []
        for item in Array(items) {
            let entry: TrashedItem?
            if includeSubtasks, let t = item as? TaskItem {
                entry = trashSubtask(t, batchID: batch, deletedUtc: stamp)
            } else {
                entry = trash(item, batchID: batch, deletedUtc: stamp)
            }
            if entry != nil { trashed.append(item) }
        }
        return trashed
    }

    /// REPO-071: soft-deletes a crew member (ItemType "Crew", KindLabel "Crew member", Name = full name, or the last
    /// name when the full name is blank), logs `Removed / "Crew member" / name / "moved to Trash"`, marks dirty.
    /// A member that is not in the live roster is not recorded (the returned entry is detached; 02 §8 D-2, P2).
    @discardableResult public func trash(_ member: CrewMember, batchID: UUID? = nil) -> TrashedItem {
        repoTrashCrew(member, batchID: batchID, log: true)
    }

    /// DECISIONS 09: "Clear all" = one Trash batch (undoable as a whole); logs `Removed / "Crew" /
    /// "all {n} member(s)"` once. Returns the number of members moved. Every entry of the batch carries the SAME
    /// `DeletedUtc` (one clock read), so the REPO-077 undo (DeletedUtc descending, ties → collection order)
    /// re-appends the roster in its original order instead of reversing it (CREW-061/062).
    @discardableResult public func trashAllCrew() -> Int {
        let members = data.crew
        guard !members.isEmpty else { return 0 }
        let batch = UUID()
        let stamp = clock.utcNow()
        for m in members { _ = repoTrashCrew(m, batchID: batch, log: false, deletedUtc: stamp) }
        logRemoved(kind: "Crew", name: "all \(members.count) member(s)", detail: "")
        markDirty()
        trashChanged.send(())
        return members.count
    }

    /// REPO-076: decodes the payload as the type named by `ItemType` (nil on any error, entry kept). The object is
    /// appended to the END of its collection unless a live item there already has its id (then it is not added,
    /// but the entry is still consumed — 02 §8 D-11 parity). A subtask entry (`ParentTaskId`) goes back to the end
    /// of its parent's subtasks when the parent still exists, else it becomes a top-level task. Removes the entry,
    /// logs `Added / KindLabel / name / "restored from Trash"`, marks dirty and returns the type.
    public func restore(_ entry: TrashedItem) -> TrashItemType? {
        guard let type = TrashItemType(rawValue: entry.itemType),
              let object = TrashPayload.decode(itemType: entry.itemType, payload: entry.payloadJson,
                                               context: repoDecodeContext) else { return nil }
        switch object {
        case let e as Equipment:
            if !data.equipment.contains(where: { $0.id == e.id }) { data.equipment.append(e) }
        case let t as TaskItem:
            if let parentID = Self.repoParentTaskID(of: entry), let parent = task(id: parentID) {
                if task(id: t.id) == nil { parent.subtasks.append(t) }
            } else if !data.tasks.contains(where: { $0.id == t.id }) {
                data.tasks.append(t)
            }
        case let p as Procedure:
            if !data.procedures.contains(where: { $0.id == p.id }) { data.procedures.append(p) }
        case let v as Vessel:
            if !data.vessels.contains(where: { $0.id == v.id }) { data.vessels.append(v) }
        case let m as CrewMember:
            if !data.crew.contains(where: { $0.id == m.id }) { data.crew.append(m) }
        default:
            return nil
        }
        if let k = data.trash.firstIndex(where: { $0.id == entry.id }) { data.trash.remove(at: k) }
        logAdded(kind: entry.kindLabel, name: entry.name, detail: "restored from Trash")
        markDirty()
        trashChanged.send(())
        return type
    }

    /// REPO-080 "Delete permanently": if the entry is in the Trash, removes it, purges every reference to the deleted
    /// subtree (DECISIONS 07 Q-02) and marks dirty.
    public func purge(_ entry: TrashedItem) {
        guard let k = data.trash.firstIndex(where: { $0.id == entry.id }) else { return }
        let removed = data.trash.remove(at: k)
        repoPurgeSubtree(of: removed)
        markDirty()
        trashChanged.send(())
    }

    /// REPO-080 "Empty Trash": no-op when empty; else purges references for every entry, clears, marks dirty.
    public func emptyTrash() {
        guard !data.trash.isEmpty else { return }
        let all = data.trash
        for e in all { repoPurgeSubtree(of: e) }
        data.trash.removeAll()
        markDirty()
        trashChanged.send(())
    }

    /// REPO-079: (1) walking from the end, evicts every entry older than 90 days (`DeletedUtc` ticks, kind
    /// ignored); (2) while more than 200 remain, evicts the oldest (ties → earliest in collection order). Eviction
    /// purges references to the deleted subtree. Marks dirty (and sends `trashChanged`) only if something was
    /// evicted; returns whether it did.
    @discardableResult public func pruneTrash(now: NetDateTime? = nil) -> Bool {
        let cutoff = (now ?? clock.utcNow()).addingDays(-Self.trashRetentionDays)
        var changed = false
        var i = data.trash.count - 1
        while i >= 0 {
            if data.trash[i].deletedUtc.ticks < cutoff.ticks { repoEvict(at: i); changed = true }
            i -= 1
        }
        while data.trash.count > Self.maxTrashItems, let k = repoOldestTrashIndex() {
            repoEvict(at: k)
            changed = true
        }
        if changed {
            markDirty()
            trashChanged.send(())
        }
        return changed
    }

    /// REPO-077: 0 when the Trash is empty, 1 when the newest entry is a single delete, else the size of its batch.
    public func pendingUndoCount() -> Int {
        guard let k = repoNewestTrashIndex() else { return 0 }
        let newest = data.trash[k]
        if newest.batchId == .netEmpty { return 1 }
        return data.trash.reduce(0) { $0 + ($1.batchId == newest.batchId ? 1 : 0) }
    }

    /// REPO-077: restores the newest entry — or its whole batch, newest first, continuing past failures — and
    /// returns the distinct restored types in restore order (`[]` when the Trash is empty).
    public func undoLastDelete() -> [TrashItemType] {
        guard let k = repoNewestTrashIndex() else { return [] }
        let newest = data.trash[k]
        var batch: [TrashedItem]
        if newest.batchId == .netEmpty {
            batch = [newest]
        } else {
            batch = data.trash.enumerated()
                .filter { $0.element.batchId == newest.batchId }
                .sorted { a, b in
                    a.element.deletedUtc.ticks != b.element.deletedUtc.ticks
                        ? a.element.deletedUtc.ticks > b.element.deletedUtc.ticks : a.offset < b.offset
                }
                .map(\.element)
        }
        var types: [TrashItemType] = []
        for e in batch {
            if let t = restore(e), !types.contains(t) { types.append(t) }
        }
        return types
    }

    /// REPO-081 (Board, Windows hard delete): removes the task wherever it lives (top level or nested) and purges
    /// references to it and its descendants; not logged. Marks dirty (the caller saves). DECISIONS 02 Q-4: the Mac
    /// Board uses `trash(_:)` / `trashSubtask(_:)` instead; this stays for completeness.
    public func hardDeleteTask(_ task: TaskItem) {
        let doomed = [task.id] + task.repoDescendantsByID().map(\.id)
        guard repoRemoveTaskAnywhere(task) else { return }
        for id in doomed { purgeReferences(to: id) }
        markDirty()
    }

    /// REPO-081 (Ctrl+N, Windows hard delete): logs `Removed / KindLabel / name`, removes the item from its
    /// collection, purges references (which also unpins it from `QuickViewPinIds`), marks dirty.
    public func hardDelete(_ item: HierarchyItem) {
        var doomed = [item.id]
        if let t = item as? TaskItem { doomed += t.repoDescendantsByID().map(\.id) }
        let removed: Bool
        if let t = item as? TaskItem { removed = repoRemoveTaskAnywhere(t) } else { removed = repoRemoveTopLevel(item) }
        guard removed else { return }
        logRemoved(kind: Self.kindLabel(item.kind), name: item.name, detail: "")
        for id in doomed { purgeReferences(to: id) }
        markDirty()
    }

    // MARK: Internals

    static let repoParentTaskKey = "ParentTaskId"

    nonisolated static func repoTrashType(_ kind: ItemKind) -> TrashItemType? {
        switch kind {
        case .equipment: return .equipment
        case .task: return .task
        case .procedure: return .procedure
        case .vessel: return .vessel
        default: return nil
        }
    }

    /// The `ParentTaskId` member of a subtask entry (DECISIONS 02 Q-4), if any.
    nonisolated static func repoParentTaskID(of entry: TrashedItem) -> UUID? {
        guard let text = entry.extra["ParentTaskId"]?.stringValue else { return nil }
        return UUID(netString: text)
    }

    private func repoTrashCrew(_ member: CrewMember, batchID: UUID?, log: Bool,
                               deletedUtc: NetDateTime? = nil) -> TrashedItem {
        let full = member.fullName
        let name = NetText.isBlank(full) ? member.lastName : full
        let entry = TrashedItem(itemType: TrashItemType.crew.rawValue, itemId: member.id,
                                batchId: batchID ?? .netEmpty, name: name, kindLabel: "Crew member",
                                deletedUtc: deletedUtc ?? clock.utcNow(), payloadJson: TrashPayload.encode(member))
        guard let k = data.crew.firstIndex(where: { $0 === member }) else { return entry }
        data.crew.remove(at: k)
        repoAddToTrash(entry)
        if log {
            logRemoved(kind: "Crew member", name: name, detail: "moved to Trash")
            markDirty()
            trashChanged.send(())
        }
        return entry
    }

    /// Append + prune (C# `AddToTrash`).
    private func repoAddToTrash(_ entry: TrashedItem) {
        data.trash.append(entry)
        pruneTrash()
    }

    private func repoEvict(at index: Int) {
        let e = data.trash.remove(at: index)
        repoPurgeSubtree(of: e)
    }

    /// PurgeReferences for the entry's `ItemId` and every id inside its payload's subtree (nested subtasks, steps,
    /// components) — DECISIONS 07 Q-02.
    func repoPurgeSubtree(of entry: TrashedItem) {
        var ids = [entry.itemId]
        if let root = try? JSONParser.parse(entry.payloadJson), case .object(let o) = root {
            Self.repoCollectIDs(o, into: &ids)
        }
        var seen = Set<UUID>()
        for id in ids where id != .netEmpty && seen.insert(id).inserted { purgeReferences(to: id) }
    }

    nonisolated private static func repoCollectIDs(_ o: JSONObject, into ids: inout [UUID]) {
        if let s = o["Id"]?.stringValue, let id = UUID(netString: s) { ids.append(id) }
        for key in ["Subtasks", "Steps", "Components"] {
            for child in o[key]?.arrayValue ?? [] {
                if case .object(let c) = child { repoCollectIDs(c, into: &ids) }
            }
        }
    }

    /// Newest by `DeletedUtc`; ties → the earliest in collection order.
    private func repoNewestTrashIndex() -> Int? {
        var best: Int?
        for (k, e) in data.trash.enumerated() {
            if let b = best, e.deletedUtc.ticks <= data.trash[b].deletedUtc.ticks { continue }
            best = k
        }
        return best
    }

    /// Oldest by `DeletedUtc`; ties → the earliest in collection order.
    private func repoOldestTrashIndex() -> Int? {
        var best: Int?
        for (k, e) in data.trash.enumerated() {
            if let b = best, e.deletedUtc.ticks >= data.trash[b].deletedUtc.ticks { continue }
            best = k
        }
        return best
    }

    /// Removes a top-level item (by identity) from its live collection; false when it is not there.
    private func repoRemoveTopLevel(_ item: HierarchyItem) -> Bool {
        switch item {
        case let e as Equipment:
            guard let k = data.equipment.firstIndex(where: { $0 === e }) else { return false }
            data.equipment.remove(at: k)
        case let t as TaskItem:
            guard let k = data.tasks.firstIndex(where: { $0 === t }) else { return false }
            data.tasks.remove(at: k)
        case let p as Procedure:
            guard let k = data.procedures.firstIndex(where: { $0 === p }) else { return false }
            data.procedures.remove(at: k)
        case let v as Vessel:
            guard let k = data.vessels.firstIndex(where: { $0 === v }) else { return false }
            data.vessels.remove(at: k)
        default:
            return false
        }
        return true
    }

    /// Removes a task (by identity) from the top level or from its parent's subtasks.
    private func repoRemoveTaskAnywhere(_ task: TaskItem) -> Bool {
        if let k = data.tasks.firstIndex(where: { $0 === task }) {
            data.tasks.remove(at: k)
            return true
        }
        guard let parent = repoParent(ofIdentical: task),
              let k = parent.subtasks.firstIndex(where: { $0 === task }) else { return false }
        parent.subtasks.remove(at: k)
        return true
    }

    /// The live task whose `Subtasks` holds this very object.
    func repoParent(ofIdentical child: TaskItem) -> TaskItem? {
        var found: TaskItem?
        repoWalkTasks { t, _ in
            if t.subtasks.contains(where: { $0 === child }) { found = t; return false }
            return true
        }
        return found
    }
}
