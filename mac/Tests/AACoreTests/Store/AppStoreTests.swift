// TV: 02 REPO-001…008, REPO-003a, 01 DATA-025 (750 ms debounce), DATA-031 (stamping + rollback), DATA-180 (write
//     guard → pause), ARCHITECTURE.md §2.3 (autosave algorithm), §5.2 (AppStore core), §3.9 (observation of base-class
//     properties on subclasses).
import Foundation
import Observation
import Testing
@testable import AACore

/// Counts writes and can refuse them (the DATA-180 hook).
private final class CountingGuard: DataFileWriteGuard, @unchecked Sendable {
    private let lock = NSLock()
    private var _allow = true
    private var _writes: [Date] = []
    private var _refusals = 0
    var allow: Bool { get { lock.withLock { _allow } } set { lock.withLock { _allow = newValue } } }
    var writes: [Date] { lock.withLock { _writes } }
    var refusals: Int { lock.withLock { _refusals } }
    func shouldWrite(to url: URL) -> Bool {
        lock.withLock { if !_allow { _refusals += 1 }; return _allow }
    }
    func didWrite(to url: URL, bytes: Data) { lock.withLock { _writes.append(Date()) } }
    func didLoad(from url: URL, bytes: Data) {}
}

private let clock = FixedClock(local: "2026-09-29T14:05:00", zone: TZ.athens)
private let stampText = "2026-09-29T14:05:00+03:00"

@MainActor @Suite(.serialized) struct AppStoreTests {
    fileprivate func made(_ data: AppData? = nil) -> (StoreFactory.Made, CountingGuard) {
        let m = StoreFactory.make(data: data, clock: clock)
        let g = CountingGuard()
        m.store.writer.writeGuard = g
        return (m, g)
    }

    func fileObject(_ m: StoreFactory.Made) throws -> JSONObject? {
        try JSONParser.parse(Data(contentsOf: m.dataStore.currentDataFile)).objectValue
    }

    /// Polls (on the main actor, letting completions run) until `cond` holds or `seconds` pass.
    func waitUntil(_ seconds: Double, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if cond() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return cond()
    }

    // TV: REPO-002 / DATA-025 — markDirty × N → exactly one write, ≥ 750 ms after the last edit
    @Test func debouncedAutosave() async throws {
        let (m, g) = made()
        var savedCount = 0
        let sub = m.store.saved.subscribe { savedCount += 1 }
        #expect(m.store.debounceInterval == .milliseconds(750))
        m.store.data.tasks = [TaskItem(name: "a")]
        var last = Date()
        for _ in 0..<5 {
            m.store.markDirty()
            last = Date()
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(m.store.isDirty && g.writes.isEmpty)
        #expect(await waitUntil(3) { savedCount == 1 })
        #expect(g.writes.count == 1)
        #expect(g.writes[0].timeIntervalSince(last) >= 0.74)
        #expect(!m.store.isDirty && m.store.lastSaveError == nil)
        #expect(try fileObject(m)?["LastModified"]?.stringValue == stampText)
        #expect(m.store.data.lastModified?.jsonString(zone: TZ.athens) == stampText)
        try await Task.sleep(for: .milliseconds(900))
        #expect(g.writes.count == 1)                                         // nothing else pending
        sub.cancel()
    }

    // TV: REPO-002 step 5 / REPO-004 — a failed background write restores LastModified and re-sets dirty
    @Test func backgroundWriteFailureRollsBack() async throws {
        let (m, _) = made()
        let blocker = try m.folder.write("blocker", "x")                    // a FILE where a folder is needed
        m.dataStore.setCurrentDataFile(blocker.appending(path: "data.json"))
        let before = NetDateTime(year: 2020, month: 1, day: 2, kind: .local)
        m.store.data.lastModified = before
        var saved = 0
        let sub = m.store.saved.subscribe { saved += 1 }
        m.store.markDirty()
        m.store.backgroundSaveIfDirty()                                     // run the tick now
        #expect(!m.store.isDirty)                                           // optimistic clear …
        #expect(await waitUntil(3) { m.store.isDirty })                     // … re-set on failure
        #expect(m.store.data.lastModified == before)
        #expect(m.store.lastSaveError != nil && saved == 0)
        #expect(!m.store.writesPaused)
        sub.cancel()
    }

    // TV: REPO-003 — confirmed save: stamp, write, clear dirty, fire saved; always writes even when clean
    @Test func confirmedSave() throws {
        let (m, g) = made()
        var saved = 0
        let sub = m.store.saved.subscribe { saved += 1 }
        try m.store.save()
        #expect(g.writes.count == 1 && saved == 1 && !m.store.isDirty)
        #expect(try fileObject(m)?["LastModified"]?.stringValue == stampText)
        #expect(try fileObject(m)?["SchemaVersion"] == .number(JSONNumber(1)))
        try m.store.save()
        #expect(g.writes.count == 2 && saved == 2)
        // flushIfDirty only writes when dirty (REPO-008)
        try m.store.flushIfDirty()
        #expect(g.writes.count == 2)
        m.store.markDirty()
        try m.store.flushIfDirty()
        #expect(g.writes.count == 3 && !m.store.isDirty)
        sub.cancel()
    }

    // TV: REPO-003 step 4 — a serialisation failure restores the stamp, leaves dirty as it was, and writes nothing
    @Test func serializationFailure() throws {
        let (m, g) = made()
        let t = TaskItem(name: "x"); t.durationMinutes = Int(Int32.max) + 1
        m.store.data.tasks = [t]
        #expect(throws: AppStoreError.self) { try m.store.save() }
        #expect(m.store.data.lastModified == nil && !m.store.isDirty && g.writes.isEmpty)
        m.store.markDirty()
        #expect(throws: AppStoreError.self) { try m.store.save() }
        #expect(m.store.isDirty)
        m.store.backgroundSaveIfDirty()
        #expect(m.store.isDirty && m.store.data.lastModified == nil && m.store.lastSaveError != nil)
    }

    // TV: REPO-003 timeout path — "Timed out writing {path}.", stamp restored
    @Test func confirmedSaveTimeout() throws {
        let (m, g) = made()
        m.store.confirmedSaveTimeout = 0.2
        m.store.writer.beforeEachJob = { _ in Thread.sleep(forTimeInterval: 0.6) }
        let before = NetDateTime(year: 2020, month: 1, day: 2, kind: .local)
        m.store.data.lastModified = before
        m.store.markDirty()
        let path = m.dataStore.currentDataFile.path
        #expect(throws: AppStoreError.timeout(path: path)) { try m.store.save() }
        #expect(AppStoreError.timeout(path: path).errorDescription == "Timed out writing \(path).")
        #expect(m.store.data.lastModified == before)
        #expect(m.store.isDirty)
        #expect(m.store.lastSaveError == "Timed out writing \(path).")
        m.store.writer.beforeEachJob = nil
        #expect(m.store.waitForQueuedWrites(timeout: 5))
        #expect(AppStore.saveTimeout == 15)
        _ = g
    }

    // TV: DATA-180 — a guard refusal fails the save with .pausedByGuard, restores the stamp, pauses writes
    @Test func guardRefusalPausesWrites() async throws {
        let (m, g) = made()
        try m.store.save()
        let onDisk = try Data(contentsOf: m.dataStore.currentDataFile)
        let stamp = m.store.data.lastModified
        g.allow = false
        m.store.data.tasks = [TaskItem(name: "mine")]
        m.store.markDirty()
        let previous = NetDateTime(year: 2020, month: 1, day: 2, kind: .local)
        m.store.data.lastModified = previous
        #expect(throws: AppStoreError.pausedByGuard) { try m.store.save() }
        #expect(m.store.data.lastModified == previous && m.store.isDirty)
        #expect(m.store.writesPaused && m.store.writePauseReason == .externalChange)
        #expect(try Data(contentsOf: m.dataStore.currentDataFile) == onDisk)
        // While paused: save() throws .writesPaused; the debounce never writes.
        #expect(throws: AppStoreError.writesPaused) { try m.store.save() }
        m.store.markDirty()
        m.store.backgroundSaveIfDirty()
        #expect(g.refusals == 1 && m.store.isDirty)
        // Resume: the pending edit is written by the debounce.
        g.allow = true
        m.store.debounceInterval = .milliseconds(50)
        m.store.resumeWrites()
        #expect(!m.store.writesPaused && m.store.writePauseReason == nil)
        #expect(await waitUntil(3) { !m.store.isDirty && g.writes.count == 2 })
        #expect(try fileObject(m)?["Tasks"]?.arrayValue?.count == 1)
        _ = stamp
    }

    // TV: DATA-180 — the same refusal on the background path pauses writes
    @Test func guardRefusalOnBackgroundSave() async throws {
        let (m, g) = made()
        g.allow = false
        m.store.markDirty()
        m.store.backgroundSaveIfDirty()
        #expect(await waitUntil(3) { m.store.writesPaused })
        #expect(m.store.isDirty && m.store.data.lastModified == nil && m.store.writePauseReason == .externalChange)
        #expect(m.store.lastSaveError == AppStoreError.pausedByGuard.errorDescription)
        m.store.pauseWrites(reason: .readOnly)                              // idempotent, reason updated
        #expect(m.store.writesPaused && m.store.writePauseReason == .readOnly)
    }

    // TV: REPO-005 — safe mode: markDirty and save do nothing
    @Test func suspendSaving() throws {
        let (m, g) = made()
        m.store.suspendSaving = true
        m.store.markDirty()
        #expect(!m.store.isDirty)
        try m.store.save()
        try m.store.flushIfDirty()
        #expect(g.writes.isEmpty && !FileManager.default.fileExists(atPath: m.dataStore.currentDataFile.path))
        #expect(m.store.data.lastModified == nil)
    }

    // TV: REPO-001 / REPO-006 — replaceData cancels the debounce, clears dirty, bumps generation, notifies
    @Test func replaceDataCancelsThePendingAutosave() async throws {
        let (m, g) = made()
        var reasons: [DataReplaceReason] = []
        let sub = m.store.dataReplaced.subscribe { reasons.append($0) }
        m.store.markDirty()
        let old = m.store.data
        let fresh = AppData(); fresh.tasks = [TaskItem(name: "theirs")]
        m.store.replaceData(fresh, reason: .reloadFromDisk)
        #expect(m.store.generation == 1 && !m.store.isDirty && m.store.data === fresh && m.store.data !== old)
        #expect(reasons == [.reloadFromDisk])
        try await Task.sleep(for: .milliseconds(1000))
        #expect(g.writes.isEmpty)
        m.store.replaceData(AppData(), reason: .other("x"))
        #expect(m.store.generation == 2 && reasons == [.reloadFromDisk, .other("x")])
        m.store.markDirty()
        m.store.cancelPendingAutosave()
        try await Task.sleep(for: .milliseconds(1000))
        #expect(g.writes.isEmpty && m.store.isDirty)
        sub.cancel()
    }

    // TV: REPO-003a — writes commit in enqueue order; a newer snapshot is never overwritten by an older one
    @Test func orderedWriteChain() throws {
        let (m, g) = made()
        m.store.writer.beforeEachJob = { job in
            // the first (older) job is slow; the later one must still land last
            if String(decoding: job.bytes, as: UTF8.self).contains("old") { Thread.sleep(forTimeInterval: 0.3) }
        }
        m.store.data.tasks = [TaskItem(name: "old")]
        m.store.markDirty()
        m.store.backgroundSaveIfDirty()                                     // queued, slow
        m.store.data.tasks = [TaskItem(name: "new")]
        try m.store.save()                                                  // waits behind it
        #expect(g.writes.count == 2)
        #expect(try fileObject(m)?["Tasks"]?.arrayValue?.first?.objectValue?["Name"]?.stringValue == "new")
        #expect(m.store.waitForQueuedWrites(timeout: 5))
    }

    // The writer captures the URL at enqueue time (02 D-9) and encrypts when local encryption is on
    @Test func encryptedAutosaveAndCapturedURL() async throws {
        let (m, g) = made()
        m.dataStore.settings.setEncryptLocalData(true)
        m.store.data.tasks = [TaskItem(name: "secret")]
        try m.store.save()
        let raw = try Data(contentsOf: m.dataStore.currentDataFile)
        #expect(raw.prefix(8) == LocalEncryption.macMagic)
        #expect(m.dataStore.load().tasks.first?.name == "secret")
        // URL captured at enqueue: switching the data file after the enqueue does not redirect the write.
        m.store.writer.beforeEachJob = { _ in Thread.sleep(forTimeInterval: 0.2) }
        m.store.markDirty()
        m.store.backgroundSaveIfDirty()
        let other = m.folder.file("other/data2.json")
        m.dataStore.setCurrentDataFile(other)
        #expect(m.store.waitForQueuedWrites(timeout: 5))
        #expect(!FileManager.default.fileExists(atPath: other.path))
        #expect(g.writes.count == 2)
    }

    // encodedSnapshot never stamps; save/markDirty keep detachedItemIDs etc. untouched
    @Test func encodedSnapshotDoesNotStamp() throws {
        let (m, g) = made()
        let bytes = try m.store.encodedSnapshot()
        #expect(String(decoding: bytes, as: UTF8.self) == Goldens.freshDB)
        #expect(m.store.data.lastModified == nil && g.writes.isEmpty)
        m.store.detachedItemIDs.insert(G(1))
        try m.store.save()
        #expect(m.store.detachedItemIDs == [G(1)])
    }

    // Error texts (AppStoreError.errorDescription)
    @Test func errorTexts() {
        #expect(AppStoreError.timeout(path: "/a/data.json").errorDescription == "Timed out writing /a/data.json.")
        #expect(AppStoreError.serialization("x").errorDescription == "x")
        #expect(AppStoreError.write("y").errorDescription == "y")
        #expect(AppStoreError.pausedByGuard.errorDescription?.isEmpty == false)
        #expect(AppStoreError.writesPaused.errorDescription?.isEmpty == false)
    }
}

@MainActor @Suite struct AppStoreObservationTests {
    // TV: ARCHITECTURE.md §3.9 — withObservationTracking fires for a BASE-class property changed on a SUBCLASS instance
    @Test func baseClassPropertyOnSubclass() {
        let task = TaskItem(name: "a")
        let fired = TestFlag()
        withObservationTracking { _ = task.name } onChange: { fired.set() }
        task.name = "b"
        #expect(fired.isSet)
        let tagsFired = TestFlag()
        let vessel = Vessel(name: "v")
        withObservationTracking { _ = vessel.tags } onChange: { tagsFired.set() }
        vessel.tags.append("x")
        #expect(tagsFired.isSet)
        let lockFired = TestFlag()
        withObservationTracking { _ = task.isLockProtected } onChange: { lockFired.set() }
        task.lockHash = "h"
        #expect(lockFired.isSet)
    }

    // Computed Status/IsComplete over observed storage (ARCHITECTURE.md §4.3)
    @Test func statusSyncIsObserved() {
        let task = TaskItem(name: "a")
        let fired = TestFlag()
        withObservationTracking { _ = task.isComplete } onChange: { fired.set() }
        task.status = .done
        #expect(fired.isSet && task.isComplete)
        let own = TestFlag()
        withObservationTracking { _ = task.subtasks } onChange: { own.set() }
        task.subtasks = [TaskItem(name: "s")]
        #expect(own.isSet)
    }

    // AppStore state is observable (dirty flag, generation)
    @Test func storeIsObservable() {
        let m = StoreFactory.make()
        let fired = TestFlag()
        withObservationTracking { _ = m.store.isDirty } onChange: { fired.set() }
        m.store.markDirty()
        #expect(fired.isSet)
        m.store.cancelPendingAutosave()
        let gen = TestFlag()
        withObservationTracking { _ = m.store.generation } onChange: { gen.set() }
        m.store.replaceData(AppData(), reason: .initialLoad)
        #expect(gen.isSet)
    }
}
