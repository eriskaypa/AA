// Spec: 01 §3.1–3.4 (load settings, load, save pipeline, ReadDataText), DATA-011, DATA-013, DATA-021–024,
//       DATA-029–031, DATA-071–072, §6.2, §6.5 (AAENCM1 / Windows AAENC1 detection), D-14 (Save a Copy As),
//       DECISIONS Q-5 (adopt an external JSON), §MP.3.4 (write guard); ARCHITECTURE.md §6.2.
import Foundation
import Observation
import CryptoKit

public enum DataLoadError: Error, LocalizedError, Sendable {
    case unreadable(String)            // locked / IO / mid-write
    case windowsEncrypted              // "AAENC1\n" DPAPI file → Mac safe-mode wording (01 §6.5)
    case macKeyUnavailable             // "AAENCM1\n" but no Keychain key (or denied)
    case parse(JSONParseError)
    case model(JSONModelError)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let why): return "The data file could not be read: \(why)"
        case .windowsEncrypted:
            return "The data file was encrypted by AA on Windows and can only be opened on that PC — export a bundle there and import it here."
        case .macKeyUnavailable: return "The key that encrypts this Mac's data file could not be read from the Keychain."
        case .parse(let e): return e.description
        case .model(let e): return e.description
        }
    }
}

@MainActor @Observable
public final class DataStore {
    public let appFolder: URL
    public let settings: SettingsStore
    public let secrets: SecretStore
    public let clock: AppClock

    public var filesFolder: URL { appFolder.appending(path: "files", directoryHint: .isDirectory) }
    public var defaultDataFile: URL { appFolder.appending(path: "data.json") }
    public var settingsFile: URL { appFolder.appending(path: "settings.json") }
    public var googleClientSecretFile: URL { appFolder.appending(path: "google_client_secret.json") }
    public var googleTokenFolder: URL { appFolder.appending(path: "google-token", directoryHint: .isDirectory) }
    public var crashLogFile: URL { appFolder.appending(path: "crash.log") }
    public var flashBaselineFile: URL { appFolder.appending(path: "qrsync-baseline.json") }
    public var instanceLockFile: URL { appFolder.appending(path: ".aa.lock") }

    public private(set) var currentDataFile: URL
    public private(set) var lastLoadFailed = false
    public private(set) var lastLoadError: DataLoadError?
    public private(set) var loadedNewerSchema: Int?
    public static let currentSchemaVersion = 1

    /// DATA-180 hook (installed by F3; §5.2). Consulted before, and told after, every write of a data file.
    @ObservationIgnored public var writeGuard: DataFileWriteGuard?

    /// Per-session cache of the local-data key (never a Keychain call per autosave).
    @ObservationIgnored private var cachedKey: SymmetricKey?
    /// Last Keychain failure while encryption is on (nil when fine).
    public private(set) var localKeyError: String?

    public init(appFolder: URL, secrets: SecretStore = KeychainSecretStore(), clock: AppClock = SystemClock()) {
        self.appFolder = appFolder.standardizedFileURL
        self.secrets = secrets
        self.clock = clock
        settings = SettingsStore(fileURL: self.appFolder.appending(path: "settings.json"), secrets: secrets)
        currentDataFile = self.appFolder.appending(path: "data.json")
    }

    var decodeContext: JSONDecodeContext { JSONDecodeContext(zone: clock.timeZone, clock: clock) }

    // MARK: Settings (01 §3.1)

    /// Reads settings.json; the persisted `CurrentDataFile` is used only if that file exists (DATA-013).
    public func loadSettings() {
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        settings.reload()
        if let p = settings.values.currentDataFile, !NetText.isBlank(p), FileManager.default.fileExists(atPath: p) {
            currentDataFile = URL(fileURLWithPath: p)
        } else {
            currentDataFile = defaultDataFile
        }
        if !settings.values.encryptLocalData { cachedKey = nil }
    }

    // MARK: Load (01 §3.2)

    /// Never throws: an absent file → empty model; a present-but-unreadable file → empty model with
    /// `lastLoadFailed` (safe mode). A `null` root is an empty model, not a failure.
    public func load() -> AppData {
        prepareFolders()
        lastLoadFailed = false; lastLoadError = nil; loadedNewerSchema = nil
        let url = currentDataFile
        guard FileManager.default.fileExists(atPath: url.path) else { return AppData() }
        do {
            let raw = try DataStore.readRaw(url)
            writeGuard?.didLoad(from: url, bytes: raw)
            let json = try DataStore.decodeFileBytes(raw, key: try keyForReading(raw))
            let root: JSONValue
            do throws(JSONParseError) { root = try JSONParser.parse(json) } catch { throw DataLoadError.parse(error) }
            let data = try decode(root)
            if data.schemaVersion > DataStore.currentSchemaVersion { loadedNewerSchema = data.schemaVersion }
            SchemaMigration.migrate(data)
            normalizeFilePaths(data)
            return data
        } catch {
            lastLoadFailed = true
            lastLoadError = (error as? DataLoadError) ?? .unreadable(String(describing: error))
            return AppData()
        }
    }

    /// Same as `load()`, with the file read and JSON parse off the main actor; the model is built on main.
    public func loadInBackground() async -> AppData {
        prepareFolders()
        lastLoadFailed = false; lastLoadError = nil; loadedNewerSchema = nil
        let url = currentDataFile
        guard FileManager.default.fileExists(atPath: url.path) else { return AppData() }
        let key: SymmetricKey?
        do throws(DataLoadError) {
            key = try keyForReading(try DataStore.readRaw(url))
        } catch {
            lastLoadFailed = true; lastLoadError = error; return AppData()
        }
        let parsed = await Task.detached(priority: .userInitiated) { () -> Result<(Data, JSONValue), DataLoadError> in
            do throws(DataLoadError) {
                let raw = try DataStore.readRaw(url)
                let json = try DataStore.decodeFileBytes(raw, key: key)
                do throws(JSONParseError) {
                    return .success((raw, try JSONParser.parse(json)))
                } catch {
                    return .failure(.parse(error))
                }
            } catch {
                return .failure(error)
            }
        }.value
        switch parsed {
        case .failure(let e):
            lastLoadFailed = true; lastLoadError = e; return AppData()
        case .success(let (raw, root)):
            writeGuard?.didLoad(from: url, bytes: raw)
            do throws(DataLoadError) {
                let data = try decode(root)
                if data.schemaVersion > DataStore.currentSchemaVersion { loadedNewerSchema = data.schemaVersion }
                SchemaMigration.migrate(data)
                normalizeFilePaths(data)
                return data
            } catch {
                lastLoadFailed = true; lastLoadError = error; return AppData()
            }
        }
    }

    /// Imports: throws on any failure; never sets `lastLoadFailed` / `loadedNewerSchema`. Migrates + normalises.
    public func loadFrom(_ url: URL) throws(DataLoadError) -> AppData {
        let raw = try DataStore.readRaw(url)
        let json = try DataStore.decodeFileBytes(raw, key: try keyForReading(raw))
        let root: JSONValue
        do throws(JSONParseError) { root = try JSONParser.parse(json) } catch { throw .parse(error) }
        let data = try decode(root)
        SchemaMigration.migrate(data)
        normalizeFilePaths(data)
        return data
    }

    func decode(_ root: JSONValue) throws(DataLoadError) -> AppData {
        do throws(JSONModelError) {
            return try ModelCodec.decodeAppData(root, context: decodeContext)
        } catch {
            throw .model(error)
        }
    }

    func prepareFolders() {
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: filesFolder, withIntermediateDirectories: true)
    }

    /// Attachment path normalisation hook (01 §3.7). The algorithm is W-PERSIST's
    /// `AttachmentStore.normalizeFilePaths` (ARCHITECTURE.md §6.6), called here on load and before every save.
    func normalizeFilePaths(_ data: AppData) {
        _ = data
    }

    // MARK: Reading bytes (01 §3.4)

    nonisolated static func readRaw(_ url: URL) throws(DataLoadError) -> Data {
        do { return try Data(contentsOf: url) } catch let e { throw .unreadable(e.localizedDescription) }
    }

    /// Classifies and decodes file bytes: Windows DPAPI → `.windowsEncrypted`; Mac format → decrypt (a missing key
    /// → `.macKeyUnavailable`); plaintext → UTF-8 BOM stripped. The JSON parse that follows replaces invalid UTF-8.
    nonisolated static func decodeFileBytes(_ raw: Data, key: SymmetricKey?) throws(DataLoadError) -> Data {
        switch LocalEncryption.classify(raw) {
        case .windowsDPAPI: throw .windowsEncrypted
        case .mac:
            guard let key else { throw .macKeyUnavailable }
            do { return try LocalEncryption.decrypt(raw, key: key) } catch {
                throw .unreadable("the encrypted data file could not be decrypted with this Mac's key")
            }
        case .plain:
            if raw.starts(with: [0xEF, 0xBB, 0xBF]) { return raw.dropFirst(3) }
            return raw
        }
    }

    /// BOM strip + decrypt of a data file.
    public nonisolated static func readDataBytes(_ url: URL, key: SymmetricKey?) throws(DataLoadError) -> Data {
        try decodeFileBytes(try readRaw(url), key: key)
    }

    /// The key needed to read `raw`: only for Mac-encrypted bytes (read once per session, never created here).
    func keyForReading(_ raw: Data) throws(DataLoadError) -> SymmetricKey? {
        guard LocalEncryption.classify(raw) == .mac else { return nil }
        if let cachedKey { return cachedKey }
        guard let k = (try? LocalEncryption.key(secrets: secrets, create: false)) ?? nil else { throw .macKeyUnavailable }
        cachedKey = k
        return k
    }

    // MARK: Encryption policy (01 DATA-071, §6.5)

    /// `/U/AA/x` is under `/U/AA`, case-insensitively; the folder itself is not.
    public func isUnderAppFolder(_ url: URL) -> Bool {
        let full = url.standardizedFileURL.path
        var root = appFolder.path
        while root.hasSuffix("/") && root.count > 1 { root.removeLast() }
        root += "/"
        guard full.utf16.count >= root.utf16.count else { return false }
        return NetText.equalsIgnoreCase(String(full.utf16.prefix(root.utf16.count))!, root)
    }

    /// Key only for files inside appFolder and only when EncryptLocalData is on; read from the SecretStore ONCE per
    /// session (created on first use) and cached; the cache is cleared when the setting is off. nil when the
    /// Keychain refuses (see `localKeyError`).
    public func localEncryptionKeyIfEnabled(for url: URL) -> SymmetricKey? {
        guard settings.values.encryptLocalData else { cachedKey = nil; return nil }
        guard isUnderAppFolder(url) else { return nil }
        if let cachedKey { return cachedKey }
        do {
            let k = try LocalEncryption.key(secrets: secrets, create: true)
            cachedKey = k
            localKeyError = nil
            return k
        } catch {
            localKeyError = String(describing: error)
            return nil
        }
    }

    /// Like `localEncryptionKeyIfEnabled`, but a file that must be encrypted and has no key is an error — a data
    /// file is never silently written in plaintext while encryption is on.
    func encryptionKeyForWrite(_ url: URL) throws(AppStoreError) -> SymmetricKey? {
        let key = localEncryptionKeyIfEnabled(for: url)
        if key == nil, settings.values.encryptLocalData, isUnderAppFolder(url) {
            throw .write("The local-data encryption key could not be read from the Keychain.")
        }
        return key
    }

    /// Replaces the cached key (key rotation / tests).
    public func clearCachedEncryptionKey() { cachedKey = nil }

    // MARK: Save (01 §3.3)

    /// Normalises attachment paths, stamps `SchemaVersion = max(v, 1)` (never downgrades), serialises compact.
    /// Int32 overflow or depth > 64 → `.serialization` (a save error, never a file Windows cannot load).
    public func serializeForSave(_ data: AppData) throws(AppStoreError) -> Data {
        normalizeFilePaths(data)
        if data.schemaVersion < DataStore.currentSchemaVersion { data.schemaVersion = DataStore.currentSchemaVersion }
        return try DataStore.serialize(data, zone: clock.timeZone)
    }

    static func serialize(_ data: AppData, zone: TimeZone) throws(AppStoreError) -> Data {
        let log = JSONEncodeIssueLog()
        let tree = ModelCodec.encodeAppData(data, options: JSONEncodeOptions(zone: zone, issueLog: log))
        if let first = log.issues.first { throw .serialization("A value is outside the range Windows can read (\(first)).") }
        guard let bytes = try? JSONWriter.data(tree) else { throw .serialization("The structure is too deep to save.") }
        return bytes
    }

    /// Save a Copy As JSON (plaintext, atomic). D-14 fixed: serialises a COPY with LastModified = now and
    /// SchemaVersion = max(v,1); the live model's stamp and dirty state are untouched (Deviations/F1.md).
    public func saveTo(_ data: AppData, url: URL) throws {
        let copy = ModelCodec.deepClone(data, context: decodeContext)
        copy.lastModified = clock.now()
        let bytes = try serializeForSave(copy)
        try AtomicWrite.write(bytes, to: url)
    }

    /// Synchronous write of already-serialised JSON; honours EncryptLocalData (files inside appFolder only);
    /// the write guard is consulted before and told after (§5.2).
    public func writeLocalDataFile(_ bytes: Data, to url: URL) throws {
        let key = try encryptionKeyForWrite(url)
        try PersistenceWriter.perform(WriteJob(bytes: bytes, url: url, encryptionKey: key), guard: writeGuard)
    }

    /// Persists `CurrentDataFile`.
    public func setCurrentDataFile(_ url: URL) {
        currentDataFile = url.standardizedFileURL
        settings.setCurrentDataFile(currentDataFile.path)
    }

    /// DECISIONS 01 Q-5 — adopt an external JSON after the import gate:
    /// * `copyIntoAppFolder` (default): its content becomes the local default data file (normalised, schema-stamped,
    ///   encrypted when enabled) and `CurrentDataFile` points at the default;
    /// * otherwise (Windows behaviour, DATA-034): the chosen file becomes the active data file and is rewritten in
    ///   place (normalised, schema-stamped; encrypted only if inside appFolder).
    /// Throws (nothing changed) when the source cannot be loaded.
    public func adoptExternalDataFile(_ source: URL, copyIntoAppFolder: Bool) throws -> URL {
        let data = try loadFrom(source)
        let target = copyIntoAppFolder ? defaultDataFile : source.standardizedFileURL
        let bytes = try serializeForSave(data)
        try writeLocalDataFile(bytes, to: target)
        setCurrentDataFile(target)
        return target
    }
}
