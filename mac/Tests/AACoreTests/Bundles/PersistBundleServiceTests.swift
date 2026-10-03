// TV: 01 §7.7 (bundles), DATA-041…047, DATA-049, §3.9 peeks, §4.4/4.5 layout, §6.6/6.7 (Finder metadata, traversal),
//     D-3 (validate first), D-13 (destination check with a separator), DATA-179 (external lock released on import).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite("W-PERSIST bundle service", .serialized)
struct PersistBundleServiceTests {
    private let stamp = NetDateTime(parsing: "2026-09-29T11:15:29.9876543+03:00")!

    /// A data folder with data.json (one equipment "Pump", stamped) and the given attachments.
    private func folder(files: [String: String]) throws -> StoreFactory.Made {
        let made = StoreFactory.make()
        let ds = made.dataStore
        try ds.persistWriteReplacing(try persistDataJSON(ds, name: "Pump", stamp: stamp), to: ds.defaultDataFile)
        try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        for (n, text) in files { try Data(text.utf8).write(to: ds.filesFolder.appending(path: n)) }
        return made
    }

    private func zipURL(_ name: String = "b.zip") -> (TempFolder, URL) {
        let t = TempFolder("persist-zip")
        return (t, t.file(name))
    }

    // MARK: Export (§7.7 rows 1–4)

    @Test("Export with attachments: data.json, source.json, files/…; DataOnly false; identity; stamp")
    func exportWithAttachments() async throws {
        let made = try folder(files: ["ab12_x.pdf": "0123456789"])
        made.dataStore.settings.setAppIdentity("Vessel-Alpha")
        let (t, url) = zipURL(); _ = t
        try await BundleService.exportFolderToZip(made.dataStore, to: url, includeAttachments: true)
        #expect(Set(try PersistZip.names(url)) == ["data.json", "source.json", "files/ab12_x.pdf"])
        let src = try #require(BundleService.peekBundleSource(url))
        #expect(src.dataOnly == false)
        #expect(src.identity == "Vessel-Alpha")
        #expect(src.machine == BundleService.machineName())
        #expect(src.lastModified == stamp)
        #expect(src.writtenUtc.kind == .utc)
        #expect(try PersistZip.entry(url, "files/ab12_x.pdf") == Data("0123456789".utf8))
        let srcText = String(decoding: try #require(try PersistZip.entry(url, "source.json")), as: UTF8.self)
        #expect(srcText.hasPrefix(#"{"Identity":"Vessel-Alpha","Machine":"#))
        #expect(srcText.contains(#""LastModified":"2026-09-29T11:15:29.9876543+03:00","DataOnly":false}"#))
    }

    @Test("Export text only: no files/ entry and DataOnly true")
    func exportTextOnly() async throws {
        let made = try folder(files: ["ab12_x.pdf": "0123456789"])
        let (t, url) = zipURL(); _ = t
        try await BundleService.exportFolderToZip(made.dataStore, to: url, includeAttachments: false)
        #expect(Set(try PersistZip.names(url)) == ["data.json", "source.json"])
        #expect(BundleService.peekBundleSource(url)?.dataOnly == true)
    }

    @Test("Export with an empty files/ writes a bare files/ directory entry")
    func exportEmptyFiles() async throws {
        let made = try folder(files: [:])
        let (t, url) = zipURL(); _ = t
        try await BundleService.exportFolderToZip(made.dataStore, to: url, includeAttachments: true)
        #expect(Set(try PersistZip.names(url)) == ["data.json", "source.json", "files/"])
    }

    @Test("Finder metadata is never bundled; sub-folders are copied recursively")
    func exportSkipsFinderMetadata() async throws {
        let made = try folder(files: ["a.pdf": "a", ".DS_Store": "junk", "._a.pdf": "apple double"])
        try FileManager.default.createDirectory(at: made.dataStore.filesFolder.appending(path: "sub"), withIntermediateDirectories: true)
        try Data("s".utf8).write(to: made.dataStore.filesFolder.appending(path: "sub/s.txt"))
        let (t, url) = zipURL(); _ = t
        try await BundleService.exportFolderToZip(made.dataStore, to: url, includeAttachments: true)
        #expect(Set(try PersistZip.names(url)) == ["data.json", "source.json", "files/a.pdf", "files/sub/s.txt"])
    }

    @Test("Destination inside the AppFolder is refused; a sibling folder is not (D-13)")
    func exportDestination() async throws {
        let made = try folder(files: [:])
        let ds = made.dataStore
        await #expect(throws: PersistBundleError.destinationInsideAppFolder) {
            try await BundleService.exportFolderToZip(ds, to: ds.appFolder.appending(path: "x.zip"), includeAttachments: true)
        }
        #expect(PersistBundleError.destinationInsideAppFolder.localizedDescription == "Choose a destination outside the AA data folder.")
        let sibling = URL(fileURLWithPath: ds.appFolder.path + "2", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sibling) }
        try await BundleService.exportFolderToZip(ds, to: sibling.appending(path: "x.zip"), includeAttachments: true)
        #expect(FileManager.default.fileExists(atPath: sibling.appending(path: "x.zip").path))
    }

    @Test("Export bundles the PLAINTEXT data file when local encryption is on (DATA-041)")
    func exportDecrypts() async throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        ds.settings.setEncryptLocalData(true)
        let json = try persistDataJSON(ds, name: "Secret pump", stamp: stamp)
        try ds.persistWriteReplacing(json, to: ds.defaultDataFile)
        #expect(LocalEncryption.classify(try Data(contentsOf: ds.defaultDataFile)) == .mac)
        let (t, url) = zipURL(); _ = t
        try await BundleService.exportFolderToZip(ds, to: url, includeAttachments: true)
        #expect(try PersistZip.entry(url, "data.json") == json)
        #expect(BundleService.peekBundleSource(url)?.lastModified == stamp)
    }

    @Test("Default export name aa-data-{yyyyMMdd-HHmm}.zip and the shared default")
    func names() {
        let now = NetDateTime(year: 2026, month: 10, day: 2, hour: 7, minute: 5, second: 59, kind: .local)
        #expect(BundleService.exportDefaultName(now) == "aa-data-20261002-0705.zip")
        #expect(BundleService.sharedDefaultName == "aa-shared.zip")
        #expect(!BundleService.machineName().isEmpty)
    }

    // MARK: IsDataOnlyBundle truth table (§7.7)

    @Test("IsDataOnlyBundle truth table")
    func dataOnlyTable() throws {
        let t = TempFolder("persist-dataonly")
        func check(source: String?, files: [String]?) throws -> Bool {
            let staging = t.file(UUID().uuidString)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            if let source { try Data(source.utf8).write(to: staging.appending(path: "source.json")) }
            if let files {
                try FileManager.default.createDirectory(at: staging.appending(path: "files"), withIntermediateDirectories: true)
                for f in files { try Data("x".utf8).write(to: staging.appending(path: "files/\(f)")) }
            }
            return PersistBundleIO.isDataOnlyBundle(staging: staging, filesSrc: staging.appending(path: "files"))
        }
        #expect(try check(source: #"{"DataOnly":true}"#, files: ["a.pdf"]) == true)
        #expect(try check(source: nil, files: nil) == true)
        #expect(try check(source: #"{"DataOnly":false}"#, files: nil) == true)
        #expect(try check(source: nil, files: []) == false)
        #expect(try check(source: #"{"DataOnly":false}"#, files: ["a.pdf"]) == false)
        #expect(try check(source: "{not json", files: ["a.pdf"]) == false)
    }

    // MARK: Smart import (§7.7)

    private func bundle(_ ds: DataStore, files: [String: String]?, source: String? = nil, name: String = "Imported") throws -> (TempFolder, URL) {
        let (t, url) = zipURL()
        var entries: [(String, Data?)] = [("data.json", try persistDataJSON(ds, name: name, stamp: stamp))]
        if let source { entries.append(("source.json", Data(source.utf8))) }
        if let files {
            if files.isEmpty { entries.append(("files/", nil)) }
            for (n, v) in files.sorted(by: { $0.key < $1.key }) { entries.append(("files/\(n)", Data(v.utf8))) }
        }
        try PersistZip.make(url, entries)
        return (t, url)
    }

    private let ten = "0123456789", five = "01234", eleven = "0123456789A"

    @Test("Smart import matrix: match → DataOnly; changes → copy + sweep; no files/ → nothing deleted")
    func smartImportMatrix() throws {
        typealias Row = (bundle: [String: String]?, kind: ImportKind, after: [String: Int])
        let rows: [Row] = [
            (["a.pdf": ten, "b.pdf": five], .dataOnly, ["a.pdf": 10, "b.pdf": 5]),
            (["A.PDF": ten, "b.pdf": five], .dataOnly, ["a.pdf": 10, "b.pdf": 5]),
            (["a.pdf": eleven, "b.pdf": five], .withAttachments, ["a.pdf": 11, "b.pdf": 5]),
            (["a.pdf": ten], .withAttachments, ["a.pdf": 10]),
            ([:], .withAttachments, [:]),
            (nil, .dataOnly, ["a.pdf": 10, "b.pdf": 5]),
        ]
        for r in rows {
            let made = try folder(files: ["a.pdf": ten, "b.pdf": five])
            let ds = made.dataStore
            let (t, url) = try bundle(ds, files: r.bundle); _ = t
            let kind = try BundleService.importBundleSmart(ds, from: url)
            #expect(kind == r.kind, "bundle \(String(describing: r.bundle))")
            var listing = persistListing(ds.filesFolder)
            listing = Dictionary(uniqueKeysWithValues: listing.map { (NetText.toLowerInvariant($0.key), $0.value) })
            #expect(listing == r.after, "bundle \(String(describing: r.bundle))")
            let loaded = ds.load()
            #expect(loaded.equipment.first?.name == "Imported")
            #expect(ds.currentDataFile.standardizedFileURL == ds.defaultDataFile.standardizedFileURL)
        }
    }

    @Test("A DataOnly source.json never sweeps even with an empty files/ (DATA-044)")
    func dataOnlyFlagNeverSweeps() throws {
        let made = try folder(files: ["a.pdf": ten])
        let (t, url) = try bundle(made.dataStore, files: [:], source: #"{"Identity":"x","DataOnly":true}"#); _ = t
        #expect(try BundleService.importBundleSmart(made.dataStore, from: url) == .dataOnly)
        #expect(persistListing(made.dataStore.filesFolder) == ["a.pdf": 10])
    }

    @Test("Shared import: data-only → no deletion; {a.pdf} only → b deleted (DATA-058)")
    func sharedImport() throws {
        let made = try folder(files: ["a.pdf": ten, "b.pdf": five])
        let (t1, dataOnly) = try bundle(made.dataStore, files: nil); _ = t1
        try BundleService.importSharedBundle(made.dataStore, from: dataOnly)
        #expect(persistListing(made.dataStore.filesFolder) == ["a.pdf": 10, "b.pdf": 5])
        let (t2, onlyA) = try bundle(made.dataStore, files: ["a.pdf": eleven]); _ = t2
        try BundleService.importSharedBundle(made.dataStore, from: onlyA)
        #expect(persistListing(made.dataStore.filesFolder) == ["a.pdf": 11])
    }

    @Test("Finder metadata is never counted by AttachmentsMatch and never swept")
    func finderMetadataNotSwept() throws {
        let made = try folder(files: ["a.pdf": ten, ".DS_Store": "junk"])
        let (t, url) = try bundle(made.dataStore, files: ["a.pdf": ten]); _ = t
        #expect(try BundleService.importBundleSmart(made.dataStore, from: url) == .dataOnly)
        let (t2, url2) = try bundle(made.dataStore, files: ["c.pdf": five]); _ = t2
        #expect(try BundleService.importBundleSmart(made.dataStore, from: url2) == .withAttachments)
        #expect(persistListing(made.dataStore.filesFolder) == ["c.pdf": 5, ".DS_Store": 4])
    }

    @Test("A bundle without data.json (or with AA/data.json nested) is refused; local folder untouched")
    func noDataJSON() throws {
        let made = try folder(files: ["a.pdf": ten])
        let before = try Data(contentsOf: made.dataStore.defaultDataFile)
        let (t, url) = zipURL(); _ = t
        try PersistZip.make(url, [("AA/data.json", Data("{}".utf8)), ("files/z.pdf", Data("z".utf8))])
        #expect(throws: PersistBundleError.noDataJSON) { try BundleService.importBundleSmart(made.dataStore, from: url) }
        #expect(throws: PersistBundleError.sharedNoDataJSON) { try BundleService.importSharedBundle(made.dataStore, from: url) }
        #expect(PersistBundleError.noDataJSON.localizedDescription == "The bundle has no data.json.")
        #expect(PersistBundleError.sharedNoDataJSON.localizedDescription == "The shared save bundle has no data.json.")
        #expect(try Data(contentsOf: made.dataStore.defaultDataFile) == before)
        #expect(persistListing(made.dataStore.filesFolder) == ["a.pdf": 10])
    }

    @Test("D-3: invalid data.json is rejected before files/ or the data file are touched")
    func invalidJSONRejected() throws {
        let made = try folder(files: ["a.pdf": ten])
        let before = try Data(contentsOf: made.dataStore.defaultDataFile)
        let (t, url) = zipURL(); _ = t
        try PersistZip.make(url, [("data.json", Data("{\"Equipment\": [ {".utf8)), ("files/", nil)])
        #expect(throws: (any Error).self) { try BundleService.importBundleSmart(made.dataStore, from: url) }
        #expect(throws: (any Error).self) { try BundleService.importSharedBundle(made.dataStore, from: url) }
        #expect(try Data(contentsOf: made.dataStore.defaultDataFile) == before)
        #expect(persistListing(made.dataStore.filesFolder) == ["a.pdf": 10])
    }

    @Test("Entry ../evil.txt is rejected and nothing is written outside the staging folder")
    func traversalRejected() throws {
        let made = try folder(files: ["a.pdf": ten])
        let (t, url) = zipURL(); _ = t
        try PersistZip.make(url, [("data.json", try persistDataJSON(made.dataStore, name: "x", stamp: stamp)),
                                  ("../evil.txt", Data("evil".utf8))])
        let tmpRoot = BundleService.tempRoot
        #expect(throws: (any Error).self) { try BundleService.importBundleSmart(made.dataStore, from: url) }
        #expect(!FileManager.default.fileExists(atPath: tmpRoot.appending(path: "evil.txt").path))
        let staging = (try? FileManager.default.contentsOfDirectory(atPath: tmpRoot.path))?.filter { $0.hasPrefix("AA_import_") } ?? []
        #expect(staging.isEmpty)
        #expect(made.dataStore.load().equipment.first?.name == "Pump")
    }

    @Test("Export → import round trip keeps the data and every attachment byte")
    func roundTrip() async throws {
        let a = try folder(files: ["3f25_manual.pdf": "PDF", "aa11_photo.jpg": "JPG"])
        let (t, url) = zipURL(); _ = t
        try await BundleService.exportFolderToZip(a.dataStore, to: url, includeAttachments: true)
        let b = StoreFactory.make()
        #expect(try BundleService.importBundleSmart(b.dataStore, from: url) == .withAttachments)
        #expect(persistListing(b.dataStore.filesFolder) == ["3f25_manual.pdf": 3, "aa11_photo.jpg": 3])
        let loaded = b.dataStore.load()
        #expect(loaded.equipment.first?.name == "Pump")
        #expect(loaded.lastModified == stamp)
    }

    @Test("Bundle import migrates another workstation's absolute files\\ paths (DATA-065)")
    func importMigratesLegacyPaths() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let d = AppData()
        let e = Equipment(name: "E")
        e.container.files = [FileItem(name: "m", path: #"C:\Users\bob\AppData\Local\AA\files\zz_missing.pdf"#)]
        d.equipment = [e]
        let json = try JSONWriter.data(ModelCodec.encodeAppData(d))
        let (t, url) = zipURL(); _ = t
        try PersistZip.make(url, [("data.json", json)])
        _ = try BundleService.importBundleSmart(ds, from: url)
        #expect(ds.load().equipment[0].container.files[0].path == "files/zz_missing.pdf")
    }

    // MARK: Peeks (§3.9)

    @Test("Peeks read single entries and return nil on any failure")
    func peeks() async throws {
        let made = try folder(files: [:])
        let ds = made.dataStore
        let (t, url) = zipURL(); _ = t
        try await BundleService.exportFolderToZip(ds, to: url, includeAttachments: true)
        #expect(BundleService.peekZipLastModified(url) == stamp)
        #expect(BundleService.peekFileLastModified(ds.defaultDataFile, key: nil) == stamp)
        #expect(BundleService.peekZipData(url, dataStore: ds)?.equipment.first?.name == "Pump")
        let garbage = t.file("garbage.zip")
        try Data("not a zip".utf8).write(to: garbage)
        #expect(BundleService.peekZipLastModified(garbage) == nil)
        #expect(BundleService.peekBundleSource(garbage) == nil)
        #expect(BundleService.peekZipData(garbage, dataStore: ds) == nil)
        #expect(BundleService.peekZipLastModified(t.file("missing.zip")) == nil)
        let nullStamp = t.file("null.zip")
        try PersistZip.make(nullStamp, [("data.json", Data(#"{"LastModified":null}"#.utf8))])
        #expect(BundleService.peekZipLastModified(nullStamp) == nil)
        let caseVariant = t.file("case.zip")
        try PersistZip.make(caseVariant, [("Data.json", Data(#"{"LastModified":"2026-01-01T00:00:00"}"#.utf8))])
        #expect(BundleService.peekZipLastModified(caseVariant) == nil)
        let bom = t.file("bom.zip")
        try PersistZip.make(bom, [("data.json", Data([0xEF, 0xBB, 0xBF]) + Data(#"{"lastmodified":"x","LastModified":"2026-01-01T08:00:00Z"}"#.utf8))])
        #expect(BundleService.peekZipLastModified(bom)?.kind == .utc)
    }

    // MARK: ApplySyncedData (DATA-049)

    @Test("ApplySyncedData writes the default file, migrates, persists the active file; never touches files/")
    func applySyncedData() throws {
        let made = try folder(files: ["keep.pdf": "k"])
        let ds = made.dataStore
        let d = AppData()
        let e = Equipment(name: "From phone")
        e.container.files = [FileItem(name: "m", path: "/var/mobile/AA/files/keep.pdf")]
        d.equipment = [e]
        let json = try JSONWriter.data(ModelCodec.encodeAppData(d))
        let applied = try ds.applySyncedData(json)
        #expect(applied.equipment.first?.name == "From phone")
        #expect(applied.equipment[0].container.files[0].path == "files/keep.pdf")
        #expect(ds.settings.values.currentDataFile == ds.defaultDataFile.standardizedFileURL.path)
        #expect(persistListing(ds.filesFolder) == ["keep.pdf": 1])
        #expect(ds.load().equipment.first?.name == "From phone")
        let before = try Data(contentsOf: ds.defaultDataFile)
        #expect(throws: (any Error).self) { _ = try ds.applySyncedData(Data("{ broken".utf8)) }
        #expect(try Data(contentsOf: ds.defaultDataFile) == before)
    }

    // MARK: Legacy import (DATA-047)

    @Test("Legacy full-wipe import keeps .aa.lock and the Google client secret, drops settings.json")
    func legacyImport() throws {
        let made = try folder(files: ["old.pdf": "o"])
        let ds = made.dataStore
        try Data("lock".utf8).write(to: ds.instanceLockFile)
        try Data("secret".utf8).write(to: ds.googleClientSecretFile)
        try Data("crash".utf8).write(to: ds.crashLogFile)
        let (t, url) = zipURL(); _ = t
        try PersistZip.make(url, [("data.json", try persistDataJSON(ds, name: "Legacy", stamp: stamp)),
                                  ("settings.json", Data(#"{"DarkMode":true}"#.utf8)),
                                  ("files/new.pdf", Data("n".utf8))])
        try BundleService.importFolderFromZipLegacy(ds, from: url)
        #expect(try Data(contentsOf: ds.instanceLockFile) == Data("lock".utf8))
        #expect(try Data(contentsOf: ds.googleClientSecretFile) == Data("secret".utf8))
        #expect(!FileManager.default.fileExists(atPath: ds.crashLogFile.path))
        #expect(persistListing(ds.filesFolder) == ["new.pdf": 1])
        #expect(ds.load().equipment.first?.name == "Legacy")
        let settings = try String(contentsOf: ds.settingsFile, encoding: .utf8)
        #expect(!settings.contains("DarkMode"))
        #expect(settings.contains("CurrentDataFile"))
    }

    @Test("A torn archive leaves the folder untouched (legacy import validates first)")
    func legacyTorn() throws {
        let made = try folder(files: ["old.pdf": "o"])
        let (t, url) = zipURL(); _ = t
        try Data("PK\u{3}\u{4} torn".utf8).write(to: url)
        #expect(throws: (any Error).self) { try BundleService.importFolderFromZipLegacy(made.dataStore, from: url) }
        #expect(persistListing(made.dataStore.filesFolder) == ["old.pdf": 1])
    }
}
