// TV: 01 App. A19.1 (UTF-8 BOM + A01), A20 (`AAENC1\n` + 64 bytes → safe mode), GF.5.b S02 / S03 (settings bytes,
//     Mac expectations) — byte fixtures under Fixtures/persistence/.
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct PersistenceFixtureTests {
    func store(_ folder: TempFolder) -> DataStore {
        let ds = DataStore(appFolder: folder.url, secrets: InMemorySecretStore(),
                           clock: FixedClock(local: "2026-09-29T14:05:00", zone: TZ.athens))
        ds.loadSettings()
        return ds
    }

    // TV: 01 App. A19.1 — BOM + A01 loads; the next save writes A01 without the BOM
    @Test func bomFile() throws {
        let folder = TempFolder()
        let bytes = try Fixtures.data("persistence/A19-bom.data-json.json")
        #expect(bytes.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        try folder.write("data.json", bytes)
        let ds = store(folder)
        let data = ds.load()
        #expect(!ds.lastLoadFailed)
        #expect(try ds.serializeForSave(data) == (try Fixtures.data("json/A01.appdata.golden.json")))
    }

    // TV: 01 App. A20 — a Windows DPAPI data file → load failure (safe mode), nothing decoded
    @Test func windowsDPAPIFile() throws {
        let folder = TempFolder()
        let bytes = try Fixtures.data("persistence/windows-dpapi.data-json.bin")
        #expect(LocalEncryption.classify(bytes) == .windowsDPAPI && bytes.count == 71)
        try folder.write("data.json", bytes)
        let ds = store(folder)
        _ = ds.load()
        #expect(ds.lastLoadFailed)
        guard case .windowsEncrypted = ds.lastLoadError else { Issue.record("expected .windowsEncrypted"); return }
        #expect(throws: DataLoadError.self) { _ = try DataStore.readDataBytes(folder.file("data.json"), key: nil) }
    }

    // GF S02 — every setter once; the file equals the golden bytes
    @Test func settingsS02() throws {
        let folder = TempFolder()
        let s = SettingsStore(fileURL: folder.file("settings.json"), secrets: InMemorySecretStore())
        s.reload()
        s.setCurrentDataFile("/U/AA/data.json")
        s.setPassword(hash: "H", salt: "AAECAwQFBgcICQoLDA0ODw==")
        s.setGoogleDriveFolder("/Users/u/My Drive")
        s.setSyncOnSave(true)
        s.setTextOnlyExport(true)
        s.setDarkMode(true)
        s.setEncryptLocalData(false)
        s.setAppIdentity(" Vessel-Alpha ")
        s.setFolderBuilderBase("/tmp/fb")
        s.setSharedSaveFile("/Volumes/share/aa-shared.zip")
        #expect(try folder.read("settings.json") == (try Fixtures.data("persistence/settings-S02.golden.json")))
        // …and reading the golden gives the same values back.
        let t = SettingsStore(fileURL: Fixtures.url("persistence/settings-S02.golden.json"), secrets: InMemorySecretStore())
        t.reload()
        #expect(t.values == s.values)
    }

    // GF S03 (Mac expectation) — unknown keys, raw numbers and Windows paths survive a key-level merge
    @Test func settingsS03() throws {
        let folder = TempFolder()
        try folder.write("settings.json", try Fixtures.data("persistence/settings-S03.input.json"))
        let s = SettingsStore(fileURL: folder.file("settings.json"), secrets: InMemorySecretStore())
        s.reload()
        s.setSyncOnSave(true)
        #expect(try folder.read("settings.json") == (try Fixtures.data("persistence/settings-S03.mac-expected.golden.json")))
    }
}
