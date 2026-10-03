// Spec: 14 TOOLS-007 (copy byte-for-byte, no validation at set time; "configured" = the file exists), TOOLS-008 step 2
//       (`installed` or `web` object, `client_id` + `client_secret`), §3.1.14 step 1 (auth_uri / token_uri from the
//       file, else Google's defaults; Mac error wording).
import Foundation

public struct DriveClientSecret: Sendable, Equatable {
    public static let defaultAuthURI = "https://accounts.google.com/o/oauth2/v2/auth"
    public static let defaultTokenURI = "https://oauth2.googleapis.com/token"

    public var clientID: String
    public var clientSecret: String
    public var authURI: String
    public var tokenURI: String

    public init(clientID: String, clientSecret: String, authURI: String = DriveClientSecret.defaultAuthURI,
                tokenURI: String = DriveClientSecret.defaultTokenURI) {
        self.clientID = clientID; self.clientSecret = clientSecret; self.authURI = authURI; self.tokenURI = tokenURI
    }

    /// Parses Google's `client_secret.json` (`{"installed":{…}}` or `{"web":{…}}`).
    public static func parse(_ data: Data) throws(DriveError) -> DriveClientSecret {
        guard let root = try? JSONParser.parse(data).objectValue else { throw .invalidClientFile }
        guard let o = (root["installed"]?.objectValue ?? root["web"]?.objectValue),
              let id = o["client_id"]?.stringValue, !id.isEmpty,
              let secret = o["client_secret"]?.stringValue, !secret.isEmpty else { throw .invalidClientFile }
        func uri(_ key: String, _ fallback: String) -> String {
            if let s = o[key]?.stringValue, !NetText.isBlank(s), URL(string: s) != nil { return s }
            return fallback
        }
        return DriveClientSecret(clientID: id, clientSecret: secret, authURI: uri("auth_uri", defaultAuthURI),
                                 tokenURI: uri("token_uri", defaultTokenURI))
    }

    /// Reads `<AppFolder>/google_client_secret.json`; a missing file → `notConfigured`.
    public static func load(from url: URL) throws(DriveError) -> DriveClientSecret {
        guard FileManager.default.fileExists(atPath: url.path) else { throw .notConfigured }
        guard let data = try? Data(contentsOf: url) else { throw .invalidClientFile }
        return try parse(data)
    }

    /// TOOLS-007: create the data folder, then copy the chosen file byte-for-byte over
    /// `<AppFolder>/google_client_secret.json` (atomic replace).
    public static func install(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = try Data(contentsOf: source)
        try AtomicWrite.write(bytes, to: destination)
    }
}
