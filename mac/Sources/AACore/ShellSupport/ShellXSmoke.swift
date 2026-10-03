// Spec: 03 SHELL-205 / BD.3.12 (smoke-test harness: refusal rules, expectations, exit codes, watchdog), BD.4.7 (the
//       report: one JSON object per line, seconds with 3 decimals, JSON-escaped strings), BD.3.13 (constants), BD.7.6;
//       REQ-F3-01 (AAMain calls `SmokeTest.run(options:)` before the app: non-zero = refused, 0 = armed).
import Foundation

/// The pure parts of `--smoke-test`: constants, refusal rules, expectations and the JSON-line report.
public enum ShellXSmoke {
    // MARK: Exit codes (BD.3.13)

    public static let exitOK: Int32 = 0
    public static let exitFailed: Int32 = 1
    public static let exitTimeout: Int32 = 2
    public static let exitRefused: Int32 = 3

    // MARK: Timing (BD.3.12 / BD.3.13)

    public static let watchdogSeconds: Double = 30
    /// `data.json` must appear within this many seconds after the main window.
    public static let autosaveBudgetSeconds: Double = 3
    public static let pollMilliseconds = 100
    /// The real splash lasts 2.4 s; the smoke accepts 2.3 … 2.9 s from splash-visible to login-visible.
    public static let splashRange: ClosedRange<Double> = 2.3...2.9

    // MARK: Credentials the harness types (the real login model; BD.3.12)

    public static let username = "44233"
    /// The spaces also prove the Trim rule on the username.
    public static let spacedUsername = " 44233 "
    public static let wrongPassword = "wrong"
    public static let password = "redemption"

    // MARK: Refusal (exit 3)

    public static let needsDataDirMessage = "--smoke-test needs --data-dir <empty folder>"
    public static func holdsDataMessage(_ path: String) -> String {
        "--smoke-test refuses to run on a data folder that already holds data: \(path)"
    }

    /// nil when the harness may run: `--data-dir` was accepted and the folder holds neither `data.json` nor
    /// `settings.json` (so it can never run on real data). `appFolder` is the resolved AppFolder (nil when the
    /// resolution itself failed — a Windows path, for example — which also refuses).
    public static func refusal(dataDir: String?, appFolder: URL?, fileExists: (String) -> Bool) -> String? {
        guard let dataDir, !dataDir.isEmpty, let appFolder else { return needsDataDirMessage }
        let data = appFolder.appending(path: "data.json").path
        let settings = appFolder.appending(path: "settings.json").path
        if fileExists(data) || fileExists(settings) { return holdsDataMessage(appFolder.path) }
        return nil
    }

    // MARK: Expectations

    public static func expectedTitle(identity: String) -> String { "AA — \(identity)" }
    /// `Loaded — {AppFolder}/data.json`, with the path as given (symlinks unresolved, like DataStore, which keeps a
    /// `/private/…` spelling).
    public static func expectedStatus(appFolder: URL) -> String {
        "Loaded — \(DataStore.lexical(appFolder.appending(path: "data.json")).path)"
    }
    public static let splashExpectation = "2.3 ≤ splashSeconds ≤ 2.9"
    public static func splashOK(_ seconds: Double) -> Bool { splashRange.contains(seconds) }

    // MARK: Report (BD.4.7)

    /// One value of a report line.
    public enum Value: Sendable, Equatable {
        case string(String)
        /// Seconds (or any fractional number) — written with exactly 3 decimals.
        case seconds(Double)
        case int(Int)
    }

    /// `{"event":"<name>", …fields in order}` — compact, strings JSON-escaped (quotes, backslashes, control
    /// characters; other characters stay literal as in the BD.4.7 example).
    public static func line(_ event: String, _ fields: [(String, Value)] = []) -> String {
        var parts = ["\"event\":" + quote(event)]
        for (k, v) in fields {
            let text: String
            switch v {
            case .string(let s): text = quote(s)
            case .seconds(let d): text = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), d)
            case .int(let i): text = String(i)
            }
            parts.append(quote(k) + ":" + text)
        }
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// `{"event":"fail","step":…,"expected":…,"actual":…}`.
    public static func failLine(step: String, expected: String, actual: String) -> String {
        line("fail", [("step", .string(step)), ("expected", .string(expected)), ("actual", .string(actual))])
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 {
                    out += String(format: "\\u%04x", u.value)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out + "\""
    }
}
