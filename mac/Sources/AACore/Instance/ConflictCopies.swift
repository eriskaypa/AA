// PLACEHOLDER(W-PERSIST) — contract: ARCHITECTURE.md §6.6
// Spec: 01 DATA-181 (AppFolder/conflicts/, newest 20 kept). Compiling stub created by F1; W-PERSIST replaces this
// file in place. The stub lists nothing (ARCH §11).
import Foundation

@MainActor public enum ConflictCopies {
    nonisolated public struct Entry: Sendable, Identifiable, Hashable {
        public var id: String { fileName }
        public var fileName: String
        public var isTheirs: Bool
        public var size: Int64
        public var lastModified: NetDateTime?

        public init(fileName: String, isTheirs: Bool, size: Int64, lastModified: NetDateTime?) {
            self.fileName = fileName; self.isTheirs = isTheirs; self.size = size; self.lastModified = lastModified
        }
    }

    public static func list(_ ds: DataStore) -> [Entry] {
        // PLACEHOLDER(W-PERSIST)
        []
    }

    public static func url(of e: Entry, _ ds: DataStore) -> URL {
        // PLACEHOLDER(W-PERSIST)
        ds.appFolder.appendingPathComponent("conflicts", isDirectory: true).appendingPathComponent(e.fileName)
    }
}
