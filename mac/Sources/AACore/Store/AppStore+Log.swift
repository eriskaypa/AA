// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §5.3
// Spec: 02 §2.I (REPO-090), 08 QUICK-154. Compiling stub created by F1; F2 replaces this file in place. The stubs
// log nothing (ARCH §11).
import Foundation

extension AppStore {
    public static let maxLogEntries = 10_000

    /// REPO-090 (name trimmed / "(unnamed)").
    public func logAdded(kind: String, name: String?, detail: String? = "") {
        // PLACEHOLDER(F2)
    }

    public func logRemoved(kind: String, name: String?, detail: String? = "") {
        // PLACEHOLDER(F2)
    }

    /// QUICK-154 (the caller confirms and saves).
    public func clearLog() {
        // PLACEHOLDER(F2)
    }
}
