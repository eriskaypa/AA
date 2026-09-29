// Spec: 01 §4.1.4 (Dictionary<string,T>: insertion order, duplicate keys last wins), 13 CS-19 (ordinal keys);
//       ARCHITECTURE.md §3.8 — mirrors .NET Dictionary's entries array + LIFO free list.
import Foundation

/// An ordered string-keyed map that reproduces .NET `Dictionary<string,T>` enumeration order exactly: keys are
/// ordinal; removing an entry frees its slot, and the next insertion of a NEW key reuses the most recently freed
/// slot (remove b, add d → a, d, c), so re-written dictionaries enumerate like Windows'.
public struct OrderedMap<Value: Sendable & Hashable>: Sendable, Hashable, Sequence {
    private var slots: [(key: String, value: Value)?] = []
    private var index: [Ordinal.Key: Int] = [:]
    private var freeList: [Int] = []                       // LIFO stack of freed slot indices

    public init() {}

    /// Builds a map by inserting the pairs in order (a repeated key keeps its first position, last value).
    public init(_ pairs: [(String, Value)]) {
        for (k, v) in pairs { self[k] = v }
    }

    public subscript(key: String) -> Value? {
        get {
            guard let i = index[Ordinal.Key(key)] else { return nil }
            return slots[i]?.value
        }
        set {
            let k = Ordinal.Key(key)
            if let v = newValue {
                if let i = index[k] {
                    slots[i] = (key: slots[i]!.key, value: v)      // existing key keeps its position (and spelling)
                } else if let free = freeList.popLast() {
                    slots[free] = (key: key, value: v)
                    index[k] = free
                } else {
                    slots.append((key: key, value: v))
                    index[k] = slots.count - 1
                }
            } else if let i = index.removeValue(forKey: k) {
                slots[i] = nil
                freeList.append(i)                                  // .NET: no reset even when count hits 0
            }
        }
    }

    /// Enumeration order (slot order, holes skipped).
    public var keys: [String] { slots.compactMap { $0?.key } }
    public var values: [Value] { slots.compactMap { $0?.value } }
    public var count: Int { index.count }
    public var isEmpty: Bool { index.isEmpty }
    public var pairs: [(key: String, value: Value)] { slots.compactMap { $0 } }

    public func containsKey(_ key: String) -> Bool { index[Ordinal.Key(key)] != nil }

    @discardableResult
    public mutating func removeValue(forKey key: String) -> Value? {
        let old = self[key]
        self[key] = nil
        return old
    }

    public mutating func removeAll() { slots.removeAll(); index.removeAll(); freeList.removeAll() }

    public func makeIterator() -> IndexingIterator<[(key: String, value: Value)]> { pairs.makeIterator() }

    public static func == (a: OrderedMap, b: OrderedMap) -> Bool {
        let pa = a.pairs, pb = b.pairs
        guard pa.count == pb.count else { return false }
        for (x, y) in zip(pa, pb) where !Ordinal.equals(x.key, y.key) || x.value != y.value { return false }
        return true
    }

    public func hash(into h: inout Hasher) {
        h.combine(count)
        for p in pairs { Ordinal.hash(p.key, into: &h); h.combine(p.value) }
    }
}
