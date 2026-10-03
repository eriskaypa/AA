// TV: 01 MP.7.5 X-1…X-11 (outside changes, clock fixed at 2026-09-30 14:15:02), DATA-180/181, §MP.3.4.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite("W-PERSIST data-file fingerprint and conflict copies", .serialized)
struct PersistFingerprintTests {
    struct Rig {
        let made: StoreFactory.Made
        let fp: DataFileFingerprint
        let host: PersistFakeConflictHost
        var store: AppStore { made.store }
        var ds: DataStore { made.dataStore }
        var statuses: [String] { statusBox.items }
        let statusBox: Box
    }

    final class Box { var items: [String] = [] }

    /// A store at 2026-09-30 14:15:02 with the guard installed, one saved model ("Pump").
    private func rig(encrypted: Bool = false) throws -> Rig {
        let clock = FixedClock(local: "2026-09-30T14:15:02", zone: .current)
        let made = StoreFactory.make(clock: clock)
        let host = PersistFakeConflictHost()
        let fp = DataFileFingerprint(store: made.store, host: host)
        made.store.writer.writeGuard = fp
        made.dataStore.writeGuard = fp
        let box = Box()
        fp.statusHandler = { box.items.append($0) }
        if encrypted { made.dataStore.settings.setEncryptLocalData(true) }
        fp.table.recordAbsentIfUnknown(made.dataStore.currentDataFile)
        let d = AppData()
        d.equipment.append(Equipment(name: "Pump"))
        made.store.replaceData(d, reason: .initialLoad)
        try made.store.save()
        return Rig(made: made, fp: fp, host: host, statusBox: box)
    }

    /// Valid AA JSON written by "another program" (a new inode, like an atomic replace).
    private func outsideWrite(_ r: Rig, name: String) throws -> Data {
        let other = AppData()
        other.equipment.append(Equipment(name: name))
        other.lastModified = NetDateTime(parsing: "2026-09-30T14:14:00")
        let bytes = try JSONWriter.data(ModelCodec.encodeAppData(other))
        try AtomicWrite.write(bytes, to: r.ds.currentDataFile)
        return bytes
    }

    private func conflicts(_ r: Rig) -> [String] { PersistConflictStore.names(in: PersistConflictStore.folder(r.ds.appFolder)) }

    @Test("X-1 our own writes keep the fingerprint current (the inode changes, no conflict)")
    func ownWrites() throws {
        let r = try rig()
        r.store.data.equipment[0].name = "Pump 2"
        try r.store.save()
        try r.store.save()
        #expect(r.host.presented.isEmpty)
        #expect(!r.store.writesPaused)
    }

    @Test("X-2 touching the file (mtime only) is not a conflict")
    func touchOnly() throws {
        let r = try rig()
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)],
                                              ofItemAtPath: r.ds.currentDataFile.path)
        try r.store.save()
        #expect(r.host.presented.isEmpty)
    }

    @Test("X-3 outside replacement: the save is refused, the sheet appears; Keep Mine keeps their bytes as -theirs")
    func keepMine() async throws {
        let r = try rig()
        let theirs = try outsideWrite(r, name: "Theirs")
        r.store.data.equipment[0].name = "Mine"
        r.store.markDirty()
        #expect(throws: AppStoreError.pausedByGuard) { try r.store.save() }
        #expect(r.store.writesPaused)
        #expect(await persistWait { !r.fp.state.isHandling && r.host.presented.count == 1 })
        let c = try #require(r.host.presented.first)
        if case .changed = c.kind {} else { Issue.record("kind \(c.kind)") }
        #expect(c.fileName == "data.json")
        #expect(c.ourTime == "2026-09-30 14:15:02")
        #expect(c.theirTime == "2026-09-30 14:14:00")
        #expect(PersistConflictText.message(c).hasPrefix("“data.json” was replaced by another program — another computer, a sync or backup tool, or AA on Windows — after this copy last saved it (2026-09-30 14:15:02).\n\nTheir version was saved: 2026-09-30 14:14:00\n\n"))
        #expect(conflicts(r) == ["data-20260930-141502-theirs.json"])
        let copy = PersistConflictStore.folder(r.ds.appFolder).appending(path: "data-20260930-141502-theirs.json")
        #expect(try Data(contentsOf: copy) == theirs)
        #expect(r.ds.load().equipment.first?.name == "Mine")
        #expect(!r.store.writesPaused)
        #expect(r.statuses.last == "Kept your version — the other version was saved to conflicts/data-20260930-141502-theirs.json.")
        r.store.data.equipment[0].name = "Mine again"
        try r.store.save()
        #expect(r.host.presented.count == 1)
    }

    @Test("X-4 Use Theirs: our model goes to -mine (encrypted when encryption is on); the model becomes theirs")
    func useTheirs() async throws {
        for encrypted in [false, true] {
            let r = try rig(encrypted: encrypted)
            r.host.choice = .useTheirs
            _ = try outsideWrite(r, name: "Theirs")
            r.store.data.equipment[0].name = "Mine"
            r.store.markDirty()
            #expect(throws: AppStoreError.pausedByGuard) { try r.store.save() }
            #expect(await persistWait { !r.fp.state.isHandling && r.store.data.equipment.first?.name == "Theirs" })
            #expect(conflicts(r) == ["data-20260930-141502-mine.json"])
            let mine = try Data(contentsOf: PersistConflictStore.folder(r.ds.appFolder).appending(path: "data-20260930-141502-mine.json"))
            if encrypted {
                #expect(mine.starts(with: Data("AAENCM1\n".utf8)))
            } else {
                let parsed = try ModelCodec.decodeAppData(try JSONParser.parse(mine), context: JSONDecodeContext())
                #expect(parsed.equipment.first?.name == "Mine")
            }
            #expect(r.statuses.last == "Loaded the other version — yours was saved to conflicts/data-20260930-141502-mine.json.")
            #expect(!r.store.writesPaused)
            r.store.data.equipment[0].name = "Edit after"
            try r.store.save()
            #expect(r.host.presented.count == 1)
        }
    }

    @Test("X-5 a Windows-encrypted outside file: only Keep Mine / Stop Editing; Keep Mine keeps their bytes")
    func unreadable() async throws {
        let r = try rig()
        let theirs = Data([0x41, 0x41, 0x45, 0x4E, 0x43, 0x31, 0x0A, 0x01, 0x02])
        try AtomicWrite.write(theirs, to: r.ds.currentDataFile)
        r.store.markDirty()
        #expect(throws: AppStoreError.pausedByGuard) { try r.store.save() }
        #expect(await persistWait { !r.fp.state.isHandling && r.host.presented.count == 1 })
        let c = try #require(r.host.presented.first)
        guard case .unreadable(let reason) = c.kind else { Issue.record("kind"); return }
        #expect(reason == "it was encrypted by AA on Windows")
        #expect(PersistConflictText.message(c).contains("Their version can't be opened on this Mac (it was encrypted by AA on Windows), so it can't be reviewed."))
        #expect(r.fp.reviewData(c) == nil)
        let copy = PersistConflictStore.folder(r.ds.appFolder).appending(path: "data-20260930-141502-theirs.json")
        #expect(try Data(contentsOf: copy) == theirs)
        #expect(r.ds.load().equipment.first?.name == "Pump")
    }

    @Test("X-6 an outside delete: the deleted variant; Keep Mine recreates the file")
    func deleted() async throws {
        let r = try rig()
        try FileManager.default.removeItem(at: r.ds.currentDataFile)
        r.store.markDirty()
        #expect(throws: AppStoreError.pausedByGuard) { try r.store.save() }
        #expect(await persistWait { !r.fp.state.isHandling && r.host.presented.count == 1 })
        let c = try #require(r.host.presented.first)
        if case .deleted = c.kind {} else { Issue.record("kind") }
        #expect(PersistConflictText.message(c).hasPrefix("“data.json” was deleted by another program"))
        #expect(FileManager.default.fileExists(atPath: r.ds.currentDataFile.path))
        #expect(conflicts(r).isEmpty)
    }

    @Test("X-7 our own shared import, ApplySyncedData and an encryption re-save never raise the sheet")
    func ownDeliberateWrites() async throws {
        let r = try rig()
        let t = TempFolder("persist-x7")
        let bundle = t.file("b.zip")
        try PersistZip.make(bundle, [("data.json", try persistDataJSON(r.ds, name: "Shared", stamp: nil))])
        try BundleService.importSharedBundle(r.ds, from: bundle)
        r.store.replaceData(r.ds.load(), reason: .sharedSavePull)
        try r.store.save()
        _ = try r.ds.applySyncedData(try persistDataJSON(r.ds, name: "Phone", stamp: nil))
        r.store.replaceData(r.ds.load(), reason: .flashSyncApply)
        try r.store.save()
        r.ds.settings.setEncryptLocalData(true)
        r.store.markDirty()
        try r.store.save()
        #expect(LocalEncryption.classify(try Data(contentsOf: r.ds.currentDataFile)) == .mac)
        try r.store.save()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(r.host.presented.isEmpty)
        #expect(conflicts(r).isEmpty)
    }

    @Test("A deliberate replacement keeps a foreign version as -theirs first (nothing lost)")
    func deliberateKeepsForeign() throws {
        let r = try rig()
        let theirs = try outsideWrite(r, name: "Theirs")
        _ = try r.ds.applySyncedData(try persistDataJSON(r.ds, name: "Phone", stamp: nil))
        let copy = PersistConflictStore.folder(r.ds.appFolder).appending(path: "data-20260930-141502-theirs.json")
        #expect(try Data(contentsOf: copy) == theirs)
    }

    @Test("X-8 21 conflict copies → the newest 20 remain; X-9 two in one second get -2")
    func retentionAndNaming() throws {
        let t = TempFolder("persist-x8")
        let base = FixedClock(local: "2026-09-30T14:15:02", zone: .current).instant()
        var names: [String] = []
        for i in 0..<21 {
            names.append(try PersistConflictStore.add(Data("\(i)".utf8), theirs: true, appFolder: t.url,
                                                      now: base.addingTimeInterval(TimeInterval(i)), zone: .current))
        }
        let kept = PersistConflictStore.names(in: PersistConflictStore.folder(t.url))
        #expect(kept.count == 20)
        #expect(!kept.contains(names[0]))
        #expect(kept.first == names[20])
        let t2 = TempFolder("persist-x9")
        let a = try PersistConflictStore.add(Data("a".utf8), theirs: true, appFolder: t2.url, now: base, zone: .current)
        let b = try PersistConflictStore.add(Data("b".utf8), theirs: true, appFolder: t2.url, now: base, zone: .current)
        let m = try PersistConflictStore.add(Data("m".utf8), theirs: false, appFolder: t2.url, now: base, zone: .current)
        #expect(a == "data-20260930-141502-theirs.json")
        #expect(b == "data-20260930-141502-2-theirs.json")
        #expect(m == "data-20260930-141502-mine.json")
        #expect(PersistConflictStore.names(in: PersistConflictStore.folder(t2.url)).first == b)
        #expect(PersistConflictStore.parse("data-20260930-141502-2-theirs.json")?.seq == 2)
        #expect(PersistConflictStore.parse("notes.json") == nil)
    }

    @Test("X-10 not dirty: the watcher shows the sheet after the debounce (no silent reload)")
    func watcherNotDirty() async throws {
        let r = try rig()
        r.fp.watchDebounce = .milliseconds(80)
        r.fp.start()
        defer { r.fp.stop() }
        #expect(r.fp.isWatching)
        #expect(!r.store.isDirty)
        _ = try outsideWrite(r, name: "Theirs")
        #expect(await persistWait { r.host.presented.count == 1 })
        #expect(await persistWait { !r.fp.state.isHandling })
        #expect(r.fp.state.outsideWriteSeen)
    }

    @Test("X-11 Stop Editing Here, then another outside change → silent reload; Resume Editing → normal")
    func stopEditing() async throws {
        let r = try rig()
        r.host.choice = .stopEditingHere
        _ = try outsideWrite(r, name: "Theirs 1")
        r.store.markDirty()
        #expect(throws: AppStoreError.pausedByGuard) { try r.store.save() }
        #expect(await persistWait { r.fp.state.mode == .stoppedEditing && !r.fp.state.isHandling })
        #expect(r.store.data.equipment.first?.name == "Theirs 1")
        #expect(r.ds.settings.isWriteGated)
        #expect(r.store.writesPaused)
        #expect(conflicts(r) == ["data-20260930-141502-mine.json"])
        _ = try outsideWrite(r, name: "Theirs 2")
        await r.fp.checkNowAndWait()
        #expect(r.host.presented.count == 1)
        #expect(r.store.data.equipment.first?.name == "Theirs 2")
        #expect(r.statuses.contains { $0.hasPrefix("Updated from the other copy of AA (") && $0.hasSuffix(").") })
        r.fp.resumeEditing()
        #expect(r.fp.state.mode == .normal)
        #expect(!r.store.writesPaused)
        #expect(!r.ds.settings.isWriteGated)
        r.store.data.equipment[0].name = "Resumed"
        try r.store.save()
        #expect(r.host.presented.count == 1)
    }

    @Test("Conflict-copies list: newest first, kind, size, LastModified without loading; restore applies it")
    func listAndRestore() throws {
        let r = try rig()
        let theirs = try persistDataJSON(r.ds, name: "Old version", stamp: NetDateTime(parsing: "2026-09-29T08:00:00"))
        _ = try PersistConflictStore.add(theirs, theirs: true, appFolder: r.ds.appFolder,
                                         now: r.ds.clock.instant().addingTimeInterval(-60), zone: .current)
        _ = try ConflictCopies.saveMine(r.store)
        let list = ConflictCopies.list(r.ds)
        #expect(list.map(\.fileName) == ["data-20260930-141502-mine.json", "data-20260930-141402-theirs.json"])
        #expect(list[1].isTheirs && !list[0].isTheirs)
        #expect(list[1].size == Int64(theirs.count))
        #expect(list[1].lastModified == NetDateTime(parsing: "2026-09-29T08:00:00"))
        #expect(ConflictCopies.url(of: list[1], r.ds).lastPathComponent == "data-20260930-141402-theirs.json")
        #expect(ConflictCopies.peekData(list[1], r.ds)?.equipment.first?.name == "Old version")
        let restored = try ConflictCopies.restore(list[1], r.ds)
        #expect(restored.equipment.first?.name == "Old version")
        #expect(r.ds.currentDataFile.standardizedFileURL == r.ds.defaultDataFile.standardizedFileURL)
        #expect(r.ds.load().equipment.first?.name == "Old version")
    }

    @Test("§MP.3.4 table: absent → created is a change; a file never seen is not guarded")
    func tableRules() throws {
        let t = TempFolder("persist-fp")
        let table = PersistFingerprintTable()
        let url = t.file("data.json")
        #expect(table.check(url) == .ok)                                  // unknown → not guarded
        table.recordAbsentIfUnknown(url)
        #expect(table.check(url) == .ok)                                  // still absent
        try Data("{}".utf8).write(to: url)
        #expect(table.check(url) == .foreignChanged(Data("{}".utf8)))     // someone created it
        table.acceptCurrent(url)
        #expect(table.check(url) == .ok)
        try FileManager.default.removeItem(at: url)
        #expect(table.check(url) == .foreignDeleted)
    }
}
