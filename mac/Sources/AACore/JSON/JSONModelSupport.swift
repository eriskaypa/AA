// Spec: 01 §4.1.2–4.1.10 (which properties are written, value encodings, missing keys/null → C# defaults),
//       DATA-024 (unknown members kept — on every object on the Mac), App. A05–A11; ARCHITECTURE.md §3.8.
import Foundation

public struct JSONDecodeContext: Sendable {
    public var zone: TimeZone = .current
    public var clock: AppClock = SystemClock()             // defaults: Added = Now, CreatedUtc = UtcNow …
    public var newGuid: @Sendable () -> UUID = { UUID() }  // tests inject deterministic ids
    public var path: [String] = []                         // for error messages ("Tasks[3].Subtasks[0].Deadline")

    public init(zone: TimeZone = .current, clock: AppClock = SystemClock(),
                newGuid: @escaping @Sendable () -> UUID = { UUID() }, path: [String] = []) {
        self.zone = zone; self.clock = clock; self.newGuid = newGuid; self.path = path
    }

    public static let standard = JSONDecodeContext()

    /// A child context whose path is extended by `component` (`"Tasks[3]"`, `"Container"`).
    public func appending(_ component: String) -> JSONDecodeContext {
        var c = self
        c.path.append(component)
        return c
    }

    func pathText(_ key: String) -> String { (path + [key]).joined(separator: ".") }
}

public enum JSONModelError: Error, Sendable, CustomStringConvertible, Equatable {
    case typeMismatch(path: String, expected: String)      // Windows would fail → load failure → safe mode
    case invalidGuid(path: String, text: String)
    case invalidDate(path: String, text: String)
    case notAnObject(path: String)

    public var description: String {
        switch self {
        case let .typeMismatch(path, expected): return "\(path): expected \(expected)"
        case let .invalidGuid(path, text): return "\(path): \"\(text)\" is not a valid GUID"
        case let .invalidDate(path, text): return "\(path): \"\(text)\" is not a valid date"
        case let .notAnObject(path): return "\(path.isEmpty ? "The document" : path): expected a JSON object"
        }
    }
}

/// Lock-protected collector of writer-side violations (e.g. an Int32 overflow that had to be clamped).
public final class JSONEncodeIssueLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    public init() {}
    public var issues: [String] { lock.lock(); defer { lock.unlock() }; return items }
    public func record(_ issue: String) { lock.lock(); items.append(issue); lock.unlock() }
}

public struct JSONEncodeOptions: Sendable {
    public var writeNulls: Bool = false                    // true only for .aasched.json (06 §4.5)
    public var includeExtra: Bool = true                   // false only for .aasched.json export (TV-OWN-11)
    public var zone: TimeZone = .current
    public var issueLog: JSONEncodeIssueLog? = nil          // serializeForSave passes one and fails the save if non-empty

    public init(writeNulls: Bool = false, includeExtra: Bool = true, zone: TimeZone = .current,
                issueLog: JSONEncodeIssueLog? = nil) {
        self.writeNulls = writeNulls; self.includeExtra = includeExtra; self.zone = zone; self.issueLog = issueLog
    }

    /// data.json / trash payloads / source.json.
    public static let dataFile = JSONEncodeOptions()
    /// `.aasched.json`: nulls written, declared keys only.
    public static let aasched = JSONEncodeOptions(writeNulls: true, includeExtra: false)
}

/// @MainActor protocol: model CLASSES conform plainly; the four value records conform from
/// `nonisolated public struct` declarations (SE-0449), so their inits and computed members stay usable off-main.
@MainActor public protocol JSONModel {
    /// Known keys in EMISSION order (derived first, then base).
    static var jsonKeys: [String] { get }
    init(json: JSONObject, context: JSONDecodeContext) throws(JSONModelError)
    func toJSON(options: JSONEncodeOptions) -> JSONObject
    /// Unknown members, emitted after known keys.
    var extra: JSONObject { get set }
}

/// Reading helpers: nil = absent OR JSON null (→ the caller applies the C# default). A value of the wrong JSON
/// type for a known key throws (Windows would fail the load).
public struct JSONFieldReader: Sendable {
    public let object: JSONObject
    public let context: JSONDecodeContext
    public let type: String

    public init(_ object: JSONObject, context: JSONDecodeContext, type: String) {
        self.object = object; self.context = context; self.type = type
    }

    private func mismatch(_ key: String, _ expected: String) -> JSONModelError {
        .typeMismatch(path: context.pathText(key), expected: expected)
    }

    public func string(_ key: String) throws(JSONModelError) -> String? {
        guard let v = object[key] else { return nil }
        guard let s = v.stringValue else { throw mismatch(key, "a string") }
        return s
    }

    public func bool(_ key: String) throws(JSONModelError) -> Bool? {
        guard let v = object[key] else { return nil }
        guard case .bool(let b) = v else { throw mismatch(key, "true or false") }
        return b
    }

    /// Integer lexeme within Int32 only (`60.0`, `6E1`, `2147483648` → type mismatch, parity with STJ).
    public func int(_ key: String) throws(JSONModelError) -> Int? {
        guard let v = object[key] else { return nil }
        guard case .number(let n) = v, let i = n.intValue else { throw mismatch(key, "a 32-bit integer") }
        return i
    }

    public func double(_ key: String) throws(JSONModelError) -> Double? {
        guard let v = object[key] else { return nil }
        guard case .number(let n) = v, let d = n.doubleValue, d.isFinite else { throw mismatch(key, "a finite number") }
        return d
    }

    public func guid(_ key: String) throws(JSONModelError) -> UUID? {
        guard let v = object[key] else { return nil }
        guard let s = v.stringValue else { throw .invalidGuid(path: context.pathText(key), text: v.idText ?? "") }
        guard let g = UUID(netString: s) else { throw .invalidGuid(path: context.pathText(key), text: s) }
        return g
    }

    public func date(_ key: String) throws(JSONModelError) -> NetDateTime? {
        guard let v = object[key] else { return nil }
        guard let s = v.stringValue else { throw .invalidDate(path: context.pathText(key), text: v.idText ?? "") }
        guard let d = NetDateTime(parsing: s, zone: context.zone) else {
            throw .invalidDate(path: context.pathText(key), text: s)
        }
        return d
    }

    /// Int32 integer lexeme only; undefined values inside Int32 load and round-trip.
    public func netEnum<E: NetIntEnum>(_ key: String, _ type: E.Type) throws(JSONModelError) -> E? {
        guard let i = try int(key) else { return nil }
        return E(rawValue: i)
    }

    public func guidArray(_ key: String) throws(JSONModelError) -> [UUID]? {
        guard let v = object[key] else { return nil }
        guard case .array(let items) = v else { throw mismatch(key, "an array of GUIDs") }
        var out: [UUID] = []
        out.reserveCapacity(items.count)
        for (n, item) in items.enumerated() {
            let p = context.pathText("\(key)[\(n)]")
            guard let s = item.stringValue else { throw .invalidGuid(path: p, text: item.idText ?? "null") }
            guard let g = UUID(netString: s) else { throw .invalidGuid(path: p, text: s) }
            out.append(g)
        }
        return out
    }

    /// A JSON null element reads as `""` (Mac leniency; a Swift `[String]` cannot hold null).
    public func stringArray(_ key: String) throws(JSONModelError) -> [String]? {
        guard let v = object[key] else { return nil }
        guard case .array(let items) = v else { throw mismatch(key, "an array of strings") }
        var out: [String] = []
        out.reserveCapacity(items.count)
        for (n, item) in items.enumerated() {
            if item.isNull { out.append(""); continue }
            guard let s = item.stringValue else { throw mismatch("\(key)[\(n)]", "a string") }
            out.append(s)
        }
        return out
    }

    /// A JSON null value reads as `""` (Mac leniency, as for string arrays).
    public func stringMap(_ key: String) throws(JSONModelError) -> OrderedMap<String>? {
        guard let v = object[key] else { return nil }
        guard case .object(let o) = v else { throw mismatch(key, "an object of strings") }
        var m = OrderedMap<String>()
        for (k, item) in o {
            if item.isNull { m[k] = ""; continue }
            guard let s = item.stringValue else { throw mismatch("\(key).\(k)", "a string") }
            m[k] = s
        }
        return m
    }

    public func boolMap(_ key: String) throws(JSONModelError) -> OrderedMap<Bool>? {
        guard let v = object[key] else { return nil }
        guard case .object(let o) = v else { throw mismatch(key, "an object of booleans") }
        var m = OrderedMap<Bool>()
        for (k, item) in o {
            guard case .bool(let b) = item else { throw mismatch("\(key).\(k)", "true or false") }
            m[k] = b
        }
        return m
    }

    @MainActor
    public func model<M: JSONModel>(_ key: String, _ type: M.Type) throws(JSONModelError) -> M? {
        guard let v = object[key] else { return nil }
        guard case .object(let o) = v else { throw .notAnObject(path: context.pathText(key)) }
        return try M(json: o, context: context.appending(key))
    }

    /// Elements that are JSON null are skipped (a Swift array of models cannot hold null).
    @MainActor
    public func modelArray<M: JSONModel>(_ key: String, _ type: M.Type) throws(JSONModelError) -> [M]? {
        guard let v = object[key] else { return nil }
        guard case .array(let items) = v else { throw mismatch(key, "an array of objects") }
        var out: [M] = []
        out.reserveCapacity(items.count)
        for (n, item) in items.enumerated() {
            if item.isNull { continue }
            let comp = "\(key)[\(n)]"
            guard case .object(let o) = item else { throw .notAnObject(path: context.pathText(comp)) }
            out.append(try M(json: o, context: context.appending(comp)))
        }
        return out
    }

    /// Pairs whose key ∉ knownKeys ∪ legacyKeys (ordinal), raw and in document order.
    public func unknownMembers(knownKeys: [String], legacyKeys: [String] = []) -> JSONObject {
        var known = Set<Ordinal.Key>()
        for k in knownKeys { known.insert(Ordinal.Key(k)) }
        for k in legacyKeys { known.insert(Ordinal.Key(k)) }
        var o = JSONObject()
        for (k, v) in object where !known.contains(Ordinal.Key(k)) { o.set(k, v) }
        return o
    }
}

public struct JSONObjectBuilder {
    public let options: JSONEncodeOptions
    private var object = JSONObject()

    public init(_ options: JSONEncodeOptions) { self.options = options }

    public mutating func string(_ key: String, _ v: String) { object.set(key, .string(v)) }

    /// Omitted when nil (JSON null when `writeNulls`).
    public mutating func optionalString(_ key: String, _ v: String?) {
        if let v { object.set(key, .string(v)) } else if options.writeNulls { object.set(key, .null) }
    }

    public mutating func bool(_ key: String, _ v: Bool) { object.set(key, .bool(v)) }

    /// Outside Int32 → clamps AND records an issue (the save then fails, §3.8 rule 2).
    public mutating func int(_ key: String, _ v: Int) {
        object.set(key, .number(JSONNumber(clampInt32(key, v))))
    }

    private func clampInt32(_ key: String, _ v: Int) -> Int {
        if v < Int(Int32.min) || v > Int(Int32.max) {
            options.issueLog?.record("\(key): \(v) is outside Int32")
            return min(max(v, Int(Int32.min)), Int(Int32.max))
        }
        return v
    }

    /// NaN/∞ → key skipped.
    public mutating func double(_ key: String, _ v: Double) {
        if let n = JSONNumber(v) { object.set(key, .number(n)) }
    }

    public mutating func optionalDouble(_ key: String, _ v: Double?) {
        if let v { double(key, v) } else if options.writeNulls { object.set(key, .null) }
    }

    public mutating func guid(_ key: String, _ v: UUID) { object.set(key, .string(v.netString)) }

    public mutating func optionalGuid(_ key: String, _ v: UUID?) {
        if let v { guid(key, v) } else if options.writeNulls { object.set(key, .null) }
    }

    /// Emits `.rawString(v.jsonString(zone:))` so offsets keep a literal `+` like STJ's typed DateTime.
    public mutating func date(_ key: String, _ v: NetDateTime) {
        object.set(key, .rawString(v.jsonString(zone: options.zone)))
    }

    public mutating func optionalDate(_ key: String, _ v: NetDateTime?) {
        if let v { date(key, v) } else if options.writeNulls { object.set(key, .null) }
    }

    public mutating func netEnum<E: NetIntEnum>(_ key: String, _ v: E) {
        object.set(key, .number(JSONNumber(clampInt32(key, v.rawValue))))
    }

    public mutating func guidArray(_ key: String, _ v: [UUID]) {
        object.set(key, .array(v.map { .string($0.netString) }))
    }

    public mutating func stringArray(_ key: String, _ v: [String]) {
        object.set(key, .array(v.map { .string($0) }))
    }

    public mutating func stringMap(_ key: String, _ v: OrderedMap<String>) {
        var o = JSONObject()
        for (k, s) in v { o.set(k, .string(s)) }
        object.set(key, .object(o))
    }

    public mutating func boolMap(_ key: String, _ v: OrderedMap<Bool>) {
        var o = JSONObject()
        for (k, b) in v { o.set(k, .bool(b)) }
        object.set(key, .object(o))
    }

    @MainActor
    public mutating func model<M: JSONModel>(_ key: String, _ v: M) {
        object.set(key, .object(v.toJSON(options: options)))
    }

    @MainActor
    public mutating func modelArray<M: JSONModel>(_ key: String, _ v: [M]) {
        object.set(key, .array(v.map { .object($0.toJSON(options: options)) }))
    }

    /// Sets an arbitrary value (used for raw subtrees).
    public mutating func value(_ key: String, _ v: JSONValue) { object.set(key, v) }

    /// Extra keys that collide with known keys are dropped; nothing is appended when `!includeExtra`.
    public func build(appending extra: JSONObject) -> JSONObject {
        var o = object
        if options.includeExtra {
            for (k, v) in extra where !o.containsKey(k) { o.set(k, v) }
        }
        return o
    }
}
