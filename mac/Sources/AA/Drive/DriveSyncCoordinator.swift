// Spec: 14 TOOLS-011 (startup: background check or re-consent notice), TOOLS-020/021 (sync on save: 1.5 s debounce,
//       single flight with coalescing, bundle built off the main actor, `lastSeenRemote = stamp`, status vocabulary),
//       TOOLS-023/024/026/027/030 (CheckRemoteNewer: review gate, smart import, reload, decline memory), §3.2.1–3.2.4,
//       §6.5 (Mac: queue the review sheet, skip overlapping background checks, in-flight set for menu enablement,
//       sync indicator), §6.3 (sign-in waiting sheet); 03 SHELL-010/011/121/122; ARCHITECTURE.md §7.7 (contract),
//       §7.9 (import pipeline).
import AppKit
import SwiftUI
import AACore

enum DriveOperation: Hashable { case upload, load, check, push }

/// Mac addition (14 §6.5): the small sync indicator's state.
enum DriveIndicatorState: Equatable {
    case idle, pushing, synced(Date), failed(String)

    var symbol: String {
        switch self {
        case .idle: return "icloud"
        case .pushing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.icloud"
        case .failed: return "exclamationmark.icloud"
        }
    }
}

@MainActor @Observable final class DriveSyncCoordinator {
    private(set) var inFlight: Set<DriveOperation> = []
    private(set) var indicator: DriveIndicatorState = .idle
    /// The last Drive status string (tooltip of the indicator).
    private(set) var lastStatus: String?
    /// Bumped whenever the sign-in / configuration state may have changed (Settings refreshes on it).
    private(set) var stateGeneration = 0

    @ObservationIgnored private weak var env: AppEnvironment?
    /// `_lastSeenRemote` (TOOLS-026): per session, starts nil.
    @ObservationIgnored private(set) var lastSeenRemote: NetDateTime?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var pushRunning = false
    @ObservationIgnored private var pushQueued = false
    @ObservationIgnored private var authorizerInstance: DriveAuthorizer?
    @ObservationIgnored private let transport = DriveURLSessionTransport()
    /// The presenter the current user-initiated Drive command came from (sign-in sheet host).
    @ObservationIgnored var activePresenter: DialogPresenter?
    @ObservationIgnored private var signIn: DriveSignInModel?

    /// TOOLS-021: 1500 ms debounce.
    static let pushDebounce: Duration = .milliseconds(1500)

    init() {}

    func attach(_ env: AppEnvironment) { self.env = env }

    // MARK: Plumbing

    private var presenter: DialogPresenter { activePresenter ?? env?.mainDialogs ?? .unbound }

    func post(_ text: String) {
        lastStatus = text
        env?.status.post(text)
    }

    func begin(_ op: DriveOperation) { inFlight.insert(op) }
    func end(_ op: DriveOperation) { inFlight.remove(op); stateGeneration += 1 }

    func noteStateChanged() { stateGeneration += 1 }

    private func authorizer(_ ds: DataStore) -> DriveAuthorizer {
        if let a = authorizerInstance { return a }
        let hooks = DriveSignInHooks(
            started: { [weak self] url, cancel in
                let me = self
                await MainActor.run { me?.presentSignIn(url: url, cancel: cancel) }
            },
            ended: { [weak self] in
                let me = self
                await MainActor.run { me?.finishSignIn() }
            },
            openBrowser: { url in
                await MainActor.run { NSWorkspace.shared.open(url) }
            })
        let a = DriveAuthorizer(clientSecretFile: ds.googleClientSecretFile, vault: GoogleTokenStore.vault(ds),
                                transport: transport, clock: ds.clock, hooks: hooks)
        authorizerInstance = a
        return a
    }

    /// The Drive operations for one command. `interactive == false` never opens a browser.
    func operations(interactive: Bool) -> DriveOperations? {
        guard let env else { return nil }
        let client = DriveRESTClient(authorizer: authorizer(env.dataStore), transport: transport, interactive: interactive)
        return DriveOperations(api: client, identity: env.settings.appIdentity)
    }

    private func presentSignIn(url: URL, cancel: @escaping @Sendable () -> Void) {
        signIn?.finish()
        let model = DriveSignInModel(cancel: cancel)
        model.consentURL = url
        signIn = model
        let dialogs = presenter
        Task { @MainActor in
            await dialogs.presentSheet(.decision) { dismiss in DriveSignInSheet(model: model, dismiss: dismiss) }
        }
    }

    private func finishSignIn() {
        signIn?.finish()
        signIn = nil
        stateGeneration += 1
    }

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if let e = error as? DriveError, e == .signInCancelled { return true }
        return false
    }

    nonisolated static func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: name)
    }

    // MARK: Sync on save (TOOLS-021, SHELL-121)

    /// Called by `env.doSave()` after a successful explicit save: (re)starts the 1.5 s debounce when sync is on and
    /// a client is configured.
    func queueSyncAfterExplicitSave() {
        guard let env, env.settings.values.syncOnSave, GoogleTokenStore.isConfigured(env.dataStore) else { return }
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: DriveSyncCoordinator.pushDebounce)
            guard !Task.isCancelled, let self else { return }
            await self.runSyncPush()
        }
    }

    /// `RunSyncPush`: single flight; a request during a push sets the queued flag and the loop runs again.
    func runSyncPush() async {
        guard let env, env.settings.values.syncOnSave, GoogleTokenStore.isConfigured(env.dataStore) else { return }
        if pushRunning { pushQueued = true; return }
        pushRunning = true
        begin(.push)
        indicator = .pushing
        defer { pushRunning = false; end(.push) }
        let ds = env.dataStore
        do {
            repeat {
                pushQueued = false
                let stamp = env.store.data.lastModified
                let temp = DriveSyncCoordinator.temporaryURL(DriveLocalFolder.syncTempName())
                defer { try? FileManager.default.removeItem(at: temp) }
                post(DriveText.syncing)
                try await BundleService.exportFolderToZip(ds, to: temp, includeAttachments: !env.settings.values.textOnlyExport)
                guard let ops = operations(interactive: true) else { return }
                try await ops.pushSync(temp, lastModified: stamp)
                lastSeenRemote = stamp
                post(DriveText.synced(ShellStatusText.hms(env.clock.now())))
                indicator = .synced(Date())
            } while pushQueued
        } catch {
            let msg = DriveSyncCoordinator.isCancellation(error) ? DriveText.signInCancelled : error.localizedDescription
            post(DriveText.syncFailed(msg))
            indicator = .failed(msg)
        }
    }

    // MARK: Newer-save check (TOOLS-023/024, SHELL-122)

    func checkRemoteNewer(interactive: Bool) async {
        await checkRemoteNewer(interactive: interactive, dialogs: nil)
    }

    func checkRemoteNewer(interactive: Bool, dialogs: DialogPresenter?) async {
        // DATA-174: a read-only copy never loads from Drive (the menu row and Settings button are disabled too).
        guard let env, env.mainLoaded, !DriveActions.isWriteGated(env) else { return }
        // Mac addition (14 §6.5, Q-18): a background check never overlaps a push or another check.
        if !interactive && (inFlight.contains(.check) || inFlight.contains(.push)) { return }
        if interactive && inFlight.contains(.check) { return }
        let ds = env.dataStore
        let dialogs = dialogs ?? env.mainDialogs
        if interactive { activePresenter = dialogs }
        begin(.check)
        defer { end(.check); if interactive { activePresenter = nil } }
        let input = DriveCheckInput(interactive: interactive, syncOnSave: env.settings.values.syncOnSave,
                                    configured: GoogleTokenStore.isConfigured(ds), hasToken: GoogleTokenStore.hasToken(ds),
                                    localStamp: env.store.data.lastModified, lastSeenRemote: lastSeenRemote)
        var temp: URL?
        defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
        do {
            guard let ops = operations(interactive: interactive) else { return }
            let (result, seen) = try await DriveRemoteCheck.run(
                input, operations: ops, zone: env.clock.timeZone,
                makeTempURL: { DriveSyncCoordinator.temporaryURL(DriveLocalFolder.checkTempName()) },
                peekStamp: { BundleService.peekZipLastModified($0) })
            lastSeenRemote = seen
            switch result {
            case .notConfigured:
                if interactive { await dialogs.info(DriveText.syncTitle, DriveText.checkNotConfigured) }
            case .noToken, .alreadySeen:
                return
            case .nothingOnDrive:
                if interactive { post(DriveText.nothingOnDrive) }
            case .upToDate:
                post(DriveText.upToDate(ShellStatusText.hms(env.clock.now())))
            case .newer(let remote, let identity, let fileID, let downloaded):
                temp = downloaded
                post(DriveText.newerFound(identity: identity))
                if temp == nil {
                    let t = DriveSyncCoordinator.temporaryURL(DriveLocalFolder.checkTempName())
                    temp = t
                    try await ops.download(fileID: fileID, to: t)
                }
                guard let zip = temp else { return }
                env.flushAllEditors()
                let incoming = BundleService.peekZipData(zip, dataStore: ds)
                let ok = await env.reviewAndConfirmImport(incoming: incoming, incomingStamp: remote,
                                                          sourceName: DriveText.newerSaveSource, presenter: env.mainDialogs)
                guard ok else {
                    post(DriveText.keptLocal)
                    return
                }
                let kind = try BundleService.importBundleSmart(ds, from: zip)
                let text = kind == .dataOnly ? DriveText.loadedNewerDataOnly : DriveText.loadedNewerWithAttachments
                env.loadDataAndInitUI(reason: .driveImport, status: text)
                lastSeenRemote = env.store.data.lastModified
                lastStatus = text
                noteStateChanged()
            }
        } catch {
            if DriveSyncCoordinator.isCancellation(error) {
                post(DriveText.signInCancelled)
            } else if interactive {
                await dialogs.error(DriveText.checkFailedTitle, error.localizedDescription)
            } else {
                post(DriveText.checkFailed(error.localizedDescription))
            }
        }
    }

    // MARK: Startup (TOOLS-011, SHELL-010/011)

    func startupChecks() async {
        guard let env else { return }
        let ds = env.dataStore
        let configured = GoogleTokenStore.isConfigured(ds)
        if env.settings.values.syncOnSave && configured && GoogleTokenStore.hasToken(ds) {
            await checkRemoteNewer(interactive: false)
        } else if configured && GoogleTokenStore.needsReconsentForWholeDrive(ds) {
            await env.mainDialogs.info(DriveText.reconsentTitle, DriveText.reconsentMessage)
        }
    }
}
