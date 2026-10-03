// Spec: 01 §E (DATA-052…058), §3.12 (shared-save machinery), §6.9 (directory watcher, 60 s poll, Task timers,
//       off-main ZIP + rename, prompt buttons), §7.13 (decision tables), DATA-185 (NSFileCoordinator; expected push
//       failures on SMB), D-1 (push when unsynced, not only when dirty), D-2 (close push compares with the last sync),
//       D-12 (safe mode never pulls silently; the unreadable file is kept); 03 SHELL-023 (indicator texts),
//       SHELL-123…126, §3.9, §7.2; ARCHITECTURE.md §5.4, §6.6.
import Foundation
import Observation

/// Implemented by F3's AppEnvironment.
@MainActor public protocol SharedSaveHost: AnyObject {
    func flushAllEditors()
    func captureUiState()
    /// D27: "Reload (Discard My Changes)" / "Keep Mine".
    func confirmReloadDiscardingChanges() async -> Bool
    /// LoadDataAndInitUi + status "Reloaded the shared save…".
    func reloadAfterSharedImport(identity: String?)
    func postStatus(_ text: String)
}

/// Exact texts of the shared-save machinery (SHELL-023, DATA-052…056).
public enum PersistSharedText {
    public static let tooltip = "Shared save status. Turns red and stays visible if the shared file goes offline (e.g. a VSAT drop) so you know your edits aren't reaching it yet."
    public static func offline(_ hhmm: String) -> String { "⚠ Shared save OFFLINE since \(hhmm) — retrying" }
    public static func notSaving(_ hhmm: String) -> String { "⚠ Shared save NOT SAVING since \(hhmm) — last write failed" }
    public static func synced(_ hhmm: String) -> String { "🔗 Shared synced \(hhmm)" }
    public static let on = "🔗 Shared save on"
    public static func written(_ label: String, _ hms: String) -> String { "\(label) written \(hms) (data + attachments)." }
    public static func failed(_ label: String, _ message: String) -> String { "\(label) failed: \(message)" }
    public static func reloaded(identity: String?, _ hms: String) -> String {
        let who = identity.flatMap { NetText.isBlank($0) ? nil : " from “\($0)”" } ?? ""
        return "Reloaded the shared save\(who) (\(hms))."
    }
    public static func skipped(_ message: String) -> String { "Shared reload skipped (busy): \(message)" }
    public static let periodicLabel = "Shared save"
    public static let onCloseLabel = "Shared save (on close)"
}

@MainActor @Observable public final class SharedSaveCoordinator {
    nonisolated public enum Health: Sendable, Equatable {
        case off, online(lastSync: Date?), offline(since: Date), notSaving(since: Date)
    }

    @ObservationIgnored private let store: AppStore
    @ObservationIgnored public weak var host: SharedSaveHost?
    public private(set) var health: Health = .off
    /// The bundle stamp already handled or declined.
    public private(set) var lastSeen: NetDateTime?
    /// The data stamp last pushed or pulled.
    public private(set) var lastSynced: NetDateTime?

    // Indicator flags (§3.12).
    @ObservationIgnored private var offline = false
    @ObservationIgnored private var pushFailed = false
    @ObservationIgnored private var troubleSince: Date?
    @ObservationIgnored private var lastSyncOk: Date?
    /// Re-entrancy guard of the pull, and the overlap guard of the background push.
    public private(set) var isHandlingUpdate = false
    public private(set) var isPushRunning = false
    @ObservationIgnored private var stampsInitialized = false
    /// V2-J6: a close-time push this copy refused (D-2) and has not resolved yet — loaded from the data folder at the
    /// first start. While set, no push runs and the next readable bundle is always asked about (never pulled silently).
    public private(set) var pendingClose: SharedSavePendingClose?

    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: PersistDirectoryWatcher?

    /// Cadences (DATA-052/053; tests shorten them).
    @ObservationIgnored var pushInterval: Duration = .seconds(60)
    @ObservationIgnored var pollInterval: Duration = .seconds(60)
    @ObservationIgnored var debounce: Duration = .milliseconds(1500)

    public init(store: AppStore) {
        self.store = store
    }

    private var ds: DataStore { store.dataStore }
    private var clock: AppClock { store.clock }

    /// The configured shared save file (nil when none).
    public var path: String? {
        guard let p = ds.settings.values.sharedSaveFile, !NetText.isBlank(p) else { return nil }
        return p
    }

    // MARK: Indicator (SHELL-023)

    /// SHELL-023 exact texts ("" when no shared file is set).
    public var indicatorText: String {
        switch health {
        case .off: return ""
        case .offline(let since): return PersistSharedText.offline(hhmm(since))
        case .notSaving(let since): return PersistSharedText.notSaving(hhmm(since))
        case .online(let last): return last.map { PersistSharedText.synced(hhmm($0)) } ?? PersistSharedText.on
        }
    }

    public var indicatorHelp: String { health == .off ? "" : PersistSharedText.tooltip }

    private func hhmm(_ d: Date) -> String { NetDateTime(date: d, kind: .local, zone: clock.timeZone).format(.time, zone: clock.timeZone) }
    private func hms() -> String { NetDateTime(date: clock.instant(), kind: .local, zone: clock.timeZone).format(.isoSecond).suffix(8).description }

    private func updateHealth() {
        guard path != nil else {
            offline = false; pushFailed = false; troubleSince = nil
            health = .off
            return
        }
        let now = clock.instant()
        if offline { health = .offline(since: troubleSince ?? now) }          // offline text wins
        else if pushFailed { health = .notSaving(since: troubleSince ?? now) }
        else { health = .online(lastSync: lastSyncOk) }
    }

    private func setOnline(_ synced: Bool) {
        offline = false
        if synced { pushFailed = false; troubleSince = nil; lastSyncOk = clock.instant() }
        updateHealth()
    }

    private func setOffline() {
        if !offline && !pushFailed { troubleSince = clock.instant() }
        offline = true
        updateHealth()
    }

    private func setPushFailed() {
        if !offline && !pushFailed { troubleSince = clock.instant() }
        pushFailed = true
        updateHealth()
    }

    // MARK: Start / stop (SHELL-123, DATA-057)

    /// Stops any previous sync; with a shared file set: 1-min push timer, 60-s poll, directory watcher with a
    /// 1.5-s debounce, indicator. The first start of a session treats the loaded data as in sync (DATA-057).
    public func start() {
        stop()
        guard let path else { updateHealth(); return }
        if !stampsInitialized {
            lastSeen = store.data.lastModified
            lastSynced = store.data.lastModified
            stampsInitialized = true
            // V2-J6: the previous session refused its close push because another copy had pushed. The close-save
            // stamped our data newer than that bundle, so DATA-057's "loaded data is in sync" would let the next push
            // overwrite the other copy's edit: restore the pre-close sync stamp and ask on the first check instead.
            if let pending = SharedSavePendingClose.load(ds.appFolder), pending.matches(path) {
                pendingClose = pending
                lastSeen = nil
                lastSynced = pending.lastSynced
            } else {
                SharedSavePendingClose.remove(ds.appFolder)
            }
        }
        let pushEvery = pushInterval, pollEvery = pollInterval
        pushTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pushEvery)
                guard !Task.isCancelled, let self else { return }
                await self.tick()
            }
        }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollEvery)
                guard !Task.isCancelled, let self else { return }
                await self.checkForUpdate()
            }
        }
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        let w = PersistDirectoryWatcher(directory: dir, debounce: debounce, poll: nil) { [weak self] in
            Task { @MainActor [weak self] in await self?.checkForUpdate() }
        }
        watcher = w
        w.start()
        updateHealth()
    }

    public func stop() {
        pushTask?.cancel(); pushTask = nil
        pollTask?.cancel(); pollTask = nil
        watcher?.stop(); watcher = nil
        if path == nil { updateHealth() }
    }

    /// Whether the timers run (tests, diagnostics).
    public var isRunning: Bool { pushTask != nil }

    // MARK: Periodic push (DATA-052, SHELL-124, D-1)

    /// One tick: adopt a newer bundle first, flush, then push in the background when this copy has unsynced data.
    public func tick() async {
        guard path != nil, !isHandlingUpdate else { return }
        await checkForUpdate()
        host?.flushAllEditors()
        guard pendingClose == nil else { return }                  // V2-J6: never push over an unresolved conflict
        guard hasUnsyncedChanges else { return }
        pushInBackground(label: PersistSharedText.periodicLabel)
    }

    /// `IsDirty || LastModified > lastSynced` (D-1: the predicate the pull side uses).
    public var hasUnsyncedChanges: Bool {
        if store.isDirty { return true }
        guard let local = store.data.lastModified else { return false }
        guard let synced = lastSynced else { return true }
        return local > synced
    }

    /// Background variant: flush, capture, save on the main actor, ZIP off-main into `{path}.{32hex}.tmp`, then an
    /// atomic coordinated rename over the bundle. A running guard prevents overlapping pushes.
    public func pushInBackground(label: String) {
        guard let path, !isPushRunning else { return }
        isPushRunning = true
        let target = URL(fileURLWithPath: path)
        let tmp = URL(fileURLWithPath: path + "." + UUID().netN + ".tmp")
        let plan: PersistExportPlan
        let pushedStamp: NetDateTime?
        do {
            host?.flushAllEditors()
            host?.captureUiState()
            try store.save()
            // The stamp the bundle's data.json carries. An autosave while the ZIP is written advances
            // `store.data.lastModified`; that newer edit is not in this bundle and must stay unsynced.
            pushedStamp = store.data.lastModified
            plan = try BundleService.exportPlan(ds, to: tmp, includeAttachments: !ds.settings.values.textOnlyExport)
        } catch {
            pushFinished(label: label, error: error, tmp: tmp, pushedStamp: nil)
            return
        }
        Task { @MainActor [weak self] in
            let failure: Error? = await Task.detached(priority: .utility) { () -> Error? in
                do { try plan.write(); return nil } catch { return error }
            }.value
            guard let self else { return }
            if let failure {
                self.pushFinished(label: label, error: failure, tmp: tmp, pushedStamp: pushedStamp)
                return
            }
            do {
                try PersistFileCoordination.replace(target, with: tmp)
                self.pushFinished(label: label, error: nil, tmp: tmp, pushedStamp: pushedStamp)
            } catch {
                self.pushFinished(label: label, error: error, tmp: tmp, pushedStamp: pushedStamp)
            }
        }
    }

    /// Synchronous push (menu / on close, SHELL-126). The status line and the indicator are updated either way;
    /// the error is rethrown for callers that need it (the Windows flows ignore it: `try?`).
    public func push(label: String) throws {
        guard let path else { return }
        let target = URL(fileURLWithPath: path)
        let tmp = URL(fileURLWithPath: path + "." + UUID().netN + ".tmp")
        var pushedStamp: NetDateTime?
        do {
            host?.flushAllEditors()
            host?.captureUiState()
            try store.save()
            pushedStamp = store.data.lastModified
            try BundleService.exportFolderToZipSync(ds, to: tmp, includeAttachments: !ds.settings.values.textOnlyExport)
            try PersistFileCoordination.replace(target, with: tmp)
            pushFinished(label: label, error: nil, tmp: tmp, pushedStamp: pushedStamp, background: false)
        } catch {
            pushFinished(label: label, error: error, tmp: tmp, pushedStamp: pushedStamp, background: false)
            throw error
        }
    }

    /// On success both stamps become `pushedStamp` — the `LastModified` the pushed data.json carries, captured right
    /// after the save that fed the bundle — never the stamp current when the ZIP finished (Deviations W-PERSIST-21).
    private func pushFinished(label: String, error: Error?, tmp: URL, pushedStamp: NetDateTime?, background: Bool = true) {
        try? FileManager.default.removeItem(at: tmp)
        if background { isPushRunning = false }
        if let error {
            host?.postStatus(PersistSharedText.failed(label, error.localizedDescription))
            setPushFailed()
        } else {
            lastSeen = pushedStamp
            lastSynced = pushedStamp
            stampsInitialized = true
            host?.postStatus(PersistSharedText.written(label, hms()))
            setOnline(true)
        }
    }

    // MARK: Pull (DATA-053/054, SHELL-125, §7.13)

    public func checkForUpdate() async {
        guard let path, !isHandlingUpdate else { return }
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard !dir.path.isEmpty, FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            setOffline(); return
        }
        guard FileManager.default.fileExists(atPath: url.path) else { setOnline(false); return }
        guard let fileStamp = BundleService.peekZipLastModified(url) else { return }   // unreadable / mid-write
        let local = store.data.lastModified
        // V2-J6: after a refused close push our local stamp is newer than the other copy's bundle, yet that bundle
        // holds an edit we never loaded — a pending close conflict is always asked about.
        let pending = pendingClose != nil
        let newer = pending || (local.map { fileStamp > $0 } ?? true)
        guard newer else { setOnline(false); return }
        if !pending, let seen = lastSeen, fileStamp == seen { setOnline(false); return }
        isHandlingUpdate = true
        defer { isHandlingUpdate = false }
        host?.flushAllEditors()
        // D-12: an unreadable local file (safe mode) is never replaced without asking.
        let unsynced = pending || hasUnsyncedChanges || ds.lastLoadFailed
        if unsynced {
            let reload = await host?.confirmReloadDiscardingChanges() ?? false
            if !reload {
                // Keep Mine: our next push replaces the bundle, so the other copy's data is kept as a `-theirs`
                // conflict copy first (DATA-181: neither side is lost).
                if pending { keepTheirsCopy(url); resolvePendingClose() }
                lastSeen = fileStamp
                setOnline(false)
                return
            }
        }
        let who = BundleService.peekBundleIdentity(url)
        do {
            if ds.lastLoadFailed { try preserveUnreadableLocalFile() }
            try BundleService.importSharedBundle(ds, from: url)
            if let host {
                host.reloadAfterSharedImport(identity: who)
            } else {
                ds.loadSettings()
                store.replaceData(ds.load(), reason: .sharedSavePull)
            }
            lastSeen = store.data.lastModified
            lastSynced = store.data.lastModified
            stampsInitialized = true
            resolvePendingClose()
            setOnline(true)
        } catch {
            host?.postStatus(PersistSharedText.skipped(error.localizedDescription))
        }
    }

    private func resolvePendingClose() {
        guard pendingClose != nil else { return }
        pendingClose = nil
        SharedSavePendingClose.remove(ds.appFolder)
    }

    /// The bundle's `data.json` bytes as a `-theirs` conflict copy (encrypted like `-mine` when local encryption is
    /// on). Best effort: a failure leaves the choice as made.
    private func keepTheirsCopy(_ url: URL) {
        let bytes: Data? = PersistFileCoordination.read(url) { u in
            guard let r = try? ZipReader(url: u), let e = r.entry(named: "data.json"),
                  let d = try? r.data(for: e) else { return nil }
            return PersistBundleIO.stripBOM(d)
        } ?? nil
        guard let bytes else { return }
        let folder = PersistConflictStore.folder(ds.appFolder)
        let key = ds.localEncryptionKeyIfEnabled(for: folder.appending(path: "x.json"))
        guard let payload = try? key.map({ try LocalEncryption.encrypt(bytes, key: $0) }) ?? bytes else { return }
        _ = try? PersistConflictStore.add(payload, theirs: true, appFolder: ds.appFolder, now: clock.instant(),
                                          zone: clock.timeZone)
    }

    /// D-12: copies the unreadable data file to `data.unreadable-{yyyyMMdd-HHmmss}.json` before a pull replaces it.
    private func preserveUnreadableLocalFile() throws {
        let src = ds.currentDataFile
        guard FileManager.default.fileExists(atPath: src.path) else { return }
        let stamp = NetDateTime(date: clock.instant(), kind: .local, zone: clock.timeZone).format(.stampSecond)
        let dest = ds.appFolder.appending(path: "data.unreadable-\(stamp).json")
        if FileManager.default.fileExists(atPath: dest.path) { return }
        try FileManager.default.copyItem(at: src, to: dest)
    }

    // MARK: On close (DATA-055, D-2)

    /// After the close-save: push when the bundle does not exist, or when its stamp is readable and the bundle has
    /// not changed since this copy last synced with it (our own push, a stamp we declined, or one not newer than our
    /// last sync). A bundle written by another copy since then is not overwritten; our data is kept as a `-mine`
    /// conflict copy instead (DATA-181) so neither side is lost. An unreadable bundle is never overwritten.
    public func pushOnCloseIfNeeded() {
        guard let path else { return }
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? push(label: PersistSharedText.onCloseLabel)
            return
        }
        guard let fileStamp = BundleService.peekZipLastModified(url) else { return }
        if pendingClose == nil, closePushAllowed(bundleStamp: fileStamp) {
            try? push(label: PersistSharedText.onCloseLabel)
        } else {
            _ = try? ConflictCopies.saveMine(store)
            // V2-J6: remember the refusal, so the next launch asks about the other copy's bundle instead of treating
            // our (now newer) close-save as in sync and pushing over it. The pre-close sync stamp is kept.
            let synced = pendingClose?.lastSynced ?? lastSynced
            SharedSavePendingClose(sharedSaveFile: path, lastSynced: synced, bundleStamp: fileStamp).save(ds.appFolder)
        }
    }

    /// The D-2 decision (exposed for tests).
    public func closePushAllowed(bundleStamp b: NetDateTime) -> Bool {
        if let seen = lastSeen, b == seen { return true }
        if let synced = lastSynced { return b <= synced }
        guard let local = store.data.lastModified else { return true }
        return local >= b
    }

    // MARK: Adopt / stop (DATA-050/051 outcomes; the menu flows are W-SHELL's)

    /// The D28 outcomes (ARCH §6.6 as amended post-wave, REQ-W-SHELL-01). Refused while the data folder is
    /// write-gated (DATA-174). Persists `url` as `SharedSaveFile`; `useItsContents` and the file exists →
    /// `ImportSharedBundle` (data + attachments), `host.reloadAfterSharedImport(identity:)` (so `store.generation`
    /// changes) and both stamps = the loaded `LastModified`; otherwise pushes our data over it synchronously
    /// (creating it; a failed push is reported by the indicator, not thrown). Then **starts** the sync — callers do
    /// not call `start()`. On failure it stops, clears the setting and rethrows.
    public func adoptSharedFile(_ url: URL, useItsContents: Bool) async throws {
        try PersistWriteGate.check(ds)                                              // DATA-174, §MP.3.5
        host?.flushAllEditors()
        let p = url.standardizedFileURL.path
        ds.settings.setSharedSaveFile(p)
        do {
            if useItsContents, FileManager.default.fileExists(atPath: p) {
                let who = BundleService.peekBundleIdentity(url)
                try BundleService.importSharedBundle(ds, from: url)
                if let host {
                    host.reloadAfterSharedImport(identity: who)
                } else {
                    ds.loadSettings()
                    store.replaceData(ds.load(), reason: .sharedSavePull)
                }
                // Windows sets both stamps but leaves the indicator flags alone: the indicator then reads
                // "Shared save on" until the first push or pull of the running sync (MenuSetSharedFile_Click).
                lastSeen = store.data.lastModified
                lastSynced = store.data.lastModified
                stampsInitialized = true
            } else {
                stampsInitialized = true
                try? push(label: PersistSharedText.periodicLabel)
            }
            resolvePendingClose()
            SharedSavePendingClose.remove(ds.appFolder)               // a new choice of file supersedes a refusal
            start()
        } catch {
            stop()
            ds.settings.setSharedSaveFile(nil)
            updateHealth()
            throw error
        }
    }

    /// Stops the timers and watcher, clears `SharedSaveFile` and hides the indicator (callers clear nothing).
    public func stopUsing() {
        stop()
        resolvePendingClose()
        SharedSavePendingClose.remove(ds.appFolder)
        ds.settings.setSharedSaveFile(nil)
        lastSyncOk = nil
        updateHealth()
    }
}

/// V2-J6: the record of a refused close push (D-2), kept in the data folder's `conflicts` folder — never exported in a
/// bundle, never listed as a conflict copy (`PersistConflictStore.parse` ignores it). Mac-only file.
public struct SharedSavePendingClose: Codable, Equatable, Sendable {
    public var sharedSaveFile: String
    /// Our last sync before the close (nil when this copy never synced).
    public var lastSyncedTicks: Int64?
    public var lastSyncedKind: UInt8?
    /// The other copy's bundle `LastModified` the close refused to overwrite.
    public var bundleTicks: Int64

    public static let fileName = "shared-pending.json"

    public init(sharedSaveFile: String, lastSynced: NetDateTime?, bundleStamp: NetDateTime) {
        self.sharedSaveFile = sharedSaveFile
        lastSyncedTicks = lastSynced?.ticks
        lastSyncedKind = lastSynced?.kind.rawValue
        bundleTicks = bundleStamp.ticks
    }

    public var lastSynced: NetDateTime? {
        lastSyncedTicks.map { NetDateTime(ticks: $0, kind: NetDateTime.Kind(rawValue: lastSyncedKind ?? 0) ?? .unspecified) }
    }

    public func matches(_ path: String?) -> Bool {
        guard let path else { return false }
        return URL(fileURLWithPath: path).standardizedFileURL.path
            == URL(fileURLWithPath: sharedSaveFile).standardizedFileURL.path
    }

    public static func url(_ appFolder: URL) -> URL { PersistConflictStore.folder(appFolder).appending(path: fileName) }

    public static func load(_ appFolder: URL) -> SharedSavePendingClose? {
        guard let d = try? Data(contentsOf: url(appFolder)) else { return nil }
        return try? JSONDecoder().decode(SharedSavePendingClose.self, from: d)
    }

    public func save(_ appFolder: URL) {
        let u = Self.url(appFolder)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(self) { try? d.write(to: u, options: .atomic) }
    }

    public static func remove(_ appFolder: URL) { try? FileManager.default.removeItem(at: url(appFolder)) }
}
