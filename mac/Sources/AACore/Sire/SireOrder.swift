// Spec: 12 SIRE-045, §3.2 (QuestionNumberComparer incl. .NET int.TryParse rules), §3.9 (stable LINQ OrderBy), §6.12
//       and Addendum A.3.2 (culture comparer = Foundation en_US compare, stable sort).
import Foundation

/// Ordering helpers shared by the SIRE engine (all pure and `nonisolated`).
public enum SireOrder {
    /// `QuestionNumberComparer.Compare`: equal (ordinal) → 0, nil first; parts split on `.` and parsed like .NET
    /// `int.TryParse` (invalid → 0), compared pairwise up to the longer length with missing parts = 0.
    public static func compareNumbers(_ x: String?, _ y: String?) -> ComparisonResult {
        switch (x, y) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (a?, b?):
            if Ordinal.equals(a, b) { return .orderedSame }
            let pa = a.split(separator: ".", omittingEmptySubsequences: false).map { netInt32(Substring($0)) ?? 0 }
            let pb = b.split(separator: ".", omittingEmptySubsequences: false).map { netInt32(Substring($0)) ?? 0 }
            for i in 0..<max(pa.count, pb.count) {
                let p = i < pa.count ? pa[i] : 0, q = i < pb.count ? pb[i] : 0
                if p != q { return p < q ? .orderedAscending : .orderedDescending }
            }
            return .orderedSame
        }
    }

    /// .NET `int.TryParse(s, NumberStyles.Integer, en-US)`: optional leading/trailing white space (U+0009–U+000D,
    /// U+0020), optional `+`/`-`, ASCII digits only, Int32 range; anything else → nil.
    public static func netInt32<S: StringProtocol>(_ s: S) -> Int? {
        let u = Array(s.utf16)
        func isWS(_ c: UInt16) -> Bool { c == 0x20 || (c >= 0x09 && c <= 0x0D) }
        var a = 0, b = u.count
        while a < b, isWS(u[a]) { a += 1 }
        while b > a, isWS(u[b - 1]) { b -= 1 }
        guard a < b else { return nil }
        var negative = false
        if u[a] == 0x2B || u[a] == 0x2D { negative = u[a] == 0x2D; a += 1 }
        guard a < b else { return nil }
        var value: Int64 = 0
        for i in a..<b {
            let c = u[i]
            guard c >= 0x30, c <= 0x39 else { return nil }
            value = value * 10 + Int64(c - 0x30)
            if value > 2_147_483_648 { return nil }
        }
        if negative { value = -value }
        guard value >= Int64(Int32.min), value <= Int64(Int32.max) else { return nil }
        return Int(value)
    }

    /// `int.TryParse(chapter, out n) ? n : 999` (ByChapter, the Chapter sort, exports).
    public static func chapterRank(_ chapter: String) -> Int { netInt32(chapter) ?? 999 }

    /// .NET's default (culture-sensitive, en-US) string comparer (§6.12, A.3.2).
    public static func compareCulture(_ a: String, _ b: String) -> ComparisonResult { NetText.compareCulture(a, b) }

    /// A stable sort (LINQ `OrderBy`/`ThenBy` semantics): ties keep their input order.
    public static func stableSorted<T>(_ items: [T], by less: (T, T) -> Bool) -> [T] {
        let indexed = items.enumerated().map { ($0.offset, $0.element) }
        return indexed.sorted { l, r in
            if less(l.1, r.1) { return true }
            if less(r.1, l.1) { return false }
            return l.0 < r.0
        }.map(\.1)
    }

    /// A stable sort by a three-way comparison.
    public static func stableSorted<T>(_ items: [T], compare: (T, T) -> ComparisonResult) -> [T] {
        let indexed = items.enumerated().map { ($0.offset, $0.element) }
        return indexed.sorted { l, r in
            switch compare(l.1, r.1) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return l.0 < r.0
            }
        }.map(\.1)
    }

    /// `OrderBy(q => q.QuestionNumber, QuestionNumberComparer.Instance)`.
    public static func sortedByNumber(_ qs: [SireQuestion]) -> [SireQuestion] {
        stableSorted(qs) { compareNumbers($0.questionNumber, $1.questionNumber) }
    }

    /// `OrderBy(s => s)` with the culture comparer.
    public static func sortedCulture(_ strings: [String]) -> [String] {
        stableSorted(strings) { compareCulture($0, $1) }
    }
}
