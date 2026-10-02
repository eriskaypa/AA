// Tests for AACore/Launch (F3): 03 BD.7.1 (AppFolder resolution), BD.7.2 (translocation), BD.7.5 (parser, version,
// crash sink), 03 §7.1 (login, password dialog, UiState restore, coordinate conversion).
import Foundation
import Testing
@testable import AACore

@Suite struct ShellLaunchArgumentsTests {
    let home = URL(fileURLWithPath: "/Users/u", isDirectory: true)
    let def = "/Users/u/Library/Application Support/AA"

    func resolve(_ args: [String], env: String?, cwd: String = "/", warnings: inout [String])
        -> Result<(url: URL, source: AppFolderSource), DataDirError> {
        let o = LaunchArguments.parse(["AA"] + args) { warnings.append($0) }
        var e: [String: String] = [:]
        if let env { e["AA_DATA_DIR"] = env }
        return AppFolderResolver.resolve(o, environment: e, cwd: URL(fileURLWithPath: cwd, isDirectory: true), home: home)
    }

    func path(_ args: [String], env: String?, cwd: String = "/") -> (String?, AppFolderSource?, [String]) {
        var w: [String] = []
        switch resolve(args, env: env, cwd: cwd, warnings: &w) {
        case .success(let r): return (r.url.path, r.source, w)
        case .failure: return (nil, nil, w)
        }
    }

    // TV: 03 BD.7.1 rows 1–19
    @Test func resolutionRows() {
        #expect(path([], env: nil).0 == def)                                                    // 1
        #expect(path([], env: "").0 == def)                                                     // 2
        #expect(path([], env: " \t\n").0 == def)                                                // 3
        #expect(path([], env: "/Volumes/STICK/AA Data").0 == "/Volumes/STICK/AA Data")          // 4
        #expect(path([], env: "/Volumes/STICK/AA Data/\n").0 == "/Volumes/STICK/AA Data")       // 5
        #expect(path([], env: "~/aa-test").0 == "/Users/u/aa-test")                             // 6
        #expect(path([], env: "~").0 == "/Users/u")                                             // 7
        #expect(path([], env: "data", cwd: "/Users/u/work").0 == "/Users/u/work/data")          // 8
        #expect(path([], env: "./x/../y", cwd: "/Users/u/work").0 == "/Users/u/work/y")         // 9
        let r10 = path(["--data-dir", "/tmp/a"], env: "/Volumes/S/AA")                          // 10
        #expect(r10.0 == "/tmp/a"); #expect(r10.1 == .argument)
        #expect(path(["--data-dir=/tmp/b"], env: nil).0 == "/tmp/b")                            // 11
        #expect(path(["--data-dir", "/a", "--data-dir", "/b"], env: nil).0 == "/b")             // 12
        let r13 = path(["--data-dir"], env: "/e")                                               // 13
        #expect(r13.0 == "/e"); #expect(r13.1 == .environment)
        #expect(r13.2 == [LaunchArguments.dataDirMissingValueWarning])
        var w14: [String] = []                                                                  // 14
        let o14 = LaunchArguments.parse(["AA", "--data-dir", "--smoke-test"]) { w14.append($0) }
        #expect(o14.smokeTest && o14.dataDir == nil && w14.count == 1)
        #expect(path(["--data-dir", "--smoke-test"], env: nil).0 == def)
        #expect(path(["--data-dir", ""], env: "/e").0 == "/e")                                  // 15
        #expect(path(["--data-dir="], env: nil).0 == def)                                       // 16
        #expect(path(["-NSDocumentRevisionsDebugMode", "YES", "--data-dir", "/t"], env: nil).0 == "/t")   // 17
        #expect(path(["-psn_0_12345", "--data-dir", "/t"], env: nil).0 == "/t")                 // 18
        let r19 = path(["--Data-Dir", "/t"], env: nil)                                           // 19
        #expect(r19.0 == def); #expect(r19.1 == .defaultLocation)
    }

    // TV: 03 BD.7.1 rows 20–22
    @Test func windowsPathsAreErrors() {
        var w: [String] = []
        for (args, env) in [([String](), Optional("C:\\AA")), ([], "\\\\srv\\share\\AA"), (["--data-dir", "E:/AA Data"], nil)] {
            guard case .failure(let e) = resolve(args, env: env, warnings: &w) else { Issue.record("expected failure"); continue }
            #expect(e == .windowsPath)
            #expect(!AppFolderResolver.offersTryAgain(e))
        }
    }

    // TV: 03 BD.7.1 rows 23–25 (pre-flight) and the row-23 alert text
    @Test func preflightRows() throws {
        do {
            try AppFolderResolver.preflight(URL(fileURLWithPath: "/Volumes/NOPE-\(UUID().uuidString)/AA"))
            Issue.record("expected volumeMissing")
        } catch {
            if case .volumeMissing = error {} else { Issue.record("wrong error \(error)") }
        }
        #expect(throws: DataDirError.self) { try AppFolderResolver.preflight(URL(fileURLWithPath: "/System/AA-\(UUID().uuidString)")) }
        let t = TempFolder("aa-preflight")
        let file = try t.write("f", "x")
        #expect(throws: DataDirError.notAFolder) { try AppFolderResolver.preflight(file) }
        try AppFolderResolver.preflight(t.url.appending(path: "new/nested"))
        #expect(t.exists("new/nested"))

        let msg = AppFolderResolver.alertMessage(path: "/Volumes/NOPE/AA", error: .volumeMissing("NOPE"), source: .environment)
        #expect(msg == "AA couldn't open or create its data folder:\n\n/Volumes/NOPE/AA\n\nThe drive “NOPE” isn't connected. Connect it, then choose Try Again.\n\nThe folder comes from the AA_DATA_DIR environment variable.")
        #expect(AppFolderResolver.alertTitle == "AA can't open its data folder")
    }

    // TV: 03 BD.7.1 row 26 (--version beats everything)
    @Test func versionFlag() {
        let o = LaunchArguments.parse(["AA", "--version", "--data-dir", "/Volumes/NOPE"]) { _ in }
        #expect(o.version)
        #expect(o.dataDir == "/Volumes/NOPE")
    }

    @Test func snapshotArguments() {
        let id = UUID()
        let o = LaunchArguments.parse(["AA", "--data-dir", "/x", "--snapshot", "TabTasks", "--out", "/tmp/a.png",
                                       "--appearance", "dark", "--select", id.uuidString, "--sheet", "f3.prompt",
                                       "--size", "1280x820"]) { _ in }
        #expect(o.snapshot == SnapshotOptions(target: "TabTasks", out: "/tmp/a.png", appearance: "dark", select: id,
                                              sheet: "f3.prompt", size: "1280x820"))
        #expect(o.snapshot?.parsedSize?.width == 1280)
        #expect(SnapshotOptions(target: "x", out: "y", size: "abc").parsedSize == nil)
    }
}

@Suite struct ShellLaunchEnvironmentTests {
    // TV: 03 BD.7.2
    @Test func translocation() {
        #expect(Translocation.isTranslocated(bundlePath: "/private/var/folders/7k/x2/T/AppTranslocation/6F1E0C2A-1B2C-4D5E-8F90-A1B2C3D4E5F6/d/AA.app"))
        #expect(!Translocation.isTranslocated(bundlePath: "/Applications/AA.app"))
        #expect(!Translocation.isTranslocated(bundlePath: "/Users/u/Downloads/AA/AA.app"))
        #expect(!Translocation.isTranslocated(bundlePath: "/Volumes/STICK/AA.app"))
    }

    // TV: 03 BD.7.5 version line, SHELL-199 detection
    @Test func versionLine() {
        #expect(ShellLaunchEnvironment.versionLine(shortVersion: "1.0.0", build: "412", unbundled: false, arch: "arm64") == "AA 1.0.0 (412) arm64")
        #expect(ShellLaunchEnvironment.versionLine(shortVersion: nil, build: nil, unbundled: true, arch: "arm64") == "AA dev (unbundled) arm64")
        #expect(ShellLaunchEnvironment.isUnbundled(bundleIdentifier: nil, bundlePathExtension: "app"))
        #expect(ShellLaunchEnvironment.isUnbundled(bundleIdentifier: "com.eriskay.aa", bundlePathExtension: ""))
        #expect(!ShellLaunchEnvironment.isUnbundled(bundleIdentifier: "com.eriskay.aa", bundlePathExtension: "app"))
    }
}

@Suite struct ShellCrashLogTests {
    // TV: 03 BD.7.5 crash block
    @Test func blockFormat() {
        let zone = TimeZone(identifier: "Europe/Athens")!
        let wall = NetDateTime(year: 2026, month: 9, day: 30, hour: 14, minute: 3, second: 12, kind: .unspecified)
        let date = wall.foundationDate(zone: zone)
        let b = CrashLog.block(details: "X", at: date, zone: zone)
        #expect(b == "[2026-09-30 14:03:12] X\r\n\r\n")
        #expect(Array(b.utf8).suffix(4) == [0x0D, 0x0A, 0x0D, 0x0A])
    }

    // TV: 03 BD.7.5 fallback and "could not be written"
    @Test func fallbackAndDialog() throws {
        let t = TempFolder("aa-crash")
        let blocker = try t.write("blocked", "file")              // a FILE where the app folder should be
        let fallback = t.url.appending(path: "Logs/AA/crash.log")
        let written = CrashLog.append("boom", appFolder: blocker, fallback: fallback, at: Date())
        #expect(written == fallback)
        #expect(try t.readText("Logs/AA/crash.log").hasSuffix("boom\r\n\r\n"))
        #expect(CrashLog.dialogMessage(message: "m", writtenTo: fallback).hasSuffix("The full details were written to:\n\(fallback.path)"))
        let none = CrashLog.append("boom", appFolder: blocker, fallback: blocker.appending(path: "x/crash.log"), at: Date())
        #expect(none == nil)
        #expect(CrashLog.dialogMessage(message: "m", writtenTo: nil) == "AA hit an unexpected error and had to stop:\n\nm\n\nThe details could not be written to a log file.")

        let ok = CrashLog.append("first", appFolder: t.url, fallback: fallback, at: Date())
        #expect(ok == t.file("crash.log"))
        CrashLog.append("second", appFolder: t.url, fallback: fallback, at: Date())
        let text = try t.readText("crash.log")
        #expect(text.contains("] first\r\n\r\n[") && text.hasSuffix("] second\r\n\r\n"))
    }

    // TV: 03 BD.7.5 signal marker
    @Test func markerLine() {
        #expect(CrashLog.markerLine(signal: 5) == "[crash marker] signal 5\r\n\r\n")
        #expect(CrashLog.markers(in: "[x] a\r\n\r\n[crash marker] signal 5\r\n\r\n[crash marker] signal 11\r\n\r\n") == [5, 11])
    }
}

@Suite struct ShellLoginTests {
    // TV: 03 §7.1 "Login"
    @Test func credentials() {
        #expect(ShellLogin.check(username: " 44233 ", password: "redemption"))
        #expect(!ShellLogin.check(username: "44233", password: "Redemption"))
        #expect(!ShellLogin.check(username: "44233", password: " redemption"))
        #expect(!ShellLogin.check(username: "044233", password: "redemption"))
        #expect(ShellLogin.failureMessage == "Incorrect username or password.")
        #expect(ShellLogin.windowTitle == "AA — Sign in")
    }

    // TV: 03 §7.1 "Password dialog" (+ DECISIONS 01 Q-4 current password)
    @Test func passwordValidation() {
        let never: (String) -> Bool = { _ in false }
        let master: (String) -> Bool = { $0 == "redemption" }
        #expect(ShellPasswordMode.setNew.validate(password: "", confirm: "", current: nil, verifyUnlock: never, verifyCurrent: never) == "Password cannot be empty.")
        #expect(ShellPasswordMode.setNew.validate(password: "abc", confirm: "abc", current: nil, verifyUnlock: never, verifyCurrent: never) == "Password must be at least 4 characters.")
        #expect(ShellPasswordMode.setNew.validate(password: "abcd", confirm: "abce", current: nil, verifyUnlock: never, verifyCurrent: never) == "Passwords do not match.")
        #expect(ShellPasswordMode.setNew.validate(password: "abcd", confirm: "abcd", current: nil, verifyUnlock: never, verifyCurrent: never) == nil)
        #expect(ShellPasswordMode.unlock.validate(password: "x", confirm: "", current: nil, verifyUnlock: master, verifyCurrent: never) == "Wrong password.")
        #expect(ShellPasswordMode.unlock.validate(password: "redemption", confirm: "", current: nil, verifyUnlock: master, verifyCurrent: never) == nil)
        #expect(ShellPasswordMode.changeExisting.validate(password: "abcd", confirm: "abcd", current: "bad", verifyUnlock: never, verifyCurrent: master) == "Wrong password.")
        #expect(ShellPasswordMode.changeExisting.validate(password: "abcd", confirm: "abcd", current: "redemption", verifyUnlock: never, verifyCurrent: master) == nil)
        #expect(ShellPasswordMode.setNew.heading == "Set app password")
        #expect(ShellPasswordMode.changeExisting.asksCurrentPassword)
    }
}

@Suite struct ShellWindowGeometryTests {
    // TV: 03 §7.1 "Coordinate conversion"
    @Test func coordinateConversion() {
        let f = ShellRect(x: 100, y: 62, width: 1280, height: 820)
        let w = ShellWindowGeometry.wpfValues(frame: f, primaryScreenMaxY: 982)
        #expect(w.left == 100 && w.top == 100 && w.width == 1280 && w.height == 820)
        #expect(ShellWindowGeometry.macFrame(left: 100, top: 100, width: 1280, height: 820, primaryScreenMaxY: 982) == f)
    }

    // TV: 03 §7.1 "UiState restore"
    @Test func restoreRules() {
        let screen = [ShellRect(x: 0, y: 0, width: 1512, height: 982)]
        let cur = ShellRect(x: 116, y: 81, width: 1280, height: 820)
        let r = ShellWindowGeometry.restoredFrame(left: nil, top: nil, width: 150, height: 900, current: cur,
                                                  primaryScreenMaxY: 982, visibleFrames: screen)
        #expect(r?.width == 1280)                                  // ≤ 200 → unchanged (default)
        #expect(r?.height == 900)
        #expect(ShellWindowGeometry.restoredState("Minimized") == .normal)
        #expect(ShellWindowGeometry.restoredState("Maximized") == .maximized)
        #expect(ShellWindowGeometry.restoredState("maximized") == .normal)
        #expect(ShellWindowGeometry.restoredState("2") == .maximized)
        #expect(ShellWindowGeometry.restoredState("7") == .normal)
        #expect(ShellWindowGeometry.restoredFrame(left: nil, top: nil, width: nil, height: nil, current: cur,
                                                  primaryScreenMaxY: 982, visibleFrames: screen) == nil)
        // Off-screen geometry is clamped onto a visible screen (MAC-ADAPT).
        let off = ShellWindowGeometry.restoredFrame(left: 5000, top: 3000, width: 800, height: 600, current: cur,
                                                    primaryScreenMaxY: 982, visibleFrames: screen)!
        #expect(off.x >= 0 && off.maxX <= 1512 && off.y >= 0 && off.maxY <= 982)
    }

    @Test func statusTexts() {
        let t = NetDateTime(year: 2026, month: 10, day: 2, hour: 9, minute: 5, second: 7, kind: .local)
        #expect(ShellStatusText.saved(t) == "Saved 09:05:07")
        #expect(ShellStatusText.autosaveNoChanges(t) == "Autosave — no changes (09:05:07)")
        #expect(ShellStatusText.restored(7) == "Restored 7 deleted items (⌘Z).")
        #expect(ShellStatusText.restored(1) == "Restored the last deleted item (⌘Z).")
        #expect(ShellStatusText.windowTitle(identity: "Vessel-Alpha") == "AA — Vessel-Alpha")
        #expect(ShellStatusText.confirmImportMessage(sourceName: "x.zip") == "Replace your current data with 'x.zip'?\n(Could not read a change preview for this source.)")
    }
}
