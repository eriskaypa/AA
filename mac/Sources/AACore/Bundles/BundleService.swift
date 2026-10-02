// PLACEHOLDER(W-PERSIST) — contract: ARCHITECTURE.md §6.6
// Spec: 01 §D, §3.10 (ZIP bundles, `.aaz`, `source.json`, DataOnly), DATA-040…049. Compiling stub created by F1;
// W-PERSIST replaces this file in place. Import/export stubs THROW (nothing is read or written); peeks return nil
// (ARCH §11).
import Foundation
import CryptoKit

public enum ImportKind: Sendable { case withAttachments, dataOnly }

@MainActor public enum BundleService {
    /// Zips off-main.
    public static func exportFolderToZip(_ ds: DataStore, to url: URL, includeAttachments: Bool) async throws {
        // PLACEHOLDER(W-PERSIST)
        throw PersistPlaceholderError.notAvailable
    }

    public static func importBundleSmart(_ ds: DataStore, from url: URL) throws -> ImportKind {
        // PLACEHOLDER(W-PERSIST)
        throw PersistPlaceholderError.notAvailable
    }

    public static func importSharedBundle(_ ds: DataStore, from url: URL) throws {
        // PLACEHOLDER(W-PERSIST)
        throw PersistPlaceholderError.notAvailable
    }

    /// DATA-047 (not wired to UI).
    public static func importFolderFromZipLegacy(_ ds: DataStore, from url: URL) throws {
        // PLACEHOLDER(W-PERSIST)
        throw PersistPlaceholderError.notAvailable
    }

    public nonisolated static func peekZipLastModified(_ url: URL) -> NetDateTime? {
        // PLACEHOLDER(W-PERSIST)
        nil
    }

    public nonisolated static func peekFileLastModified(_ url: URL, key: SymmetricKey?) -> NetDateTime? {
        // PLACEHOLDER(W-PERSIST)
        nil
    }

    public nonisolated static func peekBundleSource(_ url: URL) -> BundleSource? {
        // PLACEHOLDER(W-PERSIST)
        nil
    }

    public static func peekZipData(_ url: URL, dataStore: DataStore) -> AppData? {
        // PLACEHOLDER(W-PERSIST)
        nil
    }

    public nonisolated static func machineName() -> String {
        // PLACEHOLDER(W-PERSIST)
        ""
    }

    /// "aa-data-{yyyyMMdd-HHmm}.zip".
    public static let exportDefaultName: (NetDateTime) -> String = { _ in
        // PLACEHOLDER(W-PERSIST)
        ""
    }

    public static let sharedDefaultName = "aa-shared.zip"
}
