// Spec: 01 §4.2.16–4.2.17, §4.10 (trash payload), §3.22 (DeletedLocal, Display, TimeUtc, TimeLocal);
//       08 §4.6 (Activity-log CSV LocalTime); ARCHITECTURE.md §4.7.
import Foundation

public enum TrashItemType: String, Sendable, CaseIterable {
    case equipment = "Equipment", task = "Task", procedure = "Procedure", vessel = "Vessel", crew = "Crew"
}

nonisolated public struct TrashedItem: JSONModel, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// "Equipment" | "Task" | "Procedure" | "Vessel" | "Crew".
    public var itemType: String
    public var itemId: UUID
    public var batchId: UUID
    public var name: String
    public var kindLabel: String
    public var deletedUtc: NetDateTime
    public var payloadJson: String
    public var extra: JSONObject

    public static let jsonKeys = ["Id", "ItemType", "ItemId", "BatchId", "Name", "KindLabel", "DeletedUtc", "PayloadJson"]

    public init(id: UUID = UUID(), itemType: String = "", itemId: UUID = .netEmpty, batchId: UUID = .netEmpty,
                name: String = "", kindLabel: String = "", deletedUtc: NetDateTime = .utcNow(),
                payloadJson: String = "", extra: JSONObject = JSONObject()) {
        self.id = id; self.itemType = itemType; self.itemId = itemId; self.batchId = batchId; self.name = name
        self.kindLabel = kindLabel; self.deletedUtc = deletedUtc; self.payloadJson = payloadJson; self.extra = extra
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "TrashedItem")
        id = try r.guid("Id") ?? c.newGuid()
        itemType = try r.string("ItemType") ?? ""
        itemId = try r.guid("ItemId") ?? .netEmpty
        batchId = try r.guid("BatchId") ?? .netEmpty
        name = try r.string("Name") ?? ""
        kindLabel = try r.string("KindLabel") ?? ""
        deletedUtc = try r.date("DeletedUtc") ?? c.clock.utcNow()
        payloadJson = try r.string("PayloadJson") ?? ""
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("ItemType", itemType); w.guid("ItemId", itemId); w.guid("BatchId", batchId)
        w.string("Name", name); w.string("KindLabel", kindLabel); w.date("DeletedUtc", deletedUtc)
        w.string("PayloadJson", payloadJson)
        return w.build(appending: extra)
    }

    public var type: TrashItemType? { TrashItemType(rawValue: itemType) }

    /// `DeletedUtc.ToLocalTime()` as `yyyy-MM-dd HH:mm` (an Unspecified stamp is converted as UTC).
    public var deletedLocal: String { deletedUtc.toLocalTime().format(.isoMinute) }

    /// `"{Name or (unnamed)}   ·   {KindLabel}   ·   deleted {local yyyy-MM-dd HH:mm}"`.
    public var display: String {
        "\(name.isEmpty ? "(unnamed)" : name)   \u{00B7}   \(kindLabel)   \u{00B7}   deleted \(deletedLocal)"
    }
}

nonisolated public struct LogEntry: JSONModel, Hashable, Sendable {
    public var timestampUtc: NetDateTime
    /// "Added" / "Removed".
    public var action: String
    public var kind: String
    public var name: String
    public var detail: String
    public var extra: JSONObject

    public static let jsonKeys = ["TimestampUtc", "Action", "Kind", "Name", "Detail"]

    public init(timestampUtc: NetDateTime = .utcNow(), action: String = "", kind: String = "", name: String = "",
                detail: String = "", extra: JSONObject = JSONObject()) {
        self.timestampUtc = timestampUtc; self.action = action; self.kind = kind; self.name = name
        self.detail = detail; self.extra = extra
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "LogEntry")
        timestampUtc = try r.date("TimestampUtc") ?? c.clock.utcNow()
        action = try r.string("Action") ?? ""
        kind = try r.string("Kind") ?? ""
        name = try r.string("Name") ?? ""
        detail = try r.string("Detail") ?? ""
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.date("TimestampUtc", timestampUtc); w.string("Action", action); w.string("Kind", kind)
        w.string("Name", name); w.string("Detail", detail)
        return w.build(appending: extra)
    }

    /// `yyyy-MM-dd HH:mm:ss 'UTC'` of the stored wall clock.
    public var timeUtc: String { timestampUtc.format(.isoSecond) + " UTC" }
    /// `TimestampUtc.ToLocalTime()` as `yyyy-MM-dd HH:mm:ss`.
    public var timeLocal: String { timestampUtc.toLocalTime().format(.isoSecond) }
}
