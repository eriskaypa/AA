// TV: 01 DATA-052 / D-1 (push when unsynced), DATA-053/054 (§7.13 pull prompt), Deviations W-PERSIST-21 (the stamps
//     recorded by a push are the pushed data's stamp). Round-2 findings V2-J6 and V2-SCALE.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite("W-PERSIST shared save: edits saved while a background push is zipping", .serialized)
struct PersistSharedSaveRaceTests {
    typealias Copy = PersistSharedSaveTests.Copy

    @Test("V2-J6: an edit saved during a background push stays unsynced and the next tick pushes it")
    func editDuringBackgroundPushIsPushedNextTick() async throws {
        let clock = PersistTestClock()
        let t = TempFolder("v2j6-shared"); _ = t
        let bundle = t.file("aa-shared.zip")
        let a = try Copy(clock: clock, shared: bundle, name: "Pump")
        a.coordinator.start(); a.coordinator.stop()
        clock.advance(5)
        a.store.data.equipment[0].name = "Edit 1"; try a.store.save()
        await a.coordinator.tick()
        #expect(a.coordinator.isPushRunning)
        // The 750-ms autosave lands while the ZIP is still being written.
        clock.advance(1)
        a.store.data.equipment[0].name = "Edit 2"; try a.store.save()
        #expect(await persistWait(timeout: 60) { !a.coordinator.isPushRunning })
        #expect(BundleService.peekZipData(bundle, dataStore: a.ds)?.equipment.first?.name == "Edit 1")
        #expect(a.coordinator.lastSynced == BundleService.peekZipLastModified(bundle))
        #expect(a.coordinator.hasUnsyncedChanges)
        clock.advance(60)
        await a.coordinator.tick()
        #expect(await persistWait(timeout: 60) { !a.coordinator.isPushRunning })
        #expect(BundleService.peekZipData(bundle, dataStore: a.ds)?.equipment.first?.name == "Edit 2")
        #expect(!a.coordinator.hasUnsyncedChanges)
    }

    @Test("V2-SCALE: an edit saved during a background push is not silently discarded by the next pull")
    func editDuringBackgroundPushIsNotLostOnPull() async throws {
        let clock = PersistTestClock()
        let t = TempFolder("v2-shared"); _ = t
        let shared = t.file("aa-shared.zip")
        let a = try Copy(clock: clock, shared: shared, name: "Pump A")
        let b = try Copy(clock: clock, shared: shared, name: "Pump B")
        clock.advance(10)
        a.coordinator.pushInBackground(label: "Shared save")
        clock.advance(10)
        a.store.data.equipment[0].name = "Edited during push"
        a.store.markDirty(); try a.store.save()
        #expect(await persistWait(timeout: 60) { !a.coordinator.isPushRunning })
        #expect(a.coordinator.hasUnsyncedChanges)
        clock.advance(10); await b.coordinator.checkForUpdate()
        clock.advance(10); b.store.data.equipment.append(Equipment(name: "B addition"))
        b.store.markDirty(); try b.store.save(); try b.coordinator.push(label: "Shared save")
        a.host.answerReload = false                                  // Keep Mine
        clock.advance(10); await a.coordinator.checkForUpdate()
        #expect(a.host.prompts == 1)
        #expect(a.store.data.equipment.map(\.name).contains("Edited during push"))
    }

    @Test("The synchronous push records the pushed data's stamp as synced and seen")
    func syncPushRecordsPushedStamp() throws {
        let clock = PersistTestClock()
        let t = TempFolder("v2-sync"); _ = t
        let shared = t.file("aa-shared.zip")
        let a = try Copy(clock: clock, shared: shared)
        clock.advance(10)
        try a.coordinator.push(label: "Shared save")
        let stamp = BundleService.peekZipLastModified(shared)
        #expect(stamp != nil)
        #expect(a.coordinator.lastSynced == stamp)
        #expect(a.coordinator.lastSeen == stamp)
        #expect(!a.coordinator.hasUnsyncedChanges)
    }
}
