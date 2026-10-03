// Family (c) bundles — Swift reproductions of B01–B08, the R reader fixtures, the import matrix M, the peek matrix P,
// the truth tables T and ApplySyncedData C01 (spec 01 GF.5.c, DATA-317). Everything except BundleSource (F1) runs
// through W-PERSIST's BundleService / AttachmentStore / DataStore+Sync, so those reproducers are gated on its
// ContractStatus (post-merge acceptance).
import Foundation
import Testing
@testable import AACore

@MainActor
enum GoldBundleFamily {
    typealias Ctx = GoldCaseContext

    /// The data folder with A02 bytes as data.json and AppIdentity Vessel-Alpha (the GF.5.c default).
    static func localData(_ ds: DataStore, _ ctx: Ctx, json: Data? = nil) throws {
        try FileManager.default.createDirectory(at: ds.appFolder, withIntermediateDirectories: true)
        try (json ?? (try ds.serializeForSave(GoldKitchenSink.build()))).write(to: ds.defaultDataFile)
        ds.settings.setAppIdentity("Vessel-Alpha")
    }

    /// L0 = empty files/; L1 = files/{a.pdf 10 B, b.pdf 5 B}.
    static func localState(_ ds: DataStore, _ state: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        for f in (try? fm.contentsOfDirectory(at: ds.filesFolder, includingPropertiesForKeys: nil)) ?? [] { try fm.removeItem(at: f) }
        if state == "L1" {
            try Data("0123456789".utf8).write(to: ds.filesFolder.appending(path: "a.pdf"))
            try Data("abcde".utf8).write(to: ds.filesFolder.appending(path: "b.pdf"))
        }
    }

    static func filesListing(_ ds: DataStore) -> JSONValue {
        let urls = (try? FileManager.default.contentsOfDirectory(at: ds.filesFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let rows = urls.filter { !$0.hasDirectoryPath }.sorted { Ordinal.compare($0.lastPathComponent, $1.lastPathComponent) == .orderedAscending }
            .map { u -> JSONValue in
                let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return GoldDotNet.obj([("name", .string(u.lastPathComponent)), ("size", GoldDotNet.int(size))])
            }
        return .array(rows)
    }

    static func scratch(_ ctx: Ctx) throws -> URL {
        let u = ctx.folder.url.appending(path: "scratch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// The committed archive of a matrix row, copied to scratch (imports never read the fixture tree in place).
    static func stagedBundle(_ ctx: Ctx) throws -> URL {
        guard let rel = ctx.inlineString("bundle") else { throw GoldReproError.missingInput("bundle") }
        let dst = try scratch(ctx).appending(path: (rel as NSString).lastPathComponent)
        try ctx.index.data(rel).write(to: dst)
        return dst
    }

    /// An error as the GF.4.7 exception shape (AA-authored when the message is one of AA's own texts).
    static func exceptionShape(_ error: Error, authoredWhen phrases: [String]) -> JSONValue {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        if phrases.contains(where: { message.contains($0) }) {
            return GoldDotNet.obj([("message", .string(message)), ("aaAuthored", .bool(true))])
        }
        return GoldDotNet.frameworkException
    }

    // MARK: Writer cases

    static func export(_ ctx: Ctx, setup: (DataStore) throws -> Void) async throws -> GoldActual {
        let ds = ctx.makeDataStore()
        try setup(ds)
        let dest = try scratch(ctx).appending(path: "\(ctx.fixtureCase.id).bundle.zip")
        try await BundleService.exportFolderToZip(ds, to: dest, includeAttachments: !ds.settings.values.textOnlyExport)
        return ["bundle": .zip(try Data(contentsOf: dest))]
    }

    static func b01Files(_ ds: DataStore, all: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: ds.filesFolder.appending(path: "sub"), withIntermediateDirectories: true)
        try Data("0123456789".utf8).write(to: ds.filesFolder.appending(path: "0123456789abcdef0123456789abcdef_Manual v2.pdf"))
        guard all else { return }
        try Data("abcde".utf8).write(to: ds.filesFolder.appending(path: "fedcba9876543210fedcba9876543210_W\u{00E4}rtsil\u{00E4} manual.pdf"))
        try Data().write(to: ds.filesFolder.appending(path: "empty.txt"))
        try Data("xyz".utf8).write(to: ds.filesFolder.appending(path: "sub/x.txt"))
    }

    static let writer: [String: GoldReproducer] = [
        "B01": GoldReproducer(requires: .wPersist) { ctx in
            try await export(ctx) { ds in try localData(ds, ctx); try b01Files(ds, all: true) }
        },
        "B02": GoldReproducer(requires: .wPersist) { ctx in
            try await export(ctx) { ds in
                try localData(ds, ctx); try b01Files(ds, all: false)
                ds.settings.setTextOnlyExport(true)
            }
        },
        "B03": GoldReproducer(requires: .wPersist) { ctx in
            try await export(ctx) { ds in
                try localData(ds, ctx)
                try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
            }
        },
        "B04": GoldReproducer(requires: .wPersist) { ctx in
            let ext = try scratch(ctx).appending(path: "aa-data.json")
            return try await export(ctx) { ds in
                try localData(ds, ctx)
                let a01 = AppData()
                a01.lastModified = GoldDates.dLM
                try ds.serializeForSave(a01).write(to: ext)
                ds.setCurrentDataFile(ext)
            }
        },
        "B05a": GoldReproducer(requires: .wPersist) { ctx in
            let missing = try scratch(ctx).appending(path: "missing.json")
            return try await export(ctx) { ds in try localData(ds, ctx); ds.setCurrentDataFile(missing) }
        },
        "B05b": GoldReproducer(requires: .wPersist) { ctx in
            let missing = try scratch(ctx).appending(path: "missing.json")
            return try await export(ctx) { ds in ds.settings.setAppIdentity("Vessel-Alpha"); ds.setCurrentDataFile(missing) }
        },
        "B06a": GoldReproducer(requires: .wPersist) { ctx in
            let ds = ctx.makeDataStore()
            try localData(ds, ctx)
            do {
                try await BundleService.exportFolderToZip(ds, to: ds.appFolder.appending(path: "x.zip"), includeAttachments: true)
                return ["result": .json(GoldDotNet.obj([("threw", .bool(false))]))]
            } catch {
                return ["result": .json(GoldDotNet.obj([("exception", exceptionShape(error, authoredWhen: ["Choose a destination"]))]))]
            }
        },
        "B06b": GoldReproducer { _ in [:] },               // divergent (D-13 fixed), asserted by W-PERSIST
        "B07": GoldReproducer { ctx in
            let s = BundleSource(identity: "Vessel-Alpha", machine: "BRIDGE-PC",
                                 writtenUtc: NetDateTime(year: 2026, month: 9, day: 29, hour: 8, minute: 15, second: 30,
                                                         fractionTicks: 1_234_567, kind: .utc),
                                 lastModified: GoldDates.dLM, dataOnly: false)
            return ["result": .bytes(try JSONWriter.data(.object(s.toJSON(options: ctx.encodeOptions))))]
        },
        "B08": GoldReproducer { ctx in
            let s: BundleSource
            switch ctx.fixtureCase.id {
            case "B08.1": s = BundleSource(identity: "Vessel-Alpha", machine: "BRIDGE-PC", writtenUtc: GoldDates.dZ, lastModified: nil)
            case "B08.2": s = BundleSource(identity: "", machine: "BRIDGE-PC", writtenUtc: GoldDates.dZ, lastModified: GoldDates.dLM)
            default: s = BundleSource(identity: "Vessel-Alpha", machine: "BRIDGE-PC", lastModified: GoldDates.dLM, dataOnly: true)
            }
            return ["result": .bytes(try JSONWriter.data(.object(s.toJSON(options: ctx.encodeOptions)))),
                    "display": .json(GoldDotNet.obj([("WrittenLocal", .string(s.writtenLocal))]))]
        },
    ]

    // MARK: Matrices

    static let matrixCell = GoldReproducer(requires: .wPersist) { ctx in
        let ds = ctx.makeDataStore()
        try localData(ds, ctx)
        try localState(ds, ctx.inlineString("localState") ?? "L0")
        let bundle = try stagedBundle(ctx)
        let before = try Data(contentsOf: ds.defaultDataFile)
        let filesBefore = filesListing(ds)
        var result: JSONValue = .null
        var exception: JSONValue = .null
        let smart = ctx.inlineString("operation") == "ImportBundleSmart"
        do {
            if smart {
                result = .string(try BundleService.importBundleSmart(ds, from: bundle) == .dataOnly ? "DataOnly" : "WithAttachments")
            } else {
                try BundleService.importSharedBundle(ds, from: bundle)
                result = .string("Applied")
            }
        } catch {
            exception = exceptionShape(error, authoredWhen: ["has no data.json"])
        }
        let after = (try? Data(contentsOf: ds.defaultDataFile)) ?? Data()
        let changed = before != after
        let threw = !exception.isNull
        let filesAfter = filesListing(ds)
        let cell = GoldDotNet.obj([
            ("result", result), ("threw", .bool(threw)), ("exception", exception), ("filesAfter", filesAfter),
            ("dataJsonChanged", .bool(changed)),
            ("currentDataFileIsDefault", .bool(ds.currentDataFile.standardizedFileURL == ds.defaultDataFile.standardizedFileURL)),
            ("localModifiedBeforeThrow", .bool(threw && (changed || filesAfter != filesBefore))),
        ])
        var out: GoldActual = ["cell": .json(cell)]
        if changed && !after.isEmpty { out["data"] = .bytes(after) }
        return out
    }

    static let peek = GoldReproducer(requires: .wPersist) { ctx in
        let ds = ctx.makeDataStore()
        let bundle = try stagedBundle(ctx)
        let source = BundleService.peekBundleSource(bundle)
        let data = BundleService.peekZipData(bundle, dataStore: ds)
        return ["result": .json(GoldDotNet.obj([
            ("lastModified", GoldDotNet.dateOrNull(BundleService.peekZipLastModified(bundle), zone: ctx.zone)),
            ("source", source.map { .object($0.toJSON(options: ctx.encodeOptions)) } ?? .null),
            ("identity", GoldDotNet.str(source?.identity)),
            ("data", data.map { ModelCodec.encodeAppData($0, options: ctx.encodeOptions) } ?? .null),
        ]))]
    }

    static let c01 = GoldReproducer(requires: .wPersist) { ctx in
        let ds = ctx.makeDataStore()
        try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        try Data("0123456789".utf8).write(to: ds.filesFolder.appending(path: "ab12_x.pdf"))
        let json = try GoldJSONFamily.inputFile(ctx)
        let returned = try ds.applySyncedData(json)
        return ["model": .bytes(try JSONWriter.data(ModelCodec.encodeAppData(returned, options: ctx.encodeOptions))),
                "data": .bytes(try Data(contentsOf: ds.defaultDataFile))]
    }

    static let table: GoldReproducerTable = {
        var e = writer
        for r in ["R01", "R02", "R03", "R04", "R05", "R06", "R07", "R08", "R09", "R10", "R11", "R12", "R13", "R14", "R15", "R16", "R17"] {
            e[r] = GoldReproducer { _ in ["bundle": .skip("reader fixture (an input of the M and P matrices)")] }
        }
        e["M"] = matrixCell
        e["P"] = peek
        e["T"] = GoldReproducer { _ in [:] }                // private Windows helpers; the M matrix covers the Mac
        e["C01"] = c01
        return GoldReproducerTable(entries: e)
    }()
}

@MainActor
@Suite("WinFixtures — bundles (DATA-317)", .tags(.goldWinFixtures),
       .enabled(if: GoldFixtureIndex.winfixtures.available, GoldFixtureIndex.absentMessage))
struct GoldBundleGoldenTests {
    @Test("GF.5.c case", arguments: GoldFixtureIndex.winfixtures.cases(family: "bundles"))
    func bundleCase(_ c: GoldFixtureCase) async {
        await GoldCaseRunner.run(c, index: .winfixtures, table: GoldBundleFamily.table)
    }
}

@MainActor
@Suite("WinFixtures harness — bundle reproducers", .tags(.goldWinFixtures))
struct GoldBundleReproducerTests {
    @Test("B07 against the 01 §4.4 source.json literal")
    func b07Literal() async throws {
        let r = GoldSyntheticRoot()
        try r.write("bundles/B07.source.golden.json",
                    #"{"Identity":"Vessel-Alpha","Machine":"BRIDGE-PC","WrittenUtc":"2026-09-29T08:15:30.1234567Z","LastModified":"2026-09-29T11:15:29.9876543+03:00","DataOnly":false}"#)
        let index = try r.manifest([#"{"id":"B07","family":"bundles","title":"source","tz":"Europe/Athens","outputs":[{"role":"result","file":"bundles/B07.source.golden.json"}]}"#])
        let c = try #require(index.manifest?.cases.first)
        let ctx = GoldCaseContext(index: index, fixtureCase: c)
        let actual = try await #require(GoldBundleFamily.table.reproducer(for: c)).run(ctx)
        let problems = GoldCaseRunner.compareAll(c, actual: actual, ctx: ctx).problems
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test("every bundle case group of the C# catalogue has a reproducer")
    func covered() {
        for id in ["B01", "B02", "B03", "B04", "B05a", "B05b", "B06a", "B06b", "B07", "B08.1", "B08.3", "R01", "R17",
                   "M.R05.smart.L1", "M.B01.shared.L0", "M.R14.smart.L1w", "P.R16", "P.B05a", "T", "C01", "C01w"] {
            let c = GoldFixtureCase(id: id, family: "bundles", title: "", platform: .any, tz: nil, normative: .must, compare: .bytes,
                                    dependsOnToday: false, today: nil, inputs: JSONObject(), outputs: [], macExpectation: .same, settles: [])
            #expect(GoldBundleFamily.table.reproducer(for: c) != nil, "no reproducer for \(id)")
        }
    }
}
