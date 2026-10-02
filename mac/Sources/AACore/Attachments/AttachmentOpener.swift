// PLACEHOLDER(W-PERSIST) — contract: ARCHITECTURE.md §6.6
// Spec: ARCH §9.4 (open / reveal resolution table), 05 §6.9, OC-12. Compiling stub created by F1; W-PERSIST
// replaces this file in place. The stubs open nothing (ARCH §11).
import Foundation

public enum OpenOutcome: Sendable, Equatable {
    case opened, notFound(String), windowsPathUnmapped(String), failed(String)
}

@MainActor public enum AttachmentOpener {
    public static func url(forStored stored: String, isLink: Bool, dataStore: DataStore) -> URL? {
        // PLACEHOLDER(W-PERSIST)
        nil
    }

    /// NSWorkspace.
    public static func open(stored: String, isLink: Bool, dataStore: DataStore) -> OpenOutcome {
        // PLACEHOLDER(W-PERSIST)
        .failed("Opening attachments is not available in this build yet.")
    }

    public static func revealInFinder(stored: String, dataStore: DataStore) -> OpenOutcome {
        // PLACEHOLDER(W-PERSIST)
        .failed("Showing attachments in Finder is not available in this build yet.")
    }

    /// `www.` → `https://`, `x@y` → `mailto:`.
    public static func normalizeWebLink(_ s: String) -> URL? {
        // PLACEHOLDER(W-PERSIST)
        nil
    }
}
