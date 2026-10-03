// Spec: 10 §3.3 (PortCallReader: sheet choice and bounds, detection scan, layouts A and B, NormDate / NormTime,
//       FindRow / NextValue / SplitPort, error strings §3.3.8), VESSEL-201, VESSEL-211, VESSEL-212, VESSEL-304
//       (ports sheet policy), VESSEL-328 (renderer C), VESSEL-318 (Mac-only formula hint), §7.4–7.5, X.8.9.
import Foundation

/// A reader-level failure whose message is shown verbatim inside the importer's "Import failed" box.
public struct VesselReadError: Error, LocalizedError, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// One parsed port call (a `Sendable` value; the main actor turns it into a `PortCall`).
public struct PortCallDraft: Sendable, Hashable {
    public var portName = "", country = "", unLocode = "", portFacility = "", pfNo = ""
    public var arrivalDate = "", arrivalTime = "", departureDate = "", departureTime = ""
    public var securityLevelPort = "", securityLevelVessel = "", sspFollowed = "", specialMeasures = ""
    public var importedAt = ""

    public init(portName: String = "", country: String = "", unLocode: String = "", portFacility: String = "",
                pfNo: String = "", arrivalDate: String = "", arrivalTime: String = "", departureDate: String = "",
                departureTime: String = "", securityLevelPort: String = "", securityLevelVessel: String = "",
                sspFollowed: String = "", specialMeasures: String = "", importedAt: String = "") {
        self.portName = portName; self.country = country; self.unLocode = unLocode; self.portFacility = portFacility
        self.pfNo = pfNo; self.arrivalDate = arrivalDate; self.arrivalTime = arrivalTime
        self.departureDate = departureDate; self.departureTime = departureTime
        self.securityLevelPort = securityLevelPort; self.securityLevelVessel = securityLevelVessel
        self.sspFollowed = sspFollowed; self.specialMeasures = specialMeasures; self.importedAt = importedAt
    }

    /// A new `PortCall` model object (new Id) carrying these values.
    @MainActor public func makePortCall() -> PortCall {
        let c = PortCall(portName: portName)
        c.country = country; c.unLocode = unLocode; c.portFacility = portFacility; c.pfNo = pfNo
        c.arrivalDate = arrivalDate; c.arrivalTime = arrivalTime; c.departureDate = departureDate
        c.departureTime = departureTime; c.securityLevelPort = securityLevelPort
        c.securityLevelVessel = securityLevelVessel; c.sspFollowed = sspFollowed; c.specialMeasures = specialMeasures
        c.importedAt = importedAt
        return c
    }
}

/// C# `PortCallReader.Result`.
public struct PortCallReadResult: Sendable {
    public var calls: [PortCallDraft] = []
    /// Layout B `Vessel Name` (layout A files carry none).
    public var vesselName = ""
    /// Parsed for parity (VESSEL-211) — never stored or shown.
    public var imo = ""
    public var callSign = ""
    /// `Last Ports of Call (2 years)` or `Port of Call List (last 10 ports)`.
    public var format = ""
    /// VESSEL-318: formula cells in the used range without a saved result (rendered "").
    public var uncachedFormulaCount = 0

    public init() {}
}

/// Reads both ports-of-call layouts (C# `PortCallReader`). Runs off the main actor.
public enum PortCallReader {
    public static let formatA = "Last Ports of Call (2 years)"
    public static let formatB = "Port of Call List (last 10 ports)"

    public static let emptyMessage = "The workbook is empty."
    public static let unrecognisedMessage = "Couldn't recognise this as a ports-of-call list. Expected either a 'Last Ports of Call' sheet or a 'Port of Call List' sheet with an Arrival/Departure header."
    public static let noPortNameRowMessage = "Could not find the 'Port Name' header row."
    public static let noPortNameColumnMessage = "Could not find the port-name column."
    public static let noUnLocatorRowMessage = "Could not find the 'UN locator' header row."

    /// Opens `url` (extension gate + package, F2's reader) and reads it. `now` stamps `ImportedAt`
    /// (`yyyy-MM-dd HH:mm`, local); `today` resolves time-only date text in NormDate.
    public static func read(url: URL, now: NetDateTime, today: CivilDate, zone: TimeZone = .current) throws -> PortCallReadResult {
        let wb = try XlsxWorkbook.open(url)
        return try read(workbook: wb, now: now, today: today, zone: zone)
    }

    public static func read(workbook wb: XlsxWorkbook, now: NetDateTime, today: CivilDate,
                            zone: TimeZone = .current) throws -> PortCallReadResult {
        // VESSEL-304: the first worksheet with a used range, else position 1.
        var sheet: XlsxWorksheet?
        for ref in wb.worksheets {
            let ws = try wb.load(ref)
            if ws.rangeUsed() != nil { sheet = ws; break }
        }
        if sheet == nil, let first = wb.worksheets.first { sheet = try wb.load(first) }
        guard let ws = sheet, let used = ws.rangeUsed() else { throw VesselReadError(emptyMessage) }
        let g = Grid(ws: ws, wb: wb, used: used)

        var looksA = false, looksB = false
        var vesselName = "", imo = "", callSign = ""
        for r in used.firstRow...min(used.lastRow, used.firstRow + 12) {
            for c in used.firstColumn...used.lastColumn {
                let lv = NetText.toLowerInvariant(try g.cell(r, c))
                if VesselText.ordinalContains(lv, "un locator") || VesselText.ordinalContains(lv, "un/locode")
                    || VesselText.ordinalContains(lv, "port of call list") { looksB = true }
                if VesselText.ordinalContains(lv, "date arrived") || VesselText.ordinalContains(lv, "port name, country")
                    || VesselText.ordinalContains(lv, "last ports of call") { looksA = true }
                if lv == "vessel name" && vesselName.isEmpty { vesselName = try g.nextValue(r, c) }
                if VesselText.ordinalContains(lv, "imo number") && imo.isEmpty { imo = try g.nextValue(r, c) }
                if VesselText.ordinalContains(lv, "call sign") && callSign.isEmpty { callSign = try g.nextValue(r, c) }
            }
        }

        var result: PortCallReadResult
        if looksB && !looksA { result = try readB(g, today: today, zone: zone) }
        else if looksA { result = try readA(g, today: today, zone: zone) }
        else if looksB { result = try readB(g, today: today, zone: zone) }
        else { throw VesselReadError(unrecognisedMessage) }

        result.vesselName = vesselName
        result.imo = imo
        result.callSign = callSign
        let stamp = now.format(.isoMinute, zone: zone)
        for i in result.calls.indices { result.calls[i].importedAt = stamp }
        result.uncachedFormulaCount = ws.uncachedFormulaCount(in: used)
        return result
    }

    // MARK: Layout A (§3.3.3)

    static func readA(_ g: Grid, today: CivilDate, zone: TimeZone) throws -> PortCallReadResult {
        let u = g.used
        guard let hdr = try g.findRow("port name") else { throw VesselReadError(noPortNameRowMessage) }
        var portCol = -1, arrCol = -1, depCol = -1, secPortCol = -1, secVesselCol = -1, sspCol = -1, specialCol = -1
        for c in u.firstColumn...u.lastColumn {
            let h = NetText.toLowerInvariant(try g.cell(hdr, c))
            if h.isEmpty { continue }
            if VesselText.ordinalContains(h, "port name") { portCol = c }
            else if VesselText.ordinalContains(h, "date arrived") { arrCol = c }
            else if VesselText.ordinalContains(h, "date depart") { depCol = c }
            else if VesselText.ordinalContains(h, "security level in port") { secPortCol = c }
            else if VesselText.ordinalContains(h, "security level on vessel") { secVesselCol = c }
            else if VesselText.ordinalContains(h, "appropriate measures") || VesselText.ordinalContains(h, "ssp") { sspCol = c }
            else if VesselText.ordinalContains(h, "special security") { specialCol = c }
        }
        guard portCol >= 0 else { throw VesselReadError(noPortNameColumnMessage) }

        var res = PortCallReadResult()
        res.format = formatA
        if hdr + 1 <= u.lastRow {
            for r in (hdr + 1)...u.lastRow {
                let raw = try g.cell(r, portCol)
                if raw.isEmpty { continue }
                let (name, country) = splitPort(raw)
                func v(_ c: Int) throws -> String { if c > 0 { return try g.cell(r, c) }; return "" }
                var d = PortCallDraft(portName: name, country: country)
                d.arrivalDate = VesselText.normDate(try v(arrCol), today: today, zone: zone)
                d.departureDate = VesselText.normDate(try v(depCol), today: today, zone: zone)
                d.securityLevelPort = try v(secPortCol)
                d.securityLevelVessel = try v(secVesselCol)
                d.sspFollowed = try v(sspCol)
                d.specialMeasures = try v(specialCol)
                res.calls.append(d)
            }
        }
        return res
    }

    // MARK: Layout B (§3.3.4)

    static func readB(_ g: Grid, today: CivilDate, zone: TimeZone) throws -> PortCallReadResult {
        let u = g.used
        var subRowFound = try g.findRow("un locator")
        if subRowFound == nil { subRowFound = try g.findRow("un/locode") }
        guard let subRow = subRowFound else { throw VesselReadError(noUnLocatorRowMessage) }
        let catRow = subRow - 1

        var portNameCol = -1, unlocodeCol = -1, facilityCol = -1, pfNoCol = -1, secPortCol = -1, secVesselCol = -1
        var arrDateCol = -1, arrTimeCol = -1, depDateCol = -1, depTimeCol = -1, specialCol = -1
        var cat = ""
        for c in u.firstColumn...u.lastColumn {
            let catRaw = try (catRow >= u.firstRow ? g.cell(catRow, c) : "")
            if !catRaw.isEmpty { cat = NetText.toLowerInvariant(catRaw) }
            let sub = NetText.toLowerInvariant(try g.cell(subRow, c))
            func has(_ s: String, _ n: String) -> Bool { VesselText.ordinalContains(s, n) }
            if has(cat, "port facility") {
                if has(sub, "name") { facilityCol = c } else if has(sub, "pf no") { pfNoCol = c }
            } else if VesselText.ordinalHasPrefix(cat, "port") {
                if has(sub, "name") { portNameCol = c } else if has(sub, "un locator") || has(sub, "locode") { unlocodeCol = c }
            } else if has(cat, "security level") {
                if has(sub, "vessel") { secVesselCol = c } else if !sub.isEmpty { secPortCol = c }
            } else if has(cat, "arrival") {
                if has(sub, "date") { arrDateCol = c } else if has(sub, "time") { arrTimeCol = c }
            } else if has(cat, "departure") {
                if has(sub, "date") { depDateCol = c } else if has(sub, "time") { depTimeCol = c }
            } else if has(cat, "special") {
                specialCol = c
            }
        }
        if portNameCol < 0 { portNameCol = u.firstColumn }

        var res = PortCallReadResult()
        res.format = formatB
        if subRow + 1 <= u.lastRow {
            for r in (subRow + 1)...u.lastRow {
                let name = try g.cell(r, portNameCol)
                if name.isEmpty { continue }
                func v(_ c: Int) throws -> String { if c > 0 { return try g.cell(r, c) }; return "" }
                var d = PortCallDraft(portName: name)
                d.unLocode = try v(unlocodeCol)
                d.portFacility = try v(facilityCol)
                d.pfNo = try v(pfNoCol)
                d.securityLevelPort = try v(secPortCol)
                d.securityLevelVessel = try v(secVesselCol)
                d.arrivalDate = VesselText.normDate(try v(arrDateCol), today: today, zone: zone)
                d.arrivalTime = VesselText.normTime(try v(arrTimeCol))
                d.departureDate = VesselText.normDate(try v(depDateCol), today: today, zone: zone)
                d.departureTime = VesselText.normTime(try v(depTimeCol))
                d.specialMeasures = try v(specialCol)
                res.calls.append(d)
            }
        }
        return res
    }

    // MARK: Helpers (§3.3.7)

    /// Splits at the LAST comma; both parts trimmed. No comma → (trimmed, "").
    public static func splitPort(_ s: String) -> (name: String, country: String) {
        guard let i = s.lastIndex(of: ",") else { return (NetText.trim(s), "") }
        return (NetText.trim(String(s[..<i])), NetText.trim(String(s[s.index(after: i)...])))
    }

    /// The used range of the chosen sheet with renderer C.
    struct Grid {
        let ws: XlsxWorksheet
        let wb: XlsxWorkbook
        let used: XlsxRange

        func cell(_ r: Int, _ c: Int) throws -> String { try XlsxRender.portsCell(ws.cell(r, c), workbook: wb) }

        /// The first row (top to bottom, left to right) with a cell whose lower text contains `needle`.
        func findRow(_ needle: String) throws -> Int? {
            for r in used.firstRow...used.lastRow {
                for c in used.firstColumn...used.lastColumn {
                    if VesselText.ordinalContains(NetText.toLowerInvariant(try cell(r, c)), needle) { return r }
                }
            }
            return nil
        }

        /// The first non-empty cell to the right in the same row.
        func nextValue(_ r: Int, _ c: Int) throws -> String {
            guard c + 1 <= used.lastColumn else { return "" }
            for cc in (c + 1)...used.lastColumn {
                let v = try cell(r, cc)
                if !v.isEmpty { return v }
            }
            return ""
        }
    }
}
