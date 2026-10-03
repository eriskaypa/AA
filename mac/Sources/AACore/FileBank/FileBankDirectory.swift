// Spec: DECISIONS 05 (surface `FileItem.LinkedItemIds` — a "Linked to" column and item backlinks — and a UI for
//       `Container.SharedWithContainerIds`), 05 CONT-093 (Link to items picker: top-level items sorted by kind then
//       name, `[{Kind}] {Name}`), CONT-095 (shared containers must round-trip untouched), 07 VIEW-212 row 26 +
//       VIEW-215 (replace-and-normalise on OK: picker order, no stale ids, no duplicates, MarkDirty), 02 REPO-012
//       (`allContainers` order), ARCHITECTURE.md §9.7 (build lookups once per refresh, never per row).
import Foundation

// MARK: - Container owners

/// Who owns a container, for labels ("Shared from", backlinks "In") and navigation.
public struct FileBankOwner: Sendable, Hashable {
    public enum Role: Sendable, Hashable { case item, component, subtask, step, crewStep, savedListItem }

    public var role: Role
    /// `[Equipment] Main engine ▸ Turbocharger` — the REPO-014 `[{Kind}] {Name}` form plus the child chain.
    public var label: String
    /// The top-level hierarchy item to navigate to (nil for crew steps and saved-list items).
    public var itemID: UUID?
    /// The child to select inside that item (component / subtask / step), nil for the item itself.
    public var childID: UUID?
    /// The item whose password lock gates this container (its top-level item).
    public var gatingItemID: UUID?
    public var crewMemberID: UUID?
    public var savedListID: UUID?

    public init(role: Role, label: String, itemID: UUID? = nil, childID: UUID? = nil, gatingItemID: UUID? = nil,
                crewMemberID: UUID? = nil, savedListID: UUID? = nil) {
        self.role = role; self.label = label; self.itemID = itemID; self.childID = childID
        self.gatingItemID = gatingItemID; self.crewMemberID = crewMemberID; self.savedListID = savedListID
    }
}

/// One file linked to an item (backlink), with the container that holds it.
@MainActor public struct FileBankBacklink: @MainActor Identifiable {
    public let file: FileItem
    public let container: Container
    public let owner: FileBankOwner
    /// Unique per (container, entry) pair — FileItem ids are not globally unique (cut/paste, 05 §4.1).
    public var id: String { "\(ObjectIdentifier(container).hashValue)-\(ObjectIdentifier(file).hashValue)" }
}

/// A snapshot index of every container of the loaded data with its owner (REPO-012 order). Build it once per
/// refresh (it holds model references — never keep it across a reload, ARCH §2.4).
@MainActor public struct FileBankDirectory {
    public struct Entry {
        public let container: Container
        public let owner: FileBankOwner
    }

    public private(set) var entries: [Entry] = []
    private var byIdentity: [ObjectIdentifier: Int] = [:]

    public init(store: AppStore) {
        let d = store.data
        func kindLabel(_ i: HierarchyItem) -> String { "[\(i.kind.name)] \(i.name)" }
        for e in d.equipment {
            add(e.container, FileBankOwner(role: .item, label: kindLabel(e), itemID: e.id, gatingItemID: e.id))
            for c in e.components {
                add(c.container, FileBankOwner(role: .component, label: kindLabel(e) + " ▸ " + c.name, itemID: e.id,
                                               childID: c.id, gatingItemID: e.id))
            }
        }
        for t in d.tasks {
            add(t.container, FileBankOwner(role: .item, label: kindLabel(t), itemID: t.id, gatingItemID: t.id))
            var seen = Set<ObjectIdentifier>([ObjectIdentifier(t)])
            func walk(_ parent: TaskItem, _ prefix: String) {
                for s in parent.subtasks where seen.insert(ObjectIdentifier(s)).inserted {
                    let label = prefix + " ▸ " + s.name
                    add(s.container, FileBankOwner(role: .subtask, label: label, itemID: t.id, childID: s.id,
                                                   gatingItemID: t.id))
                    walk(s, label)
                }
            }
            walk(t, kindLabel(t))
        }
        for p in d.procedures {
            add(p.container, FileBankOwner(role: .item, label: kindLabel(p), itemID: p.id, gatingItemID: p.id))
            for s in p.steps {
                add(s.container, FileBankOwner(role: .step, label: kindLabel(p) + " ▸ " + s.title, itemID: p.id,
                                               childID: s.id, gatingItemID: p.id))
            }
        }
        for v in d.vessels {
            add(v.container, FileBankOwner(role: .item, label: kindLabel(v), itemID: v.id, gatingItemID: v.id))
        }
        for m in d.crew {
            for s in m.checklist {
                add(s.container, FileBankOwner(role: .crewStep, label: "[Crew] \(m.fullName) ▸ \(s.title)",
                                               crewMemberID: m.id))
            }
        }
        for l in d.checklistTemplates {
            for it in l.items {
                add(it.container, FileBankOwner(role: .savedListItem, label: "[Saved list] \(l.name) ▸ \(it.title)",
                                                savedListID: l.id))
            }
        }
    }

    private mutating func add(_ c: Container, _ owner: FileBankOwner) {
        let key = ObjectIdentifier(c)
        guard byIdentity[key] == nil else { return }       // a container reachable twice is listed once
        byIdentity[key] = entries.count
        entries.append(Entry(container: c, owner: owner))
    }

    /// The owner of a container of the loaded data (by identity); nil for a detached or unknown container.
    public func owner(of c: Container) -> FileBankOwner? {
        byIdentity[ObjectIdentifier(c)].map { entries[$0].owner }
    }

    /// Containers carrying an id (container ids are expected unique but never assumed so).
    public func containers(withID id: UUID) -> [Entry] { entries.filter { $0.container.id == id } }

    /// Containers whose `SharedWithContainerIds` names `c` (its files are "shared into" `c`), in REPO-012 order;
    /// `c` itself never counts.
    public func sharedInto(_ c: Container) -> [Entry] {
        entries.filter { $0.container !== c && $0.container.sharedWithContainerIds.contains(c.id) }
    }

    /// The containers `c` shares with (resolved ids, stored order; unresolved ids are skipped here and kept in data).
    public func sharedWith(_ c: Container) -> [Entry] {
        var out: [Entry] = []
        var seen = Set<ObjectIdentifier>()
        for id in c.sharedWithContainerIds {
            for e in containers(withID: id) where e.container !== c && seen.insert(ObjectIdentifier(e.container)).inserted {
                out.append(e)
            }
        }
        return out
    }

    /// Every file whose `LinkedItemIds` contains `itemID`, with its container and owner (REPO-012 order, then
    /// file order). The same entry object reachable from two containers appears once per container.
    public func backlinks(to itemID: UUID) -> [FileBankBacklink] {
        var out: [FileBankBacklink] = []
        for e in entries {
            for f in e.container.files where f.linkedItemIds.contains(itemID) {
                out.append(FileBankBacklink(file: f, container: e.container, owner: e.owner))
            }
        }
        return out
    }

    // MARK: Sharing edits (CONT-095 UI, DECISIONS 05)

    /// Candidates for "Share With…": every other container, `owner.label` as the row text, REPO-012 order.
    public func shareCandidates(excluding c: Container) -> [Entry] {
        entries.filter { $0.container !== c }
    }

    /// The new `SharedWithContainerIds` after a pick: the picked ids (duplicates collapsed, pick order) followed
    /// by every stored id that names no container of the loaded data (kept untouched — they may belong to data
    /// this build cannot see). Returns nil when nothing changes.
    public func applyingSharePick(_ picked: [UUID], to c: Container) -> [UUID]? {
        var out: [UUID] = []
        var seen = Set<UUID>()
        for id in picked where id != c.id && seen.insert(id).inserted { out.append(id) }
        for id in c.sharedWithContainerIds where containers(withID: id).isEmpty && seen.insert(id).inserted {
            out.append(id)
        }
        return out == c.sharedWithContainerIds ? nil : out
    }
}

// MARK: - Link to items (CONT-093, VIEW-212 row 26, VIEW-215)

@MainActor public enum FileBankLinkPicker {
    public struct Row: Sendable, Hashable {
        public let display: String
        public let id: UUID
    }

    /// Every top-level Equipment, Task, Procedure and Vessel (no subtasks, steps or components), sorted by kind
    /// (Equipment, Task, Procedure, Vessel) then by name with `OrdinalIgnoreCase`, stable; text `[{Kind}] {Name}`
    /// with the enum name.
    public static func rows(_ store: AppStore) -> [Row] {
        func order(_ k: ItemKind) -> Int {
            switch k {
            case .equipment: return 0
            case .task: return 1
            case .procedure: return 2
            case .vessel: return 3
            default: return 99
            }
        }
        let items = store.allItems()
        let sorted = items.indices.sorted { a, b in
            let ia = items[a], ib = items[b]
            let ka = order(ia.kind), kb = order(ib.kind)
            if ka != kb { return ka < kb }
            switch NetText.compareIgnoreCase(ia.name, ib.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a < b
            }
        }
        return sorted.map { Row(display: "[\(items[$0].kind.name)] \(items[$0].name)", id: items[$0].id) }
    }

    /// VIEW-215 replace-and-normalise: the picker result (picker order, rows identified by index so equal ids can
    /// come back twice) becomes the new `LinkedItemIds` with duplicates collapsed (first wins).
    public static func normalized(_ picked: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return picked.filter { seen.insert($0).inserted }
    }

    /// Applies an OK: replaces `LinkedItemIds` (even when unchanged — Windows parity) and marks the store dirty.
    public static func apply(_ picked: [UUID], to file: FileItem, store: AppStore) {
        file.linkedItemIds = normalized(picked)
        store.markDirty()
    }
}

/// Item names by id for the "Linked to" column (built once per refresh, first wins in E → T → P → V order).
@MainActor public struct FileBankItemIndex {
    private var names: [UUID: (name: String, kind: ItemKind)] = [:]

    public init(store: AppStore) {
        for i in store.allItems() where names[i.id] == nil { names[i.id] = (i.name, i.kind) }
    }

    public func name(of id: UUID) -> String? { names[id]?.name }
    public func kind(of id: UUID) -> ItemKind? { names[id]?.kind }

    /// The column text: linked item names in stored order, joined with ", "; ids that name no item (trashed or
    /// purged elsewhere) are skipped.
    public func linkedSummary(_ ids: [UUID]) -> String {
        ids.compactMap { names[$0]?.name }.joined(separator: ", ")
    }
}
