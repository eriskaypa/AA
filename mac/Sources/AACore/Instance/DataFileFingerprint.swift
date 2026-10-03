// Spec: 01 DATA-180 (outside changes to the active data file: pause, ask, keep both versions), DATA-181 (conflict
//       copies), §MP.3.4 (fingerprint dev/ino/size/mtime/SHA-256, checkBeforeWrite inside the writer), §MP.3.5 (write
//       gate `.externalConflict`), MP.7.5 X-1…X-11, DATA-177 (no write after another computer took the lease),
//       DATA-184 (an outside write is evidence of a Windows copy); ARCHITECTURE.md §5.2, §5.4, §6.6.
import Foundation
import CryptoKit
import Observation
import Darwin

public struct DataFileConflict: Sendable {
    public enum Kind: Sendable { case changed, deleted, unreadable(reason: String) }
    public var kind: Kind
    public var fileName: String
    public var ourTime: String
    public var theirTime: String
    public var theirBytes: Data?

    public init(kind: Kind, fileName: String, ourTime: String, theirTime: String, theirBytes: Data?) {
        self.kind = kind; self.fileName = fileName; self.ourTime = ourTime; self.theirTime = theirTime
        self.theirBytes = theirBytes
    }
}

/// "Review Changes…" is resolved inside the host (DATA-100 sheet → one of these).
public enum DataFileConflictChoice: Sendable { case keepMine, useTheirs, stopEditingHere }

/// Implemented by F3's AppEnvironment: presents the DATA-180 sheet on the main window and returns the choice.
@MainActor public protocol DataFileConflictHost: AnyObject {
    func presentConflict(_ c: DataFileConflict) async -> DataFileConflictChoice
}

/// One file's identity on disk (§MP.3.4).
public struct PersistFingerprint: Sendable, Equatable {
    public var absent: Bool
    public var dev: UInt64 = 0
    public var ino: UInt64 = 0
    public var size: Int64 = 0
    public var mtimeSec: Int = 0
    public var mtimeNsec: Int = 0
    public var sha256 = Data()

    public init(absent: Bool, dev: UInt64 = 0, ino: UInt64 = 0, size: Int64 = 0, mtimeSec: Int = 0, mtimeNsec: Int = 0,
                sha256: Data = Data()) {
        self.absent = absent; self.dev = dev; self.ino = ino; self.size = size; self.mtimeSec = mtimeSec
        self.mtimeNsec = mtimeNsec; self.sha256 = sha256
    }

    func sameMetadata(_ o: PersistFingerprint) -> Bool {
        dev == o.dev && ino == o.ino && size == o.size && mtimeSec == o.mtimeSec && mtimeNsec == o.mtimeNsec
    }

    /// `stat` of `path` (nil when it does not exist).
    static func probe(_ path: String) -> PersistFingerprint? {
        var st = Darwin.stat()
        guard stat(path, &st) == 0 else { return nil }
        return PersistFingerprint(absent: false, dev: UInt64(bitPattern: Int64(st.st_dev)), ino: UInt64(st.st_ino),
                                  size: Int64(st.st_size), mtimeSec: Int(st.st_mtimespec.tv_sec),
                                  mtimeNsec: Int(st.st_mtimespec.tv_nsec))
    }

    static func hash(_ d: Data) -> Data { Data(SHA256.hash(data: d)) }
}

/// What `checkBeforeWrite` found.
public enum PersistFingerprintVerdict: Sendable, Equatable {
    case ok, foreignDeleted, foreignChanged(Data)
}

/// Lock-protected fingerprint table (called on the writer queue and on the main actor).
public final class PersistFingerprintTable: @unchecked Sendable {
    private let lock = NSLock()
    private var known: [String: PersistFingerprint] = [:]

    public init() {}

    static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    /// After our own load (bytes read) or write (bytes renamed in).
    public func record(_ url: URL, bytes: Data) {
        let k = PersistFingerprintTable.key(url)
        var fp = PersistFingerprint.probe(k) ?? PersistFingerprint(absent: true)
        if !fp.absent { fp.sha256 = PersistFingerprint.hash(bytes) }
        lock.lock(); known[k] = fp; lock.unlock()
    }

    /// We saw no file (first run).
    public func recordAbsentIfUnknown(_ url: URL) {
        let k = PersistFingerprintTable.key(url)
        lock.lock(); defer { lock.unlock() }
        if known[k] == nil, PersistFingerprint.probe(k) == nil { known[k] = PersistFingerprint(absent: true) }
    }

    /// Accept whatever is on disk now as "ours" (Keep Mine / Use Theirs / Resume Editing).
    public func acceptCurrent(_ url: URL) {
        let k = PersistFingerprintTable.key(url)
        if var fp = PersistFingerprint.probe(k) {
            fp.sha256 = PersistFingerprint.hash((try? Data(contentsOf: URL(fileURLWithPath: k))) ?? Data())
            lock.lock(); known[k] = fp; lock.unlock()
        } else {
            lock.lock(); known[k] = PersistFingerprint(absent: true); lock.unlock()
        }
    }

    public func fingerprint(_ url: URL) -> PersistFingerprint? {
        lock.lock(); defer { lock.unlock() }
        return known[PersistFingerprintTable.key(url)]
    }

    /// §MP.3.4 `checkBeforeWrite`. A file this process never loaded or wrote is not guarded.
    public func check(_ url: URL) -> PersistFingerprintVerdict {
        let k = PersistFingerprintTable.key(url)
        lock.lock(); let known = self.known[k]; lock.unlock()
        guard let known else { return .ok }
        guard let st = PersistFingerprint.probe(k) else { return known.absent ? .ok : .foreignDeleted }
        let bytes: () -> Data = { (try? Data(contentsOf: URL(fileURLWithPath: k))) ?? Data() }
        if known.absent { return .foreignChanged(bytes()) }
        if st.sameMetadata(known) { return .ok }
        let b = bytes()
        if PersistFingerprint.hash(b) == known.sha256 {
            var updated = st
            updated.sha256 = known.sha256
            lock.lock(); self.known[k] = updated; lock.unlock()
            return .ok
        }
        return .foreignChanged(b)
    }
}

/// UI-facing state of the DATA-180 machinery (banners, write gate `.externalConflict`).
@MainActor @Observable public final class PersistConflictState {
    public enum Mode: Sendable, Equatable { case normal, stoppedEditing }
    public internal(set) var mode: Mode = .normal
    /// A conflict sheet is up (or its outcome is being applied).
    public internal(set) var isHandling = false
    /// DATA-184 evidence: an outside write to the active data file was seen in this session.
    public internal(set) var outsideWriteSeen = false
    public init() {}
}

/// Texts of the DATA-180 sheet, banner and statuses (exact where the spec quotes them).
public enum PersistConflictText {
    public static let title = "The data file was changed outside this copy of AA"
    public static let keepMine = "Keep Mine", useTheirs = "Use Theirs", review = "Review Changes…",
                      stopEditing = "Stop Editing Here", resumeEditing = "Resume Editing", conflictCopies = "Conflict Copies…"
    public static let noSaveDate = "(no save date)"
    public static let stoppedBanner = "Read-only — this data folder is being changed outside this copy of AA. Changes here are not saved."

    public static func message(_ c: DataFileConflict) -> String {
        switch c.kind {
        case .changed:
            return "“\(c.fileName)” was replaced by another program — another computer, a sync or backup tool, or AA on Windows — after this copy last saved it (\(c.ourTime)).\n\nTheir version was saved: \(c.theirTime)\n\nWhichever version you don't choose is kept as a copy in the data folder's “conflicts” folder."
        case .unreadable(let reason):
            return "“\(c.fileName)” was replaced by another program — another computer, a sync or backup tool, or AA on Windows — after this copy last saved it (\(c.ourTime)).\n\nTheir version can't be opened on this Mac (\(reason)), so it can't be reviewed. If you keep yours, theirs is kept as a copy in the data folder's “conflicts” folder."
        case .deleted:
            return "“\(c.fileName)” was deleted by another program — another computer, a sync or backup tool, or AA on Windows — after this copy last saved it (\(c.ourTime)).\n\nKeep Mine saves your version again. Stop Editing Here keeps this window open without saving."
        }
    }

    public static func keptMine(_ name: String) -> String { "Kept your version — the other version was saved to conflicts/\(name)." }
    public static let keptMineRecreated = "Kept your version — the data file was saved again."
    public static func usedTheirs(_ name: String) -> String { "Loaded the other version — yours was saved to conflicts/\(name)." }
    public static func reviewSource(_ fileName: String) -> String { "\(fileName) (changed outside AA)" }
    public static func updated(_ hms: String) -> String { "Updated from the other copy of AA (\(hms))." }
    public static let stoppedStatus = "Stopped editing here — changes in this window are not saved."
    public static let resumedStatus = "Editing resumed — the data file was re-read from disk."
}

/// DATA-180 implementation of F1's `DataFileWriteGuard` (nonisolated witnesses, lock-protected state).
@MainActor public final class DataFileFingerprint: DataFileWriteGuard {
    private let store: AppStore
    private weak var host: DataFileConflictHost?
    nonisolated public let table = PersistFingerprintTable()
    public let state = PersistConflictState()
    private var watcher: PersistDirectoryWatcher?

    /// Status line (set by the UI bridge; F3's `postStatus`).
    public var statusHandler: (@MainActor (String) -> Void)?
    /// "Revert to Saved" — reload the data from disk and show `status` (set by the UI bridge; falls back to a plain
    /// repository swap).
    public var reloadHandler: (@MainActor (_ status: String?) -> Void)?
    /// Re-applied after every reload while stopped (settings memory-only, §MP.3.5).
    public var onModeChange: (@MainActor (PersistConflictState.Mode) -> Void)?

    /// Debounce / poll of the watcher (tests shorten them).
    var watchDebounce: Duration = .milliseconds(1500)
    var watchPoll: Duration = .seconds(60)
    /// Poll even on local volumes (tests).
    var alwaysPoll = false

    public init(store: AppStore, host: DataFileConflictHost) {
        self.store = store; self.host = host
    }

    private var ds: DataStore { store.dataStore }

    // MARK: Lifecycle

    /// Records "no file" for a first run and starts the directory watcher on the active data file's folder.
    public func start() {
        table.recordAbsentIfUnknown(ds.currentDataFile)
        let dir = ds.currentDataFile.deletingLastPathComponent()
        if let w = watcher, w.isRunning, w.directory.standardizedFileURL == dir.standardizedFileURL { return }
        watcher?.stop()
        let network = PersistHost.isNetworkVolume(dir)
        let w = PersistDirectoryWatcher(directory: dir, debounce: watchDebounce,
                                        poll: (network || alwaysPoll) ? watchPoll : nil) { [weak self] in
            self?.watcherFired()
        }
        watcher = w
        w.start()
    }

    public func stop() {
        watcher?.stop()
        watcher = nil
    }

    /// Whether the watcher runs (tests, diagnostics).
    public var isWatching: Bool { watcher?.isRunning ?? false }

    // MARK: DataFileWriteGuard (writer queue)

    public nonisolated func shouldWrite(to url: URL) -> Bool {
        guard PersistLeaseGate.shared.mayWrite() else { return false }
        let verdict = table.check(url)
        if verdict == .ok { return true }
        Task { @MainActor [weak self] in await self?.detected(url, verdict) }
        return false
    }

    public nonisolated func didWrite(to url: URL, bytes: Data) { table.record(url, bytes: bytes) }

    public nonisolated func didLoad(from url: URL, bytes: Data) { table.record(url, bytes: bytes) }

    /// Before a deliberate replacement (bundle import, shared pull, Flash Sync apply, conflict restore): a foreign
    /// version on disk is kept as a "theirs" conflict copy so nothing is lost.
    public nonisolated func preserveForeignVersion(at url: URL, appFolder: URL, clock: AppClock) {
        if case .foreignChanged(let bytes) = table.check(url), !bytes.isEmpty {
            _ = try? PersistConflictStore.add(bytes, theirs: true, appFolder: appFolder, now: clock.instant(),
                                              zone: clock.timeZone)
        }
    }

    // MARK: Watcher (DATA-180 step 3)

    func watcherFired() {
        // Follow the active file when it moved to another folder (Import from file, bundle import).
        if let w = watcher, w.directory.standardizedFileURL != ds.currentDataFile.deletingLastPathComponent().standardizedFileURL {
            start()
        }
        checkNow()
    }

    /// Runs the same check as a write, on the writer queue, then reacts on the main actor.
    public func checkNow() {
        let url = ds.currentDataFile
        let table = self.table
        store.writer.runOnWriterQueue { [weak self] in
            let verdict = table.check(url)
            guard verdict != .ok else { return }
            Task { @MainActor [weak self] in await self?.detected(url, verdict) }
        }
    }

    /// Awaitable variant for tests: the verdict the watcher would act on.
    public func checkNowAndWait() async {
        let url = ds.currentDataFile
        let table = self.table
        let verdict: PersistFingerprintVerdict = await withCheckedContinuation { cont in
            store.writer.runOnWriterQueue { cont.resume(returning: table.check(url)) }
        }
        if verdict != .ok { await detected(url, verdict) }
    }

    // MARK: Reaction

    func detected(_ url: URL, _ verdict: PersistFingerprintVerdict) async {
        guard verdict != .ok, url.standardizedFileURL == ds.currentDataFile.standardizedFileURL else { return }
        state.outsideWriteSeen = true
        if state.mode == .stoppedEditing {
            // X-11: while stopped, outside changes reload silently (when readable).
            if case .foreignChanged(let bytes) = verdict, PersistConflictReading.unreadableReason(bytes, ds: ds) == nil {
                table.acceptCurrent(url)
                reload(status: PersistConflictText.updated(hms()))
                reapplyStopped()
            }
            return
        }
        guard !state.isHandling else { return }
        state.isHandling = true
        defer { state.isHandling = false }
        store.pauseWrites(reason: .externalChange)
        let conflict = makeConflict(url, verdict)
        guard let host else { return }
        let choice = await host.presentConflict(conflict)
        perform(choice, conflict: conflict, url: url)
    }

    func makeConflict(_ url: URL, _ verdict: PersistFingerprintVerdict) -> DataFileConflict {
        let ours = store.data.lastModified.map { $0.toLocalTime(zone: ds.clock.timeZone).format(.isoSecond) }
            ?? PersistConflictText.noSaveDate
        switch verdict {
        case .foreignDeleted, .ok:
            return DataFileConflict(kind: .deleted, fileName: url.lastPathComponent, ourTime: ours,
                                    theirTime: PersistConflictText.noSaveDate, theirBytes: nil)
        case .foreignChanged(let bytes):
            let theirs = PersistConflictReading.lastModified(bytes, ds: ds)
                .map { $0.toLocalTime(zone: ds.clock.timeZone).format(.isoSecond) } ?? PersistConflictText.noSaveDate
            if let why = PersistConflictReading.unreadableReason(bytes, ds: ds) {
                return DataFileConflict(kind: .unreadable(reason: why), fileName: url.lastPathComponent, ourTime: ours,
                                        theirTime: theirs, theirBytes: bytes)
            }
            return DataFileConflict(kind: .changed, fileName: url.lastPathComponent, ourTime: ours, theirTime: theirs,
                                    theirBytes: bytes)
        }
    }

    /// Carries out the user's choice (the table in DATA-180).
    public func perform(_ choice: DataFileConflictChoice, conflict c: DataFileConflict, url: URL) {
        switch choice {
        case .keepMine:
            var name: String?
            if let theirs = c.theirBytes {
                name = try? PersistConflictStore.add(theirs, theirs: true, appFolder: ds.appFolder,
                                                     now: ds.clock.instant(), zone: ds.clock.timeZone)
            }
            table.acceptCurrent(url)
            store.resumeWrites()
            do {
                try store.save()
                post(name.map(PersistConflictText.keptMine) ?? PersistConflictText.keptMineRecreated)
            } catch {
                post(error.localizedDescription)
            }
        case .useTheirs:
            guard case .changed = c.kind else { return }
            let name = (try? ConflictCopies.saveMine(store)) ?? ""
            table.acceptCurrent(url)
            reload(status: PersistConflictText.usedTheirs(name))
            store.resumeWrites()
        case .stopEditingHere:
            if case .changed = c.kind {
                _ = try? ConflictCopies.saveMine(store)
                table.acceptCurrent(url)
                reload(status: nil)
            }
            state.mode = .stoppedEditing
            reapplyStopped()
            post(PersistConflictText.stoppedStatus)
        }
    }

    /// "Resume Editing": re-read from disk, refresh the fingerprint, leave read-only mode.
    public func resumeEditing() {
        state.mode = .normal
        table.acceptCurrent(ds.currentDataFile)
        reload(status: PersistConflictText.resumedStatus)
        ds.settings.isWriteGated = false
        store.resumeWrites()
        onModeChange?(.normal)
    }

    private func reapplyStopped() {
        store.pauseWrites(reason: .readOnly)
        ds.settings.isWriteGated = true
        onModeChange?(.stoppedEditing)
    }

    private func reload(status: String?) {
        if let reloadHandler {
            reloadHandler(status)
        } else {
            ds.loadSettings()
            store.replaceData(ds.load(), reason: .reloadFromDisk)
            if let status { post(status) }
        }
    }

    private func post(_ s: String) { statusHandler?(s) }

    private func hms() -> String { ds.clock.now().format(.isoSecond).suffix(8).description }
}

/// Reading a foreign data file without adopting it.
enum PersistConflictReading {
    /// nil when the bytes are a readable AA data file on this Mac, else the reason shown in the sheet.
    @MainActor static func unreadableReason(_ bytes: Data, ds: DataStore) -> String? {
        switch LocalEncryption.classify(bytes) {
        case .windowsDPAPI: return "it was encrypted by AA on Windows"
        case .mac, .plain: break
        }
        let json: Data
        do {
            json = try DataStore.decodeFileBytes(bytes, key: try ds.keyForReading(bytes))
        } catch {
            return "it is encrypted with a key this Mac doesn't have"
        }
        guard let root = try? JSONParser.parse(json) else { return "it isn't valid JSON" }
        guard (try? ds.decode(root)) != nil else { return "it isn't an AA data file" }
        return nil
    }

    @MainActor static func lastModified(_ bytes: Data, ds: DataStore) -> NetDateTime? {
        let key: SymmetricKey? = (try? ds.keyForReading(bytes)) ?? nil
        guard let json = try? DataStore.decodeFileBytes(bytes, key: key) else { return nil }
        return BundleService.readLastModified(json)
    }

    /// The model inside foreign bytes (for "Review Changes…"); nil when unreadable.
    @MainActor static func appData(_ bytes: Data, ds: DataStore) -> AppData? {
        let key: SymmetricKey? = (try? ds.keyForReading(bytes)) ?? nil
        guard unreadableReason(bytes, ds: ds) == nil,
              let json = try? DataStore.decodeFileBytes(bytes, key: key),
              let root = try? JSONParser.parse(json) else { return nil }
        return try? ds.decode(root)
    }
}

extension DataFileFingerprint {
    /// The model inside a conflict's foreign bytes and its stamp (the "Review Changes…" preview).
    public func reviewData(_ c: DataFileConflict) -> (data: AppData, stamp: NetDateTime?)? {
        guard let b = c.theirBytes, let d = PersistConflictReading.appData(b, ds: ds) else { return nil }
        return (d, d.lastModified)
    }
}
