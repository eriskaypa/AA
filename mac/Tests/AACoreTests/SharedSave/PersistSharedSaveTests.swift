// TV: 01 §7.13 (CheckForUpdate decision table, on-close table), 03 §7.2 (shared-save state machine 1–8), DATA-050…058,
//     SHELL-023 (indicator texts), SHELL-123…126, D-1 (push when unsynced), D-2 (close push vs last sync), D-12 (safe mode).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite("W-PERSIST shared save coordinator", .serialized)
struct PersistSharedSaveTests {
    /// One copy of AA: its own data folder, store, coordinator and scripted host; all copies share `shared`.
    final class Copy {
        let made: StoreFactory.Made
        let coordinator: SharedSaveCoordinator
        let host: PersistFakeSharedHost
        var store: AppStore { made.store }
        var ds: DataStore { made.dataStore }

        @MainActor init(clock: PersistTestClock, shared: URL?, name: String = "Pump") throws {
            made = StoreFactory.make(clock: clock)
            let d = AppData()
            d.equipment.append(Equipment(name: name))
            made.store.replaceData(d, reason: .initialLoad)
            try made.store.save()
            coordinator = SharedSaveCoordinator(store: made.store)
            host = PersistFakeSharedHost(store: made.store)
            coordinator.host = host
            if let shared { made.dataStore.settings.setSharedSaveFile(shared.path) }
        }
    }

    private func sharedFolder() -> (TempFolder, URL) {
        let t = TempFolder("persist-shared")
        return (t, t.file("aa-shared.zip"))
    }

    @Test("No shared file: indicator hidden (SHELL-023)")
    func off() throws {
        let clock = PersistTestClock()
        let a = try Copy(clock: clock, shared: nil)
        a.coordinator.start()
        #expect(a.coordinator.health == .off)
        #expect(a.coordinator.indicatorText == "")
        #expect(a.coordinator.indicatorHelp == "")
        #expect(!a.coordinator.isRunning)
    }

    @Test("§7.2-1 folder exists, no bundle → healthy, 'Shared save on'")
    func noBundleYet() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared)
        await a.coordinator.checkForUpdate()
        #expect(a.coordinator.health == .online(lastSync: nil))
        #expect(a.coordinator.indicatorText == "🔗 Shared save on")
        #expect(a.coordinator.indicatorHelp == PersistSharedText.tooltip)
    }

    @Test("§7.2-2 folder missing → OFFLINE since HH:mm; back with an old bundle → green again")
    func offlineAndBack() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared)
        try a.coordinator.push(label: "Shared save")
        let synced = clock.hhmm
        let moved = t.url.deletingLastPathComponent().appending(path: t.url.lastPathComponent + "-gone")
        try FileManager.default.moveItem(at: t.url, to: moved)
        clock.advance(120)
        await a.coordinator.checkForUpdate()
        #expect(a.coordinator.indicatorText == "⚠ Shared save OFFLINE since \(clock.hhmm) — retrying")
        try FileManager.default.moveItem(at: moved, to: t.url)
        clock.advance(60)
        await a.coordinator.checkForUpdate()
        #expect(a.coordinator.indicatorText == "🔗 Shared synced \(synced)")
    }

    @Test("§7.2-3 a failed push shows NOT SAVING; a reachability check alone does not clear it; a push does")
    func notSaving() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared)
        // The bundle's folder is read-only → the temp ZIP cannot be created.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: t.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: t.url.path) }
        #expect(throws: (any Error).self) { try a.coordinator.push(label: "Shared save") }
        let since = clock.hhmm
        #expect(a.coordinator.indicatorText == "⚠ Shared save NOT SAVING since \(since) — last write failed")
        #expect(a.host.lastStatus?.hasPrefix("Shared save failed: ") == true)
        clock.advance(60)
        await a.coordinator.checkForUpdate()
        #expect(a.coordinator.indicatorText == "⚠ Shared save NOT SAVING since \(since) — last write failed")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: t.url.path)
        try a.coordinator.push(label: "Shared save")
        #expect(a.coordinator.indicatorText == "🔗 Shared synced \(clock.hhmm)")
        #expect(a.host.lastStatus == "Shared save written \(clock.hms) (data + attachments).")
    }

    @Test("§7.2-4 / §7.13 our own push (bundle stamp == lastSeen) → no reload, no prompt")
    func ownPushIgnored() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared)
        try a.coordinator.push(label: "Shared save")
        a.store.data.equipment[0].name = "Edited"
        a.store.markDirty()
        await a.coordinator.checkForUpdate()
        #expect(a.host.prompts == 0)
        #expect(a.host.reloads.isEmpty)
    }

    @Test("§7.2-5 newer bundle and no unsynced changes → silent pull; S = Y = new L")
    func silentPull() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared, name: "From A")
        let b = try Copy(clock: clock, shared: shared, name: "From B")
        b.coordinator.start(); b.coordinator.stop()                        // DATA-057: B starts in sync with its data
        a.ds.settings.setAppIdentity("Bridge")
        clock.advance(30)
        try a.coordinator.push(label: "Shared save")
        await b.coordinator.checkForUpdate()
        #expect(b.host.prompts == 0)
        #expect(b.host.reloads == ["Bridge"])
        #expect(b.store.data.equipment.first?.name == "From A")
        #expect(b.coordinator.lastSeen == b.store.data.lastModified)
        #expect(b.coordinator.lastSynced == b.store.data.lastModified)
        #expect(b.coordinator.indicatorText == "🔗 Shared synced \(clock.hhmm)")
    }

    @Test("§7.2-6 newer bundle with a local edit pending → prompt; Keep Mine → S = B and no re-prompt")
    func promptKeepMine() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared, name: "From A")
        let b = try Copy(clock: clock, shared: shared, name: "From B")
        b.coordinator.start(); b.coordinator.stop()
        clock.advance(30)
        try a.coordinator.push(label: "Shared save")
        let bundleStamp = try #require(BundleService.peekZipLastModified(shared))
        b.store.data.equipment[0].name = "B edit"
        b.store.markDirty()
        b.host.answerReload = false
        await b.coordinator.checkForUpdate()
        #expect(b.host.prompts == 1)
        #expect(b.coordinator.lastSeen == bundleStamp)
        #expect(b.store.data.equipment.first?.name == "B edit")
        await b.coordinator.checkForUpdate()
        #expect(b.host.prompts == 1)
    }

    @Test("§7.13 B > L, !d, L > Y → prompt; Reload → pulled")
    func promptWhenSavedButUnsynced() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared, name: "From A")
        let b = try Copy(clock: clock, shared: shared, name: "From B")
        b.coordinator.start(); b.coordinator.stop()
        clock.advance(10)
        b.store.data.equipment[0].name = "B saved"
        try b.store.save()                                                 // L > Y, not dirty
        clock.advance(10)
        try a.coordinator.push(label: "Shared save")
        b.host.answerReload = true
        await b.coordinator.checkForUpdate()
        #expect(b.host.prompts == 1)
        #expect(b.store.data.equipment.first?.name == "From A")
    }

    @Test("§7.13 B ≤ L → healthy, no pull")
    func notNewer() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared, name: "From A")
        try a.coordinator.push(label: "Shared save")
        let b = try Copy(clock: clock, shared: shared, name: "From B")   // saved after the push (same instant)
        clock.advance(5)
        b.store.data.equipment[0].name = "Newer"
        try b.store.save()
        await b.coordinator.checkForUpdate()
        #expect(b.host.reloads.isEmpty)
        #expect(b.coordinator.health == .online(lastSync: nil))
    }

    @Test("§7.2-7 torn bundle → no state change; an import failure → 'Shared reload skipped (busy): …'")
    func tornBundle() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let b = try Copy(clock: clock, shared: shared)
        try Data("PK\u{3}\u{4}torn".utf8).write(to: shared)
        await b.coordinator.checkForUpdate()
        #expect(b.coordinator.health == .off)                                 // nothing ran yet → unchanged
        #expect(b.host.statuses.isEmpty)
        // Readable stamp but no data.json? A bundle whose data.json is invalid JSON beyond the stamp.
        clock.advance(60)
        let future = NetDateTime(year: 2030, month: 1, day: 1, kind: .local)
        try PersistZip.make(shared, [("data.json", Data("{\"LastModified\":\"\(future.jsonString())\",\"Equipment\":7}".utf8))])
        await b.coordinator.checkForUpdate()
        #expect(b.host.lastStatus?.hasPrefix("Shared reload skipped (busy): ") == true)
        #expect(b.store.data.equipment.first?.name == "Pump")
        #expect(b.ds.load().equipment.first?.name == "Pump")
    }

    @Test("§7.2-8 on quit: bundle absent → created; unreadable → not overwritten")
    func onClose() throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared)
        a.coordinator.pushOnCloseIfNeeded()
        #expect(FileManager.default.fileExists(atPath: shared.path))
        #expect(a.host.lastStatus?.hasPrefix("Shared save (on close) written ") == true)
        try Data("garbage".utf8).write(to: shared)
        a.coordinator.pushOnCloseIfNeeded()
        #expect(try Data(contentsOf: shared) == Data("garbage".utf8))
    }

    @Test("D-2 close-push decision: own/declined stamp or not newer than the last sync → push; else keep both")
    func closeDecision() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared, name: "From A")
        let b = try Copy(clock: clock, shared: shared, name: "From B")
        try b.coordinator.push(label: "Shared save")
        let ours = try #require(b.coordinator.lastSynced)
        #expect(b.coordinator.closePushAllowed(bundleStamp: ours))
        #expect(b.coordinator.closePushAllowed(bundleStamp: ours.addingTicks(-1)))
        #expect(!b.coordinator.closePushAllowed(bundleStamp: ours.addingTicks(NetDateTime.ticksPerSecond)))
        // Another copy pushed after our last sync: on close we do not overwrite it; ours is kept as a conflict copy.
        clock.advance(20)
        try a.coordinator.push(label: "Shared save")
        let theirs = try Data(contentsOf: shared)
        b.coordinator.pushOnCloseIfNeeded()
        #expect(try Data(contentsOf: shared) == theirs)
        #expect(ConflictCopies.list(b.ds).count == 1)
        #expect(ConflictCopies.list(b.ds).first?.isTheirs == false)
    }

    @Test("D-1: the periodic tick pushes data saved since the last sync even when not dirty")
    func tickPushesUnsynced() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared)
        a.coordinator.start(); a.coordinator.stop()
        await a.coordinator.tick()
        #expect(!FileManager.default.fileExists(atPath: shared.path))       // nothing unsynced yet
        clock.advance(5)
        a.store.data.equipment[0].name = "Autosaved edit"
        try a.store.save()
        #expect(!a.store.isDirty)
        await a.coordinator.tick()
        #expect(await persistWait { !a.coordinator.isPushRunning && FileManager.default.fileExists(atPath: shared.path) })
        #expect(BundleService.peekZipData(shared, dataStore: a.ds)?.equipment.first?.name == "Autosaved edit")
        #expect(a.host.lastStatus == "Shared save written \(clock.hms) (data + attachments).")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: t.url.path).filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test("Text-only export also governs the shared bundle (DATA-042)")
    func textOnlyShared() throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared)
        try Data("pdf".utf8).write(to: a.ds.filesFolder.appending(path: "x.pdf"))
        a.ds.settings.setTextOnlyExport(true)
        try a.coordinator.push(label: "Shared save")
        #expect(Set(try PersistZip.names(shared)) == ["data.json", "source.json"])
        #expect(a.host.lastStatus?.hasSuffix("(data + attachments).") == true)
    }

    @Test("Adopt: use its contents → data + attachments imported, in sync; keep mine → bundle written")
    func adopt() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared, name: "From A")
        try Data("pdf".utf8).write(to: a.ds.filesFolder.appending(path: "x.pdf"))
        try a.coordinator.push(label: "Shared save")
        let b = try Copy(clock: clock, shared: nil, name: "From B")
        try await b.coordinator.adoptSharedFile(shared, useItsContents: true)
        #expect(b.store.data.equipment.first?.name == "From A")
        #expect(persistListing(b.ds.filesFolder)["x.pdf"] == 3)
        #expect(b.ds.settings.values.sharedSaveFile == shared.path)
        #expect(b.coordinator.lastSeen == b.store.data.lastModified)
        #expect(b.coordinator.isRunning)
        b.coordinator.stop()
        let c = try Copy(clock: clock, shared: nil, name: "From C")
        clock.advance(5)
        try await c.coordinator.adoptSharedFile(shared, useItsContents: false)
        #expect(BundleService.peekZipData(shared, dataStore: c.ds)?.equipment.first?.name == "From C")
        c.coordinator.stopUsing()
        #expect(c.coordinator.health == .off)
        #expect(c.ds.settings.values.sharedSaveFile == nil)
        #expect(!c.coordinator.isRunning)
    }

    @Test("Adopt failure clears the setting and rethrows")
    func adoptFailure() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        try PersistZip.make(shared, [("readme.txt", Data("no data".utf8))])
        let b = try Copy(clock: clock, shared: nil)
        await #expect(throws: PersistBundleError.sharedNoDataJSON) {
            try await b.coordinator.adoptSharedFile(shared, useItsContents: true)
        }
        #expect(b.ds.settings.values.sharedSaveFile == nil)
        #expect(b.coordinator.health == .off)
    }

    @Test("D-12 safe mode: an unreadable local file is never replaced silently, and is kept as a copy")
    func safeModeAsks() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared, name: "From A")
        clock.advance(5)
        try a.coordinator.push(label: "Shared save")
        let made = StoreFactory.make(clock: clock)
        try Data("{ unreadable".utf8).write(to: made.dataStore.defaultDataFile)
        made.store.replaceData(made.dataStore.load(), reason: .initialLoad)
        #expect(made.dataStore.lastLoadFailed)
        made.dataStore.settings.setSharedSaveFile(shared.path)
        let c = SharedSaveCoordinator(store: made.store)
        let host = PersistFakeSharedHost(store: made.store)
        host.answerReload = false
        c.host = host
        await c.checkForUpdate()
        #expect(host.prompts == 1)
        #expect(host.reloads.isEmpty)
        host.answerReload = true
        clock.advance(5)
        try a.coordinator.push(label: "Shared save")
        await c.checkForUpdate()
        #expect(host.reloads.count == 1)
        let kept = try FileManager.default.contentsOfDirectory(atPath: made.dataStore.appFolder.path)
            .filter { $0.hasPrefix("data.unreadable-") && $0.hasSuffix(".json") }
        #expect(kept.count == 1)
    }

    @Test("Timers and the directory watcher: an outside push is pulled after the debounce")
    func watcherPulls() async throws {
        let clock = PersistTestClock()
        let (t, shared) = sharedFolder(); _ = t
        let a = try Copy(clock: clock, shared: shared, name: "From A")
        let b = try Copy(clock: clock, shared: shared, name: "From B")
        b.coordinator.debounce = .milliseconds(100)
        b.coordinator.pollInterval = .seconds(3600)
        b.coordinator.pushInterval = .seconds(3600)
        b.coordinator.start()
        defer { b.coordinator.stop() }
        clock.advance(10)
        try a.coordinator.push(label: "Shared save")
        #expect(await persistWait { b.store.data.equipment.first?.name == "From A" })
    }
}
