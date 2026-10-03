// Family (f) extension families — Swift reproductions of X01–X06, SHOULD (spec 01 GF.5.f, DATA-320). X01 runs the
// repository scenarios of 02 §7.1/§7.4/§7.5/§7.12/§7.13 through F2's AppStore, X02/X03 the saved-list and schedule
// services; X04/X05 (W-SIRE) and X06 (W-CREW) need APIs private to those owners and are registered as pending.
import Foundation
import Testing
@testable import AACore

@MainActor
enum GoldExtFamily {
    typealias Ctx = GoldCaseContext
    static let ns = "xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" xml:space=\"preserve\""
    static func xaml(_ run: String) -> String { "<Section \(ns)><Paragraph><Run>\(run)</Run></Paragraph></Section>" }

    // The `Corpora` builders: every object with container G(1000 + n).
    static func task(_ n: Int, _ name: String) -> TaskItem { GoldKitchenSink.task(n, name) }
    static func equip(_ n: Int, _ name: String) -> Equipment { let e = Equipment(id: GoldG(n), name: name); e.container = Container(id: GoldG(1000 + n)); return e }
    static func proc(_ n: Int, _ name: String) -> Procedure { let p = Procedure(id: GoldG(n), name: name); p.container = Container(id: GoldG(1000 + n)); return p }
    static func ship(_ n: Int, _ name: String) -> Vessel { let v = Vessel(id: GoldG(n), name: name); v.container = Container(id: GoldG(1000 + n)); return v }
    static func step(_ n: Int, _ title: String) -> ChecklistStep { let s = ChecklistStep(id: GoldG(n), title: title); s.container = Container(id: GoldG(1000 + n)); return s }
    static func file(_ n: Int, _ name: String, _ path: String) -> FileItem { FileItem(id: GoldG(n), name: name, path: path, kind: .document, added: GoldDates.dL) }

    /// A store whose autosave never fires during the test, but whose dirty flag is real.
    static func store(_ d: AppData, _ ctx: Ctx) -> AppStore {
        let s = AppStore(dataStore: ctx.makeDataStore(), data: d, clock: GoldZoneClock(zone: ctx.zone))
        s.debounceInterval = .seconds(86_400)
        return s
    }

    static func ids(_ u: [UUID]) -> JSONValue { .array(u.map { .string($0.netString) }) }
    static func names(_ items: [HierarchyItem]) -> JSONValue { .array(items.map { .string($0.name) }) }

    // MARK: X01.rel

    static let relations = GoldReproducer { ctx in
        var o: [(String, JSONValue)] = []
        do {
            let a = task(3, "A"), b = task(5, "B")
            let d = AppData(); d.tasks = [a, b]
            let s = store(d, ctx)
            s.addRelation(a, b); s.addRelation(a, b)
            o.append(("T-REL-1", GoldDotNet.obj([("A", ids(a.relatedIds)), ("B", ids(b.relatedIds))])))
            s.addRelation(a, a)
            o.append(("T-REL-2", ids(a.relatedIds)))
            s.removeRelation(a, b)
            o.append(("T-REL-3", GoldDotNet.obj([("A", ids(a.relatedIds)), ("B", ids(b.relatedIds))])))
        }
        do {
            let e = equip(1, "E"), v = ship(8, "V"), p = proc(4, "P"), t = task(3, "T")
            e.relatedIds = [v.id]; e.procedureIds = [p.id]; e.taskIds = [t.id, v.id]
            let d = AppData(); d.equipment = [e]; d.vessels = [v]; d.procedures = [p]; d.tasks = [t]
            o.append(("T-REL-4", names(store(d, ctx).relatedItems(of: e))))
        }
        do {
            let p = proc(4, "P"), s = step(7, "s"); s.taskIds = [GoldG(3)]; p.steps = [s]
            let d = AppData(); d.procedures = [p]; d.tasks = [task(3, "T")]
            o.append(("T-REL-5", names(store(d, ctx).relatedItems(of: p))))
        }
        do {
            let t = task(3, "T"), e = equip(1, "E"); e.taskIds = [t.id]
            let p = proc(4, "P"), s = step(7, "s"); s.taskIds = [t.id]; p.steps = [s]
            let x = ship(8, "X"); x.relatedIds = [t.id]
            let d = AppData(); d.equipment = [e]; d.tasks = [t]; d.procedures = [p]; d.vessels = [x]
            let st = store(d, ctx)
            o.append(("T-REL-6", GoldDotNet.obj([("referencedBy", names(st.referencedBy(t))), ("related", names(st.relatedItems(of: t)))])))
        }
        do {
            let e = equip(1, "E"), p = proc(4, "P"); e.procedureIds = [p.id]
            let d = AppData(); d.equipment = [e]; d.procedures = [p]
            let st = store(d, ctx)
            st.trash(p)
            o.append(("T-REL-7", GoldDotNet.obj([("label", .string(st.label(for: GoldG(4)))), ("related", names(st.relatedItems(of: e)))])))
        }
        do {
            let d = AppData(); d.tasks = [task(3, "Pump")]
            o.append(("T-REL-8", .string(store(d, ctx).label(for: GoldG(3)))))
        }
        do {
            let d = AppData(); d.equipment = [equip(3, "Equipment Z")]; d.tasks = [task(3, "Task Z")]
            o.append(("T-REL-10", GoldDotNet.str(store(d, ctx).item(id: GoldG(3))?.name)))
        }
        do {
            let t = task(3, "T"); t.isJob = true
            let s = task(5, "S"); s.isJob = true; s.subtasks = [task(6, "SS")]; t.subtasks = [s]
            let p = proc(4, "P"), s1 = step(71, "s1"); s1.isJob = true; p.steps = [s1, step(72, "s2")]
            let crew = CrewMember(id: GoldG(11)), cs = step(12, "cs"); cs.isJob = true; crew.checklist = [cs]
            let d = AppData(); d.tasks = [t]; d.procedures = [p]; d.crew = [crew]
            o.append(("T-REL-11", .array(store(d, ctx).allJobs().map { .string($0.jobName) })))
        }
        return ["result": .json(.object(JSONObject(o)))]
    }

    // MARK: X01.rec

    static let recurrence = GoldReproducer { ctx in
        func next(_ d: NetDateTime, _ r: RecurrenceKind) -> JSONValue { GoldDotNet.dateNode(AppStore.nextOccurrence(from: d, r)) }
        var o: [(String, JSONValue)] = [
            ("T-REC-1", next(GoldDates.day(2026, 1, 31), .monthly)),
            ("T-REC-2", next(GoldDates.day(2024, 2, 29), .yearly)),
            ("T-REC-3", .array([next(GoldDates.day(2026, 12, 31), .daily), next(GoldDates.day(2026, 9, 29), .weekly),
                                next(GoldDates.day(2026, 9, 29), .none)])),
            ("T-REC-4", next(NetDateTime(year: 2026, month: 3, day: 31, hour: 9, minute: 30, kind: .unspecified), .monthly)),
        ]
        let src = task(3, "Fire drill"); src.recurrence = .monthly; src.deadline = GoldDates.day(2026, 1, 31); src.rangeStart = GoldDates.day(2026, 1, 29)
        let s = task(5, "S"); s.deadline = GoldDates.day(2026, 1, 30); s.rangeStart = GoldDates.day(2026, 1, 28); s.isComplete = true
        let u = task(6, "U"); u.status = .inProgress
        src.subtasks = [s, u]; src.container.files = [file(201, "f.pdf", "files/f.pdf")]
        src.isComplete = true
        let same = task(13, "Same-day range"); same.recurrence = .weekly; same.rangeStart = GoldDates.day(2026, 10, 5); same.deadline = GoldDates.day(2026, 10, 5); same.isComplete = true
        let spawned = task(14, "Already spawned"); spawned.recurrence = .daily; spawned.isComplete = true; spawned.recurrenceSpawned = true
        let open = task(15, "Not complete"); open.recurrence = .daily
        let parent = task(16, "Parent"), rsub = task(17, "Recurring subtask"); rsub.recurrence = .daily; rsub.isComplete = true; parent.subtasks = [rsub]
        let p = proc(4, "Weekly checks"); p.recurrence = .weekly; p.deadline = GoldDates.day(2026, 9, 28); p.status = .done
        let st1 = step(71, "step1"); st1.done = true; st1.deadline = GoldDates.day(2026, 9, 27); st1.taskIds = [GoldG(3)]
        p.steps = [st1, step(72, "step2")]
        let d = AppData(); d.tasks = [src, same, spawned, open, parent]; d.procedures = [p]
        let st = store(d, ctx)
        o.append(("first", .bool(st.reconcileRecurrences(today: ctx.today))))
        o.append(("second", .bool(st.reconcileRecurrences(today: ctx.today))))
        return ["result": .json(.object(JSONObject(o))), "bytes": .bytes(try ctx.makeDataStore().serializeForSave(st.data))]
    }

    // MARK: X01.tr

    static let trash = GoldReproducer { ctx in
        var o: [(String, JSONValue)] = []
        @MainActor func logLine(_ d: AppData) -> JSONValue {
            guard let l = d.log.last else { return .null }
            return .string("\(l.action) / \(l.kind) / \(l.name) / \(l.detail)")
        }
        do {
            let t = task(3, "T"), e = equip(1, "E")
            t.relatedIds = [e.id]; e.relatedIds = [t.id]; e.taskIds = [t.id]
            let d = AppData(); d.tasks = [t]; d.equipment = [e]
            let s = store(d, ctx)
            let ti = s.trash(t)!
            o.append(("T-TR-1", GoldDotNet.obj([("ItemType", .string(ti.itemType)), ("ItemId", .string(ti.itemId.netString)),
                                                ("KindLabel", .string(ti.kindLabel)), ("BatchIdEmpty", .bool(ti.batchId == .netEmpty)),
                                                ("E.RelatedIds", ids(e.relatedIds)), ("E.TaskIds", ids(e.taskIds)),
                                                ("tasks", GoldDotNet.int(d.tasks.count)), ("log", logLine(d))])))
            let back = s.restore(ti)
            o.append(("T-TR-2", GoldDotNet.obj([("returned", GoldDotNet.str(back?.rawValue)), ("tasks", GoldDotNet.int(s.data.tasks.count)),
                                                ("trash", GoldDotNet.int(s.data.trash.count)), ("related", names(s.relatedItems(of: e))),
                                                ("log", logLine(s.data))])))
        }
        do {
            let s = store(AppData(), ctx)
            let bad = TrashedItem(itemType: "Task", itemId: GoldG(3), deletedUtc: .utcNow(), payloadJson: "{")
            let widget = TrashedItem(itemType: "Widget", itemId: GoldG(5), deletedUtc: .utcNow(), payloadJson: "{}")
            s.data.trash = [bad, widget]
            o.append(("T-TR-4", GoldDotNet.obj([("returned", GoldDotNet.str(s.restore(bad)?.rawValue)),
                                                ("kept", .bool(s.data.trash.contains { $0.id == bad.id }))])))
            o.append(("T-TR-5", GoldDotNet.str(s.restore(widget)?.rawValue)))
        }
        do {
            let a = task(3, "A"), b = task(5, "B"), c = task(6, "C")
            let d = AppData(); d.tasks = [a, b, c]
            let s = store(d, ctx)
            let n = s.trashItems([a, b, c])
            let batches = Set(s.data.trash.map(\.batchId))
            o.append(("T-TR-6", GoldDotNet.obj([("returned", GoldDotNet.int(n)), ("entries", GoldDotNet.int(s.data.trash.count)),
                                                ("sharedBatch", .bool(batches.count == 1 && batches.first != .netEmpty))])))
            o.append(("T-TR-7.pending", GoldDotNet.int(s.pendingUndoCount())))
            let types = s.undoLastDelete()
            o.append(("T-TR-7", GoldDotNet.obj([("types", .array(types.map { .string($0.rawValue) })), ("tasks", names(s.data.tasks)),
                                                ("trash", GoldDotNet.int(s.data.trash.count))])))
            o.append(("T-TR-10", .array(s.undoLastDelete().map { .string($0.rawValue) })))
        }
        do {
            let e = equip(1, "E"); e.relatedIds = [GoldG(90), GoldG(91)]
            let d = AppData(); d.equipment = [e]
            let now = NetDateTime.utcNow(clock: GoldZoneClock(zone: ctx.zone))
            d.trash = [TrashedItem(itemType: "Task", itemId: GoldG(90), deletedUtc: now.addingDays(-91), payloadJson: "{}"),
                       TrashedItem(itemType: "Task", itemId: GoldG(91), deletedUtc: now.addingDays(-89), payloadJson: "{}")]
            let s = store(d, ctx)
            s.pruneTrash()
            o.append(("T-TR-11/13", GoldDotNet.obj([("trash", GoldDotNet.int(s.data.trash.count)), ("E.RelatedIds", ids(e.relatedIds)),
                                                    ("dirty", .bool(s.isDirty))])))
        }
        do {
            let d = AppData()
            let now = NetDateTime.utcNow(clock: GoldZoneClock(zone: ctx.zone))
            d.trash = (0..<200).map { i in
                TrashedItem(itemType: "Task", itemId: GoldG(2000 + i), deletedUtc: now.addingTicks(Int64(-300 + i) * NetDateTime.ticksPerMinute), payloadJson: "{}")
            }
            let t = task(3, "new"); d.tasks = [t]
            let s = store(d, ctx)
            s.trash(t)
            o.append(("T-TR-12", GoldDotNet.obj([("trash", GoldDotNet.int(s.data.trash.count)),
                                                 ("oldestGone", .bool(s.data.trash.allSatisfy { $0.itemId != GoldG(2000) }))])))
        }
        do {
            let m = CrewMember(id: GoldG(11)); m.firstName = "Jan"; m.lastName = "Kowalski"
            let blank = CrewMember(id: GoldG(12))
            let d = AppData(); d.crew = [m, blank]
            let s = store(d, ctx)
            let ti = s.trash(m), tb = s.trash(blank)
            o.append(("T-TR-14", GoldDotNet.obj([("Name", .string(ti.name)), ("KindLabel", .string(ti.kindLabel)), ("ItemType", .string(ti.itemType)),
                                                 ("restored", GoldDotNet.str(s.restore(ti)?.rawValue)), ("crew", GoldDotNet.int(s.data.crew.count))])))
            o.append(("T-TR-15", GoldDotNet.obj([("Name", .string(tb.name)),
                                                 ("Display", .string(tb.display.components(separatedBy: "   \u{00B7}   ").first ?? ""))])))
        }
        do {
            let e = equip(1, "E"), t = task(3, "T"); e.taskIds = [t.id]
            let d = AppData(); d.equipment = [e]; d.tasks = [t]
            let s = store(d, ctx)
            let ti = s.trash(t)!
            s.purge(ti)
            let empty = store(AppData(), ctx)
            empty.emptyTrash()
            o.append(("T-TR-16", GoldDotNet.obj([("E.TaskIds", ids(e.taskIds)), ("trash", GoldDotNet.int(s.data.trash.count)),
                                                 ("emptyOnEmptyDirty", .bool(empty.isDirty))])))
        }
        return ["result": .json(.object(JSONObject(o)))]
    }

    // MARK: X01.log

    static let logGroups = GoldReproducer { ctx in
        let s = store(AppData(), ctx)
        s.logAdded(kind: "Task", name: "  Pump  ")
        s.logRemoved(kind: "Task", name: "   ")
        let first = s.data.log[0], second = s.data.log[1]
        for i in 0..<10_000 { s.logAdded(kind: "Task", name: "n\(i)") }
        let g = s.createGroup(kind: .task, name: "  ")
        s.renameGroup(g, to: "")
        let groupName = g.name
        let e = equip(1, "E"), t = task(3, "T"); e.groupId = g.id; t.groupId = g.id
        s.data.equipment = [e]; s.data.tasks = [t]
        s.deleteGroup(g)
        return ["result": .json(GoldDotNet.obj([
            ("T-LOG-1", GoldDotNet.obj([("Name", .string(first.name)), ("Detail", .string(first.detail)), ("Action", .string(first.action)),
                                        ("Kind", .string(GoldDotNet.kindName(first.timestampUtc.kind)))])),
            ("T-LOG-2", .string(second.name)),
            ("T-LOG-3", GoldDotNet.obj([("count", GoldDotNet.int(s.data.log.count)), ("firstName", .string(s.data.log[0].name))])),
            ("T-LOG-5", .string(LogEntry(timestampUtc: NetDateTime(year: 2026, month: 9, day: 29, hour: 8, minute: 15, second: 30, kind: .utc)).timeUtc)),
            ("T-GRP-1", GoldDotNet.obj([("Name", .string(groupName)), ("Kind", GoldDotNet.int(g.kind.rawValue))])),
            ("T-GRP-3", GoldDotNet.obj([("E.GroupId", GoldDotNet.guid(e.groupId)), ("T.GroupId", GoldDotNet.guid(t.groupId)),
                                        ("groups", GoldDotNet.int(s.data.groups.count))])),
        ]))]
    }

    // MARK: X02

    static let templates = GoldReproducer { ctx in
        let opts = ctx.encodeOptions
        let st = step(7, "Check oil")
        st.durationMinutes = 15; st.isJob = true; st.done = true; st.deadline = GoldDates.day(2026, 10, 5); st.taskIds = [GoldG(3)]
        st.container.richTextXaml = xaml("X")
        let f1 = file(201, "f1.pdf", "files/f1.pdf"); f1.linkedItemIds = [GoldG(1)]; st.container.files = [f1]
        let tpl = ChecklistTemplateService.captureFromSteps(name: "  Daily rounds ", steps: [st])
        let s1 = task(5, "S1"); s1.description = "d"; s1.subtasks = [task(6, "S1a")]
        let tpl2 = ChecklistTemplateService.captureFromSubtasks(name: "L", subtasks: [s1])
        var target = [step(70, "s0")]
        let two = ChecklistTemplateService.captureFromSteps(name: "two", steps: [step(71, "n1"), step(72, "n2")])
        let applied = ChecklistTemplateService.applyToSteps(two, steps: &target, replace: false)
        var subs = [task(80, "x"), task(81, "y")]
        let appliedSubs = ChecklistTemplateService.applyToSubtasks(two, subtasks: &subs, replace: true)
        let locked = Container(id: GoldG(150), richTextXaml: "enc:QUJD", isLocked: true)
        let cloneLocked = ChecklistTemplateService.cloneContainer(locked)
        let cloneNull = ChecklistTemplateService.cloneContainer(nil)
        let item = ChecklistTemplateService.itemToTask(tpl.items[0])
        return ["result": .json(GoldDotNet.obj([
            ("T-TPL-1", .object(tpl.toJSON(options: opts))),
            ("T-TPL-2", .object(tpl2.toJSON(options: opts))),
            ("T-TPL-3", GoldDotNet.obj([("returned", GoldDotNet.int(applied)), ("titles", GoldDotNet.strings(target.map(\.title))),
                                        ("done", .array(target.map { .bool($0.done) }))])),
            ("T-TPL-4", GoldDotNet.obj([("returned", GoldDotNet.int(appliedSubs)), ("names", GoldDotNet.strings(subs.map(\.name))),
                                        ("status", .array(subs.map { GoldDotNet.int($0.status.rawValue) }))])),
            ("T-TPL-6", .object(item.toJSON(options: opts))),
            ("T-TPL-8", .object(cloneNull.toJSON(options: opts))),
            ("T-TPL-9", .object(cloneLocked.toJSON(options: opts))),
        ]))]
    }

    // MARK: X03

    static let schedule = GoldReproducer { ctx in
        let t = ScheduleTemplate(id: GoldG(23), name: "Caf\u{00E9} rota", vesselId: GoldG(8), vesselName: "Alpha", createdUtc: GoldDates.dZ)
        t.entries = [ScheduleEntry(id: GoldG(24), title: "Watch", kind: .task, refId: GoldG(3), date: "2026-10-01", time: "08:00", notes: "\u{00E9}"),
                     ScheduleEntry(id: GoldG(25), title: "Free", date: "2026-10-02")]
        let exported = try ScheduleService.exportJSON(t)
        let imported = try ScheduleService.importJSON(try GoldJSONFamily.golden(ctx, role: "export"))
        let null: JSONValue
        do {
            _ = try ScheduleService.importJSON(Data("null".utf8))
            null = GoldDotNet.obj([("threw", .bool(false))])
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            null = GoldDotNet.obj([("exception", GoldDotNet.obj([("message", .string(message)), ("aaAuthored", .bool(true))]))])
        }
        return ["export": .bytes(exported),
                "import": .bytes(try JSONWriter.data(.object(imported.toJSON(options: ctx.encodeOptions)))),
                "null": .json(null)]
    }

    static let table = GoldReproducerTable(entries: [
        "X01.rel": relations, "X01.purge": GoldReproducer { _ in [:] },  // DECISIONS 02 Q-3 divergence (F2's tests)
        "X01.rec": recurrence, "X01.recToday": GoldReproducer { _ in [:] }, "X01.tr": trash,
        "X01.log": logGroups, "X02": templates, "X03": schedule,
        "X04": .pending(.wSire, "reproducer not written yet: entry point SireExport.modes / build(mode:all:session:…); REQ-W-GOLD-03 deferred to Stage V"),
        "X05": .pending(.wSire, "reproducer not written yet: entry points SireTaskIdentifier.identifyAllTasks / SireTagExtractor; REQ-W-GOLD-03 deferred to Stage V"),
        "X06": .pending(.wCrew, "reproducer not written yet: entry point CrewCompasReader.read(url:) + CrewCompasRow.get; REQ-W-GOLD-01 deferred to Stage V"),
    ])
}

@MainActor
@Suite("WinFixtures — extension families (DATA-320, SHOULD)", .tags(.goldWinFixtures, .goldShould),
       .enabled(if: GoldFixtureIndex.winfixtures.available, GoldFixtureIndex.absentMessage))
struct GoldExtGoldenTests {
    @Test("GF.5.f case", arguments: GoldFixtureIndex.winfixtures.cases(family: "ext"))
    func extCase(_ c: GoldFixtureCase) async {
        await GoldCaseRunner.run(c, index: .winfixtures, table: GoldExtFamily.table)
    }
}

@MainActor
@Suite("WinFixtures harness — extension reproducers", .tags(.goldWinFixtures))
struct GoldExtReproducerTests {
    @Test("every ext case of the C# catalogue resolves to a reproducer")
    func covered() {
        for id in ["X01.rel", "X01.purge", "X01.rec", "X01.recToday", "X01.tr", "X01.log", "X02", "X03", "X03w", "X04.print-checklist", "X05", "X06"] {
            let c = GoldFixtureCase(id: id, family: "ext", title: "", platform: .any, tz: nil, normative: .should, compare: .bytes,
                                    dependsOnToday: false, today: nil, inputs: JSONObject(), outputs: [], macExpectation: .same, settles: [])
            #expect(GoldExtFamily.table.reproducer(for: c) != nil, "no reproducer for \(id)")
        }
    }

    @Test("X01.rel reproduces the 02 §7.1 expectations stated in the spec")
    func relations() async throws {
        let r = GoldSyntheticRoot()
        let index = try r.manifest([#"{"id":"X01.rel","family":"ext","title":"relations","compare":"json-semantic","outputs":[{"role":"result","file":"ext/X01.rel.relations.golden.json"}]}"#])
        let c = try #require(index.manifest?.cases.first)
        let actual = try await GoldExtFamily.relations.run(GoldCaseContext(index: index, fixtureCase: c))
        guard case .json(let v)? = actual["result"], let o = v.objectValue else { Issue.record("no result"); return }
        let g3 = GoldG(3).netString, g5 = GoldG(5).netString
        #expect(o["T-REL-1"] == GoldDotNet.obj([("A", .array([.string(g5)])), ("B", .array([.string(g3)]))]))
        #expect(o["T-REL-3"] == GoldDotNet.obj([("A", .array([])), ("B", .array([]))]))
        #expect(o["T-REL-4"] == GoldDotNet.strings(["V", "P", "T"]))
        #expect(o["T-REL-5"] == .array([]))
        #expect(o["T-REL-6"]?.objectValue?["referencedBy"] == GoldDotNet.strings(["E", "P", "X"]))
        #expect(o["T-REL-7"]?.objectValue?["label"] == .string("(missing)"))
        #expect(o["T-REL-8"] == .string("[Task] Pump"))
        #expect(o["T-REL-10"] == .string("Equipment Z"))
        #expect(o["T-REL-11"] == GoldDotNet.strings(["T", "S", "s1", "cs"]))
    }
}
