// Spec: 01 §4.3 (settings.json keys, order, absent values), §3.1, DATA-150–152, DATA-182 (per-key tolerance);
//       ARCHITECTURE.md §4.11.
import Foundation

/// A value snapshot of `settings.json`. Decoding never throws: a key whose value has the wrong JSON type reads as
/// that key's default for that key only (S09); the raw file keeps it until that very key is set.
public struct AppSettings: Sendable, Equatable {
    public var currentDataFile: String?
    public var passwordHash: String?
    public var passwordSalt: String?
    public var googleDriveFolder: String?
    public var syncOnSave: Bool
    public var darkMode: Bool
    public var folderBuilderBase: String?
    public var sharedSaveFile: String?
    public var encryptLocalData: Bool
    /// The Mac never sets it; preserved verbatim (DECISIONS 12).
    public var geminiApiKey: String?
    public var appIdentity: String?
    public var textOnlyExport: Bool
    /// Unknown keys (preserved and merged; Flash Sync writes them).
    public var extra: JSONObject

    /// Known keys in 01 §4.3 declaration / emission order.
    public static let knownKeys = ["CurrentDataFile", "PasswordHash", "PasswordSalt", "GoogleDriveFolder",
                                   "SyncOnSave", "DarkMode", "FolderBuilderBase", "SharedSaveFile",
                                   "EncryptLocalData", "GeminiApiKey", "AppIdentity", "TextOnlyExport"]

    public init(currentDataFile: String? = nil, passwordHash: String? = nil, passwordSalt: String? = nil,
                googleDriveFolder: String? = nil, syncOnSave: Bool = false, darkMode: Bool = false,
                folderBuilderBase: String? = nil, sharedSaveFile: String? = nil, encryptLocalData: Bool = false,
                geminiApiKey: String? = nil, appIdentity: String? = nil, textOnlyExport: Bool = false,
                extra: JSONObject = JSONObject()) {
        self.currentDataFile = currentDataFile; self.passwordHash = passwordHash; self.passwordSalt = passwordSalt
        self.googleDriveFolder = googleDriveFolder; self.syncOnSave = syncOnSave; self.darkMode = darkMode
        self.folderBuilderBase = folderBuilderBase; self.sharedSaveFile = sharedSaveFile
        self.encryptLocalData = encryptLocalData; self.geminiApiKey = geminiApiKey; self.appIdentity = appIdentity
        self.textOnlyExport = textOnlyExport; self.extra = extra
    }

    /// The only decoder; never throws (per-key tolerance).
    public init(json o: JSONObject) {
        func str(_ k: String) -> String? { o[k]?.stringValue }
        func flag(_ k: String) -> Bool { o[k]?.boolValue ?? false }
        self.init(currentDataFile: str("CurrentDataFile"), passwordHash: str("PasswordHash"),
                  passwordSalt: str("PasswordSalt"), googleDriveFolder: str("GoogleDriveFolder"),
                  syncOnSave: flag("SyncOnSave"), darkMode: flag("DarkMode"),
                  folderBuilderBase: str("FolderBuilderBase"), sharedSaveFile: str("SharedSaveFile"),
                  encryptLocalData: flag("EncryptLocalData"), geminiApiKey: str("GeminiApiKey"),
                  appIdentity: str("AppIdentity"), textOnlyExport: flag("TextOnlyExport"))
        var known = Set<Ordinal.Key>()
        for k in AppSettings.knownKeys { known.insert(Ordinal.Key(k)) }
        extra = o.filtering(excluding: known)
    }

    /// The JSON value of one known key in this snapshot (nil = omitted).
    public func jsonValue(forKey key: String) -> JSONValue? {
        switch key {
        case "CurrentDataFile": return currentDataFile.map(JSONValue.string)
        case "PasswordHash": return passwordHash.map(JSONValue.string)
        case "PasswordSalt": return passwordSalt.map(JSONValue.string)
        case "GoogleDriveFolder": return googleDriveFolder.map(JSONValue.string)
        case "SyncOnSave": return .bool(syncOnSave)
        case "DarkMode": return .bool(darkMode)
        case "FolderBuilderBase": return folderBuilderBase.map(JSONValue.string)
        case "SharedSaveFile": return sharedSaveFile.map(JSONValue.string)
        case "EncryptLocalData": return .bool(encryptLocalData)
        case "GeminiApiKey": return geminiApiKey.map(JSONValue.string)
        case "AppIdentity": return appIdentity.map(JSONValue.string)
        case "TextOnlyExport": return .bool(textOnlyExport)
        default: return extra.rawValue(forKey: key)
        }
    }
}
