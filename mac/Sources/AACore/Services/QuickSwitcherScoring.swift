// Spec: 02 REPO-107, 08 §3.3.1–§3.3.3 (QUICK-104/105), §7.3; DECISIONS 08 OQ-8 (a locked item's description never
//       contributes to ranking — recorded in Deviations/F2.md).
import Foundation

public enum QuickSwitcherScoring {
    public struct Row: Sendable, Identifiable, Hashable {
        public var id: UUID
        public var name: String
        public var kind: ItemKind
        public var kindLabel: String
        public var tags: [String]
        public var description: String

        public init(id: UUID, name: String, kind: ItemKind, kindLabel: String, tags: [String], description: String) {
            self.id = id; self.name = name; self.kind = kind; self.kindLabel = kindLabel; self.tags = tags
            self.description = description
        }
    }

    /// Every top-level item (E, T, P, V order). DECISIONS 08 OQ-8: a password-protected item's description is
    /// blanked so it cannot influence ranking (use `rows(store:isGated:)` to blank only items still locked).
    @MainActor public static func rows(store: AppStore) -> [Row] {
        rows(store: store, isGated: { $0.isLockProtected })
    }

    /// As `rows(store:)`, blanking the description of every item for which `isGated` is true.
    @MainActor public static func rows(store: AppStore, isGated: (HierarchyItem) -> Bool) -> [Row] {
        store.allItems().map { i in
            Row(id: i.id, name: i.name, kind: i.kind, kindLabel: AppStore.kindLabel(i.kind), tags: i.tags,
                description: isGated(i) ? "" : i.description)
        }
    }

    /// `text.Trim().TrimStart('#')`.
    public static func normalizeQuery(_ q: String) -> String {
        let t = NetText.trim(q)
        guard let k = t.firstIndex(where: { $0 != "#" }) else { return "" }
        return String(t[k...])
    }

    /// 08 §3.3.1 exactly (OrdinalIgnoreCase): empty query → 1; name prefix +120, else contains +60, else
    /// subsequence +25; a tag prefix +45, else a tag containing it +22; KindLabel contains +8; description
    /// contains +5. `query` is used as given (normalise it first).
    public static func score(_ row: Row, query: String) -> Int {
        let q = query
        if q.isEmpty { return 1 }
        var s = 0
        if svcHasPrefix(row.name, q) { s += 120 }
        else if NetText.containsIgnoreCase(row.name, q) { s += 60 }
        else if isSubsequence(q, of: row.name) { s += 25 }
        if row.tags.contains(where: { svcHasPrefix($0, q) }) { s += 45 }
        else if row.tags.contains(where: { NetText.containsIgnoreCase($0, q) }) { s += 22 }
        if NetText.containsIgnoreCase(row.kindLabel, q) { s += 8 }
        if !row.description.isEmpty && NetText.containsIgnoreCase(row.description, q) { s += 5 }
        return s
    }

    /// 08 §3.3.3: normalises the query, keeps rows scoring > 0 (all when the query is empty), orders by score
    /// descending then name (OrdinalIgnoreCase, stable), and takes `limit`.
    public static func rank(_ rows: [Row], query: String, limit: Int = 80) -> [Row] {
        let q = normalizeQuery(query)
        let scored = rows.enumerated().compactMap { (k, r) -> (Int, Int, Row)? in
            let sc = score(r, query: q)
            return (q.isEmpty || sc > 0) ? (sc, k, r) : nil
        }
        let sorted = scored.sorted { a, b in
            if a.0 != b.0 { return a.0 > b.0 }
            let c = NetText.compareIgnoreCase(a.2.name, b.2.name)
            return c == .orderedSame ? a.1 < b.1 : c == .orderedAscending
        }
        return sorted.prefix(max(0, limit)).map(\.2)
    }

    /// 08 §3.3.2: greedy scan; each UTF-16 unit compared after `char.ToLowerInvariant`; spaces count.
    public static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        let n = Array(needle.utf16).map(svcLower)
        var j = 0
        for c in haystack.utf16 where j < n.count {
            if svcLower(c) == n[j] { j += 1 }
        }
        return j == n.count
    }

    /// `s.StartsWith(q, StringComparison.OrdinalIgnoreCase)`.
    static func svcHasPrefix(_ s: String, _ q: String) -> Bool {
        let a = Array(s.utf16), b = Array(q.utf16)
        guard a.count >= b.count else { return false }
        for k in 0..<b.count where a[k] != b[k] && NetText.simpleUpper(a[k]) != NetText.simpleUpper(b[k]) {
            return false
        }
        return true
    }

    static func svcLower(_ u: UInt16) -> UInt16 {
        if u < 0x80 { return (u >= 0x41 && u <= 0x5A) ? u + 0x20 : u }
        guard !(0xD800...0xDFFF).contains(u), let sc = Unicode.Scalar(u) else { return u }
        let m = sc.properties.lowercaseMapping.unicodeScalars
        guard m.count == 1, let f = m.first, f.value <= 0xFFFF else { return u }
        return UInt16(f.value)
    }
}
