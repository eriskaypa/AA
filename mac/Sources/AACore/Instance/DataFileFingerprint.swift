// PLACEHOLDER(W-PERSIST) — contract: ARCHITECTURE.md §6.6
// Spec: 01 DATA-180, §MP.3.4 (fingerprint dev/ino/size/mtime/SHA-256, directory watcher). Compiling stub created by
// F1; W-PERSIST replaces this file in place. The stub guard allows every write and watches nothing (ARCH §11).
import Foundation

public struct DataFileConflict: Sendable {
    public enum Kind: Sendable { case changed, deleted, unreadable(reason: String) }
    public var kind: Kind
    public var fileName: String
    public var ourTime: String
    public var theirTime: String
    public var theirBytes: Data?

    public init(kind: Kind, fileName: String, ourTime: String, theirTime: String, theirBytes: Data?) {
        self.kind = kind; self.fileName = fileName; self.ourTime = ourTime; self.theirTime = theirTime
        self.theirBytes = theirBytes
    }
}

/// "Review Changes…" is resolved inside the host (DATA-100 sheet → one of these).
public enum DataFileConflictChoice: Sendable { case keepMine, useTheirs, stopEditingHere }

/// Implemented by F3's AppEnvironment: presents the DATA-180 sheet on the main window and returns the choice.
@MainActor public protocol DataFileConflictHost: AnyObject {
    func presentConflict(_ c: DataFileConflict) async -> DataFileConflictChoice
}

/// DATA-180 implementation of F1's `DataFileWriteGuard` (nonisolated witnesses, lock-protected state).
@MainActor public final class DataFileFingerprint: DataFileWriteGuard {
    private let store: AppStore
    private weak var host: DataFileConflictHost?

    public init(store: AppStore, host: DataFileConflictHost) {
        self.store = store; self.host = host
    }

    public func start() {
        // PLACEHOLDER(W-PERSIST)
        _ = store
    }

    public func stop() {
        // PLACEHOLDER(W-PERSIST)
    }

    public nonisolated func shouldWrite(to url: URL) -> Bool {
        // PLACEHOLDER(W-PERSIST)
        true
    }

    public nonisolated func didWrite(to url: URL, bytes: Data) {
        // PLACEHOLDER(W-PERSIST)
    }

    public nonisolated func didLoad(from url: URL, bytes: Data) {
        // PLACEHOLDER(W-PERSIST)
    }
}
