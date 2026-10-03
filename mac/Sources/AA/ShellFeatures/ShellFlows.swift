// Spec: 03 SHELL-061 (Save a Copy As), 062 (Reload from disk), 063 (Import from file), 065 (Encrypt local data file),
//       066 (Set shared save file, Mac Join/Create two-step of §6.9), 067 (Stop shared save file), 068 (App identity),
//       069 (Open data folder), 070 (Export data folder), 071 (Import data folder), 072 (Export text only), 101 (Set /
//       change password), 102 (Lock now), 185 (.aaz / .zip opened from Finder → import with review), BD.3.7, §6.5
//       (Mac button names), §6.9, Appendix A.3/A.4; 01 DATA-012, 032…034, 040, 042, 043, 048, 050, 051, 070, 080,
//       DATA-179 (external-file lock at import), DATA-182 (unreadable settings status); 06 BUILD-145 B1, A25, A27;
//       DECISIONS 01 Q-4 (current password), Q-5 (copy into AA folder / use in place), 03 Q-7 (cadence text);
//       ARCHITECTURE.md §7.7, §7.8, §7.9 (import pipeline: flush → peek → [external lock] → review gate → apply →
//       loadDataAndInitUI), §9.1.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

/// W-SHELL's File / Tools menu flows (ARCHITECTURE.md §7.8 rows 547–559, 657, 658) and Finder document opening.
@MainActor enum ShellFlows {
    /// The commands `perform` implements.
    static let handled: Set<CommandID> = [.saveCopyAs, .reloadFromDisk, .importFromFile, .encryptLocalData,
                                          .setSharedSaveFile, .stopSharedSaveFile, .checkSharedSaveNow,
                                          .setAppIdentity, .openDataFolder, .exportDataFolder, .importDataFolder,
                                          .exportTextOnly, .setPassword, .lockNow]

    /// Flows currently running (a second invocation while one is open beeps instead of stacking panels).
    private static var running: Set<CommandID> = []

    static func handles(_ c: CommandID) -> Bool { handled.contains(c) }

    static func perform(_ c: CommandID, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard handles(c) else { return }
        guard !running.contains(c) else {
            NSSound.beep()
            return
        }
        running.insert(c)
        defer { running.remove(c) }
        switch c {
        case .saveCopyAs: await saveCopyAs(env, dialogs)
        case .reloadFromDisk: await reloadFromDisk(env, dialogs)
        case .importFromFile: await importFromFile(env, dialogs)
        case .encryptLocalData: await toggleEncryption(env, dialogs)
        case .setSharedSaveFile: await setSharedSaveFile(env, dialogs)
        case .stopSharedSaveFile: await stopSharedSaveFile(env, dialogs)
        case .checkSharedSaveNow: await checkSharedSaveNow(env)
        case .setAppIdentity: await setAppIdentity(env, dialogs)
        case .openDataFolder: await openDataFolder(env, dialogs)
        case .exportDataFolder: await exportDataFolder(env, dialogs)
        case .importDataFolder: await importDataFolder(env, dialogs)
        case .exportTextOnly: toggleTextOnly(env)
        case .setPassword: await setPassword(env, dialogs)
        case .lockNow: env.status.post(ShellXDataFlows.lockNow(passwords: env.passwords, locks: env.locks))
        default: break
        }
    }

    /// SHELL-185 / BD.3.7: `.aaz` / `.zip` documents from Finder (double-click, Open With, Dock drop, forwarded by a
    /// second launch) — the Import Data Folder (ZIP) flow without its open panel, one review per file, in order.
    static func openDocuments(_ urls: [URL], env: AppEnvironment) async {
        for url in urls where ShellXDataFlows.isBundleDocument(url) {
            env.showMainWindow()
            await importBundle(url, env: env, dialogs: env.mainDialogs)
        }
    }

    // MARK: Save a Copy As JSON (SHELL-061 / DATA-032)

    private static func saveCopyAs(_ env: AppEnvironment, _ dialogs: DialogPresenter) async {
        guard let url = await dialogs.savePanel(SavePanelConfig(defaultName: ShellXText.saveCopyDefaultName,
                                                                allowedTypes: [.json], allowsOtherTypes: true,
                                                                directory: env.dataStore.appFolder)) else { return }
        env.flushAllEditors()                                           // W-9: every editor, not only four pages
        env.captureUiState()
        do {
            try ShellXDataFlows.saveCopy(env.store, to: url)
            env.status.post(ShellXText.exportedTo(url.path))
        } catch {
            await dialogs.error(ShellXText.saveAsFailedTitle, error.localizedDescription)
        }
    }

    // MARK: Reload from disk (SHELL-062 / DATA-033)

    private static func reloadFromDisk(_ env: AppEnvironment, _ dialogs: DialogPresenter) async {
        let spec = AlertSpec(title: ShellXText.confirmReloadTitle, message: ShellXText.confirmReloadMessage,
                             style: .warning,
                             buttons: [AlertButton(title: ShellXText.confirmReloadButton, role: .default),
                                       AlertButton(title: "Cancel", role: .cancel)])
        guard await dialogs.alert(spec) == 0 else { return }
        // Pending editor buffers are deliberately not flushed first (Windows parity, SHELL-062).
        env.loadDataAndInitUI(reason: .reloadFromDisk, status: ShellStatusText.reloaded(env.clock.now()))
    }

    // MARK: Import from file (SHELL-063 / DATA-034, DECISIONS 01 Q-5, DATA-179)

    private static func importFromFile(_ env: AppEnvironment, _ dialogs: DialogPresenter) async {
        let picked = await dialogs.openPanel(OpenPanelConfig(allowedTypes: [.json], directory: env.dataStore.appFolder,
                                                             allFilesAccessory: true))
        guard let url = picked.first else { return }
        env.flushAllEditors()
        let incoming: AppData
        do {
            incoming = try env.dataStore.loadFrom(url)
        } catch {
            await dialogs.error(ShellXText.importFailedTitle, error.localizedDescription)
            return
        }
        guard await env.reviewAndConfirmImport(incoming: incoming, incomingStamp: incoming.lastModified,
                                               sourceName: url.lastPathComponent, presenter: dialogs) else { return }
        var copyIntoFolder = false
        if ShellXDataFlows.asksImportPlacement(for: url, dataStore: env.dataStore) {
            let spec = AlertSpec(title: ShellXText.importPlacementTitle,
                                 message: ShellXText.importPlacementMessage(fileName: url.lastPathComponent),
                                 style: .informational,
                                 buttons: [AlertButton(title: ShellXText.copyIntoFolderButton, role: .default),
                                           AlertButton(title: ShellXText.useInPlaceButton),
                                           AlertButton(title: "Cancel", role: .cancel)])
            switch await dialogs.alert(spec) {
            case 0: copyIntoFolder = true
            case 1: copyIntoFolder = false
            default: return
            }
        }
        // DATA-179: lock an external file BEFORE it becomes the active data file; another holder cancels the import.
        if !copyIntoFolder, ShellXDataFlows.needsExternalLock(for: url, dataStore: env.dataStore) {
            let result = InstanceGuard.acquireExternal(fileURL: url)
            if ShellXDataFlows.externalLockRefuses(result) {
                _ = await dialogs.alert(AlertSpec(title: ShellXText.externalFileInUse, message: "", style: .warning,
                                                  buttons: [AlertButton(title: "OK", role: .default)]))
                return
            }
        }
        do {
            let target = try env.dataStore.adoptExternalDataFile(url, copyIntoAppFolder: copyIntoFolder)
            if env.dataStore.isUnderAppFolder(target) { InstanceGuard.releaseExternal() }
            env.loadDataAndInitUI(reason: .importFile,
                                  status: ShellStatusText.loaded(env.dataStore.currentDataFile.path))
        } catch {
            await dialogs.error(ShellXText.importFailedTitle, error.localizedDescription)
        }
    }

    // MARK: Encrypt local data file (SHELL-065 / DATA-070)

    private static func toggleEncryption(_ env: AppEnvironment, _ dialogs: DialogPresenter) async {
        guard env.mainLoaded else { return }
        if env.isSafeMode || env.isReadOnlyInstance {
            await dialogs.warning(ShellXText.safeModeTitle, ShellXText.encryptInSafeMode)
            return
        }
        let on = !env.settings.values.encryptLocalData
        if on {
            let spec = AlertSpec(title: ShellXText.encryptTitle, message: ShellXText.encryptConfirmMessage,
                                 style: .informational,
                                 buttons: [AlertButton(title: ShellXText.encryptButton, role: .default),
                                           AlertButton(title: "Cancel", role: .cancel)])
            guard await dialogs.alert(spec) == 0 else { return }
        }
        env.flushAllEditors()
        do {
            try ShellXDataFlows.setEncryptLocalData(on, store: env.store)
            env.status.post(ShellXText.encryptionStatus(on))
        } catch {
            await dialogs.error(ShellXText.encryptFailedTitle, error.localizedDescription)
        }
        postIfSettingsUnwritable(env)
    }

    // MARK: Shared save (SHELL-066 / DATA-050, SHELL-067 / DATA-051, Check Now)

    private static func setSharedSaveFile(_ env: AppEnvironment, _ dialogs: DialogPresenter) async {
        guard env.mainLoaded else { return }
        if env.isSafeMode || env.isReadOnlyInstance {
            // P2: pushing from safe mode would overwrite the shared bundle with an empty database.
            await dialogs.warning(ShellStatusText.safeModeSaveTitle, ShellStatusText.safeModeSaveMessage)
            return
        }
        // 03 §6.9 MAC-ADAPT: NSSavePanel always confirms a replace, so first ask Join or Create.
        let choice = await dialogs.alert(AlertSpec(
            title: ShellXText.sharedChoiceTitle, message: ShellXText.sharedChoiceMessage, style: .informational,
            buttons: [AlertButton(title: ShellXText.sharedJoinButton, role: .default),
                      AlertButton(title: ShellXText.sharedCreateButton), AlertButton(title: "Cancel", role: .cancel)]))
        let current = env.settings.values.sharedSaveFile.flatMap { NetText.isBlank($0) || PathMapper.isWindowsPath($0) ? nil : $0 }
        let startFolder = current.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        let url: URL?
        switch choice {
        case 0:
            url = await dialogs.openPanel(OpenPanelConfig(message: ShellXText.sharedPanelMessage,
                                                          allowedTypes: [.zip, .aaBundle], directory: startFolder,
                                                          allFilesAccessory: true)).first
        case 1:
            url = await dialogs.savePanel(SavePanelConfig(message: ShellXText.sharedPanelMessage,
                                                          defaultName: ShellXText.sharedDefaultName,
                                                          allowedTypes: [.zip, .aaBundle], allowsOtherTypes: true,
                                                          directory: startFolder))
        default:
            url = nil
        }
        guard let url else { return }
        env.flushAllEditors()
        var useItsContents = false
        if choice == 0, FileManager.default.fileExists(atPath: url.path) {
            let d28 = AlertSpec(title: ShellXText.sharedSaveFileTitle,
                                message: ShellXText.sharedExistsMessage(fileName: url.lastPathComponent),
                                style: .informational,
                                buttons: [AlertButton(title: ShellXText.sharedUseItsContents, role: .default),
                                          AlertButton(title: ShellXText.sharedOverwriteIt),
                                          AlertButton(title: "Cancel", role: .cancel)])
            switch await dialogs.alert(d28) {
            case 0: useItsContents = true
            case 1: useItsContents = false
            default: return
            }
        }
        // (Create on an existing file = the user confirmed the replace in the save panel = D28 "Overwrite It".)
        let generation = env.store.generation
        do {
            try await env.sharedSave.adoptSharedFile(url, useItsContents: useItsContents)
            // REQ-W-SHELL-01: reload here only if the coordinator did not already replace the data.
            if useItsContents, env.store.generation == generation {
                env.loadDataAndInitUI(reason: .sharedSavePull, status: nil)
            }
            env.sharedSave.start()
            env.status.post(ShellXText.sharedSet(url.path))
            postIfSettingsUnwritable(env)
            await dialogs.info(ShellXText.sharedSaveFileTitle, ShellXText.sharedSetInfo(path: url.path))
        } catch {
            env.sharedSave.stop()
            env.settings.setSharedSaveFile(nil)
            await dialogs.error(ShellXText.setSharedFailedTitle, error.localizedDescription)
        }
    }

    private static func stopSharedSaveFile(_ env: AppEnvironment, _ dialogs: DialogPresenter) async {
        guard !NetText.isBlank(env.settings.values.sharedSaveFile) else {
            env.status.post(ShellXText.sharedNone)
            return
        }
        let spec = AlertSpec(title: ShellXText.stopSharedTitle, message: ShellXText.stopSharedMessage,
                             style: .informational,
                             buttons: [AlertButton(title: ShellXText.stopSharedButton, role: .default),
                                       AlertButton(title: "Cancel", role: .cancel)])
        guard await dialogs.alert(spec) == 0 else { return }
        env.sharedSave.stopUsing()
        if !NetText.isBlank(env.settings.values.sharedSaveFile) { env.settings.setSharedSaveFile(nil) }
        env.status.post(ShellXText.sharedStopped)
        postIfSettingsUnwritable(env)
    }

    private static func checkSharedSaveNow(_ env: AppEnvironment) async {
        guard !NetText.isBlank(env.settings.values.sharedSaveFile) else {
            env.status.post(ShellXText.sharedNone)
            return
        }
        let generation = env.store.generation
        let before = env.status.message
        await env.sharedSave.checkForUpdate()
        // The coordinator posts its own reload / skip texts; say something when it found nothing to do.
        if env.store.generation == generation, env.status.message == before {
            env.status.post(ShellXText.sharedChecked(env.clock.now()))
        }
    }

    // MARK: App identity (SHELL-068 / DATA-048 / BUILD-145 B1)

    private static func setAppIdentity(_ env: AppEnvironment, _ dialogs: DialogPresenter) async {
        let request = TextPromptRequest(title: ShellXText.identityTitle, prompt: ShellXText.identityPrompt,
                                        initial: env.settings.appIdentity,
                                        helpText: ShellXText.identityHelp(defaultName: SettingsStore.defaultIdentity()))
        guard case .ok(let value) = await dialogs.prompt(request) else { return }   // Cancel → nothing at all
        let identity = ShellXDataFlows.setAppIdentity(value, settings: env.settings)
        env.postSettingStatus(ShellXText.identitySet(identity))                    // title follows the settings
        postIfSettingsUnwritable(env)
    }

    // MARK: Open data folder (SHELL-069 / DATA-012)

    private static func openDataFolder(_ env: AppEnvironment, _ dialogs: DialogPresenter) async {
        let folder = env.dataStore.appFolder
        if !NSWorkspace.shared.open(folder) {
            _ = await dialogs.alert(AlertSpec(title: ShellXText.openFailedTitle,
                                              message: ShellXText.openFolderFailedMessage(folder.path),
                                              style: .informational,
                                              buttons: [AlertButton(title: "OK", role: .default)]))
        }
    }

    // MARK: Export / import data folder (SHELL-070 / DATA-040, SHELL-071 / DATA-043)

    private static func exportDataFolder(_ env: AppEnvironment, _ dialogs: DialogPresenter) async {
        let name = ShellXText.exportDefaultName(env.clock.now(), zone: env.clock.timeZone)
        guard let url = await dialogs.savePanel(SavePanelConfig(defaultName: name, allowedTypes: [.zip, .aaBundle],
                                                                allowsOtherTypes: true)) else { return }
        guard ShellXDataFlows.exportDestinationAllowed(url, dataStore: env.dataStore) else {
            await dialogs.error(ShellXText.exportFailedTitle, ShellXText.exportInsideAppFolder)
            return
        }
        do {
            try env.saveQuietly()                                       // flush (W-9), capture, stamp + save
            try await BundleService.exportFolderToZip(env.dataStore, to: url,
                                                      includeAttachments: !env.settings.values.textOnlyExport)
            env.status.post(ShellXText.exportedDataFolder(url.path))
        } catch {
            await dialogs.error(ShellXText.exportFailedTitle, error.localizedDescription)
        }
    }

    private static func importDataFolder(_ env: AppEnvironment, _ dialogs: DialogPresenter) async {
        let picked = await dialogs.openPanel(OpenPanelConfig(allowedTypes: [.zip, .aaBundle], allFilesAccessory: true))
        guard let url = picked.first else { return }
        await importBundle(url, env: env, dialogs: dialogs)
    }

    /// SHELL-071 / SHELL-185: peek → review gate (source = file name) → smart import → reload → status.
    static func importBundle(_ url: URL, env: AppEnvironment, dialogs: DialogPresenter) async {
        env.flushAllEditors()
        guard FileManager.default.fileExists(atPath: url.path) else {
            await dialogs.error(ShellXText.importFailedTitle, "Could not find file '\(url.path)'.")
            return
        }
        let incoming = BundleService.peekZipData(url, dataStore: env.dataStore)
        guard await env.reviewAndConfirmImport(incoming: incoming, incomingStamp: incoming?.lastModified,
                                               sourceName: url.lastPathComponent, presenter: dialogs) else { return }
        do {
            let kind = try BundleService.importBundleSmart(env.dataStore, from: url)
            // A bundle import makes the default data file active again (DATA-013), so the external lock goes.
            if env.dataStore.isUnderAppFolder(env.dataStore.currentDataFile) { InstanceGuard.releaseExternal() }
            env.loadDataAndInitUI(reason: .importBundle,
                                  status: ShellXText.importedBundle(fileName: url.lastPathComponent,
                                                                    dataOnly: kind == .dataOnly))
        } catch {
            await dialogs.error(ShellXText.importFailedTitle, error.localizedDescription)
        }
    }

    // MARK: Export text only (SHELL-072 / DATA-042)

    private static func toggleTextOnly(_ env: AppEnvironment) {
        let on = !env.settings.values.textOnlyExport
        env.postSettingStatus(ShellXDataFlows.setTextOnlyExport(on, settings: env.settings))
        postIfSettingsUnwritable(env)
    }

    // MARK: Password (SHELL-101 / DATA-080, DECISIONS 01 Q-4)

    private static func setPassword(_ env: AppEnvironment, _ dialogs: DialogPresenter) async {
        let mode: PasswordSheetMode = env.passwords.hasPassword ? .changeExisting : .setNew
        guard case .ok(let password, let current) = await dialogs.password(mode) else { return }
        do {
            if try ShellXDataFlows.setPassword(password, current: current, passwords: env.passwords) {
                env.status.post(ShellXText.passwordUpdated)
                postIfSettingsUnwritable(env)
            }
        } catch {
            await dialogs.error(ShellXText.passwordFailedTitle, error.message)
        }
    }

    // MARK: Helpers

    /// DATA-182: a settings setter that could not write keeps the value for this session; say so.
    private static func postIfSettingsUnwritable(_ env: AppEnvironment) {
        if env.settings.lastWriteRefused { env.status.post(SettingsStore.unreadableStatus) }
    }
}

extension AppEnvironment {
    /// Status of a settings setter (Dark Mode, Export Text Only, identity, Sync on Save…): while `settings.json` is
    /// write-gated (read-only copy, DATA-180 stopped editing) the DATA-174 suffix says the change is session-only.
    func postSettingStatus(_ text: String) {
        status.post(ShellXText.settingStatus(text, gated: settings.isWriteGated))
    }
}
