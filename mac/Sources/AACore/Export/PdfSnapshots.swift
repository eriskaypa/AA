// Spec: 11 §6.2 (snapshot on the main actor after flushing editors, build + render off-main), §4.1 (the model
//       fields every exporter reads), §4.2 (stored calendar dates, no UTC conversion), §6.7 (FindById through a
//       dictionary built once, first-wins Equipment → Tasks → Procedures → Vessels), PDF-105 (nil strings → ""),
//       DECISIONS 11 Q6 (gated related items print their name only); ARCHITECTURE.md §2.2 rule 1.
import Foundation

public struct PdfFileSnapshot: Sendable, Hashable {
    public var name: String, path: String, kind: FileKind
    public init(name: String, path: String, kind: FileKind) { self.name = name; self.path = path; self.kind = kind }
}

public struct PdfContainerSnapshot: Sendable, Hashable {
    /// `Container.RichTextXaml` exactly as stored.
    public var xaml: String
    public var files: [PdfFileSnapshot]
    public init(xaml: String = "", files: [PdfFileSnapshot] = []) { self.xaml = xaml; self.files = files }
    public static let empty = PdfContainerSnapshot()
}

public struct PdfTaskSnapshot: Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var description: String
    public var deadline: CivilDate?
    public var rangeStart: CivilDate?
    public var recurrence: RecurrenceKind
    public var isComplete: Bool
    public var container: PdfContainerSnapshot
    public var subtasks: [PdfTaskSnapshot]

    public init(id: UUID = UUID(), name: String, description: String = "", deadline: CivilDate? = nil,
                rangeStart: CivilDate? = nil, recurrence: RecurrenceKind = .none, isComplete: Bool = false,
                container: PdfContainerSnapshot = .empty, subtasks: [PdfTaskSnapshot] = []) {
        self.id = id; self.name = name; self.description = description; self.deadline = deadline
        self.rangeStart = rangeStart; self.recurrence = recurrence; self.isComplete = isComplete
        self.container = container; self.subtasks = subtasks
    }
}

public struct PdfStepSnapshot: Sendable, Hashable {
    public var title: String
    public var done: Bool
    public var deadline: CivilDate?
    public var taskIds: [UUID]
    public var equipmentIds: [UUID]
    public var container: PdfContainerSnapshot

    public init(title: String, done: Bool = false, deadline: CivilDate? = nil, taskIds: [UUID] = [],
                equipmentIds: [UUID] = [], container: PdfContainerSnapshot = .empty) {
        self.title = title; self.done = done; self.deadline = deadline; self.taskIds = taskIds
        self.equipmentIds = equipmentIds; self.container = container
    }
}

public struct PdfComponentSnapshot: Sendable, Hashable {
    public var name: String, notes: String
    public init(name: String, notes: String) { self.name = name; self.notes = notes }
}

/// One top-level item as `FindById` sees it (plus what the linked-item sections print about it).
public struct PdfIndexEntry: Sendable, Hashable {
    public var id: UUID
    public var kind: ItemKind
    public var name: String
    public var description: String
    /// Password-gated this session (DECISIONS 11 Q6: only the name is printed).
    public var isGated: Bool
    /// Tasks: the fields of the task summary (PDF-040); subtasks/container are not used there.
    public var task: PdfTaskSnapshot?
    /// Procedures: the steps (titles + done) printed under Equipment "Linked Procedures" (PDF-037).
    public var steps: [PdfStepSnapshot]

    public init(id: UUID, kind: ItemKind, name: String, description: String = "", isGated: Bool = false,
                task: PdfTaskSnapshot? = nil, steps: [PdfStepSnapshot] = []) {
        self.id = id; self.kind = kind; self.name = name; self.description = description; self.isGated = isGated
        self.task = task; self.steps = steps
    }
}

/// `FindById` over the four top-level collections, first match wins (11 §6.7).
public struct PdfLookup: Sendable, Hashable {
    public private(set) var entries: [UUID: PdfIndexEntry] = [:]

    public init(_ ordered: [PdfIndexEntry] = []) {
        for e in ordered where entries[e.id] == nil { entries[e.id] = e }
    }

    public func find(_ id: UUID) -> PdfIndexEntry? { entries[id] }
}

public enum PdfItemSpecifics: Sendable, Hashable {
    case equipment(components: [PdfComponentSnapshot], procedureIds: [UUID], taskIds: [UUID])
    case task(PdfTaskSnapshot)
    case procedure(steps: [PdfStepSnapshot])
    case vessel
}

/// Everything the item PDF (product A) needs, detached from the model.
public struct PdfItemSnapshot: Sendable, Hashable {
    public var id: UUID
    public var kind: ItemKind
    public var name: String
    public var description: String
    public var container: PdfContainerSnapshot
    public var specifics: PdfItemSpecifics
    /// `repo.RelatedItems(item).Distinct()` (PDF-044), already resolved.
    public var related: [PdfIndexEntry]
    public var lookup: PdfLookup

    public init(id: UUID = UUID(), kind: ItemKind, name: String, description: String = "",
                container: PdfContainerSnapshot = .empty, specifics: PdfItemSpecifics, related: [PdfIndexEntry] = [],
                lookup: PdfLookup = PdfLookup()) {
        self.id = id; self.kind = kind; self.name = name; self.description = description; self.container = container
        self.specifics = specifics; self.related = related; self.lookup = lookup
    }
}

/// The checklist-only exports (products C and D).
public struct PdfChecklistSnapshot: Sendable, Hashable {
    public var name: String
    public var steps: [PdfStepSnapshot]
    public var lookup: PdfLookup
    public init(name: String, steps: [PdfStepSnapshot], lookup: PdfLookup) {
        self.name = name; self.steps = steps; self.lookup = lookup
    }
}

public struct PdfSavedListItemSnapshot: Sendable, Hashable {
    public var title: String
    public var isJob: Bool
    public var container: PdfContainerSnapshot
    public init(title: String, isJob: Bool = false, container: PdfContainerSnapshot = .empty) {
        self.title = title; self.isJob = isJob; self.container = container
    }
}

/// One `(group, template)` entry of a saved-lists export (PDF-020…022, 027).
public struct PdfSavedListEntry: Sendable, Hashable {
    public var group: String?
    public var name: String
    public var items: [PdfSavedListItemSnapshot]
    public init(group: String?, name: String, items: [PdfSavedListItemSnapshot]) {
        self.group = group; self.name = name; self.items = items
    }
}

/// Builds the snapshots on the main actor (the only place model objects are read).
@MainActor
public enum PdfSnapshotBuilder {
    public static func container(_ c: Container?) -> PdfContainerSnapshot {
        guard let c else { return .empty }
        return PdfContainerSnapshot(xaml: c.richTextXaml,
                                    files: c.files.map { PdfFileSnapshot(name: $0.name, path: $0.path, kind: $0.kind) })
    }

    /// Stored wall-clock calendar date (11 §4.2).
    static func day(_ d: NetDateTime?) -> CivilDate? { d?.civilDate }

    public static func task(_ t: TaskItem, includeChildren: Bool = true) -> PdfTaskSnapshot {
        var seen = Set<ObjectIdentifier>()
        func build(_ t: TaskItem) -> PdfTaskSnapshot {
            seen.insert(ObjectIdentifier(t))
            let kids = includeChildren ? t.subtasks.filter { !seen.contains(ObjectIdentifier($0)) }.map(build) : []
            return PdfTaskSnapshot(id: t.id, name: t.name, description: t.description, deadline: day(t.deadline),
                                   rangeStart: day(t.rangeStart), recurrence: t.recurrence, isComplete: t.isComplete,
                                   container: includeChildren ? container(t.container) : .empty, subtasks: kids)
        }
        return build(t)
    }

    public static func step(_ s: ChecklistStep, withContainer: Bool = true) -> PdfStepSnapshot {
        PdfStepSnapshot(title: s.title, done: s.done, deadline: day(s.deadline), taskIds: s.taskIds,
                        equipmentIds: s.equipmentIds, container: withContainer ? container(s.container) : .empty)
    }

    /// One index entry per top-level item, Equipment → Tasks → Procedures → Vessels (first wins).
    public static func lookup(store: AppStore, isGated: (HierarchyItem) -> Bool) -> PdfLookup {
        PdfLookup(store.allItems().map { indexEntry($0, isGated: isGated) })
    }

    public static func indexEntry(_ i: HierarchyItem, isGated: (HierarchyItem) -> Bool) -> PdfIndexEntry {
        var e = PdfIndexEntry(id: i.id, kind: i.kind, name: i.name, description: i.description, isGated: isGated(i))
        if let t = i as? TaskItem { e.task = task(t, includeChildren: false) }
        if let p = i as? Procedure { e.steps = p.steps.map { step($0, withContainer: false) } }
        return e
    }

    public static func item(_ item: HierarchyItem, store: AppStore, isGated: (HierarchyItem) -> Bool) -> PdfItemSnapshot {
        let specifics: PdfItemSpecifics
        switch item {
        case let e as Equipment:
            specifics = .equipment(components: e.components.map { PdfComponentSnapshot(name: $0.name, notes: $0.notes) },
                                   procedureIds: e.procedureIds, taskIds: e.taskIds)
        case let t as TaskItem:
            specifics = .task(task(t))
        case let p as Procedure:
            specifics = .procedure(steps: p.steps.map { step($0) })
        default:
            specifics = .vessel
        }
        var seen = Set<ObjectIdentifier>()
        let related = store.relatedItems(of: item).filter { seen.insert(ObjectIdentifier($0)).inserted }
            .map { indexEntry($0, isGated: isGated) }
        return PdfItemSnapshot(id: item.id, kind: item.kind, name: item.name, description: item.description,
                               container: container(item.container), specifics: specifics, related: related,
                               lookup: lookup(store: store, isGated: isGated))
    }

    public static func checklist(_ p: Procedure, store: AppStore) -> PdfChecklistSnapshot {
        PdfChecklistSnapshot(name: p.name, steps: p.steps.map { step($0, withContainer: false) },
                             lookup: lookup(store: store, isGated: { _ in false }))
    }

    public static func savedLists(_ entries: [(template: ChecklistTemplate, group: String?)]) -> [PdfSavedListEntry] {
        entries.map { e in
            PdfSavedListEntry(group: e.group, name: e.template.name,
                              items: e.template.items.map {
                                  PdfSavedListItemSnapshot(title: $0.title, isJob: $0.isJob, container: container($0.container))
                              })
        }
    }
}
