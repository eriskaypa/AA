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

    /// QUICK-150 default window width (points; F3's scene `defaultSize`).
    public static let windowWidth = 860.0
    /// What the inset `Table` adds around its columns: leading / trailing inset plus the intercell gaps (measured 88 pt
    /// for six columns on macOS 26: column edges at 0 / 181 / 329 / 408 / 521 / 688 / 832 for ideals summing to
    /// 744), and a legacy (always-shown) vertical scroller when a mouse is attached.
    public static let tableChromeWidth = 88.0, legacyScrollerWidth = 15.0

    /// Column widths in points, in `columns` order (V2-J7 / V2-DESIGN). The WPF widths (170 / 150 / 80 / 130 / 200 /
    /// 200 = 930) overflow its own 860-px window; on the Mac every column fits: the two times and the Action capsule
    /// are sized to their fixed formats in 11-pt brand mono, Kind holds `Equipment/Area` on one line, Name and Detail
    /// share the rest and wrap (Detail also takes any extra width).
    public static let columnWidths: [(min: Double, ideal: Double)] = [
        (158, 158),   // `yyyy-MM-dd HH:mm:ss UTC` (23 × 6.8 pt)
        (130, 130),   // `yyyy-MM-dd HH:mm:ss` (19 × 6.6 pt)
        (62, 62),     // `Removed` capsule (7 × 6.6 + 12)
        (96, 96),     // `Equipment/Area` (14 × 6.6 pt)
        (120, 160),   // Name (wraps)
        (96, 130),    // Detail (wraps, flexible)
    ]

    /// The width the table needs at its ideal column widths (with a legacy scroller showing); never more than
    /// `windowWidth`, so no column runs past the window edge (V-DESIGN rule 5).
    public static var idealTableWidth: Double {
        columnWidths.reduce(0) { $0 + $1.ideal } + tableChromeWidth + legacyScrollerWidth
    }

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

    /// `LogEntry.TimeUtc` = `TimestampUtc.ToString("yyyy-MM-dd HH:mm:ss 'UTC'")` — the stored wall clock, NOT converted
    /// (P3 / §4.6 byte parity): a `Z` stamp prints its UTC time; an offset-bearing stamp from a hand-edited file was
    /// read as a .NET Local value, so Windows prints its local wall clock with the ` UTC` suffix, and so does the Mac.
    public static func timeUtc(_ e: LogEntry) -> String {
        e.timestampUtc.format(.isoSecond) + " UTC"
    }

    /// `LogEntry.TimeLocal`: `TimestampUtc.ToLocalTime()` as `yyyy-MM-dd HH:mm:ss` (evaluated in `zone`).
    public static func timeLocal(_ e: LogEntry, zone: TimeZone = .current) -> String {
        e.timestampUtc.toLocalTime(zone: zone).format(.isoSecond)
    }

    /// `DateTime.UtcNow` for the export file name: a `.local` clock value is converted to its UTC instant.
    static func utcValue(_ d: NetDateTime) -> NetDateTime {
        guard d.kind == .local else { return d }
        return NetDateTime(date: d.foundationDate(), kind: .utc)
    }

    /// 08 §3.5 `Csv(s)`: quoted (inner `"` doubled) when it contains `,`, `"` or `\n`; a lone `\r` does not quote.
    /// The test runs per scalar (like .NET's per-char `Contains`), so `,` / `"` / `\n` inside a grapheme cluster
    /// (`,` + a combining mark, `\r\n`) still quote.
    public static func csvField(_ s: String) -> String {
        if s.unicodeScalars.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
            var out = String.UnicodeScalarView()
            out.append("\"")
            for u in s.unicodeScalars {
                out.append(u)
                if u == "\"" { out.append("\"") }
            }
            out.append("\"")
            return String(out)
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
