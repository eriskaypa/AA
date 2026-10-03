// TV: 01 §7.1 (PBKDF2 / password hash, Verify truth tables), 01 §7.2 (`enc:` blobs a–g), 04 §7.8 (lock hashes,
//     verify table, hint trimming, dialog validation, gate transitions), 01 §6.11 (Base64 / constant time),
//     01 DATA-080…084, DATA-090…094.
import Foundation
import Testing
@testable import AACore

private enum CryptoFixture {
    /// Salt S = bytes 00 01 … 0F.
    static let salt = Data(0..<16)
    static let saltB64 = "AAECAwQFBgcICQoLDA0ODw=="
    static let iv = Data(0x10...0x1F)
    static let correctHorseHash = "V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk="

    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
}

@Suite struct CryptoPrimitiveTests {
    // TV: 01 §7.1 primitive sanity (published PBKDF2-HMAC-SHA256 vector)
    @Test func pbkdf2Sanity() {
        let k = PBKDF2.sha256(password: "password", salt: Data("salt".utf8), iterations: 1, length: 32)
        #expect(CryptoFixture.hex(k) == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    }

    // TV: 01 §7.1 table — hash == encKey == K[0..<32]; macKey = K[32..<64]
    @Test(arguments: [
        ("correct horse", "V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=",
         "57f2c2f0739748d516419b062a884666323c583ea4ae165504a81f7b53c62a09",
         "a24b05529582a1a9eceedbf9bf394d270fdeebe961f37db8db486f700aad6dee"),
        ("redemption", "1+930ag9iT2JBP4/zxFyJccLLHJhA+CvurBLnPPS7Hc=",
         "d7ef77d1a83d893d8904fe3fcf117225c70b2c726103e0afbab04b9cf3d2ec77",
         "1d40448184e53d690099f505a61c54369a2beacf2dbf2eb8aa13a0b567e4f01c"),
        ("p\u{E4}ssw\u{F6}rd", "trmn14eaJqetmcWSJJwUWVLKUOyf765hiEQzeYnvalM=",
         "b6b9a7d7879a26a7ad99c592249c145952ca50ec9fefae618844337989ef6a53",
         "f33ce18ee9f1fdc6dc854372472823da1c597980ec4492c872716993d03e97af"),
    ])
    func passwordHashTable(_ password: String, _ hashB64: String, _ encHex: String, _ macHex: String) {
        let hash = PasswordHashing.hash(password: password, salt: CryptoFixture.salt)
        #expect(NetBase64.encode(hash) == hashB64)
        #expect(CryptoFixture.hex(hash) == encHex)
        let k = LegacyBodyCrypto.keys(password: password, salt: CryptoFixture.salt)
        #expect(CryptoFixture.hex(k.enc) == encHex)
        #expect(CryptoFixture.hex(k.mac) == macHex)
    }

    @Test func constants() {
        #expect(PasswordHashing.iterations == 100_000 && PasswordHashing.saltSize == 16 && PasswordHashing.keySize == 32)
        #expect(PasswordHashing.masterPassword == "redemption")
        #expect(PasswordHashing.newSalt().count == 16)
        #expect(PasswordHashing.newSalt() != PasswordHashing.newSalt())
        #expect(SecureRandom.bytes(0).isEmpty && SecureRandom.bytes(33).count == 33)
    }

    @Test func constantTime() {
        #expect(ConstantTime.equals(Data([1, 2, 3]), Data([1, 2, 3])))
        #expect(!ConstantTime.equals(Data([1, 2, 3]), Data([1, 2, 4])))
        #expect(!ConstantTime.equals(Data([1, 2]), Data([1, 2, 3])))           // length mismatch → false
        #expect(ConstantTime.equals(Data(), Data()))
    }

    // .NET Convert.FromBase64String: whitespace ignored, anything else strict.
    @Test func netBase64() {
        #expect(NetBase64.decode(CryptoFixture.saltB64) == CryptoFixture.salt)
        #expect(NetBase64.decode(" AAEC\nAwQF\tBgcI\r\nCQoLDA0ODw== ") == CryptoFixture.salt)
        #expect(NetBase64.decode("") == Data())
        for bad in ["not base64!", "%%%", "AAE", "AA=A", "A===", "AAECAw=="+"x"] {
            #expect(NetBase64.decode(bad) == nil, "\(bad)")
        }
        #expect(NetBase64.encode(Data([0xFB, 0xFF])) == "+/8=")
        #expect(NetBase64.decode("+/8=") == Data([0xFB, 0xFF]))
    }

    @Test func aesCbcAndHmac() throws {
        let key = Data(repeating: 7, count: 32)
        let ct = try AESCBC.encrypt(Data("hello".utf8), key: key, iv: CryptoFixture.iv)
        #expect(ct.count == 16)                                                  // PKCS#7 pads to one block
        #expect(try AESCBC.decrypt(ct, key: key, iv: CryptoFixture.iv) == Data("hello".utf8))
        #expect(throws: CryptoError.self) { try AESCBC.decrypt(Data([1, 2, 3]), key: key, iv: CryptoFixture.iv) }
        // RFC 4231 test case 2
        let mac = HMACSHA256.mac(Data("what do ya want for nothing?".utf8), key: Data("Jefe".utf8))
        #expect(CryptoFixture.hex(mac) == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    }
}

@Suite struct LegacyBodyCryptoTests {
    static let rows: [(String, String)] = [
        ("", "enc:EBESExQVFhcYGRobHB0eHw4QRSqEYezPC65cF1E8B3R1ApbahQo1UxRvd3kio+7TgvGYrwMij8bZDWxhSRRHsw=="),
        ("<Section>hi</Section>", "enc:EBESExQVFhcYGRobHB0eHxJkbpvR5sxlvHs4LU1Zlc/8FgD7jQznyIZndaufj6DG8Ti6ErBbvtnRWs5/oiOkMApZpCT7lzAUZnjCNe73CmY="),
        ("", "enc:EBESExQVFhcYGRobHB0eHxVqH9CC+wbDQym8EpaLqTzI1CGEYvJ2gETXttL9DZejPrh/qVUIZuxQ+8nwx/+CxQ=="),
        ("<Section>hi</Section>", "enc:EBESExQVFhcYGRobHB0eH8BIPRoz9iURWzr6BNWef9ZK5CiJh6kBlV01N1xabuu0pXm6TefrY/0XFRCF8+BkC6FJF5y0PoPkSQT/8rTn8rg="),
    ]

    // TV: 01 §7.2 (a) Encrypt with injected IV reproduces rows 1–2 (Windows form, BOM-prefixed)
    @Test func encryptReproducesWindowsBlobs() {
        for (plain, blob) in Self.rows.prefix(2) {
            #expect(LegacyBodyCrypto.encrypt(plain, password: "correct horse", saltBase64: CryptoFixture.saltB64,
                                             iv: CryptoFixture.iv) == blob)
        }
    }

    // TV: 01 §7.2 (b) Decrypt of all four rows (BOM stripped)
    @Test func decryptAllRows() {
        for (plain, blob) in Self.rows {
            #expect(LegacyBodyCrypto.decrypt(blob, password: "correct horse", saltBase64: CryptoFixture.saltB64) == plain)
        }
        let random = LegacyBodyCrypto.encrypt("Pump \u{2192} main \u{1F600}", password: "pw", saltBase64: CryptoFixture.saltB64)
        #expect(random.hasPrefix("enc:"))
        #expect(LegacyBodyCrypto.decrypt(random, password: "pw", saltBase64: CryptoFixture.saltB64) == "Pump \u{2192} main \u{1F600}")
    }

    // TV: 01 §7.2 (c) any flipped byte → nil
    @Test func tamperingIsDetected() throws {
        let blob = Self.rows[1].1
        let bytes = try #require(NetBase64.decode(String(blob.dropFirst(4))))
        for i in [0, 15, 16, 31, bytes.count - 33, bytes.count - 1] {
            var b = [UInt8](bytes)
            b[i] ^= 0x01
            let tampered = "enc:" + NetBase64.encode(Data(b))
            #expect(LegacyBodyCrypto.decrypt(tampered, password: "correct horse", saltBase64: CryptoFixture.saltB64) == nil)
        }
        #expect(LegacyBodyCrypto.decrypt(blob, password: "correct horse", saltBase64: "AAECAwQFBgcICQoLDA0ODg==") == nil)
        #expect(LegacyBodyCrypto.decrypt("enc:%%%%", password: "correct horse", saltBase64: CryptoFixture.saltB64) == nil)
        #expect(LegacyBodyCrypto.decrypt(blob, password: "correct horse", saltBase64: "not base64!") == nil)
    }

    // TV: 01 §7.2 (d) master password cannot decrypt (documents D-4); (e) 63-byte payload → nil; (f) case-sensitive prefix
    @Test func masterShortAndPrefix() {
        #expect(LegacyBodyCrypto.decrypt(Self.rows[1].1, password: "redemption", saltBase64: CryptoFixture.saltB64) == nil)
        let short = "enc:" + NetBase64.encode(Data(repeating: 0xAB, count: 63))
        #expect(LegacyBodyCrypto.decrypt(short, password: "correct horse", saltBase64: CryptoFixture.saltB64) == nil)
        #expect(!LegacyBodyCrypto.isEncrypted("ENC:" + Self.rows[1].1.dropFirst(4)))
        #expect(!LegacyBodyCrypto.isEncrypted(""))
        #expect(!LegacyBodyCrypto.isEncrypted("enc"))
        #expect(LegacyBodyCrypto.isEncrypted("enc:"))
        #expect(LegacyBodyCrypto.decrypt("ENC:" + Self.rows[1].1.dropFirst(4), password: "correct horse",
                                         saltBase64: CryptoFixture.saltB64) == nil)
    }

    // TV: 01 §7.2 (g) the AES-CBC output of row 2 begins EF BB BF 3C 53 65 63
    @Test func manualDecryptShowsBOM() throws {
        let bytes = try #require(NetBase64.decode(String(Self.rows[1].1.dropFirst(4))))
        let iv = bytes.prefix(16), ct = bytes.dropFirst(16).dropLast(32)
        let k = LegacyBodyCrypto.keys(password: "correct horse", salt: CryptoFixture.salt)
        let plain = try AESCBC.decrypt(Data(ct), key: k.enc, iv: Data(iv))
        #expect(Array(plain.prefix(7)) == [0xEF, 0xBB, 0xBF, 0x3C, 0x53, 0x65, 0x63])
    }

    // .NET StreamReader BOM detection (01 §4.7)
    @Test func bomDetection() {
        #expect(LegacyBodyCrypto.decodeWithBOMDetection(Data([0xEF, 0xBB, 0xBF, 0x41])) == "A")
        #expect(LegacyBodyCrypto.decodeWithBOMDetection(Data([0xFF, 0xFE, 0x41, 0x00])) == "A")
        #expect(LegacyBodyCrypto.decodeWithBOMDetection(Data([0xFE, 0xFF, 0x00, 0x41])) == "A")
        #expect(LegacyBodyCrypto.decodeWithBOMDetection(Data([0xFF, 0xFE, 0x00, 0x00, 0x41, 0, 0, 0])) == "A")
        #expect(LegacyBodyCrypto.decodeWithBOMDetection(Data([0x41, 0xFF])) == "A\u{FFFD}")
    }
}

@MainActor @Suite struct PasswordServiceTests {
    func service(hash: String?, salt: String?) throws -> (PasswordService, TempFolder) {
        let folder = TempFolder()
        var o = JSONObject()
        if let hash { o.set("PasswordHash", .string(hash)) }
        if let salt { o.set("PasswordSalt", .string(salt)) }
        try folder.write("settings-file.json", try JSONWriter.data(.object(o)))
        let settings = SettingsStore(fileURL: folder.file("settings-file.json"), secrets: InMemorySecretStore())
        settings.reload()
        return (PasswordService(settings: settings), folder)
    }

    // TV: 01 §7.1 Verify truth table
    @Test func verifyWithPassword() throws {
        let (ps, _) = try service(hash: CryptoFixture.correctHorseHash, salt: CryptoFixture.saltB64)
        #expect(ps.hasPassword)
        #expect(ps.verify("correct horse"))
        #expect(!ps.verify("Correct horse"))
        #expect(!ps.verify(""))
        #expect(ps.verify("redemption"))
        #expect(!ps.verify("Redemption"))
    }

    @Test func verifyWithoutPassword() throws {
        let (ps, _) = try service(hash: nil, salt: nil)
        #expect(!ps.hasPassword)
        #expect(ps.verify("redemption"))
        #expect(!ps.verify("correct horse"))
        #expect(!ps.verify(""))
        let (half, _) = try service(hash: CryptoFixture.correctHorseHash, salt: nil)
        #expect(!half.hasPassword)
        let (empty, _) = try service(hash: "", salt: CryptoFixture.saltB64)
        #expect(!empty.hasPassword)
    }

    // TV: 01 §7.12 — an invalid PasswordSalt → the catch branch: defaults, HasPassword false
    @Test func invalidSaltMeansNoPassword() throws {
        let (ps, _) = try service(hash: CryptoFixture.correctHorseHash, salt: "%%%")
        #expect(!ps.hasPassword)
        #expect(!ps.verify("correct horse"))
        #expect(ps.verify("redemption"))
    }

    // DATA-081 / DATA-082: unlock, lock, reload forgets the session; master unlock
    @Test func sessionLifecycle() throws {
        let (ps, _) = try service(hash: CryptoFixture.correctHorseHash, salt: CryptoFixture.saltB64)
        #expect(!ps.isUnlocked)
        #expect(!ps.unlock("wrong"))
        #expect(!ps.isUnlocked)
        #expect(ps.unlock("correct horse"))
        #expect(ps.isUnlocked)
        #expect(ps.decryptLegacyBody(LegacyBodyCryptoTests.rows[1].1) == "<Section>hi</Section>")
        ps.lock()
        #expect(!ps.isUnlocked)
        #expect(ps.decryptLegacyBody(LegacyBodyCryptoTests.rows[1].1) == nil)
        #expect(ps.unlock("redemption"))                                    // master unlocks …
        #expect(ps.decryptLegacyBody(LegacyBodyCryptoTests.rows[1].1) == nil)   // … but cannot decrypt (D-4)
        #expect(ps.unlock("correct horse"))
        ps.settings.reload()                                                // every LoadSettings forgets the session
        #expect(!ps.isUnlocked)
    }

    // DATA-080 + DECISIONS 01 Q-4: setting a password needs the current one when one exists; joint write
    @Test func setPassword() throws {
        let (ps, folder) = try service(hash: nil, salt: nil)
        #expect(throws: PasswordError.tooShort) { try ps.setPassword("abc", current: nil) }
        try ps.setPassword("hunter22", current: nil)
        #expect(ps.hasPassword && ps.isUnlocked)
        let file = try JSONParser.parse(folder.read("settings-file.json")).objectValue
        let salt = try #require(file?["PasswordSalt"]?.stringValue.flatMap(NetBase64.decode))
        #expect(salt.count == 16)
        #expect(file?["PasswordHash"]?.stringValue == NetBase64.encode(PasswordHashing.hash(password: "hunter22", salt: salt)))
        #expect(throws: PasswordError.wrongCurrentPassword) { try ps.setPassword("newpass1", current: nil) }
        #expect(throws: PasswordError.wrongCurrentPassword) { try ps.setPassword("newpass1", current: "nope") }
        try ps.setPassword("newpass1", current: "hunter22")
        #expect(ps.verify("newpass1") && !ps.verify("hunter22"))
        try ps.setPassword("newpass2", current: "redemption")                // the master password is accepted
        #expect(ps.verify("newpass2"))
    }

    // 01 §8.1 D-5 fix: changing the password first migrates every live legacy `enc:` body it can decrypt with the
    // OLD salt (typed current password, then the session password), saves the data file, then re-salts.
    @Test func setPasswordMigratesLegacyBodiesBeforeResalting() throws {
        let salt = CryptoFixture.saltB64
        let mine = LegacyBodyCrypto.encrypt("<Section>mine</Section>", password: "correct horse", saltBase64: salt)
        let foreign = LegacyBodyCrypto.encrypt("<Section>other</Section>", password: "other pw", saltBase64: salt)
        let data = AppData()
        let e = Equipment(name: "Pump")
        e.container.richTextXaml = mine
        e.container.isLocked = true
        let comp = Component(name: "Seal", container: Container(richTextXaml: foreign))
        e.components.append(comp)
        let t = TaskItem(name: "Plain")
        t.container.richTextXaml = "<Section>plain</Section>"
        data.equipment.append(e); data.tasks.append(t)
        let made = StoreFactory.make(data: data)
        made.dataStore.settings.setPassword(hash: CryptoFixture.correctHorseHash, salt: salt)
        let ps = PasswordService(settings: made.dataStore.settings)

        #expect(ps.undecryptableLegacyBodyCount(in: made.store, current: "correct horse") == 1)
        #expect(ps.undecryptableLegacyBodyCount(in: made.store, current: "redemption") == 2)   // master: no key (D-4)
        let r = try ps.setPassword("newpass1", current: "correct horse", migratingLegacyBodiesIn: made.store)
        #expect(r == LegacyBodyMigration(migrated: 1, undecryptable: 1))
        #expect(e.container.richTextXaml == "<Section>mine</Section>")
        #expect(!e.container.isLocked)
        #expect(comp.container.richTextXaml == foreign)                     // kept (never replaced by "")
        #expect(t.container.richTextXaml == "<Section>plain</Section>")
        #expect(ps.verify("newpass1") && settings(ps) != salt)
        let saved = made.dataStore.load()                                   // written before the re-salt
        #expect(saved.equipment.first?.container.richTextXaml == "<Section>mine</Section>")
        #expect(LegacyBodyMigration.orphanWarning(count: 0) == nil)
        #expect(LegacyBodyMigration.orphanWarning(count: 1)?.hasPrefix("1 note encrypted by an older AA build") == true)
        #expect(LegacyBodyMigration.orphanWarning(count: 2)?.contains("they can no longer be opened") == true)
    }

    // D-5: the session password is a candidate too (current typed as the master password)
    @Test func setPasswordMigratesWithSessionPassword() throws {
        let salt = CryptoFixture.saltB64
        let data = AppData()
        let v = Vessel(name: "MV X")
        v.container.richTextXaml = LegacyBodyCrypto.encrypt("<Section>v</Section>", password: "correct horse", saltBase64: salt)
        data.vessels.append(v)
        let made = StoreFactory.make(data: data)
        made.dataStore.settings.setPassword(hash: CryptoFixture.correctHorseHash, salt: salt)
        let ps = PasswordService(settings: made.dataStore.settings)
        #expect(ps.unlock("correct horse"))
        let r = try ps.setPassword("newpass1", current: "redemption", migratingLegacyBodiesIn: made.store)
        #expect(r == LegacyBodyMigration(migrated: 1, undecryptable: 0))
        #expect(v.container.richTextXaml == "<Section>v</Section>")
    }

    // D-5: a migration that cannot be saved leaves the password and salt unchanged
    @Test func setPasswordKeepsSaltWhenMigrationCannotBeSaved() throws {
        let salt = CryptoFixture.saltB64
        let data = AppData()
        let e = Equipment(name: "Pump")
        let blob = LegacyBodyCrypto.encrypt("<Section>mine</Section>", password: "correct horse", saltBase64: salt)
        e.container.richTextXaml = blob
        data.equipment.append(e)
        let made = StoreFactory.make(data: data)
        made.dataStore.settings.setPassword(hash: CryptoFixture.correctHorseHash, salt: salt)
        let ps = PasswordService(settings: made.dataStore.settings)
        made.store.suspendSaving = true
        #expect(throws: PasswordError.self) {
            try ps.setPassword("newpass1", current: "correct horse", migratingLegacyBodiesIn: made.store)
        }
        #expect(e.container.richTextXaml == blob)                           // nothing touched
        #expect(ps.verify("correct horse") && !ps.verify("newpass1") && settings(ps) == salt)
        made.store.suspendSaving = false
        made.store.pauseWrites(reason: .externalChange)
        #expect(throws: PasswordError.self) {
            try ps.setPassword("newpass1", current: "correct horse", migratingLegacyBodiesIn: made.store)
        }
        #expect(settings(ps) == salt)
        // Without a store (no data to migrate) the change goes through as before.
        try ps.setPassword("newpass1", current: "correct horse")
        #expect(settings(ps) != salt)
        #expect(PasswordError.legacyBodiesNotSaved("x").message.hasPrefix("The password was not changed."))
    }

    private func settings(_ ps: PasswordService) -> String? { ps.settings.values.passwordSalt }

    // TV: 04 §7.8 lock dialog validation (also DATA-080)
    @Test func validation() {
        #expect(PasswordService.validationMessage(password: "", confirm: "") == "Password cannot be empty.")
        #expect(PasswordService.validationMessage(password: "abc", confirm: "abc") == "Password must be at least 4 characters.")
        #expect(PasswordService.validationMessage(password: "abcd", confirm: "abce") == "Passwords do not match.")
        #expect(PasswordService.validationMessage(password: "\u{1F600}\u{1F600}", confirm: "\u{1F600}\u{1F600}") == nil)
        #expect(PasswordService.validationMessage(password: "abcd", confirm: "abcd") == nil)
        #expect(PasswordError.tooShort.message == "Password must be at least 4 characters.")
        #expect(PasswordError.mismatch.message == "Passwords do not match.")
        #expect(PasswordError.wrongCurrentPassword.message == "Wrong password.")
    }
}

@MainActor @Suite struct ItemLockServiceTests {
    // TV: 04 §7.8 expected LockHash values (salt S)
    @Test(arguments: [
        ("hunter22", "murxLdSppVnVeZbxy4IbgWXYCiM9PftQyX18mD8jBNE="),
        ("p\u{E4}ssw\u{F6}rd", "trmn14eaJqetmcWSJJwUWVLKUOyf765hiEQzeYnvalM="),
        ("abcd", "x/xHrQBjPHyVN9hXauwnarZ7Z/VWb/IqpliZy1EAn64="),
        ("redemption", "1+930ag9iT2JBP4/zxFyJccLLHJhA+CvurBLnPPS7Hc="),
    ])
    func lockHashes(_ password: String, _ expected: String) {
        #expect(NetBase64.encode(PasswordHashing.hash(password: password, salt: CryptoFixture.salt)) == expected)
    }

    // TV: 04 §7.8 Verify table and 01 §7.1 ItemLockService rows
    @Test func verifyTable() {
        let h = "murxLdSppVnVeZbxy4IbgWXYCiM9PftQyX18mD8jBNE=", s = CryptoFixture.saltB64
        #expect(ItemLockService.verify(password: "hunter22", hashBase64: h, saltBase64: s))
        #expect(!ItemLockService.verify(password: "Hunter22", hashBase64: h, saltBase64: s))
        #expect(!ItemLockService.verify(password: "", hashBase64: h, saltBase64: s))
        #expect(ItemLockService.verify(password: "redemption", hashBase64: h, saltBase64: s))
        #expect(!ItemLockService.verify(password: "Redemption", hashBase64: h, saltBase64: s))
        #expect(ItemLockService.verify(password: "redemption", hashBase64: "", saltBase64: ""))   // unprotected + master
        #expect(!ItemLockService.verify(password: "x", hashBase64: "", saltBase64: ""))
        #expect(!ItemLockService.verify(password: "hunter22", hashBase64: h, saltBase64: "not base64!"))   // no crash
        #expect(ItemLockService.verify(password: "correct horse", hashBase64: CryptoFixture.correctHorseHash, saltBase64: s))
        #expect(!ItemLockService.verify(password: "Correct horse", hashBase64: CryptoFixture.correctHorseHash, saltBase64: s))
    }

    // TV: 04 §7.8 hint trimming and gate transitions (DATA-090…093)
    @Test func protectAndGate() async throws {
        let locks = ItemLockService()
        let a = TaskItem(name: "A"), b = Equipment(name: "B")
        #expect(!a.isLockProtected && !locks.isGated(a))
        locks.protect(a, password: "hunter22", hint: "   ")
        #expect(a.lockHint == nil && a.isLockProtected && locks.isGated(a))
        #expect(a.lockSalt.flatMap(NetBase64.decode)?.count == 16)
        let json = a.toJSON(options: .dataFile)
        #expect(json["LockHash"] != nil && json["LockSalt"] != nil && !json.containsKey("LockHint"))
        locks.protect(b, password: "abcd", hint: "  my dog ")
        #expect(b.lockHint == "my dog" && locks.isGated(b))
        #expect(await !locks.tryUnlock(a, password: "Hunter22"))
        #expect(locks.isGated(a))
        #expect(await locks.tryUnlock(a, password: "hunter22"))
        #expect(!locks.isGated(a))
        locks.relock(a.id)
        #expect(locks.isGated(a))
        #expect(await locks.tryUnlock(a, password: "redemption"))
        #expect(await locks.tryUnlock(b, password: "abcd"))
        #expect(!locks.isGated(a) && !locks.isGated(b))
        locks.relockAll()
        #expect(locks.isGated(a) && locks.isGated(b))
        locks.removeProtection(b)
        #expect(!locks.isGated(b) && b.lockHash == nil && b.lockSalt == nil && b.lockHint == nil && !b.isLockProtected)
        // Re-protecting gates again even after an unlock.
        #expect(await locks.tryUnlock(a, password: "hunter22"))
        locks.protect(a, password: "other12", hint: nil)
        #expect(locks.isGated(a))
        // An unprotected item: master unlock succeeds, anything else fails.
        let c = Procedure(name: "C")
        #expect(await locks.tryUnlock(c, password: "redemption"))
        #expect(await !locks.tryUnlock(c, password: "x"))
    }
}

@Suite struct SecretStoreTests {
    @Test func inMemoryStore() throws {
        let s = InMemorySecretStore()
        #expect(try s.read(service: "a", account: "b") == nil)
        try s.write(Data([1]), service: "a", account: "b")
        try s.write(Data([2]), service: "a", account: "c")
        #expect(try s.read(service: "a", account: "b") == Data([1]))
        try s.write(Data([3]), service: "a", account: "b")
        #expect(try s.read(service: "a", account: "b") == Data([3]))
        try s.delete(service: "a", account: "b")
        #expect(try s.read(service: "a", account: "b") == nil)
        #expect(try s.read(service: "a", account: "c") == Data([2]))
        s.failAll = true
        #expect(throws: SecretStoreError.self) { try s.read(service: "a", account: "c") }
    }

    // TV: 01 DATA-215 Keychain registry names
    @Test func keychainNames() {
        #expect(Identifiers.Keychain.localDataKey.service == "AA.LocalDataKey" && Identifiers.Keychain.localDataKey.account == "v1")
        #expect(Identifiers.Keychain.googleTokenKey.service == "AA" && Identifiers.Keychain.googleTokenKey.account == "google-token-key")
        #expect(Identifiers.Keychain.gemini.service == "com.eriskay.aa.gemini" && Identifiers.Keychain.gemini.account == "GeminiApiKey")
    }
}
