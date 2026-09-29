// Spec: 01 §4.2.2 (base keys emitted after each subclass's own keys), §3.20 / DATA-132 / 07 VIEW-154 (legacy
//       BucketId), §4.8 (lock fields); ARCHITECTURE.md §3.9, §4.3.
import Foundation
import Observation

/// Abstract base of Equipment / TaskItem / Procedure / Vessel (never instantiated directly).
@MainActor @Observable
public class HierarchyItem: JSONModel, Bucketable, @MainActor Identifiable {
    public var id: UUID
    public var name: String
    public var description: String
    public var container: Container
    public var relatedIds: [UUID]
    public var tags: [String]
    public var groupId: UUID?
    public var bucketIds: [UUID]
    public var lockHash: String?
    public var lockSalt: String?
    public var lockHint: String?
    @ObservationIgnored public var extra = JSONObject()

    /// Base keys in 01 §4.2.2 order.
    public class var baseJSONKeys: [String] {
        ["Id", "Name", "Description", "Container", "RelatedIds", "Tags", "GroupId", "BucketIds",
         "LockHash", "LockSalt", "LockHint"]
    }
    /// Satisfies the protocol's static requirement; subclasses prepend their own keys.
    public class var jsonKeys: [String] { baseJSONKeys }

    /// The item's kind (not persisted — implied by the array it lives in).
    public var kind: ItemKind { .equipment }

    /// `LockHash` and `LockSalt` both non-empty.
    public var isLockProtected: Bool { !(lockHash ?? "").isEmpty && !(lockSalt ?? "").isEmpty }

    public init(id: UUID = UUID(), name: String = "") {
        self.id = id; self.name = name; description = ""; container = Container(); relatedIds = []; tags = []
        groupId = nil; bucketIds = []; lockHash = nil; lockSalt = nil; lockHint = nil
    }

    /// Decodes the base keys; each final subclass sets `extra` afterwards from its full key list.
    public required init(json: JSONObject, context: JSONDecodeContext) throws(JSONModelError) {
        id = UUID.netEmpty; name = ""; description = ""; container = Container(); relatedIds = []; tags = []
        groupId = nil; bucketIds = []; lockHash = nil; lockSalt = nil; lockHint = nil
        try decodeBase(JSONFieldReader(json, context: context, type: "HierarchyItem"))
    }

    public func decodeBase(_ r: JSONFieldReader) throws(JSONModelError) {
        let c = r.context
        id = try r.guid("Id") ?? c.newGuid()
        name = try r.string("Name") ?? ""
        description = try r.string("Description") ?? ""
        container = try r.model("Container", Container.self) ?? Container(id: c.newGuid())
        relatedIds = try r.guidArray("RelatedIds") ?? []
        tags = try r.stringArray("Tags") ?? []
        groupId = try r.guid("GroupId")
        var buckets = try r.guidArray("BucketIds") ?? []
        // Legacy single BucketId (01 §3.20): JSON null → ignored; a valid GUID not yet in BucketIds → appended,
        // regardless of key order; any other value → load failure. Never written, never kept in `extra`.
        if let legacy = r.object.rawValue(forKey: "BucketId"), !legacy.isNull {
            guard let s = legacy.stringValue, let g = UUID(netString: s) else {
                throw .invalidGuid(path: c.pathText("BucketId"), text: legacy.idText ?? "")
            }
            if !buckets.contains(g) { buckets.append(g) }
        }
        bucketIds = buckets
        lockHash = try r.string("LockHash")
        lockSalt = try r.string("LockSalt")
        lockHint = try r.string("LockHint")
    }

    public func encodeBase(into w: inout JSONObjectBuilder) {
        w.guid("Id", id); w.string("Name", name); w.string("Description", description)
        w.model("Container", container); w.guidArray("RelatedIds", relatedIds); w.stringArray("Tags", tags)
        w.optionalGuid("GroupId", groupId); w.guidArray("BucketIds", bucketIds)
        w.optionalString("LockHash", lockHash); w.optionalString("LockSalt", lockSalt)
        w.optionalString("LockHint", lockHint)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        encodeBase(into: &w)
        return w.build(appending: extra)
    }

    /// Unknown members of a subclass object: every key not in the subclass's full list, minus the legacy key.
    func unknownMembers(_ json: JSONObject, _ context: JSONDecodeContext, keys: [String]) -> JSONObject {
        JSONFieldReader(json, context: context, type: "HierarchyItem")
            .unknownMembers(knownKeys: keys, legacyKeys: ["BucketId"])
    }
}

@MainActor @Observable
public final class Equipment: HierarchyItem {
    public var procedureIds: [UUID]
    public var taskIds: [UUID]
    public var components: [Component]

    public override class var jsonKeys: [String] { ["ProcedureIds", "TaskIds", "Components"] + baseJSONKeys }
    public override var kind: ItemKind { .equipment }

    public override init(id: UUID = UUID(), name: String = "") {
        procedureIds = []; taskIds = []; components = []
        super.init(id: id, name: name)
    }

    public required init(json: JSONObject, context: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(json, context: context, type: "Equipment")
        procedureIds = try r.guidArray("ProcedureIds") ?? []
        taskIds = try r.guidArray("TaskIds") ?? []
        components = try r.modelArray("Components", Component.self) ?? []
        try super.init(json: json, context: context)
        extra = unknownMembers(json, context, keys: Equipment.jsonKeys)
    }

    public override func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guidArray("ProcedureIds", procedureIds); w.guidArray("TaskIds", taskIds)
        w.modelArray("Components", components)
        encodeBase(into: &w)
        return w.build(appending: extra)
    }
}

@MainActor @Observable
public final class Component: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var name: String
    /// One-line notes.
    public var notes: String
    public var container: Container
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "Name", "Notes", "Container"]

    public init(id: UUID = UUID(), name: String = "", notes: String = "", container: Container? = nil) {
        self.id = id; self.name = name; self.notes = notes; self.container = container ?? Container()
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "Component")
        id = try r.guid("Id") ?? c.newGuid()
        name = try r.string("Name") ?? ""
        notes = try r.string("Notes") ?? ""
        container = try r.model("Container", Container.self) ?? Container(id: c.newGuid())
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("Name", name); w.string("Notes", notes); w.model("Container", container)
        return w.build(appending: extra)
    }
}
