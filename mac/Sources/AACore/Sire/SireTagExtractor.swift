// Spec: 12 SIRE-043/044/050/051, §3.3, Addendum A.3.1 (raw joined search text, ASCII-only OrdinalIgnoreCase over
//       UTF-16, no word boundaries), A.3.2 (culture order, stable), A.3.3 (DominantCategory, tie → Equipment).
import Foundation

/// Evidence-tag classifier, ROVIQ splitter and dominant category (TagExtractor.cs).
public enum SireTagExtractor {
    /// ASCII case fold of one UTF-16 unit (A.3.1: nothing but ASCII letters folds).
    @inline(__always) static func asciiFold(_ u: UInt16) -> UInt16 { (u >= 0x61 && u <= 0x7A) ? u &- 0x20 : u }

    /// The 237 keywords pre-folded once, with their tag strings, in scan order.
    static let foldedKeywords: [(tag: String, category: String, folded: [UInt16])] = {
        var out: [(String, String, [UInt16])] = []
        for (category, list) in SireTagKeywords.scanOrder {
            for k in list { out.append(("\(category): \(k)", category, k.utf16.map(asciiFold))) }
        }
        return out
    }()

    /// .NET `haystack.Contains(needle, OrdinalIgnoreCase)` for an ASCII needle; both pre-folded.
    public static func containsOrdinalIgnoreCaseASCII(_ hay: [UInt16], _ needle: [UInt16]) -> Bool {
        let n = needle.count, h = hay.count
        if n == 0 { return true }
        guard n <= h else { return false }
        let first = needle[0]
        var i = 0
        let last = h - n
        while i <= last {
            if hay[i] == first {
                var k = 1
                while k < n && hay[i + k] == needle[k] { k += 1 }
                if k == n { return true }
            }
            i += 1
        }
        return false
    }

    /// `searchText = string.Join(" ", ExpectedEvidence, SuggestedInspectorActions, ShortQuestionText, Objective)`.
    public static func searchText(_ q: SireQuestion) -> String {
        [q.expectedEvidence, q.suggestedInspectorActions, q.shortQuestionText, q.objective].joined(separator: " ")
    }

    /// `ExtractTags`: every keyword found (raw text, no normalisation) as `"{Category}: {keyword}"`, de-duplicated
    /// (OrdinalIgnoreCase, a no-op for these lists) and sorted with the culture comparer.
    public static func extractTags(_ q: SireQuestion) -> [String] {
        extractTags(searchText: searchText(q))
    }

    public static func extractTags(searchText: String) -> [String] {
        let hay = searchText.utf16.map(asciiFold)
        var tags: [String] = []
        var seen = Set<String>()
        for k in foldedKeywords where containsOrdinalIgnoreCaseASCII(hay, k.folded) {
            let key = NetText.toUpperInvariant(k.tag)
            if seen.insert(key).inserted { tags.append(k.tag) }
        }
        return SireOrder.sortedCulture(tags)
    }

    /// `ExtractRoviqLocations`: split on `,` (empty entries removed, entries trimmed), `TrimEnd('.')`, blank entries
    /// dropped, `Distinct(OrdinalIgnoreCase)` keeping the first casing, culture order.
    public static func extractRoviqLocations(_ sequence: String) -> [String] {
        if NetText.isBlank(sequence) { return [] }
        var out: [String] = []
        var seen = Set<String>()
        for raw in SireText.split(SireText.units(sequence), on: [0x2C], removeEmpty: false) {
            let trimmed = NetText.trim(SireText.string(raw))
            if trimmed.isEmpty { continue }                                    // RemoveEmptyEntries after TrimEntries
            let loc = trimEndDots(trimmed)
            if NetText.isBlank(loc) { continue }
            if seen.insert(NetText.toUpperInvariant(loc)).inserted { out.append(loc) }
        }
        return SireOrder.sortedCulture(out)
    }

    /// `TrimEnd('.')` (only trailing dots; a space before them stays).
    static func trimEndDots(_ s: String) -> String {
        var u = Array(s.utf16)
        while let l = u.last, l == 0x2E { u.removeLast() }
        return String(decoding: u, as: UTF16.self)
    }

    /// `DominantCategory`: counts per category (text before the first `:`, index > 0, case-sensitive names);
    /// Equipment when `E > 0 && E >= P`, else Procedure when `P > 0`, else "Task".
    public static func dominantCategory(_ q: SireQuestion) -> String { dominantCategory(tags: q.evidenceTags) }

    public static func dominantCategory(tags: [String]) -> String {
        var equipment = 0, procedure = 0
        for t in tags {
            let u = Array(t.utf16)
            guard let idx = u.firstIndex(of: 0x3A), idx > 0 else { continue }
            let cat = String(decoding: u[..<idx], as: UTF16.self)
            if Ordinal.equals(cat, "Equipment") { equipment += 1 } else if Ordinal.equals(cat, "Procedure") { procedure += 1 }
        }
        if equipment > 0 && equipment >= procedure { return "Equipment" }
        if procedure > 0 { return "Procedure" }
        return "Task"
    }
}
