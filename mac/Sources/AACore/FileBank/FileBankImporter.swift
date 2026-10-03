// Spec: 05 CONT-082 (Add File: copy into files/, Name = original file name, Kind = classify, Added = now), CONT-083
//       (Add Folder / plain drop of a folder: every file below it, flattened), CONT-084 (link in place: files),
//       CONT-085 (drops: copy vs link in place; a folder linked in place is ONE "{name}  (folder)" entry, Kind Other),
//       CONT-097 (copies stored relative, links verbatim), §8 K-8 (skip Finder litter), §8 K-9 (Mac: a failed copy is
//       reported with "Link in place instead", never silently stored as an absolute path), DECISIONS 05 (packages are
//       zipped into ONE files/ entry by `AttachmentStore.importFile`), 05 §6.9 (Windows-openable stored form for
//       links in place).
import Foundation

/// The algorithms behind `FileBankOperations.addFiles` (AA target), over injectable attachment primitives so they
/// are testable without W-PERSIST's store. The defaults are W-PERSIST's `AttachmentStore` contract.
@MainActor public struct FileBankImporter {
    public struct Failure: Equatable, Sendable {
        public var url: URL
        public var message: String
        public init(url: URL, message: String) { self.url = url; self.message = message }
    }

    public struct Outcome {
        public var added: [FileItem] = []
        public var failures: [Failure] = []
        public init() {}
    }

    public var dataStore: DataStore
    /// `AttachmentStore.importFile` — returns the stored `files/<32hex>_<leaf>` path.
    public var importFile: (URL) throws -> String
    /// `AttachmentStore.classify(path:)` (CONT-081 table).
    public var classify: (String) -> FileKind
    /// The per-Mac path-mapping table (`PathMapper.shared.mappings`) used in reverse for links in place.
    public var mappings: [PathMapping]

    public init(dataStore: DataStore, importFile: ((URL) throws -> String)? = nil, classify: ((String) -> FileKind)? = nil,
                mappings: [PathMapping]? = nil) {
        self.dataStore = dataStore
        self.importFile = importFile ?? { url in try AttachmentStore.importFile(dataStore, from: url) }
        self.classify = classify ?? { AttachmentStore.classify(path: $0) }
        self.mappings = mappings ?? PathMapper.shared.mappings
    }

    // MARK: Copies (CONT-082, CONT-083, plain drop)

    /// Imports copies: a plain folder contributes every importable file below it (flattened, K-8 litter skipped,
    /// packages as one zipped entry each); a file or package is imported itself. A file that already lives in this
    /// data folder's `files/` (dragged from another file bank) is referenced, not duplicated. Entries are appended
    /// to `container.files` in order; failures are collected (the import continues with the next file, and a
    /// folder that cannot be read stops that folder only — files already imported stay, CONT-083).
    public func importCopies(_ urls: [URL], into container: Container, now: NetDateTime) -> Outcome {
        var out = Outcome()
        for url in urls {
            if FileBankFolderScan.isPlainDirectory(url) {
                let files: [URL]
                do { files = try FileBankFolderScan.importableFiles(in: url) } catch {
                    out.failures.append(Failure(url: url, message: error.localizedDescription))
                    continue
                }
                for f in files { importOne(f, into: container, now: now, outcome: &out) }
            } else if FileManager.default.fileExists(atPath: url.path) {
                importOne(url, into: container, now: now, outcome: &out)
            }
        }
        return out
    }

    private func importOne(_ url: URL, into container: Container, now: NetDateTime, outcome: inout Outcome) {
        if let existing = storedPathInsideFilesFolder(url) {
            let item = FileBankEntries.copy(name: displayNameOfStoredLeaf(url.lastPathComponent), storedPath: existing,
                                            kind: classify(url.path), added: now)
            container.files.append(item)
            outcome.added.append(item)
            return
        }
        do {
            let stored = try importFile(url)
            var name = url.lastPathComponent
            let packaged = FileBankFolderScan.isPackage(url) || FileBankFolderScan.isPlainDirectory(url)
            if packaged, stored.lowercased().hasSuffix(".zip"), !name.lowercased().hasSuffix(".zip") { name += ".zip" }
            let item = FileBankEntries.copy(name: name, storedPath: stored, kind: classify(packaged ? stored : url.path),
                                            added: now)
            container.files.append(item)
            outcome.added.append(item)
        } catch {
            outcome.failures.append(Failure(url: url, message: error.localizedDescription))
        }
    }

    /// `files/<leaf>` when `url` is a file directly inside this data folder's flat `files/` folder.
    func storedPathInsideFilesFolder(_ url: URL) -> String? {
        let folder = dataStore.filesFolder.standardizedFileURL.resolvingSymlinksInPath().path
        let parent = url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent().path
        guard parent == folder || parent == FileBankLinkPath.trimTrailingSlash(folder) else { return nil }
        return "files/" + url.lastPathComponent
    }

    /// `0123…cdef_Manual.pdf` → `Manual.pdf` (the 32-hex import prefix is not part of the display name).
    public nonisolated static func displayName(ofStoredLeaf leaf: String) -> String {
        let u = Array(leaf.utf16)
        guard u.count > 33, u[32] == 0x5F else { return leaf }
        let hex = u.prefix(32).allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
        return hex ? String(decoding: u.dropFirst(33), as: UTF16.self) : leaf
    }

    private func displayNameOfStoredLeaf(_ leaf: String) -> String { Self.displayName(ofStoredLeaf: leaf) }

    // MARK: Links in place (CONT-084, CONT-085 with the modifier)

    /// Each existing file (or package) becomes a live entry named after the file; each plain folder becomes ONE
    /// `"{folder}  (folder)"` entry of Kind Other. Missing paths are skipped (Windows checks existence too).
    public func linkInPlace(_ urls: [URL], into container: Container, now: NetDateTime) -> [FileItem] {
        var added: [FileItem] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            let stored = FileBankLinkPath.storedPath(for: url, mappings: mappings)
            let item: FileItem
            if isDir.boolValue && !FileBankFolderScan.isPackage(url) {
                item = FileBankEntries.linkedFolder(folderName: FileBankEntries.folderName(for: url), storedPath: stored,
                                                    added: now)
            } else {
                item = FileBankEntries.linkedFile(name: url.lastPathComponent, storedPath: stored,
                                                  kind: classify(url.path), added: now)
            }
            container.files.append(item)
            added.append(item)
        }
        return added
    }

    // MARK: Pasted / dropped bytes (DECISIONS 05 via W-CONT)

    /// `FileBankOperations.addImported`: an entry for bytes already stored by `AttachmentStore.importData`.
    public func addImported(storedPath: String, displayName: String, to container: Container,
                            now: NetDateTime) -> FileItem {
        let kindSource = FileBankDisplay.pathExtension(displayName).isEmpty ? storedPath : displayName
        let item = FileBankEntries.copy(name: displayName, storedPath: storedPath, kind: classify(kindSource), added: now)
        container.files.append(item)
        return item
    }
}

/// Thrown by `FileBankOperations.addFiles` when some copies failed; the entries that worked are already added.
public struct FileBankImportError: Error, LocalizedError {
    public var failures: [FileBankImporter.Failure]
    public var added: Int
    public init(failures: [FileBankImporter.Failure], added: Int) { self.failures = failures; self.added = added }

    public var errorDescription: String? {
        FileBankText.importFailed(failures.map { $0.url.lastPathComponent },
                                  failures.first?.message ?? "")
    }
}
