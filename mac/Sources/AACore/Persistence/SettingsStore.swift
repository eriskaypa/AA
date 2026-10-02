// Spec: 01 §3.1 (LoadSettings), §3.11, §4.3, §6.8, DATA-150–152, DATA-182 (key-level merge, retry, refusal,
//       joint writes), §MP.3.5 (write gate), MP.7.6 S-1…S-4, DECISIONS 14 (default identity = Computer Name);
//       ARCHITECTURE.md §4.11, §6.2.
import Foundation
import Observation
import SystemConfiguration

@MainActor @Observable
public final class SettingsStore {
    public let fileURL: URL
    public let secrets: SecretStore
    public private(set) var values: AppSettings
    /// true → setters update memory only (read-only instance / external-conflict gate, 01 §MP.3.5).
    public var isWriteGated: Bool = false
    /// Last setter failure (nil/false after a successful write); F3/W-SHELL post `unreadableStatus` when set.
    public private(set) var lastWriteRefused: Bool = false
    /// Incremented by every `reload()` (the app-password session is forgotten on every LoadSettings, 01 DATA-081).
    public private(set) var reloadGeneration: Int = 0

    /// Status text DATA-182 posts when a setter could not write (exact).
    public static let unreadableStatus = "Couldn't update settings.json (it is unreadable) — this change applies until AA quits."

    /// Retry policy of DATA-182 / §MP.3.7: 3 retries, 50 ms apart.
    static let readRetries = 3
    static let retryDelay: TimeInterval = 0.05

    public init(fileURL: URL, secrets: SecretStore) {
        self.fileURL = fileURL
        self.secrets = secrets
        values = AppSettings()
    }

    /// `values.appIdentity` when not blank, else the default identity.
    public var appIdentity: String {
        if let id = values.appIdentity, !NetText.isBlank(id) { return id }
        return SettingsStore.defaultIdentity()
    }

    /// Path keys whose value is a Windows-style path (`^[A-Za-z]:\` or `^\\`) — the 01 §6.8 banner.
    public var foreignPathKeys: [String] {
        let candidates: [(String, String?)] = [("CurrentDataFile", values.currentDataFile),
                                               ("GoogleDriveFolder", values.googleDriveFolder),
                                               ("FolderBuilderBase", values.folderBuilderBase),
                                               ("SharedSaveFile", values.sharedSaveFile)]
        return candidates.compactMap { key, v in
            guard let v, SettingsStore.isWindowsPath(v) else { return nil }
            return key
        }
    }

    nonisolated static func isWindowsPath(_ s: String) -> Bool {
        let u = Array(s.utf8)
        if u.count >= 3, ((u[0] >= 0x41 && u[0] <= 0x5A) || (u[0] >= 0x61 && u[0] <= 0x7A)), u[1] == 0x3A, u[2] == 0x5C {
            return true
        }
        return u.count >= 2 && u[0] == 0x5C && u[1] == 0x5C
    }

    // MARK: Reading

    /// 01 §3.1: missing file or an unreadable one → defaults (FolderBuilderBase / GeminiApiKey keep what memory had,
    /// like Windows); per-key tolerance otherwise.
    public func reload() {
        reloadGeneration += 1
        let keep = AppSettings(folderBuilderBase: values.folderBuilderBase, geminiApiKey: values.geminiApiKey)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { values = keep; return }
        guard let data = try? Data(contentsOf: fileURL), let root = try? JSONParser.parse(data) else { values = keep; return }
        switch root {
        case .object(let o):
            let read = AppSettings(json: o)
            // 01 §3.1 catch branch / §7.12: an undecodable PasswordSalt makes Windows' LoadFrom throw → every value
            // falls back to its default; FolderBuilderBase / GeminiApiKey keep the values just read.
            if let salt = read.passwordSalt, !salt.isEmpty, NetBase64.decode(salt) == nil {
                values = AppSettings(folderBuilderBase: read.folderBuilderBase, geminiApiKey: read.geminiApiKey,
                                     extra: read.extra)
            } else {
                values = read
            }
        default: values = keep                                  // `null` (and any non-object) → defaults
        }
    }

    enum RawRead { case absent, tree(JSONObject), unreadable(String) }

    /// One attempt + `readRetries` retries 50 ms apart. A missing file is an empty object; a `null` root reads as
    /// `{}`; IO / parse errors or another non-object root → unreadable.
    func readRawWithRetry() -> RawRead {
        var last = "unreadable"
        for attempt in 0...SettingsStore.readRetries {
            if attempt > 0 { Thread.sleep(forTimeInterval: SettingsStore.retryDelay) }
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return .absent }
            do {
                let data = try Data(contentsOf: fileURL)
                let root = try JSONParser.parse(data)
                switch root {
                case .object(let o): return .tree(o)
                case .null: return .tree(JSONObject())
                default: last = "settings.json is not a JSON object"
                }
            } catch {
                last = String(describing: error)
            }
        }
        return .unreadable(last)
    }

    /// Flash Sync (13 §3.12, DECISIONS 13 Q-5): `{}` ONLY when the file is absent; unreadable → throws.
    public func readRawTree() throws(DataLoadError) -> JSONObject {
        switch readRawWithRetry() {
        case .absent: return JSONObject()
        case .tree(let t): return t
        case .unreadable(let why): throw .unreadable(why)
        }
    }

    /// Flash Sync apply: writes the whole tree compact and atomically; refuses (throws) when the current file exists
    /// but is unreadable, or while writes are gated. Performs NO reload.
    public func writeRawTree(_ tree: JSONObject) throws(DataLoadError) {
        if isWriteGated { throw .unreadable("settings.json is read-only in this copy of AA") }
        if case .unreadable(let why) = readRawWithRetry() { throw .unreadable(why) }
        do {
            try AtomicWrite.write(try JSONWriter.data(.object(tree)), to: fileURL)
        } catch {
            throw .unreadable(String(describing: error))
        }
    }

    // MARK: Setters (DATA-151, key-level merge DATA-182)

    public func setCurrentDataFile(_ path: String?) {
        values.currentDataFile = path
        merge([("CurrentDataFile", path.map(JSONValue.string))])
    }

    /// Joint write of PasswordHash + PasswordSalt in one atomic replace (S-4).
    public func setPassword(hash: String, salt: String) {
        values.passwordHash = hash
        values.passwordSalt = salt
        merge([("PasswordHash", .string(hash)), ("PasswordSalt", .string(salt))])
    }

    public func setGoogleDriveFolder(_ path: String) {
        values.googleDriveFolder = path
        merge([("GoogleDriveFolder", .string(path))])
    }

    public func setSyncOnSave(_ on: Bool) { values.syncOnSave = on; merge([("SyncOnSave", .bool(on))]) }
    public func setTextOnlyExport(_ on: Bool) { values.textOnlyExport = on; merge([("TextOnlyExport", .bool(on))]) }
    public func setDarkMode(_ on: Bool) { values.darkMode = on; merge([("DarkMode", .bool(on))]) }
    public func setEncryptLocalData(_ on: Bool) { values.encryptLocalData = on; merge([("EncryptLocalData", .bool(on))]) }

    /// Blank → the machine's default identity, else trimmed (DATA-151).
    public func setAppIdentity(_ identity: String?) {
        let v = NetText.isBlank(identity) ? SettingsStore.defaultIdentity() : NetText.trim(identity!)
        values.appIdentity = v
        merge([("AppIdentity", .string(v))])
    }

    public func setFolderBuilderBase(_ path: String) {
        values.folderBuilderBase = path
        merge([("FolderBuilderBase", .string(path))])
    }

    /// Blank or nil → key removed.
    public func setSharedSaveFile(_ path: String?) {
        let v: String? = NetText.isBlank(path) ? nil : path
        values.sharedSaveFile = v
        merge([("SharedSaveFile", v.map(JSONValue.string))])
    }

    /// Read-modify-write of the given keys only (nil value = remove). Known keys are written in 01 §4.3 order, then
    /// unknown keys in their existing order; compact and atomic. An unreadable file is never written.
    func merge(_ changes: [(String, JSONValue?)]) {
        if isWriteGated { return }
        var tree: JSONObject
        switch readRawWithRetry() {
        case .absent: tree = JSONObject()
        case .tree(let t): tree = t
        case .unreadable:
            lastWriteRefused = true
            return
        }
        for (k, v) in changes {
            if let v { tree.set(k, v) } else { tree.removeValue(forKey: k) }
        }
        var ordered = JSONObject()
        for k in AppSettings.knownKeys { if let v = tree.rawValue(forKey: k) { ordered.set(k, v) } }
        var known = Set<Ordinal.Key>()
        for k in AppSettings.knownKeys { known.insert(Ordinal.Key(k)) }
        for (k, v) in tree where !known.contains(Ordinal.Key(k)) { ordered.set(k, v) }
        do {
            try AtomicWrite.write(try JSONWriter.data(.object(ordered)), to: fileURL)
            lastWriteRefused = false
        } catch {
            lastWriteRefused = true
        }
    }

    /// Computer Name (System Settings ▸ General ▸ Sharing) → host name → "AA" (DECISIONS 14).
    public nonisolated static func defaultIdentity() -> String {
        if let name = SCDynamicStoreCopyComputerName(nil, nil) as String?, !NetText.isBlank(name) { return name }
        let host = ProcessInfo.processInfo.hostName
        if !NetText.isBlank(host) { return host }
        return "AA"
    }
}
