// Spec: 13 §3.14 / FLASH-120 (the C# Tests/FlashSync.Interop harness, same subcommands and outputs with a "Swift" prefix),
//       FLASH-121 / §4.6 (frame files: one Base45 frame per line, LF or CRLF, never trimmed), ARCHITECTURE.md §10.4.
//
//   vectors                                              run every protocol vector
//   encode <payload> <out.frames> <n> <kind> <label> [session]
//   decode <in.frames> <out.payload>
//   cs-build <current> <baseline> <cur-settings> <base-settings> <out>
//   cs-apply <data> <settings> <changeset> <out-data> <out-settings>
//   snap-build <data> <settings> <out>
//   snap-apply <payload> <existing-data> <settings> <out-data> <out-settings>
//
// Exit codes: 0 ok, 1 failure ("FAIL: …" on stderr), 2 usage. A missing input file or a non-object file reads as {}.
// Change sets are built with From = "Windows" and created/now = 2026-09-27 12:00:00, exactly like the C# harness, so the
// outputs can be compared byte for byte.
import Foundation
import AACore

fileprivate func fail(_ message: String) -> Int32 {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    return 1
}

fileprivate func usage() -> Int32 {
    FileHandle.standardError.write(Data("usage: vectors | encode | decode | cs-build | cs-apply\n".utf8))
    return 2
}

fileprivate func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined() }

fileprivate func bytes(hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var i = hex.startIndex
    while i < hex.endIndex, let j = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) {
        out.append(UInt8(hex[i ..< j], radix: 16) ?? 0)
        i = j
    }
    return out
}

fileprivate let fixedNow = NetDateTime(year: 2026, month: 9, day: 27, hour: 12, minute: 0, second: 0, kind: .local)

/// C# `Obj(path)`: the file's root object, or {} when the file is missing or not an object.
fileprivate func object(_ path: String) throws -> JSONObject {
    guard FileManager.default.fileExists(atPath: path) else { return JSONObject() }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard case .object(let o) = try JSONParser.parse(data) else { return JSONObject() }
    return o
}

fileprivate func write(_ o: JSONObject, _ path: String) throws {
    try JSONWriter.data(.object(o)).write(to: URL(fileURLWithPath: path))
}

/// Frame-file lines: split on LF, strip only a trailing CR — never trim (Base45 contains spaces).
fileprivate func lines(_ path: String) throws -> [String] {
    // Split the BYTES on LF ("\r\n" is a single Character in Swift, so a String split would miss CRLF files).
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    var out = data.split(separator: 0x0A, omittingEmptySubsequences: false).map { line -> String in
        let bytes = line.last == 0x0D ? line.dropLast() : line
        return String(decoding: bytes, as: UTF8.self)
    }
    if out.last == "" { out.removeLast() }
    return out
}

// MARK: vectors

fileprivate func vectors() -> Int32 {
    var bad = 0
    func check(_ ok: Bool, _ what: String) {
        print("  \(ok ? "✓" : "✗") \(what)")
        if !ok { bad += 1 }
    }

    print("Base45")
    check(FlashBase45.encode([]) == "", "\"\" -> \"\"")
    check(FlashBase45.encode(Array("A".utf8)) == "K1", "\"A\" -> K1")
    check(FlashBase45.encode(Array("AB".utf8)) == "BB8", "\"AB\" -> BB8")
    check(FlashBase45.encode(Array("Hello!!".utf8)) == "%69 VD92EX0", "\"Hello!!\"")
    check(FlashBase45.encode(Array("base-45".utf8)) == "UJCLQE7W581", "\"base-45\"")
    check(FlashBase45.encode([0, 1, 0xFE, 0xFF]) == "100TAW", "00 01 FE FF -> 100TAW")
    check(FlashBase45.decode("HELLO WORLD!") == nil, "foreign text rejected")

    print("CRC-32")
    check(CRC32.checksum([UInt8]()) == 0x0000_0000, "\"\"")
    check(CRC32.checksum(Array("123456789".utf8)) == 0xCBF4_3926, "\"123456789\" = CBF43926")
    check(CRC32.checksum(Array("AA flash sync".utf8)) == 0xCD53_9EA5, "\"AA flash sync\"")

    print("xorshift32")
    func seq(_ seed: UInt32, _ want: [UInt32]) {
        var r = FlashRandom(seed: seed)
        check((0 ..< 8).map { _ in r.next() } == want, "seed \(seed)")
    }
    seq(1, [270369, 67634689, 2647435461, 307599695, 2398689233, 745495504, 632435482, 435756210])
    seq(12345, [3336926330, 1697253807, 2816511904, 1955480042, 718842323, 3283620450, 4285686168, 3680911160])
    seq(0, [1359758873, 3761132862, 2075758394, 25405621, 3862129951, 4186559031, 3122997712, 4244368831])

    print("degree")
    for (r, deg) in [(UInt32(0), 1), (83, 1), (84, 2), (553, 2), (554, 3), (1023, 60), (1024, 1), (4294967295, 60)] {
        check(FlashFountain.degree(r, 1000) == deg, "r=\(r) -> \(deg)")
    }

    print("indices (the ten rows that everything else rests on)")
    let rows: [(UInt32, Int, [Int])] = [
        (0, 5, [0]), (3, 5, [3]), (7, 5, [2]), (99, 5, [4]),
        (0, 100, [0]), (99, 100, [99]), (100, 100, [34]), (101, 100, [47]),
        (5000, 100, [64, 90]), (65535, 100, [50]),
    ]
    for (s, k, want) in rows {
        check(FlashFountain.indices(s, k) == want, "seed=\(s) K=\(k) -> [\(want.map(String.init).joined(separator: ","))]")
    }

    print("frames")
    let m = FlashManifestFrame(session: 0x1234, codedBytes: 1129, rawBytes: 3075, chunkSize: 900, chunkCount: 2,
                               crc32: 0x3D31_50F8, kind: .changeSet, label: "1 equipment")
    check(hex(FlashFrame.encodeManifest(m)) == "414151010012340000046900000C03038400023D3150F8000B312065717569706D656E74",
          "manifest bytes")
    check(FlashBase45.encode(FlashFrame.encodeManifest(m)) == "AB8$AAI00$P6400FCDC006H0.UGXC0OA6%FVUI1D44KFE$EDF$DG/D",
          "manifest QR text")
    let d = FlashDataFrame(session: 0x1234, seed: 7, payload: (0 ..< 16).map { UInt8($0) })
    check(hex(FlashFrame.encodeData(d)) == "4141510101123400000007000102030405060708090A0B0C0D0E0F", "data bytes")
    check(FlashBase45.encode(FlashFrame.encodeData(d)) == "AB8$AA460$P6000$*0X507H0QS00+0J61%H1CT1F0", "data QR text")

    print("DEFLATE (must inflate the iOS stream; must be RAW, not zlib)")
    let ios = bytes(hex: "73748401273870860300")
    let raw = bytes(hex: "414141414141414141414242424242424242424243434343434343434343")
    check((try? RawDeflate.inflate(ios, expectedLength: raw.count)) == raw, "inflates the iOS-produced stream")
    let ours = (try? RawDeflate.compress(raw)) ?? []
    check(!ours.isEmpty && ours[0] != 0x78,
          "our output is raw DEFLATE (first byte \(ours.first.map { String(format: "%02X", $0) } ?? "--"), not 78)")

    print(bad == 0 ? "\nALL VECTORS PASS" : "\n\(bad) VECTOR(S) FAILED")
    return bad == 0 ? 0 : 1
}

// MARK: encode / decode

fileprivate func encode(_ a: [String]) throws -> Int32 {
    guard a.count >= 6, let n = Int(a[3]), n >= 0 else { return usage() }
    let payload = [UInt8](try Data(contentsOf: URL(fileURLWithPath: a[1])))
    let kind: FlashFrameKind = a[4] == "snapshot" ? .fullSnapshot : .changeSet
    var session = FlashEncoder.newSession()
    if a.count > 6 {
        guard let s = UInt16(a[6]) else { return usage() }
        session = s
    }
    let enc = try FlashEncoder(payload: payload, kind: kind, label: a[5], session: session)
    var out = ""
    out.reserveCapacity(n * 1400)
    for _ in 0 ..< n { out += enc.next() + "\n" }
    try Data(out.utf8).write(to: URL(fileURLWithPath: a[2]))
    print("Swift encoded \(n) frames, K=\(enc.chunkCount), raw=\(payload.count)")
    return 0
}

fileprivate func decode(_ a: [String]) throws -> Int32 {
    guard a.count >= 3 else { return usage() }
    let dec = FlashDecoder()
    var count = 0
    for line in try lines(a[1]) {
        count += 1
        dec.ingest(line)
        if dec.isComplete { break }
    }
    guard dec.isComplete else {
        return fail("Swift decoder incomplete after \(count) frames (\(dec.solvedCount)/\(dec.chunkCount))")
    }
    guard let payload = dec.finish() else { return fail("Swift decoder: CRC or inflate failed") }
    try Data(payload).write(to: URL(fileURLWithPath: a[2]))
    print("Swift decoded \(payload.count) bytes after \(count) frames, label=\"\(dec.label)\"")
    return 0
}

// MARK: change sets and snapshots

fileprivate func csBuild(_ a: [String]) throws -> Int32 {
    guard a.count >= 6 else { return usage() }
    let cs = FlashChangeSet.buildChangeSet(current: try object(a[1]), baselineData: try object(a[2]),
                                           currentSettings: try object(a[3]), baselineSettings: try object(a[4]),
                                           from: "Windows", created: fixedNow)
    try write(cs ?? JSONObject(), a[5])
    print("Swift built change set: \(cs.map(FlashChangeSet.summarize) ?? "no changes")")
    return 0
}

fileprivate func csApply(_ a: [String]) throws -> Int32 {
    guard a.count >= 6 else { return usage() }
    var data = try object(a[1])
    var settings = try object(a[2])
    FlashChangeSet.applyChangeSet(try object(a[3]), data: &data, settings: &settings, now: fixedNow)
    try write(data, a[4])
    try write(settings, a[5])
    print("Swift applied change set")
    return 0
}

fileprivate func snapBuild(_ a: [String]) throws -> Int32 {
    guard a.count >= 4 else { return usage() }
    try write(FlashChangeSet.buildSnapshot(data: try object(a[1]), settings: try object(a[2])), a[3])
    print("Swift built snapshot")
    return 0
}

fileprivate func snapApply(_ a: [String]) throws -> Int32 {
    guard a.count >= 6 else { return usage() }
    var settings = try object(a[3])
    let r = FlashChangeSet.applySnapshot(try object(a[1]), settings: &settings, now: fixedNow, existingData: try object(a[2]))
    try write(r.data, a[4])
    try write(settings, a[5])
    print("Swift applied snapshot (carried settings: \(r.hadSettings ? "True" : "False"))")
    return 0
}

// MARK: main

let args = Array(CommandLine.arguments.dropFirst())
let code: Int32
do {
    switch args.first {
    case "vectors": code = vectors()
    case "encode": code = try encode(args)
    case "decode": code = try decode(args)
    case "cs-build": code = try csBuild(args)
    case "cs-apply": code = try csApply(args)
    case "snap-build": code = try snapBuild(args)
    case "snap-apply": code = try snapApply(args)
    default: code = usage()
    }
} catch {
    code = fail(String(describing: error))
}
exit(code)
