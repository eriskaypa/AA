// PLACEHOLDER(W-DRIVE) — contract: ARCHITECTURE.md §6.8
// Spec: 14 §6.3, OC-34 (Google token in the Keychain, its own item). Compiling stub created by F1; W-DRIVE replaces
// this file in place. The stubs report no token (ARCH §11).
import Foundation

public enum GoogleTokenStore {
    @MainActor public static func hasToken(_ ds: DataStore) -> Bool {
        // PLACEHOLDER(W-DRIVE)
        false
    }

    @MainActor public static func needsReconsentForWholeDrive(_ ds: DataStore) -> Bool {
        // PLACEHOLDER(W-DRIVE)
        false
    }
}
