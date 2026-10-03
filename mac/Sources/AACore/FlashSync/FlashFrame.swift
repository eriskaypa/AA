// Spec: 13 §3.7 / FLASH-066 (frame format), FLASH-069 (hostile-input hardening), FLASH-070 (manifest label);
//       QR_SYNC_PROTOCOL.md §7. All integers big-endian; these are the bytes BEFORE Base45.

/// Payload kind carried by the manifest (wire byte 23).
public enum FlashFrameKind: UInt8, Sendable, Equatable {
    case changeSet = 0
    case fullSnapshot = 1
}

/// Type 0: the shape of the transfer, re-shown every 12th emitted frame.
public struct FlashManifestFrame: Sendable, Equatable {
    public var session: UInt16
    public var codedBytes: UInt32
    public var rawBytes: UInt32
    public var chunkSize: UInt16
    public var chunkCount: UInt16
    public var crc32: UInt32
    public var kind: FlashFrameKind
    public var label: String

    public init(session: UInt16, codedBytes: UInt32, rawBytes: UInt32, chunkSize: UInt16, chunkCount: UInt16,
                crc32: UInt32, kind: FlashFrameKind, label: String) {
        self.session = session
        self.codedBytes = codedBytes
        self.rawBytes = rawBytes
        self.chunkSize = chunkSize
        self.chunkCount = chunkCount
        self.crc32 = crc32
        self.kind = kind
        self.label = label
    }
}

/// Type 1: one fountain symbol — the XOR of the chunks `FlashFountain.indices(seed, K)` selects.
public struct FlashDataFrame: Sendable, Equatable {
    public var session: UInt16
    public var seed: UInt32
    public var payload: [UInt8]

    public init(session: UInt16, seed: UInt32, payload: [UInt8]) {
        self.session = session
        self.seed = seed
        self.payload = payload
    }
}

/// A decoded frame.
public enum FlashDecodedFrame: Sendable, Equatable {
    case manifest(FlashManifestFrame)
    case data(FlashDataFrame)
}

/// Binary frame encode/decode. Magic "AAQ" + version 1.
public enum FlashFrame {
    public static let magic: [UInt8] = [0x41, 0x41, 0x51]
    public static let version: UInt8 = 0x01
    public static let typeManifest: UInt8 = 0x00
    public static let typeData: UInt8 = 0x01
    /// The label is truncated to this many UTF-8 BYTES (it may split a character; the decoder repairs it).
    public static let maxLabelBytes = 120

    public static func encodeManifest(_ m: FlashManifestFrame) -> [UInt8] {
        var label = Array(m.label.utf8)
        if label.count > maxLabelBytes { label = Array(label.prefix(maxLabelBytes)) }
        var b: [UInt8] = []
        b.reserveCapacity(25 + label.count)
        b += magic
        b.append(version)
        b.append(typeManifest)
        putU16(&b, m.session)
        putU32(&b, m.codedBytes)
        putU32(&b, m.rawBytes)
        putU16(&b, m.chunkSize)
        putU16(&b, m.chunkCount)
        putU32(&b, m.crc32)
        b.append(m.kind.rawValue)
        b.append(UInt8(label.count))
        b += label
        return b
    }

    public static func encodeData(_ d: FlashDataFrame) -> [UInt8] {
        var b: [UInt8] = []
        b.reserveCapacity(11 + d.payload.count)
        b += magic
        b.append(version)
        b.append(typeData)
        putU16(&b, d.session)
        putU32(&b, d.seed)
        b += d.payload
        return b
    }

    /// nil when the bytes are not ours or are malformed: shorter than 5, wrong magic/version, unknown type; a
    /// manifest shorter than 25, with chunkSize 0 or chunkCount 0, an unknown kind, or a label running past the
    /// end; a data frame without at least one payload byte. Trailing bytes after a manifest label are ignored.
    public static func decode(_ f: [UInt8]) -> FlashDecodedFrame? {
        guard f.count >= 5, f[0] == magic[0], f[1] == magic[1], f[2] == magic[2], f[3] == version else { return nil }
        switch f[4] {
        case typeManifest:
            guard f.count >= 25 else { return nil }
            let chunkSize = u16(f, 15), chunkCount = u16(f, 17)
            guard chunkSize != 0, chunkCount != 0 else { return nil }
            guard let kind = FlashFrameKind(rawValue: f[23]) else { return nil }
            let labelLen = Int(f[24])
            guard f.count >= 25 + labelLen else { return nil }
            let label = String(decoding: f[25 ..< 25 + labelLen], as: UTF8.self)   // invalid UTF-8 → U+FFFD
            return .manifest(FlashManifestFrame(session: u16(f, 5), codedBytes: u32(f, 7), rawBytes: u32(f, 11),
                                                chunkSize: chunkSize, chunkCount: chunkCount, crc32: u32(f, 19),
                                                kind: kind, label: label))
        case typeData:
            guard f.count > 11 else { return nil }
            return .data(FlashDataFrame(session: u16(f, 5), seed: u32(f, 7), payload: Array(f[11...])))
        default:
            return nil
        }
    }

    private static func putU16(_ b: inout [UInt8], _ v: UInt16) {
        b.append(UInt8(v >> 8)); b.append(UInt8(v & 0xFF))
    }

    private static func putU32(_ b: inout [UInt8], _ v: UInt32) {
        b.append(UInt8(v >> 24)); b.append(UInt8((v >> 16) & 0xFF)); b.append(UInt8((v >> 8) & 0xFF)); b.append(UInt8(v & 0xFF))
    }

    private static func u16(_ f: [UInt8], _ o: Int) -> UInt16 { UInt16(f[o]) << 8 | UInt16(f[o + 1]) }

    private static func u32(_ f: [UInt8], _ o: Int) -> UInt32 {
        UInt32(f[o]) << 24 | UInt32(f[o + 1]) << 16 | UInt32(f[o + 2]) << 8 | UInt32(f[o + 3])
    }
}
