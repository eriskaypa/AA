// TV: 03 BD.4.7 (smoke report lines, byte for byte for the example), BD.3.12 (refusal rules, splash tolerance,
//     expectations), BD.3.13 (exit codes, watchdog), BD.7.6 negative cases (data folder already holding data / no
//     --data-dir → exit 3), BD.7.1 row 14 (`--data-dir --smoke-test` → no folder accepted → refused).
import Foundation
import Testing
@testable import AACore

@Suite struct ShellXSmokeTests {
    @Test func reportLinesMatchBD47() {
        #expect(ShellXSmoke.line("start", [("version", .string("1.0.0")), ("build", .string("412")),
                                           ("arch", .string("arm64")), ("appFolder", .string("/tmp/aa-smoke.Qx81/aa")),
                                           ("t", .seconds(0.004))])
                == #"{"event":"start","version":"1.0.0","build":"412","arch":"arm64","appFolder":"/tmp/aa-smoke.Qx81/aa","t":0.004}"#)
        #expect(ShellXSmoke.line("splash", [("t", .seconds(0.391))]) == #"{"event":"splash","t":0.391}"#)
        #expect(ShellXSmoke.line("login", [("t", .seconds(2.797)), ("splashSeconds", .seconds(2.406))])
                == #"{"event":"login","t":2.797,"splashSeconds":2.406}"#)
        #expect(ShellXSmoke.line("login-rejected", [("message", .string("Incorrect username or password."))])
                == #"{"event":"login-rejected","message":"Incorrect username or password."}"#)
        #expect(ShellXSmoke.line("main", [("t", .seconds(3.118)), ("title", .string("AA — Bridge-Mac")),
                                          ("status", .string("Loaded — /tmp/aa-smoke.Qx81/aa/data.json"))])
                == #"{"event":"main","t":3.118,"title":"AA — Bridge-Mac","status":"Loaded — /tmp/aa-smoke.Qx81/aa/data.json"}"#)
        #expect(ShellXSmoke.line("autosaved", [("t", .seconds(3.972)), ("bytes", .int(541)),
                                               ("lastDigestDate", .string("2026-09-30"))])
                == #"{"event":"autosaved","t":3.972,"bytes":541,"lastDigestDate":"2026-09-30"}"#)
        #expect(ShellXSmoke.line("quit", [("t", .seconds(4.103))]) == #"{"event":"quit","t":4.103}"#)
        #expect(ShellXSmoke.failLine(step: "login", expected: "2.3 ≤ splashSeconds ≤ 2.9", actual: "3.412")
                == #"{"event":"fail","step":"login","expected":"2.3 ≤ splashSeconds ≤ 2.9","actual":"3.412"}"#)
    }

    @Test func stringsAreJSONEscaped() {
        #expect(ShellXSmoke.line("x", [("s", .string("a\"b\\c\nd\te\u{01}"))])
                == #"{"event":"x","s":"a\"b\\c\nd\te\u0001"}"#)
        #expect(ShellXSmoke.line("x", [("t", .seconds(12.3456789))]) == #"{"event":"x","t":12.346}"#)
        #expect(ShellXSmoke.line("x", [("t", .seconds(0))]) == #"{"event":"x","t":0.000}"#)
    }

    @Test func refusalRules() throws {
        let folder = TempFolder("aa-smoke-ref")
        let fm = FileManager.default
        let exists: (String) -> Bool = { fm.fileExists(atPath: $0) }
        #expect(ShellXSmoke.refusal(dataDir: nil, appFolder: nil, fileExists: exists) == ShellXSmoke.needsDataDirMessage)
        #expect(ShellXSmoke.refusal(dataDir: "", appFolder: folder.url, fileExists: exists) == ShellXSmoke.needsDataDirMessage)
        #expect(ShellXSmoke.refusal(dataDir: "/x", appFolder: nil, fileExists: exists) == ShellXSmoke.needsDataDirMessage)
        // A new folder (not even created yet) and an empty folder are fine.
        #expect(ShellXSmoke.refusal(dataDir: "x", appFolder: folder.url.appending(path: "new"), fileExists: exists) == nil)
        #expect(ShellXSmoke.refusal(dataDir: "x", appFolder: folder.url, fileExists: exists) == nil)
        try folder.write("settings.json", "{}")
        #expect(ShellXSmoke.refusal(dataDir: "x", appFolder: folder.url, fileExists: exists)
                == "--smoke-test refuses to run on a data folder that already holds data: \(folder.url.path)")
        try fm.removeItem(at: folder.file("settings.json"))
        try folder.write("data.json", Goldens.freshDB)
        #expect(ShellXSmoke.refusal(dataDir: "x", appFolder: folder.url, fileExists: exists) != nil)
        #expect(ShellXSmoke.needsDataDirMessage == "--smoke-test needs --data-dir <empty folder>")
    }

    @Test func dataDirArgumentRules() {
        // BD.7.1 row 14: `--data-dir --smoke-test` → no folder accepted, smokeTest set → the harness refuses.
        var warnings: [String] = []
        let opts = LaunchArguments.parse(["AA", "--data-dir", "--smoke-test"]) { warnings.append($0) }
        #expect(opts.smokeTest && opts.dataDir == nil && warnings.count == 1)
        #expect(ShellXSmoke.refusal(dataDir: opts.dataDir, appFolder: nil, fileExists: { _ in false }) != nil)
    }

    @Test func constantsAndExpectations() {
        #expect(ShellXSmoke.exitOK == 0 && ShellXSmoke.exitFailed == 1 && ShellXSmoke.exitTimeout == 2
                && ShellXSmoke.exitRefused == 3)
        #expect(ShellXSmoke.watchdogSeconds == 30 && ShellXSmoke.autosaveBudgetSeconds == 3)
        #expect(ShellXSmoke.splashOK(2.3) && ShellXSmoke.splashOK(2.406) && ShellXSmoke.splashOK(2.9))
        #expect(!ShellXSmoke.splashOK(2.29) && !ShellXSmoke.splashOK(3.412))
        #expect(ShellXSmoke.expectedTitle(identity: "Bridge-Mac") == "AA — Bridge-Mac")
        #expect(ShellXSmoke.expectedStatus(appFolder: URL(fileURLWithPath: "/tmp/aa-smoke.Qx81/aa"))
                == "Loaded — /tmp/aa-smoke.Qx81/aa/data.json")
        #expect(ShellLogin.check(username: ShellXSmoke.spacedUsername, password: ShellXSmoke.password))
        #expect(!ShellLogin.check(username: ShellXSmoke.username, password: ShellXSmoke.wrongPassword))
    }
}
