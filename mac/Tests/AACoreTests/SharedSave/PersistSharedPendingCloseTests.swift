// TV: 01 DATA-055 / D-2 (the close push never overwrites a bundle another copy wrote since our last sync), DATA-057
//     (first start), DATA-053/054 (§7.13 prompt), DATA-181 (conflict copies). Stage V round 2, V2-J6 blocker
//     (REQ-F3-08): a refused close push is persisted, so the next launch asks instead of overwriting the other copy's
//     edit with its own newer close-save. Journey adopted from the V2-J6 verifier.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite("W-PERSIST shared save: a refused close push survives a relaunch", .serialized)
struct PersistSharedPendingCloseTests {
    /// One installed copy of AA (own data folder) that can be "relaunched" over the same folder.
    @MainActor final class Copy {
        let folder: TempFolder
        let secrets = InMemorySecretStore()
        let clock: PersistTestClock
        var ds: DataStore
        var store: AppStore
        var coordinator: SharedSaveCoordinator
        var host: PersistFakeSharedHost

        init(clock: PersistTestClock, name: String) throws {
            self.clock = clock
            folder = TempFolder("v2j6-copy")
            ds = DataStore(appFolder: folder.url, secrets: secrets, clock: clock)
            ds.loadSettings()
            let d = AppData()
            d.equipment.append(Equipment(name: name))
            store = AppStore(dataStore: ds, data: d, clock: clock)
            try store.save()
            coordinator = SharedSaveCoordinator(store: store)
            host = PersistFakeSharedHost(store: store)
            coordinator.host = host
        }

        /// The quit pipeline (ShellQuitPipeline steps 1, 5, 6): stop sync, close-save, conditional push.
        func quit() throws {
            coordinator.stop()
            try store.save()
            coordinator.pushOnCloseIfNeeded()
        }

        /// A fresh launch over the same data folder (LaunchCoordinator: load, start(), checkForUpdate()).
        func relaunch(answerReload: Bool = true) async {
            ds = DataStore(appFolder: folder.url, secrets: secrets, clock: clock)
            ds.loadSettings()
            store = AppStore(dataStore: ds, data: ds.load(), clock: clock)
            coordinator = SharedSaveCoordinator(store: store)
            host = PersistFakeSharedHost(store: store)
            host.answerReload = answerReload
            coordinator.host = host
            coordinator.pushInterval = .seconds(3600); coordinator.pollInterval = .seconds(3600)
            coordinator.start()
            await coordinator.checkForUpdate()
        }

        var names: [String] { store.data.equipment.map(\.name) }
        var marker: URL { SharedSavePendingClose.url(folder.url) }
    }

    /// A and B on one bundle; B pushes an edit; A edits and quits before its poll saw B's push.
    private func refusedClose() async throws -> (a: Copy, b: Copy, bundle: URL, shared: TempFolder) {
        let clock = PersistTestClock()
        let shared = TempFolder("v2j6-shared")
        let bundle = shared.file("aa-shared.zip")
        let a = try Copy(clock: clock, name: "Pump")
        let b = try Copy(clock: clock, name: "x")
        try await a.coordinator.adoptSharedFile(bundle, useItsContents: false); a.coordinator.stop()
        clock.advance(2)
        try await b.coordinator.adoptSharedFile(bundle, useItsContents: true); b.coordinator.stop()
        clock.advance(20)
        b.store.data.equipment.append(Equipment(name: "B's new boiler"))
        try b.store.save()
        await b.coordinator.tick()
        #expect(await persistWait(timeout: 60) { !b.coordinator.isPushRunning })
        clock.advance(10)
        a.store.data.equipment.append(Equipment(name: "A's new valve"))
        a.store.markDirty()
        try a.quit()
        return (a, b, bundle, shared)
    }

    @Test("Close refused → relaunch asks; Reload pulls; A's next push keeps B's edit; B keeps it too")
    func closeRefusedThenRelaunchReload() async throws {
        let (a, b, bundle, shared) = try await refusedClose(); _ = shared
        #expect(ConflictCopies.list(a.ds).count == 1)                                    // ours kept as -mine
        #expect(BundleService.peekZipData(bundle, dataStore: a.ds)?.equipment.map(\.name).contains("B's new boiler") == true)
        #expect(FileManager.default.fileExists(atPath: a.marker.path))                  // the refusal is remembered
        // Next morning A launches: it must ask (not treat its close-save as in sync).
        a.clock.advance(3600)
        await a.relaunch(answerReload: true)
        #expect(a.host.prompts == 1)
        #expect(a.names.contains("B's new boiler"))
        #expect(a.coordinator.pendingClose == nil && !FileManager.default.fileExists(atPath: a.marker.path))
        // A works on; its periodic push carries B's edit.
        a.clock.advance(60)
        a.store.data.equipment[0].name = "Pump (A)"
        try a.store.save()
        await a.coordinator.tick()
        #expect(await persistWait(timeout: 60) { !a.coordinator.isPushRunning })
        let after = BundleService.peekZipData(bundle, dataStore: a.ds)?.equipment.map(\.name) ?? []
        #expect(after.contains("B's new boiler"), "B's edit was erased from the shared bundle: \(after)")
        a.clock.advance(60)
        await b.coordinator.checkForUpdate()
        #expect(b.names.contains("B's new boiler"), "B's edit lost on B too: \(b.names)")
    }

    @Test("Close refused → relaunch, Keep Mine: the bundle's data is kept as -theirs before our push replaces it")
    func closeRefusedThenRelaunchKeepMine() async throws {
        let (a, _, bundle, shared) = try await refusedClose(); _ = shared
        a.clock.advance(3600)
        await a.relaunch(answerReload: false)
        #expect(a.host.prompts == 1)
        #expect(a.names.contains("A's new valve") && !a.names.contains("B's new boiler"))
        let copies = ConflictCopies.list(a.ds)
        #expect(copies.count == 2)                                                       // -mine (close) + -theirs
        #expect(PersistConflictStore.names(in: PersistConflictStore.folder(a.folder.url)).contains { $0.hasSuffix("-theirs.json") })
        #expect(a.coordinator.pendingClose == nil && !FileManager.default.fileExists(atPath: a.marker.path))
        // The explicit choice: the next tick pushes ours.
        a.clock.advance(60)
        await a.coordinator.tick()
        #expect(await persistWait(timeout: 60) { !a.coordinator.isPushRunning })
        #expect(BundleService.peekZipData(bundle, dataStore: a.ds)?.equipment.map(\.name).contains("A's new valve") == true)
    }

    @Test("While a refusal is pending no push runs, and a second quit refuses again (marker keeps the old sync stamp)")
    func pendingBlocksPushes() async throws {
        let (a, _, bundle, shared) = try await refusedClose(); _ = shared
        let first = try #require(SharedSavePendingClose.load(a.folder.url))
        // Relaunch with the share unreachable: the bundle is moved away, so the check cannot ask.
        let parked = bundle.deletingLastPathComponent().appending(path: "parked.zip")
        try FileManager.default.moveItem(at: bundle, to: parked)
        a.clock.advance(3600)
        await a.relaunch()
        #expect(a.coordinator.pendingClose != nil && a.host.prompts == 0)
        try FileManager.default.moveItem(at: parked, to: bundle)
        let stampBefore = BundleService.peekZipLastModified(bundle)
        // Quit again without the check having run: still refused, the marker keeps the pre-close sync stamp.
        a.clock.advance(10)
        a.store.data.equipment.append(Equipment(name: "A's second edit"))
        try a.quit()
        #expect(BundleService.peekZipLastModified(bundle) == stampBefore)
        #expect(SharedSavePendingClose.load(a.folder.url)?.lastSyncedTicks == first.lastSyncedTicks)
    }

    @Test("Stop using / adopting another file clears a pending refusal")
    func stopUsingClearsMarker() async throws {
        let (a, _, _, shared) = try await refusedClose(); _ = shared
        #expect(FileManager.default.fileExists(atPath: a.marker.path))
        a.coordinator.stopUsing()
        #expect(!FileManager.default.fileExists(atPath: a.marker.path))
        // A marker for another path is ignored (and dropped) at the next start.
        SharedSavePendingClose(sharedSaveFile: "/Volumes/Other/aa-shared.zip", lastSynced: nil,
                               bundleStamp: NetDateTime(ticks: 1, kind: .local)).save(a.folder.url)
        let other = TempFolder("v2j6-other")
        a.ds.settings.setSharedSaveFile(other.file("aa-shared.zip").path)
        await a.relaunch()
        #expect(a.coordinator.pendingClose == nil)
        #expect(!FileManager.default.fileExists(atPath: a.marker.path))
    }
}
