// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 02 REPO-100…105 (search documents, scan, snippets; OC-11: locked items → Name and Tags only), DECISIONS
// 02 Q-11 (a hit selects the matched child). Compiling stub created by F1; F2 replaces this file in place. The
// stubs build no documents and find nothing (ARCH §11).
import Foundation

public enum SearchHitKind: String, Sendable {
    case item = "Item", component = "Component", subtask = "Subtask", step = "Step", file = "File"
}

public struct SearchField: Sendable, Hashable {
    public var kind: SearchHitKind
    public var whereLabel: String
    public var text: String
    public var childID: UUID?

    public init(kind: SearchHitKind, whereLabel: String, text: String, childID: UUID? = nil) {
        self.kind = kind; self.whereLabel = whereLabel; self.text = text; self.childID = childID
    }
}

/// A Sendable snapshot of one top-level item, built on the main actor and scanned off-main.
public struct SearchDocument: Sendable {
    public var ownerID: UUID
    public var ownerKind: ItemKind
    public var ownerHeader: String
    public var fields: [SearchField]

    public init(ownerID: UUID, ownerKind: ItemKind, ownerHeader: String, fields: [SearchField]) {
        self.ownerID = ownerID; self.ownerKind = ownerKind; self.ownerHeader = ownerHeader; self.fields = fields
    }
}

public struct SearchHit: Sendable, Identifiable, Hashable {
    public var id: Int
    public var ownerID: UUID
    public var ownerKind: ItemKind
    public var ownerHeader: String
    public var kind: SearchHitKind
    public var whereLabel: String
    public var snippet: String
    public var matchStart: Int
    public var matchLength: Int
    public var childID: UUID?

    public init(id: Int, ownerID: UUID, ownerKind: ItemKind, ownerHeader: String, kind: SearchHitKind,
                whereLabel: String, snippet: String, matchStart: Int, matchLength: Int, childID: UUID? = nil) {
        self.id = id; self.ownerID = ownerID; self.ownerKind = ownerKind; self.ownerHeader = ownerHeader
        self.kind = kind; self.whereLabel = whereLabel; self.snippet = snippet; self.matchStart = matchStart
        self.matchLength = matchLength; self.childID = childID
    }
}

public enum SearchService {
    public static let maxHits = 500

    @MainActor public static func makeDocuments(store: AppStore, isGated: (HierarchyItem) -> Bool) -> [SearchDocument] {
        // PLACEHOLDER(F2)
        []
    }

    public static func search(_ docs: [SearchDocument], query: String,
                              isCancelled: @Sendable () -> Bool = { false }) -> [SearchHit] {
        // PLACEHOLDER(F2)
        []
    }

    public static func makeSnippet(text: String, matchIndex: Int, matchLength: Int) -> (snippet: String, start: Int) {
        // PLACEHOLDER(F2)
        (snippet: "", start: 0)
    }
}
