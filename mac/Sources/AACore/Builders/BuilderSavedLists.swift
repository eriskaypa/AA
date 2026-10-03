// Spec: 06 §G (BUILD-070…090), BUILD-A10 (tab rows), BUILD-017 (manage), BUILD-135 (log entries), 02 REPO-130…134
//       (arranged order, guards and messages), 06 §7.5 / §7.6 vectors, §8 D1 (group by Id; dangling ids are
//       ungrouped), D2 (Move to group preselects the current group); DECISIONS 06.
// The Saved Lists tab's derived rows, texts and model operations. Ordering of the collection itself (Nudge / MoveTo)
// is F2's `SavedListOrder`; this file never re-sorts `ChecklistTemplates`.
import Foundation

/// One saved list as the tab shows it.
public struct BuilderSavedListRow: Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Display name (`"(unnamed)"` when empty).
    public var name: String
    /// `"{count} items"` — always plural, as on Windows ("1 items").
    public var countText: String
    /// Index in `AppData.ChecklistTemplates` (the user's arrangement).
    public var flatIndex: Int
    /// The resolved group (nil = ungrouped, including a dangling `GroupId`).
    public var groupID: UUID?
    public init(id: UUID, name: String, countText: String, flatIndex: Int, groupID: UUID?) {
        self.id = id; self.name = name; self.countText = countText; self.flatIndex = flatIndex; self.groupID = groupID
    }
}

/// One group section of the tab (empty groups never appear — BUILD-072).
public struct BuilderSavedListSection: Sendable, Hashable, Identifiable {
    /// The group's id, or nil for "Ungrouped".
    public var groupID: UUID?
    public var title: String
    public var rows: [BuilderSavedListRow]
    public var id: String { groupID?.uuidString ?? "ungrouped" }
    public var count: Int { rows.count }
    public init(groupID: UUID?, title: String, rows: [BuilderSavedListRow]) {
        self.groupID = groupID; self.title = title; self.rows = rows
    }
}

/// Why a reorder of the selection cannot run (BUILD-089 / REPO-134).
public enum BuilderReorderCheck {
    case ok(picks: [ChecklistTemplate])
    case sortAZ           // "Turn off \"Sort A-Z\" first …" (Arrange lists)
    case noSelection      // "Select a saved list first." (Saved Lists)
    case mixedGroups      // "Those lists are in different groups. …" (Arrange lists)
    case groupOfOne       // silently nothing
}

@MainActor public enum BuilderSavedLists {
    /// `Ui.SortAZ` key of the tab (BUILD-088).
    public static let sortAZKey = "savedlists"

    // MARK: Texts (exact Windows strings)

    public static let selectFirstTitle = "Saved Lists"
    public static let selectFirstMessage = "Select a saved list first."
    public static let arrangeTitle = "Arrange lists"
    public static let sortAZFirstMessage =
        "Turn off \"Sort A-Z\" first — while it is on you are seeing alphabetical order, not your own."
    public static let mixedGroupsMessage =
        "Those lists are in different groups. Lists are arranged within their own group, so select lists from one group at a time."
    public static let orderSavedStatus = "Order saved — this is the order the group exports in."
    public static let sortAZOnStatus =
        "Showing A-Z. Your arranged order is kept, and is what exports use — switch this off to see it."
    public static let sortAZOffStatus =
        "Showing your arranged order. This is the order lists appear in when you export a group."

    /// BUILD-073 status line.
    public static func statusLine(lists: Int, groups: Int) -> String {
        lists == 0
            ? "No saved lists yet. Build a checklist anywhere and click 'Save as list...', or click '+ List'."
            : "\(lists) saved list(s)  ·  \(groups) group(s)"
    }

    /// The tab's display name of a list.
    public static func displayName(_ t: ChecklistTemplate) -> String { t.name.isEmpty ? "(unnamed)" : t.name }

    /// BUILD-074 `DetailSub`: `"{n} item(s)"` + group part + `"  ·  created {local yyyy-MM-dd}"`.
    public static func detailSub(_ t: ChecklistTemplate, groups: [ListGroup], zone: TimeZone = .current) -> String {
        let grp = t.groupId.flatMap { gid in groups.first { $0.id == gid }?.name }
        let groupPart = NetText.isBlank(grp) ? "  ·  ungrouped" : "  ·  group: \(grp ?? "")"
        let created = t.createdUtc.toLocalTime(zone: zone).format(.isoDate, zone: zone)
        return "\(t.items.count) item(s)\(groupPart)  ·  created \(created)"
    }

    /// BUILD-075: the preview row title (`"(untitled)"` when empty).
    public static func itemTitle(_ item: ChecklistTemplateItem) -> String { item.title.isEmpty ? "(untitled)" : item.title }

    /// BUILD-075: `"job"`, `"notes"` (raw XAML not blank), `"{n} file|files"`, joined by `"  ·  "`. Duration is not shown.
    public static func itemMeta(_ item: ChecklistTemplateItem) -> String {
        var meta: [String] = []
        if item.isJob { meta.append("job") }
        if !NetText.isBlank(item.container.richTextXaml) { meta.append("notes") }
        let files = item.container.files.count
        if files > 0 { meta.append("\(files) file\(files == 1 ? "" : "s")") }
        return meta.joined(separator: "  ·  ")
    }

    /// BUILD-076 viewer subtitle (passed to the read-only viewer where supported).
    public static func viewerSubtitle(listName: String?) -> String {
        let part = NetText.isBlank(listName) ? "" : " · \(listName ?? "")"
        return "Saved-list item\(part) — read-only. Click a link to open it; double-click a file to open it."
    }

    // MARK: Rows (BUILD-072, BUILD-A10, D1)

    /// Whether the tab shows A-Z (`Ui.SortAZ["savedlists"]`).
    public static func isSortAZ(_ data: AppData) -> Bool { data.ui.sortAZ[sortAZKey] ?? false }

    /// The resolved group of a list: its `GroupId` when that group exists, else nil (dangling = ungrouped, D1).
    public static func resolvedGroup(_ t: ChecklistTemplate, groups: [ListGroup]) -> ListGroup? {
        guard let gid = t.groupId else { return nil }
        return groups.first { $0.id == gid }
    }

    /// The tab's sections: named groups ordered by lower-cased name (culture comparison; ties by group creation
    /// order), "Ungrouped" last; inside a group the arranged order, or the displayed name while Sort A-Z is on.
    /// Groups are keyed by **Id** (D1), so equally named groups stay separate.
    public static func sections(_ data: AppData, sortAZ: Bool) -> [BuilderSavedListSection] {
        let groups = data.listGroups
        let groupIndex = Dictionary(groups.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        var buckets: [UUID?: [BuilderSavedListRow]] = [:]
        for (i, t) in data.checklistTemplates.enumerated() {
            let g = resolvedGroup(t, groups: groups)
            let row = BuilderSavedListRow(id: t.id, name: displayName(t), countText: "\(t.items.count) items",
                                          flatIndex: i, groupID: g?.id)
            buckets[g?.id, default: []].append(row)
        }
        func ordered(_ rows: [BuilderSavedListRow]) -> [BuilderSavedListRow] {
            guard sortAZ else { return rows.sorted { $0.flatIndex < $1.flatIndex } }
            return rows.sorted { a, b in
                let c = NetText.compareCulture(a.name, b.name)
                return c == .orderedSame ? a.flatIndex < b.flatIndex : c == .orderedAscending
            }
        }
        var named: [(group: ListGroup, rows: [BuilderSavedListRow])] = []
        for g in groups {
            guard let rows = buckets[g.id], !rows.isEmpty, !named.contains(where: { $0.group.id == g.id }) else { continue }
            named.append((g, rows))
        }
        named.sort { a, b in
            let c = NetText.compareCulture(NetText.toLowerInvariant(a.group.name), NetText.toLowerInvariant(b.group.name))
            if c != .orderedSame { return c == .orderedAscending }
            return (groupIndex[a.group.id] ?? 0) < (groupIndex[b.group.id] ?? 0)
        }
        var out = named.map {
            BuilderSavedListSection(groupID: $0.group.id, title: $0.group.name.isEmpty ? "(unnamed group)" : $0.group.name,
                                    rows: ordered($0.rows))
        }
        if let un = buckets[nil], !un.isEmpty {
            out.append(BuilderSavedListSection(groupID: nil, title: "Ungrouped", rows: ordered(un)))
        }
        return out
    }

    /// The selected templates in collection order (REPO-134 "the selection is always taken in collection order").
    public static func selectedTemplates(_ data: AppData, ids: Set<UUID>) -> [ChecklistTemplate] {
        data.checklistTemplates.filter { ids.contains($0.id) }
    }

    /// The primary selection: the first selected list in display order.
    public static func primary(_ sections: [BuilderSavedListSection], ids: Set<UUID>, data: AppData) -> ChecklistTemplate? {
        for s in sections { for r in s.rows where ids.contains(r.id) { return data.checklistTemplates[r.flatIndex] } }
        return nil
    }

    /// BUILD-089 / REPO-134 guards of ↑ / ↓ / Move to position.
    public static func checkReorder(_ data: AppData, ids: Set<UUID>) -> BuilderReorderCheck {
        if isSortAZ(data) { return .sortAZ }
        let picks = selectedTemplates(data, ids: ids)
        guard let first = picks.first else { return .noSelection }
        if picks.contains(where: { $0.groupId != first.groupId }) { return .mixedGroups }
        let span = SavedListOrder.groupSpan(data.checklistTemplates, groupID: first.groupId)
        return span.count > 1 ? .ok(picks: picks) : .groupOfOne
    }

    /// BUILD-087 picker options: `(Move to top of group)` (0), `Before: {Shorten(name, 60)}` for each non-selected
    /// list at its group position, `(Move to bottom of group)` (group size).
    public static func moveToPositionOptions(_ data: AppData, picks: [ChecklistTemplate]) -> [BuilderMoveOption] {
        guard let first = picks.first else { return [] }
        let span = SavedListOrder.groupSpan(data.checklistTemplates, groupID: first.groupId)
        let moving = Set(picks.map(ObjectIdentifier.init))
        var out = [BuilderMoveOption(display: "(Move to top of group)", target: 0)]
        for (pos, idx) in span.enumerated() {
            let t = data.checklistTemplates[idx]
            if moving.contains(ObjectIdentifier(t)) { continue }
            out.append(BuilderMoveOption(display: "Before: \(BuilderShorten.savedLists(t.name, max: 60))", target: pos))
        }
        out.append(BuilderMoveOption(display: "(Move to bottom of group)", target: span.count))
        return out
    }

    /// A drag within one group section (06 §6.2 additive): SwiftUI's destination row index inside the section →
    /// the in-group target of `SavedListOrder.moveTo`.
    public static func dropTarget(sectionRowIDs: [UUID], destination: Int, data: AppData) -> Int {
        guard destination < sectionRowIDs.count else {
            guard let firstID = sectionRowIDs.first, let t = data.checklistTemplates.first(where: { $0.id == firstID })
            else { return 0 }
            return SavedListOrder.groupSpan(data.checklistTemplates, groupID: t.groupId).count
        }
        let targetID = sectionRowIDs[destination]
        guard let t = data.checklistTemplates.first(where: { $0.id == targetID }),
              let flat = data.checklistTemplates.firstIndex(where: { $0 === t }) else { return 0 }
        return SavedListOrder.groupSpan(data.checklistTemplates, groupID: t.groupId).firstIndex(of: flat) ?? 0
    }

    // MARK: Pickers

    /// BUILD-016/017 picker rows: every template in collection (arranged) order, display = `Display`.
    public static func templatePickerRows(_ data: AppData) -> [(display: String, id: UUID)] {
        data.checklistTemplates.map { ($0.display, $0.id) }
    }

    /// BUILD-078 rows: groups in creation order as `"{name}  ·  {k} list(s)"`.
    public static func manageGroupRows(_ data: AppData) -> [(display: String, id: UUID)] {
        data.listGroups.map { g in
            ("\(g.name)  ·  \(data.checklistTemplates.filter { $0.groupId == g.id }.count) list(s)", g.id)
        }
    }

    /// BUILD-079 rows: `"(No group — ungrouped)"` (nil) then every group name in creation order.
    public static func moveToGroupRows(_ data: AppData) -> [(display: String, id: UUID?)] {
        [("(No group — ungrouped)", nil)] + data.listGroups.map { ($0.name, Optional($0.id)) }
    }

    // MARK: Model operations (callers confirm, then Save — BUILD-077…083)

    /// BUILD-080: `+ List` — a trimmed name, appended ungrouped and empty, logged `Added / "Saved list" / name / "empty"`.
    /// Blank → nil (no-op).
    @discardableResult
    public static func newList(_ store: AppStore, rawName: String) -> ChecklistTemplate? {
        guard !NetText.isBlank(rawName) else { return nil }
        let t = ChecklistTemplate(name: NetText.trim(rawName))
        store.data.checklistTemplates.append(t)
        store.logAdded(kind: "Saved list", name: t.name, detail: "empty")
        return t
    }

    /// BUILD-017 / BUILD-081: rename (trimmed); blank → false. Not logged.
    @discardableResult
    public static func rename(_ store: AppStore, _ t: ChecklistTemplate, rawName: String) -> Bool {
        guard !NetText.isBlank(rawName) else { return false }
        t.name = NetText.trim(rawName)
        store.markDirty()
        return true
    }

    /// BUILD-017 / BUILD-082: permanent removal, logged `Removed / "Saved list" / name / ""`.
    public static func delete(_ store: AppStore, _ t: ChecklistTemplate) {
        guard let i = store.data.checklistTemplates.firstIndex(where: { $0 === t }) else { return }
        store.data.checklistTemplates.remove(at: i)
        store.logRemoved(kind: "Saved list", name: t.name)
    }

    /// BUILD-083: `Clone(t, t.Name + " (copy)")` appended at the end of the collection, logged
    /// `Added / "Saved list" / copy / "{n} item(s)"`.
    @discardableResult
    public static func duplicate(_ store: AppStore, _ t: ChecklistTemplate) -> ChecklistTemplate {
        let copy = ChecklistTemplateService.clone(t, newName: t.name + " (copy)")
        store.data.checklistTemplates.append(copy)
        store.logAdded(kind: "Saved list", name: copy.name, detail: "\(copy.items.count) item(s)")
        return copy
    }

    /// BUILD-077: `+ Group` — appended with a trimmed name; blank → nil. Not logged.
    @discardableResult
    public static func newGroup(_ store: AppStore, rawName: String) -> ListGroup? {
        guard !NetText.isBlank(rawName) else { return nil }
        let g = ListGroup(name: NetText.trim(rawName))
        store.data.listGroups.append(g)
        store.markDirty()
        return g
    }

    /// BUILD-078 rename: trimmed; blank → false. Not logged.
    @discardableResult
    public static func renameGroup(_ store: AppStore, _ g: ListGroup, rawName: String) -> Bool {
        guard !NetText.isBlank(rawName) else { return false }
        g.name = NetText.trim(rawName)
        store.markDirty()
        return true
    }

    /// BUILD-078 delete: every list of that group becomes ungrouped (flat positions unchanged), the group is removed.
    public static func deleteGroup(_ store: AppStore, _ g: ListGroup) {
        for t in store.data.checklistTemplates where t.groupId == g.id { t.groupId = nil }
        store.data.listGroups.removeAll { $0 === g }
        store.markDirty()
    }

    /// BUILD-079: the list keeps its flat position; `GroupId` = the chosen group (nil = ungrouped).
    public static func assign(_ store: AppStore, _ t: ChecklistTemplate, toGroup groupID: UUID?) {
        t.groupId = groupID
        store.markDirty()
    }

    /// BUILD-088: persists `Ui.SortAZ["savedlists"]` (the arrangement underneath never changes).
    public static func setSortAZ(_ store: AppStore, _ on: Bool) {
        store.data.ui.sortAZ[sortAZKey] = on
        store.markDirty()
    }
}
