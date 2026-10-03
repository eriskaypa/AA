// Family (b) `settings.json` — Swift reproductions of S01–S12 (spec 01 GF.5.b, DATA-316). The Windows setters
// write the whole Settings object; the Mac writes a key-level merge (01 DATA-182) and keeps the Gemini key in the
// Keychain (DECISIONS 12 Q-6), so the file bytes and the post-call state are a Windows record (`mac: false`). What the
// Mac MUST reproduce is reading: the state after loading the precondition file (`state.load`), the state after
// re-reading the Windows-written final file (`reload`), and the password truth table (`verify`).
import Foundation
import Testing
@testable import AACore

@MainActor
enum GoldSettingsFamily {
    /// The machine name the Mac writes into an unmasked input (any value matches `%%MACHINE%%`).
    static let machine = "GOLD-MACHINE"

    /// Turns a masked golden / input back into a file the Mac can read in this case's data folder.
    static func unmask(_ data: Data, _ ctx: GoldCaseContext) -> Data {
        var bytes = [UInt8](data)
        var bom: [UInt8] = []
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bom = [0xEF, 0xBB, 0xBF]; bytes.removeFirst(3) }
        let dir = String(JSONWriter.escape(ctx.dataFolder.path).dropFirst().dropLast())
        let text = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "%%DATADIRUPPER%%", with: NetText.toUpperInvariant(dir))
            .replacingOccurrences(of: "%%DATADIR%%", with: dir)
            .replacingOccurrences(of: "%%MACHINE%%", with: machine)
        return Data(bom + Array(text.utf8))
    }

    /// GF.4.7 state dump of the Mac after `loadSettings()`.
    static func dump(_ ds: DataStore) -> JSONValue {
        let v = ds.settings.values
        let shared = NetText.isBlank(v.sharedSaveFile) ? nil : v.sharedSaveFile
        return GoldDotNet.obj([
            ("CurrentDataFile", .string(ds.currentDataFile.path)),
            ("GoogleDriveFolder", GoldDotNet.str(v.googleDriveFolder)),
            ("SyncOnSave", .bool(v.syncOnSave)),
            ("TextOnlyExport", .bool(v.textOnlyExport)),
            ("DarkMode", .bool(v.darkMode)),
            ("EncryptLocalData", .bool(v.encryptLocalData)),
            ("GeminiApiKey", GoldDotNet.str(v.geminiApiKey)),
            ("AppIdentity", .string(ds.settings.appIdentity)),
            ("FolderBuilderBase", GoldDotNet.str(v.folderBuilderBase)),
            ("SharedSaveFile", GoldDotNet.str(shared)),
            ("HasPassword", .bool(PasswordService(settings: ds.settings).hasPassword)),
            ("IsUnlocked", .bool(false)),
        ])
    }

    /// Writes `file` as settings.json and dumps the state a fresh Mac launch reads from it.
    static func stateAfterLoading(_ file: Data, _ ctx: GoldCaseContext) throws -> JSONValue {
        let ds = DataStore(appFolder: ctx.dataFolder, secrets: InMemorySecretStore(), clock: GoldZoneClock(zone: ctx.zone))
        try FileManager.default.createDirectory(at: ctx.dataFolder, withIntermediateDirectories: true)
        try unmask(file, ctx).write(to: ds.settingsFile)
        ds.loadSettings()
        return dump(ds)
    }

    static let reproducer = GoldReproducer { ctx in
        var out: GoldActual = [:]
        let c = ctx.fixtureCase
        if c.output("reload") != nil {
            out["reload"] = .json(try stateAfterLoading(try GoldJSONFamily.golden(ctx, role: "settings"), ctx))
        }
        if c.output("state.load") != nil, let input = ctx.inlineString("file") {
            out["state.load"] = .json(try stateAfterLoading(try ctx.index.data(input), ctx))
        }
        if c.output("verify") != nil {
            let ds = DataStore(appFolder: ctx.dataFolder, secrets: InMemorySecretStore(), clock: GoldZoneClock(zone: ctx.zone))
            try FileManager.default.createDirectory(at: ctx.dataFolder, withIntermediateDirectories: true)
            try unmask(try GoldJSONFamily.golden(ctx, role: "settings"), ctx).write(to: ds.settingsFile)
            ds.loadSettings()
            let ps = PasswordService(settings: ds.settings)
            out["verify"] = .json(GoldDotNet.obj(["correct horse", "x", "redemption"].map { ($0, .bool(ps.verify($0))) }))
        }
        return out
    }

    static let table = GoldReproducerTable(entries: Dictionary(uniqueKeysWithValues:
        (1...12).map { (String(format: "S%02d", $0), reproducer) }))
}

@MainActor
@Suite("WinFixtures — settings.json (DATA-316)", .tags(.goldWinFixtures),
       .enabled(if: GoldFixtureIndex.winfixtures.available, GoldFixtureIndex.absentMessage))
struct GoldSettingsGoldenTests {
    @Test("GF.5.b case", arguments: GoldFixtureIndex.winfixtures.cases(family: "settings"))
    func settingsCase(_ c: GoldFixtureCase) async {
        await GoldCaseRunner.run(c, index: .winfixtures, table: GoldSettingsFamily.table)
    }
}

@MainActor
@Suite("WinFixtures harness — settings reproducer on a Windows-shaped file", .tags(.goldWinFixtures))
struct GoldSettingsReproducerTests {
    @Test("a Windows-written S02-shaped file reads back as the Windows state (01 §7.12)")
    func s02Shape() async throws {
        let r = GoldSyntheticRoot()
        // What Windows writes after the S02 setters (declaration order, compact), masked like the generator does.
        try r.write("settings/S02.settings.golden.json",
                    #"{"CurrentDataFile":"%%DATADIR%%/data.json","PasswordHash":"V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=","PasswordSalt":"AAECAwQFBgcICQoLDA0ODw==","GoogleDriveFolder":"/Users/u/My Drive","SyncOnSave":true,"DarkMode":true,"FolderBuilderBase":"/tmp/fb","SharedSaveFile":"/Volumes/share/aa-shared.zip","EncryptLocalData":false,"GeminiApiKey":"key-123","AppIdentity":"Vessel-Alpha","TextOnlyExport":true}"#)
        try r.write("settings/S02.reload.golden.json",
                    #"{"CurrentDataFile":"%%DATADIR%%/data.json","GoogleDriveFolder":"/Users/u/My Drive","SyncOnSave":true,"TextOnlyExport":true,"DarkMode":true,"EncryptLocalData":false,"GeminiApiKey":"key-123","AppIdentity":"Vessel-Alpha","FolderBuilderBase":"/tmp/fb","SharedSaveFile":"/Volumes/share/aa-shared.zip","HasPassword":true,"IsUnlocked":false}"#)
        let rec = #"{"id":"S02","family":"settings","title":"every setter","compare":"json-semantic","outputs":[{"role":"settings","file":"settings/S02.settings.golden.json","compare":"bytes-masked","mac":false},{"role":"reload","file":"settings/S02.reload.golden.json"}]}"#
        let index = try r.manifest([rec])
        let c = try #require(index.manifest?.cases.first)
        let ctx = GoldCaseContext(index: index, fixtureCase: c)
        let actual = try await GoldSettingsFamily.reproducer.run(ctx)
        let problems = GoldCaseRunner.compareAll(c, actual: actual, ctx: ctx).problems
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test("an undecodable PasswordSalt reads as the Windows catch branch (S05, 01 §7.12)")
    func s05CatchBranch() async throws {
        let r = GoldSyntheticRoot()
        try r.write("inputs/S05.input.json",
                    #"{"CurrentDataFile":"%%DATADIR%%/data.json","PasswordHash":"V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=","PasswordSalt":"%%%","DarkMode":true,"SyncOnSave":true,"FolderBuilderBase":"/tmp/fb","GeminiApiKey":"key-123","AppIdentity":"Vessel-Alpha"}"#)
        try r.write("settings/S05.state-load.golden.json",
                    #"{"CurrentDataFile":"%%DATADIR%%/data.json","GoogleDriveFolder":null,"SyncOnSave":false,"TextOnlyExport":false,"DarkMode":false,"EncryptLocalData":false,"GeminiApiKey":"key-123","AppIdentity":"%%MACHINE%%","FolderBuilderBase":"/tmp/fb","SharedSaveFile":null,"HasPassword":false,"IsUnlocked":false}"#)
        let rec = #"{"id":"S05","family":"settings","title":"catch branch","compare":"json-semantic","inputs":{"file":"inputs/S05.input.json"},"outputs":[{"role":"state.load","file":"settings/S05.state-load.golden.json"}]}"#
        let index = try r.manifest([rec])
        let c = try #require(index.manifest?.cases.first)
        let ctx = GoldCaseContext(index: index, fixtureCase: c)
        let actual = try await GoldSettingsFamily.reproducer.run(ctx)
        let problems = GoldCaseRunner.compareAll(c, actual: actual, ctx: ctx).problems
        #expect(problems.isEmpty, "\(problems)")
    }
}
