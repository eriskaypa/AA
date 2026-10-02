// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §5.3
// Spec: 02 §2.L (sidebar groups). Compiling stub created by F1; F2 replaces this file in place. `createGroup`
// returns a DETACHED group (never inserted); the other stubs are no-ops (ARCH §11).
import Foundation

extension AppStore {
    public func groups(for kind: ItemKind) -> [ItemGroup] {
        // PLACEHOLDER(F2)
        []
    }

    @discardableResult public func createGroup(kind: ItemKind, name: String) -> ItemGroup {
        // PLACEHOLDER(F2)
        ItemGroup(kind: kind, name: name)
    }

    public func renameGroup(_ g: ItemGroup, to name: String) {
        // PLACEHOLDER(F2)
    }

    public func deleteGroup(_ g: ItemGroup) {
        // PLACEHOLDER(F2)
    }

    public func assign(_ items: [HierarchyItem], toGroup groupID: UUID?) {
        // PLACEHOLDER(F2)
    }
}
