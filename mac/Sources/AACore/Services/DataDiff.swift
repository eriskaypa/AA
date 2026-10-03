// Spec: 08 §3.7 (exact algorithm), QUICK-194/195, 01 §3.15, DATA-102/103, §7.8; 08 §7.7 (T-DF-*); OC-13 (count-aware
//       file keys, never crash — 01 §8 D-10 / 08 Q-8 P2; link order = first occurrence in collection order);
//       DECISIONS 01 Q-3 ("Other data": crew, saved lists, ports, SIRE — additive, Mac only); DECISIONS 08 OQ-10
//       (status/recurrence lines use `.friendlyLabel`).
import Foundation

public struct DiffNode: Sendable, Identifiable, Hashable {
    public enum Change: Int, Sendable { case added, removed, changed }
    public var id: UUID
    public var change: Change
    public var text: String
    public var children: [DiffNode]

    public init(id: UUID = UUID(), change: Change, text: String, children: [DiffNode] = []) {
        self.id = id; self.change = change; self.text = text; self.children = children
    }
}

public struct DiffResult: Sendable {
    public var roots: [DiffNode]
    public var added: Int
    public var removed: Int
    public var changed: Int
    public var hasChanges: Bool { added + removed + changed > 0 }

    public init(roots: [DiffNode] = [], added: Int = 0, removed: Int = 0, changed: Int = 0) {
        self.roots = roots; self.added = added; self.removed = removed; self.changed = changed
    }
}

/// Runs on the main actor (it walks models); callers show `AAProgressOverlay` when it is slow.
@MainActor public enum DataDiff {
    /// 08 §3.7 / 01 §3.15: top-level items (Equipment, Tasks, Procedures, Vessels) matched by Id. Added items list
    /// their content, removed items likewise, matched items list field / file / child differences; roots ordered
    /// Added → Changed → Removed, then by text (OrdinalIgnoreCase, stable). Counts are top-level only.
    public static func compare(current: AppData, incoming: AppData) -> DiffResult {
        let names = itemNames(current, incoming)
        let cur = SvcOrderedIndex(items(current), id: \.id)
        let inc = SvcOrderedIndex(items(incoming), id: \.id)
        var r = DiffResult()
        for (id, b) in inc.entries where cur[id] == nil {
            r.added += 1
            r.roots.append(DiffNode(change: .added, text: root(b), children: contentChildren(b, .added, names)))
        }
        for (id, a) in cur.entries where inc[id] == nil {
            r.removed += 1
            r.roots.append(DiffNode(change: .removed, text: root(a), children: contentChildren(a, .removed, names)))
        }
        for (id, b) in inc.entries {
            guard let a = cur[id] else { continue }
            let kids = compareItem(a, b, names)
            if !kids.isEmpty {
                r.changed += 1
                r.roots.append(DiffNode(change: .changed, text: root(b), children: kids))
            }
        }
        r.roots = sortRoots(r.roots)
        return r
    }

    /// DECISIONS 01 Q-3: the opt-in "Other data" section Windows never shows — crew members, saved lists, saved
    /// schedules, the ports database and the SIRE session — in the same tree shape (`[Crew member] …`,
    /// `[Saved list] …`, `[Saved schedule] …`, `[Port] …`, `[SIRE] …`) and ordering as `compare`.
    public static func compareOtherData(current: AppData, incoming: AppData) -> DiffResult {
        var r = DiffResult()
        func tally(_ nodes: [DiffNode]) {
            for n in nodes {
                switch n.change {
                case .added: r.added += 1
                case .removed: r.removed += 1
                case .changed: r.changed += 1
                }
                r.roots.append(n)
            }
        }
        tally(SvcOtherDataDiff.crew(current.crew, incoming.crew, names: itemNames(current, incoming)))
        tally(SvcOtherDataDiff.savedLists(current, incoming))
        tally(SvcOtherDataDiff.schedules(current.scheduleTemplates, incoming.scheduleTemplates))
        tally(SvcOtherDataDiff.ports(current.ports, incoming.ports))
        tally(SvcOtherDataDiff.sire(current.sire, incoming.sire))
        r.roots = sortRoots(r.roots)
        return r
    }

    /// `(s ?? "")` with every `\r` and `\n` replaced by a space, trimmed; at most 40 UTF-16 units, else the first
    /// 40 + `…` (a surrogate pair is never split).
    public static func snip(_ s: String?) -> String {
        var u = Array(NetText.trim((s ?? "").replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")).utf16)
        guard u.count > 40 else { return String(decoding: u, as: UTF16.self) }
        var cut = 40
        if UTF16.isLeadSurrogate(u[cut - 1]) { cut -= 1 }
        u = Array(u[0..<cut])
        return String(decoding: u, as: UTF16.self) + "\u{2026}"
    }

    // MARK: Windows-scope internals (08 §3.7)

    static func sortRoots(_ roots: [DiffNode]) -> [DiffNode] {
        func order(_ c: DiffNode.Change) -> Int { c == .added ? 0 : c == .changed ? 1 : 2 }
        return roots.enumerated().sorted { a, b in
            let oa = order(a.element.change), ob = order(b.element.change)
            if oa != ob { return oa < ob }
            let c = NetText.compareIgnoreCase(a.element.text, b.element.text)
            return c == .orderedSame ? a.offset < b.offset : c == .orderedAscending
        }.map(\.element)
    }

    /// Top-level item id → name over both sides (incoming wins), for `linked …` nodes.
    static func itemNames(_ current: AppData, _ incoming: AppData) -> [UUID: String] {
        var names: [UUID: String] = [:]
        for i in items(current) { names[i.id] = i.name }
        for i in items(incoming) { names[i.id] = i.name }
        return names
    }

    private static func items(_ d: AppData) -> [HierarchyItem] {
        (d.equipment as [HierarchyItem]) + (d.tasks as [HierarchyItem]) + (d.procedures as [HierarchyItem])
            + (d.vessels as [HierarchyItem])
    }

    private static func root(_ i: HierarchyItem) -> String { "[\(AppStore.kindLabel(i.kind))] \(i.name)" }

    private static func name(_ names: [UUID: String], _ id: UUID) -> String { names[id] ?? "(unknown)" }

    private static func fmt(_ d: NetDateTime?) -> String { d?.format(.isoDate) ?? "(none)" }

    private static func field(_ text: String) -> DiffNode { DiffNode(change: .changed, text: text) }

    private static func fileNodes(_ c: Container, _ change: DiffNode.Change) -> [DiffNode] {
        c.files.map { DiffNode(change: change, text: "file: \($0.name)") }
    }

    private static func contentChildren(_ i: HierarchyItem, _ c: DiffNode.Change, _ names: [UUID: String]) -> [DiffNode] {
        var n = fileNodes(i.container, c)
        switch i {
        case let t as TaskItem:
            for s in t.subtasks {
                n.append(DiffNode(change: c, text: "subtask: \(s.name)", children: taskContent(s, c, [])))
            }
        case let e as Equipment:
            for comp in e.components {
                n.append(DiffNode(change: c, text: "component: \(comp.name)", children: fileNodes(comp.container, c)))
            }
            for id in e.procedureIds { n.append(DiffNode(change: c, text: "linked procedure: \(name(names, id))")) }
            for id in e.taskIds { n.append(DiffNode(change: c, text: "linked task: \(name(names, id))")) }
        case let p as Procedure:
            for st in p.steps {
                n.append(DiffNode(change: c, text: "step: \(st.title)", children: stepContent(st, c, names)))
            }
        default:
            break
        }
        return n
    }

    private static func taskContent(_ t: TaskItem, _ c: DiffNode.Change, _ seen: Set<ObjectIdentifier>) -> [DiffNode] {
        var seen = seen
        guard seen.insert(ObjectIdentifier(t)).inserted else { return [] }
        var n = fileNodes(t.container, c)
        for s in t.subtasks {
            n.append(DiffNode(change: c, text: "subtask: \(s.name)", children: taskContent(s, c, seen)))
        }
        return n
    }

    private static func stepContent(_ st: ChecklistStep, _ c: DiffNode.Change, _ names: [UUID: String]) -> [DiffNode] {
        var n = fileNodes(st.container, c)
        for id in st.taskIds { n.append(DiffNode(change: c, text: "linked task: \(name(names, id))")) }
        for id in st.equipmentIds { n.append(DiffNode(change: c, text: "linked equipment/area: \(name(names, id))")) }
        return n
    }

    private static func compareItem(_ a: HierarchyItem, _ b: HierarchyItem, _ names: [UUID: String],
                                    _ seen: Set<ObjectIdentifier> = []) -> [DiffNode] {
        var n: [DiffNode] = []
        if !Ordinal.equals(a.name, b.name) { n.append(field("name: \"\(a.name)\" \u{2192} \"\(b.name)\"")) }
        if !Ordinal.equals(a.description, b.description) {
            n.append(field("description: \"\(snip(a.description))\" \u{2192} \"\(snip(b.description))\""))
        }
        notesNode(a.container, b.container, into: &n)
        diffFiles(a.container, b.container, into: &n)
        switch (a, b) {
        case let (ta as TaskItem, tb as TaskItem):
            if ta.deadline != tb.deadline { n.append(field("deadline: \(fmt(ta.deadline)) \u{2192} \(fmt(tb.deadline))")) }
            if ta.rangeStart != tb.rangeStart { n.append(field("start: \(fmt(ta.rangeStart)) \u{2192} \(fmt(tb.rangeStart))")) }
            // DECISIONS 08 OQ-10: friendly labels ("To Do → Done", "None → Weekly"); stored integers unchanged.
            if ta.recurrence != tb.recurrence {
                n.append(field("recurrence: \(ta.recurrence.friendlyLabel) \u{2192} \(tb.recurrence.friendlyLabel)"))
            }
            if ta.status != tb.status {
                n.append(field("status: \(ta.status.friendlyLabel) \u{2192} \(tb.status.friendlyLabel)"))
            }
            var seen = seen
            if seen.insert(ObjectIdentifier(tb)).inserted {
                diffTasks(ta.subtasks, tb.subtasks, names, seen, into: &n)
            }
        case let (ea as Equipment, eb as Equipment):
            diffComponents(ea.components, eb.components, into: &n)
            diffLinks(ea.procedureIds, eb.procedureIds, names, "linked procedure", into: &n)
            diffLinks(ea.taskIds, eb.taskIds, names, "linked task", into: &n)
        case let (pa as Procedure, pb as Procedure):
            diffSteps(pa.steps, pb.steps, names, into: &n)
        default:
            break
        }
        return n
    }

    static func notesNode(_ a: Container, _ b: Container, into n: inout [DiffNode]) {
        let an = XamlPlainText.diffText(a.richTextXaml), bn = XamlPlainText.diffText(b.richTextXaml)
        if !Ordinal.equals(an, bn) { n.append(field("notes: \"\(snip(an))\" \u{2192} \"\(snip(bn))\"")) }
    }

    /// OC-13: count-aware per key `Name|Path` — k = count(b) − count(a) Added nodes when k > 0 (b's first-occurrence
    /// order), −k Removed nodes when k < 0 (a's order). Identical to Windows when there are no duplicate keys.
    static func diffFiles(_ a: Container, _ b: Container, into n: inout [DiffNode]) {
        func counts(_ c: Container) -> (order: [String], count: [String: Int], name: [String: String]) {
            var order: [String] = [], count: [String: Int] = [:], name: [String: String] = [:]
            for f in c.files {
                let key = f.name + "|" + f.path
                if count[key] == nil { order.append(key); name[key] = f.name }
                count[key, default: 0] += 1
            }
            return (order, count, name)
        }
        let ca = counts(a), cb = counts(b)
        for key in cb.order {
            let k = cb.count[key, default: 0] - ca.count[key, default: 0]
            if k > 0 { for _ in 0..<k { n.append(DiffNode(change: .added, text: "file: \(cb.name[key] ?? "")")) } }
        }
        for key in ca.order {
            let k = ca.count[key, default: 0] - cb.count[key, default: 0]
            if k > 0 { for _ in 0..<k { n.append(DiffNode(change: .removed, text: "file: \(ca.name[key] ?? "")")) } }
        }
    }

    private static func diffTasks(_ a: [TaskItem], _ b: [TaskItem], _ names: [UUID: String],
                                  _ seen: Set<ObjectIdentifier>, into n: inout [DiffNode]) {
        let ai = SvcOrderedIndex(a, id: \.id), bi = SvcOrderedIndex(b, id: \.id)
        for (id, t) in bi.entries where ai[id] == nil {
            n.append(DiffNode(change: .added, text: "subtask: \(t.name)", children: taskContent(t, .added, [])))
        }
        for (id, t) in ai.entries where bi[id] == nil {
            n.append(DiffNode(change: .removed, text: "subtask: \(t.name)", children: taskContent(t, .removed, [])))
        }
        for (id, tb) in bi.entries {
            guard let ta = ai[id] else { continue }
            let kids = compareItem(ta, tb, names, seen)
            if !kids.isEmpty { n.append(DiffNode(change: .changed, text: "subtask: \(tb.name)", children: kids)) }
        }
    }

    private static func diffComponents(_ a: [Component], _ b: [Component], into n: inout [DiffNode]) {
        let ai = SvcOrderedIndex(a, id: \.id), bi = SvcOrderedIndex(b, id: \.id)
        for (id, c) in bi.entries where ai[id] == nil {
            n.append(DiffNode(change: .added, text: "component: \(c.name)", children: fileNodes(c.container, .added)))
        }
        for (id, c) in ai.entries where bi[id] == nil {
            n.append(DiffNode(change: .removed, text: "component: \(c.name)", children: fileNodes(c.container, .removed)))
        }
        for (id, cb) in bi.entries {
            guard let ca = ai[id] else { continue }
            var kids: [DiffNode] = []
            if !Ordinal.equals(ca.name, cb.name) { kids.append(field("name: \"\(ca.name)\" \u{2192} \"\(cb.name)\"")) }
            if !Ordinal.equals(ca.notes, cb.notes) { kids.append(field("notes line: \"\(snip(ca.notes))\" \u{2192} \"\(snip(cb.notes))\"")) }
            notesNode(ca.container, cb.container, into: &kids)
            diffFiles(ca.container, cb.container, into: &kids)
            if !kids.isEmpty { n.append(DiffNode(change: .changed, text: "component: \(cb.name)", children: kids)) }
        }
    }

    private static func diffSteps(_ a: [ChecklistStep], _ b: [ChecklistStep], _ names: [UUID: String],
                                  into n: inout [DiffNode]) {
        let ai = SvcOrderedIndex(a, id: \.id), bi = SvcOrderedIndex(b, id: \.id)
        for (id, s) in bi.entries where ai[id] == nil {
            n.append(DiffNode(change: .added, text: "step: \(s.title)", children: stepContent(s, .added, names)))
        }
        for (id, s) in ai.entries where bi[id] == nil {
            n.append(DiffNode(change: .removed, text: "step: \(s.title)", children: stepContent(s, .removed, names)))
        }
        for (id, sb) in bi.entries {
            guard let sa = ai[id] else { continue }
            var kids: [DiffNode] = []
            if !Ordinal.equals(sa.title, sb.title) { kids.append(field("title: \"\(sa.title)\" \u{2192} \"\(sb.title)\"")) }
            if sa.done != sb.done { kids.append(field("done: \(svcBool(sa.done)) \u{2192} \(svcBool(sb.done))")) }
            notesNode(sa.container, sb.container, into: &kids)
            diffFiles(sa.container, sb.container, into: &kids)
            diffLinks(sa.taskIds, sb.taskIds, names, "linked task", into: &kids)
            diffLinks(sa.equipmentIds, sb.equipmentIds, names, "linked equipment/area", into: &kids)
            if !kids.isEmpty { n.append(DiffNode(change: .changed, text: "step: \(sb.title)", children: kids)) }
        }
    }

    /// Set semantics; first occurrences in collection order (OC-13).
    static func diffLinks(_ a: [UUID], _ b: [UUID], _ names: [UUID: String], _ label: String,
                                  into n: inout [DiffNode]) {
        let aset = Set(a), bset = Set(b)
        var seen = Set<UUID>()
        for id in b where !aset.contains(id) && seen.insert(id).inserted {
            n.append(DiffNode(change: .added, text: "\(label): \(name(names, id))"))
        }
        seen.removeAll()
        for id in a where !bset.contains(id) && seen.insert(id).inserted {
            n.append(DiffNode(change: .removed, text: "\(label): \(name(names, id))"))
        }
    }

    /// .NET `bool.ToString()`.
    static func svcBool(_ b: Bool) -> String { b ? "True" : "False" }
}

/// An insertion-ordered id → value map with C# `Dictionary` assignment semantics: a repeated key keeps its FIRST
/// position and takes the LAST value (01 §3.15 "map iteration order").
struct SvcOrderedIndex<Value> {
    private(set) var keys: [UUID] = []
    private var values: [UUID: Value] = [:]

    init<S: Sequence>(_ items: S, id: (Value) -> UUID) where S.Element == Value {
        for v in items {
            let k = id(v)
            if values[k] == nil { keys.append(k) }
            values[k] = v
        }
    }

    subscript(_ key: UUID) -> Value? { values[key] }

    var entries: [(UUID, Value)] { keys.map { ($0, values[$0]!) } }
}

/// DECISIONS 01 Q-3 "Other data" (Mac only; additive UI, no data effect).
@MainActor enum SvcOtherDataDiff {
    private static func field(_ text: String) -> DiffNode { DiffNode(change: .changed, text: text) }
    private static func arrow(_ label: String, _ a: String, _ b: String) -> DiffNode {
        field("\(label): \"\(DataDiff.snip(a))\" \u{2192} \"\(DataDiff.snip(b))\"")
    }

    static func crewName(_ m: CrewMember) -> String {
        let full = m.fullName
        let n = NetText.isBlank(full) ? m.lastName : full
        return n.isEmpty ? "(unnamed)" : n
    }

    static func crew(_ a: [CrewMember], _ b: [CrewMember], names: [UUID: String] = [:]) -> [DiffNode] {
        let ai = SvcOrderedIndex(a, id: \.id), bi = SvcOrderedIndex(b, id: \.id)
        var out: [DiffNode] = []
        for (id, m) in bi.entries where ai[id] == nil {
            out.append(DiffNode(change: .added, text: "[Crew member] \(crewName(m))"))
        }
        for (id, m) in ai.entries where bi[id] == nil {
            out.append(DiffNode(change: .removed, text: "[Crew member] \(crewName(m))"))
        }
        for (id, mb) in bi.entries {
            guard let ma = ai[id] else { continue }
            var kids: [DiffNode] = []
            let ja = ma.toJSON(options: .dataFile), jb = mb.toJSON(options: .dataFile)
            for key in CrewMember.jsonKeys where !["Id", "Checklist", "Schedule", "ScheduleVesselId", "Flags"].contains(key) {
                let va = ja[key]?.stringValue ?? "", vb = jb[key]?.stringValue ?? ""
                if !Ordinal.equals(va, vb) { kids.append(arrow(key, va, vb)) }
            }
            if ma.scheduleVesselId != mb.scheduleVesselId { kids.append(field("schedule vessel changed")) }
            kids += steps(ma.checklist, mb.checklist, label: "checklist item", names: names)
            kids += entries(ma.schedule, mb.schedule)
            if !kids.isEmpty { out.append(DiffNode(change: .changed, text: "[Crew member] \(crewName(mb))", children: kids)) }
        }
        return out
    }

    /// Crew checklist items: title, done, deadline, then (V2-J4) notes, the count-aware file bank and the linked
    /// tasks / equipment — the same nodes a hierarchy step shows, so a bundle that drops a crew member's scanned
    /// passport or certificate is previewed as a change, never as "no change".
    static func steps(_ a: [ChecklistStep], _ b: [ChecklistStep], label: String,
                      names: [UUID: String] = [:]) -> [DiffNode] {
        let ai = SvcOrderedIndex(a, id: \.id), bi = SvcOrderedIndex(b, id: \.id)
        var out: [DiffNode] = []
        for (id, s) in bi.entries where ai[id] == nil { out.append(DiffNode(change: .added, text: "\(label): \(s.title)")) }
        for (id, s) in ai.entries where bi[id] == nil { out.append(DiffNode(change: .removed, text: "\(label): \(s.title)")) }
        for (id, sb) in bi.entries {
            guard let sa = ai[id] else { continue }
            var kids: [DiffNode] = []
            if !Ordinal.equals(sa.title, sb.title) { kids.append(arrow("title", sa.title, sb.title)) }
            if sa.done != sb.done { kids.append(field("done: \(DataDiff.svcBool(sa.done)) \u{2192} \(DataDiff.svcBool(sb.done))")) }
            if sa.deadline != sb.deadline {
                kids.append(field("deadline: \(sa.deadline?.format(.isoDate) ?? "(none)") \u{2192} \(sb.deadline?.format(.isoDate) ?? "(none)")"))
            }
            DataDiff.notesNode(sa.container, sb.container, into: &kids)
            DataDiff.diffFiles(sa.container, sb.container, into: &kids)
            DataDiff.diffLinks(sa.taskIds, sb.taskIds, names, "linked task", into: &kids)
            DataDiff.diffLinks(sa.equipmentIds, sb.equipmentIds, names, "linked equipment/area", into: &kids)
            if !kids.isEmpty { out.append(DiffNode(change: .changed, text: "\(label): \(sb.title)", children: kids)) }
        }
        return out
    }

    static func entries(_ a: [ScheduleEntry], _ b: [ScheduleEntry]) -> [DiffNode] {
        let ai = SvcOrderedIndex(a, id: \.id), bi = SvcOrderedIndex(b, id: \.id)
        var out: [DiffNode] = []
        for (id, e) in bi.entries where ai[id] == nil { out.append(DiffNode(change: .added, text: "schedule entry: \(e.title)")) }
        for (id, e) in ai.entries where bi[id] == nil { out.append(DiffNode(change: .removed, text: "schedule entry: \(e.title)")) }
        for (id, eb) in bi.entries {
            guard let ea = ai[id] else { continue }
            var kids: [DiffNode] = []
            if !Ordinal.equals(ea.title, eb.title) { kids.append(arrow("title", ea.title, eb.title)) }
            if !Ordinal.equals(ea.whenDisplay, eb.whenDisplay) { kids.append(arrow("when", ea.whenDisplay, eb.whenDisplay)) }
            if ea.done != eb.done { kids.append(field("done: \(DataDiff.svcBool(ea.done)) \u{2192} \(DataDiff.svcBool(eb.done))")) }
            if !Ordinal.equals(ea.notes, eb.notes) { kids.append(arrow("notes", ea.notes, eb.notes)) }
            if !kids.isEmpty { out.append(DiffNode(change: .changed, text: "schedule entry: \(eb.title)", children: kids)) }
        }
        return out
    }

    static func savedLists(_ current: AppData, _ incoming: AppData) -> [DiffNode] {
        func groupName(_ d: AppData, _ id: UUID?) -> String {
            guard let id else { return "(ungrouped)" }
            return d.listGroups.first(where: { $0.id == id })?.name ?? ""
        }
        func listName(_ t: ChecklistTemplate) -> String { t.name.isEmpty ? "(unnamed)" : t.name }
        let ai = SvcOrderedIndex(current.checklistTemplates, id: \.id)
        let bi = SvcOrderedIndex(incoming.checklistTemplates, id: \.id)
        var out: [DiffNode] = []
        for (id, t) in bi.entries where ai[id] == nil {
            out.append(DiffNode(change: .added, text: "[Saved list] \(listName(t))",
                                children: t.items.map { DiffNode(change: .added, text: "item: \($0.title)") }))
        }
        for (id, t) in ai.entries where bi[id] == nil {
            out.append(DiffNode(change: .removed, text: "[Saved list] \(listName(t))",
                                children: t.items.map { DiffNode(change: .removed, text: "item: \($0.title)") }))
        }
        for (id, tb) in bi.entries {
            guard let ta = ai[id] else { continue }
            var kids: [DiffNode] = []
            if !Ordinal.equals(ta.name, tb.name) { kids.append(arrow("name", ta.name, tb.name)) }
            let ga = groupName(current, ta.groupId), gb = groupName(incoming, tb.groupId)
            if !Ordinal.equals(ga, gb) { kids.append(arrow("group", ga, gb)) }
            for k in 0..<max(ta.items.count, tb.items.count) {
                if k >= ta.items.count { kids.append(DiffNode(change: .added, text: "item: \(tb.items[k].title)")); continue }
                if k >= tb.items.count { kids.append(DiffNode(change: .removed, text: "item: \(ta.items[k].title)")); continue }
                let x = ta.items[k], y = tb.items[k]
                var itemKids: [DiffNode] = []
                if !Ordinal.equals(x.title, y.title) { itemKids.append(arrow("title", x.title, y.title)) }
                if x.durationMinutes != y.durationMinutes { itemKids.append(field("duration: \(x.durationMinutes) \u{2192} \(y.durationMinutes) min")) }
                if x.isJob != y.isJob { itemKids.append(field("schedulable: \(DataDiff.svcBool(x.isJob)) \u{2192} \(DataDiff.svcBool(y.isJob))")) }
                let nx = XamlPlainText.diffText(x.container.richTextXaml), ny = XamlPlainText.diffText(y.container.richTextXaml)
                if !Ordinal.equals(nx, ny) { itemKids.append(arrow("notes", nx, ny)) }
                if x.container.files.map(\.name) != y.container.files.map(\.name) {
                    itemKids.append(field("files: \(x.container.files.count) \u{2192} \(y.container.files.count)"))
                }
                if !itemKids.isEmpty { kids.append(DiffNode(change: .changed, text: "item \(k + 1): \(y.title)", children: itemKids)) }
            }
            if !kids.isEmpty { out.append(DiffNode(change: .changed, text: "[Saved list] \(listName(tb))", children: kids)) }
        }
        return out
    }

    static func schedules(_ a: [ScheduleTemplate], _ b: [ScheduleTemplate]) -> [DiffNode] {
        func label(_ t: ScheduleTemplate) -> String { "[Saved schedule] \(t.name.isEmpty ? "(unnamed)" : t.name)" }
        let ai = SvcOrderedIndex(a, id: \.id), bi = SvcOrderedIndex(b, id: \.id)
        var out: [DiffNode] = []
        for (id, t) in bi.entries where ai[id] == nil { out.append(DiffNode(change: .added, text: label(t))) }
        for (id, t) in ai.entries where bi[id] == nil { out.append(DiffNode(change: .removed, text: label(t))) }
        for (id, tb) in bi.entries {
            guard let ta = ai[id] else { continue }
            var kids: [DiffNode] = []
            if !Ordinal.equals(ta.name, tb.name) { kids.append(arrow("name", ta.name, tb.name)) }
            if !Ordinal.equals(ta.vesselName, tb.vesselName) { kids.append(arrow("vessel", ta.vesselName, tb.vesselName)) }
            kids += entries(ta.entries, tb.entries)
            if !kids.isEmpty { out.append(DiffNode(change: .changed, text: label(tb), children: kids)) }
        }
        return out
    }

    static func ports(_ a: [PortRecord], _ b: [PortRecord]) -> [DiffNode] {
        let ai = SvcOrderedIndex(a, id: \.id), bi = SvcOrderedIndex(b, id: \.id)
        var out: [DiffNode] = []
        for (id, p) in bi.entries where ai[id] == nil { out.append(DiffNode(change: .added, text: "[Port] \(p.display)")) }
        for (id, p) in ai.entries where bi[id] == nil { out.append(DiffNode(change: .removed, text: "[Port] \(p.display)")) }
        for (id, pb) in bi.entries {
            guard let pa = ai[id] else { continue }
            var kids: [DiffNode] = []
            if !Ordinal.equals(pa.name, pb.name) { kids.append(arrow("name", pa.name, pb.name)) }
            if !Ordinal.equals(pa.country, pb.country) { kids.append(arrow("country", pa.country, pb.country)) }
            if !Ordinal.equals(pa.unLocode, pb.unLocode) { kids.append(arrow("UN/LOCODE", pa.unLocode, pb.unLocode)) }
            let va = Set(pa.visits.map(\.visitKey)), vb = Set(pb.visits.map(\.visitKey))
            var seen = Set<String>()
            for v in pb.visits where !va.contains(v.visitKey) && seen.insert(v.visitKey).inserted {
                kids.append(DiffNode(change: .added, text: "visit: \(v.vesselName) \(v.arrivalDisplay)"))
            }
            seen.removeAll()
            for v in pa.visits where !vb.contains(v.visitKey) && seen.insert(v.visitKey).inserted {
                kids.append(DiffNode(change: .removed, text: "visit: \(v.vesselName) \(v.arrivalDisplay)"))
            }
            if !kids.isEmpty { out.append(DiffNode(change: .changed, text: "[Port] \(pb.display)", children: kids)) }
        }
        return out
    }

    static func sire(_ a: SireState, _ b: SireState) -> [DiffNode] {
        var kids: [DiffNode] = []
        var keys: [String] = b.questionStatuses.keys
        for k in a.questionStatuses.keys where !b.questionStatuses.containsKey(k) { keys.append(k) }
        for q in keys {
            let sa = a.status(for: q), sb = b.status(for: q)
            if sa != sb { kids.append(field("Q\(q) status: \(sa.rawValue) \u{2192} \(sb.rawValue)")) }
        }
        func setDiff(_ x: [String], _ y: [String], _ label: String) {
            for q in y where !x.contains(where: { Ordinal.equals($0, q) }) { kids.append(DiffNode(change: .added, text: "\(label): Q\(q)")) }
            for q in x where !y.contains(where: { Ordinal.equals($0, q) }) { kids.append(DiffNode(change: .removed, text: "\(label): Q\(q)")) }
        }
        setDiff(a.bookmarks, b.bookmarks, "bookmark")
        setDiff(a.forExport, b.forExport, "for export")
        let ai = SvcOrderedIndex(a.tasks, id: \.id), bi = SvcOrderedIndex(b.tasks, id: \.id)
        for (id, t) in bi.entries where ai[id] == nil { kids.append(DiffNode(change: .added, text: "task Q\(t.questionNumber): \(DataDiff.snip(t.text))")) }
        for (id, t) in ai.entries where bi[id] == nil { kids.append(DiffNode(change: .removed, text: "task Q\(t.questionNumber): \(DataDiff.snip(t.text))")) }
        for (id, tb) in bi.entries {
            guard let ta = ai[id] else { continue }
            if !Ordinal.equals(ta.text, tb.text) || ta.isCompleted != tb.isCompleted {
                kids.append(field("task Q\(tb.questionNumber): \(DataDiff.snip(tb.text))"))
            }
        }
        var bodyKeys: [String] = b.questionBodies.keys
        for k in a.questionBodies.keys where !b.questionBodies.containsKey(k) { bodyKeys.append(k) }
        for q in bodyKeys {
            let x = XamlPlainText.diffText(a.questionBodies[q] ?? ""), y = XamlPlainText.diffText(b.questionBodies[q] ?? "")
            if !Ordinal.equals(x, y) { kids.append(arrow("Q\(q) notes", x, y)) }
        }
        return kids.isEmpty ? [] : [DiffNode(change: .changed, text: "[SIRE] session", children: kids)]
    }
}
