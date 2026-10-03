// Spec: 10 §3.2 (PortsService.Apply / RemoveCall / CopyInto / Export), VESSEL-203, VESSEL-205, VESSEL-209,
//       VESSEL-281, §4.5 (export layout), §7.6–7.7; DECISIONS 10 Q3 (RemoveCall matching fixed: VesselId + port +
//       date, P2 — see Docs/Deviations/W-VESSEL.md).
import Foundation

/// Applies imported ports of call to a vessel and the global Ports Database, removes calls, and exports a
/// vessel's ports to Excel (C# `PortsService`).
@MainActor public enum PortsService {
    public struct ApplyResult: Sendable, Equatable {
        public var added: Int
        public var updated: Int
        public var newVisits: Int
        public init(added: Int, updated: Int, newVisits: Int) {
            self.added = added; self.updated = updated; self.newVisits = newVisits
        }
    }

    /// §3.2.1. `calls` are new objects (their `Id`s are kept when appended); a call matching an existing one by
    /// `Key` (OIC) is merged with `CopyInto` and discarded, but the global-DB step still uses the incoming values.
    @discardableResult
    public static func apply(data: AppData, vessel: Vessel, calls: [PortCall]) -> ApplyResult {
        var added = 0, updated = 0, newVisits = 0
        var byKey: [String: PortCall] = [:]                       // keyed by the OIC fold of `PortCall.key`
        for p in vessel.portCalls { byKey[fold(p.key)] = p }       // later duplicates overwrite earlier

        for call in calls {
            // (a) the vessel's own list.
            if let existing = byKey[fold(call.key)] {
                copyInto(existing, call)
                updated += 1
            } else {
                vessel.portCalls.append(call)
                byKey[fold(call.key)] = call
                added += 1
            }

            // (b) the global port: FIRST match in list order.
            let port: PortRecord
            if let found = data.ports.first(where: { matches($0, call) }) {
                port = found
                if port.unLocode.isEmpty && !call.unLocode.isEmpty { port.unLocode = call.unLocode }
                if port.country.isEmpty && !call.country.isEmpty { port.country = call.country }
            } else {
                port = PortRecord(name: call.portName, country: call.country, unLocode: call.unLocode)
                data.ports.append(port)
            }

            // (c) one visit per (vessel, arrival date) — enrich instead of duplicating.
            if let i = port.visits.firstIndex(where: {
                ($0.vesselId == vessel.id || NetText.equalsIgnoreCase($0.vesselName, vessel.name))
                    && Ordinal.equals($0.arrivalDate, call.arrivalDate)
            }) {
                if port.visits[i].vesselId == nil { port.visits[i].vesselId = vessel.id }
                if port.visits[i].arrivalTime.isEmpty { port.visits[i].arrivalTime = call.arrivalTime }
                if port.visits[i].departureDate.isEmpty { port.visits[i].departureDate = call.departureDate }
                if port.visits[i].departureTime.isEmpty { port.visits[i].departureTime = call.departureTime }
            } else {
                port.visits.append(PortVisit(vesselName: vessel.name, vesselId: vessel.id, arrivalDate: call.arrivalDate,
                                             arrivalTime: call.arrivalTime, departureDate: call.departureDate,
                                             departureTime: call.departureTime, importedAt: call.importedAt))
                newVisits += 1
            }
        }
        return ApplyResult(added: added, updated: updated, newVisits: newVisits)
    }

    /// Apply's port lookup: same UN/LOCODE (when the call has one), or the same name with a compatible country.
    public static func matches(_ port: PortRecord, _ call: PortCall) -> Bool {
        (!call.unLocode.isEmpty && NetText.equalsIgnoreCase(port.unLocode, call.unLocode))
            || (NetText.equalsIgnoreCase(port.name, call.portName)
                && (port.country.isEmpty || call.country.isEmpty || NetText.equalsIgnoreCase(port.country, call.country)))
    }

    /// §3.2.2 with the DECISIONS 10 Q3 fix (P2): removes the call (by reference), then the ONE visit that belongs to
    /// it — the first visit, in the ports that match the call (Apply's port rule, list order), whose vessel is this
    /// vessel (same `VesselId`, or no `VesselId` and the same name) and whose arrival date equals the call's — and
    /// finally prunes every port left without visits (Windows parity). A rename or a same-day call at another port
    /// no longer removes the wrong visit or keeps a stale one.
    public static func removeCall(data: AppData, vessel: Vessel, call: PortCall) {
        if let i = vessel.portCalls.firstIndex(where: { $0 === call }) { vessel.portCalls.remove(at: i) }
        outer: for port in data.ports where matches(port, call) {
            for (i, v) in port.visits.enumerated() where belongs(v, to: vessel) && Ordinal.equals(v.arrivalDate, call.arrivalDate) {
                port.visits.remove(at: i)
                break outer
            }
        }
        data.ports.removeAll { $0.visits.isEmpty }
    }

    static func belongs(_ v: PortVisit, to vessel: Vessel) -> Bool {
        if let id = v.vesselId { return id == vessel.id }
        return NetText.equalsIgnoreCase(v.vesselName, vessel.name)
    }

    /// §3.2.3: the name and `ImportedAt` always; every optional field only when the incoming value is non-empty.
    public static func copyInto(_ dst: PortCall, _ src: PortCall) {
        func keep(_ incoming: String, _ existing: String) -> String { incoming.isEmpty ? existing : incoming }
        dst.portName = src.portName
        dst.country = keep(src.country, dst.country)
        dst.unLocode = keep(src.unLocode, dst.unLocode)
        dst.portFacility = keep(src.portFacility, dst.portFacility)
        dst.pfNo = keep(src.pfNo, dst.pfNo)
        dst.arrivalTime = keep(src.arrivalTime, dst.arrivalTime)
        dst.departureDate = keep(src.departureDate, dst.departureDate)
        dst.departureTime = keep(src.departureTime, dst.departureTime)
        dst.securityLevelPort = keep(src.securityLevelPort, dst.securityLevelPort)
        dst.securityLevelVessel = keep(src.securityLevelVessel, dst.securityLevelVessel)
        dst.sspFollowed = keep(src.sspFollowed, dst.sspFollowed)
        dst.specialMeasures = keep(src.specialMeasures, dst.specialMeasures)
        dst.importedAt = src.importedAt
    }

    // MARK: Export (§3.2.4, §4.5)

    public static let exportHeaders = [
        "Port", "Country", "UN/LOCODE", "Port Facility", "PF no.", "Arrival Date", "Arrival Time", "Departure Date",
        "Departure Time", "Sec. Port", "Sec. Vessel", "SSP", "Special measures",
    ]

    /// Rows ordered by `ArrivalValue ?? MinValue` descending (stable); every value a text cell.
    public static func exportSheet(_ vessel: Vessel) -> XlsxSheetSpec {
        let ordered = stableSorted(vessel.portCalls) { a, b in arrivalTicks(a) > arrivalTicks(b) }
        let rows: [[String]] = ordered.map { c in
            [c.portName, c.country, c.unLocode, c.portFacility, c.pfNo, c.arrivalDate, c.arrivalTime, c.departureDate,
             c.departureTime, c.securityLevelPort, c.securityLevelVessel, c.sspFollowed, c.specialMeasures]
        }
        let widths = WorkOrderShippalmReader.autoFitWidths(header: exportHeaders, rows: rows)
        return XlsxSheetSpec(name: "Ports of Call", columns: widths.map { XlsxColumnSpec(width: $0) }, boldHeader: true,
                             header: exportHeaders,
                             rows: rows.map { $0.map { $0.isEmpty ? XlsxCellValue.empty : .text($0) } })
    }

    public static func export(_ vessel: Vessel, to url: URL) throws {
        try XlsxWriter.write(to: url, sheet: exportSheet(vessel))
    }

    // MARK: Helpers

    /// `ArrivalValue ?? DateTime.MinValue` as ticks.
    public static func arrivalTicks(_ c: PortCall) -> Int64 { c.arrivalValue?.ticks ?? 0 }

    /// OrdinalIgnoreCase dictionary key.
    static func fold(_ s: String) -> String { NetText.toUpperInvariant(s) }

    /// A stable sort (Swift's `sort` is not guaranteed stable for all inputs).
    public static func stableSorted<T>(_ items: [T], by less: (T, T) -> Bool) -> [T] {
        items.enumerated().sorted { a, b in
            if less(a.element, b.element) { return true }
            if less(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}
