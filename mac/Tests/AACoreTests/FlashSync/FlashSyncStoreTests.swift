// TV: 13 §7.10 (buildOutgoing with no baseline → snapshot "full database"; baseline equal → nil; after writeBaseline →
//     nil; Preview cases; Apply: baseline = tree re-read, active data file = default data.json, files/ untouched, unknown
//     settings keys survive), FLASH-100…107, FLASH-021, FLASH-132, DECISIONS 13 Q-5 (unreadable database / settings),
//     Q-10 (transactional apply), Q-11 (encrypted baseline); OWNERSHIP W-FLASH acceptance "unreadable settings abort the
//     apply with nothing written". Post-merge (gated on .wPersist): apply → applySyncedData end to end.
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct FlashSyncStoreTests {
    @MainActor final class Env {
        let made: StoreFactory.Made
        let store: FlashSyncStore
        var applyCalls = 0
        var failApply = false

        init(clock: AppClock = FixedClock(local: "2026-09-27T12:00:00", zone: TZ.athens), real: Bool = false) {
            made = StoreFactory.make(clock: clock)
            let ds = made.dataStore
            if real {
                store = FlashSyncStore(dataStore: ds)
            } else {
                weak var box: Env?
                store = FlashSyncStore(dataStore: ds) { json in
                    box?.applyCalls += 1
                    if box?.failApply == true { throw FlashSyncError.writeFailed("simulated failure") }
                    // Stand-in for W-PERSIST's applySyncedData: default data file, write, re-load through the model.
                    try ds.writeLocalDataFile(json, to: ds.defaultDataFile)
                    ds.setCurrentDataFile(ds.defaultDataFile)
                    return try ds.loadFrom(ds.defaultDataFile)
                }
                box = self
            }
        }

        var ds: DataStore { made.dataStore }
        var folder: TempFolder { made.folder }

        func writeData(_ build: (AppData) -> Void) throws {
            let d = AppData()
            build(d)
            try ds.writeLocalDataFile(try ds.serializeForSave(d), to: ds.currentDataFile)
        }

        func writeSettings(_ json: String) throws { try folder.write("settings.json", json); ds.settings.reload() }
        func settingsText() throws -> String { try folder.readText("settings.json") }
    }

    // TV: 13 §7.10 — no baseline → snapshot "full database"; pending baseline = the trees it was built from
    @Test func noBaselineSendsTheWholeDatabase() throws {
        let env = Env()
        try env.writeData { $0.tasks = [TaskItem(name: "Purge cargo tank 3")] }
        try env.writeSettings(#"{"DarkMode":true,"PasswordHash":"h","AppIdentity":"MAC1","Zed":1}"#)
        let out = try #require(try env.store.buildOutgoing(from: "MAC1"))
        #expect(out.kind == .fullSnapshot)
        #expect(out.label == "full database")
        let payload = try #require(try JSONParser.parse(Data(out.payload)).objectValue)
        #expect(FlashChangeSet.isSnapshotEnvelope(.object(payload)))
        #expect(FlashTestKit.text(payload["Settings"]!.objectValue!) == #"{"DarkMode":true,"Zed":1}"#)
        #expect(payload["Data"]?.objectValue?["LastModified"] == nil)
        #expect(out.pendingData == (try env.store.readDataTree()))
        #expect(out.pendingSettings["PasswordHash"]?.stringValue == "h")        // unstripped (FLASH-021)
    }

    // TV: 13 §7.10 — after writeBaseline(current) → nothing to send; an edit → a change set labelled by its summary
    @Test func baselineMakesTheNextSendIncremental() throws {
        let env = Env()
        let t = TaskItem(name: "Calibrate gas detector")
        try env.writeData { $0.tasks = [t] }
        let first = try #require(try env.store.buildOutgoing(from: "Mac"))
        #expect(!env.store.hasBaseline)
        #expect(env.store.writeBaseline(data: first.pendingData, settings: first.pendingSettings))
        #expect(env.store.hasBaseline)
        #expect(try env.store.buildOutgoing(from: "Mac") == nil)
        try env.writeData { $0.tasks = [t, TaskItem(name: "Test emergency shutdown")] }
        let second = try #require(try env.store.buildOutgoing(from: "Mac"))
        #expect(second.kind == .changeSet)
        #expect(second.label == "1 Tasks")
        let cs = try #require(try JSONParser.parse(Data(second.payload)).objectValue)
        #expect(cs["From"]?.stringValue == "Mac")
        #expect(cs["Created"]?.stringValue == "2026-09-27T12:00:00")
    }

    // TV: 13 §6.6 point 3 — the idle refresh is skipped while the sources are unchanged: the fingerprint is stable
    //     across reads and moves with a data save, a settings write and a baseline write or clear
    @Test func sourceFingerprintTracksEverySource() throws {
        let env = Env()
        try env.writeData { $0.tasks = [TaskItem(name: "Check fire dampers")] }
        try env.writeSettings(#"{"DarkMode":false}"#)
        let a = env.store.sourceFingerprint()
        _ = try env.store.buildOutgoing(from: "Mac")
        #expect(env.store.sourceFingerprint() == a)
        try env.writeData { $0.tasks = [TaskItem(name: "Check fire dampers"), TaskItem(name: "Grease davits")] }
        let b = env.store.sourceFingerprint()
        #expect(b != a)
        try env.writeSettings(#"{"DarkMode":true}"#)
        let c = env.store.sourceFingerprint()
        #expect(c != b)
        env.store.writeBaseline(data: FlashTestKit.object(#"{"Tasks":[]}"#), settings: nil)
        let d = env.store.sourceFingerprint()
        #expect(d != c)
        env.store.clearBaseline()
        #expect(env.store.sourceFingerprint() != d)
    }

    // TV: 13 §4.4 — baseline shape, StampedUtc "O" format; FLASH-102 unreadable baseline → snapshot, never an error
    @Test func baselineFileShapeAndTolerance() throws {
        let env = Env()
        env.store.writeBaseline(data: FlashTestKit.object(#"{"Tasks":[]}"#), settings: nil)
        let text = try env.folder.readText("qrsync-baseline.json")
        #expect(text.hasPrefix(#"{"StampedUtc":"2026-09-27T09:00:00.0000000Z","Data":{"Tasks":[]},"Settings":null}"#))
        #expect(env.store.readBaseline() == FlashBaseline(data: FlashTestKit.object(#"{"Tasks":[]}"#), settings: nil))
        try env.folder.write("qrsync-baseline.json", "{not json")
        #expect(env.store.readBaseline() == nil)
        #expect(try env.store.buildOutgoing(from: "Mac")?.kind == .fullSnapshot)
        try env.folder.write("qrsync-baseline.json", #"{"Data":[1]}"#)
        #expect(env.store.readBaseline() == nil)
        try env.folder.write("qrsync-baseline.json", #"{"Settings":{"A":1}}"#)
        #expect(env.store.readBaseline() == FlashBaseline(data: nil, settings: FlashTestKit.object(#"{"A":1}"#)))
        #expect(try env.store.buildOutgoing(from: "Mac")?.kind == .fullSnapshot)
        env.store.clearBaseline()
        #expect(!env.store.hasBaseline)
    }

    // TV: DECISIONS 13 Q-11 — encrypted baseline when local encryption is on; plaintext still readable
    @Test func baselineIsEncryptedWhenLocalEncryptionIsOn() throws {
        let env = Env()
        env.ds.settings.setEncryptLocalData(true)
        #expect(env.store.writeBaseline(data: FlashTestKit.object(#"{"Secret":"x"}"#), settings: JSONObject()))
        let raw = try env.folder.read("qrsync-baseline.json")
        #expect(LocalEncryption.classify(raw) == .mac)
        #expect(!String(decoding: raw, as: UTF8.self).contains("Secret"))
        #expect(env.store.readBaseline()?.data == FlashTestKit.object(#"{"Secret":"x"}"#))
        env.ds.settings.setEncryptLocalData(false)
        #expect(env.store.readBaseline()?.data == FlashTestKit.object(#"{"Secret":"x"}"#))   // key still in the Keychain
        env.store.writeBaseline(data: JSONObject(), settings: nil)
        #expect(LocalEncryption.classify(try env.folder.read("qrsync-baseline.json")) == .plain)
    }

    // TV: DECISIONS 13 Q-5 — an unreadable database refuses to prepare (never a snapshot of nothing)
    @Test func unreadableDatabaseRefuses() throws {
        let env = Env()
        try env.folder.write("data.json", "{\"Tasks\":[")
        #expect(throws: FlashSyncError.databaseUnreadable) { _ = try env.store.buildOutgoing(from: "Mac") }
        #expect(FlashSyncError.databaseUnreadable.localizedDescription == "The database could not be read, so Flash Sync is unavailable until it is fixed.")
        // A missing data file is an empty database, not an error.
        try FileManager.default.removeItem(at: env.folder.file("data.json"))
        #expect(try env.store.buildOutgoing(from: "Mac")?.kind == .fullSnapshot)
    }

    // TV: OWNERSHIP acceptance / Q-5 — unreadable settings abort the apply with nothing written
    @Test func unreadableSettingsAbortTheApply() throws {
        let env = Env()
        try env.writeData { $0.tasks = [TaskItem(name: "Keep me")] }
        let dataBefore = try env.folder.read("data.json")
        try env.folder.write("settings.json", "{\"DarkMode\":tr")
        let change = try #require(FlashSyncStore.preview(Array(#"{"V":1,"Settings":{"DarkMode":true},"Sets":{"Tasks":[{"Id":"x"}]}}"#.utf8), kind: .changeSet))
        #expect(throws: FlashSyncError.self) { _ = try env.store.apply(change) }
        #expect(env.applyCalls == 0)
        #expect(try env.folder.read("data.json") == dataBefore)
        #expect(try env.settingsText() == "{\"DarkMode\":tr")
        #expect(!env.store.hasBaseline)
        // Building is refused too: unreadable settings would otherwise emit SettingsDeletes for every shared key.
        #expect(throws: FlashSyncError.self) { _ = try env.store.buildOutgoing(from: "Mac") }
    }

    // TV: FLASH-105 / 13 §7.10 — the apply pipeline: settings merged and written (unknown + excluded keys survive), data
    // through applySyncedData, active data file reset to the default, files/ untouched, baseline = tree re-read
    @Test func applyChangeSetPipeline() throws {
        let env = Env()
        let other = env.folder.file("elsewhere.json")
        env.ds.setCurrentDataFile(other)
        let t = TaskItem(name: "Inspect ballast valve")
        try env.writeData { $0.tasks = [t] }
        try env.writeSettings(#"{"CurrentDataFile":"\#(other.path)","PasswordHash":"mine","DarkMode":false,"OnlyHere":1}"#)
        try env.folder.write("files/abc_manual.pdf", "PDF")
        // The sender's whole item (items always travel complete), edited on the phone, with an unmodelled key.
        var item = try #require(try env.store.readDataTree()["Tasks"]?.arrayValue?.first?.objectValue)
        item.set("Name", .string("Inspect ballast valve (done)"))
        item.set("PhoneOnly", .object(FlashTestKit.object(#"{"x":1}"#)))
        let payload = #"{"V":1,"From":"iOS","Created":"2026-09-27T11:00:00","Sets":{"Tasks":[\#(FlashTestKit.text(item))]},"Settings":{"DarkMode":true,"PasswordHash":"theirs","NewPref":"z"},"UiChanges":{"TabOrder":["TabTasks"],"WindowLeft":5}}"#
        let change = try #require(FlashSyncStore.preview(Array(payload.utf8), kind: .changeSet))
        #expect(!change.isSnapshot && change.carriesSettings)
        #expect(change.summary == "1 Tasks, layout, settings")
        let model = try env.store.apply(change)
        #expect(env.applyCalls == 1)
        #expect(model.tasks.first?.name == "Inspect ballast valve (done)")
        #expect(env.ds.currentDataFile == env.ds.defaultDataFile)
        #expect(try env.folder.readText("files/abc_manual.pdf") == "PDF")
        let settings = try env.store.readSettingsTree()
        #expect(settings["DarkMode"]?.boolValue == true)
        #expect(settings["PasswordHash"]?.stringValue == "mine")
        #expect(settings["OnlyHere"] != nil && settings["NewPref"]?.stringValue == "z")
        #expect(env.ds.settings.values.darkMode)
        let baseline = try #require(env.store.readBaseline())
        #expect(baseline.data == (try env.store.readDataTree()))
        #expect(baseline.settings == settings)
        let ui = try #require(baseline.data?["Ui"]?.objectValue)
        #expect(ui["TabOrder"] != nil && ui["WindowLeft"] == nil)
        // The receiver now agrees with the sender: nothing to send back.
        #expect(try env.store.buildOutgoing(from: "Mac") == nil)
    }

    // TV: DECISIONS 13 Q-10 — a failing data write restores the previous settings.json and writes no baseline
    @Test func applyIsTransactional() throws {
        let env = Env()
        try env.writeData { $0.tasks = [TaskItem(name: "A")] }
        let original = #"{"DarkMode":false,"Keep":true}"#
        try env.writeSettings(original)
        env.failApply = true
        let change = try #require(FlashSyncStore.preview(Array(#"{"V":1,"Settings":{"DarkMode":true}}"#.utf8), kind: .changeSet))
        #expect(throws: FlashSyncError.self) { _ = try env.store.apply(change) }
        #expect(try env.settingsText() == original)
        #expect(!env.ds.settings.values.darkMode)
        #expect(!env.store.hasBaseline)
        // With no settings.json at all, the failed apply leaves none behind.
        try FileManager.default.removeItem(at: env.folder.file("settings.json"))
        env.ds.settings.reload()
        #expect(throws: FlashSyncError.self) { _ = try env.store.apply(change) }
        #expect(!env.folder.exists("settings.json"))
    }

    // TV: FLASH-092 / CS-12 through the store — snapshot apply keeps this device's per-device Ui keys
    @Test func applySnapshotPipeline() throws {
        let env = Env()
        try env.writeData { d in
            d.tasks = [TaskItem(name: "Local only")]
            d.ui.windowLeft = 321
            d.ui.tabOrder = ["TabCrew"]
        }
        let snap = #"{"V":1,"Data":{"Tasks":[{"Id":"0b6c3d0e-0000-4000-8000-000000000001","Name":"From the phone"}],"SchemaVersion":1,"Ui":{"TabOrder":["TabTasks"],"WindowLeft":1}},"Settings":{"DarkMode":true}}"#
        let change = try #require(FlashSyncStore.preview(Array(snap.utf8), kind: .fullSnapshot))
        #expect(change.isSnapshot && change.carriesSettings)
        #expect(change.summary == "the sender's entire database (replaces yours)")
        let model = try env.store.apply(change)
        #expect(model.tasks.map(\.name) == ["From the phone"])
        #expect(model.ui.windowLeft == 321)
        #expect(model.ui.tabOrder == ["TabTasks"])
    }

    // TV: 13 §7.10 Preview cases + FLASH-132 carriesSettings
    @Test func previewCases() {
        let csShaped = Array(#"{"V":1,"Sets":{"Tasks":[]}}"#.utf8)
        #expect(FlashSyncStore.preview(csShaped, kind: .fullSnapshot)?.isSnapshot == true)     // kind wins
        #expect(FlashSyncStore.preview(csShaped, kind: .fullSnapshot)?.carriesSettings == false)
        let envelope = Array(#"{"V":1,"Data":{},"Settings":{"DarkMode":true}}"#.utf8)
        #expect(FlashSyncStore.preview(envelope, kind: .changeSet)?.isSnapshot == true)        // envelope wins
        #expect(FlashSyncStore.preview(envelope, kind: .changeSet)?.carriesSettings == true)
        #expect(FlashSyncStore.preview(Array(#"{"V":1,"Data":{},"Settings":null}"#.utf8), kind: .fullSnapshot)?.carriesSettings == false)
        #expect(FlashSyncStore.preview(Array("[]".utf8), kind: .changeSet) == nil)
        #expect(FlashSyncStore.preview([0xFF, 0xFE, 0x00, 0x7B], kind: .changeSet) == nil)
        #expect(FlashSyncStore.preview(Array("{\"a\":".utf8), kind: .changeSet) == nil)
        #expect(FlashSyncStore.preview([0xEF, 0xBB, 0xBF] + Array("{}".utf8), kind: .changeSet)?.summary == "other changes")
    }

    // Post-merge (Stage V): the real W-PERSIST applySyncedData end to end
    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func applyThroughRealApplySyncedData() throws {
        let env = Env(real: true)
        try env.writeData { $0.tasks = [TaskItem(name: "Before")] }
        try env.folder.write("files/keep.txt", "keep")
        let change = try #require(FlashSyncStore.preview(Array(#"{"V":1,"Blocks":{"Extra":{"k":1}},"Settings":{"DarkMode":true}}"#.utf8), kind: .changeSet))
        let model = try env.store.apply(change)
        #expect(model.tasks.map(\.name) == ["Before"])
        #expect(env.ds.currentDataFile == env.ds.defaultDataFile)
        #expect(try env.folder.readText("files/keep.txt") == "keep")
        #expect(env.store.readBaseline()?.data == (try env.store.readDataTree()))
        #expect(try env.store.readDataTree()["Extra"] != nil)
    }
}
