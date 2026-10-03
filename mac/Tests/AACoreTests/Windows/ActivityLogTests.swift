// Tests for 08 §7.5 (T-AL-1…6), 08 §4.6 (CSV byte format), 02 T-LOG-4 (CSV quoting), 02 REPO-092.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct ActivityLogTests {
    func entry(_ utc: String, _ action: String, _ kind: String, _ name: String, _ detail: String = "") -> LogEntry {
        LogEntry(timestampUtc: NetDateTime(parsing: utc)!, action: action, kind: kind, name: name, detail: detail)
    }

    @Test func csvQuoting() {
        // TV: 08 T-AL-1; 02 T-LOG-4
        #expect(ActivityLog.csvField("Pump, \"main\"") == "\"Pump, \"\"main\"\"\"")
        #expect(ActivityLog.csvField("a\rb") == "a\rb")
        #expect(ActivityLog.csvField("a\nb") == "\"a\nb\"")
        #expect(ActivityLog.csvField("a\r\nb") == "\"a\r\nb\"")
        #expect(ActivityLog.csvField("plain") == "plain")
        #expect(ActivityLog.csvField("") == "")
        // .NET tests and doubles per UTF-16 char: a `,` / `"` carrying a combining mark still quotes / doubles.
        #expect(ActivityLog.csvField("a,\u{0301}b") == "\"a,\u{0301}b\"")
        #expect(ActivityLog.csvField("x\"\u{0301}") == "\"x\"\"\u{0301}\"")
    }

    @Test func csvLineAndHeader() throws {
        // TV: 08 T-AL-2 (Athens, UTC+3 in September; no BOM; CRLF after every line)
        let e = entry("2026-09-29T11:03:12Z", "Added", "Task", "Fire drill")
        let data = ActivityLog.csv([e], zone: TZ.athens)
        #expect(data.prefix(3) != Data([0xEF, 0xBB, 0xBF]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text == "TimestampUTC,LocalTime,Action,Kind,Name,Detail\r\n2026-09-29 11:03:12 UTC,2026-09-29 14:03:12,Added,Task,Fire drill,\r\n")
    }

    @Test func orderUIReversedCSVChronological() {
        // TV: 08 T-AL-3
        let log = [entry("2026-09-29T10:00:00Z", "Added", "Task", "e1"),
                   entry("2026-09-29T11:00:00Z", "Added", "Task", "e2"),
                   entry("2026-09-29T12:00:00Z", "Removed", "Task", "e3")]
        #expect(ActivityLog.rows(log, filter: "", zone: TZ.athens).map(\.name) == ["e3", "e2", "e1"])
        #expect(ActivityLog.rows(log, filter: "e3", zone: TZ.athens).map(\.name) == ["e3"])
        let csv = String(decoding: ActivityLog.csv(log, zone: TZ.athens), as: UTF8.self)
        let names = csv.components(separatedBy: "\r\n").dropFirst().filter { !$0.isEmpty }.map { $0.split(separator: ",")[4] }
        #expect(names == ["e1", "e2", "e3"])
    }

    @Test func filterAndCount() {
        // TV: 08 T-AL-4
        var log: [LogEntry] = (0..<55).map { entry("2026-09-29T10:00:00Z", "Added", "Task", "item \($0)") }
        log.append(entry("2026-09-29T10:00:00Z", "Added", "Subtask", "3 added (bulk)", "Engine"))
        log.append(entry("2026-09-29T10:00:00Z", "Added", "Task", "Pump", "restored from Trash"))
        #expect(ActivityLog.rows(log, filter: "  bulk ", zone: TZ.athens).map(\.name) == ["3 added (bulk)"])
        #expect(ActivityLog.rows(log, filter: "RESTORED", zone: TZ.athens).map(\.detail) == ["restored from Trash"])
        let shown = ActivityLog.rows(log, filter: "bulk", zone: TZ.athens).count
            + ActivityLog.rows(log, filter: "restored", zone: TZ.athens).count
        #expect(ActivityLogText.countLine(shown: shown, total: log.count) == "2 of 57 log entries.")
        #expect(ActivityLog.rows(log, filter: "subtask", zone: TZ.athens).count == 1)
    }

    @Test func capAndNameNormalization() {
        // TV: 08 T-AL-5, T-AL-6 (producer contract, F2's API seen from this window)
        let made = StoreFactory.make(); let store = made.store
        store.data.log = (0..<AppStore.maxLogEntries).map { entry("2026-09-29T10:00:00Z", "Added", "Task", "n\($0)") }
        store.logAdded(kind: "Task", name: "  x  ")
        #expect(store.data.log.count == 10_000)
        #expect(store.data.log.first?.name == "n1" && store.data.log.last?.name == "x")
        store.logAdded(kind: "Task", name: "")
        #expect(store.data.log.last?.name == "(unnamed)")
        #expect(ActivityLog.rows(store.data.log, filter: "", zone: TZ.athens).first?.name == "(unnamed)")
    }

    @Test func timesAndFileName() {
        // TV: 02 REPO-092 (`2026-09-29 08:15:30 UTC`), 08 QUICK-155 default name
        let e = entry("2026-09-29T08:15:30Z", "Added", "Task", "x")
        #expect(ActivityLog.timeUtc(e) == "2026-09-29 08:15:30 UTC")
        #expect(ActivityLog.timeLocal(e, zone: TZ.newYork) == "2026-09-29 04:15:30")
        // An offset-bearing stamp is a .NET Local value: `TimeUtc` prints its (machine-local) wall clock unconverted,
        // `TimeLocal` (`ToLocalTime()` of a Local value) prints the same wall clock.
        let local = entry("2026-09-29T11:15:30+03:00", "Added", "Task", "y")
        #expect(ActivityLog.timeUtc(local) == local.timestampUtc.format(.isoSecond) + " UTC")
        #expect(ActivityLog.timeUtc(local) == ActivityLog.timeLocal(local) + " UTC")
        #expect(ActivityLog.exportFileName(utcNow: NetDateTime(parsing: "2026-10-02T07:08:09Z")!)
                == "aa-activity-log-20261002-070809.csv")
        #expect(ActivityLogText.clearMessage(12) == "Clear all 12 activity-log entries? This can't be undone.")
    }

    @Test func clearLog() throws {
        // TV: 08 QUICK-154 (clearing is not itself logged)
        let made = StoreFactory.make(); let store = made.store
        store.logAdded(kind: "Task", name: "a")
        store.clearLog()
        #expect(store.data.log.isEmpty)
    }
}
