// Spec: 01 §4.1 (System.Text.Json contract), 13 §3.11.9–3.11.10 (DeepEquals, JsonNode accessors), OC-01/OC-02;
//       ARCHITECTURE.md §3.1 — ordered JSON tree with ordinal strings and number lexemes.
import Foundation

/// A JSON number held as its lexeme: `==`/hash by lexeme (ordinal), so `1` ≠ `1.0` ≠ `1e0` and `-0` ≠ `0`.
public struct JSONNumber: Sendable, Hashable, CustomStringConvertible {
    /// Raw text as read, or the .NET-formatted text when created.
    public let lexeme: String

    public init(lexeme: String) { self.lexeme = lexeme }
    public init(_ value: Int) { lexeme = String(value) }
    public init(_ value: Int64) { lexeme = String(value) }
    /// `NetNumberText.shortest`; nil for NaN/±Infinity (01 §4.1.6).
    public init?(_ value: Double) {
        guard let s = NetNumberText.shortest(value) else { return nil }
        lexeme = s
    }

    public var doubleValue: Double? { Double(lexeme) }

    /// Integer lexeme only (optional `-`, digits); `5.0` / `5E0` → nil.
    public var int64Value: Int64? {
        guard JSONNumber.isIntegerLexeme(lexeme) else { return nil }
        return Int64(lexeme)
    }

    /// Integer lexeme within Int32.min…Int32.max, else nil.
    public var int32Value: Int32? {
        guard let v = int64Value, v >= Int64(Int32.min), v <= Int64(Int32.max) else { return nil }
        return Int32(v)
    }

    /// C# `int` fields and enums are Int32.
    public var intValue: Int? { int32Value.map(Int.init) }

    public var description: String { lexeme }

    static func isIntegerLexeme(_ s: String) -> Bool {
        var it = s.utf8.makeIterator()
        guard var c = it.next() else { return false }
        if c == 0x2D { guard let n = it.next() else { return false }; c = n }
        guard c >= 0x30, c <= 0x39 else { return false }
        while let n = it.next() { guard n >= 0x30, n <= 0x39 else { return false } }
        return true
    }

    public static func == (a: JSONNumber, b: JSONNumber) -> Bool { Ordinal.equals(a.lexeme, b.lexeme) }
    public func hash(into h: inout Hasher) { Ordinal.hash(lexeme, into: &h) }
}

public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(JSONNumber)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)
    /// WRITER-ONLY. A string emitted between quotes **without escaping** (the caller guarantees printable ASCII
    /// with no `"` or `\`). Produced only by `JSONObjectBuilder.date/optionalDate` to reproduce STJ's typed
    /// `DateTime` output (offsets keep a literal `+`). The parser never produces it. Everywhere else it behaves
    /// exactly like `.string` with the same text (accessors, `==`, hash, `deepEquals`, `idText`).
    case rawString(String)

    public var objectValue: JSONObject? { if case .object(let o) = self { return o }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var stringValue: String? {
        switch self {
        case .string(let s), .rawString(let s): return s
        default: return nil
        }
    }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var numberValue: JSONNumber? { if case .number(let n) = self { return n }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }

    /// FlashChangeSet id text: string → raw, number → lexeme, bool → "true"/"false" (13 §3.11.10);
    /// null → nil; objects/arrays → compact JSON text.
    public var idText: String? {
        switch self {
        case .null: return nil
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n.lexeme
        case .string(let s), .rawString(let s): return s
        case .array, .object: return try? JSONWriter.string(self)
        }
    }

    /// 13 §3.11.9 DeepEquals exactly: nil (absent or JSON null) handling; objects by count incl. null-valued keys
    /// and key lookup (order ignored); arrays ordered; numbers by lexeme; strings ordinally; string ≠ number.
    public static func deepEquals(_ a: JSONValue?, _ b: JSONValue?) -> Bool {
        let x: JSONValue? = (a?.isNull ?? true) ? nil : a
        let y: JSONValue? = (b?.isNull ?? true) ? nil : b
        guard let x, let y else { return x == nil && y == nil }
        switch (x, y) {
        case let (.object(oa), .object(ob)):
            guard oa.count == ob.count else { return false }
            for (k, v) in oa {
                guard ob.containsKey(k), deepEquals(v, ob.rawValue(forKey: k)) else { return false }
            }
            return true
        case let (.array(aa), .array(ab)):
            guard aa.count == ab.count else { return false }
            for (p, q) in zip(aa, ab) where !deepEquals(p, q) { return false }
            return true
        case let (.number(p), .number(q)): return p == q
        case let (.bool(p), .bool(q)): return p == q
        default:
            if let p = x.stringValue, let q = y.stringValue { return Ordinal.equals(p, q) }
            return false
        }
    }

    /// Ordered structural equality (object key order significant, numbers by lexeme, strings ordinal,
    /// `.rawString(s) == .string(s)`). For tests and caches — "did it change" checks use `deepEquals`.
    public static func == (a: JSONValue, b: JSONValue) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case let (.bool(p), .bool(q)): return p == q
        case let (.number(p), .number(q)): return p == q
        case let (.array(p), .array(q)): return p == q
        case let (.object(p), .object(q)): return p == q
        default:
            if let p = a.stringValue, let q = b.stringValue { return Ordinal.equals(p, q) }
            return false
        }
    }

    public func hash(into h: inout Hasher) {
        switch self {
        case .null: h.combine(0)
        case .bool(let b): h.combine(1); h.combine(b)
        case .number(let n): h.combine(2); h.combine(n)
        case .string(let s), .rawString(let s): h.combine(3); Ordinal.hash(s, into: &h)
        case .array(let a): h.combine(4); h.combine(a)
        case .object(let o): h.combine(5); h.combine(o)
        }
    }
}

/// An ordered JSON object with ordinal, case-sensitive keys (STJ `JsonObject` semantics).
public struct JSONObject: Sendable, Hashable, Sequence {
    public private(set) var pairs: [(key: String, value: JSONValue)] = []
    private var index: [Ordinal.Key: Int] = [:]

    public init() {}

    /// A repeated key keeps its FIRST position with the LAST value (the parser rule, 01 §4.1.4).
    public init(_ pairs: [(String, JSONValue)]) {
        self.pairs.reserveCapacity(pairs.count)
        for (k, v) in pairs { set(k, v) }
    }

    public var keys: [String] { pairs.map(\.key) }
    public var count: Int { pairs.count }
    public var isEmpty: Bool { pairs.isEmpty }

    /// nil when absent OR JSON null (mirrors `JsonNode obj[key]`). Get-only by design.
    public subscript(key: String) -> JSONValue? {
        guard let i = index[Ordinal.Key(key)] else { return nil }
        let v = pairs[i].value
        return v.isNull ? nil : v
    }

    /// True for a key whose value is JSON null.
    public func containsKey(_ key: String) -> Bool { index[Ordinal.Key(key)] != nil }

    /// The stored value with `.null` preserved (distinguishes null from absent).
    public func rawValue(forKey key: String) -> JSONValue? {
        guard let i = index[Ordinal.Key(key)] else { return nil }
        return pairs[i].value
    }

    /// Replaces in place (position kept) or appends at the end; `.null` stores a JSON null.
    public mutating func set(_ key: String, _ value: JSONValue) {
        let k = Ordinal.Key(key)
        if let i = index[k] {
            pairs[i].value = value
        } else {
            index[k] = pairs.count
            pairs.append((key: key, value: value))
        }
    }

    /// Removes the key; a later re-add appends at the end.
    @discardableResult
    public mutating func removeValue(forKey key: String) -> JSONValue? {
        guard let i = index.removeValue(forKey: Ordinal.Key(key)) else { return nil }
        let old = pairs.remove(at: i).value
        if i < pairs.count {
            for j in i..<pairs.count { index[Ordinal.Key(pairs[j].key)] = j }
        }
        return old
    }

    /// Adds every pair of `other` with `set` semantics (used for `extra` members).
    public mutating func append(contentsOf other: JSONObject) {
        for (k, v) in other.pairs { set(k, v) }
    }

    /// A copy without the given keys (order kept).
    public func filtering(excluding keys: Set<Ordinal.Key>) -> JSONObject {
        var o = JSONObject()
        for p in pairs where !keys.contains(Ordinal.Key(p.key)) { o.set(p.key, p.value) }
        return o
    }

    public func makeIterator() -> IndexingIterator<[(key: String, value: JSONValue)]> { pairs.makeIterator() }

    public static func == (a: JSONObject, b: JSONObject) -> Bool {
        guard a.pairs.count == b.pairs.count else { return false }
        for (x, y) in zip(a.pairs, b.pairs) where !Ordinal.equals(x.key, y.key) || x.value != y.value { return false }
        return true
    }

    public func hash(into h: inout Hasher) {
        h.combine(pairs.count)
        for p in pairs { Ordinal.hash(p.key, into: &h); h.combine(p.value) }
    }
}
