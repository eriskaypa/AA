// Spec: 14 TOOLS-010 (scope-versioned token key), TOOLS-011 (re-consent notice), TOOLS-012 (token encrypted at rest),
//       TOOLS-013 (sign out = delete the folder), §3.1.6, §4.3, §6.3 (Mac format `AAKCGCM1` + AES-256-GCM combined,
//       key in the Keychain, HasToken requires the Mac magic, NeedsReconsent = !HasToken and any file), vector 7.6-8;
//       01 DATA-073, DATA-215 (Keychain item `AA` / `google-token-key`), OC-34; ARCHITECTURE.md §6.8.
import Foundation
import CryptoKit

/// The OAuth token as the Google auth library stores it (same field names as the Windows file, 14 §4.3).
public struct DriveTokenResponse: Sendable, Equatable {
    public var accessToken: String
    public var tokenType: String
    public var expiresIn: Int64?
    public var refreshToken: String?
    public var scope: String?
    public var idToken: String?
    /// When the token was issued (UTC).
    public var issuedUtc: NetDateTime

    public init(accessToken: String, tokenType: String = "Bearer", expiresIn: Int64?, refreshToken: String?,
                scope: String?, idToken: String? = nil, issuedUtc: NetDateTime) {
        self.accessToken = accessToken; self.tokenType = tokenType; self.expiresIn = expiresIn
        self.refreshToken = refreshToken; self.scope = scope; self.idToken = idToken; self.issuedUtc = issuedUtc
    }

    /// Valid for at least `margin` more seconds at `now` (14 §3.1.14 step 2: five minutes).
    public func isValid(at now: NetDateTime, marginSeconds: Int64 = 300) -> Bool {
        guard !accessToken.isEmpty, let e = expiresIn else { return false }
        let expiry = issuedUtc.ticks + e * NetDateTime.ticksPerSecond
        return now.ticks + marginSeconds * NetDateTime.ticksPerSecond < expiry
    }

    /// The token endpoint's JSON (`access_token`, `expires_in`, …), stamped with `issued`.
    public init?(endpointJSON o: JSONObject, issuedUtc: NetDateTime) {
        guard let at = o["access_token"]?.stringValue, !at.isEmpty else { return nil }
        accessToken = at
        tokenType = o["token_type"]?.stringValue ?? "Bearer"
        expiresIn = o["expires_in"]?.numberValue?.int64Value
        refreshToken = o["refresh_token"]?.stringValue
        scope = o["scope"]?.stringValue
        idToken = o["id_token"]?.stringValue
        self.issuedUtc = issuedUtc
    }

    /// Newtonsoft-shaped JSON (`Issued` local, `IssuedUtc` UTC).
    public func json(zone: TimeZone = .current) -> Data {
        var o = JSONObject()
        o.set("access_token", .string(accessToken))
        o.set("token_type", .string(tokenType))
        o.set("expires_in", expiresIn.map { .number(JSONNumber($0)) } ?? .null)
        o.set("refresh_token", refreshToken.map(JSONValue.string) ?? .null)
        o.set("scope", scope.map(JSONValue.string) ?? .null)
        o.set("id_token", idToken.map(JSONValue.string) ?? .null)
        let local = NetDateTime(ticks: issuedUtc.ticks, kind: .utc).toLocalTime(zone: zone)
        o.set("Issued", .string(local.formattedISO(zone: zone)))
        o.set("IssuedUtc", .string(NetDateTime(ticks: issuedUtc.ticks, kind: .utc).formattedISO(zone: zone)))
        return (try? JSONWriter.data(.object(o))) ?? Data()
    }

    public init?(storedJSON data: Data) {
        guard let o = try? JSONParser.parse(data).objectValue,
              let at = o["access_token"]?.stringValue else { return nil }
        accessToken = at
        tokenType = o["token_type"]?.stringValue ?? "Bearer"
        expiresIn = o["expires_in"]?.numberValue?.int64Value
        refreshToken = o["refresh_token"]?.stringValue
        scope = o["scope"]?.stringValue
        idToken = o["id_token"]?.stringValue
        let utcZone = TimeZone(identifier: "UTC")!
        if let s = o["IssuedUtc"]?.stringValue, let d = NetDateTime(parsing: s, zone: utcZone) {
            issuedUtc = NetDateTime(ticks: d.ticks, kind: .utc)
        } else {
            issuedUtc = NetDateTime(ticks: 0, kind: .utc)
        }
    }
}

/// The `google-token/` folder with its Keychain-held AES-256-GCM key (Sendable; usable off the main actor).
public struct DriveTokenVault: Sendable {
    public static let macMagic = Data("AAKCGCM1".utf8)
    public static let windowsMagic = Data("AADPAPI1".utf8)

    public let folder: URL
    public let secrets: SecretStore

    public init(folder: URL, secrets: SecretStore) { self.folder = folder; self.secrets = secrets }

    public var tokenFile: URL { folder.appending(path: DriveConstants.tokenFileName) }

    private var fileNames: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?
            .filter { name in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: folder.appending(path: name).path, isDirectory: &isDir) && !isDir.boolValue
            } ?? []
    }

    /// TOOLS-010 + §6.3: a file whose name ends (ordinal) with `-v2-wholedrive` exists **and starts with the Mac
    /// magic** (a copied Windows DPAPI token is undecryptable here and must not count).
    public var hasToken: Bool {
        for name in fileNames where DriveOrdinal.hasSuffix(name, "-" + DriveConstants.scopeVersion) {
            if let h = try? FileHandle(forReadingFrom: folder.appending(path: name)) {
                let head = (try? h.read(upToCount: DriveTokenVault.macMagic.count)) ?? Data()
                try? h.close()
                if head == DriveTokenVault.macMagic { return true }
            }
        }
        return false
    }

    /// TOOLS-011: `!hasToken` and the folder contains any file.
    public var needsReconsentForWholeDrive: Bool { !hasToken && !fileNames.isEmpty }

    private func key(create: Bool) throws -> SymmetricKey? {
        let item = Identifiers.Keychain.googleTokenKey
        if let d = try secrets.read(service: item.service, account: item.account), d.count == 32 {
            return SymmetricKey(data: d)
        }
        guard create else { return nil }
        let fresh = SecureRandom.bytes(32)
        try secrets.write(fresh, service: item.service, account: item.account)
        return SymmetricKey(data: fresh)
    }

    /// The stored token, or nil (missing, foreign, undecryptable or unreadable → "no token", like Windows).
    /// A legacy plaintext JSON token is returned and re-stored encrypted (DATA-073).
    public func load() -> DriveTokenResponse? {
        guard let bytes = try? Data(contentsOf: tokenFile) else { return nil }
        if bytes.starts(with: DriveTokenVault.macMagic) {
            guard let k = try? key(create: false),
                  let box = try? AES.GCM.SealedBox(combined: bytes.dropFirst(DriveTokenVault.macMagic.count)),
                  let plain = try? AES.GCM.open(box, using: k) else { return nil }
            return DriveTokenResponse(storedJSON: plain)
        }
        if bytes.starts(with: DriveTokenVault.windowsMagic) { return nil }
        guard let legacy = DriveTokenResponse(storedJSON: bytes) else { return nil }
        try? store(legacy)
        return legacy
    }

    /// Writes `AAKCGCM1` + AES-GCM combined (nonce ‖ ciphertext ‖ tag) atomically; creates the folder.
    public func store(_ token: DriveTokenResponse) throws {
        guard let k = try key(create: true) else { return }
        let sealed = try AES.GCM.seal(token.json(), using: k)
        guard let combined = sealed.combined else { throw DriveError.transport("Could not encrypt the Google token.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try AtomicWrite.write(DriveTokenVault.macMagic + combined, to: tokenFile)
    }

    /// Removes the current-scope token (the library's `DeleteAsync` after a rejected refresh, §3.1.6).
    public func deleteToken() { try? FileManager.default.removeItem(at: tokenFile) }

    /// TOOLS-013: recursively delete the whole folder (all keys, all versions); errors swallowed.
    public func signOut() { try? FileManager.default.removeItem(at: folder) }

    /// The constructor of the Windows store creates the folder on the first Drive action (TOOLS-012).
    public func ensureFolder() { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
}

public enum GoogleTokenStore {
    @MainActor public static func vault(_ ds: DataStore) -> DriveTokenVault {
        DriveTokenVault(folder: ds.googleTokenFolder, secrets: ds.secrets)
    }

    @MainActor public static func hasToken(_ ds: DataStore) -> Bool { vault(ds).hasToken }

    @MainActor public static func needsReconsentForWholeDrive(_ ds: DataStore) -> Bool {
        vault(ds).needsReconsentForWholeDrive
    }

    /// "Configured" = `<AppFolder>/google_client_secret.json` exists (TOOLS-007).
    @MainActor public static func isConfigured(_ ds: DataStore) -> Bool {
        FileManager.default.fileExists(atPath: ds.googleClientSecretFile.path)
    }

    /// TOOLS-013.
    @MainActor public static func signOut(_ ds: DataStore) { vault(ds).signOut() }
}
