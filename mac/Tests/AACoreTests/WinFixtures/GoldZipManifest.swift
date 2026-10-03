// ZIP manifest (spec 01 GF.3.9, GF.4.6, GF.9): a container-independent description of a ZIP produced by the app
// (bundle, XLSX). Built from the raw local and central headers, so the method, flags, version-made-by host,
// external attributes and data-descriptor use that a high-level reader hides are visible. Container bytes can never
// be byte-identical between .NET (zlib-ng) and Apple `Compression`, and DOS timestamps are file mtimes, so the
// comparison covers only the GF.4.6 "significant" fields plus the payload bytes.
import CryptoKit
import Foundation
@testable import AACore

struct GoldZipEntry: Sendable, Hashable {
    var name: String
    var isDirectory: Bool
    var method: Int
    var flags: Int
    var utf8NameFlag: Bool
    var uncompressedSize: UInt64
    var crc32: UInt32
    var sha256: String
    var payload: String?
    var versionMadeByHost: Int
    var externalAttributes: UInt32
    var hasDataDescriptor: Bool
}

struct GoldZipManifest: Sendable {
    var entries: [GoldZipEntry]
    var zip64: Bool
    var comment: String
    var orderSignificant: Bool

    enum ParseError: Error, CustomStringConvertible {
        case notAZip(String)
        var description: String { switch self { case .notAZip(let w): return "not a ZIP archive: \(w)" } }
    }

    // MARK: Building from bytes

    /// Parses `data` (the whole archive). `payloadName` names each entry's payload file (GF.4.2), or nil.
    init(zip data: Data, orderSignificant: Bool = false, payloadName: ((Int, String) -> String?)? = nil) throws {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 2 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> UInt32 {
            o + 4 <= b.count ? UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24 : 0
        }
        func u64(_ o: Int) -> UInt64 { UInt64(u32(o)) | UInt64(u32(o + 4)) << 32 }

        // End of central directory (searched backwards over a comment of up to 65 535 bytes).
        var eocd = -1
        var i = b.count - 22
        let floor = max(0, b.count - 22 - 65_535)
        while i >= floor {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ParseError.notAZip("no end-of-central-directory record") }
        var count = UInt64(u16(eocd + 10))
        var cdOffset = UInt64(u32(eocd + 16))
        let commentLen = u16(eocd + 20)
        comment = String(decoding: b[min(b.count, eocd + 22)..<min(b.count, eocd + 22 + commentLen)], as: UTF8.self)
        zip64 = false
        if eocd >= 20, u32(eocd - 20) == 0x0706_4B50 {
            let z = Int(u64(eocd - 20 + 8))
            if z + 56 <= b.count, u32(z) == 0x0606_4B50 {
                zip64 = true
                count = u64(z + 32)
                cdOffset = u64(z + 48)
            }
        }
        let reader = try ZipReader(data: data)
        var out: [GoldZipEntry] = []
        var p = Int(cdOffset)
        for index in 0..<Int(count) {
            guard p + 46 <= b.count, u32(p) == 0x0201_4B50 else { throw ParseError.notAZip("bad central header \(index)") }
            let madeBy = u16(p + 4)
            let flags = u16(p + 8)
            let method = u16(p + 10)
            let crc = u32(p + 16)
            var uncompressed = UInt64(u32(p + 24))
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
            let ext = u32(p + 38)
            var localOffset = UInt64(u32(p + 42))
            let nameBytes = Array(b[(p + 46)..<min(b.count, p + 46 + nameLen)])
            // ZIP64 extra field: uncompressed, compressed, offset — present only for the 0xFFFFFFFF fields.
            var e = p + 46 + nameLen
            let extraEnd = e + extraLen
            while e + 4 <= extraEnd {
                let id = u16(e), size = u16(e + 2)
                if id == 0x0001 {
                    var q = e + 4
                    if u32(p + 24) == 0xFFFF_FFFF { uncompressed = u64(q); q += 8 }
                    if u32(p + 20) == 0xFFFF_FFFF { q += 8 }
                    if u32(p + 42) == 0xFFFF_FFFF { localOffset = u64(q) }
                }
                e += 4 + size
            }
            let utf8 = flags & 0x0800 != 0
            let name = ZipFormat.decodeName(nameBytes, utf8: utf8)
            let localFlags = Int(localOffset) + 8 <= b.count && u32(Int(localOffset)) == 0x0403_4B50 ? u16(Int(localOffset) + 6) : flags
            let isDir = name.hasSuffix("/")
            var sha = ""
            if !isDir, let info = reader.entries.first(where: { $0.localHeaderOffset == localOffset }) ?? reader.entry(named: name) {
                let payload = (try? reader.data(for: info)) ?? Data()
                sha = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            }
            out.append(GoldZipEntry(
                name: name, isDirectory: isDir, method: method, flags: flags, utf8NameFlag: utf8,
                uncompressedSize: uncompressed, crc32: crc, sha256: sha,
                payload: payloadName?(index + 1, name), versionMadeByHost: madeBy >> 8, externalAttributes: ext,
                hasDataDescriptor: (flags | localFlags) & 0x0008 != 0))
            p += 46 + nameLen + extraLen + commentLen
        }
        entries = out
        self.orderSignificant = orderSignificant
    }

    init(entries: [GoldZipEntry], zip64: Bool = false, comment: String = "", orderSignificant: Bool = false) {
        self.entries = entries; self.zip64 = zip64; self.comment = comment; self.orderSignificant = orderSignificant
    }

    // MARK: JSON (GF.4.6)

    init(json: JSONValue) throws {
        guard let o = json.objectValue, let list = o["entries"]?.arrayValue else {
            throw ParseError.notAZip("manifest JSON has no entries")
        }
        func hex(_ v: JSONValue?) -> UInt64 {
            guard let s = v?.stringValue else { return v?.numberValue?.int64Value.map(UInt64.init) ?? 0 }
            return UInt64(s.hasPrefix("0x") || s.hasPrefix("0X") ? String(s.dropFirst(2)) : s, radix: 16) ?? 0
        }
        entries = list.compactMap { v in
            guard let e = v.objectValue, let name = e["name"]?.stringValue else { return nil }
            return GoldZipEntry(
                name: name, isDirectory: e["isDirectory"]?.boolValue ?? name.hasSuffix("/"),
                method: e["method"]?.numberValue?.intValue ?? 0, flags: e["flags"]?.numberValue?.intValue ?? 0,
                utf8NameFlag: e["utf8NameFlag"]?.boolValue ?? false,
                uncompressedSize: UInt64(e["uncompressedSize"]?.numberValue?.int64Value ?? 0),
                crc32: UInt32(truncatingIfNeeded: hex(e["crc32"])), sha256: e["sha256"]?.stringValue ?? "",
                payload: e["payload"]?.stringValue,
                versionMadeByHost: e["versionMadeByHost"]?.numberValue?.intValue ?? 0,
                externalAttributes: UInt32(truncatingIfNeeded: hex(e["externalAttributes"])),
                hasDataDescriptor: e["hasDataDescriptor"]?.boolValue ?? false)
        }
        zip64 = o["zip64"]?.boolValue ?? false
        comment = o["comment"]?.stringValue ?? ""
        orderSignificant = o["orderSignificant"]?.boolValue ?? false
    }

    var json: JSONValue {
        .object(JSONObject([
            ("entries", .array(entries.map { e in
                var pairs: [(String, JSONValue)] = [
                    ("name", .string(e.name)), ("isDirectory", .bool(e.isDirectory)),
                    ("method", .number(JSONNumber(e.method))), ("flags", .number(JSONNumber(e.flags))),
                    ("utf8NameFlag", .bool(e.utf8NameFlag)),
                    ("uncompressedSize", .number(JSONNumber(Int64(e.uncompressedSize)))),
                    ("crc32", .string(String(format: "0x%08X", e.crc32))), ("sha256", .string(e.sha256)),
                ]
                pairs.append(("payload", e.payload.map(JSONValue.string) ?? .null))
                pairs += [("versionMadeByHost", .number(JSONNumber(e.versionMadeByHost))),
                          ("externalAttributes", .string(String(format: "0x%08X", e.externalAttributes))),
                          ("hasDataDescriptor", .bool(e.hasDataDescriptor))]
                return .object(JSONObject(pairs))
            })),
            ("zip64", .bool(zip64)), ("comment", .string(comment)), ("orderSignificant", .bool(orderSignificant)),
        ]))
    }

    // MARK: Comparison (GF.4.6 "significant")

    /// Compares the significant fields of `actual` against this golden manifest. Recorded-but-not-significant
    /// fields (entry order for bundles, timestamps, compressed sizes, version-made-by host, external attributes,
    /// extra fields, data descriptors, the method of empty files and directories) are ignored.
    func compare(actual: GoldZipManifest) -> [String] {
        var problems: [String] = []
        let ordered = orderSignificant
        let gNames = entries.map(\.name), aNames = actual.entries.map(\.name)
        if ordered {
            if gNames != aNames { problems.append("entry sequence differs: expected \(gNames), got \(aNames)") }
        } else {
            let gs = Set(gNames.map(Ordinal.Key.init)), as_ = Set(aNames.map(Ordinal.Key.init))
            let missing = gNames.filter { !as_.contains(Ordinal.Key($0)) }
            let extra = aNames.filter { !gs.contains(Ordinal.Key($0)) }
            if !missing.isEmpty { problems.append("missing entries \(missing)") }
            if !extra.isEmpty { problems.append("unexpected entries \(extra)") }
            if Set(aNames).count != aNames.count { problems.append("duplicate entry names in the actual archive") }
        }
        for g in entries {
            guard let a = actual.entries.first(where: { Ordinal.equals($0.name, g.name) }) else { continue }
            if g.isDirectory != a.isDirectory { problems.append("\(g.name): isDirectory \(g.isDirectory) vs \(a.isDirectory)") }
            if g.uncompressedSize != a.uncompressedSize {
                problems.append("\(g.name): uncompressedSize \(g.uncompressedSize) vs \(a.uncompressedSize)")
            }
            if !g.isDirectory && g.crc32 != a.crc32 {
                problems.append("\(g.name): crc32 \(String(format: "0x%08X", g.crc32)) vs \(String(format: "0x%08X", a.crc32))")
            }
            if g.utf8NameFlag != a.utf8NameFlag {
                problems.append("\(g.name): UTF-8 name flag \(g.utf8NameFlag) vs \(a.utf8NameFlag)")
            }
            let nonASCII = !g.name.unicodeScalars.allSatisfy(\.isASCII)
            if a.utf8NameFlag != nonASCII {
                problems.append("\(g.name): the UTF-8 name flag must be set iff the name is non-ASCII")
            }
            if !g.isDirectory && g.uncompressedSize > 0 && a.method != 8 {
                problems.append("\(g.name): method \(a.method), expected 8 (deflate) for a non-empty file")
            }
            if !g.sha256.isEmpty && !a.sha256.isEmpty && g.sha256 != a.sha256 && g.payload == nil {
                problems.append("\(g.name): payload SHA-256 differs")
            }
        }
        return problems
    }

    /// True when the AA-format payload must be compared `bytes-masked` (data.json, source.json, settings) — every
    /// other payload is compared as bytes (GF.3.9).
    static func isAAFormat(_ entryName: String) -> Bool {
        let leaf = entryName.split(separator: "/").last.map(String.init) ?? entryName
        return ["data.json", "source.json", "settings.json"].contains(leaf.lowercased())
    }

    /// GF.4.2 payload naming: `<caseId>.entry.<index>-<name with / → _ and non-[A-Za-z0-9._-] → _>.golden.<ext>`.
    static func payloadFileName(caseID: String, index: Int, entryName: String) -> String {
        let sanitized = String(entryName.map { c -> Character in
            if c == "/" { return "_" }
            guard let a = c.asciiValue, c.isASCII,
                  (a >= 0x30 && a <= 0x39) || (a >= 0x41 && a <= 0x5A) || (a >= 0x61 && a <= 0x7A) || c == "." || c == "_" || c == "-"
            else { return "_" }
            return c
        })
        let ext = entryName.split(separator: ".").last.map { String($0).lowercased() } ?? "bin"
        let safeExt = ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } && !ext.isEmpty && entryName.contains(".") ? ext : "bin"
        return "\(caseID).entry.\(index)-\(sanitized).golden.\(safeExt)"
    }
}
