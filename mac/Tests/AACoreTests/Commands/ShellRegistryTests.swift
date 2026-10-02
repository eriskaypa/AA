// Tests for the shortcut & menu registry and the menu tree (F3): 03 §6.5.1.14 "Registry integrity tests"
// (uniqueness after shift normalisation, reserved keys, text safety, coverage, strings) and the §6.5.1.6 menu tree.
import Foundation
import Testing
@testable import AACore

@Suite struct ShellRegistryTests {
    // TV: 03 §6.5.1.14 Uniqueness (SHELL-500)
    @Test func noTwoMenuItemsShareAChord() {
        var seen: [ShellShortcutChord: String] = [:]
        for (row, chord) in ShortcutRegistry.menuChords {
            if let other = seen[chord], other != row.id {
                Issue.record("\(chord) on \(row.id) and \(other)")
            }
            seen[chord] = row.id
        }
        #expect(seen.count > 60)
    }

    @Test func shiftNormalisationCatchesTheKnownCollision() {
        // ⌘{ (Align Left) is the same keystroke as ⇧⌘[ — adding ⇧⌘[ must be caught (X-1).
        #expect(ShellShortcutChord("⌘{")!.normalized == ShellShortcutChord("⇧⌘[")!.normalized)
        #expect(ShellShortcutChord("⌘+")!.normalized == ShellShortcutChord("⇧⌘=")!.normalized)
        #expect(ShellShortcutChord("⌘=")!.normalized != ShellShortcutChord("⌘+")!.normalized)
        #expect(ShellShortcutChord("⇧⌘7") != ShellShortcutChord("⌘7"))           // T-KB-41
        #expect(ShellShortcutChord("⌥⇧⌘V")?.description == "⌥⇧⌘V")
        #expect(ShellShortcutChord("⌘−")?.key == "-")
    }

    // TV: 03 §6.5.1.14 Reserved (SHELL-501)
    @Test func noReservedKeys() {
        for (row, chord) in ShortcutRegistry.menuChords {
            if let std = ShortcutRegistry.standardOwners[row.command], ShellShortcutChord(std)?.normalized == chord { continue }
            #expect(!ShellShortcutChord.reserved.contains(chord), "\(row.id) uses reserved \(chord)")
            #expect(!chord.isVoiceOverChord, "\(row.id) uses a VoiceOver chord")
        }
    }

    // TV: 03 §6.5.1.14 Text safety
    @Test func textSystemKeysAreTextClass() {
        for row in ShortcutRegistry.rows where row.isMenuItem {
            for chord in ([row.chord].compactMap { $0 } + row.aliasChords) where chord.isTextSystemKey {
                #expect(row.precedence == "TXT" || row.precedence == "EDITOR", "\(row.id) \(chord) is \(row.precedence)")
            }
        }
    }

    // TV: 03 §6.5.1.14 Coverage — every registry ID of §6.5.1.3–6.5.1.4 has a row
    @Test func coverage() {
        let ids = Set(ShortcutRegistry.rows.map { String($0.id.prefix(9)) })
        let expected = [530, 531, 532, 533, 534] + Array(540...570) + Array(575...593) + Array(600...623)
            + Array(630...640) + Array(645...658) + [660, 662, 663] + Array(665...695)
        for n in expected {
            #expect(ids.contains("SHELL-\(n)"), "missing SHELL-\(n)")
        }
        #expect(ShortcutRegistry.rows.contains { $0.id == "R-70" && $0.command == .recoverConflictCopies })
        for c in CommandID.allCases { #expect(ShortcutRegistry.row(c) != nil, "no row for \(c)") }
        for r in ShortcutRegistry.rows { #expect(!r.windowsGesture.isEmpty, "\(r.id) has no Windows gesture") }
    }

    // TV: 03 §6.5.1.3 key equivalents of the main rows
    @Test func keysAsRegistered() {
        func key(_ c: CommandID) -> String { ShortcutRegistry.row(c)!.keyDisplay }
        #expect(key(.save) == "⌘S")
        #expect(key(.saveCopyAs) == "⇧⌘S")
        #expect(key(.newItem) == "⇧⌘N")
        #expect(key(.quickWork) == "⌘N")
        #expect(key(.quickSwitcher) == "⌘O")
        #expect(key(.dueDates) == "⌘R")
        #expect(key(.deleteFamily) == "⌘⌫")
        #expect(key(.rename) == "F2")
        #expect(key(.find) == "⌘F")
        #expect(key(.searchAll) == "⇧⌘F")
        #expect(key(.searchCurrentList) == "⌥⌘F")
        #expect(key(.moveUp) == "⌃⌘↑")
        #expect(key(.lockNow) == "⌃⌘L")
        #expect(key(.exportPDF) == "⌥⌘E")
        #expect(key(.plannerToday) == "⇧⌘T")
        #expect(key(.showFonts) == "⌘T")
        #expect(key(.section1) == "⌘1")
        #expect(key(.section9) == "⌘9")
        #expect(key(.section10) == "")
        #expect(ShortcutRegistry.row(.quickSwitcher)!.aliases == ["⇧⌘O"])
        #expect(ShortcutRegistry.row(.bigger)!.aliases == ["⌘="])
        #expect(ShortcutRegistry.row(.superscript)!.aliases == ["⌃⌘="])
        #expect(ShortcutRegistry.row(.pasteAndMatchStyle)!.aliases == ["⇧⌘V"])
        let allAliases = ShortcutRegistry.rows.filter(\.isMenuItem).flatMap(\.aliases)
        #expect(allAliases.count == 4)                                           // SHELL-509: only these four
    }

    // TV: 03 §6.5.1.14 Strings — the §6.5.1.9 table round-trips through MacKeyStrings.render
    @Test func keyStrings() {
        let rows: [(String, String)] = [
            ("Restored 3 deleted items (Ctrl+Z).", "Restored 3 deleted items (⌘Z)."),
            ("Restored the last deleted item (Ctrl+Z).", "Restored the last deleted item (⌘Z)."),
            ("Quick _work window (Ctrl+N)", "Quick Work Window"),
            ("Quick s_witcher (Ctrl+O)", "Quick Switcher…"),
            ("Bold (Ctrl+B)", "Bold (⌘B)"),
            ("Redo (Ctrl+Y)", "Redo (⇧⌘Z)"),
            ("Hide this shortcuts strip (View ▸ Shortcut bar to bring it back).",
             "Hide this shortcuts strip (View ▸ Shortcut Bar to bring it back)."),
            ("Enter to open  ·  ↑ / ↓ to move  ·  Esc to close", "Return to open  ·  ↑ / ↓ to move  ·  Esc to close"),
        ]
        for (w, m) in rows { #expect(MacKeyStrings.render(w) == m) }
        // Registry tooltips already carry the Mac renderings.
        #expect(ShortcutRegistry.row(.trash)!.help!.hasSuffix("— ⌘Z undoes the last one."))
        #expect(ShortcutRegistry.row(.driveSyncOnSave)!.help!.hasPrefix("When on, ⌘S also pushes"))
        #expect(ShortcutRegistry.row(.quickSwitcher)!.help!.hasSuffix("Type, then Return."))
        #expect(ShortcutRegistry.toolbarHelp(.save) == "Save (⌘S)")
        #expect(ShortcutRegistry.toolbarHelp(.dueDates, base: "Due") == "Due (⌘R)")
    }

    // SHELL-508 title rule exceptions
    @Test func titles() {
        #expect(ShortcutRegistry.title(.saveCopyAs) == "Save a Copy As JSON…")
        #expect(ShortcutRegistry.title(.quit) == "Quit AA")
        #expect(ShortcutRegistry.title(.about) == "About AA")
        #expect(ShortcutRegistry.title(.searchAll) == "Search All Items…")
        #expect(ShortcutRegistry.title(.encryptLocalData) == "Encrypt Local Data File (This Mac)")
        #expect(ShortcutRegistry.title(.trash) == "Trash (Restore Deleted Items)…")
        for r in ShortcutRegistry.rows { #expect(!r.title.contains("..."), "\(r.id) uses three dots") }
    }
}

@Suite struct ShellMenuTreeTests {
    func titles(_ nodes: [ShellMenuNode]) -> [String] {
        nodes.map { n in
            switch n {
            case .item(let c): return ShortcutRegistry.title(c)
            case .separator: return "─"
            case .submenu(let t, _): return t + " ▸"
            case .sections: return "{sections}"
            }
        }
    }

    // TV: 03 §6.5.1.6 final menu bar (menus, order, separators)
    @Test func menuBarEqualsTheSpecTree() {
        #expect(ShellMenuTree.menus.map(\.title) == ["AA", "File", "Edit", "Format", "View", "Tools", "Window", "Help"])
        #expect(titles(ShellMenuTree.menu("AA")!.nodes) == ["About AA", "─", "Settings…", "─", "Services", "─",
                                                             "Hide AA", "Hide Others", "Show All", "─", "Quit AA"])
        #expect(titles(ShellMenuTree.menu("File")!.nodes) == [
            "New Item", "Open in New Window", "─", "Rename", "Quick Look", "Delete", "─",
            "Close", "Save", "Save a Copy As JSON…", "Reload from Disk", "Recover Conflict Copies…", "Import from File…", "─",
            "Trash (Restore Deleted Items)…", "Encrypt Local Data File (This Mac)", "─",
            "Shared Save ▸", "Set App Identity…", "─",
            "Open Data Folder", "Export Data Folder (ZIP)…", "Import Data Folder (ZIP)…", "Export Text Only (No Attachments)", "─",
            "Google Drive ▸", "─", "Flash Sync with iPhone (QR)…", "─", "Export as PDF…", "Print…"])
        guard case .submenu(_, let shared) = ShellMenuTree.menu("File")!.nodes[17],
              case .submenu(_, let drive) = ShellMenuTree.menu("File")!.nodes[25] else {
            Issue.record("submenus missing"); return
        }
        #expect(titles(shared) == ["Set Shared Save File…", "Stop Shared Save File", "─", "Check Shared Save Now"])
        #expect(titles(drive) == ["Save a Copy to Google Drive (Synced Folder)", "Set Google Drive Folder…", "─",
                                  "Upload Backup to Google Drive (OAuth)…", "Load Backup from Google Drive (OAuth)…",
                                  "Set Google OAuth Client (client_secret.json)…", "Sign Out of Google", "─",
                                  "Sync to Google Drive on Save", "Check Google Drive for Newer Save"])
        #expect(titles(ShellMenuTree.menu("Tools")!.nodes) == [
            "Folder Builder…", "Date Calculator…", "Floating Due-Dates Window", "Quick Work Window", "Quick Switcher…",
            "Activity Log…", "Unit Converter…", "─", "Import COMPAS Crew (.xlsx)…", "Check Crew Contract Expiries", "─",
            "Vessel ▸", "─", "SIRE 2.0 Export…", "Set Gemini API Key…", "─", "Set / Change Password…", "Lock Now"])
        #expect(titles(ShellMenuTree.menu("View")!.nodes).prefix(3) == ["{sections}", "Previous Section", "Next Section"])
        let format = titles(ShellMenuTree.menu("Format")!.nodes)
        #expect(format == ["Font ▸", "Text ▸", "Lists ▸", "Insert ▸", "─", "Clear Formatting", "─",
                           "Lock Highlighted Text…", "Unlock Highlighted Text…"])
    }

    // TV: T-KB-58 — the View menu follows TabOrder (SIRE first → "SIRE 2.0 ⌘1")
    @Test func sectionsFollowTheOrder() {
        let order = SectionID.applyTabOrder(["TabSire"])
        let text = ShellMenuTree.render(order: order)
        #expect(text.contains("SIRE 2.0\t⌘1"))
        #expect(text.contains("Equipment/Area\t⌘2"))
        #expect(!text.contains("Ports\t⌘"))
    }

    @Test func everyMenuCommandHasARow() {
        for c in ShellMenuTree.allCommands { #expect(ShortcutRegistry.row(c)?.isMenuItem == true, "\(c)") }
    }
}
