// Spec: 01 DATA-025 (750 ms debounce), DATA-031 (LastModified stamping), 02 REPO-001–008, REPO-003a,
//       03 SHELL-051, 01 DATA-180 (pause writes on an outside change); ARCHITECTURE.md §2.3, §2.4, §5.2.
import Foundation
import Observation
import CryptoKit

public enum DataReplaceReason: Sendable, Equatable {
    case initialLoad, reloadFromDisk, importFile, importBundle, sharedSavePull, driveImport, flashSyncApply, other(String)
}

public enum AppStoreError: Error, LocalizedError, Sendable, Equatable {
    case timeout(path: String)          // "Timed out writing {path}." (02 REPO-003)
    case serialization(String)          // incl. depth > 64 and Int32 overflow (§3.8 rule 2)
    case write(String)
    case pausedByGuard                  // the DataFileWriteGuard refused the write (01 DATA-180); nothing written
    case writesPaused                   // save() while pauseWrites is in effect

    public var errorDescription: String? {
        switch self {
        case .timeout(let path): return "Timed out writing \(path)."
        case .serialization(let s): return s
        case .write(let s): return s
        case .pausedByGuard: return "The data file was changed outside this copy of AA, so it was not overwritten."
        case .writesPaused: return "Saving is paused because the data file was changed outside this copy of AA."
        }
    }
}

public enum WritePauseReason: Sendable, Equatable { case externalChange, readOnly, other(String) }

/// The repository core: the single model root, dirty tracking, the debounced background save, the confirmed
/// synchronous save and the ordered writer (domain operations live in F2's `AppStore+*.swift`).
@MainActor @Observable
public final class AppStore {
    public let dataStore: DataStore
    public let clock: AppClock
    public private(set) var data: AppData
    /// +1 on every `replaceData`.
    public private(set) var generation: Int = 0
    public private(set) var isDirty: Bool = false
    /// Safe mode / read-only instance (02 REPO-005): `markDirty` and `save` do nothing.
    public var suspendSaving: Bool = false
    /// DATA-180 pause: debounce, save(), 5-min autosave, shared push and close-save all refuse to write.
    public private(set) var writesPaused: Bool = false
    public private(set) var writePauseReason: WritePauseReason?
    public private(set) var lastSaveError: String?
    /// Exposed so F3 can install `writer.writeGuard`.
    @ObservationIgnored public let writer = PersistenceWriter()
    /// Item windows open (04 §6.7, OC-42).
    public var detachedItemIDs: Set<UUID> = []
    public var debounceInterval: Duration = .milliseconds(750)
    public static let saveTimeout: TimeInterval = 15

    @ObservationIgnored public let saved = EventHub<Void>()                      // REPO-007
    @ObservationIgnored public let dataReplaced = EventHub<DataReplaceReason>()  // reload/import/apply notification
    @ObservationIgnored public let trashChanged = EventHub<Void>()               // router's pendingUndoCount refresh

    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    /// Confirmed-save timeout (tests shorten it).
    @ObservationIgnored var confirmedSaveTimeout: TimeInterval = AppStore.saveTimeout

    public init(dataStore: DataStore, data: AppData, clock: AppClock = SystemClock()) {
        self.dataStore = dataStore
        self.data = data
        self.clock = clock
    }

    // MARK: Pausing (DATA-180)

    /// Idempotent; the model stays dirty.
    public func pauseWrites(reason: WritePauseReason) {
        writesPaused = true
        writePauseReason = reason
    }

    /// After Keep Mine / Use Theirs / Resume Editing. Pending edits are scheduled again.
    public func resumeWrites() {
        writesPaused = false
        writePauseReason = nil
        if isDirty { scheduleDebouncedSave() }
    }

    // MARK: Debounced autosave (REPO-002, §2.3)

    public func markDirty() {
        guard !suspendSaving else { return }
        isDirty = true
        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        debounceTask?.cancel()
        let gen = generation
        let interval = debounceInterval
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: interval)
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            self.backgroundSaveIfDirty()
        }
    }

    /// Stamps, snapshots on the main actor and hands immutable bytes to the ordered writer.
    func backgroundSaveIfDirty() {
        guard !suspendSaving, !writesPaused, isDirty else { return }
        let prev = data.lastModified
        let stamp = clock.now()
        data.lastModified = stamp
        isDirty = false
        let bytes: Data
        let key: SymmetricKey?
        do throws(AppStoreError) {
            bytes = try dataStore.serializeForSave(data)
            key = try dataStore.encryptionKeyForWrite(dataStore.currentDataFile)
        } catch {
            data.lastModified = prev
            isDirty = true
            lastSaveError = error.localizedDescription
            return
        }
        let job = WriteJob(bytes: bytes, url: dataStore.currentDataFile, encryptionKey: key)
        let gen = generation
        writer.enqueue(job) { [weak self] result in
            let outcome = result.mapError { AppStore.mapWriteError($0) }
            Task { @MainActor [weak self] in
                self?.finishBackgroundSave(outcome, stamp: stamp, previous: prev, generation: gen)
            }
        }
    }

    private func finishBackgroundSave(_ result: Result<Void, AppStoreError>, stamp: NetDateTime,
                                      previous: NetDateTime?, generation gen: Int) {
        guard gen == generation else { return }                  // the graph was replaced; its writes just complete
        switch result {
        case .success:
            lastSaveError = nil
            saved.send(())
        case .failure(let e):
            if let current = data.lastModified, current.ticks == stamp.ticks, current.originalText == nil {
                data.lastModified = previous
            }
            isDirty = true
            lastSaveError = e.localizedDescription
            if e == .pausedByGuard { pauseWrites(reason: .externalChange) }
        }
    }

    // MARK: Confirmed save (REPO-003, REPO-008)

    /// Stamp, serialise on main, enqueue after every pending write, wait ≤ 15 s; restores the stamp on failure.
    /// Clears dirty and fires `saved` on success. Returns silently when `suspendSaving`; throws `.writesPaused`
    /// while paused. Always writes, even when not dirty.
    public func save() throws(AppStoreError) {
        if suspendSaving { return }
        if writesPaused { throw .writesPaused }
        debounceTask?.cancel()
        debounceTask = nil
        let prev = data.lastModified
        let stamp = clock.now()
        data.lastModified = stamp
        let bytes: Data
        let key: SymmetricKey?
        do throws(AppStoreError) {
            bytes = try dataStore.serializeForSave(data)
            key = try dataStore.encryptionKeyForWrite(dataStore.currentDataFile)
        } catch {
            data.lastModified = prev                                // dirty stays as it was
            lastSaveError = error.localizedDescription
            throw error
        }
        let url = dataStore.currentDataFile
        let box = SaveResultBox()
        let item = writer.enqueue(WriteJob(bytes: bytes, url: url, encryptionKey: key)) { result in
            box.set(result.mapError { AppStore.mapWriteError($0) })
        }
        guard box.wait(timeout: confirmedSaveTimeout) else {
            item.cancel()
            data.lastModified = prev
            let e = AppStoreError.timeout(path: url.path)
            lastSaveError = e.localizedDescription
            throw e
        }
        switch box.result ?? .failure(.write("The save did not complete.")) {
        case .success:
            isDirty = false
            lastSaveError = nil
            saved.send(())
        case .failure(let e):
            data.lastModified = prev
            lastSaveError = e.localizedDescription
            if e == .pausedByGuard { pauseWrites(reason: .externalChange) }
            throw e
        }
    }

    /// `Save()` only if dirty (REPO-008) — the "persist this toggle now" idiom is `markDirty(); flushIfDirty()`.
    public func flushIfDirty() throws(AppStoreError) {
        if isDirty { try save() }
    }

    // MARK: Replacement (REPO-001, REPO-006)

    /// Cancels the debounce, clears dirty, bumps `generation`, sends `dataReplaced`. Writes already queued still
    /// complete, but a stale timer can never write the discarded graph.
    public func replaceData(_ newData: AppData, reason: DataReplaceReason) {
        debounceTask?.cancel()
        debounceTask = nil
        isDirty = false
        lastSaveError = nil
        data = newData
        generation += 1
        dataReplaced.send(reason)
    }

    /// REPO-006 detach part (used before quit/reload).
    public func cancelPendingAutosave() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// Quit pipeline: waits for every queued write.
    public func waitForQueuedWrites(timeout: TimeInterval) -> Bool {
        writer.waitUntilIdle(timeout: timeout)
    }

    /// `serializeForSave` of the live model (no stamp).
    public func encodedSnapshot() throws(AppStoreError) -> Data {
        try dataStore.serializeForSave(data)
    }

    nonisolated static func mapWriteError(_ e: Error) -> AppStoreError {
        if let a = e as? AppStoreError { return a }
        return .write((e as? LocalizedError)?.errorDescription ?? e.localizedDescription)
    }
}

/// The confirmed save's rendezvous with the writer queue (lock-protected).
private final class SaveResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private let sema = DispatchSemaphore(value: 0)
    private var stored: Result<Void, AppStoreError>?

    var result: Result<Void, AppStoreError>? { lock.lock(); defer { lock.unlock() }; return stored }

    func set(_ r: Result<Void, AppStoreError>) {
        lock.lock(); stored = r; lock.unlock()
        sema.signal()
    }

    /// The only main-thread wait in the app (02 REPO-003); the writer never needs the main thread.
    func wait(timeout: TimeInterval) -> Bool { sema.wait(timeout: .now() + timeout) == .success }
}
