// Tests for 02 §2.H (REPO-070…081), 01 §3.17 / §7.11 (DATA-110…114), 08 §7.6; DECISIONS 02 Q-4 (trashSubtask),
// DECISIONS 07 Q-02 (purge the whole subtree), DECISIONS 09 (trashAllCrew); 02 §8 D-2 (P2).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct RepoTrashTests {
    static let clock = FixedClock(local: "2026-09-29T14:05:00", zone: TZ.athens)

    private func make() -> StoreFactory.Made { StoreFactory.make(clock: Self.clock) }

    private func utc(daysAgo: Int, store: AppStore) -> NetDateTime {
        store.clock.utcNow().addingDays(-daysAgo)
    }

    private func entry(for task: TaskItem, deleted: NetDateTime, batch: UUID = .netEmpty) -> TrashedItem {
        TrashedItem(itemType: "Task", itemId: task.id, batchId: batch, name: task.name, kindLabel: "Task",
                    deletedUtc: deleted, payloadJson: TrashPayload.encode(task))
    }

    @Test func softDeleteKeepsReferences() throws {
        // TV: 02 T-TR-1
        let made = make(); let store = made.store
        let e = Equipment(name: "E"), t = TaskItem(name: "Change fuel filter")
        let sub = TaskItem(name: "sub"); t.subtasks = [sub]
        store.data.equipment = [e]; store.data.tasks = [t]
        store.addRelation(t, e); e.taskIds = [t.id]
        var changes = 0
        let sub1 = store.trashChanged.subscribe { changes += 1 }
        let entry = try #require(store.trash(t))
        _ = sub1
        #expect(store.data.tasks.isEmpty)
        #expect(store.data.trash.count == 1)
        #expect(entry.itemType == "Task" && entry.itemId == t.id && entry.kindLabel == "Task")
        #expect(entry.batchId == .netEmpty && entry.name == "Change fuel filter")
        #expect(entry.deletedUtc == store.clock.utcNow() && entry.deletedUtc.kind == .utc)
        let decoded = try #require(TrashPayload.decode(itemType: "Task", payload: entry.payloadJson,
                                                       context: .standard) as? TaskItem)
        #expect(JSONValue.deepEquals(.object(decoded.toJSON()), .object(t.toJSON())))
        #expect(e.relatedIds == [t.id] && e.taskIds == [t.id])
        let log = try #require(store.data.log.last)
        #expect(log.action == "Removed" && log.kind == "Task" && log.name == "Change fuel filter" && log.detail == "moved to Trash")
        #expect(store.isDirty)
        #expect(changes >= 1)
    }

    @Test func restoreAppendsAtTheEnd() throws {
        // TV: 02 T-TR-2, 08 T-TR-1
        let made = make(); let store = made.store
        let e = Equipment(name: "E"), t = TaskItem(name: "T"), other = TaskItem(name: "other")
        t.subtasks = [TaskItem(name: "s1"), TaskItem(name: "s2")]
        store.data.equipment = [e]; store.data.tasks = [t, other]
        store.addRelation(t, e)
        let entry = try #require(store.trash(t))
        #expect(store.restore(entry) == .task)
        #expect(store.data.tasks.map(\.id) == [other.id, t.id])
        #expect(store.data.tasks[1] !== t)                   // a new object under the same id
        #expect(store.data.tasks[1].subtasks.count == 2)
        #expect(store.data.trash.isEmpty)
        let log = try #require(store.data.log.last)
        #expect(log.action == "Added" && log.kind == "Task" && log.name == "T" && log.detail == "restored from Trash")
        #expect(store.relatedItems(of: e).map(\.id) == [t.id])
    }

    @Test func restoreCollisionCorruptAndUnknown() throws {
        // TV: 02 T-TR-3, T-TR-4, T-TR-5; 08 T-TR-2/3
        let made = make(); let store = made.store
        let t = TaskItem(name: "T")
        store.data.tasks = [t]
        let dup = entry(for: t, deleted: store.clock.utcNow())
        store.data.trash = [dup]
        #expect(store.restore(dup) == .task)
        #expect(store.data.tasks.count == 1 && store.data.trash.isEmpty)
        #expect(store.data.log.last?.detail == "restored from Trash")

        var bad = entry(for: TaskItem(name: "X"), deleted: store.clock.utcNow())
        bad.payloadJson = "{"
        store.data.trash = [bad]
        #expect(store.restore(bad) == nil)
        #expect(store.data.trash.count == 1)
        var widget = entry(for: TaskItem(name: "W"), deleted: store.clock.utcNow())
        widget.itemType = "Widget"
        #expect(store.restore(widget) == nil)
    }

    @Test func batchTrashSharesOneBatchID() {
        // TV: 02 T-TR-6
        let made = make(); let store = made.store
        let a = TaskItem(name: "A"), b = TaskItem(name: "B"), c = TaskItem(name: "C")
        store.data.tasks = [a, b, c]
        #expect(store.trashItems([a, b, c]) == 3)
        let batches = Set(store.data.trash.map(\.batchId))
        #expect(batches.count == 1 && batches.first != .netEmpty)
    }

    @Test func undoRestoresTheNewestBatch() {
        // TV: 02 T-TR-7, T-TR-8, T-TR-10; 01 §7.11 "batch of 3 + a later single"
        let made = make(); let store = made.store
        let k = UUID()
        let a = TaskItem(name: "a"), b = TaskItem(name: "b"), c = TaskItem(name: "c")
        store.data.trash = [entry(for: a, deleted: utc(daysAgo: 3, store: store)),
                            entry(for: b, deleted: utc(daysAgo: 2, store: store), batch: k),
                            entry(for: c, deleted: utc(daysAgo: 1, store: store), batch: k)]
        #expect(store.pendingUndoCount() == 2)
        #expect(store.undoLastDelete() == [.task])
        #expect(store.data.tasks.map(\.name) == ["c", "b"])
        #expect(store.data.trash.map(\.name) == ["a"])

        let made2 = make(); let s2 = made2.store
        s2.data.trash = [entry(for: a, deleted: utc(daysAgo: 1, store: s2)),
                         entry(for: b, deleted: utc(daysAgo: 3, store: s2), batch: k)]
        #expect(s2.pendingUndoCount() == 1)
        _ = s2.undoLastDelete()
        #expect(s2.data.tasks.map(\.name) == ["a"])

        let made3 = make(); let s3 = made3.store
        #expect(s3.pendingUndoCount() == 0)
        #expect(s3.undoLastDelete().isEmpty)
    }

    @Test func undoMixedBatchReturnsDistinctTypes() {
        // TV: 02 T-TR-9; 04 §7.6 last bullet
        let made = make(); let store = made.store
        let e = Equipment(name: "E"), t = TaskItem(name: "T"), p = Procedure(name: "P"), t2 = TaskItem(name: "T2")
        store.data.equipment = [e]; store.data.tasks = [t, t2]; store.data.procedures = [p]
        #expect(store.trashItems([e, t, p, t2]) == 4)
        #expect(store.pendingUndoCount() == 4)
        let types = store.undoLastDelete()
        #expect(Set(types) == [.equipment, .task, .procedure] && types.count == 3)
        #expect(store.data.equipment.map(\.id) == [e.id])
        #expect(Set(store.data.tasks.map(\.id)) == [t.id, t2.id])
        #expect(store.data.trash.isEmpty)
    }

    @Test func pruneByAgeAndCap() throws {
        // TV: 02 T-TR-11, T-TR-12, T-TR-13; 01 §7.11; 08 T-TR-6
        let made = make(); let store = made.store
        let e = Equipment(name: "E")
        let old = TaskItem(name: "old")
        e.relatedIds = [old.id]
        store.data.equipment = [e]
        store.data.trash = [entry(for: old, deleted: utc(daysAgo: 91, store: store))]
        #expect(store.pruneTrash())
        #expect(store.data.trash.isEmpty && e.relatedIds.isEmpty && store.isDirty)

        let made2 = make(); let s2 = made2.store
        s2.data.trash = [entry(for: TaskItem(name: "kept"), deleted: utc(daysAgo: 89, store: s2))]
        #expect(!s2.pruneTrash())
        #expect(s2.data.trash.count == 1 && !s2.isDirty)

        let made3 = make(); let s3 = made3.store
        let eq = Equipment(name: "E3")
        var entries: [TrashedItem] = []
        var oldestTask: TaskItem?
        for k in 0..<200 {
            let t = TaskItem(name: "t\(k)")
            if k == 37 { oldestTask = t }
            entries.append(entry(for: t, deleted: utc(daysAgo: k == 37 ? 50 : 10, store: s3)))
        }
        let oldest = try #require(oldestTask)
        eq.procedureIds = [oldest.id]
        s3.data.equipment = [eq]
        s3.data.trash = entries
        let fresh = TaskItem(name: "fresh")
        s3.data.tasks = [fresh]
        s3.trash(fresh)
        #expect(s3.data.trash.count == 200)
        #expect(!s3.data.trash.contains { $0.itemId == oldest.id })
        #expect(eq.procedureIds.isEmpty)
    }

    @Test func crewTrashNames() throws {
        // TV: 02 T-TR-14, T-TR-15
        let made = make(); let store = made.store
        let m = CrewMember(); m.firstName = "Jan"; m.middleName = ""; m.lastName = "Kowalski"
        store.data.crew = [m]
        let e = store.trash(m)
        #expect(e.name == "Jan Kowalski" && e.kindLabel == "Crew member" && e.itemType == "Crew")
        #expect(store.data.crew.isEmpty)
        #expect(store.data.log.last?.kind == "Crew member" && store.data.log.last?.detail == "moved to Trash")
        #expect(store.restore(e) == .crew)
        #expect(store.data.crew.map(\.id) == [m.id])

        let blank = CrewMember()
        store.data.crew.append(blank)
        let e2 = store.trash(blank)
        #expect(e2.name == "" && e2.display.hasPrefix("(unnamed)"))

        let detached = CrewMember(); detached.lastName = "Ghost"
        let e3 = store.trash(detached)
        #expect(e3.name == "Ghost" && !store.data.trash.contains { $0.id == e3.id })
    }

    @Test func trashAllCrewIsOneUndoableBatch() {
        // DECISIONS 09: "Clear all" through the Trash as one batch
        let made = make(); let store = made.store
        let a = CrewMember(); a.lastName = "A"
        let b = CrewMember(); b.lastName = "B"
        store.data.crew = [a, b]
        #expect(store.trashAllCrew() == 2)
        #expect(store.data.crew.isEmpty && store.data.trash.count == 2)
        #expect(Set(store.data.trash.map(\.batchId)).count == 1)
        let crewLogs = store.data.log.filter { $0.kind == "Crew" || $0.kind == "Crew member" }
        #expect(crewLogs.count == 1 && crewLogs[0].name == "all 2 member(s)" && crewLogs[0].action == "Removed")
        #expect(store.pendingUndoCount() == 2)
        #expect(store.undoLastDelete() == [.crew])
        #expect(Set(store.data.crew.map(\.id)) == [a.id, b.id])
        #expect(store.trashAllCrew() == 2)
        store.data.crew = []
        #expect(store.trashAllCrew() == 0)
    }

    @Test func trashAllCrewUndoKeepsRosterOrderWithAMovingClock() {
        // DECISIONS 09 / CREW-061/062: every entry of the "Clear all" batch shares ONE DeletedUtc, so ⌘Z restores
        // [A, B, C] as [A, B, C] even when the clock moves between reads (the system clock does).
        let clock = RepoTickingClock()
        let store = StoreFactory.make(clock: clock).store
        let members = ["A", "B", "C"].map { n -> CrewMember in let m = CrewMember(); m.lastName = n; return m }
        store.data.crew = members
        let readsBefore = clock.reads
        #expect(store.trashAllCrew() == 3)
        #expect(Set(store.data.trash.map(\.deletedUtc.ticks)).count == 1)
        #expect(clock.reads > readsBefore)
        #expect(store.undoLastDelete() == [.crew])
        #expect(store.data.crew.map(\.lastName) == ["A", "B", "C"])
        #expect(store.data.crew.map(\.id) == members.map(\.id))
    }

    @Test func batchUndoKeepsDataOrderWithRealClock() throws {
        // Stage V2 V2-J1 journey (REPO-072/075/077, HIER-024/135): select T1, T2, T3 → Delete selected… → ⌘Z.
        // SystemClock, like the app: the batch shares ONE DeletedUtc, so the undo re-appends T1, T2, T3 in order.
        let made = StoreFactory.make(); let store = made.store
        let t1 = store.createItem(kind: .task, name: "T1")
        let t2 = store.createItem(kind: .task, name: "T2")
        let t3 = store.createItem(kind: .task, name: "T3")
        _ = store.createItem(kind: .task, name: "Keep")
        #expect(BatchDelete.trashAll([t1, t2, t3], store: store, isGated: { _ in false }) == 3)
        #expect(Set(store.data.trash.map(\.deletedUtc.ticks)).count == 1)
        _ = store.undoLastDelete()
        #expect(store.data.tasks.map(\.name) == ["Keep", "T1", "T2", "T3"])
    }

    @Test func trashBatchSharesOneStampAndHandlesSubtasks() throws {
        // V2-J1: `trashBatch` (the sidebar/Board batch path) — one BatchId, one DeletedUtc even with a moving clock,
        // nested subtasks through `trashSubtask`; ⌘Z restores in selection order (top-level items to the end of the
        // collection, the subtask to the end of its parent).
        let clock = RepoTickingClock()
        let store = StoreFactory.make(clock: clock).store
        let a = TaskItem(name: "A"), b = TaskItem(name: "B"), keep = TaskItem(name: "Keep")
        let parent = TaskItem(name: "P"), s1 = TaskItem(name: "S1"), s2 = TaskItem(name: "S2")
        parent.subtasks = [s1, s2]
        let e = Equipment(name: "E")
        store.data.tasks = [a, b, keep, parent]; store.data.equipment = [e]
        let readsBefore = clock.reads
        let trashed = store.trashBatch([a, s1, e, b])
        #expect(trashed.map(\.name) == ["A", "S1", "E", "B"])
        #expect(clock.reads > readsBefore)
        #expect(Set(store.data.trash.map(\.batchId)).count == 1 && store.data.trash.count == 4)
        #expect(Set(store.data.trash.map(\.deletedUtc.ticks)).count == 1)
        #expect(store.data.tasks.map(\.name) == ["Keep", "P"] && parent.subtasks.map(\.name) == ["S2"])
        #expect(store.pendingUndoCount() == 4)
        #expect(store.undoLastDelete() == [.task, .equipment])
        #expect(store.data.tasks.map(\.name) == ["Keep", "P", "A", "B"])
        #expect(parent.subtasks.map(\.name) == ["S2", "S1"] && store.data.equipment.map(\.name) == ["E"])
        // Without subtasks (REPO-072 `trashItems`): a nested subtask is skipped, the rest share one stamp. Restored
        // items are new objects (REPO-076), so take the live ones.
        let live = { (n: String) -> TaskItem in store.data.tasks.first { $0.name == n }! }
        let liveS1 = try #require(parent.subtasks.first { $0.name == "S1" })
        let n = store.trashItems([liveS1, live("A"), live("B")])
        #expect(n == 2 && parent.subtasks.map(\.name) == ["S2", "S1"])
        _ = store.undoLastDelete()
        #expect(store.data.tasks.map(\.name) == ["Keep", "P", "A", "B"])
    }

    @Test func singleTrashHonoursAnExplicitStamp() throws {
        // V2-J1: the `deletedUtc` parameter wins over the clock; omitted → one clock read (Windows default).
        let made = make(); let store = made.store
        let t = TaskItem(name: "T"), u = TaskItem(name: "U")
        store.data.tasks = [t, u]
        let stamp = utc(daysAgo: 3, store: store)
        #expect(try #require(store.trash(t, deletedUtc: stamp)).deletedUtc == stamp)
        #expect(try #require(store.trash(u)).deletedUtc == store.clock.utcNow())
    }

    @Test func purgeAndEmptyScrubTheSubtree() throws {
        // TV: 02 T-TR-16; 08 T-TR-5; DECISIONS 07 Q-02
        let made = make(); let store = made.store
        let e = Equipment(name: "E"), p = Procedure(name: "P"), t = TaskItem(name: "T"), sub = TaskItem(name: "S")
        t.subtasks = [sub]
        e.procedureIds = [p.id]
        store.data.equipment = [e]; store.data.procedures = [p]; store.data.tasks = [t]
        store.data.ui.quickViewPinIds = [sub.id]
        let pe = try #require(store.trash(p))
        let te = try #require(store.trash(t))
        #expect(e.procedureIds == [p.id] && store.data.ui.quickViewPinIds == [sub.id])
        store.purge(pe)
        #expect(e.procedureIds.isEmpty && store.data.trash.count == 1)
        store.emptyTrash()
        #expect(store.data.trash.isEmpty && store.data.ui.quickViewPinIds.isEmpty)
        _ = te

        let made2 = make(); let s2 = made2.store
        s2.emptyTrash()
        #expect(!s2.isDirty)
        s2.purge(TrashedItem())                               // not in the Trash → nothing
        #expect(!s2.isDirty)
    }

    @Test func nestedSubtaskIsNotTrashedByTrash() {
        // 02 §8 D-2 (P2): trash(_:) on a nested subtask does nothing
        let made = make(); let store = made.store
        let t = TaskItem(name: "T"), s = TaskItem(name: "S"); t.subtasks = [s]
        store.data.tasks = [t]
        #expect(store.trash(s) == nil)
        #expect(t.subtasks.count == 1 && store.data.trash.isEmpty && store.data.log.isEmpty)
        #expect(store.trash(TaskItem(name: "detached")) == nil)
    }

    @Test func trashSubtaskAndRestore() throws {
        // DECISIONS 02 Q-4 (REPO-081, VIEW-052)
        let made = make(); let store = made.store
        let parent = TaskItem(name: "Parent"), s = TaskItem(name: "Sub"), ss = TaskItem(name: "SubSub"), other = TaskItem(name: "O")
        s.subtasks = [ss]; parent.subtasks = [s, other]
        store.data.tasks = [parent]
        store.data.ui.quickViewPinIds = [ss.id]
        let e = try #require(store.trashSubtask(s))
        #expect(e.itemType == "Task" && e.kindLabel == "Task" && e.itemId == s.id)
        #expect(e.extra["ParentTaskId"]?.stringValue == parent.id.netString)
        #expect(parent.subtasks.map(\.id) == [other.id])
        #expect(store.data.ui.quickViewPinIds.isEmpty)
        #expect(store.data.log.last?.kind == "Task" && store.data.log.last?.detail == "moved to Trash")
        // The ParentTaskId member round-trips through data.json (unknown members are preserved).
        let json = store.data.trash[0].toJSON()
        let reread = try TrashedItem(json: json, context: .standard)
        #expect(reread.extra["ParentTaskId"]?.stringValue == parent.id.netString)

        #expect(store.restore(e) == .task)
        #expect(parent.subtasks.map(\.id) == [other.id, s.id])
        #expect(store.data.tasks.count == 1)

        // Parent gone → restored as a top-level task.
        let e2 = try #require(store.trashSubtask(store.task(id: s.id)!))
        store.data.tasks = []
        #expect(store.restore(e2) == .task)
        #expect(store.data.tasks.map(\.id) == [s.id])

        // A top-level task is forwarded to trash(_:).
        let top = TaskItem(name: "Top"); store.data.tasks.append(top)
        let e3 = try #require(store.trashSubtask(top))
        #expect(e3.extra["ParentTaskId"] == nil)
        #expect(store.trashSubtask(TaskItem(name: "nowhere")) == nil)
    }

    @Test func hardDeletes() {
        // REPO-081 (kept for completeness)
        let made = make(); let store = made.store
        let e = Equipment(name: "E"), t = TaskItem(name: "T"), s = TaskItem(name: "S"), p = Procedure(name: "P")
        t.subtasks = [s]; e.taskIds = [s.id, t.id]
        store.data.equipment = [e]; store.data.tasks = [t]; store.data.procedures = [p]
        store.data.ui.quickViewPinIds = [p.id, t.id]
        store.hardDeleteTask(s)
        #expect(t.subtasks.isEmpty && e.taskIds == [t.id] && store.data.log.isEmpty && store.isDirty)
        store.hardDelete(p)
        #expect(store.data.procedures.isEmpty && store.data.ui.quickViewPinIds == [t.id])
        #expect(store.data.log.last?.action == "Removed" && store.data.log.last?.kind == "Procedure")
        store.hardDelete(t)
        #expect(store.data.tasks.isEmpty && e.taskIds.isEmpty && store.data.ui.quickViewPinIds.isEmpty)
        #expect(store.data.trash.isEmpty)
    }

    @Test func vesselRoundTripsWithItsRecords() throws {
        // 10 VESSEL-280: quick cards, jobs, flags and port calls come back intact
        let made = make(); let store = made.store
        let v = Vessel(name: "BW Pavilion Aranda")
        v.notificationsEnabled = false
        let card = QuickCard(); card.title = "Manuals"; v.quickCards = [card]
        let job = ShipJob(); job.jobNo = "J-1"; v.jobs = [job]
        let call = PortCall(); call.portName = "Bonny"; v.portCalls = [call]
        store.data.vessels = [v]
        let before = v.toJSON()
        let e = try #require(store.trash(v))
        #expect(store.restore(e) == .vessel)
        #expect(JSONValue.deepEquals(.object(store.data.vessels[0].toJSON()), .object(before)))
    }
}

/// A clock that moves forward 1 ms on every read (the system clock's behaviour between successive calls).
private final class RepoTickingClock: AppClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = FixedClock(local: "2026-09-29T14:05:00", zone: TZ.athens).instant()
    private(set) var reads = 0
    let timeZone = TZ.athens

    func instant() -> Date {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        current = current.addingTimeInterval(0.001)
        return current
    }
    func now() -> NetDateTime { NetDateTime(date: instant(), kind: .local, zone: timeZone) }
    func utcNow() -> NetDateTime { NetDateTime(date: instant(), kind: .utc, zone: timeZone) }
    func today() -> CivilDate { now().civilDate }
}
