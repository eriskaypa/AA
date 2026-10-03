// Spec: 04 HIER-025 (each keystroke re-labels the selected row in place with no list rebuild; Enter or focus loss
//       commits: rebuild, re-sort, re-select), HIER-125 / §8 Q-07 (live refresh from any page or window),
//       HIER-117 (item-window name edits re-label the sidebar live), HIER-056 (Tools ▸ Lock Now re-loads the hosted
//       editor); 05 CONT-007 (legacy encrypted bodies), CONT-060…062 + DEVIATIONS 05 D-4 (a lock/unlock run from
//       inside the editor keeps the editor: caret, scroll and undo); ARCHITECTURE.md §2.4, §9.7.
import Foundation

/// What the sidebar must rebuild on: every structural change of the kind's collection and its groups, made from any
/// page or window (HIER-125, §8 Q-07). The name being typed in the page's own Name box is left out (HIER-025).
public struct HierStructureSignature: Equatable {
    public var generation: Int
    public var ids: [UUID]
    public var groupIDs: [UUID?]
    public var names: [String]
    public var tags: [[String]]
    public var groups: [String]
    public var sortAZ: Bool

    @MainActor
    public init(store: AppStore, kind: ItemKind, editingNameID: UUID?, includeTags: Bool) {
        let items = store.items(of: kind)
        generation = store.generation
        ids = items.map(\.id)
        groupIDs = items.map(\.groupId)
        names = items.map { $0.id == editingNameID ? "" : $0.name }
        tags = includeTags ? items.map(\.tags) : []
        groups = store.groups(for: kind).map { "\($0.id.netString)|\($0.name)" }
        sortAZ = HierUiState.sortAZ(store.data.ui, kind: kind)
    }
}

/// HIER-025 commit rule for the page's Name box.
public enum HierRenameState {
    /// The item still excluded from the rebuild signature after a commit: the one whose Name box keeps the focus
    /// after Return (when it is still the details item); nil after focus loss. Without it, every keystroke typed
    /// after Return would rebuild and re-sort the whole sidebar.
    public static func editingAfterCommit(stillEditing: UUID?, primary: UUID?) -> UUID? {
        guard let id = stillEditing, id == primary else { return nil }
        return id
    }
}

/// When a hosted container editor (main pane, item window) must be rebuilt because the app-password session changed.
public enum HierEditorReload {
    /// Unlocked → locked (Tools ▸ Lock Now, a settings reload): always — Windows `RelockCurrent` re-loads the editor
    /// (HIER-056). Locked → unlocked: only while the container still holds a legacy encrypted body that the session
    /// can now decrypt (CONT-007); an unlock made by the editor's own CONT-062 gate (🔒/🔓 on a selection) keeps the
    /// editor, so its caret, scroll position and undo stack survive (D-4).
    public static func onSessionChange(wasUnlocked: Bool, isUnlocked: Bool, bodyIsLegacyEncrypted: Bool) -> Bool {
        if wasUnlocked && !isUnlocked { return true }
        if !wasUnlocked && isUnlocked { return bodyIsLegacyEncrypted }
        return false
    }
}
