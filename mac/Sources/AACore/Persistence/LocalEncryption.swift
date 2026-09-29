// Spec: 01 DATA-070–072, §4.6 (Windows AAENC1 detection), §6.5 (Mac AAENCM1 AES-GCM format, Keychain key),
//       DATA-215; ARCHITECTURE.md §6.2.
import Foundation
import CryptoKit

public enum LocalEncryptionError: Error, Sendable, Equatable {
    case notMacEncrypted
    case decryptFailed
    case keyUnavailable
}

public enum LocalEncryption {
    public enum FileClass: Sendable { case plain, mac, windowsDPAPI }

    /// `"AAENCM1\n"` (8 bytes).
    public static let macMagic = Data("AAENCM1\n".utf8)
    /// `"AAENC1\n"` (7 bytes).
    public static let windowsMagic = Data("AAENC1\n".utf8)

    public static func classify(_ bytes: Data) -> FileClass {
        if bytes.starts(with: windowsMagic) { return .windowsDPAPI }
        if bytes.starts(with: macMagic) { return .mac }
        return .plain
    }

    /// `magic ‖ AES.GCM combined (12-byte nonce ‖ ciphertext ‖ 16-byte tag)`, associated data = the magic.
    public static func encrypt(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: macMagic)
        guard let combined = box.combined else { throw LocalEncryptionError.decryptFailed }
        return macMagic + combined
    }

    public static func decrypt(_ blob: Data, key: SymmetricKey) throws -> Data {
        guard classify(blob) == .mac else { throw LocalEncryptionError.notMacEncrypted }
        do {
            let box = try AES.GCM.SealedBox(combined: blob.dropFirst(macMagic.count))
            return try AES.GCM.open(box, using: key, authenticating: macMagic)
        } catch {
            throw LocalEncryptionError.decryptFailed
        }
    }

    /// The local-data key (Keychain `AA.LocalDataKey` / `v1`, 32 random bytes). With `create`, a missing key is
    /// generated and stored; without it, a missing key → nil. Keychain failures throw.
    public static func key(secrets: SecretStore, create: Bool) throws -> SymmetricKey? {
        let id = Identifiers.Keychain.localDataKey
        if let d = try secrets.read(service: id.service, account: id.account), d.count == 32 {
            return SymmetricKey(data: d)
        }
        guard create else { return nil }
        let fresh = SecureRandom.bytes(32)
        try secrets.write(fresh, service: id.service, account: id.account)
        return SymmetricKey(data: fresh)
    }
}
