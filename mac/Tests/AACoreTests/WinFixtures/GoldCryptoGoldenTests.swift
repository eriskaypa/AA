// Family (d) crypto — Swift reproductions of K01–K10 (spec 01 GF.5.d, DATA-318): PBKDF2, the app password, `enc:`
// blobs (fixed-IV reference vectors re-encrypted on the Mac; random-IV Windows blobs decrypted and re-derived from
// their IV), negatives, BOM sniffing, IsEncrypted, and the per-item lock.
import CryptoKit
import Foundation
import Testing
@testable import AACore

@MainActor
enum GoldCryptoFamily {
    static let s = Data((0..<16).map { UInt8($0) })
    static var sBase64: String { NetBase64.encode(s) }
    static let iv = Data((0x10..<0x20).map { UInt8($0) })

    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    static func fromHex(_ h: String) -> Data {
        var out = Data()
        var i = h.startIndex
        while i < h.endIndex, let j = h.index(i, offsetBy: 2, limitedBy: h.endIndex) {
            if let b = UInt8(h[i..<j], radix: 16) { out.append(b) }
            i = j
        }
        return out
    }

    static func goldenRows(_ ctx: GoldCaseContext, path: String? = nil) throws -> [JSONObject] {
        let root = try JSONParser.parse(try GoldJSONFamily.golden(ctx, role: "result"))
        let node = path.map { root.objectValue?[$0] ?? .null } ?? root
        return (node.arrayValue ?? []).compactMap(\.objectValue)
    }

    /// A settings file holding the given app password fields, read the way a Mac launch reads it.
    static func passwordService(hash: String?, salt: String?, _ ctx: GoldCaseContext) throws -> PasswordService {
        let ds = DataStore(appFolder: ctx.dataFolder, secrets: InMemorySecretStore(), clock: GoldZoneClock(zone: ctx.zone))
        try FileManager.default.createDirectory(at: ctx.dataFolder, withIntermediateDirectories: true)
        var o = JSONObject()
        if let hash { o.set("PasswordHash", .string(hash)) }
        if let salt { o.set("PasswordSalt", .string(salt)) }
        try JSONWriter.data(.object(o)).write(to: ds.settingsFile)
        ds.loadSettings()
        return PasswordService(settings: ds.settings)
    }

    // MARK: Reproducers

    static let k01 = GoldReproducer { ctx in
        let passwords = (ctx.inline("passwords")?.arrayValue ?? []).compactMap(\.stringValue)
        let s2 = Data(Array(SHA256.hash(data: Data("AA-fixture-salt".utf8))).prefix(16))
        var rows: [JSONValue] = []
        for pw in passwords {
            for (name, salt) in [("S", s), ("S2", s2)] {
                let k32 = PBKDF2.sha256(password: pw, salt: salt, iterations: 100_000, length: 32)
                let k64 = PBKDF2.sha256(password: pw, salt: salt, iterations: 100_000, length: 64)
                let keys = LegacyBodyCrypto.keys(password: pw, salt: salt)
                rows.append(GoldDotNet.obj([
                    ("password", .string(pw)), ("passwordUtf8Hex", .string(hex(Data(pw.utf8)))), ("salt", .string(name)),
                    ("saltHex", .string(hex(salt))), ("iterations", GoldDotNet.int(100_000)),
                    ("dk32Hex", .string(hex(k32))), ("dk32Base64", .string(NetBase64.encode(k32))),
                    ("dk64Hex", .string(hex(k64))), ("dk64Base64", .string(NetBase64.encode(k64))),
                    ("prefixEqual", .bool(k64.prefix(32) == k32)),
                    ("encKeyHex", .string(hex(keys.enc))), ("macKeyHex", .string(hex(keys.mac))),
                ]))
            }
        }
        let prim = PBKDF2.sha256(password: "password", salt: Data("salt".utf8), iterations: 1, length: 32)
        let nfc = passwords.count > 3 ? PBKDF2.sha256(password: passwords[2], salt: s, iterations: 100_000, length: 32) : Data()
        let nfd = passwords.count > 3 ? PBKDF2.sha256(password: passwords[3], salt: s, iterations: 100_000, length: 32) : Data()
        return ["result": .json(GoldDotNet.obj([
            ("rows", .array(rows)),
            ("primitive", GoldDotNet.obj([("password", .string("password")), ("salt", .string("salt")), ("iterations", GoldDotNet.int(1)),
                                          ("dkLen", GoldDotNet.int(32)), ("hex", .string(hex(prim)))])),
            ("nfcEqualsNfd", .bool(nfc == nfd)),
        ]))]
    }

    static let k02 = GoldReproducer { ctx in
        let probes = ["correct horse", "Correct horse", "correct horse ", "", "redemption", "Redemption"]
        var rows: [JSONValue] = []
        for g in try goldenRows(ctx) {
            let hash = g["hash"]?.stringValue, salt = g["salt"]?.stringValue
            var pairs: [(String, JSONValue)] = [("state", g["state"] ?? .null), ("hash", GoldDotNet.str(hash)), ("salt", GoldDotNet.str(salt))]
            if let salt, !salt.isEmpty, NetBase64.decode(salt) == nil {
                // Windows' LoadFrom throws on an undecodable salt; the Mac's settings reader refuses the same state
                // (01 §3.1 catch branch) — both sides report "refused".
                pairs.append(("exception", GoldDotNet.frameworkException))
            } else {
                let ps = try passwordService(hash: hash, salt: salt, ctx)
                pairs.append(("hasPassword", .bool(ps.hasPassword)))
                pairs.append(("verify", GoldDotNet.obj(probes.map { ($0, .bool(ps.verify($0))) })))
                pairs.append(("unlock", .bool(ps.unlock("correct horse"))))
                pairs.append(("isUnlocked", .bool(ps.isUnlocked)))
            }
            rows.append(GoldDotNet.obj(pairs))
        }
        return ["result": .json(.array(rows))]
    }

    static let k03 = GoldReproducer { ctx in
        var rows: [JSONValue] = []
        for g in try goldenRows(ctx) {
            var o = g
            let pw = g["password"]?.stringValue ?? ""
            let saltB64 = g["saltBase64"]?.stringValue ?? sBase64
            var blob = g["blob"]?.stringValue ?? ""
            if g["bom"]?.boolValue == true, let text = g["text"]?.stringValue {
                blob = LegacyBodyCrypto.encrypt(text, password: pw, saltBase64: saltB64, iv: fromHex(g["ivHex"]?.stringValue ?? hex(iv)))
            }
            o.set("blob", .string(blob))
            o.set("decrypted", GoldDotNet.str(LegacyBodyCrypto.decrypt(blob, password: pw, saltBase64: saltB64)))
            rows.append(.object(o))
        }
        return ["result": .json(.array(rows))]
    }

    static let k04 = GoldReproducer { ctx in
        var rows: [JSONValue] = []
        for g in try goldenRows(ctx) {
            let blob = g["blob"]?.stringValue ?? ""
            let text = g["text"]?.stringValue ?? ""
            let combined = NetBase64.decode(String(blob.dropFirst(4))) ?? Data()
            let ivFromBlob = Data(combined.prefix(16))
            let re = LegacyBodyCrypto.encrypt(text, password: "correct horse", saltBase64: sBase64, iv: ivFromBlob)
            rows.append(GoldDotNet.obj([("text", .string(text)), ("blob", .string(blob)), ("ivHex", .string(hex(ivFromBlob))),
                                        ("refEqual", .bool(re == blob)),
                                        ("decrypted", GoldDotNet.str(LegacyBodyCrypto.decrypt(blob, password: "correct horse", saltBase64: sBase64)))]))
        }
        return ["result": .json(.array(rows))]
    }

    static let k05 = GoldReproducer { ctx in
        var rows: [JSONValue] = []
        for g in try goldenRows(ctx) {
            let variant = g["variant"]?.stringValue ?? ""
            let blob = g["blob"]?.stringValue ?? ""
            let result: String?
            switch variant {
            case let v where v.hasPrefix("wrong password"):
                result = LegacyBodyCrypto.decrypt(blob, password: "Correct horse", saltBase64: sBase64)
            case let v where v.hasPrefix("master password"):
                result = LegacyBodyCrypto.decrypt(blob, password: "redemption", saltBase64: sBase64)
            case "not unlocked", "salt null":
                result = nil                                     // no session password / no salt: nothing to derive with
            default:
                result = LegacyBodyCrypto.decrypt(blob, password: "correct horse", saltBase64: sBase64)
            }
            rows.append(GoldDotNet.obj([("variant", .string(variant)), ("blob", .string(blob)), ("result", GoldDotNet.str(result))]))
        }
        return ["result": .json(.array(rows))]
    }

    static let k06 = GoldReproducer { ctx in
        var rows: [JSONValue] = []
        for g in try goldenRows(ctx) {
            let blob = g["blob"]?.stringValue ?? ""
            let d = LegacyBodyCrypto.decrypt(blob, password: "correct horse", saltBase64: sBase64)
            let units: JSONValue = d.map { .string($0.utf16.map { String(format: "%04X", $0) }.joined(separator: " ")) } ?? .null
            rows.append(GoldDotNet.obj([("plaintextHex", g["plaintextHex"] ?? .null), ("blob", .string(blob)),
                                        ("decrypted", GoldDotNet.str(d)), ("decryptedUtf16", units)]))
        }
        return ["result": .json(.array(rows))]
    }

    static let k07 = GoldReproducer { _ in
        let inputs: [String?] = [nil, "", "enc:", "enc:x", "ENC:x", " enc:x", "enc", "<Section"]
        return ["result": .json(.array(inputs.map { s in
            GoldDotNet.obj([("input", GoldDotNet.str(s)), ("result", .bool(s.map(LegacyBodyCrypto.isEncrypted) ?? false))])
        }))]
    }

    static let k08 = GoldReproducer { ctx in
        var rows: [JSONValue] = []
        for g in try goldenRows(ctx) {
            let hash = g["lockHash"]?.stringValue, salt = g["lockSalt"]?.stringValue
            let t = TaskItem(id: GoldG(3), name: "locked")
            t.lockHash = hash; t.lockSalt = salt
            let probes = (g["verify"]?.objectValue?.keys) ?? []
            rows.append(GoldDotNet.obj([
                ("item", g["item"] ?? .null), ("lockHash", GoldDotNet.str(hash)), ("lockSalt", GoldDotNet.str(salt)),
                ("isLockProtected", .bool(t.isLockProtected)),
                ("verify", GoldDotNet.obj(probes.map { pw in
                    (pw, .bool(ItemLockService.verify(password: pw, hashBase64: hash ?? "", saltBase64: salt ?? "")))
                })),
            ]))
        }
        return ["result": .json(.array(rows))]
    }

    static let k09 = GoldReproducer { ctx in
        @MainActor func item() -> TaskItem {
            let t = TaskItem(id: GoldG(3), name: "locked")
            t.container = Container(id: GoldG(103))
            return t
        }
        @MainActor func bytes(_ t: TaskItem) throws -> Data { try JSONWriter.data(.object(t.toJSON(options: ctx.encodeOptions))) }
        let locks = ItemLockService()
        let a = item()
        locks.protect(a, password: "correct horse", hint: "  hint  ")
        let hintBytes = try bytes(a)
        let b = item()
        locks.protect(b, password: "pw", hint: "   ")
        let blankBytes = try bytes(b)
        locks.relockAll()
        var seq: [JSONValue] = []
        @MainActor func step(_ name: String, _ returned: Bool?) {
            seq.append(GoldDotNet.obj([("step", .string(name)), ("returned", GoldDotNet.bool(returned)),
                                       ("isGated", .bool(locks.isGated(a))), ("isLockProtected", .bool(a.isLockProtected))]))
        }
        step("after Protect", nil)
        step("TryUnlock(\"wrong\")", await locks.tryUnlock(a, password: "wrong"))
        step("TryUnlock(\"correct horse\")", await locks.tryUnlock(a, password: "correct horse"))
        locks.relock(a.id); step("Relock", nil)
        step("TryUnlock(\"redemption\")", await locks.tryUnlock(a, password: "redemption"))
        locks.removeProtection(a); step("RemoveProtection", nil)
        return ["protect.hint": .bytes(hintBytes), "protect.blankHint": .bytes(blankBytes),
                "sequence": .json(.array(seq)), "removed": .bytes(try bytes(a))]
    }

    static let table = GoldReproducerTable(entries: [
        "K01": k01, "K02": k02, "K03": k03, "K04": k04, "K05": k05, "K06": k06, "K07": k07, "K08": k08, "K09": k09,
        "K10": GoldReproducer { _ in [:] },
    ])
}

@MainActor
@Suite("WinFixtures — crypto (DATA-318)", .tags(.goldWinFixtures),
       .enabled(if: GoldFixtureIndex.winfixtures.available, GoldFixtureIndex.absentMessage))
struct GoldCryptoGoldenTests {
    @Test("GF.5.d case", arguments: GoldFixtureIndex.winfixtures.cases(family: "crypto"))
    func cryptoCase(_ c: GoldFixtureCase) async {
        await GoldCaseRunner.run(c, index: .winfixtures, table: GoldCryptoFamily.table)
    }
}

@MainActor
@Suite("WinFixtures harness — crypto reproducers against the 01 §7.1/§7.2 and 05 §7.6 literals", .tags(.goldWinFixtures))
struct GoldCryptoReproducerTests {
    @Test("K03-shaped golden built from the spec's literal blobs is reproduced exactly")
    func k03Literals() async throws {
        let r = GoldSyntheticRoot()
        let rows = """
        [{"name":"BOM + \\"\\"","password":"correct horse","saltBase64":"AAECAwQFBgcICQoLDA0ODw==","ivHex":"101112131415161718191a1b1c1d1e1f","plaintextHex":"efbbbf","bom":true,"text":"","blob":"enc:EBESExQVFhcYGRobHB0eHw4QRSqEYezPC65cF1E8B3R1ApbahQo1UxRvd3kio+7TgvGYrwMij8bZDWxhSRRHsw==","decrypted":""},
         {"name":"BOM + <Section>hi</Section>","password":"correct horse","saltBase64":"AAECAwQFBgcICQoLDA0ODw==","ivHex":"101112131415161718191a1b1c1d1e1f","plaintextHex":"x","bom":true,"text":"<Section>hi</Section>","blob":"enc:EBESExQVFhcYGRobHB0eHxJkbpvR5sxlvHs4LU1Zlc/8FgD7jQznyIZndaufj6DG8Ti6ErBbvtnRWs5/oiOkMApZpCT7lzAUZnjCNe73CmY=","decrypted":"<Section>hi</Section>"},
         {"name":"\\"\\" without BOM","password":"correct horse","saltBase64":"AAECAwQFBgcICQoLDA0ODw==","ivHex":"101112131415161718191a1b1c1d1e1f","plaintextHex":"","bom":false,"text":"","blob":"enc:EBESExQVFhcYGRobHB0eHxVqH9CC+wbDQym8EpaLqTzI1CGEYvJ2gETXttL9DZejPrh/qVUIZuxQ+8nwx/+CxQ==","decrypted":""},
         {"name":"test1234: BOM + the 05 §7.6 XAML","password":"test1234","saltBase64":"AAECAwQFBgcICQoLDA0ODw==","ivHex":"101112131415161718191a1b1c1d1e1f","plaintextHex":"x","bom":true,"text":"<Section xmlns=\\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\\"><Paragraph><Run>Secret</Run></Paragraph></Section>","blob":"enc:EBESExQVFhcYGRobHB0eH7yh0+cZnnHk+wt1LaJhOt37Vp1TfN1upIjugsLMCx8A+1BO/lOwe048ZDbt09pbLyzc0beZRySCCCdKYiLMU5PdZE5PJzh+Mh/dB0qGRrpyynpDMaDlxhjSkurNzory7yVyLf5MXDJksvDN6MZQ6xq0cW8h2FEuYihYTqxvmhwrVt1py4SETHUppvsjlMHfskgrHLivepYL5vBOq4Iy1MYzL9/UXBU8F/ZSwuzCLFPP","decrypted":"<Section xmlns=\\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\\"><Paragraph><Run>Secret</Run></Paragraph></Section>"}]
        """
        try r.write("crypto/K03.blobs.golden.json", rows)
        let rec = #"{"id":"K03","family":"crypto","title":"blobs","compare":"json-semantic","outputs":[{"role":"result","file":"crypto/K03.blobs.golden.json"}]}"#
        let index = try r.manifest([rec])
        let c = try #require(index.manifest?.cases.first)
        let ctx = GoldCaseContext(index: index, fixtureCase: c)
        let actual = try await GoldCryptoFamily.k03.run(ctx)
        let problems = GoldCaseRunner.compareAll(c, actual: actual, ctx: ctx).problems
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test("K08-shaped truth table (01 §7.1) is reproduced")
    func k08Literals() async throws {
        let r = GoldSyntheticRoot()
        try r.write("crypto/K08.verify.golden.json", """
        [{"item":"locked (V/LC…, S)","lockHash":"V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=","lockSalt":"AAECAwQFBgcICQoLDA0ODw==","isLockProtected":true,
          "verify":{"correct horse":true,"Correct horse":false,"":false,"redemption":true}},
         {"item":"no lock","lockHash":null,"lockSalt":null,"isLockProtected":false,"verify":{"redemption":true,"x":false}},
         {"item":"LockSalt \\"not base64!\\"","lockHash":"V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=","lockSalt":"not base64!","isLockProtected":true,"verify":{"correct horse":false}}]
        """)
        let rec = #"{"id":"K08","family":"crypto","title":"verify","compare":"json-semantic","outputs":[{"role":"result","file":"crypto/K08.verify.golden.json"}]}"#
        let index = try r.manifest([rec])
        let c = try #require(index.manifest?.cases.first)
        let ctx = GoldCaseContext(index: index, fixtureCase: c)
        let actual = try await GoldCryptoFamily.k08.run(ctx)
        let problems = GoldCaseRunner.compareAll(c, actual: actual, ctx: ctx).problems
        #expect(problems.isEmpty, "\(problems)")
    }
}
