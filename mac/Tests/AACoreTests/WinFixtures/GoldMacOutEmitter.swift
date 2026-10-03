// The reverse direction (spec 01 GF.8.5, DATA-312): Mac-produced artefacts written to Fixtures/mac-out/ so the real
// C# can be shown to accept them (`WinFixtures check-mac` on macOS and Windows; `WinCapture load-check` for xaml/).
// The folder is committed, so a Windows machine needs no Mac. Content is synthetic (DATA-314); salts, IVs, GUIDs of
// new objects and "now" stamps are real Mac output and therefore change on every emission — check-mac never
// compares them with a golden, it asks the C# whether it loads, verifies or decrypts them.
//
// `AA_EMIT_MAC_OUT=1 swift test --filter GoldMacOutEmitter` (Scripts/fixtures.sh emit-mac-out) rewrites the folder.
// Without the switch the same emission runs into a temporary folder and is checked against the Mac's own reader
// (GoldMacOutTests), so the emitter cannot rot while nobody regenerates.
import AppKit
import Foundation
import Testing
@testable import AACore

@MainActor
enum GoldMacOut {
    struct Report {
        var written: [String] = []
        /// Sections not emitted and why (another owner's code is still a placeholder).
        var skipped: [String] = []
    }

    static let sections = ["json", "settings", "crypto", "bundles", "xaml"]

    /// Writes every section under `root` (stale files of a section are removed first).
    static func emit(to root: URL, wpfCapture: GoldFixtureIndex = .wpfCapture) async throws -> Report {
        var report = Report()
        let fm = FileManager.default
        for s in sections {
            let dir = root.appending(path: s, directoryHint: .isDirectory)
            if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        func write(_ rel: String, _ data: Data) throws {
            let url = root.appending(path: rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            report.written.append(rel)
        }
        func writeJSON(_ rel: String, _ v: JSONValue) throws {
            try write(rel, Data((try JSONWriter.string(v, options: JSONWriteOptions(indented: true)) + "\n").utf8))
        }

        try emitJSON(write)
        try emitSettings(write, writeJSON)
        try emitCrypto(writeJSON)
        if ContractStatus.isImplemented(.wPersist) {
            try await emitBundles(write, writeJSON)
        } else {
            report.skipped.append("bundles/: needs W-PERSIST's BundleService (ContractStatus.wPersist not flipped)")
        }
        if ContractStatus.isImplemented(.wRich) {
            // A local list: `write` mutates `report` too, so passing `&report.skipped` is an exclusivity conflict.
            var xamlSkipped: [String] = []
            try emitXaml(write, wpfCapture: wpfCapture, skipped: &xamlSkipped)
            report.skipped += xamlSkipped
        } else {
            report.skipped.append("xaml/: needs W-RICH's XamlReader/XamlWriter (ContractStatus.wRich not flipped)")
        }
        try writeJSON("INDEX.json", GoldDotNet.obj([
            ("emittedBy", .string("GoldMacOutEmitter (mac/Tests/AACoreTests/WinFixtures/GoldMacOutEmitter.swift)")),
            ("checkedBy", .string("WinFixtures check-mac (json, settings, crypto, bundles); WinCapture load-check (xaml)")),
            ("files", GoldDotNet.strings(report.written.sorted { Ordinal.compare($0, $1) == .orderedAscending })),
            ("skipped", GoldDotNet.strings(report.skipped)),
        ]))
        return report
    }

    /// A scratch data folder with an in-memory Keychain and the Athens zone (the fixture default).
    static func dataStore(_ folder: TempFolder, clock: AppClock? = nil) -> DataStore {
        let ds = DataStore(appFolder: folder.url, secrets: InMemorySecretStore(),
                           clock: clock ?? GoldZoneClock(zone: TimeZone(identifier: "Europe/Athens")!))
        ds.loadSettings()
        return ds
    }

    // MARK: json/

    /// The deepest subtask chain the Mac writer accepts (A18 measures the Windows limit; n = 28 per 01 §7.4).
    static func maxChainDepth(_ ds: DataStore) -> Int {
        var best = 0
        for n in 20...40 where (try? ds.serializeForSave(GoldKitchenSink.withTasks([GoldJSONFamily.chain(n)]))) != nil { best = n }
        return best
    }

    /// The Mac-created database: Mac "now" stamps, a Mac-sanitised attachment name, a chain at the maximum depth.
    static func macCreated(_ ds: DataStore, clock: AppClock) -> AppData {
        let d = GoldKitchenSink.defaults()
        let t = TaskItem(name: "Created on the Mac")
        t.deadline = clock.now()
        t.rangeStart = clock.now()
        let original = "Q3: survey/report?.pdf"
        let safe = WindowsFileName.sanitize(original, fallback: "attachment")
        let fileID = UUID()
        t.container.files = [FileItem(id: fileID, name: safe, path: "files/\(fileID.netString.replacingOccurrences(of: "-", with: ""))_\(safe)",
                                      kind: .document, added: clock.now())]
        let depth = maxChainDepth(ds)
        d.tasks.append(t)
        if depth > 0 { d.tasks.append(GoldJSONFamily.chain(depth)) }
        return d
    }

    static func emitJSON(_ write: (String, Data) throws -> Void) throws {
        let folder = TempFolder("gold-macout-json")
        let clock = GoldZoneClock(zone: TimeZone(identifier: "Europe/Athens")!)
        let ds = dataStore(folder, clock: clock)
        try write("json/A02.kitchen-sink.json", try ds.serializeForSave(GoldKitchenSink.build()))
        try write("json/A04.defaults.json", try ds.serializeForSave(GoldKitchenSink.defaults()))
        for (name, input) in [("A05.legacy-shapes", "A05.input.json"), ("A10.unknown-members", "A10.input.json")] {
            let src = GoldPaths.winfixturesInputs.appending(path: input)
            let copy = folder.file(input)
            try Data(contentsOf: src).write(to: copy)
            try write("json/\(name).json", try ds.serializeForSave(try ds.loadFrom(copy)))
        }
        try write("json/mac-created.json", try ds.serializeForSave(macCreated(ds, clock: clock)))
    }

    // MARK: settings/

    /// Each settings file is written by the Mac's key-level merge; `.expect.json` holds the state check-mac must
    /// see after `LoadSettings()` (FamilyB.Dump keys). No Mac paths: they do not exist on Windows.
    static func emitSettings(_ write: (String, Data) throws -> Void, _ writeJSON: (String, JSONValue) throws -> Void) throws {
        let cases: [(String, (DataStore) throws -> Void, [(String, JSONValue)])] = [
            ("dark-mode", { $0.settings.setDarkMode(true) },
             [("DarkMode", .bool(true)), ("HasPassword", .bool(false))]),
            ("all-flags", { ds in
                ds.settings.setSyncOnSave(true); ds.settings.setTextOnlyExport(true); ds.settings.setEncryptLocalData(false)
                ds.settings.setDarkMode(false); ds.settings.setAppIdentity("  Vessel-Mac  ")
             }, [("SyncOnSave", .bool(true)), ("TextOnlyExport", .bool(true)), ("EncryptLocalData", .bool(false)),
                 ("DarkMode", .bool(false)), ("AppIdentity", .string("Vessel-Mac"))]),
            ("password", { ds in try PasswordService(settings: ds.settings).setPassword("correct horse", current: nil) },
             [("HasPassword", .bool(true)), ("IsUnlocked", .bool(false))]),
            ("folders", { ds in
                ds.settings.setGoogleDriveFolder("G:\\My Drive\\AA"); ds.settings.setFolderBuilderBase("D:\\Ship Files")
             }, [("GoogleDriveFolder", .string("G:\\My Drive\\AA")), ("FolderBuilderBase", .string("D:\\Ship Files"))]),
        ]
        for (name, act, expect) in cases {
            let folder = TempFolder("gold-macout-settings")
            let ds = dataStore(folder)
            try act(ds)
            try write("settings/\(name).json", try Data(contentsOf: ds.settingsFile))
            try writeJSON("settings/\(name).expect.json", GoldDotNet.obj(expect))
        }
    }

    // MARK: crypto/

    static let lockRows: [(name: String, password: String, wrong: String)] = [
        ("ascii", "correct horse", "Correct horse"),
        ("greek", "Ωμέγα-λέξη", "Ωμεγα-λεξη"),
        ("four-chars", "abcd", "abc"),
        ("emoji-free-symbols", "p@ss w0rd!#%", "p@ss w0rd!#"),
    ]
    static let blobRows: [(name: String, password: String, plaintext: String)] = [
        ("empty", "correct horse", ""),
        ("section", "correct horse", "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"><Paragraph><Run>Secret</Run></Paragraph></Section>"),
        ("greek", "Ωμέγα-λέξη", "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"><Paragraph><Run>Κλειδί πυροσβεστικής</Run></Paragraph></Section>"),
    ]

    static func emitCrypto(_ writeJSON: (String, JSONValue) throws -> Void) throws {
        var locks: [JSONValue] = []
        let service = ItemLockService()
        for row in lockRows {
            let item = TaskItem(name: row.name)
            service.protect(item, password: row.password, hint: nil)
            locks.append(GoldDotNet.obj([("name", .string(row.name)), ("password", .string(row.password)),
                                         ("wrong", .string(row.wrong)), ("lockHash", GoldDotNet.str(item.lockHash)),
                                         ("lockSalt", GoldDotNet.str(item.lockSalt))]))
        }
        try writeJSON("crypto/locks.json", .array(locks))
        var blobs: [JSONValue] = []
        for row in blobRows {
            let folder = TempFolder("gold-macout-crypto")
            let ds = dataStore(folder)
            try PasswordService(settings: ds.settings).setPassword(row.password, current: nil)
            let v = ds.settings.values
            guard let hash = v.passwordHash, let salt = v.passwordSalt else { throw GoldReproError.unexpected("setPassword wrote no hash") }
            let blob = LegacyBodyCrypto.encrypt(row.plaintext, password: row.password, saltBase64: salt)
            blobs.append(GoldDotNet.obj([("name", .string(row.name)), ("password", .string(row.password)),
                                         ("passwordHash", .string(hash)), ("passwordSalt", .string(salt)),
                                         ("blob", .string(blob)), ("plaintext", .string(row.plaintext))]))
        }
        try writeJSON("crypto/blobs.json", .array(blobs))
    }

    // MARK: bundles/ (W-PERSIST)

    static func emitBundles(_ write: (String, Data) throws -> Void, _ writeJSON: (String, JSONValue) throws -> Void) async throws {
        for (name, attachments) in [("text-only", false), ("with-attachments", true)] {
            let folder = TempFolder("gold-macout-bundle")
            let clock = GoldZoneClock(zone: TimeZone(identifier: "Europe/Athens")!)
            let ds = dataStore(folder, clock: clock)
            ds.settings.setAppIdentity("Vessel-Mac")
            let data = macCreated(ds, clock: clock)
            try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
            for task in data.tasks {
                for f in task.container.files {
                    // The on-disk name is the Mac's own (":" and "?" are legal on APFS); the bundle must not carry it.
                    let leaf = (f.path as NSString).lastPathComponent
                    try Data("Mac attachment \(f.name)".utf8).write(to: ds.filesFolder.appending(path: leaf))
                }
            }
            try Data("unsanitised".utf8).write(to: ds.filesFolder.appending(path: "Mac: notes?.txt"))
            try ds.serializeForSave(data).write(to: ds.defaultDataFile)
            // DATA-041 / D-13: an export into the data folder itself is refused, so the zip goes beside it.
            let outFolder = TempFolder("gold-macout-bundle-out")
            let out = outFolder.file("\(name).zip")
            try await BundleService.exportFolderToZip(ds, to: out, includeAttachments: attachments)
            try write("bundles/\(name).zip", try Data(contentsOf: out))
            try writeJSON("bundles/\(name).expect.json", GoldDotNet.obj([
                ("importKind", .string(attachments ? "WithAttachments" : "DataOnly")), ("hasLastModified", .bool(true)),
            ]))
        }
    }

    // MARK: xaml/ (W-RICH)

    /// Documents created on the Mac (05 GF.8.5 list): empty, plain, styled, link, sub/superscript, lists, table, lock.
    static func macDocuments() -> [(String, NSAttributedString)] {
        func para(_ s: String, _ attrs: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
            NSAttributedString(string: s, attributes: attrs)
        }
        let body = NSFont.systemFont(ofSize: 12)
        var docs: [(String, NSAttributedString)] = [("mac-empty", NSAttributedString())]
        docs.append(("mac-plain", para("Check the main engine oil level.\nSecond paragraph.", [.font: body])))
        let styled = NSMutableAttributedString(string: "Bold ", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        styled.append(para("italic ", [.font: NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)]))
        styled.append(para("underlined ", [.font: body, .underlineStyle: NSUnderlineStyle.single.rawValue]))
        styled.append(para("struck ", [.font: body, .strikethroughStyle: NSUnderlineStyle.single.rawValue]))
        styled.append(para("red on yellow", [.font: body, .foregroundColor: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
                                             .backgroundColor: NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)]))
        docs.append(("mac-styled", styled))
        let link = NSMutableAttributedString(string: "See ", attributes: [.font: body])
        link.append(para("the manual", [.font: body, .link: URL(string: "https://example.com/manual")!]))
        docs.append(("mac-link", link))
        let script = NSMutableAttributedString(string: "H", attributes: [.font: body])
        script.append(para("2", [.font: body, .superscript: -1]))
        script.append(para("O and x", [.font: body]))
        script.append(para("2", [.font: body, .superscript: 1]))
        docs.append(("mac-sub-superscript", script))
        for (name, format) in [("mac-bullets", NSTextList.MarkerFormat.disc), ("mac-numbers", NSTextList.MarkerFormat.decimal)] {
            let list = NSTextList(markerFormat: format, options: 0)
            let style = NSMutableParagraphStyle()
            style.textLists = [list]
            docs.append((name, para("First item\nSecond item\nThird item", [.font: body, .paragraphStyle: style])))
        }
        let table = NSTextTable()
        table.numberOfColumns = 2
        let cells = NSMutableAttributedString()
        for (row, values) in [["Pump", "Due"], ["Fire pump", "2026-10-31"]].enumerated() {
            for (col, value) in values.enumerated() {
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: col, columnSpan: 1)
                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                cells.append(para(value + "\n", [.font: body, .paragraphStyle: style]))
            }
        }
        docs.append(("mac-table", cells))
        let lock = NSMutableAttributedString(string: "Open text, ", attributes: [.font: body])
        lock.append(para("locked text", [.font: body, .aaLockSource: "inlineRun", .aaLocked: true]))
        docs.append(("mac-lock", lock))
        return docs
    }

    static func emitXaml(_ write: (String, Data) throws -> Void, wpfCapture: GoldFixtureIndex, skipped: inout [String]) throws {
        let ctx = XamlContext.containerEditor
        for (name, doc) in macDocuments() {
            let xaml = doc.length == 0 ? XamlWriter.emptyDocument()
                : XamlWriter.write(doc, metadata: RichTextMetadata(context: ctx), context: ctx)
            try write("xaml/\(name).xaml", Data(xaml.utf8))
        }
        // Every W capture after a Mac round trip (only the Mac-compared ones are Mac documents).
        guard wpfCapture.available else {
            skipped.append("xaml/W*: the WPF captures are absent (run WinCapture first), so no Mac round trip of them")
            return
        }
        for c in wpfCapture.cases(family: "xaml") {
            for ref in c.outputs where ref.macCompared && ref.role == "xaml" {
                let wpf = String(decoding: try wpfCapture.data(ref.file), as: UTF8.self)
                do {
                    try write("xaml/\(c.id).xaml", try GoldXamlFamily.roundTrip(wpf, context: GoldXamlFamily.context(for: c)))
                } catch {
                    skipped.append("xaml/\(c.id).xaml: \(error)")
                }
            }
        }
    }
}

/// The switch-gated emission into the committed folder.
@Suite("WinFixtures — Mac-out emitter (DATA-312)", .tags(.goldWinFixtures), .serialized)
struct GoldMacOutEmitter {
    @MainActor
    @Test("emit Fixtures/mac-out", .enabled(if: GoldEnv.emitMacOut && GoldPaths.isSourceTree,
                                            "set AA_EMIT_MAC_OUT=1 to rewrite Tests/AACoreTests/Fixtures/mac-out (Scripts/fixtures.sh emit-mac-out)"))
    func emit() async throws {
        let report = try await GoldMacOut.emit(to: GoldPaths.macOut)
        #expect(!report.written.isEmpty)
        for s in report.skipped { print("mac-out: skipped \(s)") }
    }
}

/// The emitter's output read back by the Mac itself (always runs, into a temporary folder).
@MainActor
@Suite("WinFixtures harness — Mac-out artefacts read back by the Mac (DATA-312)", .tags(.goldWinFixtures))
struct GoldMacOutTests {
    @Test("every emitted artefact loads, verifies or decrypts with the Mac's own code")
    func readBack() async throws {
        let folder = TempFolder("gold-macout")
        let report = try await GoldMacOut.emit(to: folder.url, wpfCapture: GoldFixtureIndex(root: folder.url.appending(path: "none")))
        let names = Set(report.written)
        for f in ["json/A02.kitchen-sink.json", "json/A04.defaults.json", "json/A05.legacy-shapes.json",
                  "json/A10.unknown-members.json", "json/mac-created.json", "crypto/locks.json", "crypto/blobs.json",
                  "settings/dark-mode.json", "settings/dark-mode.expect.json", "settings/password.json"] {
            #expect(names.contains(f), "\(f) not emitted")
        }
        #expect(ContractStatus.isImplemented(.wPersist) || report.skipped.contains { $0.hasPrefix("bundles/") })
        #expect(ContractStatus.isImplemented(.wRich) || report.skipped.contains { $0.hasPrefix("xaml/") })

        // json/: load + re-serialise reproduces the bytes (what check-mac asks of SerializeForSave).
        let scratch = TempFolder("gold-macout-read")
        let ds = GoldMacOut.dataStore(scratch)
        for f in names.filter({ $0.hasPrefix("json/") }) {
            let bytes = try Data(contentsOf: folder.url.appending(path: f))
            let copy = scratch.file("copy.json")
            try bytes.write(to: copy)
            #expect(try ds.serializeForSave(try ds.loadFrom(copy)) == bytes, "\(f) does not round-trip on the Mac")
        }
        let created = try ds.loadFrom(folder.url.appending(path: "json/mac-created.json"))
        let macTask = try #require(created.tasks.first { $0.name == "Created on the Mac" })
        #expect(macTask.deadline?.kind == .local)
        let file = try #require(macTask.container.files.first)
        #expect(file.name == "Q3_ survey_report_.pdf")
        #expect(!file.name.contains { WindowsFileName.invalidCharacters.contains($0) })
        #expect(created.tasks.contains { $0.name == "level 1" })
        #expect(GoldMacOut.maxChainDepth(ds) >= 25)

        // settings/: the expected state is what the Mac itself reads back.
        for f in names.filter({ $0.hasPrefix("settings/") && !$0.hasSuffix(".expect.json") }) {
            let s = TempFolder("gold-macout-settings-read")
            let sds = DataStore(appFolder: s.url, secrets: InMemorySecretStore(), clock: SystemClock())
            try Data(contentsOf: folder.url.appending(path: f)).write(to: sds.settingsFile)
            sds.loadSettings()
            let state = try #require(GoldSettingsFamily.dump(sds).objectValue)
            let expect = try #require(try JSONParser.parse(try Data(contentsOf: folder.url.appending(path: String(f.dropLast(5)) + ".expect.json"))).objectValue)
            for (k, v) in expect { #expect(state[k] == v, "\(f): \(k)") }
        }

        // crypto/: lock rows verify right / reject wrong; blobs decrypt to the plaintext under the stored salt.
        let locks = try #require(try JSONParser.parse(try Data(contentsOf: folder.url.appending(path: "crypto/locks.json"))).arrayValue)
        #expect(locks.count == GoldMacOut.lockRows.count)
        for row in locks.compactMap(\.objectValue) {
            let item = TaskItem(name: "x")
            item.lockHash = row["lockHash"]?.stringValue
            item.lockSalt = row["lockSalt"]?.stringValue
            let service = ItemLockService()
            #expect(await service.tryUnlock(item, password: row["password"]?.stringValue ?? ""))
            service.relockAll()
            #expect(!(await service.tryUnlock(item, password: row["wrong"]?.stringValue ?? "")))
        }
        let blobs = try #require(try JSONParser.parse(try Data(contentsOf: folder.url.appending(path: "crypto/blobs.json"))).arrayValue)
        for row in blobs.compactMap(\.objectValue) {
            let plain = LegacyBodyCrypto.decrypt(row["blob"]?.stringValue ?? "", password: row["password"]?.stringValue ?? "",
                                                 saltBase64: row["passwordSalt"]?.stringValue ?? "")
            #expect(plain == row["plaintext"]?.stringValue, "\(row["name"]?.stringValue ?? "?")")
        }
        #expect(names.contains("INDEX.json"))
    }
}
