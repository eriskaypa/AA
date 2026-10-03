// TV: OWNERSHIP W-SHELL in-worktree acceptance "file-flow unit tests over F1/F2 code with a temp AppFolder": Save a
//     Copy As stamps only the copy (03 SHELL-061, 01 DATA-032, D-14); the encrypt toggle re-saves the active file in
//     the new form (SHELL-065, DATA-070); identity blank → default (SHELL-068, DATA-048, 06 BUILD-145 B1, A25, A27);
//     password change requires the current one (SHELL-101, DATA-080, DECISIONS 01 Q-4); Lock now (SHELL-102); text
//     only (SHELL-072, DATA-042); import placement / external lock / export destination / Finder documents
//     (SHELL-063, DATA-034, DATA-179, DATA-040, SHELL-185); the SHELL-196 / Q-16 encryption guard.
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct ShellXDataFlowsTests {
    private static let clock = FixedClock(local: "2026-09-30T14:03:12.1234567", zone: TZ.athens)

    private func make(_ data: AppData? = nil) -> StoreFactory.Made {
        StoreFactory.make(data: data, clock: Self.clock)
    }

    private func root(_ url: URL) throws -> JSONObject {
        guard case .object(let o) = try JSONParser.parse(try Data(contentsOf: url)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return o
    }

    // MARK: Save a Copy As

    @Test func saveCopyStampsOnlyTheCopy() throws {
        let data = AppData()
        data.equipment.append(Equipment(name: "Main engine"))
        let previous = NetDateTime(year: 2026, month: 9, day: 1, hour: 8, kind: .local)
        data.lastModified = previous
        let m = make(data)
        let activeBefore = m.dataStore.currentDataFile
        let out = m.folder.file("exports/aa-data.json")
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)

        try ShellXDataFlows.saveCopy(m.store, to: out)

        let copy = try root(out)
        guard case .string(let stamp)? = copy.rawValue(forKey: "LastModified") else {
            Issue.record("the copy has no LastModified")
            return
        }
        #expect(stamp.hasPrefix("2026-09-30T14:03:12.1234567"))         // the copy is stamped = now
        #expect(copy.rawValue(forKey: "SchemaVersion") == .number(JSONNumber(1)))
        #expect(m.store.data.lastModified == previous)                 // the live stamp is untouched (D-14)
        #expect(!m.store.isDirty)
        #expect(m.dataStore.currentDataFile == activeBefore)           // the active file does not change
        #expect(!FileManager.default.fileExists(atPath: m.dataStore.defaultDataFile.path))
    }

    @Test func saveCopyIsPlaintextEvenWhenEncryptionIsOn() throws {
        let m = make()
        m.dataStore.settings.setEncryptLocalData(true)
        let out = m.folder.file("copy.json")                          // inside AppFolder, still never encrypted
        try ShellXDataFlows.saveCopy(m.store, to: out)
        let bytes = try Data(contentsOf: out)
        #expect(LocalEncryption.classify(bytes) == .plain)
        #expect(bytes.first == UInt8(ascii: "{"))
    }

    // MARK: Encrypt local data file

    @Test func encryptToggleRewritesTheActiveFileInTheNewForm() throws {
        let m = make()
        m.store.data.lastModified = NetDateTime(year: 2026, month: 1, day: 1, kind: .local)
        try ShellXDataFlows.setEncryptLocalData(true, store: m.store)
        let file = m.dataStore.currentDataFile
        var bytes = try Data(contentsOf: file)
        #expect(LocalEncryption.classify(bytes) == .mac)
        #expect(bytes.prefix(8) == LocalEncryption.macMagic)
        #expect(m.dataStore.settings.values.encryptLocalData)
        #expect(m.store.data.lastModified == Self.clock.now())       // stamped = now (DATA-070)
        let settingsText = try String(contentsOf: m.dataStore.settingsFile, encoding: .utf8)
        #expect(settingsText.contains("\"EncryptLocalData\":true"))
        // The encrypted file reads back through the same key.
        let plain = try DataStore.readDataBytes(file, key: m.dataStore.localEncryptionKeyIfEnabled(for: file))
        #expect(plain.first == UInt8(ascii: "{"))

        try ShellXDataFlows.setEncryptLocalData(false, store: m.store)
        bytes = try Data(contentsOf: file)
        #expect(LocalEncryption.classify(bytes) == .plain)
        #expect(!m.dataStore.settings.values.encryptLocalData)
    }

    @Test func encryptionStatusTexts() {
        #expect(ShellXText.encryptionStatus(true) == "Local data file is now encrypted at rest.")
        #expect(ShellXText.encryptionStatus(false) == "Local data file is now plaintext.")
    }

    // MARK: SHELL-196 guard

    @Test func foreignEncryptionGuard() throws {
        #expect(ShellXDataFlows.needsForeignEncryptionPrompt(settingOn: true, fileClass: .plain, hasLocalKey: false))
        #expect(!ShellXDataFlows.needsForeignEncryptionPrompt(settingOn: false, fileClass: .plain, hasLocalKey: false))
        #expect(!ShellXDataFlows.needsForeignEncryptionPrompt(settingOn: true, fileClass: .mac, hasLocalKey: false))
        #expect(!ShellXDataFlows.needsForeignEncryptionPrompt(settingOn: true, fileClass: .windowsDPAPI, hasLocalKey: false))
        #expect(!ShellXDataFlows.needsForeignEncryptionPrompt(settingOn: true, fileClass: .plain, hasLocalKey: true))
        #expect(!ShellXDataFlows.needsForeignEncryptionPrompt(settingOn: true, fileClass: nil, hasLocalKey: false))

        let m = make()
        try m.folder.write("data.json", Goldens.freshDB)
        #expect(!ShellXDataFlows.foreignEncryptionPromptNeeded(m.dataStore))    // setting off
        m.dataStore.settings.setEncryptLocalData(true)                          // e.g. arrived from Windows
        #expect(ShellXDataFlows.foreignEncryptionPromptNeeded(m.dataStore))     // plaintext file, no key yet
        _ = try LocalEncryption.key(secrets: m.secrets, create: true)
        #expect(!ShellXDataFlows.foreignEncryptionPromptNeeded(m.dataStore))    // this Mac already has a key
    }

    @Test func foreignEncryptionGuardIgnoresMissingFiles() {
        let m = make()
        m.dataStore.settings.setEncryptLocalData(true)
        #expect(!ShellXDataFlows.foreignEncryptionPromptNeeded(m.dataStore))
    }

    // MARK: App identity (B1)

    @Test func identityBlankResetsToTheMachineName() throws {
        let m = make()
        let settings = m.dataStore.settings
        #expect(ShellXDataFlows.setAppIdentity("  Bridge-Mac  ", settings: settings) == "Bridge-Mac")
        #expect(settings.values.appIdentity == "Bridge-Mac")
        #expect(ShellXText.identitySet(settings.appIdentity) == "App identity set: Bridge-Mac")
        for blank in ["", "   ", "\t\n"] {
            let stored = ShellXDataFlows.setAppIdentity(blank, settings: settings)
            #expect(stored == SettingsStore.defaultIdentity())
            #expect(settings.values.appIdentity == SettingsStore.defaultIdentity())   // the literal name is stored
        }
        let text = try String(contentsOf: m.dataStore.settingsFile, encoding: .utf8)
        #expect(text.contains("\"AppIdentity\":"))
    }

    // MARK: Password and Lock now

    @Test func passwordChangeRequiresTheCurrentPassword() throws {
        let m = make()
        let passwords = PasswordService(settings: m.dataStore.settings)
        #expect(!passwords.hasPassword)
        #expect(try ShellXDataFlows.setPassword("", current: nil, passwords: passwords) == nil)   // empty → nothing
        #expect(!passwords.hasPassword)
        #expect(try ShellXDataFlows.setPassword("abcd", current: nil, passwords: passwords) != nil)
        #expect(passwords.hasPassword && passwords.isUnlocked)
        #expect(passwords.verify("abcd"))

        #expect(throws: PasswordError.wrongCurrentPassword) {
            try ShellXDataFlows.setPassword("wxyz", current: nil, passwords: passwords)
        }
        #expect(throws: PasswordError.wrongCurrentPassword) {
            try ShellXDataFlows.setPassword("wxyz", current: "nope", passwords: passwords)
        }
        #expect(passwords.verify("abcd"))                             // unchanged after the refusals
        #expect(throws: PasswordError.tooShort) {
            try ShellXDataFlows.setPassword("abc", current: "abcd", passwords: passwords)
        }
        #expect(try ShellXDataFlows.setPassword("wxyz", current: "abcd", passwords: passwords) != nil)
        #expect(passwords.verify("wxyz") && !passwords.verify("abcd"))
        // The master password is accepted as the current one (DECISIONS 01 Q-1).
        #expect(try ShellXDataFlows.setPassword("efgh", current: PasswordHashing.masterPassword, passwords: passwords) != nil)
        let text = try String(contentsOf: m.dataStore.settingsFile, encoding: .utf8)
        #expect(text.contains("\"PasswordHash\":") && text.contains("\"PasswordSalt\":"))
        #expect(ShellXText.passwordUpdated == "App password updated.")
    }

    @Test func lockNowForgetsTheSessionAndEveryItemUnlock() async {
        let m = make()
        let passwords = PasswordService(settings: m.dataStore.settings)
        _ = try? passwords.setPassword("abcd", current: nil)
        let locks = ItemLockService()
        let item = Equipment(name: "Cargo pump")
        locks.protect(item, password: "pump", hint: nil)
        #expect(await locks.tryUnlock(item, password: "pump"))
        #expect(passwords.isUnlocked && !locks.isGated(item))

        let status = ShellXDataFlows.lockNow(passwords: passwords, locks: locks)
        #expect(status == "Locked. Locked containers and entries will require re-unlocking.")
        #expect(!passwords.isUnlocked)
        #expect(locks.unlockedIDs.isEmpty && locks.isGated(item))
    }

    // MARK: Export text only

    @Test func textOnlyToggle() throws {
        let m = make()
        let settings = m.dataStore.settings
        #expect(ShellXDataFlows.setTextOnlyExport(true, settings: settings) == "Exports carry text only (no attachments)")
        #expect(settings.values.textOnlyExport)
        #expect(try String(contentsOf: m.dataStore.settingsFile, encoding: .utf8).contains("\"TextOnlyExport\":true"))
        #expect(ShellXDataFlows.setTextOnlyExport(false, settings: settings) == "Exports carry everything, attachments included")
        #expect(!settings.values.textOnlyExport)
    }

    // MARK: Import from file, bundles

    @Test func importPlacementAndExternalLockRules() {
        let m = make()
        let ds = m.dataStore
        #expect(!ShellXDataFlows.asksImportPlacement(for: ds.defaultDataFile, dataStore: ds))
        #expect(ShellXDataFlows.asksImportPlacement(for: m.folder.file("conflicts/data-theirs.json"), dataStore: ds))
        let external = URL(fileURLWithPath: "/Volumes/STICK/AA Data/data.json")
        #expect(ShellXDataFlows.asksImportPlacement(for: external, dataStore: ds))
        #expect(ShellXDataFlows.needsExternalLock(for: external, dataStore: ds))
        #expect(!ShellXDataFlows.needsExternalLock(for: m.folder.file("old.json"), dataStore: ds))

        #expect(!ShellXDataFlows.externalLockRefuses(.editor))
        #expect(!ShellXDataFlows.externalLockRefuses(.unguarded("SMB volume")))
        #expect(ShellXDataFlows.externalLockRefuses(.runningHere(pid: 42)))
        #expect(ShellXDataFlows.externalLockRefuses(.otherUser("eriskay")))
        #expect(ShellXDataFlows.externalLockRefuses(.sameUserNoApp(pid: 42)))
        #expect(ShellXDataFlows.externalLockRefuses(.remote(host: "BRIDGE-PC", lastSeen: Date(), stale: false)))
        #expect(ShellXText.externalFileInUse == "That file is already open in another copy of AA.")
    }

    @Test func importFromFileCopyIntoFolderAndUseInPlace() throws {
        let m = make()
        let source = TempFolder("aa-import-src")
        let incoming = AppData()
        incoming.equipment.append(Equipment(name: "Steering gear"))
        try m.dataStore.saveTo(incoming, url: source.file("stick.json"))

        // DECISIONS 01 Q-5 default: copy into the AA folder; the original stays untouched.
        let originalBytes = try source.read("stick.json")
        let target = try m.dataStore.adoptExternalDataFile(source.file("stick.json"), copyIntoAppFolder: true)
        #expect(target == m.dataStore.defaultDataFile)
        #expect(m.dataStore.currentDataFile == m.dataStore.defaultDataFile)
        #expect(try source.read("stick.json") == originalBytes)
        #expect(m.dataStore.load().equipment.map(\.name) == ["Steering gear"])

        // Windows behaviour: use in place — the chosen file becomes the active data file.
        let inPlace = try m.dataStore.adoptExternalDataFile(source.file("stick.json"), copyIntoAppFolder: false)
        #expect(inPlace.standardizedFileURL.path == source.file("stick.json").standardizedFileURL.path)
        #expect(m.dataStore.currentDataFile.standardizedFileURL.path == inPlace.standardizedFileURL.path)
        #expect(ShellStatusText.loaded(m.dataStore.currentDataFile.path).hasPrefix("Loaded — "))
    }

    @Test func exportDestinationAndDocuments() {
        let m = make()
        #expect(!ShellXDataFlows.exportDestinationAllowed(m.folder.file("backup.zip"), dataStore: m.dataStore))
        #expect(!ShellXDataFlows.exportDestinationAllowed(m.folder.file("files/x.zip"), dataStore: m.dataStore))
        #expect(ShellXDataFlows.exportDestinationAllowed(URL(fileURLWithPath: "/Volumes/STICK/aa.zip"),
                                                         dataStore: m.dataStore))
        #expect(ShellXText.exportInsideAppFolder == "Choose a destination outside the AA data folder.")
        #expect(ShellXDataFlows.isBundleDocument(URL(fileURLWithPath: "/x/AA-backup-iOS.aaz")))
        #expect(ShellXDataFlows.isBundleDocument(URL(fileURLWithPath: "/x/aa-data.ZIP")))
        #expect(!ShellXDataFlows.isBundleDocument(URL(fileURLWithPath: "/x/data.json")))
        #expect(!ShellXDataFlows.isBundleDocument(URL(fileURLWithPath: "/x/Schedule-A.aasched.json")))
    }

    // TV: 01 DATA-174 / MP.7 R-1 — "Dark mode on. (this window only — read-only)" (REQ-W-PERSIST-02)
    @Test func settingStatusSuffixWhileWriteGated() {
        #expect(ShellXText.settingStatus(ShellStatusText.darkModeOn, gated: true) == "Dark mode on. (this window only — read-only)")
        #expect(ShellXText.settingStatus(ShellStatusText.darkModeOn, gated: false) == "Dark mode on.")
    }
}
