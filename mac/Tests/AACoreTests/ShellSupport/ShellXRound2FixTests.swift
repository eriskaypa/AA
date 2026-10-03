// TV: Stage V round 2 fixes for W-SHELL — 01 §8.1 D-5 (orphaned legacy notes: distinct confirmation/warning title;
//     journey adopted from V2-J6), 03 SHELL-004 / §6.1 / DEVIATIONS SHELL-506 (Settings ▸ General writes nothing
//     before sign-in, V2-J8), SHELL-523 + design rules 1/5/18 (Keyboard Shortcuts table: flat rows, no zebra, mono
//     content, no AppKit reentrancy; V2-J8, V2-DESIGN), ARCH §9.6 (Settings debug sheets use the Settings scene's
//     chrome font, V2-DESIGN). The AA target has no test target, so view wiring is pinned by reading its sources.
import Foundation
import Testing
@testable import AACore

private enum Round2Source {
    /// `mac/` (this file is `mac/Tests/AACoreTests/ShellSupport/ShellXRound2FixTests.swift`).
    static let macRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func text(_ relative: String) throws -> String {
        try String(contentsOf: macRoot.appending(path: relative), encoding: .utf8)
    }

    /// Source lines without `//` comment lines.
    static func code(_ relative: String) throws -> String {
        try text(relative).split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .joined(separator: "\n")
    }
}

// MARK: - D-5 orphaned legacy notes (V2-J6)

@MainActor
@Suite("Round 2: D-5 orphaned notes dialogs", .serialized)
struct ShellXOrphanedNotesDialogTests {
    @Test("The confirmation and warning have their own title, not the failure title 'Password'")
    func distinctTitle() throws {
        #expect(ShellXText.olderEncryptedNotesTitle == "Older Encrypted Notes")
        #expect(ShellXText.olderEncryptedNotesTitle != ShellXText.passwordFailedTitle)
        let w = try #require(LegacyBodyMigration.orphanWarning(count: 2))
        #expect(ShellXText.orphanConfirmMessage(w)
                == "2 notes encrypted by an older AA build could not be decrypted with the current password. "
                + "After the password change they can no longer be opened with any password. Change the password anyway?")
        // ShellFlows.setPassword: both orphan dialogs use the new title; the failure alert keeps "Password".
        let flows = try Round2Source.code("Sources/AA/ShellFeatures/ShellFlows.swift")
        let start = try #require(flows.range(of: "private static func setPassword("))
        let body = String(flows[start.lowerBound...].prefix(2200))
        #expect(body.components(separatedBy: "ShellXText.olderEncryptedNotesTitle").count - 1 == 2)
        #expect(body.contains("dialogs.confirm(ShellXText.olderEncryptedNotesTitle, ShellXText.orphanConfirmMessage(w)"))
        #expect(body.contains("dialogs.warning(ShellXText.olderEncryptedNotesTitle, w)"))
        #expect(body.contains("dialogs.error(ShellXText.passwordFailedTitle, error.message)"))
    }

    /// Adopted from V2-J6 `passwordJourney`: the D-5 logic the dialogs describe.
    @Test("Change password: 1 legacy body migrated, 1 undecryptable kept, new hash persisted, master accepted")
    func orphanJourney() throws {
        let clock = PersistTestClock()
        let made = StoreFactory.make(clock: clock)
        let ds = made.dataStore
        let pw = PasswordService(settings: ds.settings)
        try pw.setPassword("oldpass", current: nil, migratingLegacyBodiesIn: made.store)
        let salt = try #require(ds.settings.values.passwordSalt)
        let xaml = #"<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Paragraph>Gas detector codes</Paragraph></Section>"#
        let d = AppData()
        let e1 = Equipment(name: "E1")
        e1.container.richTextXaml = LegacyBodyCrypto.encrypt(xaml, password: "oldpass", saltBase64: salt)
        e1.container.isLocked = true
        let e2 = Equipment(name: "E2")
        e2.container.richTextXaml = LegacyBodyCrypto.encrypt(xaml, password: "unknown!", saltBase64: salt)
        d.equipment = [e1, e2]
        made.store.replaceData(d, reason: .initialLoad)
        try made.store.save()
        pw.lock()
        // What the pre-change confirmation counts and says.
        let before = pw.undecryptableLegacyBodyCount(in: made.store, current: "oldpass")
        #expect(before == 1)
        let confirm = ShellXText.orphanConfirmMessage(try #require(LegacyBodyMigration.orphanWarning(count: before)))
        #expect(confirm.hasPrefix("1 note encrypted by an older AA build") && confirm.contains(" it can no longer"))
        let r = try pw.setPassword("newpass", current: "oldpass", migratingLegacyBodiesIn: made.store)
        #expect(r == LegacyBodyMigration(migrated: 1, undecryptable: 1))
        #expect(LegacyBodyMigration.orphanWarning(count: r.undecryptable) != nil)
        #expect(made.store.data.equipment[0].container.richTextXaml == xaml)
        #expect(!made.store.data.equipment[0].container.isLocked)
        #expect(LegacyBodyCrypto.isEncrypted(made.store.data.equipment[1].container.richTextXaml))   // kept, not ""
        let s2 = SettingsStore(fileURL: ds.settingsFile, secrets: made.secrets)
        s2.reload()
        let pw2 = PasswordService(settings: s2)
        #expect(pw2.verify("newpass") && !pw2.verify("oldpass"))
        #expect(pw2.verify("redemption"))
    }
}

// MARK: - Settings ▸ General before sign-in (V2-J8)

@Suite("Round 2: Settings ▸ General sign-in gate")
struct ShellXSettingsGateTests {
    @Test("Before sign-in only Mac-level preferences work; after it everything does")
    func gate() {
        typealias C = ShellXSettingsGate.GeneralControl
        let preLogin = Set(C.allCases.filter { ShellXSettingsGate.isEnabled($0, mainLoaded: false) })
        #expect(preLogin == [.menuBarExtra, .notificationSettings])
        for c in [C.appIdentity, .appearance, .shortcutBar, .showDataFolder] {
            #expect(!ShellXSettingsGate.isEnabled(c, mainLoaded: false), "\(c) must wait for sign-in")
        }
        #expect(C.allCases.allSatisfy { ShellXSettingsGate.isEnabled($0, mainLoaded: true) })
        #expect(ShellXSettingsGate.signInNotice == "Sign in to AA to change these settings.")
    }

    @Test("The General tab disables and guards every gated control and shows the sign-in notice")
    func generalTabWiring() throws {
        let src = try Round2Source.code("Sources/AA/ShellFeatures/ShellXSettingsTabs.swift")
        let start = try #require(src.range(of: "struct ShellXSettingsGeneralTab: View {"))
        let end = try #require(src.range(of: "struct ShellXSettingsSecurityTab: View {"))
        let general = String(src[start.lowerBound..<end.lowerBound])
        #expect(general.contains("ShellXSettingsGate.isEnabled(c, mainLoaded: env.mainLoaded)"))
        #expect(general.contains("ShellXSignInNotice()"))
        for c in ["appIdentity", "appearance", "shortcutBar", "showDataFolder"] {
            #expect(general.contains(".disabled(!enabled(.\(c)))"), "\(c) not disabled before sign-in")
        }
        // The focus-loss commit and the picker setter refuse too (they bypass `.disabled`).
        #expect(general.contains("private func commitIdentity() {\n        guard enabled(.appIdentity) else"))
        #expect(general.contains("private func setAppearance(_ mode: AppearanceMode) {\n        guard enabled(.appearance) else"))
    }
}

// MARK: - Keyboard Shortcuts window (V2-J8, V2-DESIGN)

@Suite("Round 2: Keyboard Shortcuts table")
struct ShellXShortcutTableRowTests {
    @Test("Groups flatten into one header row per menu followed by its entries; ids are unique")
    func tableRows() {
        let groups = ShellXShortcutCatalog.groups()
        let rows = ShellXShortcutCatalog.tableRows(groups)
        #expect(rows.count == groups.count + ShellXShortcutCatalog.count(groups))
        #expect(Set(rows.map(\.id)).count == rows.count)
        var i = 0
        for (gi, g) in groups.enumerated() {
            #expect(rows[i] == .header(title: g.title, count: g.entries.count, isFirst: gi == 0))
            #expect(rows[i].entry == nil)
            #expect(rows[(i + 1)...].prefix(g.entries.count).map(\.entry) == g.entries.map { Optional($0) })
            i += 1 + g.entries.count
        }
        #expect(i == rows.count)
        #expect(ShellXShortcutCatalog.tableRows(ShellXShortcutCatalog.groups(query: "zzz-no-such-command")).isEmpty)
        let filtered = ShellXShortcutCatalog.tableRows(ShellXShortcutCatalog.groups(query: "⇧⌘S"))
        #expect(filtered.first.map { if case .header(_, _, true) = $0 { true } else { false } } == true)
    }

    @Test("The view uses the flat rows (no Section → no NSTableView reentrancy), no zebra stripes, mono content")
    func viewWiring() throws {
        let src = try Round2Source.code("Sources/AA/ShellFeatures/KeyboardShortcutsView.swift")
        #expect(src.contains("Table(rows)"))
        #expect(!src.contains("Section {") && !src.contains("Section("))
        #expect(src.contains(".alternatingRowBackgrounds(.disabled)"))
        #expect(!src.contains("alternatesRowBackgrounds: true"))
        #expect(src.contains(".font(.aaMono(AAType.small))"))
        #expect(src.contains("Text(\"AA Keyboard Shortcuts\").font(.aaMono(AAType.title, weight: .bold))"))
        // Only the keycaps keep a system (rounded) face; no other content uses a raw system size.
        let systemSized = src.components(separatedBy: ".system(size: AAType").count - 1
        #expect(systemSized == 1 && src.contains(".font(.system(size: AAType.caption, weight: .medium, design: .rounded))"))
        // Rows are rebuilt on query / section-title change, not recomputed on every body pass.
        #expect(src.contains("@State private var rows: [ShellXShortcutTableRow]"))
        #expect(src.contains(".onChange(of: query)"))
    }
}

// MARK: - Settings debug sheets (V2-DESIGN)

@Suite("Round 2: Settings debug sheets match the Settings scene")
struct ShellXSettingsSnapshotChromeTests {
    @Test("Every w-shell.settings.* sheet and the Settings scene apply the same chrome font")
    func sameChrome() throws {
        let scene = try Round2Source.code("Sources/AA/ShellFeatures/SettingsView.swift")
        #expect(scene.contains(".shellXSettingsChrome()"))
        #expect(scene.contains("func shellXSettingsChrome() -> some View { font(.system(size: AAType.body)) }"))
        let snaps = try Round2Source.code("Sources/AA/ShellFeatures/ShellFeaturesDebugSnapshots.swift")
        let lines = snaps.split(separator: "\n").filter { $0.contains("register(\"w-shell.settings.") }
        #expect(lines.count == 5)
        for l in lines { #expect(l.contains(".shellXSettingsChrome())"), "\(l)") }
    }
}
