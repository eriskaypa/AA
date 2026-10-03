// TV: 01 §7.3 (local encryption detection, IsUnderAppFolder), App. A17 (schema), A19 (framing), A20 (DPAPI file),
//     01 §3.1–3.4, DATA-013, DATA-021–023, DATA-029 (atomic write), DATA-071–072, D-14 (Save a Copy As),
//     DECISIONS 01 Q-5 (adopt an external JSON), §MP.3.4 (write guard hooks), ARCHITECTURE.md §6.2.
import Foundation
import Testing
import CryptoKit
@testable import AACore

/// Records every guard call; `allow` decides `shouldWrite`.
private final class RecordingGuard: DataFileWriteGuard, @unchecked Sendable {
    private let lock = NSLock()
    private var _allow = true
    private var _events: [String] = []
    private var _lastWritten: Data?
    private var _lastLoaded: Data?
    var allow: Bool { get { lock.withLock { _allow } } set { lock.withLock { _allow = newValue } } }
    var events: [String] { lock.withLock { _events } }
    var lastWritten: Data? { lock.withLock { _lastWritten } }
    var lastLoaded: Data? { lock.withLock { _lastLoaded } }
    func shouldWrite(to url: URL) -> Bool { lock.withLock { _events.append("should:\(url.lastPathComponent)"); return _allow } }
    func didWrite(to url: URL, bytes: Data) { lock.withLock { _events.append("did:\(url.lastPathComponent)"); _lastWritten = bytes } }
    func didLoad(from url: URL, bytes: Data) { lock.withLock { _events.append("load:\(url.lastPathComponent)"); _lastLoaded = bytes } }
}

private let freshDB = Goldens.freshDB
private let athensClock = FixedClock(local: "2026-09-29T14:05:00", zone: TZ.athens)

@MainActor private func makeStore(_ folder: TempFolder, secrets: InMemorySecretStore = InMemorySecretStore()) -> DataStore {
    let ds = DataStore(appFolder: folder.url, secrets: secrets, clock: athensClock)
    ds.loadSettings()
    return ds
}

@Suite struct AtomicWriteTests {
    @Test func writesReplacesAndCleansUp() throws {
        let folder = TempFolder()
        let url = folder.file("sub/dir/target.json")
        try AtomicWrite.write(Data("one".utf8), to: url)                     // creates missing folders
        #expect(try String(contentsOf: url, encoding: .utf8) == "one")
        try AtomicWrite.write(Data("two-longer".utf8), to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "two-longer")
        try AtomicWrite.write(Data(), to: url)
        #expect(try Data(contentsOf: url).isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(leftovers == ["target.json"])
    }

    // 01 §6.4 temp name: "<path>.<32 lowercase hex>.tmp" in the same directory
    @Test func tempName() {
        let url = URL(fileURLWithPath: "/tmp/x/data.json")
        let t = AtomicWrite.tempURL(for: url)
        #expect(t.deletingLastPathComponent().path == "/tmp/x")
        let name = t.lastPathComponent
        #expect(name.hasPrefix("data.json.") && name.hasSuffix(".tmp") && name.count == "data.json.".count + 32 + 4)
        let hex = name.dropFirst("data.json.".count).dropLast(4)
        #expect(hex.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(AtomicWrite.tempURL(for: url) != t)
    }

    @Test func failsCleanlyWhenTheTargetIsADirectory() throws {
        let folder = TempFolder()
        try FileManager.default.createDirectory(at: folder.file("dir.json/inner"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try AtomicWrite.write(Data("x".utf8), to: folder.file("dir.json")) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path) == ["dir.json"])
    }

    // TV: 01 §7.14-6 — a concurrent reader never sees a partial file
    @Test func concurrentReaderNeverSeesATornFile() async throws {
        let folder = TempFolder()
        let url = folder.file("data-file.json")
        let a = Data(repeating: 0x61, count: 300_000), b = Data(repeating: 0x62, count: 200_000)
        try AtomicWrite.write(a, to: url)
        let writer = Task.detached {
            for i in 0..<40 { try AtomicWrite.write(i % 2 == 0 ? b : a, to: url) }
        }
        var reads = 0
        while !(writer.isCancelled) {
            if let d = try? Data(contentsOf: url) {
                #expect(d == a || d == b)
                reads += 1
            }
            if reads > 200 { break }
            await Task.yield()
        }
        try await writer.value
        #expect(reads > 0)
    }
}

@Suite struct LocalEncryptionTests {
    // TV: 01 §7.3 detection
    @Test func classification() {
        #expect(LocalEncryption.classify(Data([0x41, 0x41, 0x45, 0x4E, 0x43, 0x31, 0x0A, 0x01])) == .windowsDPAPI)
        #expect(LocalEncryption.classify(Data([0x41, 0x41, 0x45, 0x4E, 0x43, 0x4D, 0x31, 0x0A, 0x01])) == .mac)
        #expect(LocalEncryption.classify(Data([0xEF, 0xBB, 0xBF, 0x7B, 0x7D])) == .plain)
        #expect(LocalEncryption.classify(Data("AAENC".utf8)) == .plain)
        #expect(LocalEncryption.classify(Data()) == .plain)
        #expect(LocalEncryption.macMagic == Data([0x41, 0x41, 0x45, 0x4E, 0x43, 0x4D, 0x31, 0x0A]))
        #expect(LocalEncryption.windowsMagic == Data([0x41, 0x41, 0x45, 0x4E, 0x43, 0x31, 0x0A]))
    }

    // 01 §6.5 format: magic ‖ 12-byte nonce ‖ ciphertext ‖ 16-byte tag; AAD = magic
    @Test func macFormat() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data(freshDB.utf8)
        let blob = try LocalEncryption.encrypt(plain, key: key)
        #expect(blob.prefix(8) == LocalEncryption.macMagic)
        #expect(blob.count == 8 + 12 + plain.count + 16)
        #expect(try LocalEncryption.decrypt(blob, key: key) == plain)
        let box = try AES.GCM.SealedBox(combined: blob.dropFirst(8))
        #expect(throws: (any Error).self) { try AES.GCM.open(box, using: key) }   // the magic is authenticated
        #expect(try AES.GCM.open(box, using: key, authenticating: LocalEncryption.macMagic) == plain)
        #expect(throws: LocalEncryptionError.decryptFailed) { try LocalEncryption.decrypt(blob, key: SymmetricKey(size: .bits256)) }
        var tampered = [UInt8](blob); tampered[tampered.count - 1] ^= 1
        #expect(throws: LocalEncryptionError.decryptFailed) { try LocalEncryption.decrypt(Data(tampered), key: key) }
        #expect(throws: LocalEncryptionError.notMacEncrypted) { try LocalEncryption.decrypt(plain, key: key) }
        #expect(try LocalEncryption.encrypt(plain, key: key) != blob)                // fresh nonce every time
    }

    // DATA-215: the key lives under AA.LocalDataKey / v1; created once, never without `create`
    @Test func keyLifecycle() throws {
        let secrets = InMemorySecretStore()
        #expect(try LocalEncryption.key(secrets: secrets, create: false) == nil)
        let k = try #require(try LocalEncryption.key(secrets: secrets, create: true))
        let stored = try #require(try secrets.read(service: "AA.LocalDataKey", account: "v1"))
        #expect(stored.count == 32)
        #expect(k.withUnsafeBytes { Data($0) } == stored)
        let again = try #require(try LocalEncryption.key(secrets: secrets, create: false))
        #expect(again.withUnsafeBytes { Data($0) } == stored)
        secrets.failAll = true
        #expect(throws: (any Error).self) { try LocalEncryption.key(secrets: secrets, create: true) }
    }
}

@MainActor @Suite struct DataStoreTests {
    @Test func paths() {
        let folder = TempFolder()
        let ds = makeStore(folder)
        let root = folder.url.standardizedFileURL.path
        #expect(ds.filesFolder.path == root + "/files")
        #expect(ds.defaultDataFile.path == root + "/data.json")
        #expect(ds.settingsFile.path == root + "/settings.json")
        #expect(ds.googleClientSecretFile.lastPathComponent == "google_client_secret.json")
        #expect(ds.googleTokenFolder.lastPathComponent == "google-token")
        #expect(ds.crashLogFile.lastPathComponent == "crash.log")
        #expect(ds.flashBaselineFile.lastPathComponent == "qrsync-baseline.json")
        #expect(ds.instanceLockFile.lastPathComponent == ".aa.lock")
        #expect(ds.currentDataFile == ds.defaultDataFile)
        #expect(DataStore.currentSchemaVersion == 1)
    }

    // 01 §3.2: absent → empty, not a failure; folders created
    @Test func absentFileIsEmptyNotAFailure() {
        let folder = TempFolder()
        let ds = makeStore(folder)
        let data = ds.load()
        #expect(data.tasks.isEmpty && !ds.lastLoadFailed && ds.lastLoadError == nil)
        #expect(FileManager.default.fileExists(atPath: ds.filesFolder.path))
    }

    // TV: 01 App. A19.1–A19.9 (+ §7.3 BOM row)
    @Test(arguments: [
        ("bom", Data([0xEF, 0xBB, 0xBF]) + Data(freshDB.utf8), true),
        ("utf16", Data([0xFF, 0xFE]) + Data(freshDB.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }), false),
        ("trailing-ws", Data((freshDB + "\n  \r\n\t").utf8), true),
        ("comment", Data(("// c\n" + freshDB).utf8), false),
        ("trailing-comma", Data(#"{"Tasks":[],}"#.utf8), false),
        ("null", Data("null".utf8), true),
        ("array", Data("[]".utf8), false),
        ("empty", Data(), false),
        ("two-objects", Data((freshDB + "{}").utf8), false),
        ("bom-empty-object", Data([0xEF, 0xBB, 0xBF, 0x7B, 0x7D]), true),
    ] as [(String, Data, Bool)])
    func framing(_ label: String, _ bytes: Data, _ ok: Bool) throws {
        let folder = TempFolder()
        let ds = makeStore(folder)
        try folder.write("data.json", bytes)
        let data = ds.load()
        #expect(ds.lastLoadFailed == !ok, "\(label)")
        #expect(data.tasks.isEmpty)
        if ok {
            #expect(throws: Never.self) { _ = try ds.loadFrom(folder.file("data.json")) }
        } else {
            #expect(throws: DataLoadError.self) { _ = try ds.loadFrom(folder.file("data.json")) }
        }
    }

    // Invalid UTF-8 is replaced (U+FFFD), never a failure (01 §3.4)
    @Test func invalidUTF8IsReplaced() throws {
        let folder = TempFolder()
        let ds = makeStore(folder)
        var bytes = Data(#"{"Tasks":[{"Name":"a"#.utf8); bytes.append(0xFF); bytes.append(contentsOf: Data(#"b"}]}"#.utf8))
        try folder.write("data.json", bytes)
        let data = ds.load()
        #expect(!ds.lastLoadFailed)
        #expect(data.tasks.first?.name == "a\u{FFFD}b")
    }

    // A model type mismatch is a load failure (safe mode), with the error kept
    @Test func typeMismatchIsALoadFailure() throws {
        let folder = TempFolder()
        let ds = makeStore(folder)
        try folder.write("data.json", #"{"Tasks":[{"Status":"Done"}]}"#)
        _ = ds.load()
        #expect(ds.lastLoadFailed)
        guard case .model = ds.lastLoadError else { Issue.record("expected a model error"); return }
    }

    // TV: 01 App. A20 / §7.3 — a Windows DPAPI file → safe mode with the Mac wording
    @Test func windowsEncryptedFile() throws {
        let folder = TempFolder()
        let ds = makeStore(folder)
        try folder.write("data.json", LocalEncryption.windowsMagic + SecureRandom.bytes(64))
        let data = ds.load()
        #expect(ds.lastLoadFailed && data.tasks.isEmpty)
        guard case .windowsEncrypted = ds.lastLoadError else { Issue.record("expected .windowsEncrypted"); return }
        #expect(ds.lastLoadError?.errorDescription?.contains("Windows") == true)
        #expect(throws: DataLoadError.self) { _ = try ds.loadFrom(folder.file("data.json")) }
    }

    // TV: 01 §7.3 Mac format round trip: enable → AAENCM1 file; load decrypts; disable → plain JSON
    @Test func localEncryptionRoundTrip() async throws {
        let folder = TempFolder()
        let secrets = InMemorySecretStore()
        let ds = makeStore(folder, secrets: secrets)
        ds.settings.setEncryptLocalData(true)
        let data = AppData(); data.tasks = [TaskItem(name: "secret")]
        try ds.writeLocalDataFile(try ds.serializeForSave(data), to: ds.currentDataFile)
        let raw = try Data(contentsOf: ds.currentDataFile)
        #expect(raw.prefix(8) == LocalEncryption.macMagic)
        #expect(!String(decoding: raw, as: UTF8.self).contains("secret"))
        #expect(try secrets.read(service: "AA.LocalDataKey", account: "v1")?.count == 32)
        // A new session (fresh DataStore, same Keychain) reads it back.
        let ds2 = makeStore(folder, secrets: secrets)
        #expect(ds2.load().tasks.first?.name == "secret" && !ds2.lastLoadFailed)
        let ds3 = makeStore(folder, secrets: secrets)
        #expect(await ds3.loadInBackground().tasks.first?.name == "secret" && !ds3.lastLoadFailed)
        #expect(try ds2.loadFrom(ds2.currentDataFile).tasks.count == 1)
        #expect(try DataStore.readDataBytes(ds2.currentDataFile, key: ds2.localEncryptionKeyIfEnabled(for: ds2.currentDataFile)).first == 0x7B)
        // Disable → the next write is plain JSON, and the cache is dropped.
        ds2.settings.setEncryptLocalData(false)
        #expect(ds2.localEncryptionKeyIfEnabled(for: ds2.currentDataFile) == nil)
        try ds2.writeLocalDataFile(try ds2.serializeForSave(data), to: ds2.currentDataFile)
        #expect(try Data(contentsOf: ds2.currentDataFile).first == 0x7B)
    }

    // The key is read once per session (no Keychain call per save) and files outside AppFolder stay plaintext
    @Test func keyCacheAndScope() throws {
        let folder = TempFolder(), outside = TempFolder()
        let secrets = InMemorySecretStore()
        let ds = makeStore(folder, secrets: secrets)
        ds.settings.setEncryptLocalData(true)
        let k1 = try #require(ds.localEncryptionKeyIfEnabled(for: ds.currentDataFile))
        secrets.failAll = true                                              // the Keychain is no longer asked
        let k2 = try #require(ds.localEncryptionKeyIfEnabled(for: ds.currentDataFile))
        #expect(k1 == k2)
        #expect(ds.localEncryptionKeyIfEnabled(for: outside.file("x.json")) == nil)
        try ds.writeLocalDataFile(Data(freshDB.utf8), to: outside.file("x.json"))
        #expect(try outside.read("x.json") == Data(freshDB.utf8))
        // A denied Keychain with no cached key refuses to write plaintext into AppFolder.
        let ds2 = makeStore(folder, secrets: secrets)
        ds2.settings.setEncryptLocalData(true)                               // write gate off; memory updated
        #expect(ds2.localEncryptionKeyIfEnabled(for: ds2.currentDataFile) == nil && ds2.localKeyError != nil)
        #expect(throws: (any Error).self) { try ds2.writeLocalDataFile(Data(freshDB.utf8), to: ds2.currentDataFile) }
    }

    // DataLoadError.macKeyUnavailable: an AAENCM1 file without the Keychain key
    @Test func macKeyUnavailable() throws {
        let folder = TempFolder()
        let ds = makeStore(folder)
        try folder.write("data.json", try LocalEncryption.encrypt(Data(freshDB.utf8), key: SymmetricKey(size: .bits256)))
        _ = ds.load()
        #expect(ds.lastLoadFailed)
        guard case .macKeyUnavailable = ds.lastLoadError else { Issue.record("expected .macKeyUnavailable"); return }
    }

    // TV: 01 §7.3 IsUnderAppFolder (case-insensitive; the folder itself is not under itself)
    @Test func isUnderAppFolder() {
        let ds = DataStore(appFolder: URL(fileURLWithPath: "/U/AA"), secrets: InMemorySecretStore())
        #expect(ds.isUnderAppFolder(URL(fileURLWithPath: "/U/AA/data.json")))
        #expect(ds.isUnderAppFolder(URL(fileURLWithPath: "/U/aa/data.json")))
        #expect(!ds.isUnderAppFolder(URL(fileURLWithPath: "/U/AA2/data.json")))
        #expect(!ds.isUnderAppFolder(URL(fileURLWithPath: "/U/AA")))
        #expect(ds.isUnderAppFolder(URL(fileURLWithPath: "/U/AA/files/x/y.pdf")))
        #expect(!ds.isUnderAppFolder(URL(fileURLWithPath: "/U/AA/../B/data.json")))
    }

    // 03 SHELL-193 / BD.3.2 (V-03): symlinks stay unresolved — a `/private/var/…` AppFolder (an existing path, which
    // `standardizedFileURL` would fold onto `/var/…`) keeps its spelling in appFolder, currentDataFile and the
    // persisted CurrentDataFile; the two spellings still compare as one folder.
    @Test func pathsKeepTheSpellingTheUserGave() throws {
        let folder = TempFolder()
        let plain = folder.url.path
        try #require(plain.hasPrefix("/var/") || plain.hasPrefix("/tmp/"))     // TMPDIR is a /private firmlink
        let given = URL(fileURLWithPath: "/private" + plain, isDirectory: true)
        try #require(FileManager.default.fileExists(atPath: given.path))
        let ds = DataStore(appFolder: given, secrets: InMemorySecretStore())
        ds.loadSettings()
        #expect(ds.appFolder.path == "/private" + plain)
        #expect(ds.currentDataFile.path == "/private" + plain + "/data.json")
        _ = try ds.adoptExternalDataFile(try folder.write("x/../ext.json", "{}"), copyIntoAppFolder: false)
        #expect(ds.currentDataFile.path == plain + "/ext.json")                 // `..` removed, spelling kept
        ds.setCurrentDataFile(given.appending(path: "data.json"))
        #expect(ds.currentDataFile.path == "/private" + plain + "/data.json")
        #expect(ds.settings.values.currentDataFile == "/private" + plain + "/data.json")
        #expect(ds.isUnderAppFolder(folder.url.appending(path: "data.json")))   // /var spelling
        #expect(ds.isUnderAppFolder(given.appending(path: "files/a.pdf")))      // /private/var spelling
        #expect(!ds.isUnderAppFolder(given))
        let other = DataStore(appFolder: folder.url, secrets: InMemorySecretStore())
        #expect(other.isUnderAppFolder(given.appending(path: "data.json")))
        #expect(DataStore.comparablePath(URL(fileURLWithPath: "/private/tmp/a/./b/../c")) == "/tmp/a/c")
        #expect(DataStore.comparablePath(URL(fileURLWithPath: "/private/tmpx/a")) == "/private/tmpx/a")
        #expect(DataStore.lexical(URL(fileURLWithPath: "/private/tmp/a/../b")).path == "/private/tmp/b")
    }

    // TV: 01 App. A17 / DATA-022–023 — migration v0 → v1 and the newer-schema flag
    @Test func schemaMigration() throws {
        let legacy = #"{"Tasks":[{"Recurrence":3,"IsComplete":true,"Subtasks":[{"Recurrence":3,"IsComplete":true},{"Recurrence":3}]},{"Recurrence":0,"IsComplete":true}],"Procedures":[{"Recurrence":2,"Status":3},{"Recurrence":2,"Status":1}]}"#
        for version in ["", #","SchemaVersion":0"#, #","SchemaVersion":-1"#] {
            let folder = TempFolder()
            let ds = makeStore(folder)
            try folder.write("data.json", String(legacy.dropLast()) + version + "}")
            let data = ds.load()
            #expect(!ds.lastLoadFailed && ds.loadedNewerSchema == nil)
            #expect(data.tasks[0].recurrenceSpawned && data.tasks[0].subtasks[0].recurrenceSpawned)
            #expect(!data.tasks[0].subtasks[1].recurrenceSpawned && !data.tasks[1].recurrenceSpawned)
            #expect(data.procedures[0].recurrenceSpawned && !data.procedures[1].recurrenceSpawned)
            let out = String(decoding: try ds.serializeForSave(data), as: UTF8.self)
            #expect(out.hasSuffix(#""SchemaVersion":1}"#))
        }
        // A newer file: flagged, not migrated, never downgraded.
        let folder = TempFolder()
        let ds = makeStore(folder)
        try folder.write("data.json", String(legacy.dropLast()) + #","SchemaVersion":7}"#)
        let data = ds.load()
        #expect(ds.loadedNewerSchema == 7 && !ds.lastLoadFailed)
        #expect(!data.tasks[0].recurrenceSpawned)
        #expect(String(decoding: try ds.serializeForSave(data), as: UTF8.self).hasSuffix(#""SchemaVersion":7}"#))
        // loadFrom migrates too but never sets the flags.
        let imported = try ds.loadFrom(folder.file("data.json"))
        #expect(!imported.tasks[0].recurrenceSpawned)
        try folder.write("v0.json", legacy)
        #expect(try ds.loadFrom(folder.file("v0.json")).tasks[0].recurrenceSpawned)
    }

    // DATA-013 / 01 §3.1: a persisted CurrentDataFile is used only when it exists
    @Test func currentDataFileFallback() throws {
        let folder = TempFolder(), other = TempFolder()
        try folder.write("settings.json", #"{"CurrentDataFile":"C:\\x\\data.json","DarkMode":true,"Foo":1}"#)
        let ds = makeStore(folder)
        #expect(ds.currentDataFile == ds.defaultDataFile && ds.settings.values.darkMode)
        #expect(ds.settings.foreignPathKeys == ["CurrentDataFile"])
        let external = try other.write("mine.json", freshDB)
        ds.setCurrentDataFile(external)
        #expect(ds.settings.values.currentDataFile == external.standardizedFileURL.path)
        let again = makeStore(folder)
        #expect(again.currentDataFile == external.standardizedFileURL)
        try FileManager.default.removeItem(at: external)
        again.loadSettings()
        #expect(again.currentDataFile == again.defaultDataFile)
    }

    // D-14 fixed (DECISIONS 01): Save a Copy As serialises a COPY stamped now; the live model is untouched;
    // never encrypted, even with local encryption on.
    @Test func saveToCopy() throws {
        let folder = TempFolder()
        let ds = makeStore(folder)
        ds.settings.setEncryptLocalData(true)
        let data = AppData()
        data.tasks = [TaskItem(name: "copy me")]
        let before = NetDateTime(year: 2020, month: 1, day: 1, kind: .local)
        data.lastModified = before
        let target = folder.file("exports/aa-data.json")
        try ds.saveTo(data, url: target)
        let written = try JSONParser.parse(Data(contentsOf: target)).objectValue
        #expect(written?["LastModified"]?.stringValue == "2026-09-29T14:05:00+03:00")
        #expect(written?["SchemaVersion"] == .number(JSONNumber(1)))
        #expect(data.lastModified == before && data.lastModified?.originalText == nil && data.schemaVersion == 0)
        #expect(try Data(contentsOf: target).first == 0x7B)
    }

    // serializeForSave: SchemaVersion = max(v, 1), compact, never downgrades (DATA-022)
    @Test func serializeForSave() throws {
        let ds = makeStore(TempFolder())
        let data = AppData()
        #expect(String(decoding: try ds.serializeForSave(data), as: UTF8.self) == freshDB)
        #expect(data.schemaVersion == 1)
        data.schemaVersion = 3
        #expect(String(decoding: try ds.serializeForSave(data), as: UTF8.self).hasSuffix(#""SchemaVersion":3}"#))
    }

    // §MP.3.4 hooks: didLoad with the raw bytes; shouldWrite before, didWrite (exact on-disk bytes) after
    @Test func writeGuardHooks() throws {
        let folder = TempFolder()
        let secrets = InMemorySecretStore()
        let ds = makeStore(folder, secrets: secrets)
        let g = RecordingGuard()
        ds.writeGuard = g
        try folder.write("data.json", Data([0xEF, 0xBB, 0xBF]) + Data(freshDB.utf8))
        _ = ds.load()
        #expect(g.events == ["load:data.json"])
        #expect(g.lastLoaded?.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        ds.settings.setEncryptLocalData(true)
        try ds.writeLocalDataFile(Data(freshDB.utf8), to: ds.currentDataFile)
        #expect(g.events == ["load:data.json", "should:data.json", "did:data.json"])
        #expect(g.lastWritten == (try Data(contentsOf: ds.currentDataFile)))
        #expect(g.lastWritten?.prefix(8) == LocalEncryption.macMagic)
        g.allow = false
        let before = try Data(contentsOf: ds.currentDataFile)
        #expect(throws: AppStoreError.pausedByGuard) { try ds.writeLocalDataFile(Data("{}".utf8), to: ds.currentDataFile) }
        #expect(try Data(contentsOf: ds.currentDataFile) == before)
    }

    // DECISIONS 01 Q-5: copy into the AA folder (default) or use in place (Windows behaviour)
    @Test func adoptExternalDataFile() throws {
        let folder = TempFolder(), other = TempFolder()
        let source = try other.write("their.json", #"{"Tasks":[{"Name":"theirs","Recurrence":1,"IsComplete":true}]}"#)
        let ds = makeStore(folder)
        let target = try ds.adoptExternalDataFile(source, copyIntoAppFolder: true)
        #expect(target == ds.defaultDataFile && ds.currentDataFile == ds.defaultDataFile)
        let copied = try ds.loadFrom(target)
        #expect(copied.tasks.first?.name == "theirs" && copied.tasks.first?.recurrenceSpawned == true && copied.schemaVersion == 1)
        #expect(try other.readText("their.json").contains("SchemaVersion") == false)     // source untouched
        let inPlace = try ds.adoptExternalDataFile(source, copyIntoAppFolder: false)
        #expect(inPlace == source.standardizedFileURL && ds.currentDataFile == source.standardizedFileURL)
        #expect(try other.readText("their.json").hasSuffix(#""SchemaVersion":1}"#))
        #expect(ds.settings.values.currentDataFile == source.standardizedFileURL.path)
        #expect(throws: (any Error).self) { _ = try ds.adoptExternalDataFile(other.file("missing.json"), copyIntoAppFolder: true) }
    }

    // DataStore.loadInBackground mirrors load(): failures flag safe mode, a null root is empty
    @Test func loadInBackground() async throws {
        let folder = TempFolder()
        let ds = makeStore(folder)
        try folder.write("data.json", "null")
        _ = await ds.loadInBackground()
        #expect(!ds.lastLoadFailed)
        try folder.write("data.json", "[1]")
        _ = await ds.loadInBackground()
        #expect(ds.lastLoadFailed)
        try folder.write("data.json", #"{"Tasks":[{"Name":"bg"}],"SchemaVersion":9}"#)
        let data = await ds.loadInBackground()
        #expect(!ds.lastLoadFailed && data.tasks.first?.name == "bg" && ds.loadedNewerSchema == 9)
    }
}

@MainActor @Suite struct ModelCloningTests {
    // TV: ARCHITECTURE.md §3.10 — deepClone uses the dynamic type; own, base and extra keys preserved
    @Test func deepCloneKeepsTheDynamicType() throws {
        let t = TaskItem(name: "T")
        t.deadline = NetDateTime.calendarDate(CivilDate(year: 2026, month: 10, day: 1)!)
        t.subtasks = [TaskItem(name: "S")]
        t.lockHint = "hint"
        t.extra.set("Future", .number(JSONNumber(lexeme: "1.50")))
        let clone = ModelCodec.deepClone(t as HierarchyItem)
        #expect(clone is TaskItem)
        #expect(clone !== t)
        let c = try #require(clone as? TaskItem)
        #expect(c.id == t.id && c.subtasks.first?.name == "S" && c.subtasks.first !== t.subtasks.first)
        #expect(c.lockHint == "hint" && c.extra["Future"] == .number(JSONNumber(lexeme: "1.50")))
        #expect(c.toJSON(options: .dataFile) == t.toJSON(options: .dataFile))
        for item in [Equipment(name: "E"), Procedure(name: "P"), Vessel(name: "V")] as [HierarchyItem] {
            #expect(type(of: ModelCodec.deepClone(item)) == type(of: item))
        }
        let data = AppData(); data.tasks = [t]
        let dataClone = ModelCodec.deepClone(data)
        #expect(dataClone.tasks.first !== t && dataClone.tasks.first?.name == "T")
    }

    // TV: 01 §4.10 — Trash payloads decode with the type named by ItemType; anything else → nil
    @Test func trashPayloads() throws {
        let crew = CrewMember(id: G(11)); crew.firstName = "Ana"
        let payload = TrashPayload.encode(crew)
        #expect((TrashPayload.decode(itemType: "Crew", payload: payload, context: .standard) as? CrewMember)?.firstName == "Ana")
        let task = TaskItem(id: G(3), name: "T")
        let tp = TrashPayload.encode(task)
        #expect(TrashPayload.decode(itemType: "Task", payload: tp, context: .standard) is TaskItem)
        #expect(TrashPayload.decode(itemType: "Equipment", payload: tp, context: .standard) is Equipment)
        #expect(TrashPayload.decode(itemType: "Bogus", payload: tp, context: .standard) == nil)
        #expect(TrashPayload.decode(itemType: "Task", payload: #"{"Tasks":"#, context: .standard) == nil)
        #expect(TrashPayload.decode(itemType: "Task", payload: "[]", context: .standard) == nil)
        #expect(TrashPayload.decode(itemType: "Task", payload: #"{"Status":"Done"}"#, context: .standard) == nil)
    }
}
