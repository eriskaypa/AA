// Spec: 01 §H (DATA-080–084), §3.13, §4.7, DECISIONS Q-1 (master password), Q-4 (current password required to
//       change); 05 CONT-007 (session decryption of legacy bodies); ARCHITECTURE.md §6.3.
import Foundation
import Observation

public enum PasswordError: Error, Sendable, Equatable {
    case tooShort, mismatch, wrongCurrentPassword
    /// 01 §8.1 D-5 (Mac only): legacy `enc:` bodies were decrypted for migration but the data file could not be
    /// saved, so the password (and salt) were left unchanged. The associated value is the save error text.
    case legacyBodiesNotSaved(String)

    /// Windows texts (01 DATA-080); the D-5 text is Mac-only.
    public var message: String {
        switch self {
        case .tooShort: return "Password must be at least 4 characters."
        case .mismatch: return "Passwords do not match."
        case .wrongCurrentPassword: return "Wrong password."
        case .legacyBodiesNotSaved(let reason):
            return "The password was not changed. Notes encrypted by an older AA build were decrypted, but the data "
                + "file could not be saved, so they still need the current password: \(reason)"
        }
    }
}

/// What a password change did to the legacy `enc:` container bodies (01 §8.1 D-5).
public struct LegacyBodyMigration: Sendable, Equatable {
    /// Bodies decrypted with the old password + old salt and written back as plaintext XAML (CONT-007 form).
    public var migrated: Int
    /// Bodies no candidate password could decrypt; the new salt makes them undecryptable for good.
    public var undecryptable: Int

    public init(migrated: Int = 0, undecryptable: Int = 0) {
        self.migrated = migrated; self.undecryptable = undecryptable
    }

    public static let none = LegacyBodyMigration()

    /// Warning shown after (or before) a password change that orphans `undecryptable` bodies; nil when none.
    public static func orphanWarning(count: Int) -> String? {
        guard count > 0 else { return nil }
        let notes = count == 1 ? "1 note" : "\(count) notes"
        return "\(notes) encrypted by an older AA build could not be decrypted with the current password. "
            + "After the password change \(count == 1 ? "it" : "they") can no longer be opened with any password."
    }
}

/// The app password (settings `PasswordHash` / `PasswordSalt`) and its in-memory session. Every settings reload
/// (LoadSettings) forgets the session password, like Windows.
@MainActor @Observable
public final class PasswordService {
    public let settings: SettingsStore
    @ObservationIgnored private var currentPassword: String?
    private var unlockedAtGeneration: Int?

    public init(settings: SettingsStore) { self.settings = settings }

    private var saltBytes: Data? {
        guard let s = settings.values.passwordSalt, !s.isEmpty else { return nil }
        return NetBase64.decode(s)
    }

    /// Hash and salt both present (an undecodable salt counts as no password, like Windows' failed LoadFrom).
    public var hasPassword: Bool {
        guard let h = settings.values.passwordHash, !h.isEmpty else { return false }
        return saltBytes != nil
    }

    public var isUnlocked: Bool {
        currentPassword != nil && unlockedAtGeneration == settings.reloadGeneration
    }

    /// The master password (ordinal) always verifies; otherwise PBKDF2 against the stored hash in constant time.
    public func verify(_ password: String) -> Bool {
        if PasswordHashing.isMaster(password) { return true }
        guard hasPassword, let salt = saltBytes, let stored = NetBase64.decode(settings.values.passwordHash ?? "") else {
            return false
        }
        return ConstantTime.equals(PasswordHashing.hash(password: password, salt: salt), stored)
    }

    public func unlock(_ password: String) -> Bool {
        guard verify(password) else { return false }
        currentPassword = password
        unlockedAtGeneration = settings.reloadGeneration
        return true
    }

    /// Tools ▸ Lock Now (the caller also calls `ItemLockService.relockAll`).
    public func lock() {
        currentPassword = nil
        unlockedAtGeneration = nil
    }

    /// Sets a new password: fresh 16-byte salt, PBKDF2 hash, one joint settings write, session unlocked with it.
    /// DECISIONS 01 Q-4: when a password exists, `current` must verify (the master password is accepted).
    ///
    /// 01 §8.1 D-5 fix: re-salting orphans every legacy `enc:` body, so when `store` is given, every live container's
    /// `enc:` body is first decrypted with the OLD salt and the verified current / session password and written back
    /// as plaintext (exactly the CONT-007 open-time migration: body = plaintext, `IsLocked` cleared), then the data
    /// file is saved before the new salt is written. A save that cannot happen (read-only / safe-mode instance,
    /// paused writes, write error) throws `.legacyBodiesNotSaved` and leaves the password and salt unchanged.
    /// Bodies no candidate decrypts are counted in `undecryptable` for the caller's warning
    /// (`LegacyBodyMigration.orphanWarning`). Trash payloads (`PayloadJson`) are not rewritten.
    @discardableResult
    public func setPassword(_ new: String, current: String?,
                            migratingLegacyBodiesIn store: AppStore? = nil) throws(PasswordError) -> LegacyBodyMigration {
        if hasPassword {
            guard let current, verify(current) else { throw .wrongCurrentPassword }
        }
        guard new.utf16.count >= 4 else { throw .tooShort }
        var result = LegacyBodyMigration.none
        if let store {
            let plan = legacyBodyPlan(in: store, current: current)
            result = LegacyBodyMigration(migrated: plan.decrypted.count, undecryptable: plan.undecryptable)
            if !plan.decrypted.isEmpty {
                if store.suspendSaving {
                    throw .legacyBodiesNotSaved("this instance does not save its data (read-only or safe mode).")
                }
                for (container, plain) in plan.decrypted {
                    container.richTextXaml = plain
                    container.isLocked = false
                }
                store.markDirty()
                do { try store.save() } catch { throw .legacyBodiesNotSaved(error.localizedDescription) }
            }
        }
        let salt = PasswordHashing.newSalt()
        let hash = PasswordHashing.hash(password: new, salt: salt)
        settings.setPassword(hash: NetBase64.encode(hash), salt: NetBase64.encode(salt))
        currentPassword = new
        unlockedAtGeneration = settings.reloadGeneration
        return result
    }

    /// D-5 pre-check for a confirmation before the change: how many live legacy `enc:` bodies neither `current` nor
    /// the session password decrypts with the present salt (0 when there are none — no key derivation then).
    public func undecryptableLegacyBodyCount(in store: AppStore, current: String?) -> Int {
        legacyBodyPlan(in: store, current: current).undecryptable
    }

    /// Decrypts every live `enc:` body (REPO-012 `allContainers`) with each candidate password (the typed current
    /// password, then the unlocked session password; keys derived once per candidate), nothing written.
    private func legacyBodyPlan(in store: AppStore, current: String?)
        -> (decrypted: [(Container, String)], undecryptable: Int) {
        let encrypted = store.allContainers().filter { LegacyBodyCrypto.isEncrypted($0.richTextXaml) }
        guard !encrypted.isEmpty else { return ([], 0) }
        guard let salt = saltBytes, !salt.isEmpty else { return ([], encrypted.count) }
        var candidates: [String] = []
        if let current, !current.isEmpty { candidates.append(current) }
        if isUnlocked, let pw = currentPassword, !candidates.contains(where: { Ordinal.equals($0, pw) }) {
            candidates.append(pw)
        }
        let keys = candidates.map { LegacyBodyCrypto.keys(password: $0, salt: salt) }
        var decrypted: [(Container, String)] = []
        var undecryptable = 0
        for c in encrypted {
            if let plain = keys.lazy.compactMap({ LegacyBodyCrypto.decrypt(c.richTextXaml, keys: $0) }).first {
                decrypted.append((c, plain))
            } else {
                undecryptable += 1
            }
        }
        return (decrypted, undecryptable)
    }

    /// The password / lock dialogs' validation (Views/PasswordWindow.xaml.cs:40, ItemLockWindow.xaml.cs:34; 01 DATA-080,
    /// 04 §7.8): empty → "Password cannot be empty."; fewer than 4 UTF-16 units → "Password must be at least 4
    /// characters."; confirmation differs (ordinal) → "Passwords do not match."; nil when valid.
    public nonisolated static func validationMessage(password: String, confirm: String) -> String? {
        if password.isEmpty { return "Password cannot be empty." }
        if password.utf16.count < 4 { return PasswordError.tooShort.message }
        if !Ordinal.equals(password, confirm) { return PasswordError.mismatch.message }
        return nil
    }

    /// Decrypts a legacy `enc:` body with the session password; nil when locked, no salt, or no match (never guesses).
    public func decryptLegacyBody(_ blob: String) -> String? {
        guard isUnlocked, let pw = currentPassword, let salt = settings.values.passwordSalt else { return nil }
        return LegacyBodyCrypto.decrypt(blob, password: pw, saltBase64: salt)
    }
}
