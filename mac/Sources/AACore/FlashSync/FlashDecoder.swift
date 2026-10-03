// Spec: 13 §3.9 / FLASH-068 (peeling decoder: late join, session/CRC-change reset, duplicate-seed rejection),
//       FLASH-069 (hostile input: `finish()` never throws, caps allocations at 64 MiB), FLASH-061/062 (CRC over the
//       coded bytes, then raw inflate to exactly rawBytes); QR_SYNC_PROTOCOL.md §9.
// Every field arrives from a camera through QR error correction that can mis-correct, so nothing here traps.

/// Belief-propagation ("peeling") decoder. Not thread-safe: confine one instance to the capture queue.
public final class FlashDecoder: @unchecked Sendable {
    /// 64 MiB — the largest coded or raw payload `finish()` will allocate.
    public static let maxPayloadBytes = 64 * 1024 * 1024

    private struct Equation {
        var indices: Set<Int>
        var body: [UInt8]
    }

    public private(set) var manifest: FlashManifestFrame?
    private var solved: [Int: [UInt8]] = [:]
    private var pending: [Equation] = []
    private var seenSeeds: Set<UInt32> = []

    public init() {}

    public var solvedCount: Int { solved.count }
    /// The manifest's K, or 0 before a manifest has been seen.
    public var chunkCount: Int { manifest.map { Int($0.chunkCount) } ?? 0 }
    public var isComplete: Bool { manifest != nil && solved.count == chunkCount }
    /// The manifest label, or "".
    public var label: String { manifest?.label ?? "" }

    /// Feeds one QR string. Foreign text, frames of another session, wrong-length payloads and repeated seeds are
    /// ignored; a manifest with a different session or CRC throws everything away and starts over.
    public func ingest(_ text: String) {
        guard let bytes = FlashBase45.decode(text), let frame = FlashFrame.decode(bytes) else { return }
        ingest(frame)
    }

    public func ingest(_ frame: FlashDecodedFrame) {
        switch frame {
        case .manifest(let m):
            guard let current = manifest else { manifest = m; return }
            if m.session != current.session || m.crc32 != current.crc32 {
                reset()
                manifest = m
            }
        case .data(let d):
            guard let m = manifest else { return }                     // header not seen yet: not buffered
            guard d.session == m.session, d.payload.count == Int(m.chunkSize) else { return }
            guard seenSeeds.insert(d.seed).inserted else { return }   // already had this exact frame
            var idx = Set(FlashFountain.indices(d.seed, Int(m.chunkCount)))
            var body = d.payload
            for k in idx {
                if let s = solved[k] {
                    FlashXor.apply(&body, s)
                    idx.remove(k)
                }
            }
            if idx.isEmpty { return }                                  // fully redundant
            if idx.count == 1 { solve(idx.first!, body) } else { pending.append(Equation(indices: idx, body: body)) }
        }
    }

    private func solve(_ index: Int, _ value: [UInt8]) {
        var stack: [(Int, [UInt8])] = [(index, value)]
        while let (i, v) = stack.popLast() {
            if solved[i] != nil { continue }
            solved[i] = v
            var still: [Equation] = []
            still.reserveCapacity(pending.count)
            for var eq in pending {
                if eq.indices.contains(i) {
                    FlashXor.apply(&eq.body, v)
                    eq.indices.remove(i)
                    if eq.indices.isEmpty { continue }                 // became redundant: drop
                    if eq.indices.count == 1 { stack.append((eq.indices.first!, eq.body)); continue }
                }
                still.append(eq)
            }
            pending = still
        }
    }

    /// Reassembles, verifies and inflates; nil when not complete or anything is wrong (CRC mismatch, bounds,
    /// inflate failure). Never throws and never allocates more than 64 MiB.
    public func finish() -> [UInt8]? {
        guard let m = manifest, solved.count == Int(m.chunkCount) else { return nil }
        let k = Int(m.chunkCount), cs = Int(m.chunkSize)
        let total = Int64(k) * Int64(cs)
        guard total > 0, total <= Int64(FlashDecoder.maxPayloadBytes) else { return nil }
        var coded: [UInt8] = []
        coded.reserveCapacity(Int(total))
        for i in 0 ..< k {
            guard let chunk = solved[i], chunk.count == cs else { return nil }
            coded += chunk
        }
        let codedBytes = Int64(m.codedBytes)
        guard codedBytes > 0, codedBytes <= Int64(coded.count) else { return nil }
        coded.removeSubrange(Int(codedBytes)...)
        guard CRC32.checksum(coded) == m.crc32 else { return nil }      // corrupted — report, change nothing
        let raw = Int64(m.rawBytes)
        guard raw > 0, raw <= Int64(FlashDecoder.maxPayloadBytes) else { return nil }
        return try? RawDeflate.inflate(coded, expectedLength: Int(raw))
    }

    /// Clears the solved chunks, pending equations and seen seeds (the caller replaces the manifest).
    public func reset() {
        solved.removeAll()
        pending.removeAll()
        seenSeeds.removeAll()
    }
}
