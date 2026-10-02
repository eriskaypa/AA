// PLACEHOLDER(W-SIRE) — contract: ARCHITECTURE.md §6.8
// Spec: 12 §6.9, OC-35, DECISIONS 12 (Gemini key in the Keychain; a settings.json key is imported once and left
// untouched there), 06 BUILD-145 (blank clears). Compiling stub created by F1; W-SIRE replaces this file in place.
// The stub holds no key, never touches the Keychain and refuses to store one (ARCH §11).
import Foundation

@MainActor public final class GeminiKeyStore {
    private let secrets: SecretStore
    private let settings: SettingsStore

    public init(secrets: SecretStore, settings: SettingsStore) {
        self.secrets = secrets; self.settings = settings
    }

    public var hasKey: Bool {
        // PLACEHOLDER(W-SIRE)
        false
    }

    public func key() -> String? {
        // PLACEHOLDER(W-SIRE)
        nil
    }

    /// Blank clears.
    public func setKey(_ s: String?) throws {
        // PLACEHOLDER(W-SIRE)
        _ = (secrets, settings)
        throw SireGeminiKeyPlaceholderError.notAvailable
    }

    /// DECISIONS 12.
    public func importFromSettingsOnce() {
        // PLACEHOLDER(W-SIRE)
    }
}

/// Stub support only — delete with this placeholder.
enum SireGeminiKeyPlaceholderError: Error, LocalizedError {
    case notAvailable
    var errorDescription: String? { "Storing the Gemini API key is not available in this build yet." }
}
