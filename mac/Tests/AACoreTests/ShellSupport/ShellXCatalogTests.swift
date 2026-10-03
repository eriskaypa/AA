// TV: 03 SHELL-523 (Keyboard Shortcuts window generated from the registry, grouped by menu, searchable, columns
//     Command / Mac / Windows / Menu); OWNERSHIP W-SHELL acceptance "SceneRequest userInfo round trip" (ARCH §7.3: JSON
//     under `aa.sceneRequest`); 03 SHELL-115 / BD.3.11 / BD.7.5 (About version texts); Appendix A.3/A.4 strings
//     (SHELL-061…072, D28, D29 with the Q-7 cadence fix, D31, D33), SHELL-070 default export name.
import Foundation
import Testing
@testable import AACore

@Suite struct ShellXShortcutCatalogTests {
    @Test func groupedByMenuInMenuBarOrder() {
        let groups = ShellXShortcutCatalog.groups()
        #expect(groups.map(\.title) == ["AA", "File", "Edit", "Format", "View", "Tools", "Window", "Help",
                                        "In-Window Keys"])
        #expect(ShellXShortcutCatalog.count(groups) == ShortcutRegistry.rows.count)
        #expect(Set(groups.flatMap { $0.entries.map(\.id) }).count == ShortcutRegistry.rows.count)
        let file = groups.first { $0.title == "File" }!
        let saveAs = file.entries.first { $0.command == .saveCopyAs }!
        #expect(saveAs.title == "Save a Copy As JSON…")
        #expect(saveAs.mac == "⇧⌘S" && saveAs.chords == ["⇧⌘S"])
        #expect(saveAs.windows == "Save As...")
        #expect(saveAs.menu == "File")
        let stop = file.entries.first { $0.command == .stopSharedSaveFile }!
        #expect(stop.menu == "File ▸ Shared Save")
        let inWindow = groups.last!
        #expect(inWindow.entries.allSatisfy { !$0.menu.contains("▸") })
        #expect(inWindow.entries.first { $0.command == .kbCancel }?.mac == "⎋, ⌘.")
    }

    @Test func searchFiltersEveryColumn() {
        let byKey = ShellXShortcutCatalog.groups(query: "⇧⌘S")
        #expect(byKey.flatMap(\.entries).map(\.command).contains(.saveCopyAs))
        let shared = ShellXShortcutCatalog.groups(query: "shared save").flatMap(\.entries)
        #expect(Set(shared.map(\.command)).isSuperset(of: [.setSharedSaveFile, .stopSharedSaveFile, .checkSharedSaveNow]))
        let windows = ShellXShortcutCatalog.groups(query: "Ctrl+Z").flatMap(\.entries)
        #expect(!windows.isEmpty && windows.allSatisfy {
            NetText.containsIgnoreCase($0.windows, "Ctrl+Z") || NetText.containsIgnoreCase($0.title, "Ctrl+Z")
        })
        #expect(ShellXShortcutCatalog.groups(query: "  ") == ShellXShortcutCatalog.groups())
        #expect(ShellXShortcutCatalog.groups(query: "zzz-no-such-command").isEmpty)
    }

    @Test func sectionItemsShowTheirSectionTitles() {
        let titles = SectionID.defaultOrder.map(\.title)
        let view = ShellXShortcutCatalog.groups(sectionTitles: titles).first { $0.title == "View" }!
        let first = view.entries.first { $0.command == .section1 }!
        #expect(first.title == titles[0])
        #expect(first.mac == "⌘1")
        let thirteenth = view.entries.first { $0.command == .section13 }!
        #expect(thirteenth.title == titles[12] && thirteenth.mac.isEmpty)
        // Without titles the registry names are kept.
        #expect(ShellXShortcutCatalog.groups().first { $0.title == "View" }!.entries
            .first { $0.command == .section2 }?.title == "Section 2")
    }
}

/// A stand-in with the shape of the AA target's `SceneRequest` (which the test target cannot import).
private enum ShellXTestSceneRequest: Hashable, Codable {
    case item(UUID), search, activityLog, quickWork, dueDates, quickSwitcher, flashSync, crewTable, folderBuilder,
         dateCalculator, unitConverter, shortcuts, about, settings(tab: ShellXTestSettingsTab?)
}

private enum ShellXTestSettingsTab: String, Hashable, Codable { case general, security, sync, fileLinks, ai }

@Suite struct ShellXNotificationPayloadTests {
    @Test func sceneRequestRoundTripsThroughUserInfo() throws {
        let cases: [ShellXTestSceneRequest] = [.dueDates, .item(G(7)), .settings(tab: .fileLinks), .settings(tab: nil),
                                               .search, .crewTable]
        for c in cases {
            let info = ShellXNotificationPayload.userInfo(c)
            #expect(info.keys.sorted() == ["aa.sceneRequest"])
            // UserNotifications needs a property-list-safe dictionary.
            _ = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
            let anyInfo: [AnyHashable: Any] = info
            let json = ShellXNotificationPayload.json(from: anyInfo)
            #expect(ShellXNotificationPayload.decode(ShellXTestSceneRequest.self, json: json) == c)
        }
    }

    @Test func missingOrForeignPayloads() {
        #expect(ShellXNotificationPayload.userInfo(Optional<ShellXTestSceneRequest>.none).isEmpty)
        #expect(ShellXNotificationPayload.json(from: [:]) == nil)
        #expect(ShellXNotificationPayload.json(from: ["aa.sceneRequest": 42]) == nil)
        #expect(ShellXNotificationPayload.decode(ShellXTestSceneRequest.self, json: nil) == nil)
        #expect(ShellXNotificationPayload.decode(ShellXTestSceneRequest.self, json: "{\"nope\":{}}") == nil)
        #expect(ShellXNotificationPayload.decode(ShellXTestSceneRequest.self, json: "not json") == nil)
    }
}

@Suite struct ShellXVersionInfoTests {
    @Test func versionTexts() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "412",
                                   "AABuildDate": "2026-09-30", "AAGitCommit": "a1b2c3d-dirty"]
        let v = ShellXVersionInfo(info: info, unbundled: false)
        #expect(v.versionLine == "Version 1.0.0 (412)")
        #expect(v.buildLine == "Built 2026-09-30 · a1b2c3d-dirty")
        #expect(v.reportVersion == "1.0.0" && v.reportBuild == "412")
        #expect(ShellXVersionInfo.credits == "Created by B.E.P. Avida - May 2026")

        let template = ShellXVersionInfo(info: ["CFBundleShortVersionString": "@VERSION@", "CFBundleVersion": "@BUILD@"],
                                         unbundled: false)
        #expect(template.versionLine == "Version 1.0.0 (1)" && template.buildLine == nil)

        let dev = ShellXVersionInfo(info: nil, unbundled: true)
        #expect(dev.versionLine == "Development build (unbundled)")
        #expect(dev.reportVersion == "dev" && dev.reportBuild == "0")
    }
}

@Suite struct ShellXTextTests {
    @Test func panelDefaults() {
        let t = NetDateTime(year: 2026, month: 9, day: 30, hour: 14, minute: 3, second: 12, kind: .local)
        #expect(ShellXText.exportDefaultName(t, zone: TZ.athens) == "aa-data-20260930-1403.zip")
        #expect(ShellXText.saveCopyDefaultName == "aa-data.json")
        #expect(ShellXText.sharedDefaultName == "aa-shared.zip")
        #expect(ShellXText.sharedPanelMessage == "Choose the single shared save file (put it on a network drive or synced folder). It bundles your data AND attachments.")
    }

    @Test func statusLines() {
        #expect(ShellXText.exportedTo("/x/aa-data.json") == "Exported to /x/aa-data.json")
        #expect(ShellXText.exportedDataFolder("/x/a.zip") == "Exported data folder to /x/a.zip")
        #expect(ShellXText.importedBundle(fileName: "a.aaz", dataOnly: true)
                == "Imported a.aaz (text only — your attachments are untouched)")
        #expect(ShellXText.importedBundle(fileName: "a.zip", dataOnly: false) == "Imported a.zip (with attachments)")
        #expect(ShellXText.sharedSet("/Volumes/S/aa-shared.zip") == "Shared save file set — /Volumes/S/aa-shared.zip")
        #expect(ShellXText.sharedNone == "No shared save file is set.")
        #expect(ShellXText.sharedStopped == "Stopped using the shared save file (now saving locally).")
        let t = NetDateTime(year: 2026, month: 9, day: 30, hour: 9, minute: 5, second: 7, kind: .local)
        #expect(ShellXText.sharedChecked(t, zone: TZ.athens) == "Checked the shared save file (09:05:07).")
    }

    @Test func dialogsUseMacWording() {
        #expect(ShellXText.confirmReloadMessage == "Reload data from disk? Unsaved changes will be lost.")
        #expect(ShellXText.sharedExistsMessage(fileName: "aa-shared.zip")
                == "'aa-shared.zip' already exists.\n\nUse ITS contents (data + attachments) as your data (Use Its Contents), or keep your current data and overwrite it (Overwrite It)?")
        let d29 = ShellXText.sharedSetInfo(path: "/Volumes/S/aa-shared.zip")
        #expect(d29.hasPrefix("This copy of AA now saves to and syncs from:\n\n/Volumes/S/aa-shared.zip\n\n"))
        #expect(d29.contains("autosaves there every minute") && !d29.contains("10 minutes"))   // DECISIONS 03 Q-7
        #expect(ShellXText.stopSharedMessage.contains("on this Mac only") && !ShellXText.stopSharedMessage.contains("PC"))
        #expect(ShellXText.encryptConfirmMessage.hasPrefix("Encrypt this Mac's data file at rest with the macOS Keychain"))
        #expect(!ShellXText.encryptConfirmMessage.contains("DPAPI") && !ShellXText.encryptConfirmMessage.contains("Windows"))
        #expect(ShellXText.identityPrompt.hasPrefix("Name this installation (e.g. a vessel or operator)."))
        #expect(ShellXText.translocationTitle == "Move AA to Applications")
        #expect(ShellXText.reminderTitle == "AA — due soon")
    }
}

@Suite struct ShellXShortcutWindowsTextTests {
    @Test func specReferencesAndAccessKeysAreDropped() {
        let t = ShellXShortcutCatalog.windowsText
        #expect(t("top-level _About (SHELL-115)") == "top-level About")
        #expect(t("— (Mac addition, §6.4)") == "—")
        #expect(t("— (optional Mac addition, 11 §6.2)") == "—")
        #expect(t("E_xit; ✕ or Alt+F4 on main (SHELL-056/082)") == "Exit; ✕ or Alt+F4 on main")
        #expect(t("✕ / Alt+F4 (no Ctrl+W on Windows — W-12)") == "✕ / Alt+F4")
        #expect(t("Ctrl+S, _Save, header Save (Ctrl+S)") == "Ctrl+S, Save, header Save (Ctrl+S)")
        #expect(t("Ctrl+B, B Bold (Ctrl+B) (CONT-023)") == "Ctrl+B, B Bold (Ctrl+B)")
        #expect(t("+ New buttons (HIER-021, VIEW-053, VIEW-147, 06 New List)") == "+ New buttons")
        #expect(t("— (DECISIONS R-70, 01 DATA-181)") == "—")
        #expect(t("Ctrl+R in the editor (X-16)") == "Ctrl+R in the editor")
        #expect(t("Ctrl+Z (text undo; else main-window undo-delete)") == "Ctrl+Z (text undo; else main-window undo-delete)")
        #expect(t("I_mport data folder (ZIP)...") == "Import data folder (ZIP)...")
        #expect(t("Import COMPAS _crew (.xlsx)...") == "Import COMPAS crew (.xlsx)...")
        #expect(t("Flash S_ync with iPhone (QR)...") == "Flash Sync with iPhone (QR)...")
        #expect(t("Ctrl+N, Quick _work window (Ctrl+N)") == "Ctrl+N, Quick work window (Ctrl+N)")
        #expect(t("") == "—")
        // Every registry row stays readable: no spec IDs left in the column.
        for row in ShortcutRegistry.rows {
            let cell = t(row.windowsGesture)
            #expect(!cell.contains("SHELL-") && !cell.contains("§") && !cell.contains("CONT-"), "\(row.id): \(cell)")
        }
    }
}

@Suite struct ShellXShortcutBareReferenceTests {
    @Test func bareSpecIDsBecomeADash() {
        #expect(ShellXShortcutCatalog.windowsText("CONT-063") == "—")
        #expect(ShellXShortcutCatalog.windowsText("SHELL-056/082") == "—")
        #expect(ShellXShortcutCatalog.windowsText("Ctrl+A") == "Ctrl+A")
    }
}
