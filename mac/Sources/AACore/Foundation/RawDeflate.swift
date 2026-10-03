// Spec: 13 §3.3 / FLASH-062 (raw RFC 1951 DEFLATE via Compression's COMPRESSION_ZLIB), 01 §6.7 (ZIP method 8).
import Foundation
import Compression

public enum RawDeflateError: Error, Equatable, Sendable, CustomStringConvertible {
    case compressionFailed
    case corrupt
    /// Matches the .NET text `Inflate produced {off} bytes, expected {rawLength}.`
    case shortOutput(produced: Int, expected: Int)

    public var description: String {
        switch self {
        case .compressionFailed: return "Compression failed."
        case .corrupt: return "The compressed data is corrupt."
        case let .shortOutput(p, e): return "Inflate produced \(p) bytes, expected \(e)."
        }
    }
}

public enum RawDeflate {
    /// Raw DEFLATE (no zlib header). Empty input encodes to `03 00`.
    public static func compress(_ bytes: [UInt8]) throws -> [UInt8] {
        if bytes.isEmpty { return [0x03, 0x00] }
        let codec = try RawDeflateCodec(encode: true)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count / 2 + 64)
        _ = try bytes.withUnsafeBytes { raw in
            try codec.process(raw, finalize: true) { out.append(contentsOf: $0) }
        }
        return out
    }

    /// Inflates raw DEFLATE. With `expectedLength`, exactly that many bytes are returned: fewer produced →
    /// `.shortOutput`; extra output is ignored (13 §3.3). Without it, the whole stream is inflated.
    public static func inflate(_ bytes: [UInt8], expectedLength: Int?) throws -> [UInt8] {
        let codec = try RawDeflateCodec(encode: false)
        var out: [UInt8] = []
        // Deflate expands at most 1032:1, so a larger claimed length cannot be met: never reserve more than that.
        if let n = expectedLength {
            let (cap, overflow) = bytes.count.multipliedReportingOverflow(by: 1032)
            out.reserveCapacity(max(0, min(n, overflow ? n : cap + 64)))
        }
        var ended = false
        try bytes.withUnsafeBytes { raw in
            ended = try codec.process(raw, finalize: true) { chunk in
                if let n = expectedLength {
                    let room = n - out.count
                    if room > 0 { out.append(contentsOf: chunk.prefix(room)) }
                } else {
                    out.append(contentsOf: chunk)
                }
            }
        }
        if let n = expectedLength {
            if out.count < n { throw RawDeflateError.shortOutput(produced: out.count, expected: n) }
            return out
        }
        guard ended else { throw RawDeflateError.corrupt }
        return out
    }
}

/// Streaming raw-DEFLATE encoder/decoder over `compression_stream` (used by the ZIP reader/writer).
final class RawDeflateCodec {
    private let stream: UnsafeMutablePointer<compression_stream>
    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize = 64 * 1024
    private let encode: Bool
    private(set) var finished = false

    init(encode: Bool) throws {
        self.encode = encode
        stream = .allocate(capacity: 1)
        buffer = .allocate(capacity: bufferSize)
        let status = compression_stream_init(stream, encode ? COMPRESSION_STREAM_ENCODE : COMPRESSION_STREAM_DECODE,
                                             COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else {
            buffer.deallocate(); stream.deallocate()
            throw encode ? RawDeflateError.compressionFailed : RawDeflateError.corrupt
        }
    }

    deinit {
        compression_stream_destroy(stream)
        stream.deallocate()
        buffer.deallocate()
    }

    /// Feeds `input`; calls `output` with every produced chunk. Returns true once the stream has ended
    /// (decoder: end of the DEFLATE stream; encoder: finalized).
    @discardableResult
    func process(_ input: UnsafeRawBufferPointer, finalize: Bool,
                 output: (UnsafeBufferPointer<UInt8>) throws -> Void) throws -> Bool {
        if finished { return true }
        let empty: [UInt8] = [0]
        return try empty.withUnsafeBufferPointer { emptyBuf -> Bool in
            let base = input.baseAddress?.assumingMemoryBound(to: UInt8.self) ?? emptyBuf.baseAddress!
            stream.pointee.src_ptr = UnsafePointer(base)
            stream.pointee.src_size = input.count
            let flags = finalize ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            while true {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = bufferSize
                let status = compression_stream_process(stream, flags)
                let produced = bufferSize - stream.pointee.dst_size
                if produced > 0 { try output(UnsafeBufferPointer(start: buffer, count: produced)) }
                switch status {
                case COMPRESSION_STATUS_END:
                    finished = true
                    return true
                case COMPRESSION_STATUS_OK:
                    if stream.pointee.src_size == 0 && produced < bufferSize {
                        if !finalize { return false }
                        if !encode && produced == 0 { return false }     // decoder: input exhausted before the end
                    }
                default:
                    throw encode ? RawDeflateError.compressionFailed : RawDeflateError.corrupt
                }
            }
        }
    }
}
