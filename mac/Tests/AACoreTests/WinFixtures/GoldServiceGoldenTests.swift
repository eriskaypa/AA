// Family (e) services — Swift reproductions of E01–E16 (spec 01 GF.5.e, DATA-319). Inputs are AA-format JSON loaded
// with the Mac codec (so family (a) must pass first) plus inline parameters; outputs follow the GF.4.7 shapes. The
// DateResolver / CrewConverter (W-CREW) and checklist-XLSX (W-PDF) cases have no public Mac API to call: they are
// registered as pending and listed in Docs/Requests/W-GOLD.md.
import Foundation
import Testing
@testable import AACore

/// GF.4.8 `#row:` — a list row wrapping a model (the shape BatchDelete.Unwrap reflects on).
@MainActor
final class GoldRow: SvcModelRow {
    let item: AnyObject
    init(_ item: AnyObject) { self.item = item }
    var svcRowModel: AnyObject? { item }
}

@MainActor
enum GoldServiceFamily {
    typealias Ctx = GoldCaseContext

    // MARK: Inputs

    static func appData(_ ctx: Ctx, key: String) throws -> AppData {
        guard let rel = ctx.inlineString(key) else { throw GoldReproError.missingInput(key) }
        let root = try JSONParser.parse(try ctx.index.data(rel))
        return try ModelCodec.decodeAppData(root, context: ctx.decodeContext)
    }

    static func store(_ data: AppData, _ ctx: Ctx) -> AppStore {
        let s = AppStore(dataStore: ctx.makeDataStore(), data: data, clock: GoldZoneClock(zone: ctx.zone))
        s.suspendSaving = true
        return s
    }

    static func goldenArray(_ ctx: Ctx) throws -> [JSONObject] {
        (try JSONParser.parse(try GoldJSONFamily.golden(ctx, role: "result")).arrayValue ?? []).compactMap(\.objectValue)
    }

    static func goldenObject(_ ctx: Ctx) throws -> JSONObject {
        try JSONParser.parse(try GoldJSONFamily.golden(ctx, role: "result")).objectValue ?? JSONObject()
    }

    // MARK: E01

    static func nodeJSON(_ n: DiffNode) -> JSONValue {
        let change: String
        switch n.change {
        case .added: change = "Added"
        case .removed: change = "Removed"
        case .changed: change = "Changed"
        }
        return GoldDotNet.obj([("Change", .string(change)), ("Text", .string(n.text)), ("Children", .array(n.children.map(nodeJSON)))])
    }

    static func diffJSON(_ r: DiffResult) -> JSONValue {
        GoldDotNet.obj([("Added", GoldDotNet.int(r.added)), ("Changed", GoldDotNet.int(r.changed)), ("Removed", GoldDotNet.int(r.removed)),
                        ("HasChanges", .bool(!r.roots.isEmpty)), ("Roots", .array(r.roots.map(nodeJSON)))])
    }

    static let diffCase = GoldReproducer { ctx in
        if ctx.fixtureCase.id == "E01.14" {
            let a = try appData(ctx, key: "a"), b = try appData(ctx, key: "b")
            return ["result": .json(GoldDotNet.obj([("forward", diffJSON(DataDiff.compare(current: a, incoming: b))),
                                                    ("backward", diffJSON(DataDiff.compare(current: b, incoming: a)))]))]
        }
        if ctx.fixtureCase.id.hasPrefix("E01.19") {
            return ["result": .json(.array(try goldenArray(ctx).map { row in
                let input = row["input"]?.stringValue ?? ""
                return GoldDotNet.obj([("input", .string(input)), ("snip", .string(DataDiff.snip(input)))])
            }))]
        }
        let cur = try appData(ctx, key: "current"), inc = try appData(ctx, key: "incoming")
        return ["result": .json(diffJSON(DataDiff.compare(current: cur, incoming: inc)))]
    }

    // MARK: E02

    static let search = GoldReproducer { ctx in
        if ctx.fixtureCase.id == "E02.7" {
            return ["result": .json(.array(try goldenArray(ctx).map { row in
                let text = row["text"]?.stringValue ?? "", index = row["index"]?.numberValue?.intValue ?? 0
                let length = row["length"]?.numberValue?.intValue ?? 0
                let (snippet, start) = SearchService.makeSnippet(text: text, matchIndex: index, matchLength: length)
                return GoldDotNet.obj([("text", .string(text)), ("index", GoldDotNet.int(index)), ("length", GoldDotNet.int(length)),
                                       ("snippet", .string(snippet)), ("start", GoldDotNet.int(start))])
            }))]
        }
        let data = try appData(ctx, key: "data")
        let s = store(data, ctx)
        let query = ctx.inlineString("query") ?? ""
        let locked = Set((ctx.inline("lockedOwnerIds")?.arrayValue ?? []).compactMap { $0.stringValue.flatMap(UUID.init(netString:)) })
        let docs = SearchService.makeDocuments(store: s) { locked.contains($0.id) }
        let hits = SearchService.search(docs, query: query)
        let names = Dictionary(s.allItems().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return ["result": .json(GoldDotNet.obj([
            ("query", .string(query)), ("maxResults", GoldDotNet.int(ctx.inline("maxResults")?.numberValue?.intValue ?? 500)),
            ("lockedOwnerIds", .array((ctx.inline("lockedOwnerIds")?.arrayValue ?? []))),
            ("hits", .array(hits.map { h in
                GoldDotNet.obj([("OwnerId", .string(h.ownerID.netString)), ("OwnerName", GoldDotNet.str(names[h.ownerID])),
                                ("Kind", .string(h.kind.rawValue)), ("Where", .string(h.whereLabel)), ("Snippet", .string(h.snippet)),
                                ("MatchStart", GoldDotNet.int(h.matchStart)), ("MatchLength", GoldDotNet.int(h.matchLength)),
                                ("ChildId", GoldDotNet.guid(h.childID))])
            })),
        ]))]
    }

    // MARK: E03 / E04 / E05

    static let plainText = GoldReproducer { ctx in
        ["result": .json(.array(try goldenArray(ctx).map { row in
            let input = row["input"]?.stringValue
            let x = input ?? ""
            return GoldDotNet.obj([("input", GoldDotNet.str(input)), ("search", .string(XamlPlainText.searchText(x))),
                                   ("diff", .string(XamlPlainText.diffText(x)))])
        }))]
    }

    static let reminders = GoldReproducer { ctx in
        let s = store(try appData(ctx, key: "data"), ctx)
        let todayText = ctx.inlineString("today") ?? "2026-09-29"
        let r = ReminderService.compute(store: s, today: CivilDate(iso: todayText)!)
        return ["result": .json(GoldDotNet.obj([
            ("today", .string(todayText)), ("Overdue", GoldDotNet.int(r.overdue)), ("DueToday", GoldDotNet.int(r.dueToday)),
            ("DueWeek", GoldDotNet.int(r.dueWeek)), ("Total", GoldDotNet.int(r.total)), ("Any", .bool(r.any)),
            ("Headline", .string(r.headline())),
        ]))]
    }

    static func date(_ v: JSONValue?) -> NetDateTime? {
        guard let o = v?.objectValue, let t = o["ticks"]?.numberValue?.int64Value else { return nil }
        let kind: NetDateTime.Kind = switch o["kind"]?.stringValue {
        case "Utc": .utc
        case "Local": .local
        default: .unspecified
        }
        return NetDateTime(ticks: t, kind: kind)
    }

    static let workRange = GoldReproducer { ctx in
        ["result": .json(.array(try goldenArray(ctx).map { row in
            let s = date(row["start"]), d = date(row["deadline"]), edited = row["editedStart"]?.boolValue ?? false
            let (os, od) = WorkRange.coerce(start: s, deadline: d, editedStart: edited)
            return GoldDotNet.obj([("start", GoldDotNet.dateNode(s)), ("deadline", GoldDotNet.dateNode(d)), ("editedStart", .bool(edited)),
                                   ("outStart", GoldDotNet.dateNode(os)), ("outDeadline", GoldDotNet.dateNode(od))])
        }))]
    }

    // MARK: E06 / E07

    /// A completable item from a row spec (the C# `Build`).
    static func build(_ spec: JSONObject) -> AnyObject? {
        switch spec["kind"]?.stringValue {
        case "task":
            let t = GoldKitchenSink.task(3, "task")
            if let s = spec["status"]?.numberValue?.intValue { t.status = WorkStatus(rawValue: s) }
            if let c = spec["isComplete"]?.boolValue { t.isComplete = c }
            if let rs = spec["rangeStart"]?.stringValue { t.rangeStart = GoldDotNet.parseSpecDate(rs) }
            if let dl = spec["deadline"]?.stringValue { t.deadline = GoldDotNet.parseSpecDate(dl) }
            return t
        case "procedure":
            let p = Procedure(id: GoldG(4), name: "procedure")
            p.container = Container(id: GoldG(1004))
            if let s = spec["status"]?.numberValue?.intValue { p.status = WorkStatus(rawValue: s) }
            if let dl = spec["deadline"]?.stringValue { p.deadline = GoldDotNet.parseSpecDate(dl) }
            return p
        case "step":
            let s = ChecklistStep(id: GoldG(7), title: "step")
            if let d = spec["done"]?.boolValue { s.done = d }
            if let dl = spec["deadline"]?.stringValue { s.deadline = GoldDotNet.parseSpecDate(dl) }
            return s
        case "equipment": return Equipment(id: GoldG(1), name: "equipment")
        case "literal": return (spec["value"]?.stringValue ?? "") as NSString
        default: return nil
        }
    }

    static func state(_ o: AnyObject?) -> JSONValue {
        switch o {
        case let t as TaskItem:
            return GoldDotNet.obj([("IsComplete", .bool(t.isComplete)), ("Status", GoldDotNet.int(t.status.rawValue)),
                                   ("RangeStart", GoldDotNet.dateNode(t.rangeStart)), ("Deadline", GoldDotNet.dateNode(t.deadline))])
        case let p as Procedure:
            return GoldDotNet.obj([("Status", GoldDotNet.int(p.status.rawValue)), ("Deadline", GoldDotNet.dateNode(p.deadline))])
        case let s as ChecklistStep:
            return GoldDotNet.obj([("Done", .bool(s.done)), ("Deadline", GoldDotNet.dateNode(s.deadline))])
        case nil:
            return GoldDotNet.obj([("null", .bool(true))])
        default:
            return GoldDotNet.obj([("other", .string(o is NSString ? "String" : String(describing: type(of: o!))))])
        }
    }

    static let batchDone = GoldReproducer { ctx in
        ["result": .json(.array(try goldenArray(ctx).map { row in
            let specs = (row["items"]?.arrayValue ?? []).compactMap(\.objectValue)
            let objs = specs.map(build)
            let done = row["done"]?.boolValue ?? false
            let returned: JSONValue
            switch row["op"]?.stringValue {
            case "setDone": returned = .bool(BatchDone.setDone(objs.first ?? nil, done: done))
            case "setDoneAll": returned = GoldDotNet.int(BatchDone.setDoneAll(objs.compactMap { $0 }, done: done))
            default:
                if let t = objs.first as? TaskItem { t.status = .inProgress; returned = .bool(true) } else { returned = .bool(false) }
            }
            return GoldDotNet.obj([("id", row["id"] ?? .null), ("items", .array(specs.map(JSONValue.object))),
                                   ("op", row["op"] ?? .null), ("done", .bool(done)), ("returned", returned),
                                   ("after", .array(objs.map(state)))])
        }))]
    }

    static let batchDeadline = GoldReproducer { ctx in
        ["result": .json(.array(try goldenArray(ctx).map { row in
            let spec = row["item"]?.objectValue ?? JSONObject()
            let o = build(spec)
            let dateText = row["date"]?.stringValue
            let ret = BatchDeadline.setDeadline(o, date: dateText.flatMap(GoldDotNet.parseSpecDate))
            return GoldDotNet.obj([("id", row["id"] ?? .null), ("item", .object(spec)), ("date", GoldDotNet.str(dateText)),
                                   ("returned", .bool(ret)), ("after", state(o))])
        }))]
    }

    // MARK: E08

    /// GF.4.8 selection-reference grammar.
    static func resolve(_ ref: String, in d: AppData) -> AnyObject? {
        if ref == "null" { return nil }
        if ref.hasPrefix("#literal:") { return String(ref.dropFirst(9)) as NSString }
        if ref.hasPrefix("#row:") { return resolve(String(ref.dropFirst(5)), in: d).map { GoldRow($0) } }
        var cur: AnyObject?
        for part in ref.split(separator: ".") {
            guard let open = part.firstIndex(of: "["), let i = Int(part[part.index(after: open)..<part.index(before: part.endIndex)]) else { return nil }
            let name = String(part[..<open])
            let list: [AnyObject]
            switch (cur, name) {
            case (nil, "Equipment"): list = d.equipment
            case (nil, "Tasks"): list = d.tasks
            case (nil, "Procedures"): list = d.procedures
            case (nil, "Vessels"): list = d.vessels
            case (nil, "Crew"): list = d.crew
            case (nil, "ChecklistTemplates"): list = d.checklistTemplates
            case (let t as TaskItem, "Subtasks"): list = t.subtasks
            case (let p as Procedure, "Steps"): list = p.steps
            case (let e as Equipment, "Components"): list = e.components
            case (let c as CrewMember, "Checklist"): list = c.checklist
            case (let t as ChecklistTemplate, "Items"): list = t.items
            default: return nil
            }
            guard i < list.count else { return nil }
            cur = list[i]
        }
        return cur
    }

    static func summaryJSON(_ s: BatchDelete.Description) -> JSONValue {
        GoldDotNet.obj([("Equipment", GoldDotNet.int(s.equipment)), ("Tasks", GoldDotNet.int(s.tasks)),
                        ("Procedures", GoldDotNet.int(s.procedures)), ("Vessels", GoldDotNet.int(s.vessels)),
                        ("Locked", GoldDotNet.int(s.locked)), ("Descendants", GoldDotNet.int(s.descendants)),
                        ("WithAttachments", GoldDotNet.int(s.withAttachments)),
                        ("LinkedFromElsewhere", GoldDotNet.int(s.linkedFromElsewhere)), ("Total", GoldDotNet.int(s.total)),
                        ("IsEmpty", .bool(s.isEmpty)), ("KindBreakdown", .string(s.kindBreakdown()))])
    }

    static let batchDelete = GoldReproducer { ctx in
        if ctx.fixtureCase.id == "E08.9" {
            return ["result": .json(.array(try goldenArray(ctx).map { row in
                let n = { (k: String) in row[k]?.numberValue?.intValue ?? 0 }
                let s = BatchDelete.Description(equipment: n("Equipment"), tasks: n("Tasks"), procedures: n("Procedures"), vessels: n("Vessels"))
                return GoldDotNet.obj([("Equipment", GoldDotNet.int(n("Equipment"))), ("Tasks", GoldDotNet.int(n("Tasks"))),
                                       ("Procedures", GoldDotNet.int(n("Procedures"))), ("Vessels", GoldDotNet.int(n("Vessels"))),
                                       ("KindBreakdown", .string(s.kindBreakdown()))])
            }))]
        }
        if ctx.fixtureCase.id == "E08.8" { return [:] }
        let data = try appData(ctx, key: "data")
        let s = store(data, ctx)
        let locks = ItemLockService()
        let selection = (ctx.inline("selection")?.arrayValue ?? []).compactMap(\.stringValue).compactMap { resolve($0, in: data) }
        let summary = BatchDelete.describe(selection, store: s, isGated: { locks.isGated($0) })
        let trashed = BatchDelete.trashAll(selection, store: s, isGated: { locks.isGated($0) })
        return ["result": .json(GoldDotNet.obj([("summary", summaryJSON(summary)), ("trashed", GoldDotNet.int(trashed))])),
                "bytes": .bytes(try ctx.makeDataStore().serializeForSave(s.data))]
    }

    // MARK: E10

    static let parseDate = GoldReproducer { ctx in
        let golden = try goldenObject(ctx)
        let today = CivilDate(iso: ctx.inlineString("today") ?? "2026-09-29")!
        let rows = (golden["parseDate"]?.arrayValue ?? []).compactMap(\.objectValue).map { row -> JSONValue in
            let input = row["input"]?.stringValue
            return GoldDotNet.obj([("input", GoldDotNet.str(input)), ("value", GoldDotNet.dateNode(CrewMember.parseDate(input)))])
        }
        let contract = (golden["contract"]?.arrayValue ?? []).compactMap(\.objectValue).map { row -> JSONValue in
            let m = CrewMember(id: GoldG(11))
            m.signOffDate = row["signOff"]?.stringValue ?? ""
            return GoldDotNet.obj([("signOff", .string(m.signOffDate)), ("days", GoldDotNet.int(m.daysUntilSignOff(today: today))),
                                   ("status", .string(m.contractStatus(on: today).name))])
        }
        return ["result": .json(GoldDotNet.obj([("tz", GoldDotNet.str(ctx.fixtureCase.tz)), ("parseDate", .array(rows)),
                                                ("contract", .array(contract))]))]
    }

    // MARK: E12

    static let savedListOrder = GoldReproducer { ctx in
        if ctx.fixtureCase.id == "E12.14" {
            let data = try appData(ctx, key: "data")
            @MainActor func entries(_ e: [(template: ChecklistTemplate, group: String?)]) -> JSONValue {
                .array(e.map { GoldDotNet.obj([("group", GoldDotNet.str($0.group)), ("template", .string($0.template.name))]) })
            }
            return ["result": .json(GoldDotNet.obj([
                ("allEntries", entries(SavedListOrder.allEntries(data))),
                ("groupEntries.alpha", entries(SavedListOrder.groupEntries(data, groupID: GoldG(901)) ?? [])),
                ("groupEntries.unnamed", entries(SavedListOrder.groupEntries(data, groupID: GoldG(903)) ?? [])),
                ("groupEntries.ungrouped", entries(SavedListOrder.groupEntries(data, groupID: nil) ?? [])),
            ]))]
        }
        let groups: [String: UUID?] = ["g": GoldG(901), "h": GoldG(902), "\u{00B7}": nil]
        var all: [ChecklistTemplate] = []
        var byName: [String: ChecklistTemplate] = [:]
        var n = 910
        for tok in (ctx.inlineString("all") ?? "").split(separator: " ") {
            let parts = tok.split(separator: ":").map(String.init)
            let t = ChecklistTemplate(id: GoldG(n), name: parts[0], createdUtc: GoldDates.dZ, groupId: groups[parts[1]] ?? nil)
            n += 1
            all.append(t); byName[parts[0]] = t
        }
        let picks = (ctx.inlineString("picks") ?? "").split(separator: " ").compactMap { byName[String($0)] }
        let ret: Bool
        if ctx.inlineString("call") == "nudge" {
            ret = SavedListOrder.nudge(&all, picks: picks, up: ctx.inline("up")?.boolValue ?? false)
        } else {
            ret = SavedListOrder.moveTo(&all, picks: picks, targetInGroup: ctx.inline("target")?.numberValue?.intValue ?? 0)
        }
        var perGroup: [(String, JSONValue)] = []
        for key in ["g", "h", "\u{00B7}"] {
            let gid = groups[key] ?? nil
            let names = all.filter { $0.groupId == gid }.map { JSONValue.string($0.name) }
            if !names.isEmpty { perGroup.append((key, .array(names))) }
        }
        return ["result": .json(GoldDotNet.obj([("returned", .bool(ret)), ("flat", .array(all.map { .string($0.name) })),
                                                ("groups", .object(JSONObject(perGroup)))]))]
    }

    // MARK: E14 / E15 / E16

    static let xlsxWriter = GoldReproducer { ctx in
        let headers = (ctx.inline("headers")?.arrayValue ?? []).compactMap(\.stringValue)
        let rows = (ctx.inline("rows")?.arrayValue ?? []).map { r in (r.arrayValue ?? []).map { $0.stringValue ?? "" } }
        let url = ctx.folder.file("crew.xlsx")
        try XlsxWriter.write(to: url, sheetName: ctx.inlineString("sheetName") ?? "", headers: headers, rows: rows)
        return ["xlsx": .zip(try Data(contentsOf: url))]
    }

    static let casing = GoldReproducer(requires: .wPersist) { ctx in
        let golden = try goldenObject(ctx)
        let strings = (golden["strings"]?.arrayValue ?? []).compactMap { $0.objectValue?["input"]?.stringValue }.map { c -> JSONValue in
            let call = PortCall(portName: c); call.arrivalDate = "2026-05-01"
            let visit = PortVisit(vesselName: c, arrivalDate: "2026-05-01", arrivalTime: "08:00")
            return GoldDotNet.obj([("input", .string(c)), ("lower", .string(NetText.toLowerInvariant(c))),
                                   ("upper", .string(NetText.toUpperInvariant(c))),
                                   ("portKey", .string(PortRecord(unLocode: c).key)),
                                   ("portKeyByName", .string(PortRecord(name: c, country: "Nigeria").key)),
                                   ("portCallKey", .string(call.key)), ("visitKey", .string(visit.visitKey))])
        }
        let crew = (golden["crewKey"]?.arrayValue ?? []).compactMap(\.objectValue).map { row -> JSONValue in
            let m = CrewMember(id: GoldG(11))
            m.employeeId = row["employeeId"]?.stringValue ?? ""; m.firstName = row["first"]?.stringValue ?? ""
            m.lastName = row["last"]?.stringValue ?? ""
            return GoldDotNet.obj([("employeeId", .string(m.employeeId)), ("first", .string(m.firstName)), ("last", .string(m.lastName)),
                                   ("key", .string(m.key))])
        }
        let ds = ctx.makeDataStore()
        let classify = (golden["classify"]?.arrayValue ?? []).compactMap { $0.objectValue?["path"]?.stringValue }.map {
            GoldDotNet.obj([("path", .string($0)), ("kind", GoldDotNet.int(AttachmentStore.classify(path: $0).rawValue))])
        }
        let resolve = (golden["resolve"]?.arrayValue ?? []).compactMap { $0.objectValue?["stored"]?.stringValue }.map {
            GoldDotNet.obj([("stored", .string($0)), ("resolved", .string(AttachmentStore.resolveFilePath(ds, stored: $0)))])
        }
        return ["result": .json(GoldDotNet.obj([("strings", .array(strings)), ("crewKey", .array(crew)),
                                                ("classify", .array(classify)), ("resolve", .array(resolve))]))]
    }

    static let computed = GoldReproducer { ctx in
        if ctx.fixtureCase.id == "E16.th" { return [:] }
        if let tz = ctx.fixtureCase.tz, ctx.fixtureCase.id != "E16" {
            // Display strings in a zone: the models format through TimeZone.current, which a test must not change
            // (suites run in parallel), so the same formulas run with the case's zone explicitly.
            let zone = TimeZone(identifier: tz) ?? ctx.zone
            let deleted = GoldDates.dZ0.toLocalTime(zone: zone).format(.isoMinute)
            let deletedZ = GoldDates.dZ.toLocalTime(zone: zone).format(.isoMinute)
            return ["result": .json(GoldDotNet.obj([
                ("tz", .string(tz)), ("DeletedLocal", .string(deleted)),
                ("Display", .string("Old tug   \u{00B7}   Vessel   \u{00B7}   deleted \(deleted)")),
                ("DisplayUnnamed", .string("(unnamed)   \u{00B7}   Task   \u{00B7}   deleted \(deletedZ)")),
                ("TimeUtc", .string(LogEntry(timestampUtc: GoldDates.dZ0).timeUtc)),
                ("TimeLocal", .string(GoldDates.dZ0.toLocalTime(zone: zone).format(.isoSecond))),
                ("WrittenLocal", .string(GoldDates.dZ.toLocalTime(zone: zone).format(.isoMinute))),
            ]))]
        }
        let golden = try goldenObject(ctx)
        let ranges = (golden["ranges"]?.arrayValue ?? []).compactMap(\.objectValue).map { row -> JSONValue in
            let t = GoldKitchenSink.task(3, "t")
            let s = row["start"]?.stringValue, d = row["deadline"]?.stringValue
            t.rangeStart = s.flatMap(GoldDotNet.parseSpecDate)
            t.deadline = d.flatMap(GoldDotNet.parseSpecDate)
            let days = (row["CoversDay"]?.objectValue?.keys ?? []).map { day -> (String, JSONValue) in
                (day, .bool(GoldDotNet.parseSpecDate(day).map { t.coversDay($0.civilDate) } ?? false))
            }
            return GoldDotNet.obj([("start", GoldDotNet.str(s)), ("deadline", GoldDotNet.str(d)), ("WhenText", .string(t.whenText)),
                                   ("HasRange", .bool(t.hasRange)), ("RangeFirst", GoldDotNet.dateNode(t.rangeFirst)),
                                   ("CoversDay", .object(JSONObject(days)))])
        }
        let today = CivilDate(year: 2026, month: 9, day: 29)!
        let jobs = (golden["daysUntilDue"]?.arrayValue ?? []).compactMap(\.objectValue).map { row -> JSONValue in
            let j = ShipJob(); j.dueDate = row["DueDate"]?.stringValue ?? ""
            return GoldDotNet.obj([("DueDate", .string(j.dueDate)), ("DaysUntilDue", GoldDotNet.int(j.daysUntilDue(today: today)))])
        }
        let sire = SireState()
        for (k, v) in [("a", "InProgress"), ("b", "2"), ("c", "checked"), ("d", "Bogus"), ("e", "Checked")] { sire.questionStatuses[k] = v }
        let status = ["a", "b", "c", "d", "e", "missing"].map { ($0, JSONValue.string(sire.status(for: $0).rawValue)) }
        let counts = SireQuestionStatus.allCases.map { ($0.rawValue, GoldDotNet.int(sire.count(of: $0))) }
        sire.toggleBookmark("1.1.1"); sire.toggleBookmark("2.1.1"); sire.toggleBookmark("1.1.1")
        sire.toggleForExport("3.1"); sire.toggleForExport("3.1"); sire.toggleForExport("4.1")
        let order = ["1.10", "1.2", "1.1.1", "11.1", "2", "a.1", "1..2"].enumerated()
            .sorted { l, r in
                let c = SireState.compareQuestionNumbers(l.element, r.element)
                return c == .orderedSame ? l.offset < r.offset : c == .orderedAscending
            }.map(\.element)
        return ["result": .json(GoldDotNet.obj([
            ("ranges", .array(ranges)), ("daysUntilDue", .array(jobs)), ("sireStatus", .object(JSONObject(status))),
            ("sireCounts", .object(JSONObject(counts))), ("bookmarks", GoldDotNet.strings(sire.bookmarks)),
            ("forExport", GoldDotNet.strings(sire.forExport)), ("questionOrder", GoldDotNet.strings(order)),
        ]))]
    }

    // MARK: The table

    static let table = GoldReproducerTable(entries: [
        "E01": diffCase, "E01.7": GoldReproducer { _ in [:] },
        "E02": search, "E03": plainText, "E04": reminders, "E05": workRange, "E06": batchDone, "E07": batchDeadline,
        "E08": batchDelete,
        "E09": .pending(.wCrew, "reproducer not written yet: entry point CrewDateResolver (public, AACore/Crew); REQ-W-GOLD-01 deferred to Stage V"),
        "E10": parseDate,
        "E11": .pending(.wCrew, "reproducer not written yet: entry point CrewConverter(sourceFile:now:today:zone:use1904:); REQ-W-GOLD-01 deferred to Stage V"),
        "E12": savedListOrder,
        "E13": .pending(.wPdf, "reproducer not written yet: entry point PdfChecklistXlsx (public, AACore/Export); REQ-W-GOLD-02 deferred to Stage V"),
        "E14": xlsxWriter, "E15": casing,
        "E15b": .pending(.wCrew, "reproducer not written yet: COMPAS code mapping via CrewConverter; REQ-W-GOLD-01 deferred to Stage V"),
        "E16": computed,
    ])
}

@MainActor
@Suite("WinFixtures — services (DATA-319)", .tags(.goldWinFixtures),
       .enabled(if: GoldFixtureIndex.winfixtures.available, GoldFixtureIndex.absentMessage))
struct GoldServiceGoldenTests {
    @Test("GF.5.e case", arguments: GoldFixtureIndex.winfixtures.cases(family: "services"))
    func serviceCase(_ c: GoldFixtureCase) async {
        await GoldCaseRunner.run(c, index: .winfixtures, table: GoldServiceFamily.table)
    }
}

@MainActor
@Suite("WinFixtures harness — service reproducers against the spec tables", .tags(.goldWinFixtures))
struct GoldServiceReproducerTests {
    func run(_ family: GoldReproducerTable, _ root: GoldSyntheticRoot, _ record: String) async throws -> [String] {
        let index = try root.manifest([record])
        let c = try #require(index.manifest?.cases.first)
        let ctx = GoldCaseContext(index: index, fixtureCase: c)
        let actual = try await #require(family.reproducer(for: c)).run(ctx)
        return GoldCaseRunner.compareAll(c, actual: actual, ctx: ctx).problems
    }

    @Test("E04 on the 02 §7.8 data set reproduces 2 overdue · 2 due today · 3 due this week")
    func e04() async throws {
        let r = GoldSyntheticRoot()
        let d = AppData()
        func day(_ m: Int, _ dd: Int) -> NetDateTime { GoldDates.day(2026, m, dd) }
        let t1 = GoldKitchenSink.task(31, "T1"); t1.deadline = day(9, 28)
        let s1 = GoldKitchenSink.task(32, "S1"); s1.deadline = day(9, 29); t1.subtasks = [s1]
        let t2 = GoldKitchenSink.task(33, "T2"); t2.deadline = day(10, 6)
        let t3 = GoldKitchenSink.task(34, "T3"); t3.deadline = day(10, 7)
        let t4 = GoldKitchenSink.task(35, "T4"); t4.deadline = day(9, 20); t4.isComplete = true
        let t5 = GoldKitchenSink.task(36, "T5"); t5.rangeStart = day(9, 25); t5.deadline = day(10, 2)
        d.tasks = [t1, t2, t3, t4, t5]
        let p1 = Procedure(id: GoldG(41), name: "P1"); p1.status = .inProgress; p1.deadline = day(9, 29)
        let p1s = ChecklistStep(id: GoldG(42), title: "P1 step"); p1s.deadline = day(9, 30); p1.steps = [p1s]
        let p2 = Procedure(id: GoldG(43), name: "P2"); p2.status = .done; p2.deadline = day(9, 1)
        let p2s = ChecklistStep(id: GoldG(44), title: "P2 step"); p2s.deadline = day(9, 2); p2.steps = [p2s]
        d.procedures = [p1, p2]
        let crew = CrewMember(id: GoldG(11))
        let cs = ChecklistStep(id: GoldG(45), title: "crew step"); cs.deadline = day(9, 29); cs.done = true
        crew.checklist = [cs]; d.crew = [crew]
        try r.write("inputs/E04.1.data.input.json", try JSONWriter.data(ModelCodec.encodeAppData(d)))
        try r.write("services/E04.1.reminders.golden.json",
                    #"{"today":"2026-09-29","Overdue":2,"DueToday":2,"DueWeek":3,"Total":7,"Any":true,"Headline":"2 overdue  ·  2 due today  ·  3 due this week"}"#)
        let problems = try await run(GoldServiceFamily.table, r,
            #"{"id":"E04.1","family":"services","title":"reminders","compare":"json-semantic","inputs":{"data":"inputs/E04.1.data.input.json","today":"2026-09-29"},"outputs":[{"role":"result","file":"services/E04.1.reminders.golden.json"}]}"#)
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test("E02.1 on the 02 §7.7 corpus reproduces the FUEL table")
    func e02() async throws {
        let r = GoldSyntheticRoot()
        let d = AppData()
        let me = Equipment(id: GoldG(1), name: "Main Engine"); me.container = Container(id: GoldG(1001)); me.tags = ["engine", "ME"]
        me.components = [Component(id: GoldG(2), name: "Fuel pump", notes: "check every 500 h", container: Container(id: GoldG(1002)))]
        let t = GoldKitchenSink.task(3, "Replace the fuel filter on the main engine")
        let sub = GoldKitchenSink.task(5, "Drain water")
        sub.container.richTextXaml = "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" xml:space=\"preserve\"><Paragraph><Run>Open the drain cock</Run></Paragraph></Section>"
        t.subtasks = [sub]
        let p = Procedure(id: GoldG(4), name: "Bunkering"); p.container = Container(id: GoldG(1004))
        let st = ChecklistStep(id: GoldG(7), title: "Sample fuel"); st.container = Container(id: GoldG(1007)); p.steps = [st]
        let v = Vessel(id: GoldG(8), name: "Aurora"); v.container = Container(id: GoldG(1008))
        d.equipment = [me]; d.tasks = [t]; d.procedures = [p]; d.vessels = [v]
        try r.write("inputs/E02.1.data.input.json", try JSONWriter.data(ModelCodec.encodeAppData(d)))
        let g1 = GoldG(1).netString, g3 = GoldG(3).netString, g4 = GoldG(4).netString, g2 = GoldG(2).netString, g7 = GoldG(7).netString
        try r.write("services/E02.1.search.golden.json", """
        {"query":"FUEL","maxResults":500,"lockedOwnerIds":[],"hits":[
         {"OwnerId":"\(g1)","OwnerName":"Main Engine","Kind":"Component","Where":"Component › Name","Snippet":"Fuel pump","MatchStart":0,"MatchLength":4,"ChildId":"\(g2)"},
         {"OwnerId":"\(g3)","OwnerName":"Replace the fuel filter on the main engine","Kind":"Item","Where":"Name","Snippet":"Replace the fuel filter on the main engine","MatchStart":12,"MatchLength":4,"ChildId":null},
         {"OwnerId":"\(g4)","OwnerName":"Bunkering","Kind":"Step","Where":"Step › Title","Snippet":"Sample fuel","MatchStart":7,"MatchLength":4,"ChildId":"\(g7)"}]}
        """)
        let problems = try await run(GoldServiceFamily.table, r,
            #"{"id":"E02.1","family":"services","title":"search","compare":"json-semantic","inputs":{"data":"inputs/E02.1.data.input.json","query":"FUEL","maxResults":500,"lockedOwnerIds":[]},"outputs":[{"role":"result","file":"services/E02.1.search.golden.json"}]}"#)
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test("E12 T-ORD rows (02 §7.9) reproduce")
    func e12() async throws {
        let r = GoldSyntheticRoot()
        try r.write("services/E12.9.order.golden.json", #"{"returned":true,"flat":["B","D","A","C"],"groups":{"g":["B","D","A","C"]}}"#)
        let problems = try await run(GoldServiceFamily.table, r,
            #"{"id":"E12.9","family":"services","title":"T-ORD-9","compare":"json-semantic","inputs":{"all":"A:g B:g C:g D:g","call":"moveTo","picks":"A C","target":4,"up":false},"outputs":[{"role":"result","file":"services/E12.9.order.golden.json"}]}"#)
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test("every services case group of the C# catalogue has a reproducer (or a documented pending entry)")
    func covered() {
        for id in ["E01.1", "E01.7", "E01.14", "E01.19a", "E01.19b", "E02.1", "E02.7", "E02.17", "E03", "E04.8", "E05", "E06",
                   "E07", "E08.1", "E08.8", "E08.9", "E09", "E10.6", "E11", "E12.1", "E12.2a", "E12.13b", "E12.14", "E13.X1",
                   "E13.X4w", "E14.3", "E14.1w", "E15", "E15b", "E16", "E16.3", "E16.th"] {
            let c = GoldFixtureCase(id: id, family: "services", title: "", platform: .any, tz: nil, normative: .must, compare: .bytes,
                                    dependsOnToday: false, today: nil, inputs: JSONObject(), outputs: [], macExpectation: .same, settles: [])
            #expect(GoldServiceFamily.table.reproducer(for: c) != nil, "no reproducer for \(id)")
        }
    }
}
