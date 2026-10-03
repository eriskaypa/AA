// Spec: 12 SIRE-038, §4.3, §6.9 (Keychain generic password, service "{bundleID}.gemini", account "GeminiApiKey", not
//       synchronizable; clearing DELETES the item — fixes Q-5), 06 BUILD-145 B2 / BUILD-A26 (blank = clear, else the
//       trimmed value; no fallback), DECISIONS 12 (a key found in settings.json is imported ONCE; the settings key is
//       preserved untouched), 01 DATA-215 (Keychain registry: `Identifiers.Keychain.gemini`); ARCHITECTURE.md §6.8.
import Foundation

/// The Gemini API key, held in the login Keychain (never in any file the Mac writes).
@MainActor public final class GeminiKeyStore {
    private let secrets: SecretStore
    private let settings: SettingsStore
    private let preferences: MacPreferences

    /// Set once the one-time import from settings.json has run (`aa.sire.geminiImported`).
    public static let importedKey = MacPreferences.Key("aa.sire.geminiImported")
    static let item = Identifiers.Keychain.gemini

    public init(secrets: SecretStore, settings: SettingsStore) {
        self.secrets = secrets; self.settings = settings; self.preferences = .shared
    }

    /// Test seam: an isolated preferences domain.
    public init(secrets: SecretStore, settings: SettingsStore, preferences: MacPreferences) {
        self.secrets = secrets; self.settings = settings; self.preferences = preferences
    }

    /// True when a non-blank key is stored.
    public var hasKey: Bool { !NetText.isBlank(key()) }

    /// The stored key, or nil (also nil when the Keychain cannot be read).
    public func key() -> String? {
        guard let data = try? secrets.read(service: Self.item.service, account: Self.item.account) else { return nil }
        let s = String(decoding: data, as: UTF8.self)
        return s.isEmpty ? nil : s
    }

    /// BUILD-A26 on the Mac: blank (`IsNullOrWhiteSpace`) deletes the Keychain item, anything else stores the
    /// trimmed value. Throws the Keychain error (the caller reports it).
    public func setKey(_ s: String?) throws {
        if NetText.isBlank(s) {
            try secrets.delete(service: Self.item.service, account: Self.item.account)
        } else {
            try secrets.write(Data(NetText.trim(s!).utf8), service: Self.item.service, account: Self.item.account)
        }
    }

    /// DECISIONS 12: a `GeminiApiKey` carried over in settings.json is copied into the Keychain once (only when the
    /// Keychain has no key yet). The settings value itself is never modified. Later clears are permanent: the
    /// import never runs again on this Mac.
    public func importFromSettingsOnce() {
        guard !preferences.bool(Self.importedKey, default: false) else { return }
        guard let legacy = settings.values.geminiApiKey, !NetText.isBlank(legacy) else { return }   // nothing to import yet
        if !hasKey {
            do { try setKey(legacy) } catch { return }                   // retry on the next launch
        }
        preferences.set(true, Self.importedKey)
    }
}
