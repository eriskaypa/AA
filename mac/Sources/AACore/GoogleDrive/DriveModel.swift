// Spec: 14 §3.1.1 (constants), §3.1.3 (BundleNameQuery), §3.1.9 / §3.1.10 / §3.1.12 / §3.1.13 (exact query strings),
//       §4.5 (Drive metadata), TOOLS-018 (DriveBackup.Display), TOOLS-034 (error surfaces + setup hint, Mac addition),
//       Q-8 (long identity message). Source: AA/Services/GoogleDriveUploader.cs.
import Foundation

/// The constants of `GoogleDriveUploader` (14 §3.1.1).
public enum DriveConstants {
    public static let backupFolderName = "AA Backups"
    public static let syncFolderName = "AA Sync"
    public static let syncFileName = "AA-sync.zip"
    public static let lastModifiedProp = "aaLastModified"
    public static let identityProp = "aaIdentity"
    public static let scopeReadonly = "https://www.googleapis.com/auth/drive.readonly"
    public static let scopeFile = "https://www.googleapis.com/auth/drive.file"
    public static let scopes = [scopeReadonly, scopeFile]
    public static let scopeVersion = "v2-wholedrive"
    public static let iosBackupPrefix = "AA-backup"
    public static let folderMimeType = "application/vnd.google-apps.folder"
    public static let zipMimeType = "application/zip"
    /// The token file of the current scope (Windows name kept, 14 §6.3).
    public static let tokenFileName = "Google.Apis.Auth.OAuth2.Responses.TokenResponse-" + scopeVersion
    /// Drive's per-property limit (key + value, UTF-8 bytes).
    public static let appPropertyByteLimit = 124
}

/// The exact `q` strings sent to `files.list` (14 §3.1.3–§3.1.13, vector 7.6-7).
public enum DriveQuery {
    /// `(name contains 'aa-data' or name contains 'AA-backup' or name contains 'AA-sync' or name contains '.aaz')`.
    public static let bundleNames =
        "(name contains 'aa-data' or name contains '\(DriveConstants.iosBackupPrefix)' or name contains 'AA-sync' or name contains '.aaz')"

    /// Escapes `\` and `'` inside a quoted query literal (14 §3.1.10 SHOULD; the constants need none).
    public static func literal(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }

    /// §3.1.9 `ListBackupsAsync`.
    public static func listBackups(folderID: String?) -> String {
        if let folderID {
            return "('\(literal(folderID))' in parents or \(bundleNames)) and trashed=false and mimeType!='application/vnd.google-apps.folder'"
        }
        return "\(bundleNames) and trashed=false and mimeType!='application/vnd.google-apps.folder'"
    }

    /// §3.1.10 `EnsureFolderAsync`.
    public static func folder(named name: String) -> String {
        "mimeType='application/vnd.google-apps.folder' and name='\(literal(name))' and trashed=false"
    }

    /// §3.1.12 `GetBestRemoteAsync` (two concatenated literals: note the space before `and (name=`).
    public static let bestRemote = "trashed=false and mimeType!='application/vnd.google-apps.folder' "
        + "and (name='AA-sync.zip' or \(bundleNames))"

    /// §3.1.13 step 2 (`PushSyncAsync` existing-file lookup).
    public static func syncFile(folderID: String?) -> String {
        if let folderID { return "'\(literal(folderID))' in parents and name='AA-sync.zip' and trashed=false" }
        return "name='AA-sync.zip' and trashed=false"
    }
}

/// One Drive file as AA reads it.
public struct DriveFile: Sendable, Equatable {
    public var id: String
    public var name: String
    public var mimeType: String?
    /// RFC 3339 as Drive sent it.
    public var modifiedTime: String?
    public var appProperties: [String: String]
    public var webViewLink: String?

    public init(id: String, name: String, mimeType: String? = nil, modifiedTime: String? = nil,
                appProperties: [String: String] = [:], webViewLink: String? = nil) {
        self.id = id; self.name = name; self.mimeType = mimeType; self.modifiedTime = modifiedTime
        self.appProperties = appProperties; self.webViewLink = webViewLink
    }

    init(json o: JSONObject) {
        id = o["id"]?.stringValue ?? ""
        name = o["name"]?.stringValue ?? ""
        mimeType = o["mimeType"]?.stringValue
        modifiedTime = o["modifiedTime"]?.stringValue
        webViewLink = o["webViewLink"]?.stringValue
        var props: [String: String] = [:]
        if let p = o["appProperties"]?.objectValue {
            for (k, v) in p { if let s = v.stringValue { props[k] = s } }
        }
        appProperties = props
    }

    /// `DateTimeOffset.TryParse(modifiedTime).UtcDateTime` — Kind Utc ticks (14 §3.2.10).
    public var modifiedUtc: NetDateTime? {
        guard let raw = modifiedTime, let parsed = NetDateTime(parsing: raw, zone: TimeZone(identifier: "UTC")!) else {
            return nil
        }
        return NetDateTime(ticks: parsed.ticks, kind: .utc)
    }

    public var isBundleCandidate: Bool { BundleName.isRestorable(name: name, mimeType: mimeType) }
}

/// A restorable bundle offered by the backup picker (TOOLS-016, TOOLS-018).
public struct DriveBackup: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Drive's `modifiedTime` (UTC), nil when unparseable.
    public var modified: NetDateTime?

    public init(id: String, name: String, modified: NetDateTime?) { self.id = id; self.name = name; self.modified = modified }

    /// `{Name}    (uploaded {local yyyy-MM-dd HH:mm})` — exactly four spaces — or `{Name}`.
    public func display(zone: TimeZone = .current) -> String {
        guard let m = modified else { return name }
        return "\(name)    (uploaded \(m.toLocalTime(zone: zone).format(.isoMinute, zone: zone)))"
    }
}

/// `GetBestRemoteAsync`'s result (14 §3.1.12).
public struct DriveRemoteState: Sendable, Equatable {
    public var fileID: String
    /// `aaLastModified` parsed round-trip (nil when absent / unparseable).
    public var lastModified: NetDateTime?
    public var driveModified: NetDateTime?
    public var identity: String?

    public init(fileID: String, lastModified: NetDateTime?, driveModified: NetDateTime?, identity: String?) {
        self.fileID = fileID; self.lastModified = lastModified; self.driveModified = driveModified; self.identity = identity
    }
}

/// `UploadAsync`'s result.
public struct DriveUploadResult: Sendable, Equatable {
    public var name: String
    public var link: String?
    public init(name: String, link: String?) { self.name = name; self.link = link }
}

/// Every error the Drive family raises. `localizedDescription` is the text the Windows message boxes show
/// (`ex.Message`), with the setup hint appended where TOOLS-034 asks for it.
public enum DriveError: Error, Sendable, Equatable, LocalizedError {
    /// TOOLS-008 step 1 (exact).
    case notConfigured
    /// 14 §3.1.14 step 1 (Mac wording).
    case invalidClientFile
    /// The OAuth endpoint refused (`error`, `error_description`), e.g. `access_denied`, `invalid_grant`.
    case oauth(code: String, description: String)
    /// A Drive REST error: HTTP status, Google's `error.message` and the first `errors[].reason`.
    case api(status: Int, message: String, reason: String?)
    /// Q-8: Drive refused the metadata because the app identity is too long.
    case identityTooLong(underlying: String)
    case uploadIncomplete
    case syncUploadIncomplete
    case downloadIncomplete
    /// The user pressed Cancel on the waiting sheet (quiet status, 14 §6.3).
    case signInCancelled
    /// No browser answer within 5 minutes (14 §6.3).
    case signInTimedOut
    /// A background check needs a browser sign-in, which it never opens.
    case interactiveSignInRequired
    case loopbackFailed(String)
    case transport(String)

    /// The setup hint appended for `access_denied`, `insufficientPermissions` and `invalid_client` (TOOLS-034).
    public static let setupHint = "In Google Cloud Console: enable the Google Drive API, use an OAuth client of type 'Desktop app', and \u{2014} because drive.readonly is a restricted scope \u{2014} keep the OAuth consent screen in Testing with your Google account added as a test user."

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No Google OAuth client configured. Use File \u{25B8} 'Set Google OAuth client...' first."
        case .invalidClientFile:
            return "The OAuth client file is not a valid Google client_secret.json."
        case .oauth(let code, let description):
            let text = "Error:\"\(code)\", Description:\"\(description)\", Uri:\"\""
            return ["access_denied", "invalid_client", "unauthorized_client"].contains(code) ? text + "\n\n" + DriveError.setupHint : text
        case .api(let status, let message, let reason):
            let text = "The service drive has thrown an exception. HttpStatusCode is \(DriveError.statusName(status)). \(message)"
            return reason == "insufficientPermissions" ? text + "\n\n" + DriveError.setupHint : text
        case .identityTooLong(let underlying):
            return "App identity is too long for Google Drive metadata. Shorten it with File \u{25B8} Set App Identity\u{2026} and try again.\n\n\(underlying)"
        case .uploadIncomplete: return "Upload did not complete."
        case .syncUploadIncomplete: return "Sync upload did not complete."
        case .downloadIncomplete: return "Download did not complete."
        case .signInCancelled: return "Google sign-in cancelled."
        case .signInTimedOut: return "Google sign-in timed out (no answer from the browser within 5 minutes)."
        case .interactiveSignInRequired: return "Google sign-in required."
        case .loopbackFailed(let m): return "Could not start the local sign-in listener: \(m)"
        case .transport(let m): return m
        }
    }

    /// .NET `HttpStatusCode` names for the statuses Drive returns.
    static func statusName(_ s: Int) -> String {
        switch s {
        case 400: return "BadRequest"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "NotFound"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 412: return "PreconditionFailed"
        case 413: return "RequestEntityTooLarge"
        case 429: return "TooManyRequests"
        case 500: return "InternalServerError"
        case 502: return "BadGateway"
        case 503: return "ServiceUnavailable"
        case 504: return "GatewayTimeout"
        default: return String(s)
        }
    }
}
