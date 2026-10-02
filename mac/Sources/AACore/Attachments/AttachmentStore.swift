// PLACEHOLDER(W-PERSIST) — contract: ARCHITECTURE.md §6.6
// Spec: 01 §F (DATA-060…068), §3.7, §6.6; 05 §3.5–3.6, CONT-081; DECISIONS 05 (packages zipped, pasted images).
// Compiling stub created by F1; W-PERSIST replaces this file in place. ARCH §11 requires `normalizeFilePaths` to be
// a no-op until then; imports throw (nothing written); the other stubs return benign defaults.
import Foundation

@MainActor public enum AttachmentStore {
    /// "files/<32hex>_<leaf>"; a directory or macOS package is zipped into ONE entry `files/<32hex>_<name>.zip`.
    public static func importFile(_ ds: DataStore, from source: URL) throws -> String {
        // PLACEHOLDER(W-PERSIST)
        throw PersistPlaceholderError.notAvailable
    }

    /// Pasted / dropped bytes without a file URL (DECISIONS 05) → `files/<32hex>_<windowsSafeLeaf(name)>`.
    public static func importData(_ ds: DataStore, _ data: Data, suggestedName: String) throws -> String {
        // PLACEHOLDER(W-PERSIST)
        throw PersistPlaceholderError.notAvailable
    }

    /// Stub: the stored text unchanged ("" for nil).
    public static func resolveFilePath(_ ds: DataStore, stored: String?) -> String {
        // PLACEHOLDER(W-PERSIST)
        stored ?? ""
    }

    /// Called by `DataStore` on every load and before every save (01 §3.7). Stub: no-op (ARCH §11).
    public static func normalizeFilePaths(_ ds: DataStore, data: AppData) {
        // PLACEHOLDER(W-PERSIST)
    }

    /// Bundle import / Flash Sync apply: rewrite another workstation's absolute `files\` paths.
    public static func migrateLegacyAbsolutePaths(_ ds: DataStore, data: AppData) {
        // PLACEHOLDER(W-PERSIST)
    }

    /// DATA-066 table.
    public nonisolated static func classify(path: String) -> FileKind {
        // PLACEHOLDER(W-PERSIST)
        .other
    }

    /// 01 §6.6.
    public nonisolated static func windowsSafeLeaf(_ name: String) -> String {
        // PLACEHOLDER(W-PERSIST)
        ""
    }

    /// DATA-068.
    public static func enumerateContainers(_ data: AppData) -> [Container] {
        // PLACEHOLDER(W-PERSIST)
        []
    }
}
