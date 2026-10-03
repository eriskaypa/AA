// Spec: 13 §3.12 / FLASH-100…107 (baseline file, written at exactly two moments, read tolerance, outgoing
//       decision, side-effect-free preview, apply pipeline, reset API, what never travels), FLASH-021 (pending
//       baseline = the trees the payload was built from), FLASH-132 (snapshot without settings);
//       DECISIONS 13 Q-5 (refuse an unreadable database; unreadable settings = error), Q-10 (transactional apply),
//       Q-11 (baseline encrypted when local encryption is on), Q-12 (one baseline per device); ARCHITECTURE.md §2.2.
// The baseline only advances when the user confirms the far side received a transfer, or after this machine applies
// one: guessing is the one unrecoverable mistake (an advanced-but-not-received baseline omits those edits forever).
import Foundation
import CryptoKit

/// Errors the store surfaces (an apply that throws has changed nothing).
public enum FlashSyncError: Error, LocalizedError, Equatable, Sendable {
    /// DECISIONS 13 Q-5.
    case databaseUnreadable
    case settingsUnreadable(String)
    case settingsUnwritable(String)
    case payloadTooDeep
    case writeFailed(String)

    public static let databaseUnreadableMessage =
        "The database could not be read, so Flash Sync is unavailable until it is fixed."

    public var errorDescription: String? {
        switch self {
        case .databaseUnreadable: return FlashSyncError.databaseUnreadableMessage
        case .settingsUnreadable(let why): return "settings.json could not be read (\(why)), so nothing was changed."
        case .settingsUnwritable(let why): return "settings.json could not be written (\(why)), so nothing was changed."
        case .payloadTooDeep: return "The structure is too deep to save."
        case .writeFailed(let why): return why
        }
    }
}

/// The last state the other device confirmed (`Data` nil → the next send is a full snapshot).
public struct FlashBaseline: Sendable, Equatable {
    public var data: JSONObject?
    public var settings: JSONObject?
    public init(data: JSONObject?, settings: JSONObject?) {
        self.data = data
        self.settings = settings
    }
}

/// What `prepareSend` captures on the main actor; the diff, encoding and DEFLATE then run off-main.
public struct FlashSendInputs: Sendable {
    /// The database exactly as the persistence layer would write it (compact JSON).
    public var dataJSON: Data
    public var settings: JSONObject
    /// The decrypted baseline file, or nil when there is none / it is unreadable.
    public var baselineJSON: Data?
    public init(dataJSON: Data, settings: JSONObject, baselineJSON: Data?) {
        self.dataJSON = dataJSON
        self.settings = settings
        self.baselineJSON = baselineJSON
    }
}

/// An outgoing payload plus the pending baseline (the full, unstripped trees it was built from — FLASH-021).
public struct FlashOutgoing: Sendable {
    public let payload: [UInt8]
    public let kind: FlashFrameKind
    public let label: String
    public let pendingData: JSONObject
    public let pendingSettings: JSONObject
    public init(payload: [UInt8], kind: FlashFrameKind, label: String, pendingData: JSONObject, pendingSettings: JSONObject) {
        self.payload = payload
        self.kind = kind
        self.label = label
        self.pendingData = pendingData
        self.pendingSettings = pendingSettings
    }
}

/// A decoded, not-yet-applied transfer.
public struct FlashIncomingChange: Sendable {
    public let payload: JSONObject
    public let isSnapshot: Bool
    public let summary: String
    /// False for a snapshot that is a bare data.json or whose envelope `Settings` is not an object (FLASH-132).
    public let carriesSettings: Bool
    public init(payload: JSONObject, isSnapshot: Bool, summary: String, carriesSettings: Bool) {
        self.payload = payload
        self.isSnapshot = isSnapshot
        self.summary = summary
        self.carriesSettings = carriesSettings
    }
}

/// Bridges Flash Sync's JSON-tree world to the database and settings.json.
@MainActor
public final class FlashSyncStore {
    public let dataStore: DataStore
    private let applySynced: @MainActor (Data) throws -> AppData
    private let log = AALog.logger("flashsync")

    /// `applySyncedData` defaults to W-PERSIST's `DataStore.applySyncedData` (tests inject a stand-in).
    public init(dataStore: DataStore, applySyncedData: (@MainActor (Data) throws -> AppData)? = nil) {
        self.dataStore = dataStore
        self.applySynced = applySyncedData ?? { [dataStore] json in try dataStore.applySyncedData(json) }
    }

    public var baselineURL: URL { dataStore.flashBaselineFile }

    // MARK: Reading the current state

    /// The database read from disk, exactly as it would be written (paths normalised, SchemaVersion stamped).
    /// A missing data file is an empty database; an unreadable one throws (Q-5) — never an empty tree.
    public func readDataJSON() throws -> Data {
        let url = dataStore.currentDataFile
        let data: AppData
        if FileManager.default.fileExists(atPath: url.path) {
            do { data = try dataStore.loadFrom(url) } catch { throw FlashSyncError.databaseUnreadable }
        } else {
            data = AppData()
        }
        return try serialize(data)
    }

    public func readDataTree() throws -> JSONObject { try FlashSyncStore.parseObject(try readDataJSON()) }

    /// The tree for a model in hand.
    public func readDataTree(_ data: AppData) throws -> JSONObject { try FlashSyncStore.parseObject(try serialize(data)) }

    private func serialize(_ data: AppData) throws -> Data {
        do { return try dataStore.serializeForSave(data) } catch { throw FlashSyncError.writeFailed(error.localizedDescription) }
    }

    /// settings.json as a tree: `{}` when absent; unreadable → throws (Q-5: never treated as empty, which would emit
    /// SettingsDeletes for every shared key).
    public func readSettingsTree() throws -> JSONObject {
        do { return try dataStore.settings.readRawTree() } catch {
            throw FlashSyncError.settingsUnreadable(FlashSyncStore.reason(error))
        }
    }

    // MARK: The baseline (qrsync-baseline.json)

    public var hasBaseline: Bool { FileManager.default.fileExists(atPath: baselineURL.path) }

    /// The decrypted baseline bytes, or nil when missing or unreadable (never an error, FLASH-102).
    public func readBaselineJSON() -> Data? {
        guard let raw = try? Data(contentsOf: baselineURL) else { return nil }
        switch LocalEncryption.classify(raw) {
        case .windowsDPAPI:
            return nil
        case .mac:
            let key = dataStore.localEncryptionKeyIfEnabled(for: baselineURL)
                ?? ((try? LocalEncryption.key(secrets: dataStore.secrets, create: false)) ?? nil)
            guard let key else { return nil }
            return try? LocalEncryption.decrypt(raw, key: key)
        case .plain:
            return raw
        }
    }

    public func readBaseline() -> FlashBaseline? { readBaselineJSON().flatMap(FlashSyncStore.parseBaseline) }

    /// `{"Data":{…},"Settings":{…}|null}` → the two trees; nil when the root is not an object or a member has the
    /// wrong shape (C# `AsObject()` throws → "no baseline").
    public nonisolated static func parseBaseline(_ bytes: Data) -> FlashBaseline? {
        guard case .object(let root)? = try? JSONParser.parse(bytes) else { return nil }
        var data: JSONObject?
        var settings: JSONObject?
        switch root["Data"] {
        case nil: data = nil
        case .object(let o)?: data = o
        default: return nil
        }
        switch root["Settings"] {
        case nil: settings = nil
        case .object(let o)?: settings = o
        default: return nil
        }
        return FlashBaseline(data: data, settings: settings)
    }

    /// Records the state the other side now holds: `{"StampedUtc":…,"Data":…,"Settings":…|null}`, compact and
    /// atomic, encrypted with the local key when EncryptLocalData is on (Q-11). Errors are swallowed (worst case the
    /// next sync is a snapshot); the return value says whether it was written.
    @discardableResult
    public func writeBaseline(data: JSONObject, settings: JSONObject?) -> Bool {
        var root = JSONObject()
        root.set("StampedUtc", .string(dataStore.clock.utcNow().format(.roundTripO)))
        root.set("Data", .object(data))
        root.set("Settings", settings.map(JSONValue.object) ?? .null)
        do {
            var bytes = try JSONWriter.data(.object(root))
            if dataStore.settings.values.encryptLocalData {
                guard let key = dataStore.localEncryptionKeyIfEnabled(for: baselineURL) else {
                    log.error("Flash Sync baseline not written: the local-data key is unavailable")
                    return false
                }
                bytes = try LocalEncryption.encrypt(bytes, key: key)
            }
            try FileManager.default.createDirectory(at: dataStore.appFolder, withIntermediateDirectories: true)
            try AtomicWrite.write(bytes, to: baselineURL)
            return true
        } catch {
            log.error("Flash Sync baseline not written: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Forgets the baseline so the next send is a full snapshot (FLASH-106/131).
    public func clearBaseline() {
        try? FileManager.default.removeItem(at: baselineURL)
    }

    // MARK: Building what to send

    /// Captures the inputs on the main actor (reads the database from disk — the caller flushed and saved first).
    public func captureSendInputs() throws -> FlashSendInputs {
        FlashSendInputs(dataJSON: try readDataJSON(), settings: try readSettingsTree(), baselineJSON: readBaselineJSON())
    }

    /// Baseline → change set (nil when unchanged); no baseline → snapshot labelled `full database` (FLASH-103).
    /// Pure; runs off-main.
    public nonisolated static func buildOutgoing(_ inputs: FlashSendInputs, from: String,
                                                 now: NetDateTime) throws -> FlashOutgoing? {
        let data = try parseObject(inputs.dataJSON)
        let baseline = inputs.baselineJSON.flatMap(parseBaseline)
        if let baseData = baseline?.data {
            guard let cs = FlashChangeSet.buildChangeSet(current: data, baselineData: baseData,
                                                         currentSettings: inputs.settings,
                                                         baselineSettings: baseline?.settings,
                                                         from: from, created: now) else { return nil }
            return FlashOutgoing(payload: try encode(cs), kind: .changeSet, label: FlashChangeSet.summarize(cs),
                                 pendingData: data, pendingSettings: inputs.settings)
        }
        let snap = FlashChangeSet.buildSnapshot(data: data, settings: inputs.settings)
        return FlashOutgoing(payload: try encode(snap), kind: .fullSnapshot, label: FlashChangeSet.snapshotLabel,
                             pendingData: data, pendingSettings: inputs.settings)
    }

    /// Synchronous convenience (tests, CLI-style callers).
    public func buildOutgoing(from: String) throws -> FlashOutgoing? {
        try FlashSyncStore.buildOutgoing(try captureSendInputs(), from: from, now: dataStore.clock.now())
    }

    // MARK: Applying what arrived

    /// What an incoming payload would do, decided without touching anything; nil when it is not a JSON object.
    public nonisolated static func preview(_ payload: [UInt8], kind: FlashFrameKind) -> FlashIncomingChange? {
        guard case .object(let obj)? = try? JSONParser.parse(Data(payload)) else { return nil }
        let envelope = FlashChangeSet.isSnapshotEnvelope(.object(obj))
        let snapshot = kind == .fullSnapshot || envelope
        let carries: Bool
        if snapshot, envelope, case .object? = obj["Settings"] { carries = true } else { carries = !snapshot }
        return FlashIncomingChange(payload: obj, isSnapshot: snapshot,
                                   summary: snapshot ? FlashChangeSet.snapshotSummary : FlashChangeSet.summarize(obj),
                                   carriesSettings: carries)
    }

    /// Applies a previewed change (FLASH-105) transactionally (Q-10): both trees are read first (an unreadable
    /// database or settings file aborts with nothing written), the result is computed in memory, settings.json is
    /// written, then the data goes through `applySyncedData`; if that fails the previous settings.json is restored.
    /// Finally the baseline records the new agreed state. Returns the reloaded model.
    public func apply(_ change: FlashIncomingChange) throws -> AppData {
        let settingsBefore = try readSettingsTree()
        let existing = try readDataTree()
        let now = dataStore.clock.now()
        var settings = settingsBefore
        let applied: JSONObject
        if change.isSnapshot {
            applied = FlashChangeSet.applySnapshot(change.payload, settings: &settings, now: now, existingData: existing).data
        } else {
            var d = existing
            FlashChangeSet.applyChangeSet(change.payload, data: &d, settings: &settings, now: now)
            applied = d
        }
        guard let json = try? JSONWriter.data(.object(applied)) else { throw FlashSyncError.payloadTooDeep }

        let settingsURL = dataStore.settingsFile
        let settingsChanged = settings != settingsBefore
        let previousSettingsBytes = try? Data(contentsOf: settingsURL)
        if settingsChanged {
            do { try dataStore.settings.writeRawTree(settings) } catch {
                throw FlashSyncError.settingsUnwritable(FlashSyncStore.reason(error))
            }
            dataStore.settings.reload()
        }
        let model: AppData
        do {
            model = try applySynced(json)
        } catch {
            if settingsChanged {
                if let previousSettingsBytes {
                    try? AtomicWrite.write(previousSettingsBytes, to: settingsURL)
                } else {
                    try? FileManager.default.removeItem(at: settingsURL)
                }
                dataStore.settings.reload()
            }
            throw error
        }
        if let base = try? readDataTree(model) {
            writeBaseline(data: base, settings: (try? readSettingsTree()) ?? settings)
        }
        return model
    }

    // MARK: Helpers

    nonisolated static func reason(_ error: Error) -> String {
        if case DataLoadError.unreadable(let why) = error { return why }
        return error.localizedDescription
    }

    nonisolated static func parseObject(_ bytes: Data) throws -> JSONObject {
        guard case .object(let o) = try JSONParser.parse(bytes) else { return JSONObject() }
        return o
    }

    nonisolated static func encode(_ o: JSONObject) throws -> [UInt8] {
        guard let d = try? JSONWriter.data(.object(o)) else { throw FlashSyncError.payloadTooDeep }
        return [UInt8](d)
    }
}
