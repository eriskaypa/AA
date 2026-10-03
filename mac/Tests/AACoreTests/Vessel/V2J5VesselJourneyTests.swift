// V2-J5 journey (Stage V round 2, adopted by the integrator for W-VESSEL): vessel quick cards, Shippalm work orders,
// ports + global Ports DB, through save / reload. The crew-checklist reminder journey lives in
// Tests/AACoreTests/Crew/V2J5CrewJourneyTests.swift (W-CREW).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct V2J5VesselJourney {
    let clock = VesselTestClock.clock
    let today = VesselTestClock.today
    let zone = VesselTestClock.zone

    // MARK: Quick cards

    @Test func quickCardsCreateEditDuplicateDeleteReload() throws {
        let made = StoreFactory.make(clock: clock); let store = made.store
        let v = Vessel(name: "BW Pavilion Aranda"); store.data.vessels.append(v)
        let srcFolder = TempFolder("j5src"); let src = srcFolder.file("Manual v2.pdf")
        try Data("pdf".utf8).write(to: src)
        // Imported copy
        let a = QuickCardLayout.newCard(existingCount: v.quickCards.count)
        let rel = try AttachmentStore.importFile(made.dataStore, from: src)
        QuickCardLayout.setTarget(a, rel, kind: .importedCopy)
        a.title = QuickCardLayout.titleForFile(src)
        v.quickCards.append(a)
        #expect(rel.hasPrefix("files/") && rel.hasSuffix("_Manual v2.pdf") && a.title == "Manual v2")
        #expect(a.x == 24 && a.y == 24 && !a.isLink && !a.linkInPlace && !a.isFolder)
        #expect(FileManager.default.fileExists(atPath: made.dataStore.appFolder.appending(path: rel).path))
        // Web link, folder, in-place file (Windows UNC path kept verbatim)
        let b = QuickCardLayout.newCard(existingCount: v.quickCards.count)
        QuickCardLayout.setTarget(b, "https://shippalm.example", kind: .webLink); v.quickCards.append(b)
        let c = QuickCardLayout.newCard(existingCount: v.quickCards.count)
        QuickCardLayout.setTarget(c, "\\\\server\\ships\\Cargo", kind: .folder); v.quickCards.append(c)
        let d = QuickCardLayout.newCard(existingCount: v.quickCards.count)
        QuickCardLayout.setTarget(d, "F:\\Docs\\x.pdf", kind: .liveFile); v.quickCards.append(d)
        #expect((b.x, c.x, d.x) == (52, 80, 108))
        #expect(b.isLink && !b.linkInPlace && c.isFolder && c.linkInPlace && d.linkInPlace && !d.isFolder)
        // Move + resize clamps, duplicate offset
        (a.x, a.y) = QuickCardLayout.dragged(originX: 24, originY: 24, dx: -50, dy: 300)
        (a.width, a.height) = QuickCardLayout.resized(width: 180, height: 120, dx: -500, dy: 10)
        #expect(a.x == 0 && a.y == 324 && a.width == 90 && a.height == 130)
        let dup = QuickCardLayout.duplicate(a); v.quickCards.append(dup)
        #expect(dup.id != a.id && dup.x == 24 && dup.y == 348 && dup.target == a.target)
        // Edit cancel restores the snapshot
        let snap = b.clone(); b.title = "changed"; b.icon = "🚢"; b.copy(from: snap)
        #expect(b.title == "" && b.icon == MaritimeIcons.defaultIcon && b.id == snap.id)
        // Delete (file stays)
        #expect(QuickCardLayout.deletePrompt(title: " ", icon: "🚢") == "Delete quick card '🚢'?")
        v.quickCards.removeAll { $0 === d }
        store.markDirty(); try store.flushIfDirty()
        // Reload
        let back = made.dataStore.load()
        let bv = try #require(back.vessels.first)
        #expect(bv.quickCards.map(\.target) == [rel, "https://shippalm.example", "\\\\server\\ships\\Cargo", rel])
        #expect(bv.quickCards[0].width == 90 && bv.quickCards[0].y == 324 && bv.notificationsEnabled)
        let raw = String(decoding: try Data(contentsOf: made.dataStore.currentDataFile), as: UTF8.self)
        #expect(raw.contains("\"Width\":90,") && raw.contains("\"X\":0,"))
        // Open-step classification for every kind
        #expect(QuickCardOpen.step(bv.quickCards[0], dataStore: made.dataStore) == .attachment)
        let lowerID = bv.quickCards[0].id.uuidString.lowercased()
        #expect(raw.contains(lowerID))
    }

    // MARK: Work orders

    func shippalmBook(_ rows: [[String]], notify: Bool = false) -> VesselTestWorkbook {
        var wb = VesselTestWorkbook()
        wb.sheetName = "Work Order List"
        wb.textRow(1, ["Work Order List"])
        var headers = ["No.", "Title", "Work Order Status", "Work Order Category Code", "Responsible Rank",
                       "Due Date", "Interval", "Function Description", "Overdue Days", "Last Done Date"]
        if notify { headers.append("Notify") }
        wb.textRow(3, headers)
        for (k, r) in rows.enumerated() {
            let row = 4 + k
            for (c, v) in r.enumerated() where !v.isEmpty {
                let ref = "\(XlsxWriter.colRef(c))\(row)"
                if c == 5, let serial = Int(v) { wb.number(ref, String(serial), numFmt: 14) }      // typed date
                else if c == 8, Int(v) != nil { wb.number(ref, v) }
                else if c == 9, Int(v) != nil { wb.number(ref, v) }                              // bare serial
                else { wb.text(ref, v) }
            }
        }
        return wb
    }

    @Test func workOrdersImportToggleReimportExportReload() throws {
        let made = StoreFactory.make(clock: clock); let store = made.store
        let v = Vessel(name: "BW Pavilion: Aranda?"); store.data.vessels.append(v)
        let folder = TempFolder("j5wo")
        let book = shippalmBook([
            ["ARA.22.3100", "Main engine overhaul", "Execution", "ROUTINE", "C/E", "46285", "64,000 H", "Main engine", "22", "46000"],
            ["ARA.22.10", "Lifeboat", "Approved", "CLASS", "3/O", "2026-10-29", "1W", "LSA", "0", ""],
            ["ara.22.9", "EEBD", "Planned", "ROUTINE", "3/O", "15/07/2026", "1M", "LSA", "", ""],
            ["ARA.22.100", "Fire loop", "Planned", "", "ETO", "", "3M", "FFA", "", ""],
        ])
        let url = try book.write(in: folder)
        let r1 = try WorkOrderShippalmReader.read(url: url, now: clock.now(), today: today, zone: zone)
        #expect(r1.jobs.count == 4)
        let up1 = WorkOrderAnalysis.upsert(into: v, parsed: r1.jobs.map { $0.makeJob() })
        #expect(up1 == .init(added: 4, updated: 0))
        let j1 = v.jobs[0]
        #expect(j1.dueDate == "2026-09-20" && j1.lastDoneDate == "2025-12-09" && j1.overdueDays == 22)
        #expect(v.jobs[2].dueDate == "15/07/2026")         // unparseable → raw
        #expect(WorkOrderAnalysis.dueInfo(j1, today: today).text == "OVERDUE 9d  (2026-09-20)")
        // Notify + Done toggles, master switch
        j1.notify = true
        WorkOrderAnalysis.toggleDone(v.jobs[1], to: true, today: today)
        #expect(v.jobs[1].completedDate == "2026-09-29")
        let bar = WorkOrderAnalysis.notificationBar(vessel: v, today: today)
        #expect(bar.text == "\u{26A0} 1 flagged work order(s) need attention \u{2014} 1 overdue, 0 due \u{2264}30d:  ARA.22.3100 (overdue 9d)")
        // Filters + sort
        let keyed = WorkOrderAnalysis.keyed(v.jobs, today: today)
        let jobNoSorted = WorkOrderAnalysis.sort(keyed, by: .jobNo, descending: false).map(\.job.jobNo)
        #expect(jobNoSorted == ["ARA.22.10", "ARA.22.100", "ARA.22.3100", "ara.22.9"])
        let due = WorkOrderAnalysis.filter(keyed, WorkOrderFilter(dueSoonOnly: true)).map(\.job.jobNo)
        #expect(due == ["ARA.22.3100"])
        #expect(WorkOrderAnalysis.categoryItems(v.jobs) == ["(all categories)", "CLASS", "ROUTINE"])
        try store.save()
        // Re-import (new title, Notify=No in file) keeps Notify / completion
        let book2 = shippalmBook([["ara.22.3100", "Main engine overhaul (rev)", "Execution", "ROUTINE", "C/E", "46285", "", "", "", ""],
                                  ["ARA.22.10", "Lifeboat", "", "", "", "", "", "", "", ""],
                                  ["ARA.23.1", "New job", "", "", "", "", "", "", "", ""]], notify: true)
        let r2 = try WorkOrderShippalmReader.read(url: try book2.write(in: folder, name: "b2.xlsx"), now: clock.now(),
                                                  today: today, zone: zone)
        let up2 = WorkOrderAnalysis.upsert(into: v, parsed: r2.jobs.map { $0.makeJob() })
        #expect(up2 == .init(added: 1, updated: 2) && v.jobs.count == 5)
        #expect(v.jobs[0].jobNo == "ara.22.3100" && v.jobs[0].notify && v.jobs[0].title == "Main engine overhaul (rev)")
        #expect(v.jobs[1].isCompleted && v.jobs[1].completedDate == "2026-09-29")
        // Export → sheet XML checks → re-read into a fresh vessel
        #expect(VesselText.workOrdersExportName(v.name) == "WorkOrders-BW Pavilion_ Aranda_.xlsx")
        let out = folder.file("WorkOrders.xlsx")
        try WorkOrderShippalmReader.write(v.jobs, to: out)
        let zip = try ZipReader(url: out)
        let sheet = String(decoding: try zip.data(for: zip.entry(named: "xl/worksheets/sheet1.xml")!), as: UTF8.self)
        let wbXml = String(decoding: try zip.data(for: zip.entry(named: "xl/workbook.xml")!), as: UTF8.self)
        #expect(wbXml.contains("name=\"report\""))
        #expect(sheet.contains("<c r=\"O2\"") )
        let r3 = try WorkOrderShippalmReader.read(url: out, now: clock.now(), today: today, zone: zone)
        #expect(r3.jobs.map(\.jobNo) == v.jobs.map(\.jobNo))
        #expect(r3.jobs[0].notify && r3.jobs[0].overdueDays == 0 && r3.jobs[0].dueDate == "2026-09-20")
        #expect(r3.jobs[2].dueDate == "15/07/2026")
        // Persist + reload
        try store.save()
        let back = made.dataStore.load()
        let bv = try #require(back.vessels.first)
        #expect(bv.jobs.count == 5 && bv.jobs[0].notify && bv.jobs[1].isCompleted)
        let raw = String(decoding: try Data(contentsOf: made.dataStore.currentDataFile), as: UTF8.self)
        #expect(raw.contains("\"OverdueDays\":0,"))
        // Delete two jobs
        WorkOrderAnalysis.delete([bv.jobs[3], bv.jobs[4]], from: bv)
        #expect(bv.jobs.count == 3)
    }

    // MARK: Ports

    @Test func portsImportBothLayoutsDatabaseDeleteRenameExport() throws {
        let made = StoreFactory.make(clock: clock); let store = made.store
        let v = Vessel(name: "BW Pavilion Aranda"); store.data.vessels.append(v)
        let a = try PortCallReader.read(url: Fixtures.url("xlsx/Last Ports - 24 Months (4).xlsx"), now: clock.now(),
                                        today: today, zone: zone)
        let b = try PortCallReader.read(url: Fixtures.url("xlsx/Port of Call List - Last 10 Ports (14).xlsx"),
                                        now: clock.now(), today: today, zone: zone)
        #expect(a.calls.count == 47 && b.calls.count == 10 && b.vesselName == "BW PAVILION ARANDA")
        #expect(!PortsAnalysis.needsDifferentVesselConfirmation(fileVessel: b.vesselName, vessel: v.name))
        let ra = PortsService.apply(data: store.data, vessel: v, calls: a.calls.map { $0.makePortCall() })
        store.logAdded(kind: "Ports import", name: PortsAnalysis.logName(added: ra.added, updated: ra.updated),
                       detail: PortsAnalysis.logDetail(vessel: v.name, format: a.format))
        #expect(ra == .init(added: 47, updated: 0, newVisits: 47))
        let rb = PortsService.apply(data: store.data, vessel: v, calls: b.calls.map { $0.makePortCall() })
        #expect(rb == .init(added: 0, updated: 10, newVisits: 0))
        #expect(store.data.ports.count == 36 && store.data.ports.reduce(0) { $0 + $1.visits.count } == 47)
        let bonny = try #require(v.portCalls.first { $0.portName == "Bonny" })
        #expect(bonny.unLocode == "NGBON" && bonny.arrivalTime == "22:00" && bonny.country == "Nigeria")
        // Summary / sort
        #expect(PortsAnalysis.summary(vessel: v, shown: 47) == "\u{2693} 47 port call(s)  \u{00B7}  latest: Bonny, Nigeria (2026-07-15)")
        let sorted = PortsAnalysis.sort(v.portCalls, by: .arrival, descending: true)
        #expect(sorted.first?.portName == "Bonny" && sorted.last?.portName == "Ceuta")
        // Database view
        let dbPorts = PortsAnalysis.databasePorts(store.data.ports, query: "")
        #expect(PortsAnalysis.databaseStatus(store.data.ports, shown: dbPorts.count) == "36 port(s)  \u{00B7}  47 visit(s)")
        let freeport = try #require(store.data.ports.first { $0.unLocode == "USFPO" })
        #expect(freeport.country == "United States")
        // Persist + reload
        try store.save()
        let back = made.dataStore.load()
        #expect(back.ports.count == 36 && back.vessels[0].portCalls.count == 47)
        let raw = String(decoding: try Data(contentsOf: made.dataStore.currentDataFile), as: UTF8.self)
        #expect(raw.contains("\"Kind\":\"Ports import\"") && raw.contains("\"Name\":\"47 new, 0 updated\""))
        // Delete Bonny → port pruned
        PortsService.removeCall(data: store.data, vessel: v, call: bonny)
        #expect(store.data.ports.count == 35 && store.data.ports.reduce(0) { $0 + $1.visits.count } == 46)
        // Rename then delete Montevideo (Mac fix: visit removed by VesselId)
        v.name = "Aranda"
        let mvd = try #require(v.portCalls.first { $0.portName == "Montevideo" })
        PortsService.removeCall(data: store.data, vessel: v, call: mvd)
        #expect(!store.data.ports.contains { $0.name == "Montevideo" })
        // Export → re-import into a fresh vessel (lossy, layout B detection)
        let pf = TempFolder("j5p"); let out = pf.file("Ports-Aranda.xlsx")
        try PortsService.export(v, to: out)
        let re = try PortCallReader.read(url: out, now: clock.now(), today: today, zone: zone)
        #expect(re.format == PortCallReader.formatB && re.calls.count == 45 && re.calls.allSatisfy { $0.arrivalDate.isEmpty })
    }
}
