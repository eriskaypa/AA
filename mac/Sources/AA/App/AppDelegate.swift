// Spec: 03 BD.1.3 (launch order: AppFolder → crash sinks → pre-flight → settings/appearance → unbundled guards),
//       SHELL-192…199, SHELL-001/197 (crash reporting), SHELL-005/056 (quit), BD.3.7 (documents from Finder), 01 MP.6.1/6.2
//       (instance guard before any scene; blocked alert from applicationDidFinishLaunching; forwarded documents),
//       DATA-179/180 (external-file lock, write guard installed at launch); ARCHITECTURE.md §5.4, §7.1.
import AppKit
import SwiftUI
import AACore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var instanceResult: InstanceGuardResult = .editor
    private var externalResult: InstanceGuardResult = .editor
    private var appFolder: URL?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false                    // SHELL-526
        let coordinator = LaunchCoordinator.shared
        let opts = coordinator.options

        // 1. AppFolder (BD.3.2) — fixed for the process.
        let environment = ProcessInfo.processInfo.environment
        let resolved = AppFolderResolver.resolve(opts, environment: environment,
                                                 cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath,
                                                          isDirectory: true),
                                                 home: FileManager.default.homeDirectoryForCurrentUser)
        let raw = AppFolderResolver.rawCandidate(opts, environment: environment)
        var folder: URL
        var source: AppFolderSource
        switch resolved {
        case .success(let r):
            folder = r.url
            source = r.source
        case .failure(let e):
            ShellCrashReporter.install(appFolder: nil)
            showDataFolderAlert(path: raw?.value ?? "", error: e, source: raw?.source ?? .defaultLocation)
            exit(0)
        }
        AALog.logger("startup").info("AppFolder \(folder.path, privacy: .public) (\(String(describing: source), privacy: .public))")

        // 2. Crash sinks.
        ShellCrashReporter.install(appFolder: folder)

        // 3. Pre-flight, Try Again / Quit in a loop (BD.3.3).
        while true {
            do throws(DataDirError) {
                try AppFolderResolver.preflight(folder)
                break
            } catch {
                if !showDataFolderAlert(path: folder.path, error: error, source: source) { exit(0) }
            }
        }
        appFolder = folder

        // Instance guard before any scene (01 MP.6.1 step 1).
        instanceResult = InstanceGuard.acquire(appFolder: folder)

        // 4. Settings + appearance; the store and the environment.
        let dataStore = DataStore(appFolder: folder)
        dataStore.loadSettings()
        ShellAppearance.apply(settings: dataStore.settings)
        let store = AppStore(dataStore: dataStore, data: AppData())
        store.suspendSaving = true                                      // nothing is written before the first load
        let env = AppEnvironment(store: store, isBundled: !ShellLaunchEnvironment.isCurrentProcessUnbundled,
                                 isTranslocated: Translocation.isCurrentProcessTranslocated)
        // DATA-180: the write guard (W-PERSIST's DataFileFingerprint) on the writer and the data store.
        let fingerprint = DataFileFingerprint(store: store, host: env)
        store.writer.writeGuard = fingerprint
        dataStore.writeGuard = fingerprint
        env.dataFileGuard = fingerprint
        // DATA-179: external active data file → per-user lock.
        if !dataStore.isUnderAppFolder(dataStore.currentDataFile) {
            externalResult = InstanceGuard.acquireExternal(fileURL: dataStore.currentDataFile)
        }
        coordinator.install(env: env)

        // 5. Unbundled runs need a Dock icon and menu bar (SHELL-199).
        if ShellLaunchEnvironment.isCurrentProcessUnbundled {
            NSApp.setActivationPolicy(.regular)
        }
    }

    /// The SHELL-194 alert; returns true for Try Again.
    @discardableResult
    private func showDataFolderAlert(path: String, error: DataDirError, source: AppFolderSource) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = AppFolderResolver.alertTitle
        alert.informativeText = AppFolderResolver.alertMessage(path: path, error: error, source: source)
        if AppFolderResolver.offersTryAgain(error) {
            alert.addButton(withTitle: AppFolderResolver.tryAgainButton)
            let quit = alert.addButton(withTitle: AppFolderResolver.quitButton)
            quit.keyEquivalent = "\u{1b}"
        } else {
            alert.addButton(withTitle: AppFolderResolver.quitButton)
        }
        NSApp.activate()
        let r = alert.runModal()
        return AppFolderResolver.offersTryAgain(error) && r == .alertFirstButtonReturn
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = LaunchCoordinator.shared
        guard let env = coordinator.env, let folder = appFolder else { return }
        if ShellLaunchEnvironment.isCurrentProcessUnbundled { NSApp.activate() }
        NotificationCenterBridge.install(env: env)
        InstanceGuard.listenForForwardedDocuments { urls in LaunchCoordinator.shared.enqueueDocuments(urls) }
        ShellCrashReporter.startMetricKit()
        AppKitMenuBridge.shared.start()

        var result = instanceResult
        // DATA-179: the folder lock is ours but another AA (editing a DIFFERENT data folder) holds the external
        // CurrentDataFile — the single-instance forward does not apply (the holder ignores other folders' requests);
        // show the DATA-172 alert with the external-file wording instead.
        let externalOnly = result == .editor && externalResult != .editor
        if externalOnly { result = externalResult }
        switch result {
        case .editor:
            coordinator.instanceCheckPassed()
        case .unguarded(let why):
            AALog.logger("startup").notice("instance guard unavailable: \(why, privacy: .public)")
            coordinator.instanceCheckPassed()
        case .runningHere(let pid) where !externalOnly:
            // DECISIONS: a second launch activates the running instance (documents forwarded) and quits.
            _ = InstanceGuard.forwardToRunningInstance(pid: pid, documents: coordinator.takePendingDocuments())
            exit(0)
        case .otherUser, .remote, .sameUserNoApp, .runningHere:
            coordinator.setBlocked()
            switch InstanceAlerts.presentBlocked(result, appFolder: folder) {
            case .quit, .switchToRunning:
                exit(0)
            case .openReadOnly:
                env.isReadOnlyInstance = true
                coordinator.instanceCheckPassed()
            case .takeOver:
                coordinator.instanceCheckPassed()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        LaunchCoordinator.shared.enqueueDocuments(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ShellQuitPipeline.shouldTerminate(env: LaunchCoordinator.shared.env)
    }

    func applicationWillTerminate(_ notification: Notification) {
        InstanceGuard.release()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let c = LaunchCoordinator.shared
        switch c.phase {
        case .main: c.env?.showMainWindow()
        case .login: SceneOpener.shared.window(for: .login)?.makeKeyAndOrderFront(nil)
        default: break
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
