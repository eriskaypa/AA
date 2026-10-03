// Tests: FIX2-F3 (Stage V round-2 findings) — DECISIONS "Stage V rulings" (ISO date pickers), 09 CREW-033 (a cancel
//        button can be the alert default), 01 DATA-180 (quit while editing is stopped writes nothing), 01 DATA-021 /
//        03 SHELL-131 (leaving safe mode starts reminders), 03 §6.3 (restored geometry clamped to the screen size),
//        03 SHELL-197 (crash.log scan offset per data folder), 03 §6.5.1.6 (View / File menu order), design rules
//        14 / 15 / 17 (source rules for the shared components).
import Foundation
import Testing
@testable import AACore

@Suite struct ShellFix2Tests {
    private static let macRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func source(_ relative: String) throws -> String {
        try String(contentsOf: macRoot.appending(path: relative), encoding: .utf8)
    }

    // MARK: ISO date pickers (DECISIONS Stage V ruling; V2-J1, V2-J2, V2-J5, V2-DESIGN)

    @Test func pickerLocaleShowsISODates() {
        #expect(ShellDateDisplay.pickerLocaleIdentifier == "en_CA")
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 4; c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        cal.timeZone = utc
        let d = cal.date(from: c)!
        #expect(ShellDateDisplay.pickerText(d, zone: utc) == "2026-10-04")
        c.month = 4; c.day = 10
        #expect(ShellDateDisplay.pickerText(cal.date(from: c)!, zone: utc) == "2026-04-10")
    }

    /// Every numeric (field / stepper / default-style) DatePicker in F3's shared components carries `.aaISODatePicker()`;
    /// graphical month views keep Locale.current month names (design rule 14).
    @Test func sharedDatePickersAreISO() throws {
        for file in ["Sources/AA/Shared/DatePromptSheet.swift"] {
            let lines = try Self.source(file).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.contains("DatePicker(\"") {
                let block = lines[i..<min(i + 8, lines.count)].joined(separator: "\n")
                if block.contains(".datePickerStyle(.graphical)") { continue }
                #expect(block.contains(".aaISODatePicker()"), "\(file):\(i + 1) DatePicker without .aaISODatePicker()")
            }
        }
        let components = try Self.source("Sources/AA/Design/AAComponents.swift")
        #expect(components.contains("func aaISODatePicker() -> some View { environment(\\.locale, ShellDateDisplay.pickerLocale) }"))
    }

    // MARK: Alerts — Return on a cancel button (CREW-033; V2-J5)

    @Test func cancelButtonCanBeTheDefault() {
        // Date-order question: Day First, Month First, Cancel Import (cancel) — Return and ⎋ both cancel.
        let l = ShellAlertKeys.layout(count: 3, cancel: [false, false, true], defaultRole: [false, false, false],
                                      explicitDefault: 2)
        #expect(l.keys == ["", "", "\r"])
        #expect(l.defaultIndex == 2 && l.escapeIndex == 2 && l.escapeNeedsRouting)
        // Without the explicit default, button 0 answers Return and the cancel button ⎋ (unchanged behaviour).
        let plain = ShellAlertKeys.layout(count: 3, cancel: [false, false, true], defaultRole: [false, false, false])
        #expect(plain.keys == ["\r", "", "\u{1b}"])
        #expect(plain.defaultIndex == 0 && plain.escapeIndex == 2 && !plain.escapeNeedsRouting)
        // A `.default` role still wins over button 0; an out-of-range explicit default is ignored.
        let role = ShellAlertKeys.layout(count: 2, cancel: [true, false], defaultRole: [false, true], explicitDefault: 9)
        #expect(role.keys == ["\u{1b}", "\r"] && role.defaultIndex == 1)
        // A lone cancel button at index 0 is the default and also answers ⎋.
        let lone = ShellAlertKeys.layout(count: 2, cancel: [true, false], defaultRole: [false, false])
        #expect(lone.keys == ["\r", ""] && lone.escapeNeedsRouting)
        #expect(ShellAlertKeys.layout(count: 0, cancel: [], defaultRole: []).keys.isEmpty)
    }

    // MARK: Quit pipeline and safe-mode exit (V2-J8)

    @Test func quitWhileEditingIsStoppedWritesNothing() {
        #expect(ShellQuitPlan.skipsFinalSave(safeMode: false, readOnlyInstance: false, mainLoaded: true, stoppedEditing: true))
        #expect(!ShellQuitPlan.skipsFinalSave(safeMode: false, readOnlyInstance: false, mainLoaded: true, stoppedEditing: false))
        #expect(ShellQuitPlan.skipsFinalSave(safeMode: true, readOnlyInstance: false, mainLoaded: true, stoppedEditing: false))
        #expect(ShellQuitPlan.skipsFinalSave(safeMode: false, readOnlyInstance: true, mainLoaded: true, stoppedEditing: false))
        #expect(ShellQuitPlan.skipsFinalSave(safeMode: false, readOnlyInstance: false, mainLoaded: false, stoppedEditing: false))
    }

    @Test func leavingSafeModeStartsReminders() {
        #expect(ShellLoadPlan.startsSkippedServices(initial: false, wasSafeMode: true, isSafeMode: false, readOnlyInstance: false))
        #expect(!ShellLoadPlan.startsSkippedServices(initial: true, wasSafeMode: false, isSafeMode: false, readOnlyInstance: false))
        #expect(!ShellLoadPlan.startsSkippedServices(initial: false, wasSafeMode: false, isSafeMode: false, readOnlyInstance: false))
        #expect(!ShellLoadPlan.startsSkippedServices(initial: false, wasSafeMode: true, isSafeMode: true, readOnlyInstance: false))
        #expect(!ShellLoadPlan.startsSkippedServices(initial: false, wasSafeMode: true, isSafeMode: false, readOnlyInstance: true))
    }

    // MARK: Geometry (V2-J8)

    /// The verifier's journey test, adopted.
    @Test func geometryClampsSize() {
        let screen = ShellRect(x: 0, y: 0, width: 1728, height: 1085)
        let cur = ShellRect(x: 0, y: 0, width: 1280, height: 820)
        let f = ShellWindowGeometry.restoredFrame(left: 10, top: 40, width: 150, height: 9000, current: cur,
                                                  primaryScreenMaxY: 1117, visibleFrames: [screen])!
        #expect(f.width == 1280)                    // ≤ 200 ignored
        #expect(f.height <= screen.height)
        #expect(f.y >= screen.y && f.maxY <= screen.maxY)
    }

    @Test func geometryFromAWindowsPCFitsAMacBook() {
        // A Windows PC's 1920×1040 bounds on a 1470×919 MacBook (visible frame below a 37-pt menu bar).
        let screen = ShellRect(x: 0, y: 0, width: 1470, height: 919)
        let cur = ShellRect(x: 95, y: 49, width: 1280, height: 820)
        let f = ShellWindowGeometry.restoredFrame(left: 0, top: 0, width: 1920, height: 1040, current: cur,
                                                  primaryScreenMaxY: 956, visibleFrames: [screen])!
        #expect(f.width == 1470 && f.height == 919)
        #expect(f.x == 0 && f.y == 0)
        // Smaller than the Mac minimum (860×560) → raised to it.
        let small = ShellWindowGeometry.restoredFrame(left: 100, top: 100, width: 300, height: 250, current: cur,
                                                      primaryScreenMaxY: 956, visibleFrames: [screen])!
        #expect(small.width == 860 && small.height == 560)
        #expect(small.maxX <= screen.maxX && small.y >= screen.y)
        // A frame that fits and whose title bar is visible is kept exactly (it may span two screens).
        let ok = ShellWindowGeometry.restoredFrame(left: 100, top: 120, width: 1000, height: 700, current: cur,
                                                   primaryScreenMaxY: 956, visibleFrames: [screen])!
        #expect(ok == ShellRect(x: 100, y: 956 - 120 - 700, width: 1000, height: 700))
    }

    // MARK: Crash-log scan offset per data folder (V2-J8, V2-SCALE)

    @Test func crashScanOffsetIsPerFolder() throws {
        let a = TempFolder("aa-crash-scan-a"), b = TempFolder("aa-crash-scan-b")
        let ka = CrashLog.scanOffsetKey(appFolder: a.url), kb = CrashLog.scanOffsetKey(appFolder: b.url)
        #expect(ka != kb)
        #expect(ka.rawValue.hasPrefix("aa.shell.crashLogScanOffset."))
        let marker = "\(CrashLog.markerPrefix)11\r\n"
        let old = Data(("[2026-10-01 10:00:00] old\r\n\r\n" + marker).utf8)
        // A fresh scan reports the marker; the stored offset then hides it.
        let first = CrashLog.scan(old, storedOffset: nil)
        #expect(first.signal == 11 && first.newOffset == old.count)
        #expect(CrashLog.scan(old, storedOffset: first.newOffset).signal == nil)
        // A new marker after the offset is found.
        let grown = old + Data(("[2026-10-02 10:00:00] x\r\n\r\n" + "\(CrashLog.markerPrefix)6\r\n").utf8)
        #expect(CrashLog.scan(grown, storedOffset: old.count).signal == 6)
        // An offset past the end (log replaced) rescans from byte 0.
        #expect(CrashLog.scan(old, storedOffset: old.count + 500).signal == 11)
    }

    // MARK: Menu order (§6.5.1.6; V2-J8)

    @Test func viewMenuMatchesTheTree() {
        typealias E = ShellMenuOrder.Entry
        let built: [E] = [.item("Equipment/Area"), .item("Previous Section"), .item("Next Section"), .separator,
                          .item("Previous"), .item("Go to Today"), .item("Next"), .separator,
                          .item("Show Toolbar"), .item("Customize Toolbar…"), .item("Show Sidebar"), .fullScreen,
                          .item("Shortcut Bar"), .item("Dark Mode"), .item("Customize Tab Colors…")]
        let order = ShellMenuOrder.viewMenu(built)
        let names = order.map { $0.map { i -> String in
            switch built[i] { case .item(let t): return t; case .separator: return "─"; case .fullScreen: return "FS" }
        } ?? "─" }
        #expect(names == ["Equipment/Area", "Previous Section", "Next Section", "─", "Previous", "Go to Today", "Next", "─",
                          "Show Sidebar", "Show Toolbar", "Customize Toolbar…", "Shortcut Bar", "Dark Mode",
                          "Customize Tab Colors…", "─", "FS"])
        // Already in order → identity (the bridge leaves the menu alone).
        let ordered: [E] = names.map { $0 == "─" ? .separator : ($0 == "FS" ? .fullScreen : .item($0)) }
        #expect(ShellMenuOrder.viewMenu(ordered) == ordered.indices.map { Optional($0) })
        // Not built yet (no Shortcut Bar) → unchanged.
        #expect(ShellMenuOrder.viewMenu([.item("A"), .separator]) == [0, 1])
    }

    @Test func fileMenuKeepsExportAndPrintTogether() {
        let built: [ShellMenuOrder.Entry] = [.item("Flash Sync with iPhone (QR)…"), .separator, .item("Export as PDF…"),
                                             .separator, .item("Print…")]
        #expect(ShellMenuOrder.fileMenu(built) == [0, 1, 2, 4])
        #expect(ShellMenuOrder.fileMenu([.item("Export as PDF…"), .item("Print…")]) == [0, 1])
    }

    // MARK: Source rules for the shared shell (design rules 15 / 17; V2-DESIGN, V2-J8)

    @Test func noWindowWideTint() throws {
        let root = try Self.source("Sources/AA/Shared/ShellWindowRoot.swift")
        #expect(!root.contains(".tint("))
        let components = try Self.source("Sources/AA/Design/AAComponents.swift")
        #expect(components.contains(".buttonStyle(.borderedProminent)\n            .tint(AAColor.tint)"))
    }

    @Test func listPaneSurfaceFillsTheToolbarBand() throws {
        let components = try Self.source("Sources/AA/Design/AAComponents.swift")
        #expect(components.contains("Rectangle().fill(.regularMaterial)\n            .background(AAColor.bg)"))
    }

    @Test func geometryRestoreWaitsForTheRegisteredWindow() throws {
        let launch = try Self.source("Sources/AA/App/LaunchCoordinator.swift")
        // Both sides call the one-shot restore; `mainWindowAppeared` runs before `SceneOpener.register`.
        #expect(launch.components(separatedBy: "restoreGeometryIfReady()").count - 1 >= 3)
        #expect(!launch.contains("if let w = mainWindow { env.restoreWindowGeometry(w) }"))
    }

    @Test func darkModeCheckFollowsTheSystem() throws {
        let appearance = try Self.source("Sources/AA/Design/AAAppearance.swift")
        #expect(appearance.contains("NSApp.observe(\\.effectiveAppearance"))
        let env = try Self.source("Sources/AA/App/AppEnvironment.swift")
        #expect(env.contains("ShellAppearance.observeEffectiveAppearance"))
    }
}
