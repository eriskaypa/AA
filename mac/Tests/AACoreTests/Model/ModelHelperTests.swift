// TV: 01 §7.10 (model helpers: WhenText, CoversDay, ContractStatusOn, ParseDate exact formats, keys, displays,
//     status sync), 04 §7.3 (WhenText), 01 DATA-139 (copy helpers), DATA-140 (SIRE state), 03 Q-3 (per-device Ui
//     copy), 04 Q-G (friendly labels), TV-OWN-09 (escaping read/write), TV-OWN-10 (unknown nested members),
//     06 §4.5 / TV-OWN-11 (.aasched writer bytes), 09 CREW-052.
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct ModelHelperTests {
    func day(_ y: Int, _ m: Int, _ d: Int) -> CivilDate { CivilDate(year: y, month: m, day: d)! }
    func cal(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> NetDateTime {
        NetDateTime(year: y, month: m, day: d, hour: h, minute: min, kind: .unspecified)
    }

    // TV: 01 §7.10 and 04 §7.3 WhenText
    @Test func whenText() {
        let t = TaskItem(name: "t")
        #expect(t.whenText == "" && !t.hasRange && t.rangeFirst == nil)
        t.deadline = cal(2026, 10, 5)
        #expect(t.whenText == "2026-10-05" && t.rangeFirst == t.deadline)
        t.rangeStart = cal(2026, 10, 1)
        #expect(t.whenText == "2026-10-01 \u{2192} 2026-10-05" && t.hasRange && t.rangeFirst == t.rangeStart)
        t.rangeStart = cal(2026, 10, 5, 10)
        #expect(t.whenText == "2026-10-05" && !t.hasRange)
        t.rangeStart = cal(2026, 10, 9)
        #expect(t.whenText == "2026-10-05" && !t.hasRange)
        t.deadline = nil
        #expect(t.whenText == "" && t.rangeFirst == t.rangeStart)
        // 04 §7.3 rows
        let u = TaskItem(name: "u")
        u.deadline = cal(2026, 10, 1)
        #expect(u.whenText == "2026-10-01")
        u.rangeStart = cal(2026, 9, 28)
        #expect(u.whenText == "2026-09-28 \u{2192} 2026-10-01")
        u.rangeStart = cal(2026, 10, 1)
        #expect(u.whenText == "2026-10-01")
        u.rangeStart = cal(2026, 10, 5)
        #expect(u.whenText == "2026-10-01")
        // WhenText ignores originalText (a Local deadline read with an offset formats its wall clock)
        let parsed = NetDateTime(parsing: "2026-10-01T00:00:00+03:00", zone: TZ.athens)!
        u.deadline = parsed; u.rangeStart = nil
        #expect(u.whenText == "2026-10-01")
    }

    // TV: 01 §7.10 CoversDay
    @Test func coversDay() {
        let t = TaskItem(name: "t")
        #expect(!t.coversDay(day(2026, 10, 1)))
        t.rangeStart = cal(2026, 10, 1); t.deadline = cal(2026, 10, 5, 23, 59)
        #expect(!t.coversDay(day(2026, 9, 30)))
        #expect(t.coversDay(day(2026, 10, 1)) && t.coversDay(day(2026, 10, 3)) && t.coversDay(day(2026, 10, 5)))
        #expect(!t.coversDay(day(2026, 10, 6)))
        t.rangeStart = cal(2026, 10, 9)
        #expect(t.coversDay(day(2026, 10, 5)) && !t.coversDay(day(2026, 10, 4)) && !t.coversDay(day(2026, 10, 9)))
    }

    // TV: 01 §7.10 status sync (DATA-130 / REPO-040)
    @Test func statusSync() {
        let t = TaskItem(name: "t")
        t.isComplete = true
        #expect(t.status == .done)
        t.status = .blocked
        #expect(!t.isComplete)
        t.status = .inProgress
        t.isComplete = false
        #expect(t.status == .inProgress)
        t.status = .done
        #expect(t.isComplete)
        t.isComplete = false
        #expect(t.status == .todo)
        t.status = WorkStatus(rawValue: 9)                      // undefined values are kept
        #expect(!t.isComplete && t.status.rawValue == 9 && t.status.name == "9")
    }

    // TV: 01 §7.10 ContractStatusOn (today 2026-09-29) — DATA-135 / CREW-052
    @Test func contractStatus() {
        let today = day(2026, 9, 29)
        func status(_ signOff: String) -> ContractStatus {
            let c = CrewMember(); c.signOffDate = signOff
            return c.contractStatus(on: today)
        }
        #expect(status("2026-09-28") == .expired)
        #expect(status("2026-09-29") == .critical)
        #expect(status("2026-10-29") == .critical)
        #expect(status("2026-10-30") == .dueSoon)
        #expect(status("2026-11-28") == .dueSoon)
        #expect(status("2026-11-29") == .ok)
        #expect(status("") == .unknown)
        #expect(status("31/12/2026") == .unknown)
        let c = CrewMember(); c.signOffDate = "2026-10-09"
        #expect(c.daysUntilSignOff(today: today) == 10)
        #expect(c.contractStatus(on: today, criticalDays: 5, soonDays: 9) == .ok)
        #expect(ContractStatus.unknown.rawValue == 0 && ContractStatus.expired.rawValue == 4)
    }

    // TV: 01 §7.10 ParseDate — the exact formats (the .NET TryParse fallback rows are F2's NetDateParser)
    @Test func parseDateExactFormats() {
        for s in ["2026-03-04", "2026/03/04", "2026.03.04", " 2026-03-04 "] {
            let d = CrewMember.parseDate(s)
            #expect(d?.civilDate == day(2026, 3, 4) && d?.kind == .unspecified, "\(s)")
        }
        #expect(CrewMember.parseDate("abc") == nil)
        #expect(CrewMember.parseDate(nil) == nil && CrewMember.parseDate("  ") == nil)
        #expect(CrewMember.parseDate("2026-02-30") == nil)
        let job = ShipJob(); job.dueDate = "2026-10-02"
        #expect(job.dueDateValue?.civilDate == day(2026, 10, 2) && job.daysUntilDue(today: day(2026, 9, 29)) == 3)
        job.dueDate = ""
        #expect(job.daysUntilDue(today: day(2026, 9, 29)) == nil)
    }

    // TV: 01 §7.10 keys (DATA-133)
    @Test func identityKeys() {
        let pc = PortCall(); pc.portName = "Bonny"; pc.arrivalDate = "2026-05-01"
        #expect(pc.key == "bonny@2026-05-01")
        let p = PortRecord(); p.unLocode = "NGBON"
        #expect(p.key == "ngbon")
        let q = PortRecord(); q.name = "Bonny"; q.country = "Nigeria"
        #expect(q.key == "bonny|nigeria")
        let v = PortVisit(vesselName: "Alpha", arrivalDate: "2026-05-01", arrivalTime: "08:00")
        #expect(v.visitKey == "alpha|2026-05-01|08:00")
        let c = CrewMember(); c.employeeId = " "; c.firstName = "Ana"; c.lastName = "Cruz"
        #expect(c.key == "Ana|Cruz")
        c.firstName = ""
        #expect(c.key == "Cruz")
        c.employeeId = "E-1"
        #expect(c.key == "E-1")
        let job = ShipJob(); job.jobNo = "WO-12a"
        #expect(job.id == "wo-12a")
    }

    // TV: 01 §7.10 displays (DATA-134, §3.22)
    @Test func displays() {
        let tpl = ChecklistTemplate(name: "", items: [ChecklistTemplateItem(title: "a")])
        #expect(tpl.display == "(unnamed)  \u{B7}  1 item")
        tpl.items.append(ChecklistTemplateItem()); tpl.name = "Pre-arrival"
        #expect(tpl.display == "Pre-arrival  \u{B7}  2 items")
        let sched = ScheduleTemplate(name: "Watch", vesselName: "Alpha", entries: [ScheduleEntry(), ScheduleEntry()])
        #expect(sched.display == "Watch  \u{B7}  2 entries  \u{B7}  Alpha")
        sched.entries.removeLast(); sched.vesselName = ""
        #expect(sched.display == "Watch  \u{B7}  1 entry")
        #expect(QuickBucket(name: "Deck", category: "Location").display == "Deck  \u{B7}  Location")
        #expect(QuickBucket(name: "", category: "").display == "(unnamed)")
        #expect(QuickBucket(name: "", category: "Rank").display == "  \u{B7}  Rank")
        let log = LogEntry(timestampUtc: NetDateTime(year: 2026, month: 9, day: 29, hour: 8, minute: 15, second: 30, kind: .utc))
        #expect(log.timeUtc == "2026-09-29 08:15:30 UTC")
        #expect(log.timeLocal == log.timestampUtc.toLocalTime().format(.isoSecond))
        let trash = TrashedItem(name: "", kindLabel: "Task", deletedUtc: NetDateTime(year: 2026, month: 9, day: 29, hour: 8, kind: .utc))
        #expect(trash.display == "(unnamed)   \u{B7}   Task   \u{B7}   deleted \(trash.deletedLocal)")
        #expect(trash.deletedLocal == NetDateTime(year: 2026, month: 9, day: 29, hour: 8, kind: .utc).toLocalTime().format(.isoMinute))
        let pc = PortCall(); pc.portName = "Bonny"; pc.country = "Nigeria"; pc.arrivalDate = "2026-05-01"; pc.departureTime = "18:00"
        #expect(pc.displayName == "Bonny, Nigeria" && pc.arrivalDisplay == "2026-05-01" && pc.departureDisplay == "18:00")
        let port = PortRecord(); port.name = "Bonny"; port.unLocode = "NGBON"; port.country = "Nigeria"
        #expect(port.display == "Bonny (NGBON), Nigeria")
        let e = ScheduleEntry(kind: .procedure); e.date = "2026-10-02"; e.time = "09:00"
        #expect(e.kindIcon == "\u{1F4CB}" && e.whenDisplay == "2026-10-02 09:00")
        #expect(ScheduleEntry(kind: .task).kindIcon == "\u{2713}" && ScheduleEntry(kind: .equipment).kindIcon == "\u{2699}")
        #expect(ScheduleEntry(kind: .note).kindIcon == "\u{2022}")
        let f = FileItem(); #expect(f.sourceLabel == "Copy")
        f.linkInPlace = true; #expect(f.sourceLabel == "Live")
        f.isLink = true; #expect(f.sourceLabel == "Web link")              // CONT-094
        let crew = CrewMember(); crew.firstName = "Jos\u{E9}"; crew.middleName = "  "; crew.lastName = "Cruz"
        #expect(crew.fullName == "Jos\u{E9} Cruz")
        #expect(!crew.hasFlags && !crew.hasErrors)
        crew.flags = [CrewReviewFlag(severity: .warning), CrewReviewFlag(severity: .error)]
        #expect(crew.hasFlags && crew.hasErrors)
    }

    // TV: 01 DATA-139 copy helpers
    @Test func copyHelpers() {
        let a = QuickCard(id: G(9)); a.title = "Manuals"; a.target = "files/x"; a.isFolder = true; a.icon = "\u{1F6DF}"
        a.color = "#80FF0000"; a.x = 12.5; a.y = -24; a.width = 333.25; a.height = 0.1; a.extra.set("F", .bool(true))
        let b = a.clone()
        #expect(b !== a && b.id == a.id && b.toJSON(options: .dataFile) == a.toJSON(options: .dataFile))
        let c = QuickCard(id: G(10))
        c.copy(from: a)
        #expect(c.id == G(10) && c.title == "Manuals" && c.height == 0.1 && c.extra.isEmpty)
        let j = ShipJob()
        j.jobNo = "1"; j.title = "t"; j.workPlanNo = "w"; j.status = "s"; j.classCode = "c"; j.category = "g"
        j.responsibleRank = "r"; j.functionNo = "f"; j.functionDescription = "fd"; j.interval = "i"; j.dueStatus = "d"
        j.dueDate = "2026-10-01"; j.finishedDate = "fi"; j.lastDoneDate = "l"; j.overdueDays = -3; j.notify = true
        j.isCompleted = true; j.completedDate = "cd"; j.importedAt = "ia"
        let k = ShipJob()
        k.copy(from: j)
        #expect(k.toJSON(options: .dataFile) == j.toJSON(options: .dataFile))
        #expect(ShipJob.jsonKeys.count == 19)
    }

    // TV: 01 DATA-140 SIRE state helpers (Enum.TryParse emulation, toggles, counts)
    @Test func sireState() {
        let s = SireState()
        #expect(s.status(for: "1.1.1") == .none)
        s.setStatus(.inProgress, for: "1.1.1"); s.setStatus(.checked, for: "2.1.1"); s.setStatus(.checked, for: "3.1")
        #expect(s.questionStatuses["1.1.1"] == "InProgress" && s.count(of: .checked) == 2)
        s.setStatus(.none, for: "1.1.1")
        #expect(s.questionStatuses["1.1.1"] == nil && s.questionStatuses.count == 2)
        s.questionStatuses["n"] = "3"; s.questionStatuses["w"] = " Checked "; s.questionStatuses["x"] = "checked"
        s.questionStatuses["y"] = "7"; s.questionStatuses["z"] = "Bogus"
        #expect(s.status(for: "n") == .notApplicable && s.status(for: "w") == .checked)
        #expect(s.status(for: "x") == .none && s.status(for: "y") == .none && s.status(for: "z") == .none)
        #expect(s.questionStatuses["n"] == "3")                          // never rewritten by reading
        s.toggleBookmark("1.1.1"); s.toggleBookmark("2.1.1"); s.toggleBookmark("1.1.1")
        #expect(s.bookmarks == ["2.1.1"] && s.isBookmarked("2.1.1") && !s.isBookmarked("1.1.1"))
        s.toggleForExport("2.1.1")
        #expect(s.isForExport("2.1.1") && s.forExport == ["2.1.1"])
        s.tasks = [SireTask(questionNumber: "2.1.1", text: "a", isCompleted: true), SireTask(questionNumber: "2.1.1"),
                   SireTask(questionNumber: "3.1")]
        #expect(s.tasks(for: "2.1.1").count == 2 && s.totalTaskCount == 3 && s.completedTaskCount == 1)
        #expect(SireState.compareQuestionNumbers("2.10.1", "2.9.3") == .orderedDescending)
        #expect(SireState.compareQuestionNumbers("2.1", "2.1.0") == .orderedSame)
        #expect(SireState.compareQuestionNumbers("1.a", "1.0") == .orderedSame)
    }

    // DECISIONS 03 Q-3: per-device Ui keys come from the pre-reload state; shared keys keep the loaded value
    @Test func perDeviceUiCopy() throws {
        let loaded = UiState(), mine = UiState()
        mine.windowLeft = 10; mine.windowTop = 20; mine.windowWidth = 800; mine.windowHeight = 600; mine.windowState = "Normal"
        mine.dueWindowWidth = 300; mine.dueWindowHeight = 400; mine.selectedMainTabIndex = 4
        mine.selectedEquipmentId = G(1); mine.selectedTaskId = G(2); mine.selectedProcedureId = G(3); mine.selectedVesselId = G(4)
        mine.calendarSelectedDate = NetDateTime.calendarDate(day(2026, 9, 29)); mine.mapFocusedItemId = G(5)
        mine.groupExpanded["Task|A"] = false; mine.lastDigestDate = "2026-09-29"
        mine.tabOrder = ["TabTasks"]; mine.showShortcutBar = false
        loaded.tabOrder = ["TabEquipment"]; loaded.calendarViewMode = "Week"
        loaded.copyPerDeviceValues(from: mine)
        let out = loaded.toJSON(options: .dataFile)
        for key in UiState.perDeviceKeyNames {
            #expect(out[key] == mine.toJSON(options: .dataFile)[key], "\(key)")
        }
        #expect(loaded.tabOrder == ["TabEquipment"] && loaded.showShortcutBar && loaded.calendarViewMode == "Week")
        #expect(UiState.perDeviceKeyNames.allSatisfy { UiState.jsonKeys.contains($0) })
    }

    // 04 Q-G friendly labels are display-only; C# names otherwise
    @Test func enumLabels() {
        #expect(WorkStatus.allStatuses.map(\.friendlyLabel) == ["To Do", "In Progress", "Blocked", "Done"])
        #expect(WorkStatus.allStatuses.map(\.name) == ["Todo", "InProgress", "Blocked", "Done"])
        #expect(RecurrenceKind.allKinds.map(\.friendlyLabel) == ["None", "Daily", "Weekly", "Monthly", "Yearly"])
        #expect(FileKind.other.name == "Other" && ItemKind.vessel.name == "Vessel" && ScheduleKind.equipment.name == "Equipment")
        #expect(CrewFlagSeverity.error.name == "Error" && FileKind(rawValue: -1).name == "-1")
        #expect(TaskItem(name: "").kind == .task && Equipment(name: "").kind == .equipment)
        #expect(Procedure(name: "").kind == .procedure && Vessel(name: "").kind == .vessel)
        #expect(TrashItemType(rawValue: "Crew") == .crew && TrashItemType(rawValue: "crew") == nil)
    }

    // TV-OWN-09: escaped or raw input reads to the same model; the writer escapes (OC-01)
    @Test func tvOwn09() throws {
        let raw = try QuickCard(json: #require(try JSONParser.parse(#"{"Icon":"⚓","Title":"A&B <1>"}"#).objectValue), context: .standard)
        let esc = try QuickCard(json: #require(try JSONParser.parse(#"{"Icon":"\u2693","Title":"A\u0026B \u003C1\u003E"}"#).objectValue), context: .standard)
        #expect(raw.icon == esc.icon && raw.title == esc.title && raw.icon == "\u{2693}")
        let out = try JSONWriter.string(.object(raw.toJSON(options: .dataFile)))
        #expect(out.contains(#""Title":"A\u0026B \u003C1\u003E""#) && out.contains(#""Icon":"\u2693""#))
    }

    // TV-OWN-10: unknown nested members re-emitted after the task's known keys
    @Test func tvOwn10() throws {
        let ds = DataStore(appFolder: TempFolder().url, secrets: InMemorySecretStore())
        let data = try ModelCodec.decodeAppData(try JSONParser.parse(#"{"Tasks":[{"Name":"a","FutureField":{"x":1}}],"SchemaVersion":1}"#), context: .standard)
        let out = String(decoding: try ds.serializeForSave(data), as: UTF8.self)
        #expect(out.contains(#""BucketIds":[],"FutureField":{"x":1}}]"#))
    }

    // TV: 06 §4.5 / TV-OWN-11 — the .aasched writer: indented 2 spaces, CRLF, nulls written, `"Key": value`
    @Test func aaschedBytes() throws {
        let t = ScheduleTemplate(id: UUID(netString: "5b0c8f5e-6a4e-4a7a-9f7e-2d1a1c7b9e11")!, name: "Jane Doe schedule")
        let e = ScheduleEntry(id: UUID(netString: "0f6d3c1a-2b3c-4d5e-8f90-1a2b3c4d5e6f")!, title: "Fire drill", kind: .procedure,
                              refId: UUID(netString: "7c9e6679-7425-40de-944b-e07fc1f90ae7")!)
        e.date = "2026-10-02"; e.time = "09:00"
        e.extra.set("Unknown", .bool(true))                              // never exported (includeExtra = false)
        t.entries = [e]
        t.createdUtc = NetDateTime(parsing: "2026-09-29T08:12:44.5123456Z")!
        let lines = ["{", #"  "Id": "5b0c8f5e-6a4e-4a7a-9f7e-2d1a1c7b9e11","#, #"  "Name": "Jane Doe schedule","#,
                     #"  "VesselId": null,"#, #"  "VesselName": "","#, #"  "Entries": ["#, "    {",
                     #"      "Id": "0f6d3c1a-2b3c-4d5e-8f90-1a2b3c4d5e6f","#, #"      "Title": "Fire drill","#,
                     #"      "Kind": 2,"#, #"      "RefId": "7c9e6679-7425-40de-944b-e07fc1f90ae7","#,
                     #"      "Date": "2026-10-02","#, #"      "Time": "09:00","#, #"      "EndDate": "","#,
                     #"      "EndTime": "","#, #"      "Done": false,"#, #"      "Notes": """#, "    }", "  ],",
                     #"  "CreatedUtc": "2026-09-29T08:12:44.5123456Z""#, "}"]
        let text = try JSONWriter.string(.object(t.toJSON(options: .aasched)), options: .aaschedIndented)
        #expect(text == lines.joined(separator: "\r\n"))
        #expect(JSONEncodeOptions.aasched.writeNulls && !JSONEncodeOptions.aasched.includeExtra)
    }
}
