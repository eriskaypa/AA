// Spec: 01 §4.2.6, DATA-130 / 02 REPO-040 (IsComplete ⇄ Status sync + order-independent load rule),
//       01 §3.19 / DATA-131 / 02 REPO-054 (working range), 04 §7.3 (WhenText); ARCHITECTURE.md §4.3.
import Foundation
import Observation

@MainActor @Observable
public final class TaskItem: HierarchyItem, SchedulableJob {
    /// Range END (the deadline).
    public var deadline: NetDateTime?
    public var rangeStart: NetDateTime?
    public var isJob: Bool
    public var durationMinutes: Int
    public var scheduledStart: NetDateTime?
    public var recurrence: RecurrenceKind
    public var recurrenceSpawned: Bool
    private var storedIsComplete: Bool
    private var storedStatus: WorkStatus
    public var subtasks: [TaskItem]

    public override class var jsonKeys: [String] {
        ["Deadline", "RangeStart", "IsJob", "DurationMinutes", "ScheduledStart", "Recurrence", "RecurrenceSpawned",
         "IsComplete", "Status", "Subtasks"] + baseJSONKeys
    }
    public override var kind: ItemKind { .task }
    public var jobName: String { name }

    /// DATA-130: true → Status Done (if not already); false while Done → Todo (InProgress/Blocked preserved).
    public var isComplete: Bool {
        get { storedIsComplete }
        set {
            guard newValue != storedIsComplete else { return }
            storedIsComplete = newValue
            if newValue && storedStatus != .done { storedStatus = .done }
            else if !newValue && storedStatus == .done { storedStatus = .todo }
        }
    }

    /// DATA-130: IsComplete = (Status == Done).
    public var status: WorkStatus {
        get { storedStatus }
        set {
            guard newValue != storedStatus else { return }
            storedStatus = newValue
            let done = newValue == .done
            if storedIsComplete != done { storedIsComplete = done }
        }
    }

    public override init(id: UUID = UUID(), name: String = "") {
        deadline = nil; rangeStart = nil; isJob = false; durationMinutes = 60; scheduledStart = nil
        recurrence = .none; recurrenceSpawned = false; storedIsComplete = false; storedStatus = .todo; subtasks = []
        super.init(id: id, name: name)
    }

    public required init(json: JSONObject, context: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(json, context: context, type: "Task")
        deadline = try r.date("Deadline")
        rangeStart = try r.date("RangeStart")
        isJob = try r.bool("IsJob") ?? false
        durationMinutes = try r.int("DurationMinutes") ?? 60
        scheduledStart = try r.date("ScheduledStart")
        recurrence = try r.netEnum("Recurrence", RecurrenceKind.self) ?? .none
        recurrenceSpawned = try r.bool("RecurrenceSpawned") ?? false
        // Load rule (order-independent): Status present → it wins, IsComplete = (Status == Done);
        // only IsComplete → Status = IsComplete ? Done : Todo; neither → defaults.
        let complete = try r.bool("IsComplete")
        let status = try r.netEnum("Status", WorkStatus.self)
        if let status {
            storedStatus = status
            storedIsComplete = status == .done
        } else if let complete {
            storedIsComplete = complete
            storedStatus = complete ? .done : .todo
        } else {
            storedIsComplete = false
            storedStatus = .todo
        }
        subtasks = try r.modelArray("Subtasks", TaskItem.self) ?? []
        try super.init(json: json, context: context)
        extra = unknownMembers(json, context, keys: TaskItem.jsonKeys)
    }

    public override func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.optionalDate("Deadline", deadline); w.optionalDate("RangeStart", rangeStart); w.bool("IsJob", isJob)
        w.int("DurationMinutes", durationMinutes); w.optionalDate("ScheduledStart", scheduledStart)
        w.netEnum("Recurrence", recurrence); w.bool("RecurrenceSpawned", recurrenceSpawned)
        w.bool("IsComplete", isComplete); w.netEnum("Status", status); w.modelArray("Subtasks", subtasks)
        encodeBase(into: &w)
        return w.build(appending: extra)
    }

    // MARK: Working range (01 §3.19, 02 REPO-054) — all ignore originalText.

    /// RangeStart and Deadline set and RangeStart.Date < Deadline.Date.
    public var hasRange: Bool {
        guard let s = rangeStart, let d = deadline else { return false }
        return s.date.ticks < d.date.ticks
    }

    /// RangeStart ?? Deadline.
    public var rangeFirst: NetDateTime? { rangeStart ?? deadline }

    /// `""` | `"yyyy-MM-dd → yyyy-MM-dd"` (hasRange) | `"yyyy-MM-dd"`.
    public var whenText: String {
        guard let d = deadline else { return "" }
        if let s = rangeStart, s.date.ticks < d.date.ticks {
            return s.format(.isoDate) + " \u{2192} " + d.format(.isoDate)
        }
        return d.format(.isoDate)
    }

    /// False without a deadline; the range is [start … end] with end = Deadline.Date and start = RangeStart.Date
    /// if it is <= end, else end (an out-of-order range collapses to the deadline day).
    public func coversDay(_ day: CivilDate) -> Bool {
        guard let d = deadline else { return false }
        let end = d.civilDate
        var start = end
        if let s = rangeStart, s.civilDate <= end { start = s.civilDate }
        return day >= start && day <= end
    }

    /// Every nested subtask, pre-order (depth first), guarded against cycles.
    public func allSubtasksDepthFirst() -> [TaskItem] {
        var out: [TaskItem] = []
        var seen: Set<ObjectIdentifier> = [ObjectIdentifier(self)]
        func walk(_ t: TaskItem) {
            for s in t.subtasks where seen.insert(ObjectIdentifier(s)).inserted {
                out.append(s)
                walk(s)
            }
        }
        walk(self)
        return out
    }
}

@MainActor @Observable
public final class Procedure: HierarchyItem, SchedulableJob {
    public var steps: [ChecklistStep]
    public var deadline: NetDateTime?
    public var recurrence: RecurrenceKind
    public var recurrenceSpawned: Bool
    public var status: WorkStatus
    public var isJob: Bool
    public var durationMinutes: Int
    public var scheduledStart: NetDateTime?

    public override class var jsonKeys: [String] {
        ["Steps", "Deadline", "Recurrence", "RecurrenceSpawned", "Status", "IsJob", "DurationMinutes",
         "ScheduledStart"] + baseJSONKeys
    }
    public override var kind: ItemKind { .procedure }
    public var jobName: String { name }

    public override init(id: UUID = UUID(), name: String = "") {
        steps = []; deadline = nil; recurrence = .none; recurrenceSpawned = false; status = .todo; isJob = false
        durationMinutes = 60; scheduledStart = nil
        super.init(id: id, name: name)
    }

    public required init(json: JSONObject, context: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(json, context: context, type: "Procedure")
        steps = try r.modelArray("Steps", ChecklistStep.self) ?? []
        deadline = try r.date("Deadline")
        recurrence = try r.netEnum("Recurrence", RecurrenceKind.self) ?? .none
        recurrenceSpawned = try r.bool("RecurrenceSpawned") ?? false
        status = try r.netEnum("Status", WorkStatus.self) ?? .todo
        isJob = try r.bool("IsJob") ?? false
        durationMinutes = try r.int("DurationMinutes") ?? 60
        scheduledStart = try r.date("ScheduledStart")
        try super.init(json: json, context: context)
        extra = unknownMembers(json, context, keys: Procedure.jsonKeys)
    }

    public override func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.modelArray("Steps", steps); w.optionalDate("Deadline", deadline); w.netEnum("Recurrence", recurrence)
        w.bool("RecurrenceSpawned", recurrenceSpawned); w.netEnum("Status", status); w.bool("IsJob", isJob)
        w.int("DurationMinutes", durationMinutes); w.optionalDate("ScheduledStart", scheduledStart)
        encodeBase(into: &w)
        return w.build(appending: extra)
    }
}

@MainActor @Observable
public final class ChecklistStep: JSONModel, SchedulableJob, Bucketable, @MainActor Identifiable {
    public var id: UUID
    public var title: String
    public var bucketIds: [UUID]
    public var done: Bool
    public var deadline: NetDateTime?
    public var isJob: Bool
    public var durationMinutes: Int
    public var scheduledStart: NetDateTime?
    public var taskIds: [UUID]
    public var equipmentIds: [UUID]
    public var container: Container
    @ObservationIgnored public var extra = JSONObject()

    /// [JsonIgnore] JobName.
    public var jobName: String { title }

    public static let jsonKeys = ["Id", "Title", "BucketIds", "Done", "Deadline", "IsJob",
                                  "DurationMinutes", "ScheduledStart", "TaskIds", "EquipmentIds", "Container"]

    public init(id: UUID = UUID(), title: String = "") {
        self.id = id; self.title = title; bucketIds = []; done = false; deadline = nil
        isJob = false; durationMinutes = 60; scheduledStart = nil; taskIds = []; equipmentIds = []
        container = Container()
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "ChecklistStep")
        id              = try r.guid("Id") ?? c.newGuid()
        title           = try r.string("Title") ?? ""
        bucketIds       = try r.guidArray("BucketIds") ?? []
        done            = try r.bool("Done") ?? false
        deadline        = try r.date("Deadline")
        isJob           = try r.bool("IsJob") ?? false
        durationMinutes = try r.int("DurationMinutes") ?? 60
        scheduledStart  = try r.date("ScheduledStart")
        taskIds         = try r.guidArray("TaskIds") ?? []
        equipmentIds    = try r.guidArray("EquipmentIds") ?? []
        container       = try r.model("Container", Container.self) ?? Container(id: c.newGuid())
        extra           = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("Title", title); w.guidArray("BucketIds", bucketIds); w.bool("Done", done)
        w.optionalDate("Deadline", deadline); w.bool("IsJob", isJob); w.int("DurationMinutes", durationMinutes)
        w.optionalDate("ScheduledStart", scheduledStart); w.guidArray("TaskIds", taskIds)
        w.guidArray("EquipmentIds", equipmentIds); w.model("Container", container)
        return w.build(appending: extra)
    }
}

/// Sidebar group (01 §4.2.11). `expanded` is round-trip only (UI expansion lives in `Ui.GroupExpanded`).
@MainActor @Observable
public final class ItemGroup: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var kind: ItemKind
    public var name: String
    public var expanded: Bool
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "Kind", "Name", "Expanded"]

    public init(id: UUID = UUID(), kind: ItemKind = .equipment, name: String = "", expanded: Bool = true) {
        self.id = id; self.kind = kind; self.name = name; self.expanded = expanded
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "ItemGroup")
        id = try r.guid("Id") ?? c.newGuid()
        kind = try r.netEnum("Kind", ItemKind.self) ?? .equipment
        name = try r.string("Name") ?? ""
        expanded = try r.bool("Expanded") ?? true
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.netEnum("Kind", kind); w.string("Name", name); w.bool("Expanded", expanded)
        return w.build(appending: extra)
    }
}
