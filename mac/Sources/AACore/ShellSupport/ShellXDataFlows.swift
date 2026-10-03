// Spec: 03 SHELL-061 (Save a Copy As), SHELL-063 (Import from file), SHELL-065 (Encrypt local data file), SHELL-068
//       (App identity), SHELL-070 (Export data folder — destination rule), SHELL-072 (Export text only), SHELL-101
//       (Set / change password), SHELL-102 (Lock now), SHELL-185 (.aaz / .zip documents), SHELL-196 (cross-platform
//       EncryptLocalData guard, Q-16); 01 DATA-032, 034, 040, 042, 048, 070, 080, DATA-179; 06 BUILD-145 B1, BUILD-A25,
//       A27; DECISIONS 01 Q-4 (current password required), Q-5 (copy into AA folder / use in place), D-14 (F1's
//       `saveTo` stamps only the copy); ARCHITECTURE.md §6.2, §6.3, §6.6, §7.8.
import Foundation

/// The data-side half of W-SHELL's File / Tools flows: everything that touches `DataStore`, `SettingsStore`,
/// `PasswordService` or `ItemLockService`. The AA target adds panels, alerts and status lines around these calls
/// (`ShellFlows`), so the behaviour that matters on disk is unit-tested here.
@MainActor
public enum ShellXDataFlows {
    // MARK: Save a Copy As JSON (SHELL-061 / DATA-032)

    /// Writes a plaintext copy of the live model to `url` (normalised paths, SchemaVersion ≥ 1, `LastModified = now`
    /// on the COPY only — F1's D-14 fix). The active data file, the live stamp and the dirty flag are untouched.
    public static func saveCopy(_ store: AppStore, to url: URL) throws {
        try store.dataStore.saveTo(store.data, url: url)
    }

    // MARK: Encrypt local data file (SHELL-065 / DATA-070)

    /// Persists `EncryptLocalData`, stamps `LastModified = now` and rewrites the active data file in the new form
    /// (only files inside AppFolder are ever encrypted; DATA-071). Throws the save error; the setting keeps the new
    /// value either way (Windows reverts the checkmark to the stored setting, which is already the new one).
    public static func setEncryptLocalData(_ on: Bool, store: AppStore) throws {
        store.dataStore.settings.setEncryptLocalData(on)
        try store.save()
    }

    /// SHELL-196 / 03 BD Q-16 (Mac guard): the setting is on, the active data file inside AppFolder is plaintext on
    /// disk and this Mac has no local-data key yet — the setting came from another computer.
    public nonisolated static func needsForeignEncryptionPrompt(settingOn: Bool, fileClass: LocalEncryption.FileClass?,
                                                                hasLocalKey: Bool) -> Bool {
        settingOn && fileClass == .plain && !hasLocalKey
    }

    /// Evaluates the guard against the real folder and Keychain (a Keychain refusal never prompts: the encrypted
    /// write reports its own error). No key is created.
    public static func foreignEncryptionPromptNeeded(_ dataStore: DataStore) -> Bool {
        let file = dataStore.currentDataFile
        guard dataStore.settings.values.encryptLocalData, dataStore.isUnderAppFolder(file) else { return false }
        guard let cls = fileClass(of: file) else { return false }
        let hasKey: Bool
        do { hasKey = try LocalEncryption.key(secrets: dataStore.secrets, create: false) != nil } catch { return false }
        return needsForeignEncryptionPrompt(settingOn: true, fileClass: cls, hasLocalKey: hasKey)
    }

    /// What the active data file looks like on disk (Settings ▸ Security): nil when it does not exist yet.
    public nonisolated static func fileClass(of url: URL) -> LocalEncryption.FileClass? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 16), !head.isEmpty else { return nil }
        return LocalEncryption.classify(head)
    }

    /// Settings ▸ Security "On disk" line for the active data file.
    public static func onDiskDescription(_ dataStore: DataStore) -> String {
        let file = dataStore.currentDataFile
        // DATA-071: files outside AppFolder are never encrypted.
        guard dataStore.isUnderAppFolder(file) else { return "External file — never encrypted" }
        switch fileClass(of: file) {
        case .none: return "Not written yet"
        case .some(.plain): return "Plaintext"
        case .some(.mac): return "Encrypted with this Mac's Keychain key"
        case .some(.windowsDPAPI): return "Encrypted on Windows (DPAPI) — unreadable on this Mac"
        }
    }

    // MARK: App identity (SHELL-068 / DATA-048 / BUILD-145 B1, BUILD-A25, A27)

    /// Blank (`IsNullOrWhiteSpace` on the raw value) → this Mac's name, else trimmed; persisted per machine. Returns the
    /// STORED identity — the status line interpolates the resolved value (BUILD-A27).
    @discardableResult
    public static func setAppIdentity(_ raw: String, settings: SettingsStore) -> String {
        settings.setAppIdentity(raw)
        return settings.appIdentity
    }

    // MARK: Export text only (SHELL-072 / DATA-042)

    /// Persists `TextOnlyExport`; returns the status line.
    @discardableResult
    public static func setTextOnlyExport(_ on: Bool, settings: SettingsStore) -> String {
        settings.setTextOnlyExport(on)
        return ShellXText.textOnlyStatus(on)
    }

    // MARK: Password (SHELL-101 / DATA-080, DECISIONS 01 Q-4) and Lock now (SHELL-102)

    /// The password sheet's OK: an empty password does nothing (Windows `IsNullOrEmpty → return`, returns false);
    /// otherwise `PasswordService.setPassword` (fresh salt, PBKDF2, one joint settings write, session unlocked),
    /// which requires the current password when one exists. With `store`, legacy `enc:` bodies are migrated first
    /// (01 §8.1 D-5). Returns the migration result when a password was set, nil when nothing was done.
    @discardableResult
    public static func setPassword(_ new: String, current: String?, passwords: PasswordService,
                                   store: AppStore? = nil) throws(PasswordError) -> LegacyBodyMigration? {
        guard !new.isEmpty else { return nil }
        return try passwords.setPassword(new, current: current, migratingLegacyBodiesIn: store)
    }

    /// Forgets the app-password session and every per-item unlock; returns the status line. Views observing
    /// `ItemLockService.unlockedIDs` re-gate their current selection in place (W-HIER, DECISIONS 04 Q-D).
    @discardableResult
    public static func lockNow(passwords: PasswordService, locks: ItemLockService) -> String {
        passwords.lock()
        locks.relockAll()
        return ShellXText.lockedNow
    }

    // MARK: Import from file (SHELL-063 / DATA-034, DECISIONS 01 Q-5, DATA-179)

    /// Whether Import from File must ask "Copy into AA Folder" / "Use in Place": every file except the default
    /// data file itself (adopting that one in place is the only meaningful choice).
    public static func asksImportPlacement(for url: URL, dataStore: DataStore) -> Bool {
        url.standardizedFileURL.path != dataStore.defaultDataFile.standardizedFileURL.path
    }

    /// Whether "Use in Place" needs the per-user external-file lock (DATA-179): files outside AppFolder only.
    public static func needsExternalLock(for url: URL, dataStore: DataStore) -> Bool {
        !dataStore.isUnderAppFolder(url)
    }

    /// DATA-179: a guard result that cancels the import ("That file is already open in another copy of AA.").
    /// `.unguarded` (the lock can't be taken on this volume) lets the import continue, like a launch does.
    public nonisolated static func externalLockRefuses(_ result: InstanceGuardResult) -> Bool {
        switch result {
        case .editor, .unguarded: return false
        case .runningHere, .otherUser, .remote, .sameUserNoApp: return true
        }
    }

    // MARK: Bundles (SHELL-070, SHELL-071, SHELL-185)

    /// DATA-040: an export destination inside AppFolder is refused.
    public static func exportDestinationAllowed(_ url: URL, dataStore: DataStore) -> Bool {
        !dataStore.isUnderAppFolder(url)
    }

    /// BD.3.7: documents AA accepts from Finder (Open With, double-click, Dock drop): `.aaz` and `.zip`.
    public nonisolated static func isBundleDocument(_ url: URL) -> Bool {
        ["aaz", "zip"].contains(url.pathExtension.lowercased())
    }
}
