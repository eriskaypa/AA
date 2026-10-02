// TV: 01 MP.7.6 S-1…S-4 (DATA-182 key-level merge, retry, refusal, write gate, joint writes), 01 §7.12, App. GF.5.b
//     S03/S06/S07/S09/S12 (Mac expectations), 13 §3.12 / DECISIONS 13 Q-5 (raw tree read/write), 01 §6.8 (foreign
//     paths), DECISIONS 14 (default identity).
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct SettingsStoreTests {
    @MainActor final class Env {
        let folder = TempFolder("aa-settings")
        lazy var store = SettingsStore(fileURL: folder.file("settings.json"), secrets: InMemorySecretStore())
        func write(_ text: String) throws { try folder.write("settings.json", text) }
        func text() throws -> String { try folder.readText("settings.json") }
        var exists: Bool { folder.exists("settings.json") }
    }

    // TV: 01 §7.12 — no file → defaults; AppIdentity = computer name
    @Test func noFileDefaults() {
        let env = Env()
        env.store.reload()
        #expect(env.store.values == AppSettings())
        #expect(env.store.appIdentity == SettingsStore.defaultIdentity())
        #expect(!SettingsStore.defaultIdentity().isEmpty)
        #expect(!env.exists)
    }

    // TV: MP.7.6 S-1 — another process's DarkMode survives; known keys in §4.3 order, unknown keys last
    @Test func s1KeyLevelMerge() throws {
        let env = Env()
        env.store.reload()
        #expect(!env.store.values.darkMode)
        try env.write(#"{"SyncOnSave":false,"DarkMode":true,"Foo":1}"#)
        env.store.setTextOnlyExport(true)
        #expect(try env.text() == #"{"SyncOnSave":false,"DarkMode":true,"TextOnlyExport":true,"Foo":1}"#)
        #expect(!env.store.values.darkMode)                       // memory is not re-read
        #expect(!env.store.lastWriteRefused)
    }

    // TV: MP.7.6 S-2 — an unreadable file is retried 3 × 50 ms, never written; memory keeps the value
    @Test func s2UnreadableFileIsNeverOverwritten() throws {
        let env = Env()
        let cut = #"{"PasswordHash":"V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=","PasswordSalt":"AAECAwQFBgcICQoLDA0ODw==","DarkMode":tr"#
        try env.write(cut)
        env.store.reload()
        let started = Date()
        env.store.setDarkMode(false)
        #expect(Date().timeIntervalSince(started) >= 0.14)       // 3 retries, 50 ms apart
        #expect(try env.text() == cut)
        #expect(env.store.values.darkMode == false)
        #expect(env.store.lastWriteRefused)
        #expect(SettingsStore.unreadableStatus == "Couldn't update settings.json (it is unreadable) — this change applies until AA quits.")
        try env.write(#"{"DarkMode":true}"#)                      // readable again → the next setter writes and clears the flag
        env.store.setSyncOnSave(true)
        #expect(!env.store.lastWriteRefused)
        #expect(try env.text() == #"{"SyncOnSave":true,"DarkMode":true}"#)
    }

    // TV: MP.7.6 S-3 — read-only instance: the file is unchanged, memory updated
    @Test func s3WriteGate() throws {
        let env = Env()
        try env.write(#"{"DarkMode":false}"#)
        env.store.reload()
        env.store.isWriteGated = true
        env.store.setDarkMode(true)
        #expect(try env.text() == #"{"DarkMode":false}"#)
        #expect(env.store.values.darkMode)
        #expect(throws: DataLoadError.self) { try env.store.writeRawTree(JSONObject([("DarkMode", .bool(true))])) }
        #expect(try env.text() == #"{"DarkMode":false}"#)
    }

    // TV: MP.7.6 S-4 — PasswordHash + PasswordSalt in one atomic replace; GF S11 (verify after reload)
    @Test func s4JointPasswordWrite() throws {
        let env = Env()
        try env.write(#"{"AppIdentity":"Vessel-Alpha","X":[1]}"#)
        env.store.setPassword(hash: "V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=", salt: "AAECAwQFBgcICQoLDA0ODw==")
        #expect(try env.text() == #"{"PasswordHash":"V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=","PasswordSalt":"AAECAwQFBgcICQoLDA0ODw==","AppIdentity":"Vessel-Alpha","X":[1]}"#)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: env.folder.url.path)
        #expect(leftovers == ["settings.json"])                   // no temp file left behind
        env.store.reload()
        let ps = PasswordService(settings: env.store)
        #expect(ps.verify("correct horse") && !ps.verify("x") && ps.verify("redemption"))
    }

    // GF S01/S02 — every setter, emission order, trimming (DATA-151)
    @Test func everySetterInOrder() throws {
        let env = Env()
        env.store.reload()
        env.store.setCurrentDataFile("/U/AA/data.json")
        env.store.setPassword(hash: "H", salt: "AAECAwQFBgcICQoLDA0ODw==")
        env.store.setGoogleDriveFolder("/Users/u/My Drive")
        env.store.setSyncOnSave(true)
        env.store.setTextOnlyExport(true)
        env.store.setDarkMode(true)
        env.store.setEncryptLocalData(false)
        env.store.setAppIdentity(" Vessel-Alpha ")
        env.store.setFolderBuilderBase("/tmp/fb")
        env.store.setSharedSaveFile("/Volumes/share/aa-shared.zip")
        #expect(try env.text() == #"{"CurrentDataFile":"/U/AA/data.json","PasswordHash":"H","PasswordSalt":"AAECAwQFBgcICQoLDA0ODw==","GoogleDriveFolder":"/Users/u/My Drive","SyncOnSave":true,"DarkMode":true,"FolderBuilderBase":"/tmp/fb","SharedSaveFile":"/Volumes/share/aa-shared.zip","EncryptLocalData":false,"AppIdentity":"Vessel-Alpha","TextOnlyExport":true}"#)
        #expect(env.store.appIdentity == "Vessel-Alpha")
        env.store.reload()
        #expect(env.store.values.sharedSaveFile == "/Volumes/share/aa-shared.zip" && env.store.values.syncOnSave)
    }

    // TV: 01 §7.12 — SetAppIdentity blank → computer name; trimmed; SetSharedSaveFile(nil / blank) removes the key
    @Test func identityAndSharedSave() throws {
        let env = Env()
        env.store.reload()
        env.store.setAppIdentity("  ")
        #expect(env.store.values.appIdentity == SettingsStore.defaultIdentity())
        env.store.setAppIdentity(" Vessel-Alpha ")
        #expect(env.store.values.appIdentity == "Vessel-Alpha")
        env.store.setSharedSaveFile("/x.zip")
        #expect(try env.text().contains("SharedSaveFile"))
        env.store.setSharedSaveFile(nil)
        #expect(try !env.text().contains("SharedSaveFile") && env.store.values.sharedSaveFile == nil)
        env.store.setSharedSaveFile("/x.zip")
        env.store.setSharedSaveFile("   ")
        #expect(try !env.text().contains("SharedSaveFile"))
        env.store.setCurrentDataFile(nil)
        #expect(try !env.text().contains("CurrentDataFile"))
    }

    // GF S03 (Mac): unknown keys incl. raw numbers survive; Windows paths are flagged, not rewritten
    @Test func s03UnknownKeysAndForeignPaths() throws {
        let env = Env()
        try env.write(#"{"Foo":1,"DarkMode":true,"Nested":{"a":[1,"é"],"b":1.50},"CurrentDataFile":"C:\\x\\data.json","SharedSaveFile":"\\\\srv\\share\\aa-shared.zip"}"#)
        env.store.reload()
        #expect(env.store.values.darkMode && env.store.values.currentDataFile == #"C:\x\data.json"#)
        #expect(env.store.foreignPathKeys == ["CurrentDataFile", "SharedSaveFile"])
        #expect(env.store.values.extra.keys == ["Foo", "Nested"])
        env.store.setSyncOnSave(true)
        #expect(try env.text() == #"{"CurrentDataFile":"C:\\x\\data.json","SyncOnSave":true,"DarkMode":true,"SharedSaveFile":"\\\\srv\\share\\aa-shared.zip","Foo":1,"Nested":{"a":[1,"\u00E9"],"b":1.50}}"#)
    }

    // GF S05 / 01 §7.12 — invalid PasswordSalt → catch branch (defaults); the merge keeps "%%%"
    @Test func s05InvalidSalt() throws {
        let env = Env()
        try env.write(#"{"PasswordHash":"V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=","PasswordSalt":"%%%","DarkMode":true,"FolderBuilderBase":"/fb","AppIdentity":"Ship"}"#)
        env.store.reload()
        #expect(!env.store.values.darkMode && env.store.values.passwordHash == nil && env.store.values.appIdentity == nil)
        #expect(env.store.values.folderBuilderBase == "/fb")
        #expect(!PasswordService(settings: env.store).hasPassword)
        env.store.setDarkMode(false)
        #expect(try env.text() == #"{"PasswordHash":"V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=","PasswordSalt":"%%%","DarkMode":false,"FolderBuilderBase":"/fb","AppIdentity":"Ship"}"#)
    }

    // GF S06 (`null`), S07 (BOM), S09 (per-key tolerance), S12 (iOS keys)
    @Test func s06NullRoot() throws {
        let env = Env()
        try env.write("null")
        env.store.reload()
        #expect(env.store.values == AppSettings())
        env.store.setDarkMode(true)
        #expect(try env.text() == #"{"DarkMode":true}"#)
    }

    @Test func s07BOM() throws {
        let env = Env()
        try env.folder.write("settings.json", Data([0xEF, 0xBB, 0xBF]) + Data(#"{"DarkMode":true}"#.utf8))
        env.store.reload()
        #expect(env.store.values.darkMode)
        env.store.setSyncOnSave(true)
        #expect(try env.text() == #"{"SyncOnSave":true,"DarkMode":true}"#)     // written without a BOM
    }

    @Test func s09PerKeyTolerance() throws {
        let env = Env()
        try env.write(#"{"DarkMode":"true","Foo":1,"AppIdentity":5}"#)
        env.store.reload()
        #expect(!env.store.values.darkMode && env.store.values.appIdentity == nil)
        env.store.setSyncOnSave(true)
        #expect(try env.text() == #"{"SyncOnSave":true,"DarkMode":"true","AppIdentity":5,"Foo":1}"#)
        env.store.setDarkMode(true)
        #expect(try env.text() == #"{"SyncOnSave":true,"DarkMode":true,"AppIdentity":5,"Foo":1}"#)
    }

    @Test func s12ForeignKeysSurvive() throws {
        let env = Env()
        try env.write(#"{"iOSOnlyPref":{"x":[true,null]},"LastSyncDevice":"iPhone","DarkMode":false}"#)
        env.store.reload()
        env.store.setAppIdentity("Mac-Test")
        #expect(try env.text() == #"{"DarkMode":false,"AppIdentity":"Mac-Test","iOSOnlyPref":{"x":[true,null]},"LastSyncDevice":"iPhone"}"#)
    }

    // GeminiApiKey is never written by the Mac and preserved verbatim (DECISIONS 12)
    @Test func geminiKeyPreserved() throws {
        let env = Env()
        try env.write(#"{"GeminiApiKey":"  key-123  ","DarkMode":false}"#)
        env.store.reload()
        #expect(env.store.values.geminiApiKey == "  key-123  ")
        env.store.setDarkMode(true)
        #expect(try env.text() == #"{"DarkMode":true,"GeminiApiKey":"  key-123  "}"#)
    }

    // 13 §3.12 / DECISIONS 13 Q-5: readRawTree — {} only when absent; null → {}; anything unreadable throws
    @Test func readRawTree() throws {
        let env = Env()
        #expect(try env.store.readRawTree().count == 0)
        try env.write("null")
        #expect(try env.store.readRawTree().count == 0)
        try env.write(#"{"B":1,"A":2}"#)
        #expect(try env.store.readRawTree().keys == ["B", "A"])
        for bad in ["[]", "5", #"{"A":"#, ""] {
            try env.write(bad)
            #expect(throws: DataLoadError.self, "\(bad)") { try env.store.readRawTree() }
        }
    }

    // writeRawTree: compact + atomic; refuses over an unreadable file (D-18); no reload
    @Test func writeRawTree() throws {
        let env = Env()
        try env.write(#"{"PasswordHash":"H","PasswordSalt":"AAECAwQFBgcICQoLDA0ODw=="}"#)
        env.store.reload()
        var tree = try env.store.readRawTree()
        tree.set("DarkMode", .bool(true))
        tree.set("Zeta", .null)
        try env.store.writeRawTree(tree)
        #expect(try env.text() == #"{"PasswordHash":"H","PasswordSalt":"AAECAwQFBgcICQoLDA0ODw==","DarkMode":true,"Zeta":null}"#)
        #expect(!env.store.values.darkMode)                        // the caller reloads
        env.store.reload()
        #expect(env.store.values.darkMode)
        try env.write(#"{"PasswordHash":"H","#)
        #expect(throws: DataLoadError.self) { try env.store.writeRawTree(JSONObject()) }
        #expect(try env.text() == #"{"PasswordHash":"H","#)
        try FileManager.default.removeItem(at: env.folder.file("settings.json"))
        try env.store.writeRawTree(JSONObject([("A", .number(JSONNumber(1)))]))     // absent → written
        #expect(try env.text() == #"{"A":1}"#)
    }

    @Test func reloadAfterDeleteKeepsGeminiAndFolderBuilder() throws {
        let env = Env()
        try env.write(#"{"GeminiApiKey":"k","FolderBuilderBase":"/fb","DarkMode":true}"#)
        env.store.reload()
        try FileManager.default.removeItem(at: env.folder.file("settings.json"))
        env.store.reload()                                          // §3.1 missing-file branch quirk
        #expect(env.store.values.geminiApiKey == "k" && env.store.values.folderBuilderBase == "/fb")
        #expect(!env.store.values.darkMode)
    }

    @Test func windowsPathDetection() {
        #expect(SettingsStore.isWindowsPath(#"C:\x"#))
        #expect(SettingsStore.isWindowsPath(#"z:\"#))
        #expect(SettingsStore.isWindowsPath(#"\\srv\share"#))
        #expect(!SettingsStore.isWindowsPath("/Users/x"))
        #expect(!SettingsStore.isWindowsPath("C:/x"))
        #expect(!SettingsStore.isWindowsPath(#"\x"#))
    }
}
