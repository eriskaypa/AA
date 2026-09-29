// Spec: 01 §3.2 (null root → empty), App. A19, §4.10 (trash payload), 02 REPO-061 (DeepClone through JSON);
//       ARCHITECTURE.md §3.10.
import Foundation

@MainActor public enum ModelCodec {
    /// A JSON `null` root → empty `AppData()`; any other non-object root → `.notAnObject` (load failure).
    public static func decodeAppData(_ root: JSONValue, context: JSONDecodeContext) throws(JSONModelError) -> AppData {
        switch root {
        case .null: return AppData()
        case .object(let o): return try AppData(json: o, context: context)
        default: throw .notAnObject(path: "")
        }
    }

    public static func encodeAppData(_ data: AppData, options: JSONEncodeOptions = .dataFile) -> JSONValue {
        .object(data.toJSON(options: options))
    }

    /// Deep clone through JSON using the DYNAMIC type, so a TaskItem typed as HierarchyItem clones to a TaskItem
    /// with every key (own, base and extra) preserved.
    public static func deepClone<M: JSONModel>(_ model: M, context: JSONDecodeContext = .standard) -> M {
        let json = model.toJSON(options: .dataFile)
        do {
            return try type(of: model).init(json: json, context: context)
        } catch {
            // Unreachable for a model this codec just encoded; never crash — log and return a default instance.
            AALog.logger("model").error("deepClone failed: \(String(describing: error), privacy: .public)")
            return (try? type(of: model).init(json: JSONObject(), context: context)) ?? model
        }
    }
}

@MainActor public enum TrashPayload {
    /// Compact JSON text of the item's runtime type (01 §4.10), full subtree.
    public static func encode(_ item: HierarchyItem) -> String {
        (try? JSONWriter.string(.object(item.toJSON(options: .dataFile)))) ?? ""
    }

    public static func encode(_ crew: CrewMember) -> String {
        (try? JSONWriter.string(.object(crew.toJSON(options: .dataFile)))) ?? ""
    }

    /// Decodes with the concrete class named by `itemType` ("Equipment"|"Task"|"Procedure"|"Vessel"|"Crew");
    /// nil on any error.
    public static func decode(itemType: String, payload: String, context: JSONDecodeContext) -> AnyObject? {
        guard let root = try? JSONParser.parse(payload), case .object(let o) = root,
              let type = TrashItemType(rawValue: itemType) else { return nil }
        switch type {
        case .equipment: return try? Equipment(json: o, context: context)
        case .task: return try? TaskItem(json: o, context: context)
        case .procedure: return try? Procedure(json: o, context: context)
        case .vessel: return try? Vessel(json: o, context: context)
        case .crew: return try? CrewMember(json: o, context: context)
        }
    }
}
