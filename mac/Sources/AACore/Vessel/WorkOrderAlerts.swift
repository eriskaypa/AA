// Spec: DECISIONS 10 Q7 (system notifications for flagged overdue work orders, respecting the per-ship master switch),
//       10 §9 Q7 (gate on NotificationsEnabled + Notify + !IsCompleted), VESSEL-120/121; ARCHITECTURE.md §7.7
//       (`WorkOrderNotifications.runDigest`: deduplicated per vessel/job/day in MacPreferences `aa.vessel.notified`),
//       §9.3.
import Foundation

/// The pure part of the work-order notification digest: which flagged overdue jobs still need a notification today.
@MainActor public enum WorkOrderAlerts {
    /// MacPreferences key holding today's already-notified `vesselId|jobNo|yyyy-MM-dd` entries.
    public static let notifiedKey = MacPreferences.Key("aa.vessel.notified")

    /// One notification (one per vessel with newly overdue flagged jobs).
    public struct Alert: Sendable, Hashable {
        public var vesselID: UUID
        public var vesselName: String
        /// Every currently overdue flagged job of the vessel, most overdue first: (JobNo, days overdue).
        public var overdue: [WorkOrderAlertJob]
        /// The dedup keys this alert covers (the jobs not yet notified today).
        public var newKeys: [String]
        public init(vesselID: UUID, vesselName: String, overdue: [WorkOrderAlertJob], newKeys: [String]) {
            self.vesselID = vesselID; self.vesselName = vesselName; self.overdue = overdue; self.newKeys = newKeys
        }

        /// Notification identifier (replaces the vessel's previous banner).
        public var identifier: String { "aa.vessel.workorders." + vesselID.uuidString.lowercased() }
        public var title: String { "AA — work orders overdue" }
        /// `{Vessel}: {n} flagged work order(s) overdue — {JobNo} (overdue {d}d),   …` (first 4, then `…`).
        public var body: String {
            let top = overdue.prefix(4).map { "\($0.jobNo) (overdue \($0.daysOverdue)d)" }
            return "\(vesselName): \(overdue.count) flagged work order(s) overdue — " + top.joined(separator: ",   ")
                + (overdue.count > 4 ? "   …" : "")
        }
    }

    /// The dedup key of one job on one day.
    public static func key(vesselID: UUID, jobNo: String, day: CivilDate) -> String {
        vesselID.uuidString.lowercased() + "|" + NetText.toLowerInvariant(jobNo) + "|" + day.iso
    }

    /// Alerts for every vessel with `NotificationsEnabled` that has a flagged (`Notify`), active, overdue job whose key
    /// is not in `alreadyNotified`. Vessels in list order.
    public static func pending(vessels: [Vessel], today: CivilDate, alreadyNotified: Set<String>) -> [Alert] {
        var out: [Alert] = []
        for v in vessels where v.notificationsEnabled {
            let overdue = WorkOrderAnalysis.attention(v.jobs, today: today).overdue
            guard !overdue.isEmpty else { continue }
            let keys = overdue.map { key(vesselID: v.id, jobNo: $0.job.jobNo, day: today) }
            let fresh = keys.filter { !alreadyNotified.contains($0) }
            guard !fresh.isEmpty else { continue }
            out.append(Alert(vesselID: v.id, vesselName: v.name,
                             overdue: overdue.map { WorkOrderAlertJob(jobNo: $0.job.jobNo, daysOverdue: -$0.days) },
                             newKeys: fresh))
        }
        return out
    }

    /// Reads the stored keys, keeping only today's (older days are dropped).
    public static func storedKeys(_ prefs: MacPreferences, today: CivilDate) -> Set<String> {
        let all = prefs.codable(notifiedKey, as: [String].self) ?? []
        return Set(all.filter { $0.hasSuffix("|" + today.iso) })
    }

    /// Persists `keys` (today's only).
    public static func storeKeys(_ keys: Set<String>, _ prefs: MacPreferences, today: CivilDate) {
        let todays = keys.filter { $0.hasSuffix("|" + today.iso) }.sorted()
        prefs.setCodable(todays.isEmpty ? nil : todays, notifiedKey)
    }
}

public struct WorkOrderAlertJob: Sendable, Hashable {
    public var jobNo: String
    public var daysOverdue: Int
    public init(jobNo: String, daysOverdue: Int) { self.jobNo = jobNo; self.daysOverdue = daysOverdue }
}
