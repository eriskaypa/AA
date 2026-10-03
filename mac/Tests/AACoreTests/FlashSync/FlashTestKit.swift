// Shared helpers of the W-FLASH test suites (prefixed per ARCHITECTURE.md §12.2).
import Foundation
@testable import AACore

enum FlashTestKit {
    /// `Fixtures/flashsync/vectors.json` (the protocol and 13 §7 vectors, copied).
    static let vectors: JSONObject = {
        guard let d = try? Fixtures.data("flashsync/vectors.json"),
              case .object(let o)? = try? JSONParser.parse(d) else { return JSONObject() }
        return o
    }()

    static func bytes(hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var chars = Array(hex.utf8)[...]
        while chars.count >= 2 {
            let pair = String(decoding: chars.prefix(2), as: UTF8.self)
            out.append(UInt8(pair, radix: 16)!)
            chars = chars.dropFirst(2)
        }
        return out
    }

    static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined() }

    static func object(_ json: String) -> JSONObject {
        guard case .object(let o)? = try? JSONParser.parse(json) else { return JSONObject() }
        return o
    }

    static func text(_ o: JSONObject) -> String { (try? JSONWriter.string(.object(o))) ?? "<too deep>" }

    /// 2026-09-27 12:00:00 local wall time (13 §7.8 created/now).
    static let created = NetDateTime(year: 2026, month: 9, day: 27, hour: 12, minute: 0, second: 0, kind: .local)

    static func int(_ v: JSONValue?) -> Int { v?.numberValue?.int64Value.map(Int.init) ?? -1 }
    static func uint32(_ v: JSONValue?) -> UInt32 { UInt32(v?.numberValue?.int64Value ?? 0) }
    static func ints(_ v: JSONValue?) -> [Int] { (v?.arrayValue ?? []).map { int($0) } }

    /// A deterministic pseudo-random byte string (SplitMix64).
    static func noise(_ count: Int, seed: UInt64) -> [UInt8] {
        var s = seed
        var out = [UInt8](repeating: 0, count: count)
        for i in 0 ..< count {
            s &+= 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            out[i] = UInt8(truncatingIfNeeded: z ^ (z >> 31))
        }
        return out
    }

    /// A JSON document of roughly `bytes` bytes that DEFLATEs realistically (repetitive keys, varied values).
    static func sampleJSON(approxBytes: Int, seed: UInt64 = 7) -> [UInt8] {
        var items: [String] = []
        var size = 0
        var i = 0
        let words = ["Ballast pump", "Main engine", "Cargo tank", "Inspection", "Overhaul", "Gauge", "Valve", "LNG", "Boil-off"]
        let n = noise(approxBytes / 8 + 64, seed: seed)
        while size < approxBytes {
            let w = words[Int(n[i % n.count]) % words.count]
            let item = #"{"Id":"\#(UUID().uuidString.lowercased())","Name":"\#(w) \#(i)","Note":"\#(n[(i * 3) % n.count]) \#(w.uppercased()) \#(n[(i * 7) % n.count])","Done":\#(n[(i * 5) % n.count] % 2 == 0)}"#
            items.append(item)
            size += item.utf8.count + 1
            i += 1
        }
        return Array(#"{"Tasks":[\#(items.joined(separator: ","))]}"#.utf8)
    }
}
