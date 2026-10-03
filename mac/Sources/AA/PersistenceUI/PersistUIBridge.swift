// Spec: 01 DATA-174 (read-only instance: live view, upgrade poll, banner actions), DATA-175 (Edit Here / Stay
//       Read-Only and everything a new editor starts), DATA-177 (lease lost after wake), DATA-180 (the guard's watcher,
//       reload and status hooks), DATA-181 (conflict-copies availability for File ▸ Recover Conflict Copies…), DATA-184
//       (shared-with-Windows evidence banner); ARCHITECTURE.md §6.6, §7.7. The UI-side wiring of W-PERSIST's AACore
//       machinery to F3's AppEnvironment (REQ-W-PERSIST-01: attached by F3's LaunchCoordinator after the first load;
//       F3 stops the watcher on quit).
import AppKit
import SwiftUI
import AACore

@MainActor @Observable final class PersistUIBridge {
    static let shared = PersistUIBridge()

    @ObservationIgnored private(set) weak var env: AppEnvironment?
    private(set) var readOnlySession: PersistReadOnlySession?
    /// Static DATA-184 evidence found at attach time (files and settings).
    private(set) var windowsEvidenceAtAttach = false
    private(set) var windowsWarningDismissed = false
    @ObservationIgnored private var contentBaseline: String?
    @ObservationIgnored private var subscriptions: [EventSubscription] = []
    @ObservationIgnored private var presentingSaveSheet = false

    // MARK: Attach (once per environment)

    func attach(_ env: AppEnvironment) {
        guard self.env !== env else { return }
        self.env = env
        subscriptions.removeAll()
        if let fp = env.dataFileGuard {
            fp.statusHandler = { [weak self] text in
                self?.env?.status.post(text)
                self?.refreshConflictCopies()
            }
            fp.reloadHandler = { [weak self] status in
                guard let env = self?.env else { return }
                env.loadDataAndInitUI(reason: .reloadFromDisk, status: status)
                self?.refreshConflictCopies()
            }
            fp.onModeChange = { [weak self] mode in self?.editingModeChanged(mode) }
            if !env.isReadOnlyInstance, !env.isSafeMode { fp.start() }
        }
        InstanceGuard.onLeaseLost = { [weak self] host in self?.leaseLost(host: host) }
        subscriptions.append(env.store.dataReplaced.subscribe { [weak self] _ in
            self?.rememberContent()
            self?.followActiveFile()
        })
        rememberContent()
        windowsEvidenceAtAttach = PersistWindowsEvidence.detect(appFolder: env.dataStore.appFolder,
                                                                settings: env.settings.values,
                                                                foreignTempAtLaunch: InstanceGuard.foreignTempFileAtLaunch,
                                                                outsideWriteSeen: false)
        windowsWarningDismissed = MacPreferences.shared.bool(PersistWindowsEvidence.warnedKey(env.dataStore.appFolder),
                                                             default: false)
        if env.isReadOnlyInstance { startReadOnly() }
        refreshConflictCopies()
    }

    /// DATA-180 step 3 after every reload: the data-file watcher runs for an editor that is not in safe mode, on the
    /// folder of the CURRENT active file (Import from file can move it; leaving safe mode starts it).
    private func followActiveFile() {
        guard let env, let fp = env.dataFileGuard, !env.isReadOnlyInstance, !env.dataStore.lastLoadFailed,
              fp.state.mode == .normal else { return }
        fp.start()
    }

    /// DATA-180 "Stop Editing Here" applies the DATA-174 list (§MP.3.5): the shared-save sync and the 5-minute autosave
    /// stop while editing is stopped (each would only report "Saving is paused…") and start again on "Resume Editing".
    private func editingModeChanged(_ mode: PersistConflictState.Mode) {
        guard let env else { return }
        switch mode {
        case .stoppedEditing:
            env.sharedSave.stop()
            env.stopAutosaveTimer()
        case .normal:
            if !env.isReadOnlyInstance, !env.isSafeMode {
                env.startAutosaveTimer()
                env.sharedSave.start()
            }
        }
        refreshConflictCopies()
    }

    /// File ▸ Recover Conflict Copies… is enabled when copies exist (DECISIONS R-70).
    func refreshConflictCopies() {
        guard let env else { return }
        env.router.conflictCopiesExist = !ConflictCopies.list(env.dataStore).isEmpty
    }

    // MARK: DATA-184 banner

    var showsWindowsWarning: Bool {
        guard let env, !windowsWarningDismissed else { return false }
        return windowsEvidenceAtAttach || (env.dataFileGuard?.state.outsideWriteSeen ?? false)
    }

    func dismissWindowsWarning() {
        guard let env else { return }
        PersistWindowsEvidence.dismiss(appFolder: env.dataStore.appFolder)
        withAnimation(.snappy) { windowsWarningDismissed = true }
    }

    func showSharedSaveHelp() {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") != nil {
            NSHelpManager.shared.openHelpAnchor(PersistWindowsEvidence.helpAnchor, inBook: nil)
            return
        }
        guard let env else { return }
        Task { @MainActor in
            await env.mainDialogs.info("Connecting AA on Windows and this Mac", PersistUIText.sharedSaveSetup)
        }
    }

    // MARK: Read-only instance (DATA-174/175)

    func startReadOnly() {
        guard let env, readOnlySession == nil else { readOnlySession?.start(); return }
        let session = PersistReadOnlySession(
            dataFile: { [weak env] in env?.dataStore.currentDataFile ?? URL(fileURLWithPath: "/") },
            tryUpgrade: { InstanceGuard.retryEditing() },
            onSaveSeen: { [weak self] in self?.liveReload() })
        readOnlySession = session
        session.start()
    }

    /// The editor saved: reload silently, keeping this window's own selection (DATA-174 live view).
    private func liveReload() {
        guard let env, env.isReadOnlyInstance else { return }
        env.loadDataAndInitUI(reason: .other("persist.liveView"),
                              status: PersistReadOnlyText.updated(ShellStatusText.hms(env.clock.now())))
        readOnlySession?.rememberDisk()
    }

    /// The holder of the lock on this Mac, when it is a running app (Switch to Other AA).
    var otherAppPid: Int32? {
        guard let pid = InstanceGuard.folderBlocked?.localPid ?? InstanceGuard.externalBlocked?.localPid,
              NSRunningApplication(processIdentifier: pid) != nil else { return nil }
        return pid
    }

    func switchToOther() {
        guard let pid = otherAppPid else { return }
        _ = InstanceGuard.forwardToRunningInstance(pid: pid, documents: [])
    }

    func stayReadOnly() {
        InstanceGuard.relinquishEditing()
        withAnimation(.snappy) { readOnlySession?.stayReadOnly() }
    }

    /// "Edit Here": confirm discarding in-memory changes, reload from disk, leave read-only mode and start everything
    /// a read-only copy suppressed (shared save, autosave, housekeeping, reminders, the data-file watcher).
    func editHere() async {
        guard let env else { return }
        if hasInMemoryChanges {
            let ok = await env.mainDialogs.confirm(PersistReadOnlyText.discardTitle, "",
                                                   confirm: PersistReadOnlyText.discardAndEdit, destructive: true)
            guard ok else { return }
        }
        guard InstanceGuard.canEdit || InstanceGuard.retryEditing() else { return }
        readOnlySession?.stop()
        readOnlySession = nil
        withAnimation(.snappy) { env.isReadOnlyInstance = false }
        env.loadDataAndInitUI(reason: .reloadFromDisk,
                              status: PersistReadOnlyText.nowEditing(env.dataStore.currentDataFile.path))
        env.dataFileGuard?.start()
        env.startAutosaveTimer()
        env.sharedSave.start()
        if env.sharedSave.path != nil { await env.sharedSave.checkForUpdate() }
        if !env.isSafeMode {
            _ = env.store.pruneTrash()
            _ = env.store.reconcileRecurrences()
            env.refreshAfterTrashChange()
            ReminderCenter.shared.start(env: env)
        }
        refreshConflictCopies()
    }

    /// The model differs from the last loaded data (UI state excluded) — read-only edits never set `isDirty`.
    var hasInMemoryChanges: Bool {
        guard let env, let base = contentBaseline else { return false }
        return PersistUIBridge.contentSignature(env.store) != base
    }

    private func rememberContent() {
        guard let env else { return }
        contentBaseline = PersistUIBridge.contentSignature(env.store)
    }

    static func contentSignature(_ store: AppStore) -> String {
        guard case .object(var o) = ModelCodec.encodeAppData(store.data) else { return "" }
        _ = o.removeValue(forKey: "Ui")
        _ = o.removeValue(forKey: "LastModified")
        return (try? JSONWriter.string(.object(o))) ?? ""
    }

    // MARK: ⌘S in a read-only copy (DATA-174 — F3's `AppEnvironment.doSave` presents this sheet)

    /// "Read-only — not saving" with "OK" (default) and, when the editing copy runs on this Mac, "Switch to Other AA".
    func presentReadOnlySaveSheet() async {
        guard let env, !presentingSaveSheet else { return }
        presentingSaveSheet = true
        defer { presentingSaveSheet = false }
        let canSwitch = otherAppPid != nil
        var buttons = [AlertButton(title: "OK", role: .default)]
        if canSwitch { buttons.append(AlertButton(title: PersistReadOnlyText.switchToOther)) }
        let picked = await env.mainDialogs.alert(AlertSpec(title: PersistReadOnlyText.saveTitle,
                                                           message: PersistReadOnlyText.saveMessage,
                                                           style: .warning, buttons: buttons))
        if canSwitch, picked == 1 { switchToOther() }
    }

    // MARK: Lease lost (DATA-177)

    private func leaseLost(host: String) {
        guard let env else { return }
        PersistLeaseLoss.enterReadOnly(env.store, hasUnsavedChanges: env.store.isDirty || hasInMemoryChanges)
        env.sharedSave.stop()
        env.stopAutosaveTimer()
        env.dataFileGuard?.stop()
        ReminderCenter.shared.stop()
        withAnimation(.snappy) { env.isReadOnlyInstance = true }
        startReadOnly()
        refreshConflictCopies()
        Task { @MainActor in
            await env.mainDialogs.info(PersistReadOnlyText.leaseLostTitle, PersistReadOnlyText.leaseLostMessage(host: host))
        }
    }
}

/// Mac-only explanatory texts of W-PERSIST's UI.
enum PersistUIText {
    static let sharedSaveSetup = "Give each computer its own AA data folder (the default one is fine), then point both copies of AA at one shared save file that both can reach — File ▸ Shared Save File ▸ Set… on each.\n\nWith Parallels, keep the shared file in a Mac folder that is shared with Windows: for example ~/AA-Shared/aa-shared.zip on this Mac, which Windows sees as \\\\Mac\\Home\\AA-Shared\\aa-shared.zip.\n\nAA then saves to that file every minute and reloads automatically when the other copy updates it."
    static let conflictCopiesEmpty = "When another program changes the data file while AA is open, the version you don't keep is saved here."
    static let conflictCopiesHelp = "Versions of the data file kept when it was changed outside this copy of AA. The newest 20 are kept."
}
