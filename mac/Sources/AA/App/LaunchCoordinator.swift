// Spec: 03 §1.3 / BD.1.3 (startup sequence), SHELL-003 (2.4 s splash), SHELL-004 (login gate; closing = terminate),
//       SHELL-005, SHELL-012/013 (startup shared check, then housekeeping), SHELL-008/009 (D1 / D2 after load),
//       SHELL-014 (no crew popup), 01 MP.6.1/6.2 (instance check before any scene), BD.3.7 (queued documents);
//       ARCHITECTURE.md §7.1 (phases .instanceCheck → .splash → .login → .main; .blocked).
import AppKit
import SwiftUI
import AACore

@MainActor @Observable
final class LaunchCoordinator {
    static let shared = LaunchCoordinator()

    private(set) var phase: ShellAppPhase = .instanceCheck
    /// Created by the AppDelegate once the data folder passed pre-flight.
    private(set) var env: AppEnvironment?
    /// The parsed command line (set by `AAMain`).
    var options = LaunchOptions()
    /// DEBUG snapshot runs skip splash and login.
    var snapshotMode = false
    /// MenuBarExtra preference `aa.menuBarExtra` (on by default; W-SHELL's Settings toggle writes it).
    var menuBarExtraEnabled = MacPreferences.shared.bool(MacPreferences.Key("aa.menuBarExtra"), default: true)

    /// DECISIONS Q-4/Q-13: present while AA runs in the main phase (not in snapshot or smoke runs).
    var menuBarExtraVisible: Bool { phase == .main && menuBarExtraEnabled && !snapshotMode && !options.smokeTest }

    func setMenuBarExtra(_ on: Bool) {
        menuBarExtraEnabled = on
        MacPreferences.shared.set(on, MacPreferences.Key("aa.menuBarExtra"))
    }

    @ObservationIgnored private var bootstrapIsReady = false
    @ObservationIgnored private var guardAllowsStart = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pendingDocuments: [URL] = []
    @ObservationIgnored private var draining = false
    @ObservationIgnored private var housekeepingDone = false
    @ObservationIgnored weak var mainWindow: NSWindow?
    @ObservationIgnored private var mainWindowDelegate: ShellWindowDelegateProxy?

    static let splashDuration: Duration = .milliseconds(2400)

    func install(env: AppEnvironment) {
        self.env = env
        env.router.startTracking()
    }

    // MARK: Gates

    func bootstrapReady() {
        bootstrapIsReady = true
        startIfPossible()
    }

    /// The instance guard allowed this process to continue (editor or read-only).
    func instanceCheckPassed() {
        guardAllowsStart = true
        startIfPossible()
    }

    func setBlocked() { setPhase(.blocked) }

    private func setPhase(_ p: ShellAppPhase) {
        phase = p
        env?.router.phase = p
    }

    private func startIfPossible() {
        guard bootstrapIsReady, guardAllowsStart, !started, env != nil else { return }
        started = true
        if snapshotMode {
            #if DEBUG
            SnapshotHook.start()
            #endif
            return
        }
        showSplash()
    }

    // MARK: Splash → login → main

    private func showSplash() {
        setPhase(.splash)
        SceneOpener.shared.open(.splash)
        Task { @MainActor in
            try? await Task.sleep(for: LaunchCoordinator.splashDuration)
            self.showLogin()
        }
    }

    func showLogin() {
        setPhase(.login)
        SceneOpener.shared.open(.login)
        SceneOpener.shared.dismiss(.splash)
        NSApp.activate()
    }

    /// The login succeeded (`ShellLoginModel.submit`).
    func loginSucceeded() {
        enterMain()
        SceneOpener.shared.dismiss(.login)
    }

    /// Phase `.main`: open the main window (snapshot runs come here directly).
    func enterMain() {
        setPhase(.main)
        ProcessInfo.processInfo.disableSuddenTermination()
        SceneOpener.shared.open(.main)
    }

    func loginWindowRegistered(_ w: NSWindow) {
        w.styleMask.remove(.resizable)
    }

    /// SHELL-004: closing the login window (✕ or ⌘W) = Exit → terminate (nothing written).
    func loginWindowWillClose() {
        if phase == .login { NSApp.terminate(nil) }
    }

    func mainWindowRegistered(_ w: NSWindow) {
        guard mainWindow !== w else { return }
        mainWindow = w
        w.tabbingMode = .disallowed
        w.minSize = NSSize(width: 860, height: 560)
        // SHELL-513: closing the main window (red button, ⌘W) runs the quit pipeline; the window stays until then.
        mainWindowDelegate = ShellWindowDelegateProxy(window: w) { _ in
            NSApp.terminate(nil)
            return false
        }
        ShellUndoShim.install(on: w)
    }

    /// The main window appeared: first load, geometry restore and the OnLoaded pipeline (03 §1.3 steps 11–19).
    func mainWindowAppeared() {
        guard let env, !env.mainLoaded else { return }
        env.loadDataAndInitUI(reason: .initialLoad, status: nil)
        // DATA-180 / DATA-174 (REQ-W-PERSIST-01): W-PERSIST's guard hooks (status, reload, mode change), the data-file
        // watcher for an editor outside safe mode, and the read-only session — once, after the first load.
        PersistUIBridge.shared.attach(env)
        if let w = mainWindow { env.restoreWindowGeometry(w) }
        // DATA-174: a read-only copy starts no 5-minute autosave (and so no Drive newer-save check); "Edit Here"
        // starts it (PersistUIBridge.editHere).
        if !env.isReadOnlyInstance { env.startAutosaveTimer() }
        // The window opens with the section sidebar focused, never a page's Name box in edit mode (HIER-025: Windows
        // focuses the Name box only on F2 / click).
        Task { @MainActor [weak self] in
            for delay in [100, 400] {
                try? await Task.sleep(for: .milliseconds(delay))
                ShellFocus.leaveHiddenSection(in: self?.mainWindow)
            }
        }
        if snapshotMode { return }
        Task { @MainActor in
            await Task.yield()
            await self.afterMainShown(env)
        }
    }

    /// Steps 15–19, deferred until the window rendered: dialogs, Drive, shared check first, then housekeeping.
    private func afterMainShown(_ env: AppEnvironment) async {
        if env.isSafeMode {
            await env.mainDialogs.warning(ShellStatusText.safeModeTitle,
                                          ShellStatusText.safeModeMessage(cause: env.dataStore.lastLoadError))
        } else if let v = env.dataStore.loadedNewerSchema {
            await env.mainDialogs.info(ShellStatusText.newerFormatTitle,
                                       ShellStatusText.newerFormatMessage(version: v, current: DataStore.currentSchemaVersion))
        }
        // SHELL-011/122, TOOLS-011: CheckRemoteNewer(false) is fire-and-forget on Windows — the shared-save start and
        // the housekeeping below run while the Drive request is in flight. Only the modal re-consent box is awaited.
        // DATA-174: a read-only copy runs no Drive check at all.
        if !env.isReadOnlyInstance { await startDriveChecks(env) }
        if !env.isReadOnlyInstance {
            env.sharedSave.start()
            if !NetText.isBlank(env.settings.values.sharedSaveFile) { await env.sharedSave.checkForUpdate() }
        }
        if !env.isSafeMode, !env.isReadOnlyInstance {
            _ = env.store.pruneTrash()
            _ = env.store.reconcileRecurrences()
            env.refreshAfterTrashChange()
            ReminderCenter.shared.start(env: env)
        }
        housekeepingDone = true
        await ShellCrashReporter.presentPendingReport(env: env)
        drainDocuments()
    }

    /// The startup half of `DriveSyncCoordinator.startupChecks()` without awaiting the network: the background
    /// newer-save check runs detached; the D3 re-consent info box (modal on Windows) is still awaited.
    private func startDriveChecks(_ env: AppEnvironment) async {
        let ds = env.dataStore
        if env.settings.values.syncOnSave && GoogleTokenStore.isConfigured(ds) && GoogleTokenStore.hasToken(ds) {
            Task { @MainActor in await env.driveSync.checkRemoteNewer(interactive: false) }
        } else {
            await env.driveSync.startupChecks()
        }
    }

    // MARK: Documents opened from Finder (BD.3.7, SHELL-185 — the import flow is W-SHELL's)

    func enqueueDocuments(_ urls: [URL]) {
        // DATA-173: bundles (.aaz / .zip) go to Import with preview, a .json database to Import Database (W-SHELL's
        // `ShellFlows.openDocuments` routes each kind).
        pendingDocuments.append(contentsOf: urls.filter { ["aaz", "zip", "json"].contains($0.pathExtension.lowercased()) })
        drainDocuments()
    }

    /// Documents that arrived before the instance check (forwarded to a running instance).
    func takePendingDocuments() -> [URL] {
        defer { pendingDocuments.removeAll() }
        return pendingDocuments
    }

    func drainDocuments() {
        guard phase == .main, housekeepingDone, !draining, let env, !pendingDocuments.isEmpty else { return }
        draining = true
        let urls = pendingDocuments
        pendingDocuments.removeAll()
        Task { @MainActor in
            env.showMainWindow()
            await ShellFlows.openDocuments(urls, env: env)
            self.draining = false
            self.drainDocuments()
        }
    }
}

/// Wraps SwiftUI's window delegate to intercept `windowShouldClose` and forwards everything else.
final class ShellWindowDelegateProxy: NSObject, NSWindowDelegate, @unchecked Sendable {
    private weak var original: NSWindowDelegate?
    private weak var window: NSWindow?
    private let shouldClose: @MainActor (NSWindow) -> Bool
    private var observation: NSKeyValueObservation?

    @MainActor
    init(window: NSWindow, shouldClose: @escaping @MainActor (NSWindow) -> Bool) {
        self.window = window
        self.shouldClose = shouldClose
        super.init()
        original = window.delegate
        window.delegate = self
        // SwiftUI may install a new delegate later; re-wrap it.
        observation = window.observe(\.delegate, options: [.new]) { [weak self] w, _ in
            MainActor.assumeIsolated {
                guard let self, w.delegate !== self else { return }
                self.original = w.delegate
                w.delegate = self
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated { shouldClose(sender) }
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return original?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let o = original, o.responds(to: aSelector) { return o }
        return super.forwardingTarget(for: aSelector)
    }
}

/// SHELL-521 parity: ⌘Z that no responder handled in the main window shows "Nothing to undo." instead of beeping.
final class ShellUndoShim: NSResponder {
    @MainActor static func install(on window: NSWindow) {
        // Insert after the content view controller (NSView forwards setNextResponder to its controller).
        let anchor: NSResponder? = window.contentViewController ?? window.contentView
        guard let anchor, !(anchor.nextResponder is ShellUndoShim) else { return }
        let shim = ShellUndoShim()
        shim.nextResponder = anchor.nextResponder
        anchor.nextResponder = shim
        objc_setAssociatedObject(window, &ShellUndoShim.key, shim, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    nonisolated(unsafe) private static var key: UInt8 = 0

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "z" {
            MainActor.assumeIsolated {
                if let env = LaunchCoordinator.shared.env, env.mainLoaded, !env.isSafeMode,
                   env.router.pendingUndoCount == 0 {
                    env.status.post(ShellStatusText.nothingToUndo)
                } else {
                    NSSound.beep()
                }
            }
            return
        }
        super.keyDown(with: event)
    }
}
