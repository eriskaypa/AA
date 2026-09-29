// Spec: 01 §3 ("Ordinal"), 13 §3.11.9 (CS-19), ARCHITECTURE.md §3.1
import Foundation

/// .NET ordinal string semantics: equality, hashing and ordering over UTF-16 code units — never Swift's
/// canonical-equivalence `String ==` (which would merge `"é"` U+00E9 and `"e\u{301}"`).
public enum Ordinal {
    /// `string.Equals(a, b, StringComparison.Ordinal)`.
    public static func equals(_ a: String, _ b: String) -> Bool {
        a.utf16.elementsEqual(b.utf16)
    }

    /// Hashes the UTF-16 code units (consistent with `equals`).
    public static func hash(_ s: String, into h: inout Hasher) {
        var n = 0
        for u in s.utf16 { h.combine(u); n += 1 }
        h.combine(n)
    }

    /// `string.CompareOrdinal(a, b)`: lexicographic over UTF-16 code units.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        var ia = a.utf16.makeIterator(), ib = b.utf16.makeIterator()
        while true {
            switch (ia.next(), ib.next()) {
            case (nil, nil): return .orderedSame
            case (nil, _): return .orderedAscending
            case (_, nil): return .orderedDescending
            case let (x?, y?):
                if x != y { return x < y ? .orderedAscending : .orderedDescending }
            }
        }
    }

    /// A dictionary/set key with ordinal `==` and hash.
    public struct Key: Hashable, Sendable, CustomStringConvertible {
        public let string: String
        public init(_ s: String) { string = s }
        public static func == (a: Key, b: Key) -> Bool { Ordinal.equals(a.string, b.string) }
        public func hash(into h: inout Hasher) { Ordinal.hash(string, into: &h) }
        public var description: String { string }
    }
}
