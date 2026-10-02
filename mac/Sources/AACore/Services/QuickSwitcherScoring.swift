// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 02 REPO-107, 08 QUICK-104/105 (quick-switcher rows and scoring). Compiling stub created by F1; F2 replaces
// this file in place. The stubs return no rows and score 0 (ARCH §11).
import Foundation

public enum QuickSwitcherScoring {
    public struct Row: Sendable, Identifiable, Hashable {
        public var id: UUID
        public var name: String
        public var kind: ItemKind
        public var kindLabel: String
        public var tags: [String]
        public var description: String

        public init(id: UUID, name: String, kind: ItemKind, kindLabel: String, tags: [String], description: String) {
            self.id = id; self.name = name; self.kind = kind; self.kindLabel = kindLabel; self.tags = tags
            self.description = description
        }
    }

    @MainActor public static func rows(store: AppStore) -> [Row] {
        // PLACEHOLDER(F2)
        []
    }

    public static func normalizeQuery(_ q: String) -> String {
        // PLACEHOLDER(F2)
        ""
    }

    public static func score(_ row: Row, query: String) -> Int {
        // PLACEHOLDER(F2)
        0
    }

    public static func rank(_ rows: [Row], query: String, limit: Int = 80) -> [Row] {
        // PLACEHOLDER(F2)
        []
    }
}
