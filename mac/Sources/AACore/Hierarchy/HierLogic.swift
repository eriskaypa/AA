// Spec: 04 HIER-058 (lock dialog validation), §3.5 (duration text), §3.8 / §7.9 (safe file names), HIER-031
//       (group picker rows, title, preselection), HIER-060…063 / §3.6 / §7.11 (relationship rows, candidates,
//       backlinks), HIER-072/073 + 07 VIEW-212 rows 11–12 / VIEW-215 (replace-semantics link pickers),
//       DECISIONS 04 Q-B (one-way rows); 02 REPO-023…026, REPO-028.
import Foundation

// MARK: Lock dialog validation (HIER-058)

public enum HierLockForm {
    /// First failure wins: empty → length < 4 UTF-16 units → confirmation differs (ordinal). nil = valid.
    public static func validate(password: String, confirm: String) -> String? {
        if password.isEmpty { return "Password cannot be empty." }
        if password.utf16.count < 4 { return "Password must be at least 4 characters." }
        if !Ordinal.equals(password, confirm) { return "Passwords do not match." }
        return nil
    }
}

// MARK: Duration text (§3.5)

public enum HierDuration {
    /// `int.TryParse(text, NumberStyles.Integer) && m > 0`: leading/trailing white space (U+0009–U+000D, U+0020),
    /// one optional leading `+`/`-`, ASCII digits only, within Int32. Returns nil for anything else (ignored input).
    public static func parse(_ text: String) -> Int? {
        let ws: Set<UInt16> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20]
        var u = Array(text.utf16)
        while let f = u.first, ws.contains(f) { u.removeFirst() }
        while let l = u.last, ws.contains(l) { u.removeLast() }
        guard !u.isEmpty else { return nil }
        var negative = false
        if u[0] == 0x2B || u[0] == 0x2D {
            negative = u[0] == 0x2D
            u.removeFirst()
        }
        guard !u.isEmpty, u.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        var value: Int64 = 0
        for d in u {
            value = value * 10 + Int64(d - 0x30)
            if value > Int64(Int32.max) + 1 { return nil }
        }
        if negative { value = -value }
        guard value >= Int64(Int32.min), value <= Int64(Int32.max), value > 0 else { return nil }
        return Int(value)
    }
}

// MARK: Safe file names (§3.8, §7.9)

public enum HierExportName {
    /// Replaces each Windows-invalid file-name character (`" < > | : * ? \ /`, U+0000…U+001F) with `_`; nothing
    /// else changes (no trimming — an empty name stays empty).
    public static func safe(_ name: String) -> String {
        var out = String.UnicodeScalarView()
        for sc in name.unicodeScalars {
            if sc.value < 0x20 || "\"<>|:*?\\/".unicodeScalars.contains(sc) { out.append("_") } else { out.append(sc) }
        }
        return String(out)
    }

    /// `"{Kind}-{safe}.pdf"` (Kind = enum name).
    public static func itemPDF(kind: ItemKind, name: String) -> String { "\(kind.name)-\(safe(name)).pdf" }

    /// `"checklist-{safe}.{ext}"`.
    public static func checklist(name: String, ext: String) -> String { "checklist-\(safe(name)).\(ext)" }
}

// MARK: Group picker (HIER-031, VIEW-212 row 7)

public struct HierGroupChoice: Sendable, Hashable {
    /// `.netEmpty` = "(Ungrouped)".
    public var tag: UUID
    public var display: String
    public init(tag: UUID, display: String) { self.tag = tag; self.display = display }
}

@MainActor
public enum HierGroupPicker {
    /// "(Ungrouped)" (empty GUID) first, then this kind's groups in `Data.Groups` order.
    public static func assignChoices(store: AppStore, kind: ItemKind) -> [HierGroupChoice] {
        [HierGroupChoice(tag: .netEmpty, display: HierText.ungroupedRow)]
            + store.groups(for: kind).map { HierGroupChoice(tag: $0.id, display: $0.name) }
    }

    /// The common group of the picks (`.netEmpty` when all are ungrouped), or nil when they differ. A group id
    /// that resolves to no group of this kind is treated as ungrouped (that is where the sidebar shows the item).
    public static func commonGroup(_ items: [HierarchyItem], store: AppStore, kind: ItemKind) -> UUID? {
        let valid = Set(store.groups(for: kind).map(\.id))
        let tags = items.map { i -> UUID in
            guard let g = i.groupId, valid.contains(g) else { return .netEmpty }
            return g
        }
        guard let first = tags.first, tags.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// The picked tag → `GroupId` (`.netEmpty` → nil).
    public static func groupID(fromTag tag: UUID) -> UUID? { tag == .netEmpty ? nil : tag }
}

// MARK: Relationships (HIER-060…064, §3.6)

public struct HierRelationRow: Sendable, Hashable, Identifiable {
    public var id: UUID { item.id }
    public var item: HierItemSummary
    /// The row exists only through an Equipment's one-way `ProcedureIds` / `TaskIds` (DECISIONS 04 Q-B: Remove is
    /// disabled for it).
    public var isOneWay: Bool
    public var label: String { HierText.label(item) }
    public init(item: HierItemSummary, isOneWay: Bool) { self.item = item; self.isOneWay = isOneWay }
}

@MainActor
public enum HierRelations {
    public static func summary(_ i: HierarchyItem) -> HierItemSummary {
        HierItemSummary(id: i.id, kind: i.kind, name: i.name)
    }

    /// `RelatedItems(item)` with the one-way flag.
    public static func relatedRows(store: AppStore, item: HierarchyItem) -> [HierRelationRow] {
        let twoWay = Set(item.relatedIds)
        return store.relatedItems(of: item).map {
            HierRelationRow(item: summary($0), isOneWay: !twoWay.contains($0.id))
        }
    }

    /// `ReferencedBy(item)` (AllItems order).
    public static func backlinkRows(store: AppStore, item: HierarchyItem) -> [HierRelationRow] {
        store.referencedBy(item).map { HierRelationRow(item: summary($0), isOneWay: false) }
    }

    /// HIER-061 candidates: every top-level item except `item`, by kind (E, T, P, V) then Name ordinal-ignore-case
    /// (stable), displayed `"[{Kind}] {Name}"`.
    public static func candidates(store: AppStore, excluding item: HierarchyItem) -> [HierItemSummary] {
        let all = store.allItems().filter { $0.id != item.id }.map(summary)
        return all.enumerated().sorted { a, b in
            if a.element.kind.rawValue != b.element.kind.rawValue { return a.element.kind.rawValue < b.element.kind.rawValue }
            let c = NetText.compareIgnoreCase(a.element.name, b.element.name)
            return c == .orderedSame ? a.offset < b.offset : c == .orderedAscending
        }.map(\.element)
    }

    /// HIER-061 apply: `AddRelation(item, pick)` for each pick in selection order (two-way, no duplicates, self
    /// ignored). Returns how many links were new.
    @discardableResult
    public static func addRelations(store: AppStore, item: HierarchyItem, pickedIDs: [UUID]) -> Int {
        var n = 0
        for id in pickedIDs {
            guard let other = store.item(id: id), other.id != item.id else { continue }
            let before = item.relatedIds.contains(other.id) && other.relatedIds.contains(item.id)
            store.addRelation(item, other)
            if !before { n += 1 }
        }
        return n
    }
}

// MARK: Equipment link pickers (HIER-072/073, VIEW-212 rows 11–12, VIEW-215)

public struct HierLinkCandidate: Sendable, Hashable {
    public var id: UUID
    public var display: String
    public init(id: UUID, display: String) { self.id = id; self.display = display }
}

@MainActor
public enum HierLinkPicker {
    /// Every procedure in data order, display = bare name.
    public static func procedureCandidates(store: AppStore) -> [HierLinkCandidate] {
        store.data.procedures.map { HierLinkCandidate(id: $0.id, display: $0.name) }
    }

    /// Every top-level task in data order, display = bare name.
    public static func taskCandidates(store: AppStore) -> [HierLinkCandidate] {
        store.data.tasks.map { HierLinkCandidate(id: $0.id, display: $0.name) }
    }

    /// VIEW-215: the picker's result (selection order) replaces the stored list; ids without a candidate row are
    /// dropped and duplicates collapse (the picker can only return candidate rows, each once).
    public static func normalized(_ picked: [UUID], candidates: [HierLinkCandidate]) -> [UUID] {
        let valid = Set(candidates.map(\.id))
        var seen = Set<UUID>()
        return picked.filter { valid.contains($0) && seen.insert($0).inserted }
    }

    /// `Label(id)` rows of a one-way link list, in stored order (`"[Procedure] {Name}"` or `"(missing)"`).
    public static func labels(store: AppStore, ids: [UUID]) -> [(id: UUID, label: String, exists: Bool)] {
        ids.map { id in
            let exists = store.item(id: id) != nil
            return (id, store.label(for: id), exists)
        }
    }
}

// MARK: Router inputs the hierarchy pages publish (03 §6.5.1.10; T-KB-02/03/24/25/35/36/49…51)

public enum HierCommandState {
    /// The hierarchy sidebar's list state: ⌘⌫ "Move to Trash" (HIER-022 with the HIER-135 confirmation; plain ⌫ too,
    /// because it confirms), ↩ primary = Rename (T-KB-24).
    public static func sidebarList(selectionCount: Int) -> ShellListState {
        ShellListState(role: "hierarchySidebar", selectionCount: selectionCount, deleteTitle: HierText.moveToTrash,
                       hasDelete: true, hasPrimary: true)
    }

    /// The section's selection summary (Export as PDF / Print / Rename / Open in New Window enablement).
    public static func selection(primary: UUID?, count: Int, gated: Bool, detached: Bool) -> ShellHierarchySelection {
        ShellHierarchySelection(primary: primary, count: count, gated: gated, detached: detached)
    }
}
