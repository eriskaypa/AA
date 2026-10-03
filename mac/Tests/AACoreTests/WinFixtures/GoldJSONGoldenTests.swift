// Family (a) `data.json` — the Swift reproductions of cases A01–A26 and W19 (spec 01 GF.5.a, DATA-315, DATA-324).
// Each reproducer builds the case's input with the Mac code (models, DataStore, AppStore) and returns the outputs by
// role; GoldCaseRunner compares them with the Windows goldens (or the Mac-expected golden of a divergent case).
import Foundation
import Testing
@testable import AACore

@MainActor
enum GoldJSONFamily {
    typealias Ctx = GoldCaseContext

    // MARK: Shared operations

    static func serialize(_ d: AppData, _ ctx: Ctx) throws -> Data {
        try ctx.makeDataStore().serializeForSave(d)
    }

    /// Writes `doc` as the data file, loads it with `loadFrom` and re-serialises — the C# `Shapes.LoadSave`.
    static func loadSave(_ doc: Data, _ ctx: Ctx) -> (outcome: JSONValue, bytes: Data?, model: AppData?) {
        let ds = ctx.makeDataStore()
        let url = ds.defaultDataFile
        do { try doc.write(to: url) } catch {
            return (GoldDotNet.obj([("loadOk", .bool(false)), ("saveOk", .bool(false)), ("exception", GoldDotNet.frameworkException)]), nil, nil)
        }
        let model: AppData
        do { model = try ds.loadFrom(url) } catch {
            return (GoldDotNet.obj([("loadOk", .bool(false)), ("saveOk", .bool(false)), ("exception", GoldDotNet.frameworkException)]), nil, nil)
        }
        do {
            let bytes = try ds.serializeForSave(model)
            return (GoldDotNet.obj([("loadOk", .bool(true)), ("saveOk", .bool(true))]), bytes, model)
        } catch {
            return (GoldDotNet.obj([("loadOk", .bool(true)), ("saveOk", .bool(false)), ("exception", GoldDotNet.frameworkException)]), nil, model)
        }
    }

    /// The generic load/save case: `inputs.inline` → outcome + bytes.
    static func inlineLoadSave(_ ctx: Ctx) throws -> GoldActual {
        let (outcome, bytes, _) = loadSave(try ctx.inlineDocument(), ctx)
        var out: GoldActual = ["outcome": .json(outcome)]
        if let bytes { out["bytes"] = .bytes(bytes) }
        return out
    }

    static func golden(_ ctx: Ctx, role: String) throws -> Data {
        guard let ref = ctx.fixtureCase.output(role) else { throw GoldReproError.unexpected("no \(role) output") }
        return try ctx.goldenData(ref.file)
    }

    /// A case's input file (`inputs.file` or another key).
    static func inputFile(_ ctx: Ctx, key: String = "file") throws -> Data {
        guard let rel = ctx.inlineString(key) else { throw GoldReproError.missingInput(key) }
        return try ctx.index.data(rel)
    }

    // MARK: A12 / A18 builders

    static func dateTasks(_ ctx: Ctx) throws -> [TaskItem] {
        guard let specs = ctx.inline("tasks")?.arrayValue else { throw GoldReproError.missingInput("tasks") }
        return try specs.map { v in
            guard let o = v.objectValue, let id = o["id"]?.stringValue.flatMap(UUID.init(netString:)),
                  let cid = o["containerId"]?.stringValue.flatMap(UUID.init(netString:)),
                  let ticks = o["ticks"]?.numberValue?.int64Value else { throw GoldReproError.unexpected("bad A12 task spec") }
            let t = TaskItem(id: id, name: o["name"]?.stringValue ?? "")
            t.container = Container(id: cid)
            let kind: NetDateTime.Kind = switch o["kind"]?.stringValue {
            case "Utc": .utc
            case "Local": .local
            default: .unspecified
            }
            if o["via"]?.stringValue == "utcToLocal", let utc = o["utcTicks"]?.numberValue?.int64Value {
                t.deadline = NetDateTime(ticks: utc, kind: .utc).toLocalTime(zone: ctx.zone)
            } else {
                t.deadline = NetDateTime(ticks: ticks, kind: kind)
            }
            return t
        }
    }

    /// A18: `KitchenSink.Task(2000, "level 1")` … `level n`, the deepest with a file linking G(1).
    static func chain(_ n: Int) -> TaskItem {
        let root = GoldKitchenSink.task(2000, "level 1")
        var cur = root
        if n >= 2 {
            for level in 2...n {
                let next = GoldKitchenSink.task(2000 + level - 1, "level \(level)")
                cur.subtasks = [next]
                cur = next
            }
        }
        cur.container.files = [FileItem(id: GoldG(2999), name: "deep.pdf", path: "files/deep.pdf", kind: .document,
                                        added: GoldDates.dL, linkedItemIds: [GoldG(1)])]
        return root
    }

    // MARK: A24

    static func trashStep(_ index: Int, _ store: AppStore) -> JSONValue {
        let task = { store.data.tasks.first { $0.id == GoldG(3) }! }
        let crew = { store.data.crew.first { $0.id == GoldG(11) }! }
        switch index {
        case 1: return GoldDotNet.str(store.trash(task())?.itemType)
        case 2: return GoldDotNet.str(store.trash(crew()).itemType)
        case 3:
            guard let e = store.trash(task()) else { return .null }
            return GoldDotNet.str(store.restore(e)?.rawValue)
        case 4:
            let e = store.trash(crew())
            return GoldDotNet.str(store.restore(e)?.rawValue)
        case 5:
            let t = task()
            guard let e = store.trash(t) else { return .null }
            store.data.tasks.append(t)
            return GoldDotNet.str(store.restore(e)?.rawValue)
        default:
            let bad = TrashedItem(id: GoldG(31), itemType: "Task", itemId: GoldG(32), name: "bad", kindLabel: "Task",
                                  deletedUtc: .utcNow(), payloadJson: "{\"Tasks\":")
            let bogus = TrashedItem(id: GoldG(33), itemType: "Bogus", itemId: GoldG(34), name: "bogus", kindLabel: "?",
                                    deletedUtc: .utcNow(), payloadJson: "{}")
            store.data.trash.append(bad)
            store.data.trash.append(bogus)
            return GoldDotNet.obj([("invalidPayload", GoldDotNet.str(store.restore(bad)?.rawValue)),
                                   ("bogusType", GoldDotNet.str(store.restore(bogus)?.rawValue))])
        }
    }

    // MARK: A25

    static func expand(_ p: String, _ dir: String) -> String {
        p.replacingOccurrences(of: "{DATADIR_UPPER}", with: NetText.toUpperInvariant(dir))
            .replacingOccurrences(of: "{DATADIR}", with: dir)
    }

    /// `Path.IsPathRooted`: POSIX on the unix run; on the windows run a drive (`C:`), a UNC/`\` or `/` prefix.
    static func isRooted(_ p: String, windows: Bool) -> Bool {
        if !windows { return p.hasPrefix("/") }
        let u = Array(p.utf8)
        if u.first == 0x5C || u.first == 0x2F { return true }
        return u.count >= 2 && u[1] == 0x3A && ((u[0] >= 0x41 && u[0] <= 0x5A) || (u[0] >= 0x61 && u[0] <= 0x7A))
    }

    static func paths(_ ctx: Ctx, classifyAndImport: Bool) throws -> GoldActual {
        let ds = ctx.makeDataStore()
        try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        try Data("0123456789".utf8).write(to: ds.filesFolder.appending(path: "ab12_x.pdf"))
        let dir = ds.appFolder.path
        let windows = ctx.fixtureCase.platform == .windows
        var rows: [JSONValue] = []
        for raw in (ctx.inline("stored")?.arrayValue ?? []).compactMap(\.stringValue) {
            for mode in ["plain", "IsLink", "LinkInPlace"] {
                let p = expand(raw, dir)
                func make() -> FileItem {
                    FileItem(id: GoldG(201), name: "x", path: p, isLink: mode == "IsLink", linkInPlace: mode == "LinkInPlace")
                }
                func holder(_ f: FileItem) -> AppData {
                    let d = AppData()
                    let e = Equipment(id: GoldG(1))
                    e.container = Container(id: GoldG(101), files: [f])
                    d.equipment = [e]
                    return d
                }
                let nf = make(), mf = make()
                AttachmentStore.normalizeFilePaths(ds, data: holder(nf))
                AttachmentStore.migrateLegacyAbsolutePaths(ds, data: holder(mf))
                let under: JSONValue = isRooted(p, windows: windows) ? .bool(ds.isUnderAppFolder(URL(fileURLWithPath: p))) : .null
                rows.append(GoldDotNet.obj([("stored", .string(raw)), ("mode", .string(mode)), ("normalized", .string(nf.path)),
                                            ("migrated", .string(mf.path)),
                                            ("resolved", .string(AttachmentStore.resolveFilePath(ds, stored: p))),
                                            ("isUnderAppFolder", under)]))
            }
        }
        var result: [(String, JSONValue)] = [("rows", .array(rows))]
        if classifyAndImport {
            let names = ["X.PDF", "a.heic", "b.webm", "c.csv", "noext", "a.tar.gz", ".hidden", "file.", "dir.d/file", "x.JPEG "]
            result.append(("classify", .array(names.map {
                GoldDotNet.obj([("path", .string($0)), ("kind", GoldDotNet.int(AttachmentStore.classify(path: $0).rawValue))])
            })))
            let src = ctx.folder.file("src/Pump manual.pdf")
            try FileManager.default.createDirectory(at: src.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("pump".utf8).write(to: src)
            let imported = try AttachmentStore.importFile(ds, from: src)
            let exists = FileManager.default.fileExists(atPath: ds.appFolder.appending(path: imported).path)
            result.append(("import", .array([GoldDotNet.obj([("source", .string("Pump manual.pdf")), ("result", .string(imported)),
                                                              ("exists", .bool(exists))])])))
        }
        return ["result": .json(.object(JSONObject(result)))]
    }

    // MARK: The table

    static let table = GoldReproducerTable(entries: [
        "A01": GoldReproducer { ctx in ["result": .bytes(try serialize(AppData(), ctx))] },
        "A02": GoldReproducer { ctx in ["result": .bytes(try serialize(GoldKitchenSink.build(), ctx))] },
        "A03": GoldReproducer { ctx in
            let a02 = try ctx.goldenData(ctx.inlineString("from") ?? "json/A02.appdata.golden.json")
            let (_, bytes, _) = loadSave(a02, ctx)
            guard let bytes else { throw GoldReproError.unexpected("the A02 golden did not load on the Mac") }
            return ["result": .bytes(bytes)]
        },
        "A04": GoldReproducer { ctx in ["result": .bytes(try serialize(GoldKitchenSink.defaults(), ctx))] },
        "A05": GoldReproducer { ctx in
            let (outcome, bytes, _) = loadSave(try inputFile(ctx), ctx)
            guard let bytes else { throw GoldReproError.unexpected("A05 did not load: \(outcome)") }
            return ["result": .bytes(bytes)]
        },
        "A06": GoldReproducer { ctx in try inlineLoadSave(ctx) },
        "A07": GoldReproducer { ctx in try inlineLoadSave(ctx) },
        "A08": GoldReproducer { ctx in try inlineLoadSave(ctx) },
        "A09a": GoldReproducer { ctx in
            guard let name = ctx.inlineString("name"), let description = ctx.inlineString("description"),
                  let id = ctx.inlineString("taskId").flatMap(UUID.init(netString:)),
                  let cid = ctx.inlineString("containerId").flatMap(UUID.init(netString:)) else {
                throw GoldReproError.missingInput("name/description/taskId/containerId")
            }
            let t = TaskItem(id: id, name: name)
            t.description = description
            t.container = Container(id: cid)
            return ["result": .bytes(try serialize(GoldKitchenSink.withTasks([t]), ctx))]
        },
        "A09b": GoldReproducer { _ in ["outcome": .skip("Swift strings cannot hold a lone surrogate (record-only)")] },
        "A10": GoldReproducer { ctx in
            let (outcome, bytes, _) = loadSave(try inputFile(ctx), ctx)
            var out: GoldActual = ["outcome": .json(outcome)]
            if let bytes { out["bytes"] = .bytes(bytes) }
            return out
        },
        "A11": GoldReproducer { ctx in try inlineLoadSave(ctx) },
        "A12": GoldReproducer { ctx in ["result": .bytes(try serialize(GoldKitchenSink.withTasks(try dateTasks(ctx)), ctx))] },
        "A13": GoldReproducer { ctx in
            let strings = (ctx.inline("strings")?.arrayValue ?? []).compactMap(\.stringValue)
            return ["result": .json(GoldDotNet.obj([("tz", GoldDotNet.str(ctx.fixtureCase.tz)),
                                                    ("rows", .array(strings.map { GoldDotNet.dateReadShape($0, zone: ctx.zone) }))]))]
        },
        "A14": GoldReproducer { ctx in
            let athens = try ctx.goldenData(ctx.inlineString("from") ?? "json/A12.1.appdata.golden.json")
            let (_, bytes, _) = loadSave(athens, ctx)
            guard let bytes else { throw GoldReproError.unexpected("the A12.1 golden did not load on the Mac") }
            return ["result": .bytes(bytes)]
        },
        "A15a": GoldReproducer { ctx in
            let values = (ctx.inline("values")?.arrayValue ?? []).compactMap { $0.stringValue.flatMap(Double.init) }
            let v = Vessel(id: GoldG(8), name: "doubles")
            v.container = Container(id: GoldG(108))
            v.quickCards = values.enumerated().map { i, x in
                let q = QuickCard(id: GoldG(300 + i))
                q.x = x; q.y = x; q.width = x; q.height = x
                return q
            }
            let d = AppData()
            d.vessels = [v]
            d.ui.windowLeft = -0.0; d.ui.windowTop = 5e-324; d.ui.calendarFontScale = 0.30000000000000004
            d.ui.dueWindowWidth = 1e16; d.ui.dueWindowHeight = 1.5e-7
            return ["result": .bytes(try serialize(d, ctx))]
        },
        "A15": GoldReproducer { ctx in try inlineLoadSave(ctx) },
        "A16": GoldReproducer { ctx in
            let (outcome, bytes, model) = loadSave(try ctx.inlineDocument(), ctx)
            var o = outcome.objectValue ?? JSONObject()
            if let t = model?.tasks.first {
                o.set("Status", .number(JSONNumber(t.status.rawValue)))
                o.set("IsComplete", .bool(t.isComplete))
            }
            var out: GoldActual = ["outcome": .json(.object(o))]
            if let bytes { out["bytes"] = .bytes(bytes) }
            return out
        },
        "A17": GoldReproducer { ctx in
            let ds = ctx.makeDataStore()
            try ctx.inlineDocument().write(to: ds.currentDataFile)
            let data = ds.load()
            let outcome = GoldDotNet.obj([
                ("lastLoadFailed", .bool(ds.lastLoadFailed)), ("loadedNewerSchema", GoldDotNet.int(ds.loadedNewerSchema)),
                ("schemaVersionAfterLoad", GoldDotNet.int(data.schemaVersion)),
                ("taskSpawned", GoldDotNet.bool(data.tasks.first?.recurrenceSpawned)),
                ("subtaskSpawned", GoldDotNet.bool(data.tasks.first?.subtasks.first?.recurrenceSpawned)),
                ("procedureSpawned", GoldDotNet.bool(data.procedures.first?.recurrenceSpawned)),
            ])
            return ["outcome": .json(outcome), "bytes": .bytes(try ds.serializeForSave(data))]
        },
        "A18": GoldReproducer { ctx in
            var ser: [JSONValue] = []
            for n in 25...32 {
                let ok = (try? serialize(GoldKitchenSink.withTasks([chain(n)]), ctx)) != nil
                ser.append(GoldDotNet.obj([("n", GoldDotNet.int(n)), ("ok", .bool(ok))] +
                                          (ok ? [] : [("exception", GoldDotNet.frameworkException)])))
            }
            var de: [JSONValue] = []
            let docs = (ctx.inline("documents")?.arrayValue ?? []).compactMap(\.stringValue)
            for (i, doc) in docs.enumerated() {
                var ok = false
                if let root = try? JSONParser.parse(Data(doc.utf8)),
                   (try? ModelCodec.decodeAppData(root, context: ctx.decodeContext)) != nil { ok = true }
                de.append(GoldDotNet.obj([("depth", GoldDotNet.int(62 + i)), ("ok", .bool(ok))] +
                                         (ok ? [] : [("exception", GoldDotNet.frameworkException)])))
            }
            return ["result": .json(GoldDotNet.obj([("serialize", .array(ser)), ("deserialize", .array(de))]))]
        },
        "A19": GoldReproducer { ctx in
            let ds = ctx.makeDataStore()
            try inputFile(ctx).write(to: ds.currentDataFile)
            let model = ds.load()
            let failed = ds.lastLoadFailed
            let threw = (try? ds.loadFrom(ds.currentDataFile)) == nil
            return ["outcome": .json(GoldDotNet.obj([("lastLoadFailed", .bool(failed)), ("loadFromThrows", .bool(threw))])),
                    "bytes": .bytes(try ds.serializeForSave(model))]
        },
        "A20": GoldReproducer { ctx in
            let ds = ctx.makeDataStore()
            try inputFile(ctx).write(to: ds.currentDataFile)
            _ = ds.load()
            return ["outcome": .json(GoldDotNet.obj([("lastLoadFailed", .bool(ds.lastLoadFailed))]))]
        },
        "W19": GoldReproducer { ctx in
            let ds = ctx.makeDataStore()
            try golden(ctx, role: "aaenc1").write(to: ds.currentDataFile)
            _ = ds.load()
            var detected = false
            if case .windowsEncrypted? = ds.lastLoadError { detected = true }
            return ["outcome": .json(GoldDotNet.obj([("lastLoadFailed", .bool(ds.lastLoadFailed)),
                                                     ("detectedWindowsEncryption", .bool(detected))]))]
        },
        "A21": GoldReproducer { ctx in try inlineLoadSave(ctx) },
        "A22.1": GoldReproducer { ctx in
            let shared = Container(id: GoldG(103), richTextXaml: "shared")
            let a = TaskItem(id: GoldG(3), name: "a"); a.container = shared
            let b = TaskItem(id: GoldG(5), name: "b"); b.container = shared
            return ["result": .bytes(try serialize(GoldKitchenSink.withTasks([a, b]), ctx))]
        },
        "A22.2": GoldReproducer { _ in ["result": .skip("a self-containing subtask cannot be built safely on the Mac (record-only)")] },
        "A22.3": GoldReproducer { ctx in try inlineLoadSave(ctx) },
        "A23": GoldReproducer { ctx in ["result": .bytes(try serialize(GoldKitchenSink.build(), ctx))] },
        "A24": GoldReproducer { ctx in
            let ks = GoldKitchenSink.build()
            ks.trash[0].deletedUtc = .utcNow(clock: GoldZoneClock(zone: ctx.zone))
            let ds = ctx.makeDataStore()
            let store = AppStore(dataStore: ds, data: ks, clock: GoldZoneClock(zone: ctx.zone))
            store.suspendSaving = true
            let index = Int(ctx.fixtureCase.id.split(separator: ".").last ?? "1") ?? 1
            let returned = trashStep(index, store)
            return ["returned": .json(GoldDotNet.obj([("returned", returned)])), "bytes": .bytes(try ds.serializeForSave(store.data))]
        },
        "A25": GoldReproducer(requires: .wPersist) { ctx in try paths(ctx, classifyAndImport: true) },
        "A25x": GoldReproducer(requires: .wPersist) { ctx in try paths(ctx, classifyAndImport: false) },
        "A25s": GoldReproducer { _ in [:] },          // divergent, asserted by W-PERSIST's own tests
        "A26": GoldReproducer(requires: .wPersist) { ctx in
            var rows: [JSONValue] = []
            for text in (ctx.inline("rows")?.arrayValue ?? []).compactMap(\.stringValue) {
                let url = ctx.folder.file("peek.json")
                try Data(text.utf8).write(to: url)
                let value = GoldDotNet.dateOrNull(BundleService.peekFileLastModified(url, key: nil), zone: ctx.zone)
                rows.append(GoldDotNet.obj([("input", .string(text)), ("bom", .bool(false)), ("read", value), ("peekFile", value)]))
            }
            if let first = (ctx.inline("rows")?.arrayValue ?? []).first?.stringValue {
                let url = ctx.folder.file("peek-bom.json")
                try (Data([0xEF, 0xBB, 0xBF]) + Data(first.utf8)).write(to: url)
                rows.append(GoldDotNet.obj([("input", .string(first)), ("bom", .bool(true)), ("read", .null),
                                            ("peekFile", GoldDotNet.dateOrNull(BundleService.peekFileLastModified(url, key: nil), zone: ctx.zone))]))
            }
            return ["result": .json(.array(rows))]
        },
    ])
}

@MainActor
@Suite("WinFixtures — data.json (DATA-315)", .tags(.goldWinFixtures),
       .enabled(if: GoldFixtureIndex.winfixtures.available, GoldFixtureIndex.absentMessage))
struct GoldJSONGoldenTests {
    @Test("GF.5.a case", arguments: GoldFixtureIndex.winfixtures.cases(family: "json"))
    func jsonCase(_ c: GoldFixtureCase) async {
        await GoldCaseRunner.run(c, index: .winfixtures, table: GoldJSONFamily.table)
    }
}
