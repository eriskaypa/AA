// TV: 03 §6.5.1.9 (MacKeyStrings table), 13 §7.2 (CRC-32), 13 §7.6 (DEFLATE), 03 BD.7.3 (resource integrity),
//     09 §7.14 (Sanitize), 03 §3.8 (SafeIdentity), 03 §6.7 (WPF colours), 01 §3 (Ordinal / OrdinalIgnoreCase).
import Foundation
import Testing
import CryptoKit
@testable import AACore

@Suite struct CivilDateTests {
    @Test func arithmetic() {
        let d = CivilDate(year: 2027, month: 1, day: 31)!
        #expect(d.addingMonths(1).iso == "2027-02-28")
        #expect(CivilDate(year: 2028, month: 1, day: 31)!.addingMonths(1).iso == "2028-02-29")
        #expect(CivilDate(year: 2028, month: 2, day: 29)!.addingYears(1).iso == "2029-02-28")
        #expect(CivilDate(year: 2026, month: 12, day: 31)!.addingDays(1).iso == "2027-01-01")
        #expect(CivilDate(year: 2026, month: 3, day: 1)!.addingMonths(-3).iso == "2025-12-01")
        #expect(CivilDate(year: 1970, month: 1, day: 1)!.daysFromCivil == 0)
        #expect(CivilDate(year: 1, month: 1, day: 1)!.daysFromCivil == -719_162)
        #expect(CivilDate(daysFromCivil: 20_725).iso == "2026-09-29")
        #expect(CivilDate(year: 2026, month: 9, day: 29)!.weekday == 2)            // Tuesday
        #expect(CivilDate(year: 2026, month: 9, day: 27)!.weekday == 0)            // Sunday
        #expect(CivilDate(year: 2026, month: 9, day: 29)!.days(to: CivilDate(year: 2026, month: 10, day: 29)!) == 30)
    }

    @Test func validation() {
        #expect(CivilDate(year: 2026, month: 2, day: 29) == nil)
        #expect(CivilDate(year: 2024, month: 2, day: 29) != nil)
        #expect(CivilDate(iso: "2026-09-29")?.day == 29)
        #expect(CivilDate(iso: "2026-9-29") == nil)
        #expect(CivilDate(iso: "2026/09/29") == nil)
        #expect(CivilDate(year: 2026, month: 1, day: 2)! < CivilDate(year: 2026, month: 1, day: 3)!)
    }
}

@Suite struct NetTextTests {
    @Test func whitespace() {
        #expect(NetText.isBlank(nil))
        #expect(NetText.isBlank(""))
        #expect(NetText.isBlank(" \t\u{00A0}\u{2003}\u{3000}\r\n"))
        #expect(!NetText.isBlank("\u{200B}"))                                     // ZWSP is not white space in .NET
        #expect(NetText.trim("  a b \u{00A0}") == "a b")
        #expect(NetText.trim("|John|", characters: [0x7C]) == "John")
    }

    @Test func ordinalIgnoreCase() {
        #expect(NetText.equalsIgnoreCase("A.PDF", "a.pdf"))
        #expect(NetText.equalsIgnoreCase("Ωmega", "ωMEGA"))
        #expect(!NetText.equalsIgnoreCase("Straße.pdf", "STRASSE.pdf"))          // simple case mapping only
        #expect(!NetText.equalsIgnoreCase("é", "e\u{301}"))
        #expect(NetText.containsIgnoreCase("Main Engine", "ENGINE"))
        #expect(NetText.containsIgnoreCase("x", ""))
        #expect(NetText.compareIgnoreCase("apple", "Banana") == .orderedAscending)
        #expect(NetText.indexOfIgnoreCase("Pump manual", "MAN") == 5)
    }

    @Test func invariantCasing() {
        #expect(NetText.toLowerInvariant("NGBON") == "ngbon")
        #expect(NetText.toLowerInvariant("Bonny|Nigeria") == "bonny|nigeria")
        #expect(NetText.toLowerInvariant("İstanbul") == "istanbul")
        #expect(NetText.toLowerInvariant("ÄÖÜ") == "äöü")
        #expect(NetText.toUpperInvariant("straße") == "STRAßE")
    }

    @Test func ordinal() {
        #expect(Ordinal.equals("a", "a"))
        #expect(!Ordinal.equals("\u{E9}", "e\u{301}"))
        #expect(Ordinal.compare("B", "a") == .orderedAscending)
        #expect(Ordinal.Key("é") != Ordinal.Key("e\u{301}"))
    }
}

@Suite struct WindowsFileNameTests {
    // TV: 09 §7.14 Sanitize
    @Test func sanitize() {
        #expect(WindowsFileName.sanitize("Juan/Cruz:", fallback: "crew") == "Juan_Cruz_")
        #expect(WindowsFileName.sanitize("  ", fallback: "crew") == "crew")
        #expect(WindowsFileName.sanitize(" Deck ", fallback: "saved-lists") == "Deck")
        #expect(WindowsFileName.sanitize("a*b", fallback: "saved-lists") == "a_b")
        #expect(WindowsFileName.sanitize("a\u{1}b<c>", fallback: "x") == "a_b_c_")
        #expect(WindowsFileName.invalidCharacters.contains("?"))
        #expect(WindowsFileName.invalidCharacters.contains("\u{1F}"))
    }

    // TV: 03 §3.8 SafeIdentity
    @Test func safeIdentity() {
        #expect(WindowsFileName.safeIdentity("Vessel Alpha") == "VesselAlpha")
        #expect(WindowsFileName.safeIdentity("a:b/c") == "abc")
        #expect(WindowsFileName.safeIdentity("  ") == "AA")
        #expect(WindowsFileName.safeIdentity("") == "AA")
    }
}

@Suite struct WpfColorTests {
    @Test func parsing() {
        #expect(WpfColor.parse("#FF1E88E5") == ARGB(a: 0xFF, r: 0x1E, g: 0x88, b: 0xE5))
        #expect(WpfColor.parse("#80FF0000") == ARGB(a: 0x80, r: 0xFF, g: 0, b: 0))
        #expect(WpfColor.parse("#1E88E5") == ARGB(r: 0x1E, g: 0x88, b: 0xE5))
        #expect(WpfColor.parse("#F00") == ARGB(r: 0xFF, g: 0, b: 0))
        #expect(WpfColor.parse("#8F00") == ARGB(a: 0x88, r: 0xFF, g: 0, b: 0))
        #expect(WpfColor.parse(" red ") == ARGB(r: 0xFF, g: 0, b: 0))
        #expect(WpfColor.parse("CornflowerBlue") == ARGB(r: 0x64, g: 0x95, b: 0xED))
        #expect(WpfColor.parse("Transparent") == ARGB(a: 0, r: 0xFF, g: 0xFF, b: 0xFF))
        #expect(WpfColor.parse("sc#1,0,0") == ARGB(r: 0xFF, g: 0, b: 0))
        #expect(WpfColor.parse("sc#0.5,1,0.5,0") == ARGB(a: 128, r: 255, g: 188, b: 0))
        #expect(WpfColor.parse("#GG0000") == nil)
        #expect(WpfColor.parse("#12345") == nil)
        #expect(WpfColor.parse("#123456789") == nil)
        #expect(WpfColor.parse("notacolour") == nil)
        #expect(WpfColor.parse(nil) == nil)
    }

    @Test func formatting() {
        let c = ARGB(a: 0x80, r: 0x1E, g: 0x08, b: 0xE5)
        #expect(WpfColor.hexRRGGBB(c) == "#1E08E5")
        #expect(WpfColor.hexAARRGGBB(c) == "#801E08E5")
        #expect(WpfColor.luma(ARGB(r: 255, g: 255, b: 255)) == 255)
        #expect(abs(WpfColor.luma(ARGB(r: 100, g: 0, b: 0)) - 29.9) < 0.0001)
    }
}

@Suite struct MacKeyStringsTests {
    // TV: 03 §6.5.1.9 — every row of the table (Windows string → Mac string)
    @Test(arguments: [
        ("Restored 3 deleted items (Ctrl+Z).", "Restored 3 deleted items (⌘Z)."),
        ("Restored the last deleted item (Ctrl+Z).", "Restored the last deleted item (⌘Z)."),
        ("Restore items you deleted, or remove them for good. Deletes go here instead of vanishing — Ctrl+Z undoes the last one.",
         "Restore items you deleted, or remove them for good. Deletes go here instead of vanishing — ⌘Z undoes the last one."),
        ("When on, Ctrl+S also pushes your data to Google Drive (OAuth), and the app checks for a newer save pushed from other PCs.",
         "When on, ⌘S also pushes your data to Google Drive (OAuth), and the app checks for a newer save pushed from other PCs."),
        ("Quick _work window (Ctrl+N)", "Quick Work Window"),
        ("Quick s_witcher (Ctrl+O)", "Quick Switcher…"),
        ("Fuzzy-jump to any item by name, kind or #tag — Obsidian-style. Type, then Enter.",
         "Fuzzy-jump to any item by name, kind or #tag — Obsidian-style. Type, then Return."),
        ("Search (Ctrl+F)", "Search"), ("Go to (Ctrl+O)", "Go to"), ("Save (Ctrl+S)", "Save"),
        ("⌨  Ctrl+S Save   ·   Ctrl+F Search   ·   Ctrl+N Quick work   ·   Ctrl+O Go to (quick switcher)   ·   Ctrl+R Due-dates window   ·   Ctrl+1…9 Switch tab   ·   F2 Rename   ·   Ctrl+Z Undo delete",
         "⌨  ⌘S Save · ⌘F Search · ⌘N Quick work · ⌘O Go to (quick switcher) · ⌘R Due-dates window · ⌘1…9 Switch tab · F2 Rename · ⌘Z Undo delete"),
        ("Move every selected item to the Trash. Restore from File ▸ Trash, or undo with Ctrl+Z.",
         "Move every selected item to the Trash. Restore from File ▸ Trash, or undo with ⌘Z."),
        ("Comma- or space-separated tags. Used for filtering, global search and the quick switcher (Ctrl+O).",
         "Comma- or space-separated tags. Used for filtering, global search and the quick switcher (⌘O)."),
        ("No tasks yet.\n\nClick “+ New” to add a task, or Ctrl+N for the quick-work window.",
         "No tasks yet.\n\nClick “+ New” to add a task, or ⌘N for the quick-work window."),
        ("'Pump' moved to Trash — Ctrl+Z to undo.", "'Pump' moved to Trash — ⌘Z to undo."),
        ("4 items moved to Trash — Ctrl+Z to undo them all.", "4 items moved to Trash — ⌘Z to undo them all."),
        ("Move Juan Cruz to the Trash?\n\nYou can restore them from File ▸ Trash, or undo with Ctrl+Z.",
         "Move Juan Cruz to the Trash?\n\nYou can restore them from File ▸ Trash, or undo with ⌘Z."),
        ("Predefine buckets here — a location, a rank, a department, anything. Then sort tasks & procedures into up to two of them (in the Ctrl+N quick-work window).",
         "Predefine buckets here — a location, a rank, a department, anything. Then sort tasks & procedures into up to two of them (in the ⌘N quick-work window)."),
        ("The list is added where your cursor is. Nothing already in the note is changed, and one Ctrl+Z removes the whole list again.",
         "The list is added where your cursor is. Nothing already in the note is changed, and one ⌘Z removes the whole list again."),
        ("Bold (Ctrl+B)", "Bold (⌘B)"), ("Italic (Ctrl+I)", "Italic (⌘I)"), ("Underline (Ctrl+U)", "Underline (⌘U)"),
        ("Undo (Ctrl+Z)", "Undo (⌘Z)"), ("Redo (Ctrl+Y)", "Redo (⇧⌘Z)"),
        ("Move the current list item (or block) up — Ctrl+Alt+Up. Sub-items move with it.",
         "Move the current list item (or block) up — ⌃⌘↑. Sub-items move with it."),
        ("Move the current list item (or block) down — Ctrl+Alt+Down. Sub-items move with it.",
         "Move the current list item (or block) down — ⌃⌘↓. Sub-items move with it."),
        ("Outdent (Shift+Tab at the start of a list item)", "Outdent (⇧Tab at the start of a list item)"),
        ("Indent (Tab at the start of a list item)", "Indent (Tab at the start of a list item)"),
        ("Paste text only", "Paste Text Only"), ("Ctrl+Shift+V", "⌥⇧⌘V"),
        ("Enter to open  ·  ↑ / ↓ to move  ·  Esc to close", "Return to open  ·  ↑ / ↓ to move  ·  Esc to close"),
        ("Add a task and press Enter…", "Add a task and press Return…"),
        ("Editable — type to add line breaks / notes (Enter = new line). Your edits are saved.",
         "Editable — type to add line breaks / notes (Return = new line). Your edits are saved."),
        ("Hide this shortcuts strip (View ▸ Shortcut bar to bring it back).",
         "Hide this shortcuts strip (View ▸ Shortcut Bar to bring it back)."),
        ("Enter the app password to unlock locked containers:", "Enter the app password to unlock locked containers:"),
    ] as [(String, String)])
    func renders(_ windows: String, _ mac: String) {
        #expect(MacKeyStrings.render(windows) == mac)
    }
}

@Suite struct CRCAndDeflateTests {
    // TV: 13 §7.2
    @Test func crc32Vectors() {
        #expect(CRC32.checksum(Data()) == 0x0000_0000)
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data("AA flash sync".utf8)) == 0xCD53_9EA5)
        #expect(CRC32.checksum(Data(count: 900)) == 0xD5B7_BCEC)
        let a = CRC32.checksum(Data("12345".utf8))
        #expect(CRC32.checksum(Data("6789".utf8), seed: a) == 0xCBF4_3926)       // chained
    }

    static func hex(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            out.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    // TV: 13 §7.6
    @Test func deflateVectors() throws {
        let coded = Self.hex("73748401273870860300")
        let raw = Self.hex("414141414141414141414242424242424242424243434343434343434343")
        #expect(try RawDeflate.inflate(coded, expectedLength: 30) == raw)
        #expect(try RawDeflate.compress(raw) == coded)                          // identical to iOS
        #expect(try RawDeflate.compress([]) == [0x03, 0x00])
        #expect(try RawDeflate.compress(raw).first != 0x78)                      // not zlib-wrapped
        #expect(try RawDeflate.inflate(coded, expectedLength: 10) == Array(raw.prefix(10)))
        #expect(throws: RawDeflateError.shortOutput(produced: 30, expected: 40)) {
            try RawDeflate.inflate(coded, expectedLength: 40)
        }
        #expect(try RawDeflate.inflate(coded, expectedLength: nil) == raw)
    }

    @Test func largeRoundTrip() throws {
        var g = SystemRandomNumberGenerator()
        let text = (0..<200_000).map { _ in UInt8.random(in: 0x61...0x66, using: &g) }
        let c = try RawDeflate.compress(text)
        #expect(c.count < text.count)
        #expect(try RawDeflate.inflate(c, expectedLength: text.count) == text)
        #expect(throws: (any Error).self) { try RawDeflate.inflate([0xFF, 0xFF, 0xFF], expectedLength: nil) }
    }
}

@MainActor @Suite struct EventHubTests {
    @Test func subscribeSendCancel() {
        let hub = EventHub<Int>()
        var got: [Int] = []
        let a = hub.subscribe { got.append($0) }
        var b: EventSubscription? = hub.subscribe { got.append($0 * 10) }
        hub.send(1)
        #expect(got == [1, 10])
        b = nil                                                                   // releasing the token cancels
        #expect(b == nil)
        hub.send(2)
        #expect(got == [1, 10, 2])
        a.cancel()
        hub.send(3)
        #expect(got == [1, 10, 2])
        #expect(hub.subscriberCount == 0)
    }
}

@Suite struct IdentifiersAndResourcesTests {
    @Test func identifiers() {
        #expect(Identifiers.bundleID == "com.eriskay.aa")
        #expect(Identifiers.Keychain.localDataKey.service == "AA.LocalDataKey")
        #expect(Identifiers.Keychain.localDataKey.account == "v1")
        #expect(Identifiers.Keychain.gemini.service == "com.eriskay.aa.gemini")
        #expect(SceneID.quickWork.rawValue == "quick-work")
        #expect(SceneID.activityLog.rawValue == "activity-log")
        #expect(SceneID.bootstrap.rawValue == "bootstrap")
    }

    static func sha256(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    static var macRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()      // Foundation
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()   // mac/
    }

    // TV: 03 BD.7.3 — the byte copies equal the originals
    @Test func resourceCopiesArePinned() throws {
        let bank = try Data(contentsOf: Self.macRoot.appending(path: "Sources/AACore/Resources/sire2_question_bank.json"))
        #expect(Self.sha256(bank) == "e05d3c59572625b639005c498f5090c88a6ea67cdff9b45581df3f8658eb8bcf")
        #expect(bank.count == 3_350_301)
        let splash = try Data(contentsOf: Self.macRoot.appending(path: "Sources/AA/Resources/Splash.png"))
        #expect(Self.sha256(splash) == "1489fd928894042eda13a510b6916eb18ccb0310fa54b035d2e82682a84539a6")
        #expect(splash.count == 97_640)
        for name in ["MenuBarIconTemplate.png", "MenuBarIconTemplate@2x.png"] {
            let png = try Data(contentsOf: Self.macRoot.appending(path: "Sources/AA/Resources/\(name)"))
            #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        }
    }

    // TV: 03 BD.3.4 — the locator finds the AACore resource bundle from the test process
    @Test func locatorFindsQuestionBank() throws {
        let d = try #require(AAResources.data(name: "sire2_question_bank", ext: "json"))
        #expect(Self.sha256(d) == "e05d3c59572625b639005c498f5090c88a6ea67cdff9b45581df3f8658eb8bcf")
        #expect(AAResources.url(name: "does-not-exist", ext: "json") == nil)
    }

    @Test func macPreferences() {
        let suite = "aa-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let p = MacPreferences(defaults: defaults)
        let k = MacPreferences.Key("aa.tests.flag")
        #expect(p.bool(k, default: true))
        p.set(false, k)
        #expect(!p.bool(k, default: true))
        let s = MacPreferences.Key("aa.tests.text")
        p.set("x", s); #expect(p.string(s) == "x")
        p.set(nil as String?, s); #expect(p.string(s) == nil)
        struct M: Codable, Equatable { var a: Int }
        let c = MacPreferences.Key("aa.tests.codable")
        p.setCodable(M(a: 3), c)
        #expect(p.codable(c, as: M.self) == M(a: 3))
    }
}
