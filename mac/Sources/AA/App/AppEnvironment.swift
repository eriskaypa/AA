// Spec: 03 SHELL-007/008 (LoadDataAndInitUi, safe mode), SHELL-009 (newer schema), SHELL-032/033 (CaptureUiState),
//       SHELL-047 (undo delete), SHELL-050 (DoSave), SHELL-054 (FlushAllEditors), SHELL-120 (import review gate),
//       SHELL-125 (shared-save host hooks), 01 DATA-020/021/026/027/036/081/104, DATA-180 host, 02 REPO-009,
//       08 QUICK-190, DECISIONS 03 Q-3 (reload keeps per-device Ui keys and geometry), W-9 (flush all editors),
//       W-11 (re-apply appearance and toggles after every reload); ARCHITECTURE.md §7.3, §7.9.
import AppKit
import SwiftUI
import AACore

/// Codable so a notification click can round-trip it through `UNNotification.userInfo` (key "aa.sceneRequest").
enum SceneRequest: Hashable, Codable {
    case item(UUID), search, activityLog, quickWork, dueDates, quickSwitcher, flashSync, crewTable, folderBuilder,
         dateCalculator, unitConverter, shortcuts, about, settings(tab: SettingsTab?)
}

enum SettingsTab: String, Hashable, Codable { case general, security, sync, fileLinks, ai }

@MainActor @Observable
final class AppEnvironment: SharedSaveHost, DataFileConflictHost {
    let store: AppStore
    var dataStore: DataStore { store.dataStore }
    var settings: SettingsStore { store.dataStore.settings }
    let locks: ItemLockService
    let passwords: PasswordService
    let navigator: Navigator
    let status: StatusCenter
    let router: CommandRouter
    let flush: EditorFlushCenter
    let sharedSave: SharedSaveCoordinator
    let driveSync: DriveSyncCoordinator
    let clock: AppClock

    /// SHELL-199: `swift run` (no bundle).
    let isBundled: Bool
    /// BD.3.6 (the informational sheet is W-SHELL's SHELL-190).
    let isTranslocated: Bool
    /// The data file was unreadable at load (01 DATA-021).
    private(set) var safeMode = false
    /// This copy runs read-only beside another editor (W-PERSIST DATA-172 "Open Read-Only").
    var isReadOnlyInstance = false
    /// True once the first load completed and the main window shows data.
    private(set) var mainLoaded = false
    /// The Settings tab requested by `open(.settings(tab:))` (read by W-SHELL's SettingsView).
    var requestedSettingsTab: SettingsTab?
    /// The DATA-180 guard (W-PERSIST type) installed at launch.
    @ObservationIgnored var dataFileGuard: DataFileFingerprint?

    var isSafeMode: Bool { safeMode }

    /// The presenter bound to the main window (falls back to the unbound presenter before it exists).
    var mainDialogs: DialogPresenter { SceneOpener.shared.dialogs(for: .main) ?? .unbound }

    /// `AA — {identity}` (SHELL-020).
    var windowTitle: String { ShellStatusText.windowTitle(identity: settings.appIdentity) }

    @ObservationIgnored private var subscriptions: [EventSubscription] = []
    @ObservationIgnored private var reconciling = false
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?

    init(store: AppStore, isBundled: Bool, isTranslocated: Bool) {
        self.store = store
        self.clock = store.clock
        self.locks = ItemLockService()
        self.passwords = PasswordService(settings: store.dataStore.settings)
        self.navigator = Navigator(store: store)
        self.status = StatusCenter()
        self.router = CommandRouter()
        self.flush = EditorFlushCenter()
        self.sharedSave = SharedSaveCoordinator(store: store)
        self.driveSync = DriveSyncCoordinator()
        self.isBundled = isBundled
        self.isTranslocated = isTranslocated
        router.env = self
        sharedSave.host = self
        driveSync.attach(self)
        subscriptions.append(store.saved.subscribe { [weak self] in self?.storeDidSave() })
        subscriptions.append(store.trashChanged.subscribe { [weak self] in self?.refreshAfterTrashChange() })
    }

    // MARK: Editors and UI state

    /// OC-43 / W-9: every live editor, item window, SIRE body and modal editor.
    func flushAllEditors() { flush.flushAll() }

    /// SHELL-032/033: geometry only while the window is normal; state always; SelectedMainTabIndex.
    func captureUiState() {
        let ui = store.data.ui
        ui.selectedMainTabIndex = navigator.selectedIndex
        guard let w = SceneOpener.shared.window(for: .main) else { return }
        let zoomed = w.isZoomed || w.styleMask.contains(.fullScreen)
        if w.isMiniaturized {
            ui.windowState = ShellWindowStateName.minimized.rawValue
        } else if zoomed {
            ui.windowState = ShellWindowStateName.maximized.rawValue
        } else {
            ui.windowState = ShellWindowStateName.normal.rawValue
            let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? w.frame.maxY
            let f = w.frame
            let v = ShellWindowGeometry.wpfValues(frame: ShellRect(x: f.minX, y: f.minY, width: f.width, height: f.height),
                                                  primaryScreenMaxY: primaryMaxY)
            ui.windowLeft = v.left; ui.windowTop = v.top; ui.windowWidth = v.width; ui.windowHeight = v.height
        }
    }

    /// Applies the stored geometry to the main window (launch only — DECISIONS 03 Q-3).
    func restoreWindowGeometry(_ w: NSWindow) {
        let ui = store.data.ui
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? w.frame.maxY
        let visible = NSScreen.screens.map { s in
            ShellRect(x: s.visibleFrame.minX, y: s.visibleFrame.minY, width: s.visibleFrame.width, height: s.visibleFrame.height)
        }
        let cur = ShellRect(x: w.frame.minX, y: w.frame.minY, width: w.frame.width, height: w.frame.height)
        if let f = ShellWindowGeometry.restoredFrame(left: ui.windowLeft, top: ui.windowTop, width: ui.windowWidth,
                                                     height: ui.windowHeight, current: cur,
                                                     primaryScreenMaxY: primaryMaxY, visibleFrames: visible) {
            w.setFrame(NSRect(x: f.x, y: f.y, width: f.width, height: f.height), display: true)
        }
        if ShellWindowGeometry.restoredState(ui.windowState) == .maximized, !w.isZoomed { w.zoom(nil) }
    }

    func setShortcutBarVisible(_ visible: Bool) {
        guard store.data.ui.showShortcutBar != visible else { return }
        withAnimation(.snappy) { store.data.ui.showShortcutBar = visible }
        store.markDirty()
    }

    // MARK: Save (SHELL-050, DATA-027) and autosave (SHELL-052, DATA-026, REPO-009)

    func doSave() {
        if isReadOnlyInstance {                         // DATA-174: "Read-only — not saving" (REQ-W-PERSIST-02)
            Task { @MainActor in await PersistUIBridge.shared.presentReadOnlySaveSheet() }
            return
        }
        if safeMode {
            Task { @MainActor in await mainDialogs.warning(ShellStatusText.safeModeSaveTitle, ShellStatusText.safeModeSaveMessage) }
            return
        }
        flushAllEditors()
        captureUiState()
        do {
            try store.save()
            status.post(ShellStatusText.saved(clock.now()))
            driveSync.queueSyncAfterExplicitSave()
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in await mainDialogs.error(ShellStatusText.saveFailedTitle, message) }
        }
    }

    /// Flush + confirmed save (exports, sync); the caller reports errors.
    func saveQuietly() throws {
        flushAllEditors()
        captureUiState()
        try store.save()
    }

    func doAutosave() {
        guard mainLoaded, !safeMode else { return }
        flushAllEditors()
        let now = clock.now()
        guard store.isDirty else {
            status.post(ShellStatusText.autosaveNoChanges(now))
            return
        }
        captureUiState()
        do {
            try store.save()
            status.post(ShellStatusText.autosaved(clock.now()))
        } catch {
            status.post(ShellStatusText.autosaveFailed(error.localizedDescription))
        }
    }

    /// The 5-minute timer: autosave, then the non-interactive Drive check (SHELL-052).
    func startAutosaveTimer(interval: Duration = .seconds(300)) {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.doAutosave()
                // TOOLS-024 (MW:244-247): the background Drive check is fire-and-forget, so a slow listing or an open
                // review sheet never holds back the next 5-minute autosave (overlaps are refused by the coordinator).
                let drive = self.driveSync
                Task { @MainActor in await drive.checkRemoteNewer(interactive: false) }
            }
        }
    }

    func stopAutosaveTimer() {
        autosaveTask?.cancel()
        autosaveTask = nil
    }

    /// SHELL-055 / REPO-063: reconcile recurrences after every save (re-entrancy and safe-mode guards).
    private func storeDidSave() {
        if !reconciling, !safeMode, mainLoaded {
            reconciling = true
            _ = store.reconcileRecurrences()
            reconciling = false
        }
        if DueDatesPanelController.shared.isVisible { DueDatesPanelController.shared.refresh() }
    }

    // MARK: Undo delete (SHELL-047, SHELL-521)

    func undoDelete() {
        guard mainLoaded, !safeMode else { return }
        let n = store.pendingUndoCount()
        guard n > 0 else {
            status.post(ShellStatusText.nothingToUndo)
            return
        }
        // REPO-077 (MainWindow.xaml.cs:1461-1471): nothing came back (unreadable payload, unknown type) → "Nothing to
        // undo." and no save; otherwise save, surfacing a failure like every other immediate save (D5).
        let types = store.undoLastDelete()
        refreshAfterTrashChange()
        guard !types.isEmpty else {
            status.post(ShellStatusText.nothingToUndo)
            return
        }
        do {
            try store.save()
            status.post(ShellStatusText.restored(n))
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in await mainDialogs.error(ShellStatusText.saveFailedTitle, message) }
        }
    }

    func refreshAfterTrashChange() {
        router.pendingUndoCount = mainLoaded ? store.pendingUndoCount() : 0
    }

    // MARK: Load (SHELL-007, DATA-020/021/036, ARCH §7.9)

    /// Reload settings + data, replace the graph, safe-mode flag, per-device Ui keys kept on reloads, appearance and
    /// menu toggles re-applied, status.
    func loadDataAndInitUI(reason: DataReplaceReason, status statusText: String?) {
        let initial = reason == .initialLoad
        if !initial { captureUiState() }
        let oldUi = store.data.ui
        dataStore.loadSettings()                                    // also forgets the app-password session (DATA-081)
        let data = dataStore.load()
        if !initial { data.ui.copyPerDeviceValues(from: oldUi) }
        store.replaceData(data, reason: reason)
        safeMode = dataStore.lastLoadFailed
        store.suspendSaving = safeMode || isReadOnlyInstance
        settings.isWriteGated = isReadOnlyInstance
        ShellAppearance.apply(settings: settings)
        router.darkModeChecked = ShellAppearance.isEffectivelyDark
        if initial || reason == .reloadFromDisk || reason == .importFile {
            navigator.restoreSelection()
        } else if !navigator.sectionOrder.contains(navigator.selectedSection) {
            navigator.restoreSelection()
        }
        mainLoaded = true
        router.pendingUndoCount = store.pendingUndoCount()
        router.conflictCopiesExist = !ConflictCopies.list(dataStore).isEmpty
        let path = dataStore.currentDataFile.path
        status.post(statusText ?? (safeMode ? ShellStatusText.safeModeStatus(cause: dataStore.lastLoadError)
                                                       : ShellStatusText.loaded(path)))
    }

    // MARK: Import review gate (SHELL-120, DATA-104, QUICK-190)

    func reviewAndConfirmImport(incoming: AppData?, incomingStamp: NetDateTime?, sourceName: String,
                                presenter: DialogPresenter?) async -> Bool {
        let dialogs = presenter ?? mainDialogs
        guard let incoming else {
            let spec = AlertSpec(title: ShellStatusText.confirmImportTitle,
                                 message: ShellStatusText.confirmImportMessage(sourceName: sourceName), style: .warning,
                                 buttons: [AlertButton(title: "Yes", role: .default), AlertButton(title: "No", role: .cancel)])
            return await dialogs.alert(spec) == 0
        }
        let diff = DataDiff.compare(current: store.data, incoming: incoming)
        let other = DataDiff.compareOtherData(current: store.data, incoming: incoming)
        let age = AgeVerdict.text(incoming: incomingStamp, current: store.data.lastModified)
        return await dialogs.reviewChanges(ReviewChangesRequest(sourceName: sourceName, ageText: age, diff: diff,
                                                                otherData: other))
    }

    // MARK: DATA-180 host (W-PERSIST's sheet on the main window)

    func presentConflict(_ c: DataFileConflict) async -> DataFileConflictChoice {
        showMainWindow()
        var choice = DataFileConflictChoice.keepMine
        await mainDialogs.presentSheet(.decision) { dismiss in
            DataFileConflictSheet(conflict: c) { picked in choice = picked; dismiss() }
        }
        return choice
    }

    // MARK: SharedSaveHost (W-PERSIST's coordinator calls these)

    func confirmReloadDiscardingChanges() async -> Bool {
        let spec = AlertSpec(title: "Shared save updated",
                             message: "The shared save file was updated by another copy of AA.\n\nReload it now (data + attachments)? Changes on this Mac that aren't in the shared file yet will be lost.\n\nReload (Discard My Changes) = reload\nKeep Mine = keep mine (they overwrite the shared file on the next save)",
                             style: .informational,
                             buttons: [AlertButton(title: "Reload (Discard My Changes)", role: .default),
                                       AlertButton(title: "Keep Mine", role: .cancel)])
        return await mainDialogs.alert(spec) == 0
    }

    func reloadAfterSharedImport(identity: String?) {
        let t = ShellStatusText.hms(clock.now())
        let who = identity.flatMap { NetText.isBlank($0) ? nil : " from “\($0)”" } ?? ""
        loadDataAndInitUI(reason: .sharedSavePull, status: "Reloaded the shared save\(who) (\(t)).")
    }

    func postStatus(_ text: String) { status.post(text) }

    // MARK: Windows

    func open(_ request: SceneRequest) {
        let opener = SceneOpener.shared
        switch request {
        case .item(let id):
            if let w = opener.itemWindow(id) { w.makeKeyAndOrderFront(nil) } else {
                flushAllEditors()                                   // SHELL-054: flush before detaching
                opener.open(.item, value: id)
            }
        case .search: opener.open(.search)
        case .activityLog: opener.open(.activityLog)
        case .quickWork: opener.open(.quickWork)
        case .dueDates:
            DueDatesPanelController.shared.show(env: self)
            DueDatesPanelController.shared.refresh()
        case .quickSwitcher:
            showMainWindow()
            QuickSwitcherPanelController.shared.show(env: self)
        case .flashSync: opener.open(.flashSync)
        case .crewTable: opener.open(.crewTable)
        case .folderBuilder: opener.open(.folderBuilder)
        case .dateCalculator: opener.open(.dateCalculator)
        case .unitConverter: opener.open(.unitConverter, value: UUID())
        case .shortcuts: opener.open(.shortcuts)
        case .about: opener.open(.about)
        case .settings(let tab):
            requestedSettingsTab = tab
            opener.openSettings()
        }
    }

    func showMainWindow() {
        if let w = SceneOpener.shared.window(for: .main) {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        } else if LaunchCoordinator.shared.phase == .main {
            SceneOpener.shared.open(.main)
        }
    }

    // MARK: Errors (SHELL-001, ARCH §9.1)

    func reportError(_ error: Error, context: String) {
        let written = CrashLog.append(CrashLog.details(for: error, context: context), appFolder: dataStore.appFolder)
        let message = CrashLog.dialogMessage(message: error.localizedDescription, writtenTo: written)
        Task { @MainActor in await mainDialogs.error(CrashLog.dialogTitle, message) }
    }
}
