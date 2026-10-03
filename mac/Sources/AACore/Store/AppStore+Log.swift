// Spec: 02 §2.I, §3.1.4 (REPO-090, REPO-091 Kind strings), 01 DATA-115, 08 QUICK-154; ARCHITECTURE.md §5.3.
import Foundation

extension AppStore {
    /// REPO-090 / DATA-115: the log keeps at most this many entries (oldest removed first).
    public static let maxLogEntries = 10_000

    /// REPO-090: appends `Added / kind / name / detail` stamped `UtcNow`. `name` is trimmed (.NET `Trim`), or
    /// `"(unnamed)"` when nil/whitespace; `detail` nil → `""`. Trims the log from the front to 10 000, marks dirty.
    public func logAdded(kind: String, name: String?, detail: String? = "") {
        repoLog(action: "Added", kind: kind, name: name, detail: detail)
    }

    /// REPO-090: as `logAdded` with Action `"Removed"`.
    public func logRemoved(kind: String, name: String?, detail: String? = "") {
        repoLog(action: "Removed", kind: kind, name: name, detail: detail)
    }

    /// QUICK-154: removes every entry (the caller confirms and saves). No-op when already empty.
    public func clearLog() {
        guard !data.log.isEmpty else { return }
        data.log.removeAll()
        markDirty()
    }

    private func repoLog(action: String, kind: String, name: String?, detail: String?) {
        let entry = LogEntry(timestampUtc: clock.utcNow(), action: action, kind: kind,
                             name: NetText.isBlank(name) ? "(unnamed)" : NetText.trim(name ?? ""),
                             detail: detail ?? "")
        data.log.append(entry)
        let excess = data.log.count - Self.maxLogEntries
        if excess > 0 { data.log.removeFirst(excess) }
        markDirty()
    }
}
