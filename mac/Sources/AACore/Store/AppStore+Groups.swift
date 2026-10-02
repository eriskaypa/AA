// Spec: 02 §2.L, §3.1.7 (REPO-120), 01 §3.24 (DATA-136); ARCHITECTURE.md §5.3. None of these save or mark dirty —
//       callers `Save()` (02 REPO-120).
import Foundation

extension AppStore {
    /// `Data.Groups` filtered by kind, in collection order.
    public func groups(for kind: ItemKind) -> [ItemGroup] {
        data.groups.filter { $0.kind == kind }
    }

    /// Appends a group named `name` trimmed, or `"New group"` when blank, and returns it.
    @discardableResult public func createGroup(kind: ItemKind, name: String) -> ItemGroup {
        let g = ItemGroup(kind: kind, name: NetText.isBlank(name) ? "New group" : NetText.trim(name))
        data.groups.append(g)
        return g
    }

    /// Ignored when blank; else the trimmed name.
    public func renameGroup(_ g: ItemGroup, to name: String) {
        guard !NetText.isBlank(name) else { return }
        g.name = NetText.trim(name)
    }

    /// Every top-level item of ANY kind with `GroupId == g.Id` becomes ungrouped, then the group is removed.
    public func deleteGroup(_ g: ItemGroup) {
        for i in allItems() where i.groupId == g.id { i.groupId = nil }
        if let k = data.groups.firstIndex(where: { $0 === g }) ?? data.groups.firstIndex(where: { $0.id == g.id }) {
            data.groups.remove(at: k)
        }
    }

    /// `AssignToGroup`: sets `GroupId` (nil = ungrouped) on every given item.
    public func assign(_ items: [HierarchyItem], toGroup groupID: UUID?) {
        for i in items where i.groupId != groupID { i.groupId = groupID }
    }
}
