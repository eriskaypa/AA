// Spec: 04 HIER-005 (search: trimmed, Name contains ordinal-ignore-case), HIER-006 (empty hints), HIER-010…015
//       (grouped list, section order, row order, A→Z, empty-group placeholder, expand keys), HIER-019 (scale),
//       §3.1 (RefreshList algorithm and the Mac decisions: section by group Id, stable sort, first-wins duplicate
//       group ids, creation-order tie-break), §7.7 (vectors), §8 Q-02 (empty group counts 0), Q-03 (no placeholders
//       while searching), Q-11, Q-12, Q-30; DECISIONS 04 Q-E (`#tag` matching).
import Foundation

/// One item as the sidebar sees it (a value snapshot, so the build is pure and testable).
public struct HierSidebarItem: Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var groupID: UUID?
    public var tags: [String]
    public init(id: UUID, name: String, groupID: UUID? = nil, tags: [String] = []) {
        self.id = id; self.name = name; self.groupID = groupID; self.tags = tags
    }
}

/// One sidebar group of the page's kind, in `Data.Groups` (creation) order.
public struct HierSidebarGroup: Sendable, Hashable {
    public var id: UUID
    public var name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}

/// A row: a real item, or the "(empty — right-click an item to assign)" placeholder of an empty group.
public struct HierSidebarRow: Sendable, Hashable, Identifiable {
    public var id: String
    public var itemID: UUID?
    public var isPlaceholder: Bool { itemID == nil }
    public init(id: String, itemID: UUID?) { self.id = id; self.itemID = itemID }
}

/// A collapsible section (a user group, or the synthetic "Ungrouped").
public struct HierSidebarSection: Sendable, Hashable, Identifiable {
    /// `"group:<uuid>"` or `"ungrouped"` (Mac decision §3.1: sections are keyed by group Id).
    public var id: String
    /// nil = the synthetic Ungrouped section (dropping onto it ungroups, HIER-M01).
    public var groupID: UUID?
    public var title: String
    /// Real rows only (Q-02: an empty group shows 0).
    public var count: Int
    public var rows: [HierSidebarRow]
    /// `Ui.GroupExpanded` key `"{Kind}|{SectionName}"` (HIER-015; by name, like Windows).
    public var expandKey: String
    public init(id: String, groupID: UUID?, title: String, count: Int, rows: [HierSidebarRow], expandKey: String) {
        self.id = id; self.groupID = groupID; self.title = title; self.count = count; self.rows = rows
        self.expandKey = expandKey
    }
}

/// The built sidebar.
public struct HierSidebar: Sendable, Hashable {
    public var sections: [HierSidebarSection]
    /// HIER-006 hint (nil = hidden).
    public var emptyHint: String?
    /// Every shown item id in display order (section order, then row order).
    public var visibleItemIDs: [UUID]
    /// Items of the kind in total (regardless of the query).
    public var totalCount: Int
    public init(sections: [HierSidebarSection] = [], emptyHint: String? = nil, visibleItemIDs: [UUID] = [],
                totalCount: Int = 0) {
        self.sections = sections; self.emptyHint = emptyHint; self.visibleItemIDs = visibleItemIDs
        self.totalCount = totalCount
    }

    public static let empty = HierSidebar()
}

public enum HierSidebarBuilder {
    /// The synthetic section name (also the expand-key suffix).
    public static let ungroupedName = "Ungrouped"
    /// HIER-014 placeholder text (two leading spaces on Windows; the Mac row trims them for display).
    public static let placeholderText = "  (empty — right-click an item to assign)"

    /// `Ui.GroupExpanded` key (HIER-015): the enum name of the kind + "|" + the section name.
    public static func expandKey(kind: ItemKind, sectionName: String) -> String { "\(kind.name)|\(sectionName)" }

    /// True when the item passes the query (already trimmed): `#tag` queries match tags (DECISIONS 04 Q-E), any
    /// other query matches the Name, ordinal ignore-case (HIER-005). An empty query matches everything.
    public static func matches(_ item: HierSidebarItem, trimmedQuery q: String) -> Bool {
        if q.isEmpty { return true }
        if TagParser.isHashQuery(q) { return TagParser.matches(item.tags, hashQuery: q) }
        return NetText.containsIgnoreCase(item.name, q)
    }

    /// 04 §3.1 `RefreshList` with the Mac decisions. `items` are in data order, `groups` are this kind's groups in
    /// `Data.Groups` order.
    public static func build(kind: ItemKind, items: [HierSidebarItem], groups: [HierSidebarGroup], query: String,
                             sortAZ: Bool) -> HierSidebar {
        let q = NetText.trim(query)
        let searching = !q.isEmpty
        let shown = searching ? items.filter { matches($0, trimmedQuery: q) } : items

        // Duplicate group ids (malformed data): the first wins (§3.1 note).
        var uniqueGroups: [HierSidebarGroup] = []
        var seen = Set<UUID>()
        for g in groups where seen.insert(g.id).inserted { uniqueGroups.append(g) }
        let groupIDs = seen

        // Rows per group id (nil = Ungrouped), data order.
        var byGroup: [UUID: [HierSidebarItem]] = [:]
        var ungrouped: [HierSidebarItem] = []
        for item in shown {
            if let g = item.groupID, groupIDs.contains(g) { byGroup[g, default: []].append(item) } else { ungrouped.append(item) }
        }

        func ordered(_ rows: [HierSidebarItem]) -> [HierSidebarItem] {
            guard sortAZ else { return rows }
            let keyed = rows.enumerated().map { (offset: $0.offset, item: $0.element, key: NetText.folded($0.element.name)) }
            return keyed.sorted { a, b in
                let c = compareFolded(a.key, b.key)
                return c == .orderedSame ? a.offset < b.offset : c == .orderedAscending     // stable (Q-12)
            }.map(\.item)
        }

        // Real groups by name (ordinal ignore-case), ties in creation order; Ungrouped always last.
        let sortedGroups = uniqueGroups.enumerated().sorted { a, b in
            let c = NetText.compareIgnoreCase(a.element.name, b.element.name)
            return c == .orderedSame ? a.offset < b.offset : c == .orderedAscending
        }.map(\.element)

        var sections: [HierSidebarSection] = []
        for g in sortedGroups {
            let rows = ordered(byGroup[g.id] ?? [])
            if rows.isEmpty && searching { continue }                                // Q-03
            var sectionRows = rows.map { HierSidebarRow(id: $0.id.netString, itemID: $0.id) }
            if rows.isEmpty { sectionRows.append(HierSidebarRow(id: "placeholder:\(g.id.netString)", itemID: nil)) }
            sections.append(HierSidebarSection(id: "group:\(g.id.netString)", groupID: g.id, title: g.name,
                                               count: rows.count, rows: sectionRows,
                                               expandKey: expandKey(kind: kind, sectionName: g.name)))
        }
        // Ungrouped: whenever it has rows; also (Mac, HIER-M01) as an empty drop target when the kind has items and
        // groups but every item is grouped and no search is active.
        let showEmptyUngrouped = !searching && ungrouped.isEmpty && !items.isEmpty && !uniqueGroups.isEmpty
        if !ungrouped.isEmpty || showEmptyUngrouped {
            let rows = ordered(ungrouped)
            sections.append(HierSidebarSection(id: "ungrouped", groupID: nil, title: ungroupedName, count: rows.count,
                                               rows: rows.map { HierSidebarRow(id: $0.id.netString, itemID: $0.id) },
                                               expandKey: expandKey(kind: kind, sectionName: ungroupedName)))
        }

        let visible = sections.flatMap { $0.rows.compactMap(\.itemID) }
        return HierSidebar(sections: sections,
                           emptyHint: emptyHint(kind: kind, total: items.count, shown: visible.count, searching: searching),
                           visibleItemIDs: visible, totalCount: items.count)
    }

    /// HIER-006 `UpdateEmptyHint` (with the Mac key names, §6.9).
    public static func emptyHint(kind: ItemKind, total: Int, shown: Int, searching: Bool) -> String? {
        if total == 0 { return HierText.emptyKindHint(kind) }
        if searching && shown == 0 { return HierText.noSearchMatches }
        return nil
    }

    static func compareFolded(_ a: [UInt16], _ b: [UInt16]) -> ComparisonResult {
        for (x, y) in zip(a, b) where x != y { return x < y ? .orderedAscending : .orderedDescending }
        if a.count == b.count { return .orderedSame }
        return a.count < b.count ? .orderedAscending : .orderedDescending
    }
}

@MainActor
extension HierSidebarBuilder {
    /// Value snapshot of a kind's collection (data order) and groups, then `build`.
    public static func build(store: AppStore, kind: ItemKind, query: String, sortAZ: Bool) -> HierSidebar {
        let items = store.items(of: kind).map {
            HierSidebarItem(id: $0.id, name: $0.name, groupID: $0.groupId, tags: $0.tags)
        }
        let groups = store.groups(for: kind).map { HierSidebarGroup(id: $0.id, name: $0.name) }
        return build(kind: kind, items: items, groups: groups, query: query, sortAZ: sortAZ)
    }
}
