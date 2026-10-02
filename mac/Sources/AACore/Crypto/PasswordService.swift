// Spec: 01 §H (DATA-080–084), §3.13, §4.7, DECISIONS Q-1 (master password), Q-4 (current password required to
//       change); 05 CONT-007 (session decryption of legacy bodies); ARCHITECTURE.md §6.3.
import Foundation
import Observation

public enum PasswordError: Error, Sendable, Equatable {
    case tooShort, mismatch, wrongCurrentPassword

    /// Windows texts (01 DATA-080).
    public var message: String {
        switch self {
        case .tooShort: return "Password must be at least 4 characters."
        case .mismatch: return "Passwords do not match."
        case .wrongCurrentPassword: return "Wrong password."
        }
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
    public func setPassword(_ new: String, current: String?) throws(PasswordError) {
        if hasPassword {
            guard let current, verify(current) else { throw .wrongCurrentPassword }
        }
        guard new.utf16.count >= 4 else { throw .tooShort }
        let salt = PasswordHashing.newSalt()
        let hash = PasswordHashing.hash(password: new, salt: salt)
        settings.setPassword(hash: NetBase64.encode(hash), salt: NetBase64.encode(salt))
        currentPassword = new
        unlockedAtGeneration = settings.reloadGeneration
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
