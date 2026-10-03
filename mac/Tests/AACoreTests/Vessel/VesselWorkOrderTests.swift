// TV: 10 §7.8 ExcelDate / ParseBool / Overdue Days, §7.9 header detection, §7.10 upsert, §7.11 DueInfo + DST,
//     §7.12 summary and notifications bar, §7.13 filters and sort, §7.16 export → import round trip, X.8.7 round trip,
//     VESSEL-123 / VESSEL-332 performance (2 524 rows); DECISIONS 10 Q7 notification dedup.
import Foundation
import Testing
@testable import AACore

@Suite("W-VESSEL — Shippalm reader and writer")
@MainActor struct VesselShippalmTests {
    let today = VesselTestClock.today

    // TV: 10 §7.8 ExcelDate (through the reader's date columns)
    @Test(arguments: [
        ("48108", "2031-09-17"), ("46218", "2026-07-15"), ("45000", "2023-03-15"), ("20001", "1954-10-04"),
        ("15000", "15000"), ("2026-07-15", "2026-07-15"), ("2026/07/15", "2026-07-15"), ("07/15/2026", "2026-07-15"),
        ("03/04/2026", "2026-03-04"), ("15/07/2026", "15/07/2026"), ("", ""),
    ])
    func excelDate(_ raw: String, _ expected: String) {
        #expect(ShippalmDates.excelDate(raw, today: today) == expected)
    }

    // TV: 10 §7.8 ParseBool
    @Test func parseBool() {
        for s in ["Yes", "yes ", "TRUE", "true", "Y", "1"] { #expect(WorkOrderShippalmReader.parseBool(s), "\(s)") }
        for s in ["No", "0", "FALSE", "on", ""] { #expect(!WorkOrderShippalmReader.parseBool(s), "\(s)") }
    }

    // TV: 10 §7.8 Overdue Days, §3.4.1 int.TryParse(Any)
    @Test(arguments: [
        ("12", 12), ("-3", -3), ("12.0", 12), ("12.5", 0), ("1,234", 1234), ("abc", 0), ("(5)", -5), (" 7 ", 7),
        ("", 0), ("5-", -5), ("1E3", 1000), ("99999999999", 0), ("48108", 48108),
    ])
    func overdueDays(_ raw: String, _ expected: Int) {
        #expect(WorkOrderShippalmReader.parseOverdueDays(raw) == expected)
    }

    func read(_ wb: VesselTestWorkbook, in folder: TempFolder) throws -> WorkOrderReadResult {
        try WorkOrderShippalmReader.read(url: try wb.write(in: folder), now: VesselTestClock.now, today: today,
                                         zone: VesselTestClock.zone)
    }

    // TV: 10 §7.9 header detection
    @Test func headerDetection() throws {
        let folder = TempFolder("aa-vessel")
        var wb = VesselTestWorkbook()
        wb.textRow(1, ["Work Order List"])
        wb.textRow(3, ["No.", "Title", "Title", "Work Order\nStatus", "Due  Date", "Overdue Days"])
        wb.textRow(4, ["ARA.22.3120", "Main engine", "Other", "Execution", "2026-10-01", ""])
        wb.number("F4", "12")
        wb.textRow(5, ["   ", "skipped (blank No.)"])
        let r = try read(wb, in: folder)
        #expect(r.jobs.count == 1)
        let j = r.jobs[0]
        #expect(j.jobNo == "ARA.22.3120" && j.title == "Main engine" && j.status == "Execution")
        #expect(j.dueDate == "2026-10-01" && j.overdueDays == 12 && !j.notify)
        #expect(j.importedAt == "2026-09-29 10:15")

        var bad = VesselTestWorkbook()
        bad.textRow(1, ["No", "Title"])
        #expect(throws: VesselReadError(WorkOrderShippalmReader.headerMissingMessage)) { try read(bad, in: folder) }

        // An empty workbook → [] (not an error).
        #expect(try read(VesselTestWorkbook(), in: folder).jobs.isEmpty)
    }

    // TV: 10 §3.4.1 typed date cells and serials in date columns (renderer B + ExcelDate)
    @Test func typedDateCells() throws {
        let folder = TempFolder("aa-vessel")
        var wb = VesselTestWorkbook()
        wb.textRow(1, ["No.", "Title", "Due Date", "Last Done Date", "Finished Date-Time", "Notify"])
        wb.text("A2", "J1"); wb.text("B2", "x")
        wb.number("C2", "46218", numFmt: 14)                 // a real date cell
        wb.number("D2", "48108")                             // a bare serial
        wb.number("E2", "46218.75", numFmt: 22)              // time dropped
        wb.raw("F2", "<c r=\"F2\" t=\"b\"><v>1</v></c>")    // TRUE → Notify
        let r = try read(wb, in: folder)
        #expect(r.jobs[0].dueDate == "2026-07-15")
        #expect(r.jobs[0].lastDoneDate == "2031-09-17")
        #expect(r.jobs[0].finishedDate == "2026-07-15")
        #expect(r.jobs[0].notify)
    }

    // TV: 10 §7.16, §4.4, X.8.7 round trip
    @Test func exportImportRoundTrip() throws {
        let jobs: [ShipJob] = (1...3).map { i in
            let j = ShipJob(jobNo: "ARA.22.\(i)")
            j.title = "Job \(i)"; j.workPlanNo = "WP\(i)"; j.status = "Execution"; j.classCode = "C\(i)"
            j.category = i == 1 ? "ROUTINE" : "CBM"; j.responsibleRank = "2/E"; j.functionNo = "6\(i)"
            j.functionDescription = "Function \(i)"; j.interval = "64,000 H"; j.dueStatus = "in Window"
            j.finishedDate = "2026-01-0\(i)"; j.lastDoneDate = "2025-12-0\(i)"
            j.dueDate = i == 1 ? "2031-09-17" : "2026-10-0\(i)"
            j.overdueDays = i == 1 ? 12 : 0
            j.notify = i == 1
            j.isCompleted = true; j.completedDate = "2026-09-01"
            return j
        }
        let folder = TempFolder("aa-vessel")
        let url = folder.file("WorkOrders-V.xlsx")
        try WorkOrderShippalmReader.write(jobs, to: url)

        // Package checks: sheet "report", I2 text in an @ column, O2 numeric 12, P2 "Yes", header bold.
        let wb = try XlsxWorkbook.open(url)
        #expect(wb.worksheets.map(\.name) == ["report"])
        let ws = try wb.load(wb.worksheets[0])
        #expect(ws.cell(2, 9).value == .text("2031-09-17"))
        #expect(ws.cell(2, 15).value == .number(12))
        #expect(ws.cell(2, 16).value == .text("Yes"))
        #expect(ws.cell(3, 16).value == .text("No"))
        #expect(ws.cell(1, 1).value == .text("No."))
        let spec = WorkOrderShippalmReader.exportSheet(jobs)
        #expect(spec.boldHeader && spec.header == WorkOrderShippalmReader.exportHeaders)
        #expect(spec.columns[8].textFormat && spec.columns[13].textFormat)
        #expect(spec.columns.enumerated().allSatisfy { ($0.offset == 8 || $0.offset == 13) == $0.element.textFormat })

        // Re-read into a new vessel: all 16 fields equal, Notify true, IsCompleted false.
        let back = try WorkOrderShippalmReader.read(url: url, now: VesselTestClock.now, today: today, zone: VesselTestClock.zone)
        #expect(back.jobs.count == 3)
        for (a, b) in zip(jobs, back.jobs) {
            #expect([b.jobNo, b.title, b.workPlanNo, b.status, b.classCode, b.category, b.responsibleRank, b.functionNo,
                     b.functionDescription, b.interval, b.dueStatus, b.dueDate, b.finishedDate, b.lastDoneDate]
                    == [a.jobNo, a.title, a.workPlanNo, a.status, a.classCode, a.category, a.responsibleRank, a.functionNo,
                        a.functionDescription, a.interval, a.dueStatus, a.dueDate, a.finishedDate, a.lastDoneDate])
            #expect(b.overdueDays == a.overdueDays && b.notify == a.notify)
        }
        let v = Vessel(name: "New")
        WorkOrderAnalysis.upsert(into: v, parsed: back.jobs.map { $0.makeJob() })
        #expect(v.jobs[0].notify && !v.jobs[0].isCompleted && v.jobs[0].completedDate == "")
    }

    // TV: VESSEL-123 / VESSEL-332 — 2 524 × 16 parse < 1 s, linear upsert
    @Test func largeExportPerformance() throws {
        let jobs: [ShipJob] = (0..<2524).map { i in
            let j = ShipJob(jobNo: "ARA.\(i / 100).\(i)")
            j.title = "Routine maintenance item \(i)"; j.category = ["ROUTINE", "CBM", "CLASS"][i % 3]
            j.dueDate = CivilDate(year: 2026, month: 1 + i % 12, day: 1 + i % 28)!.iso
            j.responsibleRank = ["C/E", "2/E", "3/E", "ETO"][i % 4]; j.functionDescription = "Function \(i % 50)"
            j.overdueDays = i % 7
            return j
        }
        let folder = TempFolder("aa-vessel")
        let url = folder.file("big.xlsx")
        try WorkOrderShippalmReader.write(jobs, to: url)
        let start = Date()
        let r = try WorkOrderShippalmReader.read(url: url, now: VesselTestClock.now, today: today, zone: VesselTestClock.zone)
        let parse = Date().timeIntervalSince(start)
        #expect(r.jobs.count == 2524)
        #expect(parse < 1.0, "parse took \(parse) s")
        let v = Vessel(name: "V")
        let t0 = Date()
        let res = WorkOrderAnalysis.upsert(into: v, parsed: r.jobs.map { $0.makeJob() })
        let res2 = WorkOrderAnalysis.upsert(into: v, parsed: r.jobs.map { $0.makeJob() })
        #expect(res == .init(added: 2524, updated: 0) && res2 == .init(added: 0, updated: 2524))
        #expect(Date().timeIntervalSince(t0) < 1.0)
        let t1 = Date()
        let rows = WorkOrderAnalysis.sort(WorkOrderAnalysis.filter(WorkOrderAnalysis.keyed(v.jobs, today: today),
                                                                    WorkOrderFilter(query: "item")),
                                          by: .due, descending: false)
        #expect(rows.count == 2524)
        _ = WorkOrderAnalysis.summary(jobs: v.jobs, shown: rows.count, today: today)
        #expect(Date().timeIntervalSince(t1) < 1.0)
    }
}

@Suite("W-VESSEL — Work-order analysis")
@MainActor struct VesselWorkOrderAnalysisTests {
    let today = VesselTestClock.today

    func job(_ no: String, due: String = "", notify: Bool = false, completed: Bool = false, completedDate: String = "",
             category: String = "") -> ShipJob {
        let j = ShipJob(jobNo: no)
        j.dueDate = due; j.notify = notify; j.isCompleted = completed; j.completedDate = completedDate; j.category = category
        return j
    }

    // TV: 10 §7.10 upsert
    @Test func upsertKeepsUserChoices() {
        let v = Vessel(name: "V")
        let existing = job("ARA.1", notify: true, completed: true, completedDate: "2026-09-01")
        existing.title = "Old"
        v.jobs = [existing]
        let a = ShipJob(jobNo: "ara.1"); a.title = "New title"; a.notify = false
        let b = ShipJob(jobNo: "ARA.2"); b.notify = true
        let c = ShipJob(jobNo: "ARA.2"); c.title = "Title B"
        let r = WorkOrderAnalysis.upsert(into: v, parsed: [a, b, c])
        #expect(r == .init(added: 1, updated: 2))
        #expect(v.jobs.count == 2)
        #expect(v.jobs[0] === existing)
        #expect(existing.jobNo == "ara.1" && existing.title == "New title" && existing.notify && existing.isCompleted
                && existing.completedDate == "2026-09-01")
        #expect(v.jobs[1].jobNo == "ARA.2" && v.jobs[1].title == "Title B" && v.jobs[1].notify)
        #expect(WorkOrderAnalysis.importedHint(count: 3, vessel: "V", added: r.added, updated: r.updated)
                == "Imported 3 work orders for V (1 new, 2 updated).")
        #expect(WorkOrderAnalysis.importedHint(count: 0, vessel: "V", added: 0, updated: 0)
                == "Imported 0 work orders for V (0 new, 0 updated).")
    }

    // TV: 10 §7.11 DueInfo
    @Test(arguments: [
        ("2026-09-28", false, "", "OVERDUE 1d  (2026-09-28)", WorkOrderTone.red),
        ("2026-09-29", false, "", "DUE TODAY  (2026-09-29)", .red),
        ("2026-10-29", false, "", "in 30d  (2026-10-29)", .orange),
        ("2026-10-30", false, "", "in 31d  (2026-10-30)", .amber),
        ("2026-12-28", false, "", "in 90d  (2026-12-28)", .amber),
        ("2026-12-29", false, "", "2026-12-29  (in 91d)", .green),
        ("", false, "", "", .gray),
        ("15/07/2026", false, "", "15/07/2026", .gray),
        ("2026-01-01", true, "2026-09-20", "✓ completed 2026-09-20", .green),
        ("2026-01-01", true, "", "✓ completed", .green),
    ])
    func dueInfo(_ due: String, _ done: Bool, _ doneDate: String, _ text: String, _ tone: WorkOrderTone) {
        let j = job("J", due: due, completed: done, completedDate: doneDate)
        let info = WorkOrderAnalysis.dueInfo(j, today: today)
        #expect(info.text == text && info.tone == tone)
    }

    // TV: 10 §7.11 DST check (calendar-day difference, never seconds / 86 400)
    @Test func daysAcrossDST() {
        let j = job("J", due: "2026-03-30")
        #expect(j.daysUntilDue(today: CivilDate(year: 2026, month: 3, day: 28)!) == 2)
    }

    var set712: [ShipJob] {
        [job("J1", due: "2026-09-20", notify: true, category: "ROUTINE"),
         job("J2", due: "2026-10-10", notify: true, category: "ROUTINE"),
         job("J3", due: "2026-12-01", category: "ROUTINE"),
         job("J4", due: "2026-09-01", notify: true, completed: true, completedDate: "2026-09-02", category: "CBM"),
         job("J5")]
    }

    // TV: 10 §7.12 summary
    @Test func summary() {
        #expect(WorkOrderAnalysis.summary(jobs: set712, shown: 5, today: today)
                == "⚙ 5 work orders   ·   ⚠ 1 overdue   ·   1 due ≤30d   ·   2 due ≤90d   ·   ✓ 1 completed   ·   🔔 3 notify-on   ·   showing 5\nBy category: ROUTINE 3   CBM 1   (none) 1")
        #expect(WorkOrderAnalysis.summary(jobs: [], shown: 0, today: today)
                == "No work orders imported yet for this ship. Click “Import Shippalm (.xlsx)...”.")
        #expect(WorkOrderAnalysis.summary(vessel: nil, shown: 0, today: today) == "No ship selected.")
        // Category grouping is case-sensitive, top 5 by count (ties keep first-appearance order).
        let cats = ["A", "a", "B", "B", "C", "D", "E", "F"].enumerated().map { job("X\($0.offset)", category: $0.element) }
        #expect(WorkOrderAnalysis.summary(jobs: cats, shown: 8, today: today).hasSuffix("By category: B 2   A 1   a 1   C 1   D 1"))
    }

    // TV: 10 §7.12 notifications bar
    @Test func notificationBar() {
        let red = WorkOrderAnalysis.notificationBar(enabled: true, jobs: set712, today: today)
        #expect(red.text == "⚠ 2 flagged work order(s) need attention — 1 overdue, 1 due ≤30d:  J1 (overdue 9d),   J2 (in 11d)")
        #expect(red.borderTone == .red && red.textTone == .red)
        let off = WorkOrderAnalysis.notificationBar(enabled: false, jobs: set712, today: today)
        #expect(off.text == "Off — turn on to track this ship's due / overdue work orders here." && off.borderTone == .gray && off.textTone == .gray)
        let clear = WorkOrderAnalysis.notificationBar(enabled: true, jobs: [job("J3", due: "2026-12-01", notify: true)], today: today)
        #expect(clear.text == "On — 1 flagged job(s), all clear (none due within 30 days)." && clear.borderTone == .green)
        let none = WorkOrderAnalysis.notificationBar(enabled: true, jobs: [job("J3", due: "2026-12-01")], today: today)
        #expect(none.text == WorkOrderAnalysis.barNoneText && none.borderTone == .gray && none.textTone == nil)
        let orange = WorkOrderAnalysis.notificationBar(enabled: true, jobs: [job("K", due: "2026-09-29", notify: true)], today: today)
        #expect(orange.text.hasSuffix("0 overdue, 1 due ≤30d:  K (in 0d)") && orange.borderTone == .orange)
        let many = (1...6).map { job("M\($0)", due: "2026-09-2\($0)", notify: true) }
        let manyBar = WorkOrderAnalysis.notificationBar(enabled: true, jobs: many, today: today)
        #expect(manyBar.text.hasPrefix("⚠ 6 flagged work order(s) need attention — 6 overdue, 0 due ≤30d:  M1 (overdue 8d),   M2 (overdue 7d)"))
        #expect(manyBar.text.hasSuffix("M4 (overdue 5d)   …"))
    }

    // TV: 10 §7.13 filters
    @Test func filters() {
        let k = WorkOrderAnalysis.keyed(set712, today: today)
        func names(_ f: WorkOrderFilter) -> Set<String> { Set(WorkOrderAnalysis.filter(k, f).map(\.job.jobNo)) }
        #expect(names(WorkOrderFilter(dueSoonOnly: true)) == ["J1", "J2", "J3"])
        #expect(names(WorkOrderFilter(notifyOnly: true)) == ["J1", "J2", "J4"])
        #expect(names(WorkOrderFilter(completion: .completedOnly)) == ["J4"])
        #expect(names(WorkOrderFilter(completion: .activeOnly)) == ["J1", "J2", "J3", "J5"])
        #expect(names(WorkOrderFilter(category: "routine")) == ["J1", "J2", "J3"])
        #expect(names(WorkOrderFilter(query: " j4 ")) == ["J4"])
        let ranked = job("R", category: "x"); ranked.responsibleRank = "Chief Officer"
        let k2 = WorkOrderAnalysis.keyed([ranked], today: today)
        #expect(WorkOrderAnalysis.filter(k2, WorkOrderFilter(query: "officer")).count == 1)  // rank is searched too
        #expect(WorkOrderAnalysis.filter(k2, WorkOrderFilter(rank: "chief officer")).count == 1)
    }

    // TV: 10 §7.13 sort
    @Test func sorting() {
        let k = WorkOrderAnalysis.keyed(set712, today: today)
        #expect(WorkOrderAnalysis.sort(k, by: .due, descending: false).map(\.job.jobNo) == ["J1", "J2", "J3", "J5", "J4"])
        #expect(WorkOrderAnalysis.sort(k, by: .due, descending: true).map(\.job.jobNo) == ["J4", "J5", "J3", "J2", "J1"])
        let ties = WorkOrderAnalysis.keyed([job("b", due: "2026-10-01"), job("A", due: "2026-10-01")], today: today)
        #expect(WorkOrderAnalysis.sort(ties, by: .due, descending: false).map(\.job.jobNo) == ["A", "b"])
        #expect(WorkOrderAnalysis.sort(ties, by: .due, descending: true).map(\.job.jobNo) == ["A", "b"])
        let nos = WorkOrderAnalysis.keyed([job("ARA.22.10"), job("ara.22.9"), job("ARA.22.100")], today: today)
        #expect(WorkOrderAnalysis.sort(nos, by: .jobNo, descending: false).map(\.job.jobNo) == ["ARA.22.10", "ARA.22.100", "ara.22.9"])
        #expect(WorkOrderAnalysis.sort(k, by: .notify, descending: true).map(\.job.jobNo) == ["J1", "J2", "J4", "J3", "J5"])
        #expect(WorkOrderAnalysis.sort(k, by: .done, descending: false).map(\.job.jobNo) == ["J1", "J2", "J3", "J5", "J4"])
        let t = WorkOrderAnalysis.toggledSort(current: .due, descending: false, clicked: .due)
        #expect(t.column == .due && t.descending)
        let n = WorkOrderAnalysis.toggledSort(current: .due, descending: true, clicked: .title)
        #expect(n.column == .title && !n.descending)
    }

    // TV: 10 VESSEL-105 filter combos
    @Test func filterCombos() {
        let jobs = [job("1"), job("2"), job("3")]
        jobs[0].status = "Execution"; jobs[1].status = "execution"; jobs[2].status = "Approved"
        #expect(WorkOrderAnalysis.statusItems(jobs) == ["(all statuses)", "Approved", "Execution"])
        #expect(WorkOrderAnalysis.categoryItems(jobs) == ["(all categories)"])
        #expect(WorkOrderAnalysis.rankItems(jobs) == ["(all ranks)"])
        #expect(WorkOrderAnalysis.keepSelection("Execution", in: ["(all statuses)", "Approved", "Execution"]) == "Execution")
        #expect(WorkOrderAnalysis.keepSelection("execution", in: ["(all statuses)", "Approved", "Execution"]) == nil)
        #expect(WorkOrderAnalysis.keepSelection(nil, in: ["(all statuses)"]) == nil)
    }

    // TV: 10 VESSEL-112…117 bulk actions and texts
    @Test func bulkActions() {
        let v = Vessel(name: "BW Pavilion Aranda")
        v.jobs = set712
        let shown = Array(v.jobs.prefix(3))
        #expect(WorkOrderAnalysis.targets(selected: [], shown: shown).count == 3)
        #expect(WorkOrderAnalysis.targets(selected: [v.jobs[4]], shown: shown).map(\.jobNo) == ["J5"])
        WorkOrderAnalysis.setCompleted(shown, done: true, today: today)
        #expect(shown.allSatisfy { $0.isCompleted && $0.completedDate == "2026-09-29" })
        WorkOrderAnalysis.setCompleted(shown, done: false, today: today)
        #expect(shown.allSatisfy { !$0.isCompleted && $0.completedDate == "" })
        WorkOrderAnalysis.toggleDone(v.jobs[0], to: true, today: today)
        #expect(v.jobs[0].completedDate == "2026-09-29")
        WorkOrderAnalysis.delete([v.jobs[0], v.jobs[2]], from: v)
        #expect(v.jobs.map(\.jobNo) == ["J2", "J4", "J5"])
        #expect(WorkOrderAnalysis.markedHint(count: 2, done: true) == "Marked 2 work order(s) completed.")
        #expect(WorkOrderAnalysis.markedHint(count: 1, done: false) == "Marked 1 work order(s) active.")
        #expect(WorkOrderAnalysis.notifyTargetHint(count: 3, on: true) == "Notifications turned ON for 3 work order(s).")
        #expect(WorkOrderAnalysis.notifyShownHint(count: 4, on: false) == "Notifications turned OFF for 4 shown job(s).")
        #expect(WorkOrderAnalysis.deleteConfirmMessage(count: 2, vessel: v.name)
                == "Delete 2 work order(s) from BW Pavilion Aranda? This is permanent (re-import to restore).")
        #expect(WorkOrderAnalysis.deletedHint(count: 2, vessel: v.name) == "Deleted 2 work order(s) from BW Pavilion Aranda.")
        #expect(WorkOrderAnalysis.importDialogTitle(v.name) == "Import Shippalm Work Order List for BW Pavilion Aranda")
        #expect(WorkOrderAnalysis.exportedHint(count: 3, vessel: "V") == "Exported 3 work orders for V.")
    }
}

@Suite("W-VESSEL — Work-order notification digest")
@MainActor struct VesselWorkOrderAlertTests {
    // DECISIONS 10 Q7 — flagged, active, overdue jobs; master switch; dedup per vessel/job/day.
    @Test func pendingAndDedup() throws {
        let clock = FixedClock(local: "2026-09-29T08:00:00", zone: VesselTestClock.zone)
        let today = clock.today()
        let a = Vessel(name: "Aranda"), b = Vessel(name: "Muted")
        b.notificationsEnabled = false
        func job(_ no: String, _ due: String, notify: Bool = true, done: Bool = false) -> ShipJob {
            let j = ShipJob(jobNo: no); j.dueDate = due; j.notify = notify; j.isCompleted = done; return j
        }
        a.jobs = [job("A1", "2026-09-20"), job("A2", "2026-09-27"), job("A3", "2026-09-28", notify: false),
                  job("A4", "2026-09-01", done: true), job("A5", "2026-10-05")]
        b.jobs = [job("B1", "2026-09-01")]
        let first = WorkOrderAlerts.pending(vessels: [a, b], today: today, alreadyNotified: [])
        #expect(first.count == 1)
        #expect(first[0].vesselID == a.id)
        #expect(first[0].overdue.map(\.jobNo) == ["A1", "A2"])
        #expect(first[0].body == "Aranda: 2 flagged work order(s) overdue — A1 (overdue 9d),   A2 (overdue 2d)")
        #expect(first[0].identifier == "aa.vessel.workorders." + a.id.uuidString.lowercased())

        let temp = TempDefaults("aa.vessel.tests"); defer { temp.remove() }
        let prefs = temp.preferences
        WorkOrderAlerts.storeKeys(Set(first[0].newKeys), prefs, today: today)
        let stored = WorkOrderAlerts.storedKeys(prefs, today: today)
        #expect(stored.count == 2)
        #expect(WorkOrderAlerts.pending(vessels: [a, b], today: today, alreadyNotified: stored).isEmpty)

        // A new overdue job the same day → one more alert covering only the new key.
        a.jobs.append(job("A6", "2026-09-28"))
        let again = WorkOrderAlerts.pending(vessels: [a, b], today: today, alreadyNotified: stored)
        #expect(again.count == 1 && again[0].newKeys == [WorkOrderAlerts.key(vesselID: a.id, jobNo: "A6", day: today)])
        #expect(again[0].overdue.count == 3)

        // The next day the stored keys no longer count.
        let tomorrow = today.addingDays(1)
        #expect(WorkOrderAlerts.storedKeys(prefs, today: tomorrow).isEmpty)
        #expect(WorkOrderAlerts.pending(vessels: [a], today: tomorrow, alreadyNotified: []).count == 1)
    }
}
