// Spec: 01 §4.2.3 Container, §4.2.4 FileItem, §4.11 (rich text is opaque), §3.22 / 05 CONT-094 (SourceLabel);
//       ARCHITECTURE.md §4.2.
import Foundation
import Observation

@MainActor @Observable
public final class FileItem: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var name: String
    /// `files/<32hex>_<name>` | absolute/UNC | URL; never rewritten if `linkInPlace`/`isLink`.
    public var path: String
    public var kind: FileKind
    public var added: NetDateTime
    public var isLink: Bool
    public var linkInPlace: Bool
    public var linkedItemIds: [UUID]
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "Name", "Path", "Kind", "Added", "IsLink", "LinkInPlace", "LinkedItemIds"]

    public init(id: UUID = UUID(), name: String = "", path: String = "", kind: FileKind = .document,
                added: NetDateTime = .now(), isLink: Bool = false, linkInPlace: Bool = false, linkedItemIds: [UUID] = []) {
        self.id = id; self.name = name; self.path = path; self.kind = kind; self.added = added
        self.isLink = isLink; self.linkInPlace = linkInPlace; self.linkedItemIds = linkedItemIds
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "FileItem")
        id = try r.guid("Id") ?? c.newGuid()
        name = try r.string("Name") ?? ""
        path = try r.string("Path") ?? ""
        kind = try r.netEnum("Kind", FileKind.self) ?? .document
        added = try r.date("Added") ?? c.clock.now()
        isLink = try r.bool("IsLink") ?? false
        linkInPlace = try r.bool("LinkInPlace") ?? false
        linkedItemIds = try r.guidArray("LinkedItemIds") ?? []
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("Name", name); w.string("Path", path); w.netEnum("Kind", kind)
        w.date("Added", added); w.bool("IsLink", isLink); w.bool("LinkInPlace", linkInPlace)
        w.guidArray("LinkedItemIds", linkedItemIds)
        return w.build(appending: extra)
    }

    /// 05 CONT-094 / 01 §3.22: `Web link` | `Live` | `Copy`.
    public var sourceLabel: String { isLink ? "Web link" : linkInPlace ? "Live" : "Copy" }
}

@MainActor @Observable
public final class Container: JSONModel, @MainActor Identifiable {
    public var id: UUID
    /// Opaque WPF XAML (or a legacy `enc:` blob); never rewritten unless the user edited (01 §4.11).
    public var richTextXaml: String
    public var files: [FileItem]
    public var sharedWithContainerIds: [UUID]
    public var isLocked: Bool
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "RichTextXaml", "Files", "SharedWithContainerIds", "IsLocked"]

    public init(id: UUID = UUID(), richTextXaml: String = "", files: [FileItem] = [],
                sharedWithContainerIds: [UUID] = [], isLocked: Bool = false) {
        self.id = id; self.richTextXaml = richTextXaml; self.files = files
        self.sharedWithContainerIds = sharedWithContainerIds; self.isLocked = isLocked
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "Container")
        id = try r.guid("Id") ?? c.newGuid()
        richTextXaml = try r.string("RichTextXaml") ?? ""
        files = try r.modelArray("Files", FileItem.self) ?? []
        sharedWithContainerIds = try r.guidArray("SharedWithContainerIds") ?? []
        isLocked = try r.bool("IsLocked") ?? false
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("RichTextXaml", richTextXaml); w.modelArray("Files", files)
        w.guidArray("SharedWithContainerIds", sharedWithContainerIds); w.bool("IsLocked", isLocked)
        return w.build(appending: extra)
    }
}
