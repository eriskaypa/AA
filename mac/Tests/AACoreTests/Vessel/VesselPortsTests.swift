// TV: 10 §7.1 NormDate, §7.2 NormTime, §7.3 SplitPort / keys / displays, §7.4–7.5 POC layouts, §7.6 Apply /
//     RemoveCall scenarios (RemoveCall per DECISIONS 10 Q3), §7.7 export → re-import, §7.13 ports sort, X.8.1 C·D /
//     C·T, X.8.9, §3.3.8 errors.
import Foundation
import Testing
@testable import AACore

@Suite("W-VESSEL — NormDate / NormTime / displays")
@MainActor struct VesselPortTextTests {
    let today = VesselTestClock.today
    let zone = VesselTestClock.zone

    // TV: 10 §7.1
    @Test(arguments: [
        ("15/07/2026", "2026-07-15"), ("01/07/2026", "2026-07-01"), ("5.7.26", "2026-07-05"), ("1/2/99", "2099-02-01"),
        ("2026-7-5", "2026-07-05"), ("2026-07-15 22:00", "2026-07-15"), ("15/07/2026 22:00", "2026-07-15"),
        ("07/15/2026", "2026-07-15"), ("03/04/2026", "2026-04-03"), ("Jul 15, 2026", "2026-07-15"),
        ("2026-02-30", "2026-02-30"), ("  ", ""), ("", ""), ("TBC", "TBC"), ("15/07/202", "0202-07-15"),
    ])
    func normDate(_ input: String, _ expected: String) {
        #expect(VesselText.normDate(input, today: today, zone: zone) == expected)
    }

    // TV: 10 §7.2
    @Test(arguments: [
        ("22:00", "22:00"), ("9:05", "09:05"), ("00:01", "00:01"), ("22:00:59", "22:00"), ("1899-12-30 22:00", "22:00"),
        ("123:45", "23:45"), ("2200", ""), ("", ""), ("99:99", "99:99"), (" 7:3", ""),
    ])
    func normTime(_ input: String, _ expected: String) {
        #expect(VesselText.normTime(input) == expected)
    }

    func split(_ s: String) -> [String] { let r = PortCallReader.splitPort(s); return [r.name, r.country] }

    // TV: 10 §7.3
    @Test func splitAndDisplays() {
        #expect(split("Hong Kong, Hong Kong S.A.R.") == ["Hong Kong", "Hong Kong S.A.R."])
        #expect(split("A, B, C") == ["A, B", "C"])
        #expect(split("Singapore") == ["Singapore", ""])
        #expect(split(" Bonny ,Nigeria ") == ["Bonny", "Nigeria"])
        let call = PortCall(portName: "Bonny")
        call.arrivalDate = "2026-07-15"
        #expect(call.key == "bonny@2026-07-15")
        #expect(call.displayName == "Bonny")
        call.country = "Nigeria"
        #expect(call.displayName == "Bonny, Nigeria")
        #expect(call.arrivalDisplay == "2026-07-15")
        call.arrivalTime = "22:00"
        #expect(call.arrivalDisplay == "2026-07-15 22:00")
        #expect(PortRecord(name: "Bonny", country: "Nigeria", unLocode: "NGBON").display == "Bonny (NGBON), Nigeria")
        #expect(PortRecord(name: "Bonny", country: "Nigeria").display == "Bonny, Nigeria")
        #expect(PortRecord(name: "Bonny", unLocode: "NGBON").display == "Bonny (NGBON)")
        #expect(PortRecord(name: "Bonny").display == "Bonny")
        let v = PortVisit(vesselName: "BW Pavilion Aranda", arrivalDate: "2026-07-15", arrivalTime: "22:00")
        #expect(v.visitKey == "bw pavilion aranda|2026-07-15|22:00")
    }

    // TV: 10 X.8.1 columns C·D and C·T (renderer C → NormDate / NormTime)
    @Test func matrixPortDateAndTimeColumns() throws {
        let wb = XlsxWorkbook(worksheets: [], use1904: false)
        func c(_ v: XlsxValue) throws -> String { try XlsxRender.portsCell(XlsxCell(value: v), workbook: wb) }
        func cd(_ v: XlsxValue) throws -> String { VesselText.normDate(try c(v), today: today, zone: zone) }
        func ct(_ v: XlsxValue) throws -> String { VesselText.normTime(try c(v)) }
        let t = today.iso
        // M1, M1a, M1b
        #expect(try cd(.dateTime(serial: 45000)) == "2023-03-15"); #expect(try ct(.dateTime(serial: 45000)) == "")
        #expect(try cd(.dateTime(serial: 45000.75)) == "2023-03-15"); #expect(try ct(.dateTime(serial: 45000.75)) == "18:00")
        // M1c / M1d: numbers stay numbers in ports.
        #expect(try cd(.number(45000)) == "45000"); #expect(try ct(.number(45000)) == "")
        // M2 … M2c: durations → today in a date column, hh:mm in a time column.
        #expect(try cd(.timeSpan(serial: 0.5)) == t); #expect(try ct(.timeSpan(serial: 0.5)) == "12:00")
        #expect(try cd(.timeSpan(serial: 0.25)) == t); #expect(try ct(.timeSpan(serial: 0.25)) == "06:00")
        #expect(try cd(.timeSpan(serial: 1.5)) == t); #expect(try ct(.timeSpan(serial: 1.5)) == "12:00")
        #expect(try cd(.timeSpan(serial: 0.500001)) == t); #expect(try ct(.timeSpan(serial: 0.500001)) == "12:00")
        // M2d / M2e
        #expect(try cd(.dateTime(serial: 0.5)) == "1899-12-31"); #expect(try ct(.dateTime(serial: 0.5)) == "12:00")
        #expect(try cd(.dateTime(serial: 1.5)) == "1900-01-01"); #expect(try ct(.dateTime(serial: 1.5)) == "12:00")
        // M3 / M3a / M3b: text dates.
        #expect(try cd(.text("2026-03-04")) == "2026-03-04"); #expect(try ct(.text("2026-03-04")) == "")
        #expect(try cd(.text("  2026-03-04 ")) == "2026-03-04")
        // M4: a bare serial is kept in a ports date column.
        #expect(try cd(.number(48108)) == "48108")
        // M5 / M5a / M6 / M6a
        #expect(try cd(.boolean(true)) == "TRUE"); #expect(try ct(.boolean(true)) == "")
        #expect(try cd(.boolean(false)) == "FALSE")
        #expect(try cd(.error(.notAvailable)) == "#N/A"); #expect(try ct(.error(.notAvailable)) == "")
        #expect(try cd(.blank) == ""); #expect(try ct(.blank) == "")
    }
}

@Suite("W-VESSEL — PortCallReader")
@MainActor struct VesselPortCallReaderTests {
    // TV: 10 §7.4, X.8.9 layout A
    @Test func layoutASample() throws {
        let r = try VesselPOC.read(VesselPOC.layoutA)
        #expect(r.format == "Last Ports of Call (2 years)")
        #expect(r.vesselName == "" && r.imo == "" && r.callSign == "")
        #expect(r.calls.count == 47)
        let c1 = r.calls[0]
        #expect(c1 == PortCallDraft(portName: "Bonny", country: "Nigeria", arrivalDate: "2026-07-15",
                                    departureDate: "2026-07-17", securityLevelPort: "1", securityLevelVessel: "1",
                                    sspFollowed: "YES", specialMeasures: "", importedAt: c1.importedAt))
        let c12 = r.calls[11]
        #expect([c12.portName, c12.country, c12.arrivalDate, c12.departureDate, c12.securityLevelPort,
                 c12.securityLevelVessel, c12.sspFollowed, c12.specialMeasures]
                == ["Portland", "United Kingdom", "2026-02-13", "2026-02-14", "1", "1", "YES", "Bunker barge 'Monjasa Promoter'"])
        let c24 = r.calls[23]
        #expect([c24.portName, c24.country, c24.arrivalDate, c24.departureDate]
                == ["Hong Kong", "Hong Kong S.A.R.", "2025-09-16", "2025-09-17"])
        let c42 = r.calls[41]
        #expect([c42.portName, c42.country, c42.arrivalDate, c42.departureDate, c42.securityLevelPort,
                 c42.securityLevelVessel, c42.sspFollowed, c42.specialMeasures]
                == ["Brunsbuttel", "Germany", "2024-11-01", "2024-11-04", "", "", "YES", "ArrPurpose:"])
        let c47 = r.calls[46]
        #expect([c47.portName, c47.country, c47.arrivalDate, c47.departureDate, c47.specialMeasures]
                == ["Ceuta", "Spain", "2024-07-29", "2024-07-29", "ArrPurpose: DO Bunkering"])
        #expect(Set(r.calls.map { NetText.toLowerInvariant($0.portName) + "@" + $0.arrivalDate }).count == 47)
        #expect(Set(r.calls.map(\.importedAt)) == ["2026-09-29 10:15"])
        #expect(r.calls.allSatisfy { $0.unLocode.isEmpty && $0.arrivalTime.isEmpty && $0.portFacility.isEmpty })
        #expect(r.uncachedFormulaCount == 0)
    }

    // TV: 10 §7.5, X.8.9 layout B
    @Test func layoutBSample() throws {
        let r = try VesselPOC.read(VesselPOC.layoutB)
        #expect(r.format == "Port of Call List (last 10 ports)")
        #expect(r.vesselName == "BW PAVILION ARANDA" && r.imo == "9792606" && r.callSign == "9V6330")
        #expect(r.calls.count == 10)
        let expected: [[String]] = [
            ["Bonny", "NGBON", "", "", "SL 1", "SL 1", "2026-07-15", "22:00", "2026-07-17", "13:00"],
            ["Montevideo", "UYMVD", "", "", "SL 1", "SL 1", "2026-07-01", "14:20", "2026-07-01", "18:45"],
            ["Escobar LNG", "ARBDE", "", "", "SL 1", "SL 1", "2026-06-29", "16:25", "2026-06-30", "22:35"],
            ["Savannah", "USSAV", "Savannah Port Area", "0001", "SL 1", "SL 1", "2026-06-13", "08:46", "2026-06-14", "08:06"],
            ["Eemshaven", "NLEEM", "Eemshaven: Eems Energy Terminal", "0039", "SL 1", "SL 1", "2026-06-01", "00:01", "2026-06-03", "01:15"],
            ["Corpus Christi", "USCRP", "Corpus Christi Port Area", "0001", "SL 1", "SL 1", "2026-05-15", "10:00", "2026-05-16", "07:20"],
            ["Algeciras", "ESALG", "Zonas de Fondeo", "0014", "SL 1", "SL 1", "2026-05-01", "06:00", "2026-05-02", "17:15"],
            ["Enez", "TRENE", "", "", "SL 1", "SL 1", "2026-04-25", "00:01", "2026-04-26", "17:15"],
            ["Freeport", "USFPO", "", "", "SL 1", "SL 1", "2026-04-03", "23:00", "2026-04-04", "12:28"],
            ["Dunkerque", "FRDKK", "DUNKERQUE LNG SAS", "0117", "SL 1", "SL 1", "2026-03-20", "21:00", "2026-03-22", "18:24"],
        ]
        for (i, row) in expected.enumerated() {
            let c = r.calls[i]
            #expect([c.portName, c.unLocode, c.portFacility, c.pfNo, c.securityLevelPort, c.securityLevelVessel,
                     c.arrivalDate, c.arrivalTime, c.departureDate, c.departureTime] == row, "row \(i + 1)")
            #expect(c.country == "" && c.sspFollowed == "" && c.specialMeasures == "")
        }
    }

    // TV: 10 §3.3.8 errors
    @Test func readerErrors() throws {
        let folder = TempFolder("aa-vessel")
        // Unrecognised layout.
        var wb = VesselTestWorkbook()
        wb.textRow(1, ["Hello", "World"])
        #expect(throws: VesselReadError(PortCallReader.unrecognisedMessage)) {
            try PortCallReader.read(url: try wb.write(in: folder, name: "a.xlsx"), now: VesselTestClock.now,
                                    today: VesselTestClock.today, zone: VesselTestClock.zone)
        }
        // Empty workbook.
        let empty = VesselTestWorkbook()
        #expect(throws: VesselReadError(PortCallReader.emptyMessage)) {
            try PortCallReader.read(url: try empty.write(in: folder, name: "b.xlsx"), now: VesselTestClock.now,
                                    today: VesselTestClock.today, zone: VesselTestClock.zone)
        }
        // "last ports of call" title without a Port Name header row.
        var a = VesselTestWorkbook()
        a.textRow(1, ["Last Ports of Call - 2 Years"])
        #expect(throws: VesselReadError(PortCallReader.noPortNameRowMessage)) {
            try PortCallReader.read(url: try a.write(in: folder, name: "c.xlsx"), now: VesselTestClock.now,
                                    today: VesselTestClock.today, zone: VesselTestClock.zone)
        }
        // "port of call list" title without a UN locator row.
        var b = VesselTestWorkbook()
        b.textRow(1, ["PORT OF CALL LIST - LAST 10 PORTS"])
        #expect(throws: VesselReadError(PortCallReader.noUnLocatorRowMessage)) {
            try PortCallReader.read(url: try b.write(in: folder, name: "d.xlsx"), now: VesselTestClock.now,
                                    today: VesselTestClock.today, zone: VesselTestClock.zone)
        }
        // Extension gate (VESSEL-301) from F2's reader.
        let csv = try folder.write("ports.csv", "a,b")
        #expect(throws: XlsxReadError.gate("Extension 'csv' is not supported. Supported extensions are '.xlsx', '.xlsm', '.xltx' and '.xltm'.")) {
            try PortCallReader.read(url: csv, now: VesselTestClock.now, today: VesselTestClock.today)
        }
    }

    // TV: 10 §3.3.4 layout B with real date / time cells and a missing name column (fallback to firstCol)
    @Test func layoutBTypedCellsAndFallback() throws {
        let folder = TempFolder("aa-vessel")
        var wb = VesselTestWorkbook()
        wb.textRow(2, ["Port", "", "Arrival", "", "Special measures"])
        wb.textRow(3, ["Port Name", "UN locator", "Date", "Time", ""])
        wb.text("A4", "Bonny"); wb.text("B4", "NGBON")
        wb.number("C4", "46218", numFmt: 14)
        wb.number("D4", "0.9166666666666666", numFmt: 20)
        wb.text("E4", "  Escort  ")
        let r = try PortCallReader.read(url: try wb.write(in: folder), now: VesselTestClock.now,
                                        today: VesselTestClock.today, zone: VesselTestClock.zone)
        #expect(r.format == PortCallReader.formatB)
        #expect(r.calls.count == 1)
        #expect(r.calls[0].portName == "Bonny" && r.calls[0].unLocode == "NGBON")
        #expect(r.calls[0].arrivalDate == "2026-07-15" && r.calls[0].arrivalTime == "22:00")
        #expect(r.calls[0].specialMeasures == "Escort")
    }

    // TV: 10 §3.3.1 — A wins when both detection sets match; "Port Name" header with the last duplicate column winning
    @Test func layoutAWinsAndLastColumnWins() throws {
        let folder = TempFolder("aa-vessel")
        var wb = VesselTestWorkbook()
        wb.textRow(1, ["Port Name, Country", "UN/LOCODE", "Date Arrived", "Date Arrived"])
        wb.textRow(2, ["Rotterdam, Netherlands", "NLRTM", "01/02/2026", "03/02/2026"])
        let r = try PortCallReader.read(url: try wb.write(in: folder), now: VesselTestClock.now,
                                        today: VesselTestClock.today, zone: VesselTestClock.zone)
        #expect(r.format == PortCallReader.formatA)
        #expect(r.calls.count == 1)
        #expect(r.calls[0].portName == "Rotterdam" && r.calls[0].country == "Netherlands")
        #expect(r.calls[0].arrivalDate == "2026-02-03")
        #expect(r.calls[0].unLocode == "")
    }
}

@Suite("W-VESSEL — PortsService")
@MainActor struct VesselPortsServiceTests {
    func vessel(_ name: String = "BW Pavilion Aranda") -> Vessel { Vessel(name: name) }

    func visitCount(_ d: AppData) -> Int { d.ports.reduce(0) { $0 + $1.visits.count } }

    // TV: 10 §7.6 scenario 1 + 2
    @Test func importAThenB() throws {
        let data = AppData(), v = vessel()
        data.vessels.append(v)
        let ra = PortsService.apply(data: data, vessel: v, calls: try VesselPOC.calls(VesselPOC.layoutA))
        #expect(ra == .init(added: 47, updated: 0, newVisits: 47))
        #expect(data.ports.count == 36 && visitCount(data) == 47)
        func port(_ name: String, _ country: String) -> PortRecord? {
            data.ports.first { $0.name == name && $0.country == country }
        }
        #expect(port("Corpus Christi", "United States")?.visits.count == 4)
        #expect(port("Barrow Island", "Australia")?.visits.count == 4)
        #expect(port("Savannah", "United States")?.visits.count == 2)
        #expect(port("Singapore", "Singapore")?.visits.count == 2)
        #expect(port("Hong Kong", "Hong Kong S.A.R.")?.visits.count == 2)
        #expect(port("Incheon", "South Korea")?.visits.count == 2)
        #expect(port("Rotterdam", "Netherlands")?.visits.count == 2)
        #expect(port("Freeport", "United States") != nil && port("Freeport", "Bahamas") != nil)
        #expect(data.ports.allSatisfy { $0.unLocode.isEmpty })

        let rb = try VesselPOC.read(VesselPOC.layoutB)
        #expect(!PortsAnalysis.needsDifferentVesselConfirmation(fileVessel: rb.vesselName, vessel: v.name))
        let r2 = PortsService.apply(data: data, vessel: v, calls: rb.calls.map { $0.makePortCall() })
        #expect(r2 == .init(added: 0, updated: 10, newVisits: 0))
        #expect(data.ports.count == 36 && visitCount(data) == 47)
        let bonny = try #require(v.portCalls.first { $0.portName == "Bonny" })
        #expect([bonny.country, bonny.unLocode, bonny.arrivalTime, bonny.departureTime, bonny.securityLevelPort,
                  bonny.securityLevelVessel, bonny.sspFollowed]
                == ["Nigeria", "NGBON", "22:00", "13:00", "SL 1", "SL 1", "YES"])
        let bonnyPort = try #require(port("Bonny", "Nigeria"))
        #expect(bonnyPort.unLocode == "NGBON")
        #expect(bonnyPort.visits[0].arrivalTime == "22:00" && bonnyPort.visits[0].departureTime == "13:00")
        #expect(bonnyPort.visits[0].vesselId == v.id)
        #expect(port("Freeport", "United States")?.unLocode == "USFPO")
        #expect(port("Freeport", "Bahamas")?.unLocode == "")

        // Scenario 3: idempotent re-imports; A last → security levels revert to "1".
        let r3 = PortsService.apply(data: data, vessel: v, calls: rb.calls.map { $0.makePortCall() })
        #expect(r3 == .init(added: 0, updated: 10, newVisits: 0))
        let r4 = PortsService.apply(data: data, vessel: v, calls: try VesselPOC.calls(VesselPOC.layoutA))
        #expect(r4 == .init(added: 0, updated: 47, newVisits: 0))
        #expect(bonny.securityLevelPort == "1")
        #expect(bonny.arrivalTime == "22:00")                    // empty incoming keeps the existing time
    }

    // TV: 10 §7.6 scenario 4 (reverse order)
    @Test func importBThenA() throws {
        let data = AppData(), v = vessel()
        let r1 = PortsService.apply(data: data, vessel: v, calls: try VesselPOC.calls(VesselPOC.layoutB))
        #expect(r1 == .init(added: 10, updated: 0, newVisits: 10))
        #expect(data.ports.count == 10 && data.ports.allSatisfy { !$0.unLocode.isEmpty && $0.country.isEmpty })
        let r2 = PortsService.apply(data: data, vessel: v, calls: try VesselPOC.calls(VesselPOC.layoutA))
        #expect(r2 == .init(added: 37, updated: 10, newVisits: 37))
        #expect(data.ports.count == 36 && visitCount(data) == 47)
        #expect(data.ports.first { $0.name == "Freeport" && $0.unLocode == "USFPO" }?.country == "United States")
        #expect(data.ports.contains { $0.name == "Freeport" && $0.country == "Bahamas" })
        #expect(v.portCalls.first { $0.portName == "Bonny" }?.securityLevelPort == "1")
    }

    // TV: 10 §7.6 scenario 5
    @Test func differentVesselPrompt() throws {
        let rb = try VesselPOC.read(VesselPOC.layoutB)
        #expect(PortsAnalysis.needsDifferentVesselConfirmation(fileVessel: rb.vesselName, vessel: "Other"))
        #expect(PortsAnalysis.differentVesselMessage(fileVessel: rb.vesselName, vessel: "Other", count: rb.calls.count)
                == "This file lists vessel \"BW PAVILION ARANDA\", but you're importing into \"Other\".\n\nImport these 10 port call(s) for Other anyway?")
        #expect(!PortsAnalysis.needsDifferentVesselConfirmation(fileVessel: "", vessel: "Other"))
    }

    func scenario2() throws -> (AppData, Vessel) {
        let data = AppData(), v = vessel()
        data.vessels.append(v)
        PortsService.apply(data: data, vessel: v, calls: try VesselPOC.calls(VesselPOC.layoutA))
        PortsService.apply(data: data, vessel: v, calls: try VesselPOC.calls(VesselPOC.layoutB))
        return (data, v)
    }

    // TV: 10 §7.6 scenario 6
    @Test func removeCallPrunesEmptyPort() throws {
        let (data, v) = try scenario2()
        let bonny = try #require(v.portCalls.first { $0.portName == "Bonny" })
        PortsService.removeCall(data: data, vessel: v, call: bonny)
        #expect(!v.portCalls.contains { $0 === bonny })
        #expect(data.ports.count == 35 && visitCount(data) == 46)
        #expect(!data.ports.contains { $0.name == "Bonny" })
    }

    // TV: 10 §7.6 scenario 7 — DECISIONS 10 Q3 fix: after a rename the visit is matched by VesselId and removed.
    @Test func removeCallAfterRenameUsesVesselId() throws {
        let (data, v) = try scenario2()
        v.name = "Aranda"
        let call = try #require(v.portCalls.first { $0.portName == "Montevideo" })
        PortsService.removeCall(data: data, vessel: v, call: call)
        #expect(!data.ports.contains { $0.name == "Montevideo" })
        #expect(data.ports.count == 35 && visitCount(data) == 46)
    }

    // TV: 10 §7.6 scenario 8 — DECISIONS 10 Q3 fix: a same-day call at another port keeps its visit.
    @Test func sameDayCrossPortKeepsOtherVisit() throws {
        let data = AppData(), v = vessel()
        let x = PortCall(portName: "X"); x.arrivalDate = "2026-01-01"
        let y = PortCall(portName: "Y"); y.arrivalDate = "2026-01-01"
        PortsService.apply(data: data, vessel: v, calls: [x, y])
        #expect(data.ports.count == 2)
        PortsService.removeCall(data: data, vessel: v, call: x)
        #expect(data.ports.map(\.name) == ["Y"])
        #expect(data.ports[0].visits.count == 1)
        #expect(v.portCalls.map(\.portName) == ["Y"])
    }

    // TV: 10 §7.6 legacy visits without VesselId still match by name.
    @Test func removeLegacyVisitByName() {
        let data = AppData(), v = vessel()
        let p = PortRecord(name: "Bonny", country: "Nigeria",
                           visits: [PortVisit(vesselName: "bw pavilion aranda", arrivalDate: "2026-07-15")])
        data.ports.append(p)
        let call = PortCall(portName: "Bonny"); call.country = "Nigeria"; call.arrivalDate = "2026-07-15"
        v.portCalls.append(call)
        PortsService.removeCall(data: data, vessel: v, call: call)
        #expect(data.ports.isEmpty && v.portCalls.isEmpty)
    }

    // TV: 10 §7.7 export → re-import (lossy quirk)
    @Test func exportReimportIsLossy() throws {
        let (_, v) = try scenario2()
        let folder = TempFolder("aa-vessel")
        let url = folder.file("Ports-BW.xlsx")
        try PortsService.export(v, to: url)
        let r = try PortCallReader.read(url: url, now: VesselTestClock.now, today: VesselTestClock.today, zone: VesselTestClock.zone)
        #expect(r.format == PortCallReader.formatB)
        #expect(r.calls.count == 47)
        #expect(r.calls.allSatisfy { $0.arrivalDate.isEmpty && $0.country.isEmpty && $0.unLocode.isEmpty })
        let data2 = AppData(), fresh = vessel("Fresh")
        // Seed the DB with the scenario-2 ports so the date-less visits attach to existing ports.
        let (seed, _) = try scenario2()
        data2.ports = seed.ports
        let res = PortsService.apply(data: data2, vessel: fresh, calls: r.calls.map { $0.makePortCall() })
        #expect(res == .init(added: 35, updated: 12, newVisits: 35))
    }

    // TV: 10 §4.5 export layout
    @Test func exportLayout() throws {
        let (_, v) = try scenario2()
        let spec = PortsService.exportSheet(v)
        #expect(spec.name == "Ports of Call")
        #expect(spec.header == ["Port", "Country", "UN/LOCODE", "Port Facility", "PF no.", "Arrival Date", "Arrival Time",
                                "Departure Date", "Departure Time", "Sec. Port", "Sec. Vessel", "SSP", "Special measures"])
        #expect(spec.boldHeader)
        #expect(spec.rows.count == 47)
        #expect(spec.rows.first?.first == .text("Bonny"))
        #expect(spec.rows.last?.first == .text("Ceuta"))
        #expect(spec.rows.allSatisfy { $0.allSatisfy { if case .number = $0 { return false }; return true } })
    }

    // TV: 10 §7.13 ports default sort, VESSEL-208 quirk, VESSEL-210 summary
    @Test func panelSortAndSummary() throws {
        let (_, v) = try scenario2()
        let byArrivalDesc = PortsAnalysis.sort(v.portCalls, by: .arrival, descending: true)
        #expect(byArrivalDesc.first?.portName == "Bonny" && byArrivalDesc.first?.arrivalDisplay == "2026-07-15 22:00")
        #expect(byArrivalDesc.last?.portName == "Ceuta" && byArrivalDesc.last?.arrivalDisplay == "2024-07-29")
        let special = PortsAnalysis.sort(v.portCalls, by: .special, descending: false)
        #expect(special.first?.portName == "Ceuta")
        let toggled = PortsAnalysis.toggledSort(current: .arrival, descending: true, clicked: .special)
        #expect(toggled.column == .special && !toggled.descending)
        let byPort = PortsAnalysis.sort(v.portCalls, by: .port, descending: false)
        #expect(byPort.first?.portName == "Algeciras")
        #expect(PortsAnalysis.summary(vessel: v, shown: 47)
                == "⚓ 47 port call(s)  ·  latest: Bonny, Nigeria (2026-07-15)")
        #expect(PortsAnalysis.summary(vessel: v, shown: 3)
                == "⚓ 47 port call(s)  ·  showing 3  ·  latest: Bonny, Nigeria (2026-07-15)")
        #expect(PortsAnalysis.summary(vessel: Vessel(name: "E"), shown: 0) == PortsAnalysis.noCallsSummary)
        #expect(PortsAnalysis.summary(vessel: nil, shown: 0) == "No vessel selected.")
        #expect(PortsAnalysis.filter(v.portCalls, query: " ngbon ").map(\.portName) == ["Bonny"])
        #expect(PortsAnalysis.filter(v.portCalls, query: "united kingdom").count >= 1)
    }

    // TV: 10 VESSEL-251…254 Ports Database
    @Test func databaseView() throws {
        let (data, _) = try scenario2()
        let list = PortsAnalysis.databasePorts(data.ports, query: "")
        #expect(list.count == 36)
        #expect(list.map(\.name) == list.map(\.name).sorted { NetText.compareIgnoreCase($0, $1) == .orderedAscending })
        #expect(PortsAnalysis.databaseStatus(data.ports, shown: 36) == "36 port(s)  ·  47 visit(s)")
        let filtered = PortsAnalysis.databasePorts(data.ports, query: "free")
        #expect(filtered.count == 2)
        #expect(PortsAnalysis.databaseStatus(data.ports, shown: filtered.count) == "36 port(s)  ·  47 visit(s)  ·  showing 2")
        #expect(PortsAnalysis.databaseStatus([], shown: 0) == "No ports yet. Import a ports-of-call list on any vessel's “Ports” tab.")
        let corpus = try #require(data.ports.first { $0.name == "Corpus Christi" })
        #expect(PortsAnalysis.visitsHeader(corpus) == "⚓ Corpus Christi (USCRP), United States   —   4 visit(s)")
        let ordered = PortsAnalysis.orderedVisits(corpus)
        #expect(ordered.first?.arrivalDate == "2026-05-15")
        #expect(zip(ordered, ordered.dropFirst()).allSatisfy { ($0.arrivalValue?.ticks ?? 0) >= ($1.arrivalValue?.ticks ?? 0) })
        #expect(PortsAnalysis.visitCountText(1) == "1 visit" && PortsAnalysis.visitCountText(4) == "4 visits")
        #expect(PortsAnalysis.retainedSelection(corpus.id, in: filtered) == nil)
        #expect(PortsAnalysis.retainedSelection(corpus.id, in: list) == corpus.id)
    }

    // TV: 10 VESSEL-204 activity-log texts
    @Test func logTexts() {
        #expect(PortsAnalysis.logName(added: 47, updated: 0) == "47 new, 0 updated")
        #expect(PortsAnalysis.logDetail(vessel: "BW Pavilion Aranda", format: PortCallReader.formatA)
                == "BW Pavilion Aranda · Last Ports of Call (2 years)")
        #expect(PortsAnalysis.importedHint(count: 10, vessel: "V", added: 0, updated: 10, format: PortCallReader.formatB, newVisits: 0)
                == "Imported 10 port(s) for V (0 new, 10 updated) — Port of Call List (last 10 ports). 0 new visit(s) in the ports database.")
    }
}
