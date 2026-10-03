// MANIFEST / case-record logic and the runner, unit-tested on synthetic fixture roots (W-GOLD acceptance:
// "MANIFEST/selfcheck logic unit-tested on synthetic manifests"; spec 01 GF.4.3/GF.4.4, GF.9). The synthetic goldens
// are the literal vectors the specs quote (01 §4.2.1, §7.5), so a pass also proves the reproducers against them.
import Foundation
import Testing
@testable import AACore

/// A temporary fixture root with a MANIFEST built from case records.
@MainActor
final class GoldSyntheticRoot {
    let folder = TempFolder("gold-synthetic")
    var root: URL { folder.url }

    func write(_ rel: String, _ text: String) throws { try folder.write(rel, text) }
    func write(_ rel: String, _ data: Data) throws { try folder.write(rel, data) }

    func manifest(_ cases: [String]) throws -> GoldFixtureIndex {
        let text = "{\"schema\":1,\"generator\":{\"name\":\"WinFixtures\",\"version\":\"1.0.0\",\"linkedSourcesCommit\":\"37cdab0\"," +
            "\"linkedSources\":[{\"path\":\"AA/Models/Models.cs\",\"sha256\":\"00\"}]},\"generatedAtUtc\":\"2026-09-30T10:00:00Z\"," +
            "\"today\":\"2026-09-30\",\"runs\":[],\"cases\":[" + cases.joined(separator: ",") + "],\"specConflicts\":[],\"platformDivergences\":[]}"
        try write("MANIFEST.json", text)
        return GoldFixtureIndex(root: root)
    }
}

@MainActor
@Suite("WinFixtures harness — manifest and runner (GF.4.3, GF.4.4, GF.9)", .tags(.goldWinFixtures))
struct GoldHarnessManifestTests {
    static let a01 = #"{"id":"A01","family":"json","title":"new AppData()","platform":"any","tz":"Europe/Athens","normative":"must","compare":"bytes-masked","dependsOnToday":false,"inputs":{},"outputs":[{"role":"result","file":"json/A01.appdata.golden.json"}],"macExpectation":{"kind":"same"},"settles":["01 §4.2.1"]}"#

    @Test("a manifest decodes; ids, modes, platform, outputs, mac flags and pointers are read")
    func decode() throws {
        let r = GoldSyntheticRoot()
        let divergent = #"{"id":"A06.1","family":"json","title":"x","compare":"bytes-masked","outputs":[{"role":"outcome","file":"json/A06.1.outcome.golden.json","compare":"json-semantic"},{"role":"bytes","file":"json/A06.1.appdata.golden.json","mac":false}],"macExpectation":{"kind":"divergent","file":"windows/json/A06.1w.x.golden.json#/rows","role":"bytes","reason":"01 §4.1.10"}}"#
        let index = try r.manifest([Self.a01, divergent])
        let m = try #require(index.manifest)
        #expect(m.cases.count == 2)
        #expect(m.today == "2026-09-30")
        #expect(m.linkedSourcesCommit == "37cdab0")
        #expect(index.cases(family: "json").map(\.id) == ["A01", "A06.1"])
        let c = m.cases[1]
        #expect(c.platform == .any)                                          // default
        #expect(c.normative == .must)                                        // default
        #expect(c.outputs[0].compare == .jsonSemantic)
        #expect(c.outputs[1].macCompared == false)
        #expect(c.macExpectation.kind == .divergent)
        #expect(c.macExpectation.file == "windows/json/A06.1w.x.golden.json")
        #expect(c.macExpectation.pointer == "/rows")
        #expect(c.group == "A06")
        #expect(c.testDescription == "A06.1")
    }

    @Test("invalid manifests are rejected with a reason")
    func rejects() throws {
        let r = GoldSyntheticRoot()
        _ = try r.manifest([Self.a01, Self.a01])
        #expect(GoldFixtureIndex(root: r.root).loadError?.contains("duplicate id A01") == true)
        _ = try r.manifest([#"{"id":"X","family":"json","compare":"fuzzy","outputs":[]}"#])
        #expect(GoldFixtureIndex(root: r.root).loadError?.contains("unknown mode fuzzy") == true)
        _ = try r.manifest([#"{"id":"X","family":"json","outputs":[],"macExpectation":{"kind":"divergent"}}"#])
        #expect(GoldFixtureIndex(root: r.root).loadError?.contains("cite its spec clause") == true)
        try r.write("MANIFEST.json", #"{"schema":2,"cases":[]}"#)
        #expect(GoldFixtureIndex(root: r.root).loadError?.contains("schema") == true)
        try r.write("MANIFEST.json", "not json")
        #expect(GoldFixtureIndex(root: r.root).available == false)
        #expect(GoldFixtureIndex(root: r.root).loadError != nil)
    }

    @Test("absent manifest: not available, no error (the suites skip)")
    func absent() {
        let r = GoldSyntheticRoot()
        let index = GoldFixtureIndex(root: r.root)
        #expect(!index.available)
        #expect(index.loadError == nil)
        #expect(index.cases(family: "json").isEmpty)
    }

    @Test("A01 end to end: the 01 §4.2.1 literal as the golden reproduces; a corrupted golden reports the byte")
    func a01EndToEnd() async throws {
        let r = GoldSyntheticRoot()
        try r.write("json/A01.appdata.golden.json", Goldens.freshDB)
        let index = try r.manifest([Self.a01])
        let c = try #require(index.manifest?.cases.first)
        let repro = try #require(GoldJSONFamily.table.reproducer(for: c))
        let ctx = GoldCaseContext(index: index, fixtureCase: c)
        let actual = try await repro.run(ctx)
        #expect(GoldCaseRunner.compareAll(c, actual: actual, ctx: ctx).problems.isEmpty)

        try r.write("json/A01.appdata.golden.json", Goldens.freshDB.replacingOccurrences(of: "\"SchemaVersion\":1", with: "\"SchemaVersion\":2"))
        let ctx2 = GoldCaseContext(index: index, fixtureCase: c)
        let problems = GoldCaseRunner.compareAll(c, actual: actual, ctx: ctx2).problems
        #expect(problems.count == 1)
        #expect(problems.first?.contains("first difference at byte \(Goldens.freshDB.utf8.count - 2)") == true)
    }

    @Test("A13 in New York against the 01 §7.5 read table")
    func a13NewYork() async throws {
        let r = GoldSyntheticRoot()
        // 2026-10-01T00:00:00 = 639264096000000000 ticks (01 §7.5); 17:00 the day before = − 7 h.
        let golden = """
        {"tz":"America/New_York","rows":[
         {"input":"2026-10-01T00:00:00+03:00","ok":true,"ticks":639263844000000000,"kind":"Local","isAmbiguousTime":false,"isDaylightSavingTime":true,"wall":"2026-09-30 17:00:00.0000000","rewritten":"2026-09-30T17:00:00-04:00"},
         {"input":"2026-10-01","ok":true,"ticks":639264096000000000,"kind":"Unspecified","isAmbiguousTime":false,"isDaylightSavingTime":true,"wall":"2026-10-01 00:00:00.0000000","rewritten":"2026-10-01T00:00:00"},
         {"input":"2026-10-01T00:00:00Z","ok":true,"ticks":639264096000000000,"kind":"Utc","isAmbiguousTime":false,"isDaylightSavingTime":false,"wall":"2026-10-01 00:00:00.0000000","rewritten":"2026-10-01T00:00:00Z"},
         {"input":"2026-10-01 00:00:00","ok":false,"error":{"type":"System.Text.Json.JsonException","aaAuthored":false}},
         {"input":"01/10/2026","ok":false,"error":{"type":"System.Text.Json.JsonException","aaAuthored":false}},
         {"input":"2026-11-01T05:30:00Z","ok":true,"ticks":639291078000000000,"kind":"Utc","isAmbiguousTime":true,"isDaylightSavingTime":false,"wall":"2026-11-01 05:30:00.0000000","rewritten":"2026-11-01T05:30:00Z"}
        ]}
        """
        try r.write("json/A13.2.read-matrix.golden.json", golden)
        let rec = #"{"id":"A13.2","family":"json","title":"reads in New York","platform":"unix","tz":"America/New_York","compare":"json-semantic","inputs":{"strings":["2026-10-01T00:00:00+03:00","2026-10-01","2026-10-01T00:00:00Z","2026-10-01 00:00:00","01/10/2026","2026-11-01T05:30:00Z"]},"outputs":[{"role":"result","file":"json/A13.2.read-matrix.golden.json"}],"macExpectation":{"kind":"same"}}"#
        let index = try r.manifest([rec])
        let c = try #require(index.manifest?.cases.first)
        let ctx = GoldCaseContext(index: index, fixtureCase: c)
        let actual = try await #require(GoldJSONFamily.table.reproducer(for: c)).run(ctx)
        let problems = GoldCaseRunner.compareAll(c, actual: actual, ctx: ctx).problems
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test("divergent: only the Mac-expected golden is compared; mac:false outputs and record-only divergences are skipped")
    func divergentAndMacFlag() async throws {
        let r = GoldSyntheticRoot()
        try r.write("json/A06.9.outcome.golden.json", #"{"loadOk":false,"saveOk":false,"exception":{"type":"System.NullReferenceException","message":"x","aaAuthored":false}}"#)
        try r.write("json/A06.9.mac-expected.golden.json", Goldens.freshDB)
        let rec = #"{"id":"A06.9","family":"json","title":"Subtasks null","inputs":{"inline":"{}"},"outputs":[{"role":"outcome","file":"json/A06.9.outcome.golden.json","compare":"json-semantic"}],"macExpectation":{"kind":"divergent","file":"json/A06.9.mac-expected.golden.json","role":"bytes","reason":"01 §4.1.10"}}"#
        let recordOnly = #"{"id":"A25s","family":"json","title":"x","outputs":[{"role":"result","file":"json/missing.json"}],"macExpectation":{"kind":"divergent","reason":"01 §6.6"}}"#
        let skipped = #"{"id":"A20","family":"json","title":"x","compare":"json-semantic","outputs":[{"role":"outcome","file":"json/A20.outcome.golden.json"},{"role":"exception","file":"json/nowhere.json","mac":false}]}"#
        try r.write("json/A20.outcome.golden.json", #"{"lastLoadFailed":true}"#)
        let index = try r.manifest([rec, recordOnly, skipped])
        let cases = try #require(index.manifest?.cases)

        // `{}` loads on the Mac to the empty database: equal to the Mac-expected golden; the Windows outcome is ignored.
        let a06 = cases[0]
        let ctx = GoldCaseContext(index: index, fixtureCase: a06)
        let actual = try await #require(GoldJSONFamily.table.reproducer(for: a06)).run(ctx)
        #expect(GoldCaseRunner.compareAll(a06, actual: actual, ctx: ctx).problems.isEmpty)

        let a25s = cases[1]
        #expect(GoldCaseRunner.compareAll(a25s, actual: [:], ctx: GoldCaseContext(index: index, fixtureCase: a25s)).problems.isEmpty)

        let a20 = cases[2]
        let ok = GoldCaseRunner.compareAll(a20, actual: ["outcome": .json(GoldDotNet.obj([("lastLoadFailed", .bool(true))]))],
                                           ctx: GoldCaseContext(index: index, fixtureCase: a20))
        #expect(ok.problems.isEmpty)
        let missing = GoldCaseRunner.compareAll(a20, actual: [:], ctx: GoldCaseContext(index: index, fixtureCase: a20))
        #expect(missing.problems == ["outcome: the reproducer produced no output for this role"])
    }

    @Test("json-semantic ignores .NET type/message of framework exceptions but not AA-authored ones")
    func aaAuthored() throws {
        let golden = try JSONParser.parse(#"{"exception":{"type":"System.IO.IOException","message":"The process cannot access the file","aaAuthored":false}}"#)
        #expect(GoldJSONSemantic.compare(golden: golden, actual: try JSONParser.parse(#"{"exception":{"aaAuthored":false}}"#)) == nil)
        let aa = try JSONParser.parse(#"{"exception":{"type":"System.IO.InvalidDataException","message":"The bundle has no data.json.","aaAuthored":true}}"#)
        #expect(GoldJSONSemantic.compare(golden: aa, actual: try JSONParser.parse(#"{"exception":{"type":"System.IO.InvalidDataException","message":"The bundle has no data.json.","aaAuthored":true}}"#)) == nil)
        #expect(GoldJSONSemantic.compare(golden: aa, actual: try JSONParser.parse(#"{"exception":{"type":"System.IO.InvalidDataException","message":"No data.json.","aaAuthored":true}}"#)) != nil)
    }

    @Test("reproducer lookup: exact id, the `w` twin, the group, the family prefix")
    func lookup() {
        let table = GoldReproducerTable(entries: ["A06": GoldReproducer { _ in [:] }, "A25x": GoldReproducer { _ in [:] },
                                                  "A09a": GoldReproducer { _ in [:] }])
        func c(_ id: String) -> GoldFixtureCase {
            GoldFixtureCase(id: id, family: "json", title: "", platform: .any, tz: nil, normative: .must, compare: .bytes,
                            dependsOnToday: false, today: nil, inputs: JSONObject(), outputs: [], macExpectation: .same, settles: [])
        }
        #expect(table.reproducer(for: c("A06.14")) != nil)
        #expect(table.reproducer(for: c("A25xw")) != nil)
        #expect(table.reproducer(for: c("A09a")) != nil)
        #expect(table.reproducer(for: c("A09b")) == nil)
        #expect(table.reproducer(for: c("B01")) == nil)
    }

    @Test("every json-family reproducer group of the C# catalogue is registered")
    func jsonCatalogueCovered() {
        let ids = ["A01", "A02", "A03", "A04", "A05", "A06.1", "A07.11", "A08.2", "A09a", "A09b", "A10", "A11.3", "A12.4",
                   "A13.6", "A14.3", "A15a", "A15.5", "A16.22", "A17.4", "A18", "A19.9", "A20", "A20w", "W19w", "A21",
                   "A22.1", "A22.2", "A22.3", "A23", "A24.6", "A25", "A25x", "A25xw", "A25s", "A26"]
        for id in ids {
            let c = GoldFixtureCase(id: id, family: "json", title: "", platform: .any, tz: nil, normative: .must, compare: .bytes,
                                    dependsOnToday: false, today: nil, inputs: JSONObject(), outputs: [], macExpectation: .same, settles: [])
            #expect(GoldJSONFamily.table.reproducer(for: c) != nil, "no reproducer for \(id)")
        }
    }
}
