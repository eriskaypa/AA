// Spec: 08 §2.5 (QUICK-150…156), §3.5 (Refresh, Csv), §4.5 (entries produced here), §4.6 (CSV byte format), §7.5
//       (T-AL-1…6); 02 REPO-092 (Activity log window), REPO-090 (producer); 02 T-LOG-4 (CSV quoting — the vector
//       F2 left to this owner).
import Foundation

/// One displayed row (a snapshot, 08 QUICK-152; newest first = the reverse of stored order, never a timestamp sort).
public struct ActivityLogRow: Sendable, Identifiable, Hashable {
    /// The entry's index in the stored log (stable for the snapshot).
    public var id: Int
    public var timeUtc: String
    public var timeLocal: String
    public var action: String
    public var kind: String
    public var name: String
    public var detail: String

    public init(id: Int, timeUtc: String, timeLocal: String, action: String, kind: String, name: String, detail: String) {
        self.id = id; self.timeUtc = timeUtc; self.timeLocal = timeLocal; self.action = action; self.kind = kind
        self.name = name; self.detail = detail
    }
}

public enum ActivityLogText {
    public static let windowTitle = "Activity log"
    public static let header = "Activity log"
    public static let filterPrompt = "Filter action / kind / name..."
    public static let exportButton = "Export (.csv)\u{2026}"
    public static let clearButton = "Clear log"
    public static let help = "Every entry added or removed is recorded with a UTC timestamp (newest first). Local time is shown alongside for convenience."
    public static let menuHelp = "UTC-timestamped log of every entry added and removed."
    public static let clearTitle = "Clear activity log"
    public static let exportTitle = "Export activity log"
    public static let exportFailedTitle = "Export failed"
    /// Column titles (08 QUICK-152).
    public static let columns = ["Time (UTC)", "Local time", "Action", "Kind", "Name", "Detail"]

    /// `"Clear all {n} activity-log entries? This can't be undone."`
    public static func clearMessage(_ n: Int) -> String { "Clear all \(n) activity-log entries? This can't be undone." }

    /// `"{shown} of {total} log entries."`
    public static func countLine(shown: Int, total: Int) -> String { "\(shown) of \(total) log entries." }
}

public enum ActivityLog {
    /// 08 QUICK-152/153: newest first (reverse of stored order); the trimmed filter keeps entries whose Action, Kind,
    /// Name or Detail contains it (OrdinalIgnoreCase); empty → all. Times: `yyyy-MM-dd HH:mm:ss UTC` and the local
    /// `yyyy-MM-dd HH:mm:ss` in `zone`.
    public static func rows(_ log: [LogEntry], filter: String, zone: TimeZone = .current) -> [ActivityLogRow] {
        let q = NetText.trim(filter)
        var out: [ActivityLogRow] = []
        out.reserveCapacity(log.count)
        for k in stride(from: log.count - 1, through: 0, by: -1) {
            let e = log[k]
            if !q.isEmpty && !(NetText.containsIgnoreCase(e.action, q) || NetText.containsIgnoreCase(e.kind, q)
                               || NetText.containsIgnoreCase(e.name, q) || NetText.containsIgnoreCase(e.detail, q)) {
                continue
            }
            out.append(ActivityLogRow(id: k, timeUtc: timeUtc(e), timeLocal: timeLocal(e, zone: zone), action: e.action,
                                      kind: e.kind, name: e.name, detail: e.detail))
        }
        return out
    }

    /// `LogEntry.TimeUtc`: `yyyy-MM-dd HH:mm:ss UTC` of the stored instant.
    public static func timeUtc(_ e: LogEntry) -> String {
        utcValue(e.timestampUtc).format(.isoSecond) + " UTC"
    }

    /// `LogEntry.TimeLocal`: `TimestampUtc.ToLocalTime()` as `yyyy-MM-dd HH:mm:ss` (evaluated in `zone`).
    public static func timeLocal(_ e: LogEntry, zone: TimeZone = .current) -> String {
        e.timestampUtc.toLocalTime(zone: zone).format(.isoSecond)
    }

    /// A `.local` stamp (hand-edited files) is shown as its UTC instant, like `.ToUniversalTime()`.
    static func utcValue(_ d: NetDateTime) -> NetDateTime {
        guard d.kind == .local else { return d }
        return NetDateTime(date: d.foundationDate(), kind: .utc)
    }

    /// 08 §3.5 `Csv(s)`: quoted (inner `"` doubled) when it contains `,`, `"` or `\n`; a lone `\r` does not quote.
    public static func csvField(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.unicodeScalars.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    /// 08 §4.6: UTF-8 without BOM, CRLF after every line, header `TimestampUTC,LocalTime,Action,Kind,Name,Detail`,
    /// then every entry in STORED (chronological) order, whatever the filter.
    public static func csv(_ log: [LogEntry], zone: TimeZone = .current) -> Data {
        var s = "TimestampUTC,LocalTime,Action,Kind,Name,Detail\r\n"
        for e in log {
            s += [timeUtc(e), timeLocal(e, zone: zone), e.action, e.kind, e.name, e.detail].map(csvField)
                .joined(separator: ",")
            s += "\r\n"
        }
        return Data(s.utf8)
    }

    /// `aa-activity-log-{UTC now:yyyyMMdd-HHmmss}.csv`.
    public static func exportFileName(utcNow: NetDateTime) -> String {
        "aa-activity-log-\(utcValue(utcNow).format(.stampSecond)).csv"
    }
}
