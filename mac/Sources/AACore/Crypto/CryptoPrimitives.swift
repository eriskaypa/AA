// Spec: 01 §6.11 (crypto mapping: CommonCrypto PBKDF2 / AES-CBC, CryptoKit HMAC, constant-time compare,
//       SecRandomCopyBytes, .NET Base64), §4.7–4.8; ARCHITECTURE.md §6.3.
import Foundation
import CommonCrypto
import CryptoKit
import Security

public enum CryptoError: Error, Sendable, Equatable {
    case cryptorFailed(Int32)
    case randomFailed
}

public enum PBKDF2 {
    /// PBKDF2-HMAC-SHA256 over the UTF-8 bytes of `password` (no normalisation, like .NET).
    public static func sha256(password: String, salt: Data, iterations: Int, length: Int) -> Data {
        let pw = Array(password.utf8)
        var out = [UInt8](repeating: 0, count: length)
        let status = pw.withUnsafeBufferPointer { pwBuf in
            salt.withUnsafeBytes { saltBuf in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     pwBuf.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                                     pw.count,
                                     saltBuf.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                     &out, length)
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed")     // only fails for invalid parameters
        return Data(out)
    }
}

public enum AESCBC {
    public static func encrypt(_ d: Data, key: Data, iv: Data) throws -> Data {
        try crypt(CCOperation(kCCEncrypt), d, key: key, iv: iv)
    }

    /// PKCS#7 padding.
    public static func decrypt(_ d: Data, key: Data, iv: Data) throws -> Data {
        try crypt(CCOperation(kCCDecrypt), d, key: key, iv: iv)
    }

    private static func crypt(_ op: CCOperation, _ input: Data, key: Data, iv: Data) throws -> Data {
        var out = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let status = input.withUnsafeBytes { inBuf in
            key.withUnsafeBytes { keyBuf in
                iv.withUnsafeBytes { ivBuf in
                    CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBuf.baseAddress, key.count, ivBuf.baseAddress,
                            inBuf.baseAddress, input.count, &out, out.count, &moved)
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.cryptorFailed(status) }
        return Data(out.prefix(moved))
    }
}

public enum HMACSHA256 {
    public static func mac(_ d: Data, key: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: d, using: SymmetricKey(data: key)))
    }
}

public enum ConstantTime {
    /// XOR-accumulate over equal-length buffers; a length mismatch → false.
    public static func equals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var acc: UInt8 = 0
        for (x, y) in zip(a, b) { acc |= x ^ y }
        return acc == 0
    }
}

public enum SecureRandom {
    public static func bytes(_ count: Int) -> Data {
        var buf = [UInt8](repeating: 0, count: count)
        if count > 0, SecRandomCopyBytes(kSecRandomDefault, count, &buf) != errSecSuccess {
            var g = SystemRandomNumberGenerator()                  // CSPRNG fallback (arc4random)
            for i in 0..<count { buf[i] = UInt8.random(in: 0...255, using: &g) }
        }
        return Data(buf)
    }
}

/// .NET `Convert.ToBase64String` / `Convert.FromBase64String`.
public enum NetBase64 {
    public static func encode(_ d: Data) -> String { d.base64EncodedString() }

    /// Ignores white space (space, TAB, CR, LF) like .NET; anything else outside the standard alphabet, a length
    /// that is not a multiple of 4, or bad padding → nil.
    public static func decode(_ s: String) -> Data? {
        var chars: [UInt8] = []
        chars.reserveCapacity(s.utf8.count)
        for c in s.utf8 where !(c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0A) { chars.append(c) }
        guard chars.count % 4 == 0 else { return nil }
        var pad = 0
        for (i, c) in chars.enumerated() {
            let isAlpha = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x2B || c == 0x2F
            if c == 0x3D {
                guard i >= chars.count - 2 else { return nil }
                pad += 1
            } else {
                guard isAlpha, pad == 0 else { return nil }
            }
        }
        if chars.isEmpty { return Data() }
        return Data(base64Encoded: Data(chars))
    }
}
