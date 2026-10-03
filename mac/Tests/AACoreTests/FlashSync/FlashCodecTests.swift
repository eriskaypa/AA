// TV: QR_SYNC_PROTOCOL.md §3 (Base45), §5 (xorshift32), §6 (degree, the ten index rows), §7 (frame vectors, CRC-32),
//     §4 (DEFLATE); 13 §7.1–7.6 incl. every *extra* row (FLASH-060, 061, 062, 063, 064, 065, 066, 069, 070).
import Foundation
import Testing
@testable import AACore

@Suite struct FlashCodecTests {
    // MARK: Base45 (13 §7.1)

    // TV: protocol §3 — the six encode vectors
    @Test func base45ProtocolVectors() {
        for row in FlashTestKit.vectors["base45Encode"]?.arrayValue ?? [] {
            let o = row.objectValue!
            let bytes = FlashTestKit.bytes(hex: o["hex"]!.stringValue!)
            let text = o["text"]!.stringValue!
            #expect(FlashBase45.encode(bytes) == text)
            #expect(FlashBase45.decode(text) == bytes)
        }
        #expect((FlashTestKit.vectors["base45Encode"]?.arrayValue ?? []).count == 6)
    }

    // TV: 13 §7.1 extra decode rows (invalid input → nil)
    @Test func base45DecodeRejections() {
        for row in FlashTestKit.vectors["base45DecodeExtra"]?.arrayValue ?? [] {
            let o = row.objectValue!
            let got = FlashBase45.decode(o["text"]!.stringValue!)
            if let hex = o["hex"]?.stringValue {
                #expect(got == FlashTestKit.bytes(hex: hex))
            } else {
                #expect(got == nil, "\(o["text"]!.stringValue!) must be rejected")
            }
        }
        #expect(FlashBase45.decode("HELLO WORLD!") == nil)          // the C# vectors' foreign-text row
    }

    // TV: 13 §7.1 round-trip property for random lengths 0…2000
    @Test func base45RoundTrip() {
        for len in [0, 1, 2, 3, 899, 900, 911, 1999, 2000] + (0 ..< 40).map({ $0 * 37 }) {
            let b = FlashTestKit.noise(len, seed: UInt64(len) &+ 11)
            let t = FlashBase45.encode(b)
            #expect(t.utf8.count == len / 2 * 3 + (len % 2) * 2)
            #expect(FlashBase45.decode(t) == b)
            #expect(FlashQRSegment.isAlphanumeric(t))
        }
    }

    // MARK: CRC-32 (13 §7.2 — F1 owns the implementation, W-FLASH the vectors' use on the wire)

    @Test func crcVectors() {
        for row in FlashTestKit.vectors["crc32"]?.arrayValue ?? [] {
            let o = row.objectValue!
            let input: [UInt8] = o["ascii"].map { Array($0.stringValue!.utf8) }
                ?? [UInt8](repeating: 0, count: FlashTestKit.int(o["zeros"]))
            #expect(String(format: "%08X", CRC32.checksum(input)) == o["crc"]!.stringValue!)
        }
    }

    // MARK: xorshift32 (13 §7.3)

    @Test func xorshiftVectors() {
        let rows = FlashTestKit.vectors["xorshift"]?.arrayValue ?? []
        #expect(rows.count == 5)
        for row in rows {
            let o = row.objectValue!
            var r = FlashRandom(seed: FlashTestKit.uint32(o["seed"]))
            let want = (o["out"]?.arrayValue ?? []).map { FlashTestKit.uint32($0) }
            let got = (0 ..< want.count).map { _ in r.next() }
            #expect(got == want, "seed \(FlashTestKit.uint32(o["seed"]))")
        }
        #expect(FlashRandom(seed: 0).state == 0x9E37_79B9)
    }

    // MARK: Degree and indices (13 §7.4)

    @Test func degreeVectors() {
        for row in FlashTestKit.vectors["degree"]?.arrayValue ?? [] {
            let o = row.objectValue!
            #expect(FlashFountain.degree(FlashTestKit.uint32(o["r"]), FlashTestKit.int(o["k"])) == FlashTestKit.int(o["d"]),
                    "r=\(FlashTestKit.uint32(o["r"])) K=\(FlashTestKit.int(o["k"]))")
        }
    }

    // TV: protocol §6 — "If these ten rows do not reproduce exactly, stop and fix it before writing anything else."
    @Test func indicesTheTenProtocolRows() {
        let rows = FlashTestKit.vectors["indicesProtocol"]?.arrayValue ?? []
        #expect(rows.count == 10)
        for row in rows {
            let o = row.objectValue!
            #expect(FlashFountain.indices(FlashTestKit.uint32(o["seed"]), FlashTestKit.int(o["k"])) == FlashTestKit.ints(o["idx"]),
                    "seed=\(FlashTestKit.uint32(o["seed"])) K=\(FlashTestKit.int(o["k"]))")
        }
    }

    @Test func indicesExtraRows() {
        let rows = FlashTestKit.vectors["indicesExtra"]?.arrayValue ?? []
        #expect(rows.count == 58)
        for row in rows {
            let o = row.objectValue!
            #expect(FlashFountain.indices(FlashTestKit.uint32(o["seed"]), FlashTestKit.int(o["k"])) == FlashTestKit.ints(o["idx"]),
                    "seed=\(FlashTestKit.uint32(o["seed"])) K=\(FlashTestKit.int(o["k"]))")
        }
        #expect(FlashFountain.indices(5, 0) == [])
        #expect(FlashFountain.indices(5, -1) == [])
    }

    @Test func indicesAreSortedDistinctAndInRange() {
        for k in [9, 10, 37, 165, 1000] {
            for s in stride(from: UInt32(k), to: UInt32(k + 400), by: 1) {
                let idx = FlashFountain.indices(s, k)
                #expect(!idx.isEmpty && idx == idx.sorted() && Set(idx).count == idx.count && idx.allSatisfy { $0 >= 0 && $0 < k })
            }
        }
    }

    // MARK: Frames (13 §7.5)

    @Test func frameVectors() {
        for row in FlashTestKit.vectors["frames"]?.arrayValue ?? [] {
            let o = row.objectValue!
            let bytes: [UInt8]
            if o["type"]?.stringValue == "manifest" {
                let m = FlashManifestFrame(session: UInt16(FlashTestKit.int(o["session"])),
                                           codedBytes: FlashTestKit.uint32(o["codedBytes"]),
                                           rawBytes: FlashTestKit.uint32(o["rawBytes"]),
                                           chunkSize: UInt16(FlashTestKit.int(o["chunkSize"])),
                                           chunkCount: UInt16(FlashTestKit.int(o["chunkCount"])),
                                           crc32: UInt32(o["crc32"]!.stringValue!, radix: 16)!,
                                           kind: FlashFrameKind(rawValue: UInt8(FlashTestKit.int(o["kind"])))!,
                                           label: o["label"]!.stringValue!)
                bytes = FlashFrame.encodeManifest(m)
                #expect(FlashFrame.decode(bytes) == .manifest(m))
            } else {
                let d = FlashDataFrame(session: UInt16(FlashTestKit.int(o["session"])), seed: FlashTestKit.uint32(o["seed"]),
                                       payload: FlashTestKit.bytes(hex: o["payload"]!.stringValue!))
                bytes = FlashFrame.encodeData(d)
                #expect(FlashFrame.decode(bytes) == .data(d))
            }
            #expect(FlashTestKit.hex(bytes) == o["hex"]!.stringValue!)
            #expect(FlashBase45.encode(bytes) == o["text"]!.stringValue!)
            #expect(FlashBase45.decode(o["text"]!.stringValue!) == bytes)
        }
    }

    // TV: 13 §7.5 — the all-zero data frame (the tail-padding case that broke QRCoder)
    @Test func allZeroDataFrame() {
        let bytes = FlashFrame.encodeData(FlashDataFrame(session: 0x1234, seed: 0, payload: [UInt8](repeating: 0, count: 900)))
        #expect(bytes.count == 911)
        let text = FlashBase45.encode(bytes)
        #expect(text.utf8.count == 1367)
        #expect(text.hasPrefix("AB8$AA460$P6"))
        #expect(text.dropFirst(12).allSatisfy { $0 == "0" })            // "000" groups, then the "00" tail byte
    }

    // TV: 13 §7.5 — label truncation to 120 bytes; invalid UTF-8 decoded with U+FFFD
    @Test func labelTruncation() {
        func roundTrip(_ label: String) -> (UInt8, String) {
            let m = FlashManifestFrame(session: 1, codedBytes: 1, rawBytes: 1, chunkSize: 900, chunkCount: 1, crc32: 0,
                                       kind: .changeSet, label: label)
            let b = FlashFrame.encodeManifest(m)
            guard case .manifest(let d)? = FlashFrame.decode(b) else { return (0, "<nil>") }
            return (b[24], d.label)
        }
        let a = roundTrip(String(repeating: "é", count: 61))
        #expect(a.0 == 0x78)
        #expect(a.1 == String(repeating: "é", count: 60))
        let b = roundTrip("a" + String(repeating: "é", count: 60))
        #expect(b.0 == 120)
        #expect(b.1 == "a" + String(repeating: "é", count: 59) + "\u{FFFD}")
    }

    // TV: 13 §7.5 decode rejections
    @Test func frameDecodeRejections() {
        let good = FlashTestKit.bytes(hex: "414151010012340000046900000C03038400023D3150F8000B312065717569706D656E74")
        #expect(FlashFrame.decode([0x41, 0x41, 0x51, 0x01]) == nil)                 // 4 bytes
        var v2 = good; v2[3] = 0x02
        #expect(FlashFrame.decode(v2) == nil)                                         // version 2
        var cs0 = good; cs0[15] = 0; cs0[16] = 0
        #expect(FlashFrame.decode(cs0) == nil)                                        // chunkSize 0
        var k0 = good; k0[17] = 0; k0[18] = 0
        #expect(FlashFrame.decode(k0) == nil)                                         // K 0
        var kind2 = good; kind2[23] = 2
        #expect(FlashFrame.decode(kind2) == nil)                                      // unknown kind
        var long = good; long[24] = 40
        #expect(FlashFrame.decode(long) == nil)                                       // labelLen past the end
        #expect(FlashFrame.decode([0x41, 0x41, 0x51, 0x01, 0x01, 0, 1, 0, 0, 0, 7]) == nil)   // data, exactly 11 bytes
        var t2 = good; t2[4] = 2
        #expect(FlashFrame.decode(t2) == nil)                                         // type 2
        #expect(FlashFrame.decode(Array(good.prefix(24))) == nil)                     // short manifest
        guard case .manifest(let m)? = FlashFrame.decode(good + [9, 9, 9]) else {
            Issue.record("trailing bytes after the label must be accepted"); return
        }
        #expect(m.label == "1 equipment")
        #expect(FlashFrame.decode([0x41, 0x41, 0x51, 0x01, 0x01, 0, 1, 0, 0, 0, 7, 0xAB]) ==
                .data(FlashDataFrame(session: 1, seed: 7, payload: [0xAB])))
    }

    // MARK: DEFLATE (13 §7.6)

    @Test func deflateVectors() throws {
        let ios = FlashTestKit.bytes(hex: "73748401273870860300")
        let raw = FlashTestKit.bytes(hex: "414141414141414141414242424242424242424243434343434343434343")
        #expect(try RawDeflate.inflate(ios, expectedLength: 30) == raw)
        let ours = try RawDeflate.compress(raw)
        #expect(!ours.isEmpty && ours[0] != 0x78)                                     // raw, not zlib-wrapped
        #expect(FlashTestKit.hex(ours) == "73748401273870860300")                    // Apple = iOS (extra, Mac)
        #expect(FlashTestKit.hex(try RawDeflate.compress([])) == "0300")
        #expect(try RawDeflate.inflate(ios, expectedLength: 10) == Array(raw.prefix(10)))   // excess ignored
        #expect(throws: (any Error).self) { try RawDeflate.inflate(ios, expectedLength: 40) } // only 30 produced
    }
}
