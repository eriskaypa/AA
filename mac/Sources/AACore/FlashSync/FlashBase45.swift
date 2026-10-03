// Spec: 13 §3.1 / FLASH-060 (Base45, RFC 9285 — the text that goes into every QR code), QR_SYNC_PROTOCOL.md §3.
// The alphabet is exactly QR's alphanumeric set, so a QR encoder packs it at 5.5 bits per character.
// Invalid input decodes to nil — that is how foreign QR codes are ignored. Frames are NEVER trimmed: space is a
// legal Base45 character and a frame may start or end with it.

/// RFC 9285 Base45 over raw bytes.
public enum FlashBase45 {
    /// Index 0…44: digits, `A`–`Z`, space, `$ % * + - . / :`.
    public static let alphabet: [UInt8] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".utf8)

    /// Reverse table over the 7-bit code points; -1 = not in the alphabet.
    private static let reverse: [Int8] = {
        var t = [Int8](repeating: -1, count: 128)
        for (i, c) in alphabet.enumerated() { t[Int(c)] = Int8(i) }
        return t
    }()

    /// Pairs `[a, b]` → three characters of `n = a·256 + b` (least significant first); a trailing byte → two.
    public static func encode(_ bytes: [UInt8]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count / 2 * 3 + 2)
        var i = 0
        while i + 1 < bytes.count {
            let n = Int(bytes[i]) << 8 | Int(bytes[i + 1])
            out.append(alphabet[n % 45])
            out.append(alphabet[(n / 45) % 45])
            out.append(alphabet[n / 2025])
            i += 2
        }
        if i < bytes.count {
            let a = Int(bytes[i])
            out.append(alphabet[a % 45])
            out.append(alphabet[a / 45])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// The inverse of `encode`, or nil on any invalid input: a length ≡ 1 (mod 3), a character outside the
    /// alphabet (lower case, non-ASCII, `!`…), a 3-character group above 0xFFFF or a 2-character tail above 0xFF.
    public static func decode(_ text: String) -> [UInt8]? {
        let chars = Array(text.utf8)
        if chars.count % 3 == 1 { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 3 * 2 + 1)
        func value(_ c: UInt8) -> Int? {
            guard c < 128 else { return nil }
            let v = reverse[Int(c)]
            return v < 0 ? nil : Int(v)
        }
        var i = 0
        while i + 2 < chars.count {
            guard let c0 = value(chars[i]), let c1 = value(chars[i + 1]), let c2 = value(chars[i + 2]) else { return nil }
            let n = c0 + c1 * 45 + c2 * 2025
            guard n <= 0xFFFF else { return nil }
            out.append(UInt8(n >> 8))
            out.append(UInt8(n & 0xFF))
            i += 3
        }
        if i < chars.count {
            guard chars.count - i == 2, let c0 = value(chars[i]), let c1 = value(chars[i + 1]) else { return nil }
            let n = c0 + c1 * 45
            guard n <= 0xFF else { return nil }
            out.append(UInt8(n))
        }
        return out
    }
}
