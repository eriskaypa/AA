// Spec: 01 §D (DATA-041, DATA-044–047), §3.9 (peeks), §3.10 (export, smart import, shared import, legacy import,
//       IsDataOnlyBundle, AttachmentsMatch), §4.4 (source.json), §4.5 (layout), §6.6 (Finder metadata, case-insensitive
//       names), §6.7 (in-house ZIP, path traversal, no AppleDouble), §7.7 (vectors), DATA-179 (external-file lock released
//       when the active file goes back to the default), DATA-185 (NSFileCoordinator), D-3 (validate before touching
//       anything), D-13 (destination check with a trailing separator); ARCHITECTURE.md §6.6.
import Foundation
import CryptoKit

public enum ImportKind: Sendable { case withAttachments, dataOnly }

/// Errors with the Windows messages (01 §3.10).
public enum PersistBundleError: Error, LocalizedError, Sendable, Equatable {
    case destinationInsideAppFolder
    case noDataJSON
    case sharedNoDataJSON
    case invalidData(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .destinationInsideAppFolder: return "Choose a destination outside the AA data folder."
        case .noDataJSON: return "The bundle has no data.json."
        case .sharedNoDataJSON: return "The shared save bundle has no data.json."
        case .invalidData(let why): return "The bundle's data.json could not be read: \(why)"
        case .io(let why): return why
        }
    }
}

@MainActor public enum BundleService {
    /// Where staging folders are created (`AA_import_<32hex>`, `AA_shared_<32hex>`); tests may redirect it.
    static var tempRoot: URL = FileManager.default.temporaryDirectory

    // MARK: Export (DATA-041, §3.10)

    /// Zips off-main. `data.json` is the plaintext active data file as on disk (decrypted; falls back to the default
    /// file; omitted if neither exists), `files/` a recursive copy of the attachments when included (a bare `files/`
    /// entry when it is empty), `source.json` the `BundleSource` stamp. Never settings, tokens or the baseline.
    public static func exportFolderToZip(_ ds: DataStore, to url: URL, includeAttachments: Bool) async throws {
        let plan = try exportPlan(ds, to: url, includeAttachments: includeAttachments)
        try await Task.detached(priority: .userInitiated) { try plan.write() }.value
    }

    /// The synchronous variant used by the shared-save push (SHELL-126) and tests.
    public static func exportFolderToZipSync(_ ds: DataStore, to url: URL, includeAttachments: Bool) throws {
        try exportPlan(ds, to: url, includeAttachments: includeAttachments).write()
    }

    /// Everything the writer needs, snapshotted on the main actor.
    static func exportPlan(_ ds: DataStore, to url: URL, includeAttachments: Bool) throws -> PersistExportPlan {
        ds.prepareFolders()
        let dest = url.standardizedFileURL
        // D-13: compare with a trailing separator, so `…/AA2/x.zip` is not refused.
        if ds.isUnderAppFolder(dest) || dest.path == ds.appFolder.standardizedFileURL.path {
            throw PersistBundleError.destinationInsideAppFolder
        }
        var dataBytes: Data?
        let fm = FileManager.default
        for candidate in [ds.currentDataFile, ds.defaultDataFile] where fm.fileExists(atPath: candidate.path) {
            let raw = try DataStore.readRaw(candidate)
            dataBytes = try DataStore.decodeFileBytes(raw, key: try ds.keyForReading(raw))
            break
        }
        var lastModified: NetDateTime?
        if let raw = try? DataStore.readRaw(ds.currentDataFile) {
            lastModified = BundleService.peekFileLastModified(ds.currentDataFile, key: try? ds.keyForReading(raw))
        }
        let source = BundleSource(identity: ds.settings.appIdentity, machine: machineName(),
                                  writtenUtc: ds.clock.utcNow(), lastModified: lastModified,
                                  dataOnly: !includeAttachments)
        let sourceBytes = try JSONWriter.data(.object(source.toJSON(options: JSONEncodeOptions(zone: ds.clock.timeZone))))
        return PersistExportPlan(dest: dest, dataBytes: dataBytes, sourceBytes: sourceBytes,
                                 filesFolder: includeAttachments ? ds.filesFolder : nil)
    }

    // MARK: Smart import (DATA-043…045, §3.10)

    public static func importBundleSmart(_ ds: DataStore, from url: URL) throws -> ImportKind {
        ds.prepareFolders()
        let staging = tempRoot.appending(path: "AA_import_" + UUID().netN, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: staging) }
        try PersistBundleIO.extract(url, to: staging)
        let dataSrc = staging.appending(path: "data.json")
        guard FileManager.default.fileExists(atPath: dataSrc.path) else { throw PersistBundleError.noDataJSON }
        let json = try PersistBundleIO.validatedJSON(ds, dataSrc)                 // D-3: nothing touched yet
        let filesSrc = staging.appending(path: "files", directoryHint: .isDirectory)
        let dataOnly = PersistBundleIO.isDataOnlyBundle(staging: staging, filesSrc: filesSrc)
        let changed = !dataOnly && !PersistBundleIO.attachmentsMatch(bundleDir: filesSrc, localDir: ds.filesFolder)
        if changed {
            let names = try PersistBundleIO.copyTopLevelFiles(from: filesSrc, to: ds.filesFolder)
            try applyDataFile(ds, json: json)
            PersistBundleIO.sweepOrphans(ds.filesFolder, keeping: names)
        } else {
            try applyDataFile(ds, json: json)
        }
        try reloadMigrateRewrite(ds)
        return changed ? .withAttachments : .dataOnly
    }

    // MARK: Shared import (DATA-058, §3.10)

    public static func importSharedBundle(_ ds: DataStore, from url: URL) throws {
        ds.prepareFolders()
        let staging = tempRoot.appending(path: "AA_shared_" + UUID().netN, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: staging) }
        try PersistBundleIO.extract(url, to: staging)
        let dataSrc = staging.appending(path: "data.json")
        guard FileManager.default.fileExists(atPath: dataSrc.path) else { throw PersistBundleError.sharedNoDataJSON }
        let json = try PersistBundleIO.validatedJSON(ds, dataSrc)                 // D-3
        let filesSrc = staging.appending(path: "files", directoryHint: .isDirectory)
        let names = try PersistBundleIO.copyTopLevelFiles(from: filesSrc, to: ds.filesFolder)
        try applyDataFile(ds, json: json)
        if !PersistBundleIO.isDataOnlyBundle(staging: staging, filesSrc: filesSrc) {
            PersistBundleIO.sweepOrphans(ds.filesFolder, keeping: names)
        }
        try reloadMigrateRewrite(ds)
    }

    // MARK: Legacy full-wipe import (DATA-047; not wired to UI)

    /// Wipes the data folder (keeping the Google client secret and token, and never touching `.aa.lock`, DATA-170),
    /// extracts the bundle over it, deletes an extracted `settings.json`, resets the active file, migrates and
    /// rewrites (errors in that last step ignored, as on Windows).
    public static func importFolderFromZipLegacy(_ ds: DataStore, from url: URL) throws {
        let fm = FileManager.default
        let app = ds.appFolder
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        // Validate the archive before wiping anything (a torn ZIP leaves the folder untouched).
        let reader = try PersistBundleIO.openReader(url)
        let secret = try? Data(contentsOf: ds.googleClientSecretFile)
        var tokenCopy: URL?
        if fm.fileExists(atPath: ds.googleTokenFolder.path) {
            let tmp = tempRoot.appending(path: "AA_gtok_" + UUID().netN, directoryHint: .isDirectory)
            if (try? fm.copyItem(at: ds.googleTokenFolder, to: tmp)) != nil { tokenCopy = tmp }
        }
        defer { if let tokenCopy { try? fm.removeItem(at: tokenCopy) } }
        for item in (try? fm.contentsOfDirectory(at: app, includingPropertiesForKeys: nil, options: [])) ?? [] {
            if item.lastPathComponent == ".aa.lock" { continue }
            try? fm.removeItem(at: item)
        }
        try reader.extractAll(to: app, skip: PersistPaths.isFinderMetadata)
        try? fm.removeItem(at: ds.settingsFile)
        if let secret, !fm.fileExists(atPath: ds.googleClientSecretFile.path) {
            try? secret.write(to: ds.googleClientSecretFile)
        }
        if let tokenCopy, !fm.fileExists(atPath: ds.googleTokenFolder.path) {
            try? fm.copyItem(at: tokenCopy, to: ds.googleTokenFolder)
        }
        ds.setCurrentDataFile(ds.defaultDataFile)
        InstanceGuard.releaseExternal()
        if fm.fileExists(atPath: ds.defaultDataFile.path) {
            if let data = try? ds.loadFrom(ds.defaultDataFile) {
                AttachmentStore.migrateLegacyAbsolutePaths(ds, data: data)
                if let bytes = try? ds.serializeForSave(data) {
                    try? ds.persistWriteReplacing(bytes, to: ds.defaultDataFile)
                }
            }
        }
    }

    // MARK: Peeks (DATA-046, §3.9) — all return nil on any failure

    /// `data.json` (exact, root) → `LastModified`.
    public nonisolated static func peekZipLastModified(_ url: URL) -> NetDateTime? {
        PersistFileCoordination.read(url) { u in
            guard let r = try? ZipReader(url: u), let e = r.entry(named: "data.json"),
                  let d = try? r.data(for: e) else { return nil }
            return readLastModified(PersistBundleIO.stripBOM(d))
        } ?? nil
    }

    /// `LastModified` of a data file on disk (decrypting a Mac-encrypted file with `key`).
    public nonisolated static func peekFileLastModified(_ url: URL, key: SymmetricKey?) -> NetDateTime? {
        guard let raw = try? DataStore.readRaw(url), let json = try? DataStore.decodeFileBytes(raw, key: key) else { return nil }
        return readLastModified(json)
    }

    /// `source.json` → `BundleSource` (nil when absent — older bundles, some iOS bundles — or unreadable).
    public nonisolated static func peekBundleSource(_ url: URL) -> BundleSource? {
        PersistFileCoordination.read(url) { u in
            guard let r = try? ZipReader(url: u), let e = r.entry(named: "source.json"),
                  let d = try? r.data(for: e) else { return nil }
            return parseBundleSource(PersistBundleIO.stripBOM(d))
        } ?? nil
    }

    /// `PeekBundleIdentity`.
    public nonisolated static func peekBundleIdentity(_ url: URL) -> String? { peekBundleSource(url)?.identity }

    /// `data.json` → `AppData` with no migration and no normalisation (previews only).
    public static func peekZipData(_ url: URL, dataStore: DataStore) -> AppData? {
        let bytes: Data? = PersistFileCoordination.read(url) { u in
            guard let r = try? ZipReader(url: u), let e = r.entry(named: "data.json"),
                  let d = try? r.data(for: e) else { return nil }
            return PersistBundleIO.stripBOM(d)
        } ?? nil
        guard let bytes, let root = try? JSONParser.parse(bytes) else { return nil }
        return try? ModelCodec.decodeAppData(root, context: dataStore.decodeContext)
    }

    /// `ReadLastModified`: root `LastModified` (case-sensitive), non-null, parsed as a DateTime.
    public nonisolated static func readLastModified(_ json: Data) -> NetDateTime? {
        guard let root = try? JSONParser.parse(json), let o = root.objectValue, let v = o["LastModified"] else { return nil }
        guard case .string(let s) = v else { return nil }
        return NetDateTime(parsing: s)
    }

    nonisolated static func parseBundleSource(_ bytes: Data) -> BundleSource? {
        guard let root = try? JSONParser.parse(bytes), let o = root.objectValue else { return nil }
        return try? BundleSource(json: o, context: JSONDecodeContext())
    }

    /// `Environment.MachineName` on the Mac: the Computer Name, then the host name, then `"AA"` (01 §6.8).
    public nonisolated static func machineName() -> String { SettingsStore.defaultIdentity() }

    /// "aa-data-{yyyyMMdd-HHmm}.zip" (local time).
    public static let exportDefaultName: (NetDateTime) -> String = { now in "aa-data-\(now.format(.stampMinute)).zip" }

    public static let sharedDefaultName = "aa-shared.zip"

    // MARK: Shared steps

    /// `CurrentDataFile = Default`; the bundle's JSON text written through the local-encryption policy.
    static func applyDataFile(_ ds: DataStore, json: Data) throws {
        ds.setCurrentDataFile(ds.defaultDataFile)
        InstanceGuard.releaseExternal()
        try ds.persistWriteReplacing(json, to: ds.defaultDataFile)
    }

    /// `LoadFrom(Default)` → `MigrateLegacyAbsolutePaths` → rewrite (settings already persisted the active file).
    static func reloadMigrateRewrite(_ ds: DataStore) throws {
        let data = try ds.loadFrom(ds.defaultDataFile)
        AttachmentStore.migrateLegacyAbsolutePaths(ds, data: data)
        try ds.persistWriteReplacing(try ds.serializeForSave(data), to: ds.defaultDataFile)
    }
}

/// Immutable export job (main-actor snapshot → background ZIP writer).
struct PersistExportPlan: Sendable {
    let dest: URL
    let dataBytes: Data?
    let sourceBytes: Data
    let filesFolder: URL?

    func write() throws {
        let fm = FileManager.default
        let writer = try ZipWriter(url: dest)
        var ok = false
        defer { if !ok { try? fm.removeItem(at: dest) } }
        let now = Date()
        if let dataBytes { try writer.addData(dataBytes, named: "data.json", modified: now) }
        try writer.addData(sourceBytes, named: "source.json", modified: now)
        if let filesFolder, fm.fileExists(atPath: filesFolder.path) {
            try PersistBundleIO.addTree(filesFolder, entryPrefix: "files", to: writer)
        }
        try writer.finish()
        ok = true
    }
}

/// File-level helpers of the bundle service.
enum PersistBundleIO {
    static func stripBOM(_ d: Data) -> Data { d.starts(with: [0xEF, 0xBB, 0xBF]) ? d.dropFirst(3) : d }

    static func openReader(_ url: URL) throws -> ZipReader {
        do { return try ZipReader(url: url) } catch { throw error }
    }

    /// Extracts the whole archive (coordinated read) into a fresh staging folder; unsafe entries are rejected and
    /// nothing is written outside the folder; Finder metadata is skipped.
    static func extract(_ url: URL, to staging: URL) throws {
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var failure: Error?
        let done: Bool? = PersistFileCoordination.read(url) { u in
            do {
                try ZipReader(url: u).extractAll(to: staging, skip: PersistPaths.isFinderMetadata)
                return true
            } catch {
                failure = error
                return false
            }
        }
        if let failure { throw failure }
        if done == nil { throw PersistBundleError.io("The bundle could not be read: \(url.path)") }
    }

    /// The staged `data.json` as JSON text (BOM stripped), validated by a full model decode (D-3).
    @MainActor static func validatedJSON(_ ds: DataStore, _ url: URL) throws -> Data {
        let raw = try DataStore.readRaw(url)
        let json = try DataStore.decodeFileBytes(raw, key: try ds.keyForReading(raw))
        do {
            let root = try JSONParser.parse(json)
            _ = try ds.decode(root)
        } catch let e as DataLoadError {
            throw PersistBundleError.invalidData(e.localizedDescription)
        } catch let e as JSONParseError {
            throw PersistBundleError.invalidData(e.description)
        }
        return json
    }

    /// `IsDataOnlyBundle`: `source.json` with `DataOnly == true`, else no `files/` directory at all.
    static func isDataOnlyBundle(staging: URL, filesSrc: URL) -> Bool {
        let src = staging.appending(path: "source.json")
        if let d = try? Data(contentsOf: src), let s = BundleService.parseBundleSource(stripBOM(d)), s.dataOnly {
            return true
        }
        var isDir: ObjCBool = false
        return !(FileManager.default.fileExists(atPath: filesSrc.path, isDirectory: &isDir) && isDir.boolValue)
    }

    /// Top-level regular files of a folder (Finder metadata excluded): leaf → size.
    static func topLevelFiles(_ dir: URL) -> [(url: URL, leaf: String, size: Int64)] {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys:
            [.isRegularFileKey, .fileSizeKey], options: []) else { return [] }
        var out: [(URL, String, Int64)] = []
        for k in kids {
            let leaf = k.lastPathComponent
            if PersistPaths.isFinderMetadata(leaf) { continue }
            guard let v = try? k.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), v.isRegularFile == true else { continue }
            out.append((k, leaf, Int64(v.fileSize ?? 0)))
        }
        return out.sorted { $0.1 < $1.1 }
    }

    static func key(_ leaf: String) -> String { NetText.toUpperInvariant(leaf) }

    /// `AttachmentsMatch`: same set of top-level names (case-insensitive) with equal sizes; a missing dir is empty.
    static func attachmentsMatch(bundleDir: URL, localDir: URL) -> Bool {
        var b: [String: Int64] = [:], l: [String: Int64] = [:]
        for f in topLevelFiles(bundleDir) { b[key(f.leaf)] = f.size }
        for f in topLevelFiles(localDir) { l[key(f.leaf)] = f.size }
        guard b.count == l.count else { return false }
        for (k, size) in b { guard l[k] == size else { return false } }
        return true
    }

    /// Copies the bundle's top-level files into `files/` (overwrite; a local file differing only in case is replaced)
    /// and returns the copied names (case-insensitive keys). A missing source folder copies nothing.
    static func copyTopLevelFiles(from src: URL, to dest: URL) throws -> Set<String> {
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        var names = Set<String>()
        let local = topLevelFiles(dest)
        for f in topLevelFiles(src) {
            names.insert(key(f.leaf))
            for l in local where key(l.leaf) == key(f.leaf) && l.leaf != f.leaf { try? fm.removeItem(at: l.url) }
            let target = dest.appending(path: f.leaf)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: f.url, to: target)
        }
        return names
    }

    /// Deletes every top-level local file whose name is not in `keeping` (sub-folders and Finder metadata untouched).
    static func sweepOrphans(_ dir: URL, keeping: Set<String>) {
        for f in topLevelFiles(dir) where !keeping.contains(key(f.leaf)) {
            try? FileManager.default.removeItem(at: f.url)
        }
    }

    /// Adds a folder recursively under `entryPrefix/`: one entry per file, a directory entry only for empty folders
    /// (incl. the root itself), Finder metadata skipped, symbolic links not followed.
    static func addTree(_ root: URL, entryPrefix: String, to writer: ZipWriter) throws {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let kids = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [])
            .filter { !PersistPaths.isFinderMetadata($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if kids.isEmpty {
            try writer.addDirectory(named: entryPrefix + "/")
            return
        }
        for k in kids {
            let v = try k.resourceValues(forKeys: Set(keys))
            if v.isSymbolicLink == true { continue }
            let name = entryPrefix + "/" + k.lastPathComponent
            if v.isDirectory == true {
                try addTree(k, entryPrefix: name, to: writer)
            } else {
                try writer.addFile(named: name, from: k, modified: v.contentModificationDate)
            }
        }
    }
}

/// NSFileCoordinator wrappers for bundle access (DATA-185): orders reads/writes against other Mac processes and
/// downloads dataless File Provider placeholders before reading. Returns nil when coordination itself failed.
public enum PersistFileCoordination {
    public static func read<T>(_ url: URL, _ body: (URL) -> T) -> T? {
        var result: T?
        var err: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [.withoutChanges], error: &err) { u in
            result = body(u)
        }
        return result
    }

    /// Replaces `target` with `source` (same directory) under a coordinated write (`.forReplacing`).
    public static func replace(_ target: URL, with source: URL) throws {
        var err: NSError?
        var failure: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: target, options: [.forReplacing], error: &err) { u in
            if rename(source.path, u.path) != 0 {
                let code = errno
                failure = PersistBundleError.io(String(cString: strerror(code)))
            }
        }
        if let err { throw err }
        if let failure { throw failure }
    }
}

/// A write guard used for deliberate replacements of the active data file (bundle imports, shared pulls, Flash Sync
/// apply, conflict restore): the user already chose to replace the file, so the DATA-180 pre-write check is skipped,
/// but the new fingerprint is still recorded (Deviations/W-PERSIST.md).
final class PersistAcceptingGuard: DataFileWriteGuard, @unchecked Sendable {
    let inner: DataFileWriteGuard?
    init(_ inner: DataFileWriteGuard?) { self.inner = inner }
    func shouldWrite(to url: URL) -> Bool { true }
    func didWrite(to url: URL, bytes: Data) { inner?.didWrite(to: url, bytes: bytes) }
    func didLoad(from url: URL, bytes: Data) { inner?.didLoad(from: url, bytes: bytes) }
}

extension DataStore {
    /// Deliberate replacement of a data file: a foreign version found on disk is first kept as a "theirs" conflict
    /// copy (nothing is lost), then the bytes are written atomically through the encryption policy and the
    /// fingerprint is updated.
    func persistWriteReplacing(_ bytes: Data, to url: URL) throws {
        let key = try encryptionKeyForWrite(url)
        (writeGuard as? DataFileFingerprint)?.preserveForeignVersion(at: url, appFolder: appFolder, clock: clock)
        try PersistenceWriter.perform(WriteJob(bytes: bytes, url: url, encryptionKey: key),
                                      guard: PersistAcceptingGuard(writeGuard))
    }
}
