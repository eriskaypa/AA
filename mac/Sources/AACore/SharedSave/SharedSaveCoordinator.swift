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
        do {
            host?.flushAllEditors()
            host?.captureUiState()
            try store.save()
            plan = try BundleService.exportPlan(ds, to: tmp, includeAttachments: !ds.settings.values.textOnlyExport)
        } catch {
            pushFinished(label: label, error: error, tmp: tmp)
            return
        }
        Task { @MainActor [weak self] in
            let failure: Error? = await Task.detached(priority: .utility) { () -> Error? in
                do { try plan.write(); return nil } catch { return error }
            }.value
            guard let self else { return }
            if let failure {
                self.pushFinished(label: label, error: failure, tmp: tmp)
                return
            }
            do {
                try PersistFileCoordination.replace(target, with: tmp)
                self.pushFinished(label: label, error: nil, tmp: tmp)
            } catch {
                self.pushFinished(label: label, error: error, tmp: tmp)
            }
        }
    }

    /// Synchronous push (menu / on close, SHELL-126). The status line and the indicator are updated either way;
    /// the error is rethrown for callers that need it (the Windows flows ignore it: `try?`).
    public func push(label: String) throws {
        guard let path else { return }
        let target = URL(fileURLWithPath: path)
        let tmp = URL(fileURLWithPath: path + "." + UUID().netN + ".tmp")
        do {
            host?.flushAllEditors()
            host?.captureUiState()
            try store.save()
            try BundleService.exportFolderToZipSync(ds, to: tmp, includeAttachments: !ds.settings.values.textOnlyExport)
            try PersistFileCoordination.replace(target, with: tmp)
            pushFinished(label: label, error: nil, tmp: tmp, background: false)
        } catch {
            pushFinished(label: label, error: error, tmp: tmp, background: false)
            throw error
        }
    }

    private func pushFinished(label: String, error: Error?, tmp: URL, background: Bool = true) {
        try? FileManager.default.removeItem(at: tmp)
        if background { isPushRunning = false }
        if let error {
            host?.postStatus(PersistSharedText.failed(label, error.localizedDescription))
            setPushFailed()
        } else {
            lastSeen = store.data.lastModified
            lastSynced = store.data.lastModified
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
        let newer = local.map { fileStamp > $0 } ?? true
        guard newer else { setOnline(false); return }
        if let seen = lastSeen, fileStamp == seen { setOnline(false); return }
        isHandlingUpdate = true
        defer { isHandlingUpdate = false }
        host?.flushAllEditors()
        // D-12: an unreadable local file (safe mode) is never replaced without asking.
        let unsynced = hasUnsyncedChanges || ds.lastLoadFailed
        if unsynced {
            let reload = await host?.confirmReloadDiscardingChanges() ?? false
            if !reload {
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
            setOnline(true)
        } catch {
            host?.postStatus(PersistSharedText.skipped(error.localizedDescription))
        }
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
        if closePushAllowed(bundleStamp: fileStamp) {
            try? push(label: PersistSharedText.onCloseLabel)
        } else {
            _ = try? ConflictCopies.saveMine(store)
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

    /// Persists `url` as the shared file; `useItsContents` (and the file exists) → import it (data + attachments),
    /// reload and mark in sync; otherwise push our data over it (creating it). Then starts sync. On failure the
    /// setting is cleared and the error rethrown.
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
            start()
        } catch {
            stop()
            ds.settings.setSharedSaveFile(nil)
            updateHealth()
            throw error
        }
    }

    /// Stops the timers and watcher, clears the setting and hides the indicator.
    public func stopUsing() {
        stop()
        ds.settings.setSharedSaveFile(nil)
        lastSyncOk = nil
        updateHealth()
    }
}
