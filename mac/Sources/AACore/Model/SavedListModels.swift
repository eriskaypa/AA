// Spec: 01 §4.2.13–4.2.15, §3.22 (display strings); ARCHITECTURE.md §4.6.
import Foundation
import Observation

/// One item of a saved list (no Id; identified in memory by `rowID`).
@MainActor @Observable
public final class ChecklistTemplateItem: JSONModel, @MainActor Identifiable {
    public var title: String
    public var durationMinutes: Int
    public var isJob: Bool
    public var container: Container
    @ObservationIgnored public var extra = JSONObject()
    /// In-memory identity (not persisted).
    @ObservationIgnored public let rowID = UUID()
    public var id: UUID { rowID }

    public static let jsonKeys = ["Title", "DurationMinutes", "IsJob", "Container"]

    public init(title: String = "", durationMinutes: Int = 60, isJob: Bool = false, container: Container? = nil) {
        self.title = title; self.durationMinutes = durationMinutes; self.isJob = isJob; self.container = container ?? Container()
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "ChecklistTemplateItem")
        title = try r.string("Title") ?? ""
        durationMinutes = try r.int("DurationMinutes") ?? 60
        isJob = try r.bool("IsJob") ?? false
        container = try r.model("Container", Container.self) ?? Container(id: c.newGuid())
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.string("Title", title); w.int("DurationMinutes", durationMinutes); w.bool("IsJob", isJob)
        w.model("Container", container)
        return w.build(appending: extra)
    }
}

@MainActor @Observable
public final class ChecklistTemplate: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var name: String
    public var items: [ChecklistTemplateItem]
    public var createdUtc: NetDateTime
    public var groupId: UUID?
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "Name", "Items", "CreatedUtc", "GroupId"]

    public init(id: UUID = UUID(), name: String = "", items: [ChecklistTemplateItem] = [],
                createdUtc: NetDateTime = .utcNow(), groupId: UUID? = nil) {
        self.id = id; self.name = name; self.items = items; self.createdUtc = createdUtc; self.groupId = groupId
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "ChecklistTemplate")
        id = try r.guid("Id") ?? c.newGuid()
        name = try r.string("Name") ?? ""
        items = try r.modelArray("Items", ChecklistTemplateItem.self) ?? []
        createdUtc = try r.date("CreatedUtc") ?? c.clock.utcNow()
        groupId = try r.guid("GroupId")
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("Name", name); w.modelArray("Items", items); w.date("CreatedUtc", createdUtc)
        w.optionalGuid("GroupId", groupId)
        return w.build(appending: extra)
    }

    /// `"{Name or (unnamed)}  ·  {n} item{s}"`.
    public var display: String {
        "\(name.isEmpty ? "(unnamed)" : name)  \u{00B7}  \(items.count) item\(items.count == 1 ? "" : "s")"
    }
}

@MainActor @Observable
public final class ListGroup: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var name: String
    public var createdUtc: NetDateTime
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "Name", "CreatedUtc"]

    public init(id: UUID = UUID(), name: String = "", createdUtc: NetDateTime = .utcNow()) {
        self.id = id; self.name = name; self.createdUtc = createdUtc
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "ListGroup")
        id = try r.guid("Id") ?? c.newGuid()
        name = try r.string("Name") ?? ""
        createdUtc = try r.date("CreatedUtc") ?? c.clock.utcNow()
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("Name", name); w.date("CreatedUtc", createdUtc)
        return w.build(appending: extra)
    }
}

@MainActor @Observable
public final class ScheduleEntry: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var title: String
    public var kind: ScheduleKind
    /// Linked Task/Procedure/Equipment (nil for a free-text note; written as null under `.aasched`).
    public var refId: UUID?
    /// `yyyy-MM-dd`.
    public var date: String
    /// `HH:mm`.
    public var time: String
    public var endDate: String
    public var endTime: String
    public var done: Bool
    public var notes: String
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "Title", "Kind", "RefId", "Date", "Time", "EndDate", "EndTime", "Done", "Notes"]

    public init(id: UUID = UUID(), title: String = "", kind: ScheduleKind = .note, refId: UUID? = nil,
                date: String = "", time: String = "", endDate: String = "", endTime: String = "",
                done: Bool = false, notes: String = "") {
        self.id = id; self.title = title; self.kind = kind; self.refId = refId; self.date = date; self.time = time
        self.endDate = endDate; self.endTime = endTime; self.done = done; self.notes = notes
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "ScheduleEntry")
        id = try r.guid("Id") ?? c.newGuid()
        title = try r.string("Title") ?? ""
        kind = try r.netEnum("Kind", ScheduleKind.self) ?? .note
        refId = try r.guid("RefId")
        date = try r.string("Date") ?? ""
        time = try r.string("Time") ?? ""
        endDate = try r.string("EndDate") ?? ""
        endTime = try r.string("EndTime") ?? ""
        done = try r.bool("Done") ?? false
        notes = try r.string("Notes") ?? ""
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("Title", title); w.netEnum("Kind", kind); w.optionalGuid("RefId", refId)
        w.string("Date", date); w.string("Time", time); w.string("EndDate", endDate); w.string("EndTime", endTime)
        w.bool("Done", done); w.string("Notes", notes)
        return w.build(appending: extra)
    }

    /// `CrewMember.parseDate(Date)`.
    public var when: NetDateTime? { CrewMember.parseDate(date) }
    /// Task `✓`, Procedure `📋`, Equipment `⚙`, else `•`.
    public var kindIcon: String {
        switch kind {
        case .task: return "\u{2713}"
        case .procedure: return "\u{1F4CB}"
        case .equipment: return "\u{2699}"
        default: return "\u{2022}"
        }
    }
    /// `"{Date} {Time}".Trim()`.
    public var whenDisplay: String { NetText.trim("\(date) \(time)") }
}

@MainActor @Observable
public final class ScheduleTemplate: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var name: String
    public var vesselId: UUID?
    public var vesselName: String
    public var entries: [ScheduleEntry]
    public var createdUtc: NetDateTime
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "Name", "VesselId", "VesselName", "Entries", "CreatedUtc"]

    public init(id: UUID = UUID(), name: String = "", vesselId: UUID? = nil, vesselName: String = "",
                entries: [ScheduleEntry] = [], createdUtc: NetDateTime = .utcNow()) {
        self.id = id; self.name = name; self.vesselId = vesselId; self.vesselName = vesselName
        self.entries = entries; self.createdUtc = createdUtc
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "ScheduleTemplate")
        id = try r.guid("Id") ?? c.newGuid()
        name = try r.string("Name") ?? ""
        vesselId = try r.guid("VesselId")
        vesselName = try r.string("VesselName") ?? ""
        entries = try r.modelArray("Entries", ScheduleEntry.self) ?? []
        createdUtc = try r.date("CreatedUtc") ?? c.clock.utcNow()
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("Name", name); w.optionalGuid("VesselId", vesselId)
        w.string("VesselName", vesselName); w.modelArray("Entries", entries); w.date("CreatedUtc", createdUtc)
        return w.build(appending: extra)
    }

    /// `"{Name or (unnamed)}  ·  {n} entr{y|ies}"` + (`"  ·  {VesselName}"` when set).
    public var display: String {
        "\(name.isEmpty ? "(unnamed)" : name)  \u{00B7}  \(entries.count) entr\(entries.count == 1 ? "y" : "ies")"
            + (vesselName.isEmpty ? "" : "  \u{00B7}  \(vesselName)")
    }
}

@MainActor @Observable
public final class QuickBucket: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var name: String
    public var category: String
    public var createdUtc: NetDateTime
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "Name", "Category", "CreatedUtc"]

    public init(id: UUID = UUID(), name: String = "", category: String = "", createdUtc: NetDateTime = .utcNow()) {
        self.id = id; self.name = name; self.category = category; self.createdUtc = createdUtc
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "QuickBucket")
        id = try r.guid("Id") ?? c.newGuid()
        name = try r.string("Name") ?? ""
        category = try r.string("Category") ?? ""
        createdUtc = try r.date("CreatedUtc") ?? c.clock.utcNow()
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("Name", name); w.string("Category", category); w.date("CreatedUtc", createdUtc)
        return w.build(appending: extra)
    }

    /// `Category != "" ? "{Name}  ·  {Category}" : (Name != "" ? Name : "(unnamed)")`.
    public var display: String {
        category.isEmpty ? (name.isEmpty ? "(unnamed)" : name) : "\(name)  \u{00B7}  \(category)"
    }
}
