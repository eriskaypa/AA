// Spec: 13 FLASH-135 (optional rich review sheet: per-collection breakdown — sets / deletes / blocks / removals in red /
//       settings / layout — under the exact FLASH-044 summary line), FLASH-044, FLASH-132, DECISIONS 13 (rich review
//       sheet: yes). Pure, so the rows are testable; the sheet only lays them out.

/// One row of the review sheet's breakdown.
public struct FlashReviewRow: Sendable, Equatable, Identifiable {
    public enum Tone: Sendable, Equatable { case added, changed, removed, neutral }

    public let id: Int
    public let title: String
    public let detail: String
    public let tone: Tone
    /// An SF Symbol name for the row.
    public let symbol: String

    public init(id: Int, title: String, detail: String, tone: Tone, symbol: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.tone = tone
        self.symbol = symbol
    }
}

public enum FlashReviewBreakdown {
    /// The breakdown rows for an incoming change, in the order the apply runs.
    public static func rows(for change: FlashIncomingChange) -> [FlashReviewRow] {
        var rows: [FlashReviewRow] = []
        func add(_ title: String, _ detail: String, _ tone: FlashReviewRow.Tone, _ symbol: String) {
            rows.append(FlashReviewRow(id: rows.count, title: title, detail: detail, tone: tone, symbol: symbol))
        }
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        let p = change.payload

        if change.isSnapshot {
            let data = FlashChangeSet.isSnapshotEnvelope(.object(p)) ? (p["Data"]?.objectValue ?? JSONObject()) : p
            add("Whole database", "replaces everything on this Mac", .removed, "externaldrive.badge.exclamationmark")
            for (name, value) in data where !FlashChangeSet.isExcludedDataKey(name) {
                if case .array(let a) = value { add(name, plural(a.count, "item"), .changed, "list.bullet") }
            }
            if case .object? = data["Ui"] { add("Layout", "shared preferences replaced; this Mac's window layout kept", .changed, "rectangle.3.group") }
            if change.carriesSettings {
                let n = (p["Settings"]?.objectValue ?? JSONObject()).filter { !FlashChangeSet.isExcludedSettingsKey($0.key) }.count
                add("Settings", plural(n, "setting") + " merged", .changed, "gearshape")
            } else {
                add("Settings", "not carried — dark mode etc. stay as they are", .neutral, "gearshape")
            }
            return rows
        }

        if case .object(let sets)? = p["Sets"] {
            for (name, arr) in sets where !FlashChangeSet.isExcludedDataKey(name) {
                if case .array(let a) = arr, !a.isEmpty { add(name, plural(a.count, "item") + " added or changed", .added, "plus.circle") }
            }
        }
        if case .object(let dels)? = p["Deletes"] {
            for (name, arr) in dels where !FlashChangeSet.isExcludedDataKey(name) {
                if case .array(let a) = arr, !a.isEmpty { add(name, plural(a.count, "item") + " deleted", .removed, "minus.circle") }
            }
        }
        if case .object(let order)? = p["Order"] {
            for (name, _) in order where !FlashChangeSet.isExcludedDataKey(name) { add(name, "reordered", .changed, "arrow.up.arrow.down") }
        }
        if case .object(let blocks)? = p["Blocks"] {
            for (name, _) in blocks where !FlashChangeSet.isExcludedDataKey(name) { add(name, "replaced as a whole", .changed, "square.stack.3d.up") }
        }
        let uiChanged = (p["UiChanges"]?.objectValue?.filter { !FlashChangeSet.isPerDeviceUiKey($0.key) }.count ?? 0)
            + (p["Blocks"]?.objectValue?["Ui"]?.objectValue?.filter { !FlashChangeSet.isPerDeviceUiKey($0.key) }.count ?? 0)
            + (p["Ui"]?.objectValue?.filter { !FlashChangeSet.isPerDeviceUiKey($0.key) }.count ?? 0)
        let uiRemoved = (p["UiDeletes"]?.arrayValue ?? []).filter { !FlashChangeSet.isPerDeviceUiKey($0.idText ?? "") }.count
        if uiChanged + uiRemoved > 0 {
            var parts: [String] = []
            if uiChanged > 0 { parts.append(plural(uiChanged, "preference") + " changed") }
            if uiRemoved > 0 { parts.append("\(uiRemoved) removed") }
            add("Layout", parts.joined(separator: ", "), .changed, "rectangle.3.group")
        }
        if case .array(let bd)? = p["BlockDeletes"] {
            for n in bd {
                let k = n.idText ?? "?"
                if !FlashChangeSet.isExcludedDataKey(k) { add(k, "REMOVED entirely", .removed, "trash") }
            }
        }
        if case .object(let s)? = p["Settings"] {
            let n = s.filter { !FlashChangeSet.isExcludedSettingsKey($0.key) }.count
            add("Settings", n == 0 ? "no shareable settings changed" : plural(n, "setting") + " merged", .changed, "gearshape")
        }
        if case .array(let sd)? = p["SettingsDeletes"] {
            let n = sd.filter { !FlashChangeSet.isExcludedSettingsKey($0.idText ?? "") }.count
            if n > 0 { add("Settings", "clears " + plural(n, "setting"), .removed, "gearshape.2") }
        }
        if rows.isEmpty { add("Other changes", "nothing this build can list in detail", .neutral, "ellipsis.circle") }
        return rows
    }
}
