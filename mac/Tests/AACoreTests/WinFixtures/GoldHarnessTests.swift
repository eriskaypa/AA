// Harness self-tests (spec 01 GF.9 "Verification of the plan itself"): the matcher, the XML canonicaliser, the ZIP
// manifest and the MANIFEST/case-record logic, exercised on synthetic data so they are proven before any Windows
// golden exists.
import CryptoKit
import Foundation
import Testing
@testable import AACore

@Suite("WinFixtures harness — GoldenMatcher (GF.9)", .tags(.goldWinFixtures))
struct GoldMatcherSelfTests {
    let guidA = "3f2504e0-4f89-11d3-9a0c-0305e82c3301"
    let guidB = "6fa459ea-ee8a-3ca4-894e-db77e160355e"

    @Test("same-numbered NEWGUID tokens must bind to one value")
    func sameNumberSameValue() {
        let golden = #"{"Id":"%%NEWGUID:1%%","R":"%%NEWGUID:1%%"}"#
        #expect(GoldenMatcher.match(golden: golden, actual: #"{"Id":"\#(guidA)","R":"\#(guidA)"}"#) == nil)
        let m = GoldenMatcher.match(golden: golden, actual: #"{"Id":"\#(guidA)","R":"\#(guidB)"}"#)
        #expect(m != nil)
        #expect(m?.reason.contains("NEWGUID:1") == true)
    }

    @Test("different-numbered NEWGUID tokens must bind to different values")
    func differentNumbersDifferentValues() {
        let golden = #"{"Id":"%%NEWGUID:1%%","R":"%%NEWGUID:2%%"}"#
        #expect(GoldenMatcher.match(golden: golden, actual: #"{"Id":"\#(guidA)","R":"\#(guidB)"}"#) == nil)
        #expect(GoldenMatcher.match(golden: golden, actual: #"{"Id":"\#(guidA)","R":"\#(guidA)"}"#) != nil)
    }

    @Test("GUIDN shares the value space of NEWGUID")
    func guidNSharesValue() {
        let golden = #"{"Id":"%%NEWGUID:3%%","P":"files/%%GUIDN:3%%_Pump manual.pdf"}"#
        let n = guidA.replacingOccurrences(of: "-", with: "")
        #expect(GoldenMatcher.match(golden: golden, actual: #"{"Id":"\#(guidA)","P":"files/\#(n)_Pump manual.pdf"}"#) == nil)
        let other = guidB.replacingOccurrences(of: "-", with: "")
        #expect(GoldenMatcher.match(golden: golden, actual: #"{"Id":"\#(guidA)","P":"files/\#(other)_Pump manual.pdf"}"#) != nil)
    }

    @Test("bindings persist across outputs of one case")
    func bindingsAcrossOutputs() {
        let b = GoldBindings()
        #expect(GoldenMatcher.match(golden: "%%NEWGUID:1%%", actual: guidA, bindings: b) == nil)
        #expect(GoldenMatcher.match(golden: "x=%%NEWGUID:1%%", actual: "x=\(guidB)", bindings: b) != nil)
        #expect(GoldenMatcher.match(golden: "x=%%NEWGUID:1%%", actual: "x=\(guidA)", bindings: b) == nil)
    }

    @Test("NOWUTC rejects the Local form; NOWLOCAL rejects Z")
    func nowForms() {
        #expect(GoldenMatcher.match(golden: #""%%NOWUTC%%""#, actual: #""2026-09-29T08:15:30+00:00""#) != nil)
        #expect(GoldenMatcher.match(golden: #""%%NOWUTC%%""#, actual: #""2026-09-29T08:15:30.1234567Z""#) == nil)
        #expect(GoldenMatcher.match(golden: #""%%NOWLOCAL%%""#, actual: #""2026-09-29T11:15:30.5+03:00""#) == nil)
        #expect(GoldenMatcher.match(golden: #""%%NOWLOCAL%%""#, actual: #""2026-09-29T11:15:30Z""#) != nil)
    }

    @Test("NOWLOCAL must lie within ±10 min of the test clock when a clock is given")
    func nowPlausibility() throws {
        let now = try #require(GoldenMatcher.parseISO("2026-09-29T08:15:30Z"))
        let ctx = GoldMatchContext(dataDir: nil, now: now)
        #expect(GoldenMatcher.match(golden: "%%NOWLOCAL%%", actual: "2026-09-29T11:20:00+03:00", context: ctx) == nil)
        #expect(GoldenMatcher.match(golden: "%%NOWLOCAL%%", actual: "2026-09-29T11:40:00+03:00", context: ctx) != nil)
        #expect(GoldenMatcher.parseISO("2026-09-29T11:15:30.5+03:00") == Date(timeIntervalSince1970: now.timeIntervalSince1970 + 0.5))
    }

    @Test("DATADIR with backslashes matches its JSON-escaped form")
    func dataDirEscaped() {
        let ctx = GoldMatchContext(dataDir: #"C:\aa-winfixtures\run\json-athens"#)
        let golden = #"{"CurrentDataFile":"%%DATADIR%%\\data.json"}"#
        #expect(GoldenMatcher.match(golden: golden, actual: #"{"CurrentDataFile":"C:\\aa-winfixtures\\run\\json-athens\\data.json"}"#,
                                    context: ctx) == nil)
        #expect(GoldenMatcher.match(golden: golden, actual: #"{"CurrentDataFile":"C:\\other\\data.json"}"#, context: ctx) != nil)
        // Raw form (outside a JSON string) too.
        #expect(GoldenMatcher.match(golden: "%%DATADIR%%/files", actual: #"C:\aa-winfixtures\run\json-athens/files"#, context: ctx) == nil)
    }

    @Test("DATADIR without a data folder never matches")
    func dataDirAbsent() {
        #expect(GoldenMatcher.match(golden: "%%DATADIR%%/x", actual: "/tmp/x") != nil)
    }

    @Test("a non-token %% run stays literal (S05 salt \"%%%\")")
    func percentLiteral() {
        #expect(GoldenMatcher.segments(#"{"PasswordSalt":"%%%"}"#) == [.literal(#"{"PasswordSalt":"%%%"}"#)])
        #expect(GoldenMatcher.match(golden: #"{"PasswordSalt":"%%%"}"#, actual: #"{"PasswordSalt":"%%%"}"#) == nil)
        #expect(GoldenMatcher.segments("a%%FOO%%b") == [.literal("a%%FOO%%b")])
    }

    @Test("other token shapes")
    func otherShapes() {
        #expect(GoldenMatcher.match(golden: #""%%SALT16%%""#, actual: #""AAECAwQFBgcICQoLDA0ODw==""#) == nil)
        #expect(GoldenMatcher.match(golden: #""%%HASH32%%""#, actual: #""V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=""#) == nil)
        #expect(GoldenMatcher.match(golden: #""%%ENCBLOB%%""#, actual: #""enc:EBESExQVFhcYGRobHB0eHw4Q==""#) == nil)
        #expect(GoldenMatcher.match(golden: #""%%MACHINE%%""#, actual: #""BRIDGE-PC""#) == nil)
        #expect(GoldenMatcher.match(golden: #""%%MACHINE%%""#, actual: #""a"b""#) != nil)
        #expect(GoldenMatcher.match(golden: "at %%TEMP%%.", actual: "at /var/folders/x/T/AA_export_1.") == nil)
    }

    @Test("a mismatch reports the first differing byte with context on both sides")
    func mismatchReport() throws {
        let golden = #"{"Name":"Pump","Id":"%%NEWGUID:1%%","Description":"main engine"}"#
        let actual = #"{"Name":"Pump","Id":"\#(guidA)","Description":"main engime"}"#
        let m = try #require(GoldenMatcher.match(golden: golden, actual: actual))
        let expectedOffset = Array(actual.utf8).count - #"e"}"#.utf8.count - 1
        #expect(m.offset == expectedOffset)
        #expect(m.actualContext?.contains("engime") == true)
        #expect(m.expectedContext?.contains("engine") == true)
        // Plain byte mismatch.
        let b = try #require(GoldenMatcher.byteMismatch(Data("abcdef".utf8), Data("abcxef".utf8)))
        #expect(b.offset == 3)
        #expect(GoldenMatcher.byteMismatch(Data("abc".utf8), Data("abc".utf8)) == nil)
        let short = try #require(GoldenMatcher.byteMismatch(Data("abc".utf8), Data("ab".utf8)))
        #expect(short.offset == 2)
    }

    @Test("json-semantic: key order ignored, array order kept, code units exact, tokens in strings")
    func jsonSemantic() throws {
        let g = try JSONParser.parse(#"{"a":1,"b":[1,2],"s":"é","id":"%%NEWGUID:1%%"}"#)
        let ok = try JSONParser.parse(#"{"id":"\#(guidA)","s":"é","b":[1,2],"a":1.0}"#)
        #expect(GoldJSONSemantic.compare(golden: g, actual: ok) == nil)
        let order = try JSONParser.parse(#"{"id":"\#(guidA)","s":"é","b":[2,1],"a":1}"#)
        #expect(GoldJSONSemantic.compare(golden: g, actual: order)?.path == "/b/0")
        let nfd = try JSONParser.parse(#"{"id":"\#(guidA)","s":"e\u0301","b":[1,2],"a":1}"#)
        #expect(GoldJSONSemantic.compare(golden: g, actual: nfd)?.path == "/s")
        let extra = try JSONParser.parse(#"{"id":"\#(guidA)","s":"é","b":[1,2],"a":1,"x":null}"#)
        #expect(GoldJSONSemantic.compare(golden: g, actual: extra) != nil)
        #expect(GoldJSONSemantic.resolve("/b/1", in: g) == .number(JSONNumber(2)))
        #expect(GoldJSONSemantic.resolve("/A13.4", in: try JSONParser.parse(#"{"A13.4":true}"#)) == .bool(true))
        #expect(GoldJSONSemantic.resolve("/a~1b", in: try JSONParser.parse(#"{"a/b":3}"#)) == .number(JSONNumber(3)))
    }
}

@Suite("WinFixtures harness — XMLCanonicalizer (GF.9)", .tags(.goldWinFixtures))
struct GoldXMLCanonicalizerSelfTests {
    @Test("attribute order and empty-element form are not significant")
    func attributeOrder() throws {
        #expect(try GoldXMLCanonicalizer.equivalent(#"<A b="1" a="2"/>"#, #"<A a="2" b="1" />"#))
        #expect(try GoldXMLCanonicalizer.canonicalize(#"<A b="1" a="2"></A>"#) == #"<A a="2" b="1" />"#)
    }

    @Test("whitespace in text is significant")
    func whitespace() throws {
        #expect(try !GoldXMLCanonicalizer.equivalent("<R> x</R>", "<R>x</R>"))
        #expect(try GoldXMLCanonicalizer.equivalent("<R> x</R>", "<R> x</R>"))
    }

    @Test("entities normalised; namespaces and prefixed attributes kept")
    func entitiesAndNamespaces() throws {
        let a = #"<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xml:space="preserve" FontSize="14"><Run>A &#38; B &gt; C "q"</Run></Section>"#
        let b = #"<Section FontSize="14" xml:space="preserve" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Run>A &amp; B > C &quot;q&quot;</Run></Section>"#
        #expect(try GoldXMLCanonicalizer.equivalent(a, b))
        let c = try GoldXMLCanonicalizer.canonicalize(a)
        #expect(c.contains("A &amp; B &gt; C \"q\""))
        #expect(c.hasPrefix(#"<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation""#))
    }

    @Test("difference reports an offset; malformed XML is an error")
    func difference() {
        #expect(GoldXMLCanonicalizer.difference(golden: Data("<R><B>x</B></R>".utf8), actual: Data("<R><B>y</B></R>".utf8))?.offset == 6)
        #expect(GoldXMLCanonicalizer.difference(golden: Data("<R/>".utf8), actual: Data("<R>".utf8)) != nil)
        #expect(throws: GoldXMLCanonicalizer.Failure.self) { _ = try GoldXMLCanonicalizer.canonicalize("<a><b></a>") }
    }
}

@Suite("WinFixtures harness — ZipManifest (GF.9)", .tags(.goldWinFixtures))
struct GoldZipManifestSelfTests {
    /// B01's content (GF.5.c): data.json, source.json, two attachments (one NFC non-ASCII name), an empty file and a
    /// file in a sub-folder.
    static let b01Files: [(String, Data)] = [
        ("data.json", Data(#"{"Tasks":[]}"#.utf8)),
        ("source.json", Data(#"{"Identity":"Vessel-Alpha","DataOnly":false}"#.utf8)),
        ("files/0123456789abcdef0123456789abcdef_Manual v2.pdf", Data("0123456789".utf8)),
        ("files/fedcba9876543210fedcba9876543210_W\u{00E4}rtsil\u{00E4} manual.pdf", Data("abcde".utf8)),
        ("files/empty.txt", Data()),
        ("files/sub/x.txt", Data("xyz".utf8)),
    ]

    static func writeZip(_ files: [(String, Data)], to url: URL) throws {
        let z = try ZipWriter(url: url)
        for (n, d) in files { try z.addData(d, named: n, modified: Date(timeIntervalSince1970: 1_790_000_000)) }
        try z.finish()
    }

    /// The manifest .NET would record for B01: same significant fields, different host / attributes / flags.
    static func windowsLikeManifest() -> GoldZipManifest {
        GoldZipManifest(entries: b01Files.enumerated().map { i, f in
            GoldZipEntry(name: f.0, isDirectory: false, method: f.1.isEmpty ? 0 : 8,
                         flags: f.0.unicodeScalars.allSatisfy(\.isASCII) ? 0 : 0x0800,
                         utf8NameFlag: !f.0.unicodeScalars.allSatisfy(\.isASCII),
                         uncompressedSize: UInt64(f.1.count), crc32: CRC32.checksum(f.1),
                         sha256: SHA256.hash(data: f.1).map { String(format: "%02x", $0) }.joined(),
                         payload: nil, versionMadeByHost: 0, externalAttributes: 0, hasDataDescriptor: false)
        }.reversed())                                      // bundle entry order is not significant
    }

    @Test("a Swift-written ZIP of B01's content matches B01's significant fields; container bytes differ")
    func b01SignificantFields() throws {
        let folder = TempFolder("gold-zip")
        let a = folder.file("a.zip"), b = folder.file("b.zip")
        try Self.writeZip(Self.b01Files, to: a)
        try Self.writeZip(Array(Self.b01Files.reversed()), to: b)
        let actual = try GoldZipManifest(zip: try Data(contentsOf: a))
        #expect(actual.entries.count == 6)
        #expect(Self.windowsLikeManifest().compare(actual: actual).isEmpty)
        // Round trip through the GF.4.6 JSON form.
        let reparsed = try GoldZipManifest(json: Self.windowsLikeManifest().json)
        #expect(reparsed.compare(actual: actual).isEmpty)
        // Container bytes differ (entry order, timestamps), yet the manifests agree.
        #expect(try Data(contentsOf: a) != Data(contentsOf: b))
        #expect(Self.windowsLikeManifest().compare(actual: try GoldZipManifest(zip: try Data(contentsOf: b))).isEmpty)
    }

    @Test("significant differences are reported")
    func differences() throws {
        let folder = TempFolder("gold-zip")
        var files = Self.b01Files
        files[2].1 = Data("0123456789X".utf8)                       // size + crc differ
        files.removeLast()                                           // missing entry
        let url = folder.file("c.zip")
        try Self.writeZip(files, to: url)
        let problems = Self.windowsLikeManifest().compare(actual: try GoldZipManifest(zip: try Data(contentsOf: url)))
        #expect(problems.contains { $0.contains("missing entries") })
        #expect(problems.contains { $0.contains("uncompressedSize") })
        #expect(problems.contains { $0.contains("crc32") })
    }

    @Test("ordered manifests (XLSX) compare the entry sequence")
    func ordered() throws {
        let folder = TempFolder("gold-zip")
        let url = folder.file("o.zip")
        try Self.writeZip(Array(Self.b01Files.reversed()), to: url)
        var golden = Self.windowsLikeManifest()
        golden.entries.reverse()
        golden.orderSignificant = true
        let actual = try GoldZipManifest(zip: try Data(contentsOf: url))
        #expect(!golden.compare(actual: actual).isEmpty)
        golden.entries.reverse()
        #expect(golden.compare(actual: actual).isEmpty)
    }

    @Test("raw header fields: UTF-8 flag, host, directories")
    func rawFields() throws {
        let folder = TempFolder("gold-zip")
        let url = folder.file("d.zip")
        let z = try ZipWriter(url: url)
        try z.addDirectory(named: "files/")
        try z.addData(Data("x".utf8), named: "files/Wärtsilä.pdf", modified: nil)
        try z.finish()
        let m = try GoldZipManifest(zip: try Data(contentsOf: url))
        let dir = try #require(m.entries.first { $0.name == "files/" })
        #expect(dir.isDirectory)
        let w = try #require(m.entries.first { $0.name.hasPrefix("files/W") })
        #expect(w.utf8NameFlag)
        #expect([0, 3].contains(w.versionMadeByHost))       // DOS or Unix — recorded, not significant
        #expect(w.method == 8)
    }

    @Test("GF.4.2 payload names")
    func payloadNames() {
        #expect(GoldZipManifest.payloadFileName(caseID: "B01", index: 1, entryName: "data.json") == "B01.entry.1-data.json.golden.json")
        #expect(GoldZipManifest.payloadFileName(caseID: "B01", index: 3, entryName: "files/a b.pdf") == "B01.entry.3-files_a_b.pdf.golden.pdf")
        #expect(GoldZipManifest.payloadFileName(caseID: "B01", index: 4, entryName: "files/Wärtsilä manual.pdf")
                == "B01.entry.4-files_W_rtsil__manual.pdf.golden.pdf")
        #expect(GoldZipManifest.payloadFileName(caseID: "E13.X1", index: 6, entryName: "xl/worksheets/sheet1.xml")
                == "E13.X1.entry.6-xl_worksheets_sheet1.xml.golden.xml")
        #expect(GoldZipManifest.isAAFormat("data.json") && GoldZipManifest.isAAFormat("source.json"))
        #expect(!GoldZipManifest.isAAFormat("files/data.json.pdf"))
    }
}
