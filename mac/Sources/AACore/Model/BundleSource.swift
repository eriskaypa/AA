// Spec: 01 §4.4 (source.json), §3.22 (WrittenLocal), App. B07/B08; ARCHITECTURE.md §4.12.
import Foundation

/// The identity/source stamp written into every bundle.
nonisolated public struct BundleSource: Sendable, Equatable {
    public var identity: String
    public var machine: String
    /// C# `default(DateTime)` when absent: written `"0001-01-01T00:00:00"`.
    public var writtenUtc: NetDateTime
    public var lastModified: NetDateTime?
    public var dataOnly: Bool
    public var extra: JSONObject

    public static let jsonKeys = ["Identity", "Machine", "WrittenUtc", "LastModified", "DataOnly"]

    public init(identity: String = "", machine: String = "", writtenUtc: NetDateTime = NetDateTime(ticks: 0, kind: .unspecified),
                lastModified: NetDateTime? = nil, dataOnly: Bool = false, extra: JSONObject = JSONObject()) {
        self.identity = identity; self.machine = machine; self.writtenUtc = writtenUtc
        self.lastModified = lastModified; self.dataOnly = dataOnly; self.extra = extra
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "BundleSource")
        identity = try r.string("Identity") ?? ""
        machine = try r.string("Machine") ?? ""
        writtenUtc = try r.date("WrittenUtc") ?? NetDateTime(ticks: 0, kind: .unspecified)
        lastModified = try r.date("LastModified")
        dataOnly = try r.bool("DataOnly") ?? false
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.string("Identity", identity); w.string("Machine", machine); w.date("WrittenUtc", writtenUtc)
        w.optionalDate("LastModified", lastModified); w.bool("DataOnly", dataOnly)
        return w.build(appending: extra)
    }

    /// `WrittenUtc.ToLocalTime()` as `yyyy-MM-dd HH:mm`, `""` when `WrittenUtc` is `default(DateTime)`.
    public var writtenLocal: String {
        writtenUtc.ticks == 0 ? "" : writtenUtc.toLocalTime().format(.isoMinute)
    }
}
