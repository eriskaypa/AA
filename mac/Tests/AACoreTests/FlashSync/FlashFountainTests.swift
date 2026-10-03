// TV: 13 §7.7 (encoder emission order, the K=10 fixed vector incl. the space-bearing manifest text, decoder solved
//     counts on that stream, session/CRC reset, same-session manifests ignored, wrong-length/foreign frames ignored,
//     CRC-ok-but-inflate-fails → nil, loopback at 40 % loss, late join, clean capture = exactly K data frames,
//     measured-target loss simulations, foreign text, fuzz, finish() bounds); QR_SYNC_PROTOCOL.md §8–§9
//     (FLASH-022, 023, 067, 068, 069).
import Foundation
import Testing
@testable import AACore

@Suite struct FlashFountainTests {
    static let k10: JSONObject = FlashTestKit.vectors["fountainK10"]?.objectValue ?? JSONObject()

    static func k10Encoder() throws -> FlashEncoder {
        let v = k10
        return try FlashEncoder(coded: FlashTestKit.bytes(hex: v["coded"]!.stringValue!), rawBytes: 123, kind: .changeSet,
                                label: "test", session: 0x0102, chunkSize: 4)
    }

    /// Data frame text for a seed of the K=10 stream.
    static func k10Data(_ seed: Int) -> String {
        for row in k10["data"]?.arrayValue ?? [] {
            let r = row.arrayValue!
            if FlashTestKit.int(r[0]) == seed { return r[3].stringValue! }
        }
        return ""
    }

    // TV: 13 §7.7 — emission order M,0…10,M,11…21,M,22 (seeds never consumed by manifests)
    @Test func emissionOrder() throws {
        let enc = try FlashEncoder(payload: FlashTestKit.sampleJSON(approxBytes: 40_000), kind: .changeSet, label: "x", session: 9)
        var order: [String] = []
        for _ in 0 ..< 26 {
            guard let b = FlashBase45.decode(enc.next()), let f = FlashFrame.decode(b) else { order.append("?"); continue }
            switch f {
            case .manifest: order.append("M")
            case .data(let d): order.append(String(d.seed))
            }
        }
        let want = ["M"] + (0 ... 10).map(String.init) + ["M"] + (11 ... 21).map(String.init) + ["M", "22"]
        #expect(order == want)
    }

    // TV: 13 §7.7 — the fixed K=10 vector (manifest bytes/text, every data frame's indices, payload and text)
    @Test func fixedK10Vector() throws {
        let v = Self.k10
        let enc = try Self.k10Encoder()
        #expect(enc.chunkCount == 10)
        #expect(String(format: "%08X", enc.manifest.crc32) == v["crc"]!.stringValue!)
        let manifest = FlashFrame.encodeManifest(enc.manifest)
        #expect(FlashTestKit.hex(manifest) == v["manifestHex"]!.stringValue!)
        #expect(FlashBase45.encode(manifest) == v["manifestText"]!.stringValue!)
        #expect(v["manifestText"]!.stringValue!.contains(" "))
        for row in v["data"]?.arrayValue ?? [] {
            let r = row.arrayValue!
            let seed = UInt32(FlashTestKit.int(r[0]))
            #expect(FlashFountain.indices(seed, 10) == FlashTestKit.ints(r[1]), "seed \(seed)")
            let payload = enc.symbol(seed: seed)
            #expect(FlashTestKit.hex(payload) == r[2].stringValue!, "seed \(seed)")
            let text = FlashBase45.encode(FlashFrame.encodeData(FlashDataFrame(session: 0x0102, seed: seed, payload: payload)))
            #expect(text == r[3].stringValue!, "seed \(seed)")
        }
        // The live stream: M, seeds 0…10 — identical to the vector texts.
        #expect(enc.next() == v["manifestText"]!.stringValue!)
        for s in 0 ... 10 { #expect(enc.next() == Self.k10Data(s)) }
    }

    // TV: 13 §7.7 — decoder behaviour on the K=10 stream (solvedCount after each ingest)
    @Test func decoderOnK10Stream() throws {
        let dec = FlashDecoder()
        let manifest = Self.k10["manifestText"]!.stringValue!
        dec.ingest(Self.k10Data(0)); #expect(dec.solvedCount == 0 && dec.chunkCount == 0)   // before the manifest
        dec.ingest(manifest); #expect(dec.solvedCount == 0 && dec.chunkCount == 10)
        #expect(dec.label == "test")
        dec.ingest(Self.k10Data(10)); #expect(dec.solvedCount == 0)                          // pending [0,1]
        dec.ingest(Self.k10Data(11)); #expect(dec.solvedCount == 0)                          // pending [1,6]
        dec.ingest(Self.k10Data(1)); #expect(dec.solvedCount == 3)                           // 1, then 0 and 6 cascade
        dec.ingest(Self.k10Data(10)); #expect(dec.solvedCount == 3)                          // duplicate seed
        for s in [2, 3, 4, 5, 7, 8] { dec.ingest(Self.k10Data(s)) }
        #expect(dec.solvedCount == 9)
        dec.ingest(Self.k10Data(12)); #expect(dec.solvedCount == 9)                          // [3,8] redundant
        #expect(!dec.isComplete)
        #expect(dec.finish() == nil)                                                         // not complete
        dec.ingest(Self.k10Data(9)); #expect(dec.solvedCount == 10)
        #expect(dec.isComplete)
        #expect(dec.finish() == nil)        // CRC passes, but the synthetic bytes are not DEFLATE → nil, no throw
    }

    @Test func manifestChangesResetOrAreIgnored() throws {
        let enc = try FlashEncoder(payload: FlashTestKit.sampleJSON(approxBytes: 30_000), kind: .changeSet, label: "one",
                                   session: 100)
        let dec = FlashDecoder()
        for _ in 0 ..< 6 { dec.ingest(enc.next()) }
        #expect(dec.solvedCount == 5)
        // Same session + CRC, different label → ignored.
        var m = enc.manifest
        m.label = "renamed"
        dec.ingest(FlashBase45.encode(FlashFrame.encodeManifest(m)))
        #expect(dec.label == "one" && dec.solvedCount == 5)
        // A data frame of another session → ignored; a wrong-length payload → ignored.
        dec.ingest(FlashBase45.encode(FlashFrame.encodeData(FlashDataFrame(session: 101, seed: 40, payload: enc.symbol(seed: 40)))))
        dec.ingest(FlashBase45.encode(FlashFrame.encodeData(FlashDataFrame(session: 100, seed: 41, payload: [1, 2, 3]))))
        #expect(dec.solvedCount == 5)
        // A different session mid-way → everything discarded, the new K adopted.
        let other = try FlashEncoder(payload: FlashTestKit.sampleJSON(approxBytes: 9_000, seed: 3), kind: .fullSnapshot,
                                     label: "two", session: 200)
        dec.ingest(other.next())
        #expect(dec.solvedCount == 0 && dec.chunkCount == other.chunkCount && dec.label == "two")
        // A different CRC with the same session also resets.
        let third = try FlashEncoder(payload: FlashTestKit.sampleJSON(approxBytes: 5_000, seed: 4), kind: .changeSet,
                                     label: "three", session: 200)
        dec.ingest(other.next())
        #expect(dec.solvedCount == 1)
        dec.ingest(third.next())
        #expect(dec.solvedCount == 0 && dec.label == "three")
    }

    // TV: 13 §7.7 — loopback: 60 KB JSON, 40 % random loss → byte-equal
    @Test func loopbackWithLoss() throws {
        let payload = FlashTestKit.sampleJSON(approxBytes: 60_000)
        for trial in 0 ..< 5 {
            let enc = try FlashEncoder(payload: payload, kind: .changeSet, label: "loop", session: FlashEncoder.newSession())
            let dec = FlashDecoder()
            var rng = FlashRandom(seed: UInt32(trial + 1))
            var shown = 0
            while !dec.isComplete && shown < 5_000 {
                let t = enc.next()
                shown += 1
                if rng.next(100) < 40 { continue }
                dec.ingest(t)
            }
            #expect(dec.isComplete)
            #expect(dec.finish() == payload)
        }
    }

    // TV: 13 §7.7 — late join at emitted frame 37 still completes
    @Test func lateJoin() throws {
        let payload = FlashTestKit.sampleJSON(approxBytes: 80_000)
        let enc = try FlashEncoder(payload: payload, kind: .changeSet, label: "late", session: 77)
        for _ in 0 ..< 37 { _ = enc.next() }
        let dec = FlashDecoder()
        var n = 0
        while !dec.isComplete && n < 5_000 { dec.ingest(enc.next()); n += 1 }
        #expect(dec.finish() == payload)
    }

    // TV: 13 §7.7 — a clean capture of K ≥ 9 completes after exactly K data frames (1.00×)
    @Test func cleanCaptureIsExactlyKDataFrames() throws {
        let payload = FlashTestKit.sampleJSON(approxBytes: 150_000)
        let enc = try FlashEncoder(payload: payload, kind: .fullSnapshot, label: "clean", session: 5)
        #expect(enc.chunkCount >= 9)
        let dec = FlashDecoder()
        var dataFrames = 0
        while !dec.isComplete {
            let t = enc.next()
            if case .data? = FlashBase45.decode(t).flatMap(FlashFrame.decode) { dataFrames += 1 }
            dec.ingest(t)
            if dataFrames > enc.chunkCount * 3 { break }
        }
        #expect(dataFrames == enc.chunkCount)
        #expect(dec.finish() == payload)
    }

    // TV: 13 §7.7 / protocol §1 — measured targets: assert "completes" at 0/25/50/70 % loss, report the counts
    @Test func measuredTargets() throws {
        for (approx, label) in [(12_000, "typical"), (60_000, "bigger"), (400_000, "large")] {
            let payload = FlashTestKit.sampleJSON(approxBytes: approx, seed: UInt64(approx))
            for loss in [0, 25, 50, 70] {
                var seen: [Int] = []
                for trial in 0 ..< 4 {
                    let enc = try FlashEncoder(payload: payload, kind: .changeSet, label: label,
                                               session: UInt16(trial + 1))
                    for _ in 0 ..< (trial * 13) { _ = enc.next() }                   // join mid-stream
                    let dec = FlashDecoder()
                    var rng = FlashRandom(seed: UInt32(loss * 100 + trial + 1))
                    var received = 0, shown = 0
                    while !dec.isComplete && shown < 200_000 {
                        let t = enc.next()
                        shown += 1
                        if rng.next(100) < loss { continue }
                        received += 1
                        dec.ingest(t)
                    }
                    #expect(dec.finish() == payload, "\(label) K=\(enc.chunkCount) loss \(loss)%")
                    seen.append(received)
                }
                let avg = seen.reduce(0, +) / seen.count
                print("Flash Sync loss simulation: \(label) (\(payload.count) B) loss \(loss)% → \(avg) frames received on average")
            }
        }
    }

    // TV: 13 §7.7 — foreign text never changes state
    @Test func foreignTextIsIgnored() throws {
        let dec = FlashDecoder()
        for t in ["HELLO WORLD", "https://example.com/x?y=1", "", " ", "AB8$AA", "abc"] { dec.ingest(t) }
        #expect(dec.manifest == nil && dec.solvedCount == 0)
        let enc = try FlashEncoder(payload: FlashTestKit.sampleJSON(approxBytes: 3_000), kind: .changeSet, label: "", session: 3)
        dec.ingest(enc.next())
        let before = dec.solvedCount
        for t in ["HELLO WORLD", "https://example.com", "", FlashBase45.encode([0x41, 0x41, 0x51, 0x02, 0x00])] { dec.ingest(t) }
        #expect(dec.solvedCount == before && dec.chunkCount == enc.chunkCount)
    }

    // TV: 13 §7.7 — fuzz: random Base45 strings and mutations of valid frames never crash and never yield a payload
    // whose CRC is wrong
    @Test func fuzz() throws {
        let payload = FlashTestKit.sampleJSON(approxBytes: 20_000)
        let enc = try FlashEncoder(payload: payload, kind: .changeSet, label: "fuzz", session: 4242)
        let valid = (0 ..< 60).map { _ in enc.nextFrameBytes() }
        var rng = FlashRandom(seed: 99)
        let dec = FlashDecoder()
        for i in 0 ..< 20_000 {
            var b: [UInt8]
            if i % 2 == 0 {
                b = FlashTestKit.noise(rng.next(40) + (i % 7 == 0 ? 0 : 5), seed: UInt64(i))
                if i % 4 == 0 && b.count >= 5 { b[0] = 0x41; b[1] = 0x41; b[2] = 0x51; b[3] = 0x01; b[4] = UInt8(rng.next(2)) }
            } else {
                b = valid[rng.next(valid.count)]
                for _ in 0 ..< 1 + rng.next(3) where !b.isEmpty { b[rng.next(b.count)] ^= UInt8(1 + rng.next(255)) }
            }
            dec.ingest(FlashBase45.encode(b))
            if dec.isComplete, let out = dec.finish() {
                #expect(out == payload)                                   // the CRC guards every accepted payload
            }
        }
        // Whatever state the fuzz left, a correct manifest + clean pass of a fresh session still decodes.
        let fresh = try FlashEncoder(payload: payload, kind: .changeSet, label: "after", session: 4243)
        var n = 0
        while !dec.isComplete && n < 2_000 { dec.ingest(fresh.next()); n += 1 }
        #expect(dec.finish() == payload)
    }

    // TV: 13 §7.7 — finish() returns nil for hostile manifests (never allocates > 64 MiB, never throws)
    @Test func finishBounds() throws {
        func run(_ m: FlashManifestFrame, chunks: [[UInt8]]) -> [UInt8]? {
            let dec = FlashDecoder()
            dec.ingest(.manifest(m))
            for (i, c) in chunks.enumerated() {
                dec.ingest(.data(FlashDataFrame(session: m.session, seed: UInt32(i), payload: c)))
            }
            return dec.finish()
        }
        let payload = Array("{\"a\":1}".utf8)
        let coded = try RawDeflate.compress(payload)
        let cs = 16
        var chunk = coded
        chunk += [UInt8](repeating: 0, count: cs - coded.count)
        let good = FlashManifestFrame(session: 1, codedBytes: UInt32(coded.count), rawBytes: UInt32(payload.count),
                                      chunkSize: UInt16(cs), chunkCount: 1, crc32: CRC32.checksum(coded), kind: .changeSet,
                                      label: "")
        #expect(run(good, chunks: [chunk]) == payload)
        var m = good; m.codedBytes = 0
        #expect(run(m, chunks: [chunk]) == nil)                            // codedBytes 0
        m = good; m.codedBytes = UInt32(cs + 1)
        #expect(run(m, chunks: [chunk]) == nil)                            // codedBytes > K·chunkSize
        m = good; m.rawBytes = 0
        #expect(run(m, chunks: [chunk]) == nil)                            // rawBytes 0
        m = good; m.rawBytes = UInt32(FlashDecoder.maxPayloadBytes + 1)
        #expect(run(m, chunks: [chunk]) == nil)                            // rawBytes > 64 MiB
        m = good; m.crc32 ^= 1
        #expect(run(m, chunks: [chunk]) == nil)                            // CRC mismatch
        m = good; m.rawBytes = UInt32(payload.count + 5)
        #expect(run(m, chunks: [chunk]) == nil)                            // inflate short
        // K·chunkSize > 64 MiB (1025 × 65535): rejected before the reassembly buffer is allocated. The chunks
        // share one copy-on-write buffer, so the test itself stays small.
        m = good; m.chunkSize = 65535; m.chunkCount = 1025
        let big = [UInt8](repeating: 7, count: 65535)
        #expect(run(m, chunks: Array(repeating: big, count: 1025)) == nil)
    }

    @Test func payloadTooLarge() {
        #expect(throws: FlashEncoderError.payloadTooLarge(chunks: 65536)) {
            _ = try FlashEncoder(coded: [UInt8](repeating: 1, count: 65536), rawBytes: 1, kind: .changeSet, label: "",
                                 session: 1, chunkSize: 1)
        }
        let s = (0 ..< 2000).map { _ in FlashEncoder.newSession() }
        #expect(!s.contains(0))
    }

    @Test func smallPayloadCyclesRoundRobin() throws {
        let enc = try FlashEncoder(payload: FlashTestKit.sampleJSON(approxBytes: 2_500), kind: .changeSet, label: "s", session: 8)
        #expect(enc.chunkCount <= 8)
        let dec = FlashDecoder()
        var dataFrames = 0
        while !dec.isComplete && dataFrames < 100 {
            let t = enc.next()
            if case .data? = FlashBase45.decode(t).flatMap(FlashFrame.decode) { dataFrames += 1 }
            dec.ingest(t)
        }
        #expect(dataFrames == enc.chunkCount)
        #expect(dec.finish() != nil)
    }
}
