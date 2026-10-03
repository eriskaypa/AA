// Spec: 01 §3.13, §4.7 (byte-exact `enc:` blobs), §4.8, §7.1–7.2, App. K01–K07; ARCHITECTURE.md §6.3.
import Foundation

public enum PasswordHashing {
    public static let iterations = 100_000, saltSize = 16, keySize = 32
    /// DECISIONS Q-1: keep exactly.
    public static let masterPassword = "redemption"

    public static func newSalt() -> Data { SecureRandom.bytes(saltSize) }

    /// PBKDF2-HMAC-SHA256(UTF-8(password), salt, 100 000, 32 bytes).
    public static func hash(password: String, salt: Data) -> Data {
        PBKDF2.sha256(password: password, salt: salt, iterations: iterations, length: keySize)
    }

    /// Ordinal comparison with the master password.
    public static func isMaster(_ password: String) -> Bool { Ordinal.equals(password, masterPassword) }
}

/// Legacy encrypted container bodies: `"enc:" + Base64(IV[16] ‖ AES-256-CBC(PKCS#7) ‖ HMAC-SHA256[32])`,
/// keys = PBKDF2(password, settings salt, 100 000, 64) split 32 / 32 (01 §4.7).
public enum LegacyBodyCrypto {
    public static let prefix = "enc:"
    static let ivSize = 16, macSize = 32

    /// Non-empty and starts with `enc:` (ordinal, case-sensitive).
    public static func isEncrypted(_ text: String) -> Bool {
        let p = Array(prefix.utf16), u = text.utf16
        guard u.count >= p.count else { return false }
        return u.prefix(p.count).elementsEqual(p)
    }

    static func keys(password: String, salt: Data) -> (enc: Data, mac: Data) {
        let k = PBKDF2.sha256(password: password, salt: salt, iterations: PasswordHashing.iterations, length: 64)
        return (k.prefix(32), k.suffix(32))
    }

    /// nil on any failure — never guesses (wrong password, tampered data, short blob, bad Base64).
    public static func decrypt(_ blob: String, password: String, saltBase64: String) -> String? {
        guard isEncrypted(blob), let salt = NetBase64.decode(saltBase64), !salt.isEmpty else { return nil }
        return decrypt(blob, keys: keys(password: password, salt: salt))
    }

    /// `decrypt` with pre-derived keys (the D-5 bulk migration derives once per candidate password).
    static func decrypt(_ blob: String, keys k: (enc: Data, mac: Data)) -> String? {
        guard isEncrypted(blob) else { return nil }
        guard let combined = NetBase64.decode(String(blob.utf16.dropFirst(prefix.utf16.count))!),
              combined.count >= ivSize + macSize + 16 else { return nil }
        let bytes = [UInt8](combined)
        let iv = Data(bytes[0..<ivSize])
        let tag = Data(bytes[(bytes.count - macSize)...])
        let ct = Data(bytes[ivSize..<(bytes.count - macSize)])
        let (enc, mac) = k
        guard ConstantTime.equals(HMACSHA256.mac(iv + ct, key: mac), tag) else { return nil }
        guard let plain = try? AESCBC.decrypt(ct, key: enc, iv: iv) else { return nil }
        return decodeWithBOMDetection(plain)
    }

    /// Windows form: the plaintext is `EF BB BF ‖ UTF-8(xaml)` (StreamWriter(Encoding.UTF8) writes a BOM).
    /// `iv` is random unless injected (tests). An undecodable salt derives with an empty salt.
    public static func encrypt(_ xaml: String, password: String, saltBase64: String, iv: Data? = nil) -> String {
        let salt = NetBase64.decode(saltBase64) ?? Data()
        let (enc, mac) = keys(password: password, salt: salt)
        let ivBytes = iv ?? SecureRandom.bytes(ivSize)
        let plain = Data([0xEF, 0xBB, 0xBF]) + Data(xaml.utf8)
        let ct = (try? AESCBC.encrypt(plain, key: enc, iv: ivBytes)) ?? Data()
        let tag = HMACSHA256.mac(ivBytes + ct, key: mac)
        return prefix + NetBase64.encode(ivBytes + ct + tag)
    }

    /// .NET `StreamReader(stream, Encoding.UTF8)` decoding: UTF-8 BOM stripped; UTF-16 LE/BE and UTF-32 LE/BE BOMs
    /// switch the encoding; invalid sequences → U+FFFD.
    static func decodeWithBOMDetection(_ d: Data) -> String {
        let b = [UInt8](d)
        if b.count >= 4, b[0] == 0xFF, b[1] == 0xFE, b[2] == 0, b[3] == 0 { return utf32(Array(b[4...]), littleEndian: true) }
        if b.count >= 4, b[0] == 0, b[1] == 0, b[2] == 0xFE, b[3] == 0xFF { return utf32(Array(b[4...]), littleEndian: false) }
        if b.count >= 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF { return String(decoding: b[3...], as: UTF8.self) }
        if b.count >= 2, b[0] == 0xFF, b[1] == 0xFE { return utf16(Array(b[2...]), littleEndian: true) }
        if b.count >= 2, b[0] == 0xFE, b[1] == 0xFF { return utf16(Array(b[2...]), littleEndian: false) }
        return String(decoding: b, as: UTF8.self)
    }

    static func utf16(_ b: [UInt8], littleEndian: Bool) -> String {
        var units: [UInt16] = []
        var i = 0
        while i + 1 < b.count {
            units.append(littleEndian ? UInt16(b[i]) | UInt16(b[i + 1]) << 8 : UInt16(b[i]) << 8 | UInt16(b[i + 1]))
            i += 2
        }
        var s = String(decoding: units, as: UTF16.self)
        if b.count % 2 == 1 { s.append("\u{FFFD}") }
        return s
    }

    static func utf32(_ b: [UInt8], littleEndian: Bool) -> String {
        var scalars = String.UnicodeScalarView()
        var i = 0
        while i + 3 < b.count {
            let v = littleEndian
                ? UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
                : UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
            scalars.append(Unicode.Scalar(v) ?? "\u{FFFD}")
            i += 4
        }
        if b.count % 4 != 0 { scalars.append("\u{FFFD}") }
        return String(scalars)
    }
}
