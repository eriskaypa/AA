// Spec: 10 §D (VESSEL-100…123), §3.5 (ShipJobsPanel algorithms: PopulateFilters / FillCombo, upsert, filters, sort,
//       DueInfo, UpdateSummary, UpdateNotifications, TargetRows), §3.4.5 (DaysUntilDue on calendar dates), §7.10–7.13.
import Foundation

/// The fixed due colours (both appearances, VESSEL-110): Red #D45050, Orange #E8890C, Amber #C9A227, Green #2E9E5B,
/// Gray #8A8A8A.
public enum WorkOrderTone: String, Sendable, Hashable {
    case red, orange, amber, green, gray

    public var hex: String {
        switch self {
        case .red: return "#FFD45050"
        case .orange: return "#FFE8890C"
        case .amber: return "#FFC9A227"
        case .green: return "#FF2E9E5B"
        case .gray: return "#FF8A8A8A"
        }
    }
}

/// `Completion` combo (VESSEL-106).
public enum WorkOrderCompletionFilter: Int, Sendable, Hashable, CaseIterable {
    case all = 0, activeOnly = 1, completedOnly = 2

    public var label: String {
        switch self {
        case .all: return "All"
        case .activeOnly: return "Active only"
        case .completedOnly: return "Completed only"
        }
    }
}

/// Sortable columns (VESSEL-109 headers, VESSEL-111 keys).
public enum WorkOrderColumn: String, Sendable, Hashable, CaseIterable {
    case done = "Done", notify = "Notify", jobNo = "Job No.", title = "Title", due = "Due", interval = "Interval"
    case status = "Status", dueStatus = "Due Status", category = "Category", responsible = "Responsible"
    case function = "Function"

    /// Windows column width (VESSEL-109).
    public var width: Double {
        switch self {
        case .done: return 48
        case .notify: return 52
        case .jobNo: return 110
        case .title: return 260
        case .due: return 150
        case .interval: return 80
        case .status: return 90
        case .dueStatus: return 90
        case .category: return 80
        case .responsible: return 130
        case .function: return 220
        }
    }
}

/// Every filter of the Work Orders toolbar (combined with AND in this order: search → status → category → rank →
/// completion → due-soon → notify, VESSEL-104…108).
public struct WorkOrderFilter: Sendable, Hashable {
    public var query: String = ""
    /// nil = "(all …)".
    public var status: String? = nil
    public var category: String? = nil
    public var rank: String? = nil
    public var completion: WorkOrderCompletionFilter = .all
    public var dueSoonOnly = false
    public var notifyOnly = false

    public init(query: String = "", status: String? = nil, category: String? = nil, rank: String? = nil,
                completion: WorkOrderCompletionFilter = .all, dueSoonOnly: Bool = false, notifyOnly: Bool = false) {
        self.query = query; self.status = status; self.category = category; self.rank = rank
        self.completion = completion; self.dueSoonOnly = dueSoonOnly; self.notifyOnly = notifyOnly
    }
}

/// The notifications bar state (VESSEL-120). `tone == nil` means "theme foreground text, gray border" (state 2).
public struct WorkOrderBarState: Sendable, Hashable {
    public var text: String
    public var borderTone: WorkOrderTone
    /// nil → the theme `Fg` colour.
    public var textTone: WorkOrderTone?
    public init(text: String, borderTone: WorkOrderTone, textTone: WorkOrderTone?) {
        self.text = text; self.borderTone = borderTone; self.textTone = textTone
    }
}

@MainActor public enum WorkOrderAnalysis {
    /// `DueSoonDays` (VESSEL-107).
    public static let dueSoonDays = 90

    public static let allStatuses = "(all statuses)"
    public static let allCategories = "(all categories)"
    public static let allRanks = "(all ranks)"

    // MARK: Strings (VESSEL-100…120)

    public static let noJobsSummary = "No work orders imported yet for this ship. Click “Import Shippalm (.xlsx)...”."
    public static let noShipSummary = "No ship selected."
    public static let readingSummary = "Reading Shippalm export… (large files take a few seconds)"
    public static let searchPlaceholder = "Search job no / title / function..."
    public static let noTargetsHint = "No work orders to update — select rows, or clear filters so some are shown."
    public static let selectToDeleteHint = "Select one or more work orders to delete."
    public static let exportEmptyMessage = "No work orders to export for this ship."

    public static func importedHint(count: Int, vessel: String, added: Int, updated: Int) -> String {
        "Imported \(count) work orders for \(vessel) (\(added) new, \(updated) updated)."
    }
    public static func exportedHint(count: Int, vessel: String) -> String { "Exported \(count) work orders for \(vessel)." }
    public static func markedHint(count: Int, done: Bool) -> String {
        "Marked \(count) work order(s) \(done ? "completed" : "active")."
    }
    public static func notifyTargetHint(count: Int, on: Bool) -> String {
        "Notifications turned \(on ? "ON" : "OFF") for \(count) work order(s)."
    }
    public static func notifyShownHint(count: Int, on: Bool) -> String {
        "Notifications turned \(on ? "ON" : "OFF") for \(count) shown job(s)."
    }
    public static func deleteConfirmMessage(count: Int, vessel: String) -> String {
        "Delete \(count) work order(s) from \(vessel)? This is permanent (re-import to restore)."
    }
    public static func deletedHint(count: Int, vessel: String) -> String { "Deleted \(count) work order(s) from \(vessel)." }
    public static func importDialogTitle(_ vessel: String) -> String { "Import Shippalm Work Order List for \(vessel)" }
    public static func exportDialogTitle(_ vessel: String) -> String { "Export work orders for \(vessel)" }

    // MARK: Upsert (VESSEL-102)

    public struct UpsertResult: Sendable, Equatable {
        public var added: Int
        public var updated: Int
        public init(added: Int, updated: Int) { self.added = added; self.updated = updated }
    }

    /// Upserts parsed jobs by `JobNo` (OIC; the FIRST existing job of each group is the target). An existing job keeps
    /// its `Notify`, `IsCompleted` and `CompletedDate` and takes every other field (including `JobNo` casing) from the
    /// file; a new job is appended. Jobs absent from the file are kept. Linear.
    @discardableResult
    public static func upsert(into vessel: Vessel, parsed: [ShipJob]) -> UpsertResult {
        var byNo: [String: ShipJob] = [:]
        for j in vessel.jobs {
            let k = NetText.toUpperInvariant(j.jobNo)
            if byNo[k] == nil { byNo[k] = j }
        }
        var added = 0, updated = 0
        var appended: [ShipJob] = []
        for j in parsed {
            let k = NetText.toUpperInvariant(j.jobNo)
            if let existing = byNo[k] {
                j.notify = existing.notify
                j.isCompleted = existing.isCompleted
                j.completedDate = existing.completedDate
                existing.copy(from: j)
                updated += 1
            } else {
                appended.append(j)
                byNo[k] = j
                added += 1
            }
        }
        if !appended.isEmpty { vessel.jobs.append(contentsOf: appended) }
        return UpsertResult(added: added, updated: updated)
    }

    // MARK: Filter combos (VESSEL-105)

    /// `(allLabel)` + the distinct non-blank values (OIC distinct, first-seen casing), sorted OIC.
    public static func comboItems(allLabel: String, values: [String]) -> [String] {
        var seen = Set<String>()
        var distinct: [String] = []
        for v in values where !NetText.isBlank(v) {
            if seen.insert(NetText.toUpperInvariant(v)).inserted { distinct.append(v) }
        }
        let sorted = PortsService.stableSorted(distinct) { NetText.compareIgnoreCase($0, $1) == .orderedAscending }
        return [allLabel] + sorted
    }

    /// Repopulation keeps the previous selection when the new list contains the identical (case-sensitive) string.
    public static func keepSelection(_ previous: String?, in items: [String]) -> String? {
        guard let previous, items.dropFirst().contains(where: { Ordinal.equals($0, previous) }) else { return nil }
        return previous
    }

    public static func statusItems(_ jobs: [ShipJob]) -> [String] { comboItems(allLabel: allStatuses, values: jobs.map(\.status)) }
    public static func categoryItems(_ jobs: [ShipJob]) -> [String] { comboItems(allLabel: allCategories, values: jobs.map(\.category)) }
    public static func rankItems(_ jobs: [ShipJob]) -> [String] { comboItems(allLabel: allRanks, values: jobs.map(\.responsibleRank)) }

    // MARK: Filter + sort (VESSEL-104…111)

    /// Precomputed per-job keys so a 2 500-row rebuild parses each due date once.
    public struct Keyed {
        public let job: ShipJob
        public let days: Int?
    }

    public static func keyed(_ jobs: [ShipJob], today: CivilDate) -> [Keyed] {
        jobs.map { Keyed(job: $0, days: $0.daysUntilDue(today: today)) }
    }

    /// Filters in the Windows order; the returned rows are then sorted with `sort`.
    public static func filter(_ rows: [Keyed], _ f: WorkOrderFilter) -> [Keyed] {
        let q = NetText.trim(f.query)
        return rows.filter { k in
            let j = k.job
            if !q.isEmpty && !(NetText.containsIgnoreCase(j.jobNo, q) || NetText.containsIgnoreCase(j.title, q)
                               || NetText.containsIgnoreCase(j.functionDescription, q)
                               || NetText.containsIgnoreCase(j.responsibleRank, q)) { return false }
            if let s = f.status, !NetText.equalsIgnoreCase(j.status, s) { return false }
            if let c = f.category, !NetText.equalsIgnoreCase(j.category, c) { return false }
            if let r = f.rank, !NetText.equalsIgnoreCase(j.responsibleRank, r) { return false }
            switch f.completion {
            case .all: break
            case .activeOnly: if j.isCompleted { return false }
            case .completedOnly: if !j.isCompleted { return false }
            }
            if f.dueSoonOnly {
                guard !j.isCompleted, let d = k.days, d <= dueSoonDays else { return false }
            }
            if f.notifyOnly && !j.notify { return false }
            return true
        }
    }

    /// VESSEL-111: column keys (strings OIC; booleans false < true; `Due` = (IsCompleted, days ?? Int.max), both keys
    /// reversed when descending), then ALWAYS `JobNo` ascending OIC; stable.
    public static func sort(_ rows: [Keyed], by column: WorkOrderColumn, descending: Bool) -> [Keyed] {
        func primary(_ a: Keyed, _ b: Keyed) -> ComparisonResult {
            switch column {
            case .jobNo: return NetText.compareIgnoreCase(a.job.jobNo, b.job.jobNo)
            case .title: return NetText.compareIgnoreCase(a.job.title, b.job.title)
            case .interval: return NetText.compareIgnoreCase(a.job.interval, b.job.interval)
            case .status: return NetText.compareIgnoreCase(a.job.status, b.job.status)
            case .dueStatus: return NetText.compareIgnoreCase(a.job.dueStatus, b.job.dueStatus)
            case .category: return NetText.compareIgnoreCase(a.job.category, b.job.category)
            case .responsible: return NetText.compareIgnoreCase(a.job.responsibleRank, b.job.responsibleRank)
            case .function: return NetText.compareIgnoreCase(a.job.functionDescription, b.job.functionDescription)
            case .done: return compareBool(a.job.isCompleted, b.job.isCompleted)
            case .notify: return compareBool(a.job.notify, b.job.notify)
            case .due:
                let c = compareBool(a.job.isCompleted, b.job.isCompleted)
                if c != .orderedSame { return c }
                let da = a.days ?? Int.max, db = b.days ?? Int.max
                return da == db ? .orderedSame : (da < db ? .orderedAscending : .orderedDescending)
            }
        }
        let indexed = rows.enumerated().map { ($0.offset, $0.element) }
        return indexed.sorted { x, y in
            var c = primary(x.1, y.1)
            if descending { c = invert(c) }
            if c != .orderedSame { return c == .orderedAscending }
            let t = NetText.compareIgnoreCase(x.1.job.jobNo, y.1.job.jobNo)
            if t != .orderedSame { return t == .orderedAscending }
            return x.0 < y.0
        }.map(\.1)
    }

    static func compareBool(_ a: Bool, _ b: Bool) -> ComparisonResult {
        a == b ? .orderedSame : (!a ? .orderedAscending : .orderedDescending)
    }

    static func invert(_ c: ComparisonResult) -> ComparisonResult {
        switch c {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    /// Header click (VESSEL-111): the same column toggles; another column becomes the sort column, ascending.
    public static func toggledSort(current: WorkOrderColumn, descending: Bool,
                                   clicked: WorkOrderColumn) -> (column: WorkOrderColumn, descending: Bool) {
        clicked == current ? (current, !descending) : (clicked, false)
    }

    // MARK: Due cell (VESSEL-110)

    public static func dueInfo(_ j: ShipJob, days: Int?) -> (text: String, tone: WorkOrderTone) {
        if j.isCompleted {
            return (NetText.isBlank(j.completedDate) ? "✓ completed" : "✓ completed \(j.completedDate)", .green)
        }
        guard let d = days else { return (NetText.isBlank(j.dueDate) ? "" : j.dueDate, .gray) }
        if d < 0 { return ("OVERDUE \(-d)d  (\(j.dueDate))", .red) }
        if d == 0 { return ("DUE TODAY  (\(j.dueDate))", .red) }
        if d <= 30 { return ("in \(d)d  (\(j.dueDate))", .orange) }
        if d <= 90 { return ("in \(d)d  (\(j.dueDate))", .amber) }
        return ("\(j.dueDate)  (in \(d)d)", .green)
    }

    public static func dueInfo(_ j: ShipJob, today: CivilDate) -> (text: String, tone: WorkOrderTone) {
        dueInfo(j, days: j.daysUntilDue(today: today))
    }

    // MARK: Summary (VESSEL-119)

    public static func summary(vessel: Vessel?, shown: Int, today: CivilDate) -> String {
        guard let vessel else { return noShipSummary }
        return summary(jobs: vessel.jobs, shown: shown, today: today)
    }

    public static func summary(jobs all: [ShipJob], shown: Int, today: CivilDate) -> String {
        if all.isEmpty { return noJobsSummary }
        var overdue = 0, due30 = 0, due90 = 0, completed = 0, notify = 0
        var catOrder: [String] = []
        var catCount: [Ordinal.Key: Int] = [:]
        for j in all {
            if j.isCompleted { completed += 1 } else if let d = j.daysUntilDue(today: today) {
                if d < 0 { overdue += 1 }
                if d >= 0 && d <= 30 { due30 += 1 }
                if d >= 0 && d <= 90 { due90 += 1 }
            }
            if j.notify { notify += 1 }
            let cat = NetText.isBlank(j.category) ? "(none)" : j.category
            let key = Ordinal.Key(cat)
            if catCount[key] == nil { catOrder.append(cat); catCount[key] = 0 }
            catCount[key]! += 1
        }
        let top = PortsService.stableSorted(catOrder) { catCount[Ordinal.Key($0)]! > catCount[Ordinal.Key($1)]! }
            .prefix(5).map { "\($0) \(catCount[Ordinal.Key($0)]!)" }
        return "⚙ \(all.count) work orders   ·   ⚠ \(overdue) overdue   ·   \(due30) due ≤30d   ·   \(due90) due ≤90d   ·   ✓ \(completed) completed   ·   🔔 \(notify) notify-on   ·   showing \(shown)\n"
            + "By category: " + top.joined(separator: "   ")
    }

    // MARK: Notifications bar (VESSEL-120)

    public static let barOffText = "Off — turn on to track this ship's due / overdue work orders here."
    public static let barNoneText = "On — no active flagged jobs. Tick the Notify box (or “🔔 shown ON”) on the recurring jobs you want tracked."
    public static let masterSwitchTitle = "🔔 Notifications for this ship"
    public static let masterSwitchHelp = "Master on/off switch for THIS ship's work-order notifications."

    /// Flagged = `Notify ∧ !IsCompleted`; overdue (d < 0) and due ≤ 30 (0 ≤ d ≤ 30), each sorted by d ascending.
    public static func attention(_ jobs: [ShipJob], today: CivilDate)
        -> (flagged: Int, overdue: [(job: ShipJob, days: Int)], dueSoon: [(job: ShipJob, days: Int)]) {
        let flagged = jobs.filter { $0.notify && !$0.isCompleted }
        var overdue: [(job: ShipJob, days: Int)] = [], soon: [(job: ShipJob, days: Int)] = []
        for j in flagged {
            guard let d = j.daysUntilDue(today: today) else { continue }
            if d < 0 { overdue.append((j, d)) } else if d <= 30 { soon.append((j, d)) }
        }
        return (flagged.count, PortsService.stableSorted(overdue) { $0.days < $1.days },
                PortsService.stableSorted(soon) { $0.days < $1.days })
    }

    public static func notificationBar(vessel: Vessel, today: CivilDate) -> WorkOrderBarState {
        notificationBar(enabled: vessel.notificationsEnabled, jobs: vessel.jobs, today: today)
    }

    public static func notificationBar(enabled: Bool, jobs: [ShipJob], today: CivilDate) -> WorkOrderBarState {
        if !enabled { return WorkOrderBarState(text: barOffText, borderTone: .gray, textTone: .gray) }
        let a = attention(jobs, today: today)
        if a.flagged == 0 { return WorkOrderBarState(text: barNoneText, borderTone: .gray, textTone: nil) }
        let all = a.overdue + a.dueSoon
        if all.isEmpty {
            return WorkOrderBarState(text: "On — \(a.flagged) flagged job(s), all clear (none due within 30 days).",
                                     borderTone: .green, textTone: .green)
        }
        let tone: WorkOrderTone = a.overdue.isEmpty ? .orange : .red
        let top = all.prefix(4).map { $0.days < 0 ? "\($0.job.jobNo) (overdue \(-$0.days)d)" : "\($0.job.jobNo) (in \($0.days)d)" }
        let text = "⚠ \(all.count) flagged work order(s) need attention — \(a.overdue.count) overdue, \(a.dueSoon.count) due ≤30d:  "
            + top.joined(separator: ",   ") + (all.count > 4 ? "   …" : "")
        return WorkOrderBarState(text: text, borderTone: tone, textTone: tone)
    }

    // MARK: Bulk actions (VESSEL-112…117)

    /// `TargetRows`: the selected jobs, or every shown job when nothing is selected.
    public static func targets(selected: [ShipJob], shown: [ShipJob]) -> [ShipJob] {
        selected.isEmpty ? shown : selected
    }

    /// Sets completion; `CompletedDate` = today (`yyyy-MM-dd`) when done, "" otherwise (re-stamps already completed).
    public static func setCompleted(_ jobs: [ShipJob], done: Bool, today: CivilDate) {
        for j in jobs {
            j.isCompleted = done
            j.completedDate = done ? today.iso : ""
        }
    }

    /// The per-row Done checkbox (VESSEL-112).
    public static func toggleDone(_ j: ShipJob, to done: Bool, today: CivilDate) {
        j.isCompleted = done
        j.completedDate = done ? today.iso : ""
    }

    /// Removes the given jobs from the vessel (by reference).
    public static func delete(_ jobs: [ShipJob], from vessel: Vessel) {
        let ids = Set(jobs.map { ObjectIdentifier($0) })
        vessel.jobs.removeAll { ids.contains(ObjectIdentifier($0)) }
    }
}
