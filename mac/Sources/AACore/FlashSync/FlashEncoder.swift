// Spec: 13 §3.8 / FLASH-022 (session 1…65535), FLASH-023 (frame stream), FLASH-067 (encoder);
//       QR_SYNC_PROTOCOL.md §8. The stream never ends: M, 0…10, M, 11…21, M, 22, … — manifests NEVER consume a
//       seed (separate counters), which is what makes a clean capture cost exactly K data frames.
import Foundation

public enum FlashEncoderError: Error, Equatable, Sendable, LocalizedError {
    /// "Payload too large for Flash Sync: {K} chunks (max 65535)."
    case payloadTooLarge(chunks: Int)
    case compressionFailed

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge(let k): return "Payload too large for Flash Sync: \(k) chunks (max 65535)."
        case .compressionFailed: return "The payload could not be compressed."
        }
    }
}

/// The fountain encoder. Not thread-safe: confine one instance to one queue (the sender's render queue).
public final class FlashEncoder: @unchecked Sendable {
    public static let defaultChunkSize = 900
    /// A manifest is emitted at positions 0, 12, 24, …
    public static let manifestInterval = 12

    public let manifest: FlashManifestFrame
    public let chunkCount: Int
    public let chunkSize: Int
    private let chunks: [[UInt8]]
    /// Frames shown so far (drives the manifest cadence).
    public private(set) var emitted: UInt64 = 0
    /// The NEXT seed to use — a separate counter.
    public private(set) var seed: UInt32 = 0

    /// DEFLATEs `payload` and splits it into K = ⌈coded / chunkSize⌉ zero-padded chunks.
    public convenience init(payload: [UInt8], kind: FlashFrameKind, label: String, session: UInt16,
                            chunkSize: Int = FlashEncoder.defaultChunkSize) throws {
        let coded: [UInt8]
        do { coded = try RawDeflate.compress(payload) } catch { throw FlashEncoderError.compressionFailed }
        try self.init(coded: coded, rawBytes: UInt32(truncatingIfNeeded: payload.count), kind: kind, label: label,
                      session: session, chunkSize: chunkSize)
    }

    /// Already-coded bytes (vector tests keep DEFLATE out of the loop, 13 §7.7).
    public init(coded: [UInt8], rawBytes: UInt32, kind: FlashFrameKind, label: String, session: UInt16,
                chunkSize: Int = FlashEncoder.defaultChunkSize) throws {
        precondition(chunkSize > 0 && chunkSize <= Int(UInt16.max), "chunkSize must fit in a UInt16")
        let k = max(1, (coded.count + chunkSize - 1) / chunkSize)
        guard k <= 65535 else { throw FlashEncoderError.payloadTooLarge(chunks: k) }
        var parts: [[UInt8]] = []
        parts.reserveCapacity(k)
        for i in 0 ..< k {
            let start = i * chunkSize
            let end = min(start + chunkSize, coded.count)
            var c = start < end ? Array(coded[start ..< end]) : []
            if c.count < chunkSize { c += [UInt8](repeating: 0, count: chunkSize - c.count) }
            parts.append(c)
        }
        chunks = parts
        chunkCount = k
        self.chunkSize = chunkSize
        manifest = FlashManifestFrame(session: session, codedBytes: UInt32(truncatingIfNeeded: coded.count),
                                      rawBytes: rawBytes, chunkSize: UInt16(chunkSize), chunkCount: UInt16(k),
                                      crc32: CRC32.checksum(coded), kind: kind, label: label)
    }

    /// The Base45 text of the next QR code.
    public func next() -> String { FlashBase45.encode(nextFrameBytes()) }

    /// The binary frame of the next QR code (before Base45).
    public func nextFrameBytes() -> [UInt8] {
        if emitted % UInt64(FlashEncoder.manifestInterval) == 0 {
            emitted &+= 1
            return FlashFrame.encodeManifest(manifest)
        }
        emitted &+= 1
        let s = seed
        seed &+= 1
        return FlashFrame.encodeData(FlashDataFrame(session: manifest.session, seed: s, payload: symbol(seed: s)))
    }

    /// The payload of the data frame with this seed: the XOR of the chunks it selects.
    public func symbol(seed s: UInt32) -> [UInt8] {
        let idx = FlashFountain.indices(s, chunkCount)
        var body = chunks[idx[0]]
        for k in idx.dropFirst() { FlashXor.apply(&body, chunks[k]) }
        return body
    }

    /// A uniformly random session id in 1…65535 (never 0).
    public static func newSession() -> UInt16 { UInt16.random(in: 1 ... 65535) }
}

/// Byte-wise XOR of equal-length buffers, eight bytes at a time.
public enum FlashXor {
    public static func apply(_ a: inout [UInt8], _ b: [UInt8]) {
        let n = min(a.count, b.count)
        a.withUnsafeMutableBytes { pa in
            b.withUnsafeBytes { pb in
                let words = n / 8
                for w in 0 ..< words {
                    let x = pa.loadUnaligned(fromByteOffset: w * 8, as: UInt64.self)
                    let y = pb.loadUnaligned(fromByteOffset: w * 8, as: UInt64.self)
                    pa.storeBytes(of: x ^ y, toByteOffset: w * 8, as: UInt64.self)
                }
                for i in words * 8 ..< n { pa[i] ^= pb[i] }
            }
        }
    }
}
