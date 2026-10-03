// Stage V round 2, V2-J1 (sidebar path): `BatchActions.confirmAndTrash` now trashes through `AppStore.trashBatch`
// (F2 API) — one BatchId and ONE DeletedUtc for the whole selection — so ⌘Z restores T1, T2, T3 in their original
// order even with a clock that moves between reads (the system clock does). REPO-072/075/077, HIER-024/135.
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct HierBatchTrashTests {
    @Test func sidebarBatchUndoKeepsSelectionOrderWithAMovingClock() {
        let clock = HierTickingClock()
        let store = StoreFactory.make(clock: clock).store
        let keep = TaskItem(name: "Keep"), t1 = TaskItem(name: "T1"), t2 = TaskItem(name: "T2"), t3 = TaskItem(name: "T3")
        store.data.tasks = [keep, t1, t2, t3]
        // The same steps as confirmAndTrash after the confirmation: top-level picks, ungated, one trashBatch call.
        let picks = BatchDelete.topLevel([t1, t2, t3]).filter { _ in true }
        let readsBefore = clock.reads
        let trashed = store.trashBatch(picks)
        #expect(trashed.map(\.name) == ["T1", "T2", "T3"])
        #expect(clock.reads > readsBefore)
        #expect(Set(store.data.trash.map(\.batchId)).count == 1)
        #expect(Set(store.data.trash.map(\.deletedUtc.ticks)).count == 1)
        #expect(store.data.tasks.map(\.name) == ["Keep"])
        _ = store.undoLastDelete()
        #expect(store.data.tasks.map(\.name) == ["Keep", "T1", "T2", "T3"])
    }
}

/// Moves forward 1 ms on every read, like the system clock between successive calls.
private final class HierTickingClock: AppClock, @unchecked Sendable {
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
