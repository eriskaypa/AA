// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 08 §3.7, 01 §3.15 (change preview), DECISIONS 01 Q-3 ("Other data"), OC-13. Compiling stub created by F1;
// F2 replaces this file in place. The stubs report no changes (ARCH §11).
import Foundation

public struct DiffNode: Sendable, Identifiable, Hashable {
    public enum Change: Int, Sendable { case added, removed, changed }
    public var id: UUID
    public var change: Change
    public var text: String
    public var children: [DiffNode]

    public init(id: UUID = UUID(), change: Change, text: String, children: [DiffNode] = []) {
        self.id = id; self.change = change; self.text = text; self.children = children
    }
}

public struct DiffResult: Sendable {
    public var roots: [DiffNode]
    public var added: Int
    public var removed: Int
    public var changed: Int
    public var hasChanges: Bool { added + removed + changed > 0 }

    public init(roots: [DiffNode] = [], added: Int = 0, removed: Int = 0, changed: Int = 0) {
        self.roots = roots; self.added = added; self.removed = removed; self.changed = changed
    }
}

/// Runs on the main actor (it walks models); callers show `AAProgressOverlay` when it is slow.
@MainActor public enum DataDiff {
    /// Windows scope (+ OC-13).
    public static func compare(current: AppData, incoming: AppData) -> DiffResult {
        // PLACEHOLDER(F2)
        DiffResult()
    }

    /// DECISIONS 01 Q-3 "Other data" (crew, saved lists, ports, SIRE).
    public static func compareOtherData(current: AppData, incoming: AppData) -> DiffResult {
        // PLACEHOLDER(F2)
        DiffResult()
    }

    public static func snip(_ s: String?) -> String {
        // PLACEHOLDER(F2)
        ""
    }
}
