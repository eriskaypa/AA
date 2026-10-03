// The kitchen-sink database (spec 01 GF.5.a "KS") built with the Swift models — the same objects, ids, strings and
// dates as mac/Tools/WinFixtures/Builders/KitchenSink.cs, so the A02 golden is reproduced byte-for-byte and the
// mac-out emitter writes the Mac's own serialisation of it (DATA-312). Keep the two builders in step.
import Foundation
@testable import AACore

/// GF.3.5 ids: G(n) = aaaaaaaa-0000-4000-8000-{n:D12}.
func GoldG(_ n: Int) -> UUID {
    UUID(netString: "aaaaaaaa-0000-4000-8000-" + String(format: "%012d", n))!
}

/// GF.3.5 dates (exact ticks and kind).
enum GoldDates {
    /// 2026-10-01 00:00 Unspecified.
    static var dU: NetDateTime { NetDateTime(year: 2026, month: 10, day: 1, kind: .unspecified) }
    /// 2026-10-01 08:30:15.1234567 Unspecified.
    static var dU7: NetDateTime { NetDateTime(year: 2026, month: 10, day: 1, hour: 8, minute: 30, second: 15, fractionTicks: 1_234_567, kind: .unspecified) }
    /// 2026-09-29 11:15:30.5 Local.
    static var dL: NetDateTime { NetDateTime(year: 2026, month: 9, day: 29, hour: 11, minute: 15, second: 30, fractionTicks: 5_000_000, kind: .local) }
    /// 2026-09-29 11:15:29.9876543 Local.
    static var dLM: NetDateTime { NetDateTime(year: 2026, month: 9, day: 29, hour: 11, minute: 15, second: 29, fractionTicks: 9_876_543, kind: .local) }
    /// 2026-09-29 08:15:30.1234560 Utc.
    static var dZ: NetDateTime { NetDateTime(year: 2026, month: 9, day: 29, hour: 8, minute: 15, second: 30, fractionTicks: 1_234_560, kind: .utc) }
    /// 2026-09-29 08:15:30 Utc.
    static var dZ0: NetDateTime { NetDateTime(year: 2026, month: 9, day: 29, hour: 8, minute: 15, second: 30, kind: .utc) }

    static func day(_ y: Int, _ m: Int, _ d: Int, _ kind: NetDateTime.Kind = .unspecified) -> NetDateTime {
        NetDateTime(year: y, month: m, day: d, kind: kind)
    }
}

@MainActor
enum GoldKitchenSink {
    static let lockHash = "V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk="
    static let lockSalt = "AAECAwQFBgcICQoLDA0ODw=="
    static let manualPath = "files/0123456789abcdef0123456789abcdef_Manual v2.pdf"

    static let equipmentXaml =
        "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" xml:space=\"preserve\" " +
        "TextAlignment=\"Left\" LineHeight=\"Auto\" IsHyphenationEnabled=\"False\" xml:lang=\"en-us\" " +
        "FlowDirection=\"LeftToRight\" NumberSubstitution.CultureSource=\"User\" NumberSubstitution.Substitution=\"AsCulture\" " +
        "FontFamily=\"Consolas\" FontStyle=\"Normal\" FontWeight=\"Normal\" FontStretch=\"Normal\" FontSize=\"14\" " +
        "Foreground=\"#FF1A1A1A\" Typography.StandardLigatures=\"True\" Typography.ContextualLigatures=\"True\" " +
        "Typography.DiscretionaryLigatures=\"False\" Typography.HistoricalLigatures=\"False\" Typography.AnnotationAlternates=\"0\" " +
        "Typography.ContextualAlternates=\"True\" Typography.HistoricalForms=\"False\" Typography.Kerning=\"True\" " +
        "Typography.CapitalSpacing=\"False\" Typography.CaseSensitiveForms=\"False\" Typography.StylisticSet1=\"False\" " +
        "Typography.Fraction=\"Normal\" Typography.SlashedZero=\"False\" Typography.MathematicalGreek=\"False\" " +
        "Typography.EastAsianExpertForms=\"False\" Typography.Variants=\"Normal\" Typography.Capitals=\"Normal\" " +
        "Typography.NumeralStyle=\"Normal\" Typography.NumeralAlignment=\"Normal\" Typography.EastAsianWidths=\"Normal\" " +
        "Typography.EastAsianLanguage=\"Normal\" Typography.StandardSwashes=\"0\" Typography.ContextualSwashes=\"0\" " +
        "Typography.StylisticAlternates=\"0\"><Paragraph><Run>Check oil &amp; filters \u{2192} W\u{00E4}rtsil\u{00E4} </Run>" +
        "<Run Background=\"#FFFFE699\">locked part</Run></Paragraph></Section>"

    static let sireBody =
        "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" xml:space=\"preserve\">" +
        "<Paragraph><Run>Edited body</Run></Paragraph></Section>"

    static func c(_ n: Int) -> Container { Container(id: GoldG(n)) }

    static func file(_ n: Int, _ name: String, _ path: String, _ kind: FileKind,
                     isLink: Bool = false, inPlace: Bool = false) -> FileItem {
        FileItem(id: GoldG(n), name: name, path: path, kind: kind, added: GoldDates.dL, isLink: isLink, linkInPlace: inPlace)
    }

    static func build() -> AppData {
        let d = AppData()

        // ---- Equipment G(1) ----
        let eqContainer = c(101)
        eqContainer.richTextXaml = equipmentXaml
        let manual = file(201, "Manual v2.pdf", manualPath, .document)
        manual.linkedItemIds = [GoldG(3)]
        eqContainer.files = [
            manual,
            file(203, "Daily log.xlsx", #"\\shipserver\ops\Daily log.xlsx"#, .document, inPlace: true),
            file(204, "Routine  (folder)", #"Z:\Routine"#, .other, inPlace: true),
            file(205, "IMO", "https://www.imo.org", .link, isLink: true),
            file(206, "deck.jpg", "files/00000000000000000000000000000206_deck.jpg", .image),
            file(207, "drill.mp4", "files/00000000000000000000000000000207_drill.mp4", .video),
        ]
        eqContainer.sharedWithContainerIds = [GoldG(103)]
        eqContainer.isLocked = true
        let pumpContainer = c(102)
        pumpContainer.files = [file(202, "pump.pdf", "files/00000000000000000000000000000202_pump.pdf", .document)]

        let eq = Equipment(id: GoldG(1), name: "Main Engine \u{2192} \u{2693} <ME>")
        eq.description = "Two-stroke & 'slow' \"speed\" +1"
        eq.container = eqContainer
        eq.groupId = GoldG(40)
        eq.lockHash = lockHash
        eq.lockSalt = lockSalt
        eq.lockHint = "the usual"
        eq.tags = ["engine", "ME"]
        eq.relatedIds = [GoldG(3)]
        eq.bucketIds = [GoldG(50), GoldG(51)]
        eq.procedureIds = [GoldG(4)]
        eq.taskIds = [GoldG(3)]
        eq.components = [Component(id: GoldG(2), name: "Fuel pump", notes: "check every 500 h", container: pumpContainer)]
        d.equipment = [eq]

        // ---- Task G(3) with nested subtasks ----
        let grandchild = TaskItem(id: GoldG(6), name: "Count heads")
        grandchild.container = c(106)
        grandchild.recurrence = .yearly
        grandchild.rangeStart = GoldDates.day(2026, 9, 28)
        let child = TaskItem(id: GoldG(5), name: "Muster")
        child.container = c(105)
        child.deadline = GoldDates.dU7
        child.status = .blocked
        child.subtasks = [grandchild]
        let task = TaskItem(id: GoldG(3), name: "Fire drill \u{1F600}")
        task.container = c(103)
        task.deadline = GoldDates.dU
        task.rangeStart = GoldDates.day(2026, 9, 27, .local)
        task.isJob = true
        task.durationMinutes = 90
        task.scheduledStart = GoldDates.dL
        task.recurrence = .monthly
        task.recurrenceSpawned = true
        task.isComplete = true                          // → Status Done via the setter
        task.subtasks = [child]
        d.tasks = [task]

        // ---- Procedure G(4) ----
        let step = ChecklistStep(id: GoldG(7), title: "Sample fuel")
        step.done = true
        step.deadline = GoldDates.dZ
        step.isJob = true
        step.durationMinutes = 15
        step.scheduledStart = GoldDates.dU7
        step.container = c(107)
        step.bucketIds = [GoldG(50)]
        step.taskIds = [GoldG(3)]
        step.equipmentIds = [GoldG(1)]
        let proc = Procedure(id: GoldG(4), name: "Bunkering")
        proc.container = c(104)
        proc.deadline = GoldDates.dL
        proc.recurrence = .weekly
        proc.status = .inProgress
        proc.isJob = true
        proc.durationMinutes = 120
        proc.scheduledStart = GoldDates.dZ0
        proc.steps = [step]
        d.procedures = [proc]

        // ---- Vessel G(8) ----
        let vessel = Vessel(id: GoldG(8), name: "Alpha")
        vessel.container = c(108)
        vessel.notificationsEnabled = false
        let card = QuickCard(id: GoldG(9), title: "Manuals")
        card.target = manualPath; card.isFolder = true; card.linkInPlace = true; card.icon = "\u{1F6DF}"
        card.color = "#80FF0000"; card.x = 12.5; card.y = -24; card.width = 333.25; card.height = 0.1
        let link = QuickCard(id: GoldG(30), title: "IMO")
        link.target = "https://www.imo.org"; link.isLink = true
        vessel.quickCards = [card, link]
        let job = ShipJob(jobNo: "ARA.22.3120")
        job.title = "Overhaul purifier"; job.workPlanNo = "WP-7"; job.status = "Execution"; job.classCode = "MC"
        job.category = "ROUTINE"; job.responsibleRank = "2E"; job.functionNo = "601.01"
        job.functionDescription = "Fuel oil purifier"; job.interval = "64,000 H"; job.dueStatus = "in Window"
        job.dueDate = "2026-10-15"; job.finishedDate = "2026-10-16"; job.lastDoneDate = "2024-03-01"
        job.overdueDays = -3; job.notify = true; job.isCompleted = true; job.completedDate = "2026-10-16"
        job.importedAt = "2026-09-29 14:05"
        vessel.jobs = [job]
        let call = PortCall(id: GoldG(10), portName: "Bonny")
        call.country = "Nigeria"; call.unLocode = "NGBON"; call.portFacility = "Bonny LNG Terminal"; call.pfNo = "NGBON-0001"
        call.arrivalDate = "2026-05-01"; call.arrivalTime = "08:00"; call.departureDate = "2026-05-03"
        call.departureTime = "17:30"; call.securityLevelPort = "1"; call.securityLevelVessel = "1"; call.sspFollowed = "YES"
        call.specialMeasures = "none"; call.importedAt = "2026-09-29 14:05"
        vessel.portCalls = [call]
        d.vessels = [vessel]

        // ---- Group G(40) ----
        d.groups = [ItemGroup(id: GoldG(40), kind: .vessel, name: "Engine room", expanded: false)]

        // ---- Crew G(11) ----
        let crew = CrewMember(id: GoldG(11))
        crew.scheduleVesselId = GoldG(8)
        crew.employeeId = "E-1001"; crew.firstName = "Jos\u{00E9}"; crew.middleName = "\u{03A9}mega"; crew.lastName = "Cruz"
        crew.nationality = "Philippines"; crew.dateOfBirth = "1985-03-04"; crew.placeOfBirth = "Manila"; crew.gender = "Male"
        crew.height = "175"; crew.eyesColor = "Brown"; crew.hairColor = "Black"; crew.userType = "Officer"
        crew.rank = "Chief Officer"; crew.rankCode = "CO"; crew.signedOnOff = "Off"; crew.company = "Fixture Shipping"
        crew.vessel = "Alpha"; crew.signOnDate = "2026-06-01"; crew.signOnPort = "SGSIN"; crew.signOnPortRaw = "Singapore"
        crew.signOffDate = "2026-12-01"; crew.signOffPort = "NLRTM"; crew.signOffPortRaw = "Rotterdam"
        crew.passportNumber = "P1234567"; crew.passportExpiry = "2030-01-01"; crew.passportIssued = "2020-01-02"
        crew.seamansBookNumber = "SB-765"; crew.seamansBookExpiry = "2029-05-05"; crew.seamansBookIssued = "2019-05-06"
        crew.cocNumber = "COC-42"; crew.cocExpiry = "2028-08-08"; crew.cocIssue = "2023-08-09"
        crew.healthCertExpiry = "2027-02-02"; crew.nokFirstName = "Maria"; crew.nokLastName = "Cruz"
        crew.nokRelationship = "Spouse"; crew.rawNationality = "FILIPINO"; crew.importedAt = "2026-09-29 14:05"
        crew.sourceFile = "compas-fixture.xlsx"
        let fam = ChecklistStep(id: GoldG(12), title: "Familiarisation")
        fam.container = c(112)
        crew.checklist = [fam]
        crew.schedule = [
            ScheduleEntry(id: GoldG(13), title: "Joining briefing", kind: .note, date: "2026-06-01", time: "09:00", notes: "bring documents"),
            ScheduleEntry(id: GoldG(14), title: "Fire drill", kind: .task, refId: GoldG(3), date: "2026-10-01", done: true),
            ScheduleEntry(id: GoldG(15), title: "Bunkering", kind: .procedure, refId: GoldG(4), date: "2026-10-02", endDate: "2026-10-03", endTime: "18:00"),
            ScheduleEntry(id: GoldG(16), title: "Main engine rounds", kind: .equipment, refId: GoldG(1), date: "2026-10-04"),
        ]
        crew.flags = [
            CrewReviewFlag(severity: .info, field: "Rank", message: "Mapped CO \u{2192} Chief Officer"),
            CrewReviewFlag(severity: .warning, field: "SignOffPort", message: "Guessed UN/LOCODE from 'Rotterdam'"),
            CrewReviewFlag(severity: .error, field: "PassportNumber", message: "Mandatory field missing in a fixture row"),
        ]
        d.crew = [crew]

        // ---- Log ----
        d.log = [LogEntry(timestampUtc: GoldDates.dZ0, action: "Added", kind: "Task", name: "Fire drill \u{1F600}", detail: "fixture")]

        // ---- Saved lists, list groups, buckets ----
        let tpl = ChecklistTemplate(id: GoldG(20), name: "Daily rounds", createdUtc: GoldDates.dZ, groupId: GoldG(21))
        tpl.items = [ChecklistTemplateItem(title: "Check oil", durationMinutes: 45, isJob: true, container: c(120))]
        d.checklistTemplates = [tpl, ChecklistTemplate(id: GoldG(29), name: "Orphan list", createdUtc: GoldDates.dZ, groupId: GoldG(99))]
        d.listGroups = [ListGroup(id: GoldG(21), name: "Engine", createdUtc: GoldDates.dZ)]
        d.quickBuckets = [QuickBucket(id: GoldG(50), name: "Deck", category: "Location", createdUtc: GoldDates.dZ),
                          QuickBucket(id: GoldG(51), name: "Bosun", category: "", createdUtc: GoldDates.dZ)]

        // ---- Ports, schedule templates ----
        let port = PortRecord(id: GoldG(22), name: "Bonny", country: "Nigeria", unLocode: "NGBON")
        port.visits = [PortVisit(vesselName: "Alpha", vesselId: GoldG(8), arrivalDate: "2026-05-01", arrivalTime: "08:00",
                                 departureDate: "2026-05-03", departureTime: "17:30", importedAt: "2026-09-29 14:05")]
        d.ports = [port]
        let sched = ScheduleTemplate(id: GoldG(23), name: "Port rota", vesselId: GoldG(8), vesselName: "Alpha", createdUtc: GoldDates.dZ)
        sched.entries = [ScheduleEntry(id: GoldG(24), title: "Gangway watch", kind: .note, date: "2026-05-01", time: "08:00",
                                       endDate: "2026-05-01", endTime: "12:00", notes: "bring radio")]
        d.scheduleTemplates = [sched]

        // ---- Trash ----
        let trashed = Vessel(id: GoldG(26), name: "Old tug")
        trashed.container = c(126)
        d.trash = [TrashedItem(id: GoldG(25), itemType: "Vessel", itemId: GoldG(26), batchId: GoldG(27), name: "Old tug",
                               kindLabel: "Vessel", deletedUtc: GoldDates.dZ0, payloadJson: TrashPayload.encode(trashed))]

        // ---- SIRE ----
        d.sire.questionStatuses["1.1.1"] = "InProgress"
        d.sire.questionStatuses["2.1.1"] = "Checked"
        d.sire.questionStatuses["11.1.2"] = "NotApplicable"
        d.sire.bookmarks = ["1.1.1"]
        d.sire.forExport = ["2.1.1"]
        d.sire.tasks = [SireTask(id: GoldG(28), questionNumber: "1.1.1", text: "Check the certificate", isCompleted: true, createdAt: GoldDates.dL)]
        d.sire.questionBodies["1.1.1"] = sireBody

        // ---- Ui (every key non-null) ----
        let ui = d.ui
        ui.windowLeft = -1280.5; ui.windowTop = 0; ui.windowWidth = 1600; ui.windowHeight = 900.25
        ui.windowState = "Maximized"; ui.selectedMainTabIndex = 3
        ui.selectedEquipmentId = GoldG(1); ui.selectedTaskId = GoldG(3); ui.selectedProcedureId = GoldG(4); ui.selectedVesselId = GoldG(8)
        ui.calendarSelectedDate = GoldDates.dU; ui.calendarViewMode = "Week"; ui.calendarFontScale = 13.5; ui.showShortcutBar = false
        ui.quickViewPinIds = [GoldG(3), GoldG(4)]
        ui.tabColors["TabTasks"] = "#FF00AA00"
        ui.tabOrder = ["TabTasks", "TabEquipment"]
        ui.dueWindowWidth = 420; ui.dueWindowHeight = 640.5; ui.mapFocusedItemId = GoldG(8)
        ui.sortAZ["Task"] = true; ui.sortAZ["savedlists"] = false
        ui.groupExpanded["Vessel|Engine room"] = false
        ui.crewSortMode = "Name"
        ui.crewTableColumns = ["Rank", "Name", "SignOff"]
        ui.crewTableShownColumns = ["Rank", "Name"]
        ui.crewTableDateFormat = "DayMonthYear"; ui.crewTableDateSeparator = "/"
        ui.lastDigestDate = "2026-09-29"
        ui.extra = JSONObject([("NewPref", .bool(true))])

        // ---- Root ----
        d.lastModified = GoldDates.dLM
        d.schemaVersion = 1
        d.extra = JSONObject([("FutureThing", .object(JSONObject([("a", .array([.number(JSONNumber(1)), .number(JSONNumber(2))]))])))])
        return d
    }

    /// A04: one instance of every type with only ids and dates fixed.
    static func defaults() -> AppData {
        let d = AppData()
        let eq = Equipment(id: GoldG(1))
        eq.container = c(101)
        eq.container.files = [FileItem(id: GoldG(201), added: GoldDates.dL)]
        eq.components = [Component(id: GoldG(2), container: c(102))]
        d.equipment = [eq]
        let t = TaskItem(id: GoldG(3))
        t.container = c(103)
        let sub = TaskItem(id: GoldG(5))
        sub.container = c(105)
        t.subtasks = [sub]
        d.tasks = [t]
        let p = Procedure(id: GoldG(4))
        p.container = c(104)
        let s = ChecklistStep(id: GoldG(7))
        s.container = c(107)
        p.steps = [s]
        d.procedures = [p]
        let v = Vessel(id: GoldG(8))
        v.container = c(108)
        v.quickCards = [QuickCard(id: GoldG(9))]
        v.jobs = [ShipJob()]
        v.portCalls = [PortCall(id: GoldG(10))]
        d.vessels = [v]
        d.groups = [ItemGroup(id: GoldG(40))]
        let crew = CrewMember(id: GoldG(11))
        let cs = ChecklistStep(id: GoldG(12))
        cs.container = c(112)
        crew.checklist = [cs]
        crew.schedule = [ScheduleEntry(id: GoldG(13))]
        crew.flags = [CrewReviewFlag()]
        d.crew = [crew]
        d.log = [LogEntry(timestampUtc: GoldDates.dZ0)]
        let tpl = ChecklistTemplate(id: GoldG(20), createdUtc: GoldDates.dZ)
        tpl.items = [ChecklistTemplateItem(container: c(120))]
        d.checklistTemplates = [tpl]
        d.listGroups = [ListGroup(id: GoldG(21), createdUtc: GoldDates.dZ)]
        d.quickBuckets = [QuickBucket(id: GoldG(50), createdUtc: GoldDates.dZ)]
        let port = PortRecord(id: GoldG(22))
        port.visits = [PortVisit()]
        d.ports = [port]
        let st = ScheduleTemplate(id: GoldG(23), createdUtc: GoldDates.dZ)
        st.entries = [ScheduleEntry(id: GoldG(24))]
        d.scheduleTemplates = [st]
        d.trash = [TrashedItem(id: GoldG(25), deletedUtc: GoldDates.dZ0)]
        d.sire.tasks = [SireTask(id: GoldG(28), createdAt: GoldDates.dL)]
        return d
    }

    /// `KitchenSink.Task(n, name)`: a task with container G(1000 + n).
    static func task(_ n: Int, _ name: String) -> TaskItem {
        let t = TaskItem(id: GoldG(n), name: name)
        t.container = c(1000 + n)
        return t
    }

    static func withTasks(_ tasks: [TaskItem]) -> AppData {
        let d = AppData()
        d.tasks = tasks
        return d
    }
}
