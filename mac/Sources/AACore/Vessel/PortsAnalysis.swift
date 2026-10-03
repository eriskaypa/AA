// Spec: 10 §E (VESSEL-200…212: per-vessel Ports panel — search, columns, sort incl. the `Special measures` quirk,
//       summary), §F (VESSEL-250…256: Ports Database — list, filter, order, status, visits pane), §3.7, §7.3, §7.13.
import Foundation

/// The per-vessel ports table columns (VESSEL-207) — header text is the sort key.
public enum PortColumn: String, Sendable, Hashable, CaseIterable {
    case port = "Port", country = "Country", unLocode = "UN/LOCODE", arrival = "Arrival", departure = "Departure"
    case secPort = "Sec P", secVessel = "Sec V", ssp = "SSP", facility = "Port Facility"
    case special = "Special measures"

    public var width: Double {
        switch self {
        case .port: return 150
        case .country: return 120
        case .unLocode: return 90
        case .arrival, .departure: return 130
        case .secPort, .secVessel: return 55
        case .ssp: return 50
        case .facility: return 180
        case .special: return 200
        }
    }
}

@MainActor public enum PortsAnalysis {
    // MARK: Strings

    public static let searchPlaceholder = "Search port / country / UN-LOCODE..."
    public static let noCallsSummary = "No ports imported yet for this vessel. Click “Import ports (.xlsx)...”."
    public static let noVesselSummary = "No vessel selected."
    public static let selectToDeleteHint = "Select one or more ports to delete."
    public static let exportEmptyMessage = "No ports to export for this vessel."
    public static let exportDialogTitle = "Export ports of call"
    public static let dbTitle = "⚓ Ports Database"
    public static let dbDescription = "Every port any vessel has called, built from the ports imported on each vessel's Ports tab. Select a port to see which vessels called and when."
    public static let dbEmptyStatus = "No ports yet. Import a ports-of-call list on any vessel's “Ports” tab."
    public static let dbNoSelectionHeader = "Select a port to see the vessels that called."

    public static func importDialogTitle(_ vessel: String) -> String { "Import ports of call for \(vessel)" }

    public static func importedHint(count: Int, vessel: String, added: Int, updated: Int, format: String,
                                    newVisits: Int) -> String {
        "Imported \(count) port(s) for \(vessel) (\(added) new, \(updated) updated) — \(format). \(newVisits) new visit(s) in the ports database."
    }

    public static func differentVesselMessage(fileVessel: String, vessel: String, count: Int) -> String {
        "This file lists vessel \"\(fileVessel)\", but you're importing into \"\(vessel)\".\n\nImport these \(count) port call(s) for \(vessel) anyway?"
    }

    /// VESSEL-202: the file names a vessel and it differs (OIC) from the target vessel.
    public static func needsDifferentVesselConfirmation(fileVessel: String, vessel: String) -> Bool {
        !fileVessel.isEmpty && !NetText.equalsIgnoreCase(fileVessel, vessel)
    }

    public static func exportedHint(count: Int, vessel: String) -> String { "Exported \(count) port(s) for \(vessel)." }
    public static func deleteConfirmMessage(count: Int, vessel: String) -> String {
        "Delete \(count) port call(s) from \(vessel)? Their visit is also removed from the ports database."
    }
    public static func deletedHint(count: Int) -> String { "Deleted \(count) port call(s)." }

    /// VESSEL-204 activity-log `Name` and `Detail`.
    public static func logName(added: Int, updated: Int) -> String { "\(added) new, \(updated) updated" }
    public static func logDetail(vessel: String, format: String) -> String { "\(vessel) · \(format)" }

    // MARK: Per-vessel panel (VESSEL-206, 208, 210)

    /// Trimmed query, OIC substring on PortName, Country or UnLocode.
    public static func filter(_ calls: [PortCall], query: String) -> [PortCall] {
        let q = NetText.trim(query)
        guard !q.isEmpty else { return calls }
        return calls.filter {
            NetText.containsIgnoreCase($0.portName, q) || NetText.containsIgnoreCase($0.country, q)
                || NetText.containsIgnoreCase($0.unLocode, q)
        }
    }

    /// VESSEL-208 keys (stable, no extra tiebreak). `Arrival` and every unlisted header (incl. `Special measures`)
    /// sort by `ArrivalValue ?? MinValue`, then `ArrivalTime`.
    public static func sort(_ calls: [PortCall], by column: PortColumn, descending: Bool) -> [PortCall] {
        func str(_ c: PortCall) -> String? {
            switch column {
            case .port: return c.portName
            case .country: return c.country
            case .unLocode: return c.unLocode
            case .departure: return c.departureDate + " " + c.departureTime
            case .secPort: return c.securityLevelPort
            case .secVessel: return c.securityLevelVessel
            case .ssp: return c.sspFollowed
            case .facility: return c.portFacility
            case .arrival, .special: return nil
            }
        }
        let keyed = calls.map { ($0, PortsService.arrivalTicks($0)) }
        let sorted = PortsService.stableSorted(keyed) { a, b in
            var r: ComparisonResult
            if let sa = str(a.0), let sb = str(b.0) {
                r = NetText.compareIgnoreCase(sa, sb)
            } else {
                r = a.1 == b.1 ? Ordinal.compare(a.0.arrivalTime, b.0.arrivalTime) : (a.1 < b.1 ? .orderedAscending : .orderedDescending)
            }
            return descending ? r == .orderedDescending : r == .orderedAscending
        }
        return sorted.map(\.0)
    }

    /// Header click: same column toggles; another column becomes the sort column, ascending.
    public static func toggledSort(current: PortColumn, descending: Bool, clicked: PortColumn) -> (column: PortColumn, descending: Bool) {
        clicked == current ? (current, !descending) : (clicked, false)
    }

    /// VESSEL-210 summary.
    public static func summary(vessel: Vessel?, shown: Int) -> String {
        guard let vessel else { return noVesselSummary }
        let all = vessel.portCalls
        if all.isEmpty { return noCallsSummary }
        var latest = all[0]
        var best = PortsService.arrivalTicks(latest)
        for c in all.dropFirst() {
            let t = PortsService.arrivalTicks(c)
            if t > best { best = t; latest = c }
        }
        return "⚓ \(all.count) port call(s)" + (shown != all.count ? "  ·  showing \(shown)" : "")
            + "  ·  latest: \(latest.displayName) (\(latest.arrivalDate))"
    }

    // MARK: Ports Database (VESSEL-251…254)

    /// Trimmed query, OIC substring on Name, Country or UnLocode; ordered by Name OIC (stable).
    public static func databasePorts(_ ports: [PortRecord], query: String) -> [PortRecord] {
        let q = NetText.trim(query)
        let filtered = q.isEmpty ? ports : ports.filter {
            NetText.containsIgnoreCase($0.name, q) || NetText.containsIgnoreCase($0.country, q)
                || NetText.containsIgnoreCase($0.unLocode, q)
        }
        return PortsService.stableSorted(filtered) { NetText.compareIgnoreCase($0.name, $1.name) == .orderedAscending }
    }

    /// The trailing count of a port row. Windows prints `{n} visits` with no singular (DECISIONS 10 Q8: pluralised
    /// on the Mac — `1 visit`).
    public static func visitCountText(_ n: Int) -> String { n == 1 ? "1 visit" : "\(n) visits" }

    /// VESSEL-252 status line (totals over the whole DB).
    public static func databaseStatus(_ ports: [PortRecord], shown: Int) -> String {
        if ports.isEmpty { return dbEmptyStatus }
        let visits = ports.reduce(0) { $0 + $1.visits.count }
        return "\(ports.count) port(s)  ·  \(visits) visit(s)" + (shown != ports.count ? "  ·  showing \(shown)" : "")
    }

    /// VESSEL-253 header for a selected port.
    public static func visitsHeader(_ port: PortRecord) -> String {
        "⚓ \(port.display)   —   \(port.visits.count) visit(s)"
    }

    /// One VESSEL-253 visits column: title, minimum and ideal width (pt) and whether its text wraps.
    public struct VisitsColumn: Sendable, Equatable {
        public let title: String
        public let minWidth: Double
        public let idealWidth: Double
        public let wraps: Bool
    }

    /// VESSEL-253 columns: `Vessel` (Windows 220, wrapped `VesselName`), `Arrival` / `Departure` / `Imported` (Windows
    /// 140 each). In the brand mono the four columns must fit the visits pane of the default 1280-pt window (about
    /// 577 pt of table, with ~17 pt of cell padding per column), so the widths are narrower than the Windows px
    /// (DEVIATIONS W-VESSEL, VESSEL-253): the date columns hug `yyyy-MM-dd HH:mm`, and the Vessel column wraps long
    /// names onto a second line instead of truncating them (design rule 5).
    public static let visitsColumns: [VisitsColumn] = [
        VisitsColumn(title: "Vessel", minWidth: 100, idealWidth: 110, wraps: true),
        VisitsColumn(title: "Arrival", minWidth: 130, idealWidth: 130, wraps: false),
        VisitsColumn(title: "Departure", minWidth: 130, idealWidth: 130, wraps: false),
        VisitsColumn(title: "Imported", minWidth: 126, idealWidth: 126, wraps: false),
    ]

    /// The width budget the four ideal widths must stay within so no column runs past the pane edge at 1280 pt.
    public static let visitsColumnsBudget: Double = 577 - 4 * 17

    /// VESSEL-253 order: `ArrivalValue ?? MinValue` descending, then `ArrivalTime` descending.
    public static func orderedVisits(_ port: PortRecord) -> [PortVisit] {
        let keyed = port.visits.map { ($0, $0.arrivalValue?.ticks ?? 0) }
        return PortsService.stableSorted(keyed) { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return Ordinal.compare(a.0.arrivalTime, b.0.arrivalTime) == .orderedDescending
        }.map(\.0)
    }

    /// VESSEL-254: keep the selection when the port is still in the filtered list.
    public static func retainedSelection(_ id: UUID?, in list: [PortRecord]) -> UUID? {
        guard let id, list.contains(where: { $0.id == id }) else { return nil }
        return id
    }
}
