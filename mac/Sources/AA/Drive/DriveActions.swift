// Spec: 14 TOOLS-001…004 (synced-folder copy, ResolveDriveFolder, Set folder), TOOLS-007 (Set OAuth client),
//       TOOLS-013 (sign out), TOOLS-014/015 (OAuth upload / load with the backup picker = VIEW-212 row 1, review gate,
//       smart import), TOOLS-020 (sync toggle), TOOLS-023 (interactive check), TOOLS-031 (text-only governs Drive),
//       TOOLS-035 (temp hygiene), §6.2 (NSOpenPanel with can-create, "Show in Finder" addition), Q-12 (flush all editors),
//       Q-21 (safe mode refuses the synced copy and upload); 01 DATA-174 (read-only copy: the Drive commands of
//       `CommandRouterCore.readOnlyDisabled` are disabled in Settings too, and refuse when reached); 03 SHELL-073…080;
//       ARCHITECTURE.md §7.7, §7.8, §7.9.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

@MainActor enum DriveActions {
    // MARK: DATA-174 write gate

    /// The router's G3 condition (`CommandRouter` context `writeGated`): a read-only copy, or DATA-180 "Stop Editing
    /// Here". The Drive commands in `CommandRouterCore.readOnlyDisabled` are unavailable while it holds.
    static func isWriteGated(_ env: AppEnvironment) -> Bool {
        env.isReadOnlyInstance || env.dataFileGuard?.state.mode == .stoppedEditing
    }

    /// Defence in depth for callers that bypass the router (Settings buttons): posts the DATA-174 text and refuses.
    private static func refusedWhenGated(_ env: AppEnvironment) -> Bool {
        guard isWriteGated(env) else { return false }
        env.driveSync.post(PersistReadOnlyText.disabledHelp)
        return true
    }

    // MARK: Synced folder (TOOLS-002…004)

    static func saveCopyToSyncedFolder(env: AppEnvironment, dialogs: DialogPresenter) async {
        if refusedWhenGated(env) { return }
        if env.isSafeMode {                                                       // Q-21
            await dialogs.warning(ShellStatusText.safeModeSaveTitle, ShellStatusText.safeModeSaveMessage)
            return
        }
        guard let folder = await resolveDriveFolder(forcePick: false, env: env, dialogs: dialogs) else { return }
        let ds = env.dataStore
        do {
            try env.saveQuietly()
            let backups = folder.appending(path: DriveLocalFolder.backupsSubfolder, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            let zip = backups.appending(path: DriveLocalFolder.backupFileName(identity: env.settings.appIdentity,
                                                                              now: env.clock.now()))
            try await BundleService.exportFolderToZip(ds, to: zip, includeAttachments: !env.settings.values.textOnlyExport)
            env.driveSync.post(DriveText.savedCopy(zip.path))
            let choice = await dialogs.alert(AlertSpec(title: DriveText.savedToDriveTitle,
                                                       message: DriveText.savedToDriveMessage(zip.path), style: .informational,
                                                       buttons: [AlertButton(title: "OK", role: .default),
                                                                 AlertButton(title: "Show in Finder")]))
            if choice == 1 { NSWorkspace.shared.activateFileViewerSelecting([zip]) }
        } catch {
            await dialogs.error(DriveText.saveToDriveFailedTitle, error.localizedDescription)
        }
    }

    static func setDriveFolder(env: AppEnvironment, dialogs: DialogPresenter) async {
        if refusedWhenGated(env) { return }
        _ = await resolveDriveFolder(forcePick: true, env: env, dialogs: dialogs)
    }

    /// TOOLS-003 `ResolveDriveFolder(forcePick)`.
    static func resolveDriveFolder(forcePick: Bool, env: AppEnvironment, dialogs: DialogPresenter) async -> URL? {
        let settings = env.settings
        if !forcePick {
            if let stored = DriveLocalFolder.usableStored(settings.values.googleDriveFolder) { return stored }
            if let found = DriveLocalFolder.detect() {
                settings.setGoogleDriveFolder(found.path)
                env.driveSync.noteStateChanged()
                return found
            }
        }
        await dialogs.info(DriveText.locateTitle, forcePick ? DriveText.locateForced : DriveText.locateNotFound)
        let current = DriveLocalFolder.usableStored(settings.values.googleDriveFolder)
        guard let picked = await chooseFolder(message: DriveText.folderPickerMessage, directory: current, dialogs: dialogs) else {
            return nil
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: picked.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        settings.setGoogleDriveFolder(picked.path)
        env.driveSync.post(DriveText.folderSet(picked.path))
        env.driveSync.noteStateChanged()
        return picked
    }

    /// A folder picker that can create folders (14 §6.2), attached to the presenter's window.
    static func chooseFolder(message: String, directory: URL?, dialogs: DialogPresenter) async -> URL? {
        let p = NSOpenPanel()
        p.message = message
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.allowsMultipleSelection = false
        if let directory { p.directoryURL = directory }
        let response: NSApplication.ModalResponse
        if let w = dialogs.window ?? NSApp.keyWindow, w.isVisible, w.attachedSheet == nil {
            response = await withCheckedContinuation { cont in p.beginSheetModal(for: w) { cont.resume(returning: $0) } }
        } else {
            response = p.runModal()
        }
        return response == .OK ? p.url : nil
    }

    // MARK: OAuth client (TOOLS-007)

    static func setOAuthClient(env: AppEnvironment, dialogs: DialogPresenter) async {
        if refusedWhenGated(env) { return }
        _ = await chooseClientSecret(env: env, dialogs: dialogs)
    }

    /// Returns true when a client file was copied.
    @discardableResult
    static func chooseClientSecret(env: AppEnvironment, dialogs: DialogPresenter) async -> Bool {
        let urls = await dialogs.openPanel(OpenPanelConfig(message: DriveText.clientPickerMessage, allowedTypes: [.json],
                                                           allFilesAccessory: true))
        guard let source = urls.first else { return false }
        do {
            try DriveClientSecret.install(from: source, to: env.dataStore.googleClientSecretFile)
            env.driveSync.post(DriveText.clientSet)
            env.driveSync.noteStateChanged()
            await dialogs.info(DriveText.oauthTitle, DriveText.clientSavedMessage)
            return true
        } catch {
            await dialogs.error(DriveText.setClientFailedTitle, error.localizedDescription)
            return false
        }
    }

    /// TOOLS-014 step 1: offer to choose the client file when none is configured; true when configured afterwards.
    static func ensureConfigured(env: AppEnvironment, dialogs: DialogPresenter) async -> Bool {
        if GoogleTokenStore.isConfigured(env.dataStore) { return true }
        let yes = await dialogs.alert(AlertSpec(title: DriveText.oauthTitle, message: DriveText.notConfiguredQuestion,
                                                style: .informational,
                                                buttons: [AlertButton(title: "Yes", role: .default),
                                                          AlertButton(title: "No", role: .cancel)])) == 0
        guard yes else { return false }
        await chooseClientSecret(env: env, dialogs: dialogs)
        return GoogleTokenStore.isConfigured(env.dataStore)
    }

    // MARK: Upload (TOOLS-014)

    static func uploadBackup(env: AppEnvironment, dialogs: DialogPresenter) async {
        if refusedWhenGated(env) { return }
        guard await ensureConfigured(env: env, dialogs: dialogs) else { return }
        if env.isSafeMode {                                                       // Q-21
            await dialogs.warning(ShellStatusText.safeModeSaveTitle, ShellStatusText.safeModeSaveMessage)
            return
        }
        let sync = env.driveSync
        sync.begin(.upload)
        sync.activePresenter = dialogs
        defer { sync.end(.upload); sync.activePresenter = nil }
        let temp = DriveSyncCoordinator.temporaryURL(DriveLocalFolder.uploadTempName(now: env.clock.now()))
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            try env.saveQuietly()
            try await BundleService.exportFolderToZip(env.dataStore, to: temp,
                                                      includeAttachments: !env.settings.values.textOnlyExport)
            sync.post(DriveText.uploading)
            guard let ops = sync.operations(interactive: true) else { return }
            let result = try await ops.uploadBackup(temp)
            sync.post(DriveText.uploaded(result.name))
            var buttons = [AlertButton(title: "OK", role: .default)]
            if let link = result.link, URL(string: link) != nil { buttons.append(AlertButton(title: "Open in Browser")) }
            let choice = await dialogs.alert(AlertSpec(title: DriveText.uploadedTitle,
                                                       message: DriveText.uploadedMessage(name: result.name, link: result.link),
                                                       style: .informational, buttons: buttons))
            if choice == 1, let link = result.link, let url = URL(string: link) { NSWorkspace.shared.open(url) }
        } catch {
            if DriveSyncCoordinator.isCancellation(error) {
                sync.post(DriveText.signInCancelled)
                return
            }
            sync.post(DriveText.uploadFailedStatus)
            await dialogs.error(DriveText.uploadFailedTitle, error.localizedDescription)
        }
    }

    // MARK: Load (TOOLS-015)

    static func loadBackup(env: AppEnvironment, dialogs: DialogPresenter) async {
        if refusedWhenGated(env) { return }
        guard await ensureConfigured(env: env, dialogs: dialogs) else { return }
        let sync = env.driveSync
        let ds = env.dataStore
        sync.begin(.load)
        sync.activePresenter = dialogs
        defer { sync.end(.load); sync.activePresenter = nil }
        var temp: URL?
        defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
        do {
            sync.post(DriveText.listing)
            guard let ops = sync.operations(interactive: true) else { return }
            let backups = try await ops.listBackups()
            if backups.isEmpty {
                sync.post(DriveText.noBackupsStatus)
                await dialogs.info(DriveText.loadTitle, DriveText.noBackupsMessage)
                return
            }
            // VIEW-212 row 1: single selection, newest first, rows "{name}    (uploaded yyyy-MM-dd HH:mm)".
            let zone = env.clock.timeZone
            let rows = backups.map { ItemPickerRow(display: $0.display(zone: zone), tag: $0.id) }
            let picked = await dialogs.pickItems(ItemPickerRequest(prompt: DriveText.pickerPrompt, rows: rows, mode: .single))
            guard let id = picked?.first, let backup = backups.first(where: { $0.id == id }) else { return }
            sync.post(DriveText.downloading(backup.name))
            let t = DriveSyncCoordinator.temporaryURL(DriveLocalFolder.loadTempName(now: env.clock.now()))
            temp = t
            try await ops.download(fileID: backup.id, to: t)
            env.flushAllEditors()
            let incoming = BundleService.peekZipData(t, dataStore: ds)
            let ok = await env.reviewAndConfirmImport(incoming: incoming, incomingStamp: incoming?.lastModified,
                                                      sourceName: DriveText.backupSource(backup.name), presenter: dialogs)
            guard ok else {
                sync.post(DriveText.loadCancelled)
                return
            }
            let kind = try BundleService.importBundleSmart(ds, from: t)
            let text = DriveText.loadedBackup(backup.name, dataOnly: kind == .dataOnly)
            env.loadDataAndInitUI(reason: .driveImport, status: text)
            sync.noteStateChanged()
        } catch {
            if DriveSyncCoordinator.isCancellation(error) {
                sync.post(DriveText.signInCancelled)
                return
            }
            sync.post(DriveText.loadFailedStatus)
            await dialogs.error(DriveText.loadFailedTitle, error.localizedDescription)
        }
    }

    // MARK: Sign out, toggle, check (TOOLS-013, TOOLS-020, TOOLS-023)

    static func signOut(env: AppEnvironment, dialogs: DialogPresenter) async {
        GoogleTokenStore.signOut(env.dataStore)
        env.driveSync.post(DriveText.signedOut)
        env.driveSync.noteStateChanged()
    }

    static func toggleSyncOnSave(env: AppEnvironment, dialogs: DialogPresenter) async {
        await setSyncOnSave(!env.settings.values.syncOnSave, env: env, dialogs: dialogs)
    }

    static func setSyncOnSave(_ on: Bool, env: AppEnvironment, dialogs: DialogPresenter) async {
        env.settings.setSyncOnSave(on)
        env.driveSync.noteStateChanged()
        let gated = env.settings.isWriteGated                                   // DATA-174 settings suffix
        guard on else {
            env.driveSync.post(ShellXText.settingStatus(DriveText.syncOff, gated: gated))
            return
        }
        env.driveSync.post(ShellXText.settingStatus(DriveText.syncOn, gated: gated))
        if !GoogleTokenStore.isConfigured(env.dataStore) {
            await dialogs.info(DriveText.syncTitle, DriveText.syncOnNotConfigured)
        } else {
            await env.driveSync.checkRemoteNewer(interactive: true, dialogs: dialogs)
        }
    }

    static func checkForNewer(env: AppEnvironment, dialogs: DialogPresenter) async {
        if refusedWhenGated(env) { return }
        await env.driveSync.checkRemoteNewer(interactive: true, dialogs: dialogs)
    }
}

// MARK: Settings ▸ Sync (W-SHELL embeds it)

/// The Google Drive part of Settings ▸ Sync: synced folder, OAuth client, sign-in state, sync on save and the Mac
/// sync indicator (14 §6.5), with buttons for every Drive command of the File menu.
struct DriveSettingsSection: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        let sync = env.driveSync
        let ds = env.dataStore
        let _ = sync.stateGeneration
        let configured = GoogleTokenStore.isConfigured(ds)
        let hasToken = GoogleTokenStore.hasToken(ds)
        let reconsent = GoogleTokenStore.needsReconsentForWholeDrive(ds)
        let folder = DriveLocalFolder.usableStored(env.settings.values.googleDriveFolder)
        // DATA-174: the same Drive commands the router disables in a read-only copy (`readOnlyDisabled`).
        let gated = DriveActions.isWriteGated(env)
        Section {
            LabeledContent("Synced folder") {
                HStack(spacing: AASpacing.s) {
                    if let folder {
                        Label(folder.path, systemImage: "folder")
                            .lineLimit(1).truncationMode(.middle)
                            .help(folder.path)
                    } else {
                        Text("Not set — detected automatically on first use").foregroundStyle(.secondary)
                    }
                    Button("Choose\u{2026}") { run { await DriveActions.setDriveFolder(env: env, dialogs: dialogs) } }
                        .disabled(gated)
                        .help(gatedHelp(gated, "Choose which local folder is your Google Drive (the one Google Drive for desktop syncs)."))
                }
            }
            HStack {
                Spacer()
                Button("Save a Copy to Google Drive") { run { await DriveActions.saveCopyToSyncedFolder(env: env, dialogs: dialogs) } }
                    .disabled(gated)
                    .help(gatedHelp(gated, "Save a timestamped backup ZIP into your Google Drive desktop folder, which syncs it to the cloud."))
            }
            DriveSettingsHelp("Backups go to “AA Backups” inside that folder; Google Drive for desktop uploads them.")
        } header: {
            Text("Google Drive for desktop")
        }

        Section {
            LabeledContent("OAuth client") {
                HStack(spacing: AASpacing.s) {
                    DriveSettingsBadge(text: configured ? "Configured" : "Not configured",
                                       symbol: configured ? "checkmark.seal.fill" : "seal",
                                       color: configured ? AAColor.Status.ok : AAColor.Status.neutral)
                    Button("Choose client_secret.json\u{2026}") { run { await DriveActions.setOAuthClient(env: env, dialogs: dialogs) } }
                        .disabled(gated)
                        .help(gatedHelp(gated, "Load the client_secret.json you downloaded from Google Cloud Console (OAuth 'Desktop app' client)."))
                }
            }
            LabeledContent("Google sign-in") {
                HStack(spacing: AASpacing.s) {
                    if hasToken {
                        DriveSettingsBadge(text: "Signed in (whole Drive)", symbol: "person.crop.circle.badge.checkmark",
                                           color: AAColor.Status.ok)
                    } else if reconsent {
                        DriveSettingsBadge(text: "One more sign-in needed", symbol: "exclamationmark.triangle.fill",
                                           color: AAColor.Status.dueSoon)
                            .help(DriveText.reconsentMessage)
                    } else {
                        DriveSettingsBadge(text: "Not signed in", symbol: "person.crop.circle", color: AAColor.Status.neutral)
                    }
                    Button("Sign Out") { run { await DriveActions.signOut(env: env, dialogs: dialogs) } }
                        .disabled(!hasToken && !reconsent)
                        .help("Forget the cached Google sign-in for OAuth uploads.")
                }
            }
            Toggle(isOn: Binding(get: { env.settings.values.syncOnSave },
                                 set: { on in run { await DriveActions.setSyncOnSave(on, env: env, dialogs: dialogs) } })) {
                Text("Sync to Google Drive on save")
                Text("When on, \u{2318}S also pushes your data to Google Drive (OAuth), and the app checks for a newer save pushed from other Macs and PCs.")
            }
            LabeledContent("Last activity") {
                HStack(spacing: AASpacing.s) {
                    Image(systemName: sync.indicator.symbol)
                        .foregroundStyle(DriveSettingsSection.indicatorColor(sync.indicator))
                        .symbolEffect(.rotate, isActive: sync.indicator == .pushing)
                    Text(sync.lastStatus ?? "No Drive activity this session")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(sync.lastStatus ?? "")
                }
            }
            HStack(spacing: AASpacing.s) {
                Spacer()
                Button("Check for Newer Save") { run { await DriveActions.checkForNewer(env: env, dialogs: dialogs) } }
                    .disabled(gated || sync.inFlight.contains(.check))
                    .help(gatedHelp(gated, "Ask Google Drive whether a newer save state exists, and offer to load it."))
                Button("Upload Backup\u{2026}") { run { await DriveActions.uploadBackup(env: env, dialogs: dialogs) } }
                    .disabled(gated || !sync.inFlight.isDisjoint(with: [.upload, .load, .check]))
                    .help(gatedHelp(gated, "Upload a backup directly to Google Drive via the Drive API (no desktop client needed). Requires a Google OAuth client."))
                Button("Load Backup\u{2026}") { run { await DriveActions.loadBackup(env: env, dialogs: dialogs) } }
                    .disabled(gated || !sync.inFlight.isDisjoint(with: [.upload, .load, .check]))
                    .help(gatedHelp(gated, "Download a backup from your Google Drive and (after a newer/older check) replace your current data with it."))
            }
            DriveSettingsHelp("AA reads your whole Drive to find backups (including iPhone .aaz files) but can only change files it created. Keep the Google Cloud consent screen in Testing with your account added as a test user.")
        } header: {
            Text("Google Drive (OAuth)")
        }
    }

    private func run(_ body: @escaping @MainActor () async -> Void) { Task { @MainActor in await body() } }

    /// The router's G3 tooltip for a gated command (`PersistReadOnlyText.disabledHelp`), else the command's own.
    private func gatedHelp(_ gated: Bool, _ help: String) -> String { gated ? PersistReadOnlyText.disabledHelp : help }

    static func indicatorColor(_ s: DriveIndicatorState) -> Color {
        switch s {
        case .idle: return AAColor.Status.neutral
        case .pushing: return AAColor.tint
        case .synced: return AAColor.Status.ok
        case .failed: return AAColor.Status.danger
        }
    }
}

/// A help line inside a Settings ▸ Sync section — the same proportional, muted, wrapping style as the Shared Save
/// File and Exports help rows of that pane (Settings is system-font chrome, design rule 2).
struct DriveSettingsHelp: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// A compact state capsule used in the Drive settings rows.
struct DriveSettingsBadge: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View { AAStatusCapsule(text: text, symbol: symbol, color: color) }
}
