// TV: Stage V round 2 finding V2-SCALE (Flash Sync Send prepared the payload by loading, decoding and re-serialising
//     the whole database on the main thread — 1.24 s for 70 MB). `FlashSyncStore.captureSendInputs(live:)` must return
//     exactly what the synchronous `captureSendInputs()` returns (13 §3.12 FLASH-103: the database read from disk as
//     it would be written), taking the off-main route when the file is the live model's own save encoding and the
//     exact reload otherwise; DECISIONS 13 Q-5 (unreadable database / settings), Q-11 (encrypted baseline).
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct FlashSendCaptureTests {
    private static func richModel(_ appFolder: URL) -> AppData {
        let d = AppData()
        let t = TaskItem(name: "Purge cargo tank 3")
        t.deadline = NetDateTime(year: 2026, month: 10, day: 3, hour: 8, minute: 30, kind: .local)
        t.container.files = [FileItem(name: "sop.pdf", path: appFolder.appending(path: "files/sop.pdf").path),
                             FileItem(name: "web", path: "https://example.org/x", isLink: true)]
        d.tasks = [t, TaskItem(name: "Calibrate gas detector")]
        d.schemaVersion = 0                                                  // stamped by the save encoding
        return d
    }

    private static func assertSameAsSynchronous(_ store: FlashSyncStore, _ got: FlashSendInputs) throws {
        let sync = try store.captureSendInputs()
        #expect(got.dataJSON == sync.dataJSON)
        #expect(got.settings == sync.settings)
        #expect(got.baselineJSON == sync.baselineJSON)
    }

    // TV: V2-SCALE — after a save the file is the live model's encoding: no reload on the main actor, same bytes
    @Test func savedModelTakesTheOffMainRoute() async throws {
        let made = StoreFactory.make()
        made.store.replaceData(Self.richModel(made.dataStore.appFolder), reason: .other("test"))
        try made.store.save()
        try made.folder.write("settings.json", #"{"DarkMode":true,"AppIdentity":"MAC1"}"#)
        made.dataStore.settings.reload()
        let store = FlashSyncStore(dataStore: made.dataStore)
        #expect(store.writeBaseline(data: FlashTestKit.object(#"{"Tasks":[]}"#), settings: JSONObject()))
        let (inputs, route) = try await store.captureSendInputsRouted(live: made.store.data)
        #expect(route == .liveModelMatch)
        try Self.assertSameAsSynchronous(store, inputs)
        #expect(String(decoding: inputs.dataJSON, as: UTF8.self).contains(#""Path":"files/sop.pdf""#))
        #expect(inputs.baselineJSON != nil)
    }

    // TV: V2-SCALE + Q-11 — an encrypted data file and an encrypted baseline still take the off-main route
    @Test func encryptedFilesTakeTheOffMainRoute() async throws {
        let made = StoreFactory.make()
        made.dataStore.settings.setEncryptLocalData(true)
        made.store.replaceData(Self.richModel(made.dataStore.appFolder), reason: .other("test"))
        try made.store.save()
        #expect(LocalEncryption.classify(try made.folder.read("data.json")) == .mac)
        let store = FlashSyncStore(dataStore: made.dataStore)
        #expect(store.writeBaseline(data: FlashTestKit.object(#"{"Secret":"x"}"#), settings: nil))
        #expect(LocalEncryption.classify(try made.folder.read("qrsync-baseline.json")) == .mac)
        let (inputs, route) = try await store.captureSendInputsRouted(live: made.store.data)
        #expect(route == .liveModelMatch)
        try Self.assertSameAsSynchronous(store, inputs)
        #expect(inputs.baselineJSON.flatMap(FlashSyncStore.parseBaseline)?.data == FlashTestKit.object(#"{"Secret":"x"}"#))
    }

    // TV: V2-SCALE — bytes another writer produced (indented JSON, a pre-SchemaVersion Windows file) are reloaded
    //     exactly; the result is the save encoding, never the raw file
    @Test func foreignBytesAreReloadedExactly() async throws {
        let made = StoreFactory.make()
        made.store.replaceData(Self.richModel(made.dataStore.appFolder), reason: .other("test"))
        try made.store.save()
        let tree = try JSONParser.parse(try made.folder.read("data.json"))
        var obj = try #require(tree.objectValue)
        _ = obj.removeValue(forKey: "SchemaVersion")
        try made.folder.write("data.json", try JSONWriter.data(.object(obj), options: .aaschedIndented))
        let store = FlashSyncStore(dataStore: made.dataStore)
        let (inputs, route) = try await store.captureSendInputsRouted(live: made.store.data)
        #expect(route == .reloaded)
        try Self.assertSameAsSynchronous(store, inputs)
        #expect(String(decoding: inputs.dataJSON, as: UTF8.self).contains(#""SchemaVersion":1"#))
    }

    // TV: V2-SCALE — a live edit that is not on disk: the disk is what travels (13 §3.12; the window saves first)
    @Test func unsavedLiveEditsDoNotLeakIntoThePayload() async throws {
        let made = StoreFactory.make()
        made.store.replaceData(Self.richModel(made.dataStore.appFolder), reason: .other("test"))
        try made.store.save()
        made.store.data.tasks.append(TaskItem(name: "Not saved yet"))
        let store = FlashSyncStore(dataStore: made.dataStore)
        let (inputs, route) = try await store.captureSendInputsRouted(live: made.store.data)
        #expect(route == .reloaded)
        try Self.assertSameAsSynchronous(store, inputs)
        #expect(!String(decoding: inputs.dataJSON, as: UTF8.self).contains("Not saved yet"))
    }

    // TV: V2-SCALE — a stored file whose path normalisation changed since the save (its leaf arrived in files/) is
    //     reloaded, so the payload carries the normalised path exactly as the synchronous read does
    @Test func pathNormalisationSinceTheSaveIsHonoured() async throws {
        let made = StoreFactory.make()
        let d = AppData()
        let t = TaskItem(name: "Bunker plan")
        t.container.files = [FileItem(name: "plan.txt", path: #"C:\Users\Ship\AppData\Local\AA\files\plan.txt"#)]
        d.tasks = [t]
        made.store.replaceData(d, reason: .other("test"))
        try made.store.save()
        #expect(String(decoding: try made.folder.read("data.json"), as: UTF8.self).contains(#"C:\\Users"#))
        try made.folder.write("files/plan.txt", "plan")
        let store = FlashSyncStore(dataStore: made.dataStore)
        let (inputs, route) = try await store.captureSendInputsRouted(live: made.store.data)
        #expect(route == .reloaded)
        try Self.assertSameAsSynchronous(store, inputs)
        #expect(String(decoding: inputs.dataJSON, as: UTF8.self).contains(#""Path":"files/plan.txt""#))
    }

    // TV: V2-SCALE — no live model / a missing data file → the exact synchronous read (empty database)
    @Test func missingFileOrNoLiveModelReload() async throws {
        let made = StoreFactory.make()
        let store = FlashSyncStore(dataStore: made.dataStore)
        let (empty, r1) = try await store.captureSendInputsRouted(live: made.store.data)
        #expect(r1 == .reloaded)
        try Self.assertSameAsSynchronous(store, empty)
        made.store.replaceData(Self.richModel(made.dataStore.appFolder), reason: .other("test"))
        try made.store.save()
        let (inputs, r2) = try await store.captureSendInputsRouted(live: nil)
        #expect(r2 == .reloaded)
        try Self.assertSameAsSynchronous(store, inputs)
    }

    // TV: V2-SCALE + Q-5 — an unreadable database refuses (before an unreadable settings.json), as the sync path does
    @Test func unreadableSourcesKeepTheirErrorsAndOrder() async throws {
        let made = StoreFactory.make()
        let store = FlashSyncStore(dataStore: made.dataStore)
        try made.folder.write("data.json", Data("AAENC1\n".utf8) + Data(repeating: 7, count: 64))
        await #expect(throws: FlashSyncError.databaseUnreadable) { _ = try await store.captureSendInputs(live: made.store.data) }
        try made.folder.write("data.json", "{\"Tasks\":[")
        try made.folder.write("settings.json", "{\"DarkMode\":tr")
        await #expect(throws: FlashSyncError.databaseUnreadable) { _ = try await store.captureSendInputs(live: made.store.data) }
        try FileManager.default.removeItem(at: made.folder.file("data.json"))
        await #expect(throws: FlashSyncError.self) { _ = try await store.captureSendInputs(live: made.store.data) }
    }

    // TV: V2-SCALE — the main-actor half encodes exactly as `DataStore.serializeForSave` does (a drift here would only
    //     make every send take the reload route, but it must not go unnoticed)
    @Test func saveEncodingTreeMatchesSerializeForSave() throws {
        let made = StoreFactory.make()
        let store = FlashSyncStore(dataStore: made.dataStore)
        let a = Self.richModel(made.dataStore.appFolder)
        let b = ModelCodec.deepClone(a, context: made.dataStore.decodeContext)
        let tree = try #require(store.saveEncodingTree(a))
        #expect(try JSONWriter.data(tree) == (try made.dataStore.serializeForSave(b)))
        #expect(a.schemaVersion == DataStore.currentSchemaVersion)
    }
}
