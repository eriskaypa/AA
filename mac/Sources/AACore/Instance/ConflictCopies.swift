// Spec: 01 DATA-181 (AppFolder/conflicts/, `data-{yyyyMMdd-HHmmss}[-n]-{theirs|mine}.json`, newest 20 kept,
//       recovery list with Show in Finder / Restore… applied like ApplySyncedData), §MP.4.2, MP.7.5 X-8/X-9,
//       DECISIONS R-70 (File ▸ Recover Conflict Copies…); ARCHITECTURE.md §6.6.
import Foundation
import CryptoKit

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

    /// Newest first (by the stamp and sequence in the name); `LastModified` read without loading the model (a
    /// "mine" copy encrypted on this Mac is decrypted with the local key; a Windows-encrypted one shows none).
    public static func list(_ ds: DataStore) -> [Entry] {
        let folder = PersistConflictStore.folder(ds.appFolder)
        return PersistConflictStore.names(in: folder).map { name in
            let url = folder.appending(path: name)
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            var stamp: NetDateTime?
            if let raw = try? DataStore.readRaw(url) {
                let key: SymmetricKey? = (try? ds.keyForReading(raw)) ?? nil
                stamp = BundleService.peekFileLastModified(url, key: key)
            }
            return Entry(fileName: name, isTheirs: name.hasSuffix("-theirs.json"), size: size, lastModified: stamp)
        }
    }

    public static func url(of e: Entry, _ ds: DataStore) -> URL {
        PersistConflictStore.folder(ds.appFolder).appending(path: e.fileName)
    }

    /// The JSON text of a copy, decrypted when it was encrypted on this Mac (throws for a Windows-encrypted one).
    public static func readJSON(_ e: Entry, _ ds: DataStore) throws -> Data {
        let raw = try DataStore.readRaw(url(of: e, ds))
        return try DataStore.decodeFileBytes(raw, key: try ds.keyForReading(raw))
    }

    /// The model inside a copy (no migration) for the change preview; nil when unreadable here.
    public static func peekData(_ e: Entry, _ ds: DataStore) -> AppData? {
        guard let json = try? readJSON(e, ds), let root = try? JSONParser.parse(json) else { return nil }
        return try? ModelCodec.decodeAppData(root, context: ds.decodeContext)
    }

    /// "Restore…" after the preview: applied into the default data file exactly like `ApplySyncedData` (never
    /// repoints `CurrentDataFile` into `conflicts/`). The caller reloads the UI.
    @discardableResult
    public static func restore(_ e: Entry, _ ds: DataStore) throws -> AppData {
        try ds.applySyncedData(try readJSON(e, ds))
    }

    /// Writes our serialised model as a `-mine` copy (encrypted when local encryption is on). Returns the file name.
    @discardableResult
    public static func saveMine(_ store: AppStore) throws -> String {
        let ds = store.dataStore
        let bytes = try ds.serializeForSave(store.data)
        let folder = PersistConflictStore.folder(ds.appFolder)
        let key = ds.localEncryptionKeyIfEnabled(for: folder.appending(path: "x.json"))
        let payload = try key.map { try LocalEncryption.encrypt(bytes, key: $0) } ?? bytes
        return try PersistConflictStore.add(payload, theirs: false, appFolder: ds.appFolder, now: ds.clock.instant(),
                                            zone: ds.clock.timeZone)
    }
}

/// Thread-safe file operations of the conflicts folder (called from the writer queue too).
public enum PersistConflictStore {
    public static let keep = 20

    public static func folder(_ appFolder: URL) -> URL { appFolder.appending(path: "conflicts", directoryHint: .isDirectory) }

    /// `(stamp, sequence, kind)` of a conflict-copy name; nil for any other file.
    public static func parse(_ name: String) -> (stamp: String, seq: Int, theirs: Bool)? {
        guard name.hasPrefix("data-"), name.hasSuffix(".json") else { return nil }
        var body = String(name.dropFirst(5).dropLast(5))
        let theirs: Bool
        if body.hasSuffix("-theirs") { theirs = true; body.removeLast(7) } else if body.hasSuffix("-mine") {
            theirs = false; body.removeLast(5)
        } else { return nil }
        var seq = 1
        let parts = body.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        if parts.count == 3 { guard let n = Int(parts[2]), n >= 2 else { return nil }; seq = n }
        guard parts[0].count == 8, parts[1].count == 6, (parts[0] + parts[1]).allSatisfy(\.isNumber) else { return nil }
        return (parts[0] + parts[1], seq, theirs)
    }

    /// Conflict-copy names, newest first.
    public static func names(in folder: URL) -> [String] {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return all.compactMap { n in parse(n).map { (n, $0) } }
            .sorted { a, b in
                if a.1.stamp != b.1.stamp { return a.1.stamp > b.1.stamp }
                if a.1.seq != b.1.seq { return a.1.seq > b.1.seq }
                return a.0 > b.0
            }
            .map(\.0)
    }

    /// Writes `bytes` as `data-{yyyyMMdd-HHmmss}[-n]-{theirs|mine}.json` (local time; `-2`, `-3`, … when a name of
    /// that second exists), then keeps the newest 20. Returns the file name.
    public static func add(_ bytes: Data, theirs: Bool, appFolder: URL, now: Date, zone: TimeZone) throws -> String {
        let dir = folder(appFolder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = NetDateTime(date: now, kind: .local, zone: zone).format(.stampSecond, zone: zone)
        let kind = theirs ? "theirs" : "mine"
        var n = 1
        var name = "data-\(stamp)-\(kind).json"
        while FileManager.default.fileExists(atPath: dir.appending(path: name).path) {
            n += 1
            name = "data-\(stamp)-\(n)-\(kind).json"
        }
        try AtomicWrite.write(bytes, to: dir.appending(path: name))
        prune(dir)
        return name
    }

    /// Keeps the newest `keep` copies (by name order); older ones are deleted.
    public static func prune(_ dir: URL) {
        for old in names(in: dir).dropFirst(keep) { try? FileManager.default.removeItem(at: dir.appending(path: old)) }
    }
}
