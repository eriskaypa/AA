// PLACEHOLDER(W-PERSIST) — contract: ARCHITECTURE.md §6.6
// Spec: 01 MP (DATA-170…186) as simplified by DECISIONS ("a second launch activates the running instance").
// Compiling stub created by F1; W-PERSIST replaces this file in place. The stub always answers `.editor` and holds
// no lock (ARCH §11).
import Foundation

public enum InstanceGuardResult: Sendable, Equatable {
    case editor, unguarded(String), runningHere(pid: Int32), otherUser(String),
         remote(host: String, lastSeen: Date, stale: Bool)
}

@MainActor public enum InstanceGuard {
    public static func acquire(appFolder: URL) -> InstanceGuardResult {
        // PLACEHOLDER(W-PERSIST)
        .editor
    }

    /// `runningHere` → activate the running AA, forward the documents, quit.
    public static func forwardToRunningInstance(pid: Int32, documents: [URL]) -> Bool {
        // PLACEHOLDER(W-PERSIST)
        false
    }

    public static func listenForForwardedDocuments(_ handler: @escaping @MainActor ([URL]) -> Void) {
        // PLACEHOLDER(W-PERSIST)
    }

    public static func release() {
        // PLACEHOLDER(W-PERSIST)
    }

    /// DATA-179: per-user flock on ~/Library/Application Support/AA-locks/external-{sha256}.lock.
    public static func acquireExternal(fileURL: URL) -> InstanceGuardResult {
        // PLACEHOLDER(W-PERSIST)
        .editor
    }

    /// When the active file goes back to the default.
    public static func releaseExternal() {
        // PLACEHOLDER(W-PERSIST)
    }
}
