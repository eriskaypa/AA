// Spec: 02 §2.M, §3.8 (REPO-130…136), 06 BUILD-A7…A9, §7.4; DECISIONS 02 Q-1 + OC-16 (the FIXED nudge: compute the
//       intended group order, then re-anchor like MoveTo — 02 §8 D-1, recorded in Deviations/F2.md); 02 §8 D-14 /
//       BUILD-A9 (ungrouped sorts last explicitly; names compared with the culture comparer).
// The order of `AppData.ChecklistTemplates` IS the user's arrangement; every operation here is a pure permutation.
import Foundation

@MainActor public enum SavedListOrder {
    /// REPO-131: ascending indices in `all` of the lists whose `GroupId == groupID` (nil = ungrouped).
    public static func groupSpan(_ all: [ChecklistTemplate], groupID: UUID?) -> [Int] {
        all.indices.filter { all[$0].groupId == groupID }
    }

    /// REPO-132 with the D-1 fix: false when the picks are empty or span groups, the group has fewer than two lists,
    /// or the first pick is already first (up) / the last pick already last (down). Otherwise each pick swaps with
    /// its group neighbour (ascending for up, descending for down) in the group's order, and the group is
    /// re-anchored into its own flat slots exactly like `moveTo`'s final loop.
    public static func nudge(_ all: inout [ChecklistTemplate], picks: [ChecklistTemplate], up: Bool) -> Bool {
        guard let gid = sameGroup(picks) else { return false }
        let span = groupSpan(all, groupID: gid)
        guard span.count >= 2 else { return false }
        let at = Array(Set(picks.compactMap { p in
            all.firstIndex(where: { $0 === p }).flatMap { span.firstIndex(of: $0) }
        })).sorted()
        guard let first = at.first, let last = at.last else { return false }
        if up && first == 0 { return false }
        if !up && last == span.count - 1 { return false }
        var desired = span.map { all[$0] }
        for pos in (up ? at : at.reversed()) {
            desired.swapAt(pos, up ? pos - 1 : pos + 1)
        }
        reanchor(&all, span: span, desired: desired)
        return true
    }

    /// REPO-133: moves the picks (keeping their relative order) to `targetInGroup` (0 = top, group size = bottom;
    /// "Before: X" = X's position) within their group. False when the picks are empty, span groups, are not all in
    /// the group, or the group has fewer than two lists.
    public static func moveTo(_ all: inout [ChecklistTemplate], picks: [ChecklistTemplate], targetInGroup: Int) -> Bool {
        guard let gid = sameGroup(picks) else { return false }
        let span = groupSpan(all, groupID: gid)
        guard span.count >= 2 else { return false }
        let moving = Set(picks.map(ObjectIdentifier.init))
        let ordered = span.map { all[$0] }
        let orderedIDs = Set(ordered.map(ObjectIdentifier.init))
        guard moving.isSubset(of: orderedIDs) else { return false }
        let cut = min(max(targetInGroup, 0), ordered.count)
        let before = ordered[0..<cut].filter { moving.contains(ObjectIdentifier($0)) }.count
        var remaining = ordered.filter { !moving.contains(ObjectIdentifier($0)) }
        let inOrder = ordered.filter { moving.contains(ObjectIdentifier($0)) }
        remaining.insert(contentsOf: inOrder, at: min(max(targetInGroup - before, 0), remaining.count))
        reanchor(&all, span: span, desired: remaining)
        return true
    }

    /// REPO-135: the lists with that `GroupId` in collection order, each paired with the group's name — nil as the
    /// group component when `groupID` is nil, the group no longer exists, or its name is empty. Never returns nil
    /// (an empty array when nothing matches).
    public static func groupEntries(_ data: AppData, groupID: UUID?) -> [(template: ChecklistTemplate, group: String?)]? {
        var name: String?
        if let gid = groupID { name = data.listGroups.first(where: { $0.id == gid })?.name }
        if let n = name, n.isEmpty { name = nil }
        return data.checklistTemplates.filter { $0.groupId == groupID }.map { (template: $0, group: name) }
    }

    /// REPO-136: every list, stably sorted by group key then collection position, so each group's lists are
    /// contiguous. Ungrouped sorts LAST (paired nil); otherwise the key is the group name lower-cased (a dangling
    /// group id → `""`, which sorts first and is paired `""`), compared with the culture comparer.
    public static func allEntries(_ data: AppData) -> [(template: ChecklistTemplate, group: String?)] {
        func groupName(_ g: UUID) -> String { data.listGroups.first(where: { $0.id == g })?.name ?? "" }
        let keyed = data.checklistTemplates.enumerated().map { (offset, t) -> (Int, String?, ChecklistTemplate) in
            (offset, t.groupId.map { NetText.toLowerInvariant(groupName($0)) }, t)
        }
        let sorted = keyed.sorted { a, b in
            switch (a.1, b.1) {
            case (nil, nil): return a.0 < b.0
            case (nil, _): return false
            case (_, nil): return true
            case let (ka?, kb?):
                let c = NetText.compareCulture(ka, kb)
                return c == .orderedSame ? a.0 < b.0 : c == .orderedAscending
            }
        }
        return sorted.map { (template: $0.2, group: $0.2.groupId.map(groupName)) }
    }

    // MARK: Internals

    /// The common `GroupId` of a non-empty pick list (`.some(nil)` = all ungrouped), or nil when empty or mixed.
    static func sameGroup(_ picks: [ChecklistTemplate]) -> UUID?? {
        guard let first = picks.first else { return nil }
        let g = first.groupId
        return picks.allSatisfy { $0.groupId == g } ? .some(g) : nil
    }

    /// `MoveTo`'s final loop: for each slot of the span, move the desired list into that flat index (remove at
    /// `from`, insert at the slot — `ObservableCollection.Move`) when it is not already there.
    static func reanchor(_ all: inout [ChecklistTemplate], span: [Int], desired: [ChecklistTemplate]) {
        for pos in 0..<span.count {
            guard let from = all.firstIndex(where: { $0 === desired[pos] }), from != span[pos] else { continue }
            let x = all.remove(at: from)
            all.insert(x, at: span[pos])
        }
    }
}
