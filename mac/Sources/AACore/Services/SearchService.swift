// Spec: 02 §2.J, §3.2 (REPO-100…105), §7.7; 08 §3.4, §7.4 (T-SR-*); OC-11 (a gated item: Name and Tags only);
//       DECISIONS 02 Q-11 (a hit carries the matched child's id); 10 VESSEL-283 (vessel work orders, quick cards and
//       ports are not searched); ARCHITECTURE.md §6.5, §9.7 (documents are built on the main actor, scanned off it).
// Offsets (`matchStart`, `matchLength`) are UTF-16 code units, exactly as in C#.
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
    /// REPO-101: scanning stops as soon as this many hits exist.
    public static let maxHits = 500

    /// REPO-101 / REPO-102: one document per top-level item (Equipment, Tasks, Procedures, Vessels order) with its
    /// fields in scan order — Name; Tags (joined `", "`, only when present); then, unless `isGated(item)` (locked
    /// and not unlocked this session: Name and Tags only, OC-11), Description; Notes (plain text of the
    /// container, REPO-104); each file's name and stored path (`File › {Kind}` / `File › {Kind} › Path`); and the
    /// children — components (`Component › Name/Notes/Container/File`), nested subtasks depth-first
    /// (`Subtask › Name/Description/Container/File`), steps (`Step › Title/Container/File`). Empty fields are
    /// dropped (they can never match). The document header is `"[{Kind}] {Name}"` (enum name).
    @MainActor public static func makeDocuments(store: AppStore, isGated: (HierarchyItem) -> Bool) -> [SearchDocument] {
        var docs: [SearchDocument] = []
        for item in store.allItems() {
            var fields: [SearchField] = []
            func add(_ kind: SearchHitKind, _ label: String, _ text: String, _ child: UUID? = nil) {
                if !text.isEmpty { fields.append(SearchField(kind: kind, whereLabel: label, text: text, childID: child)) }
            }
            func addFiles(_ c: Container, _ kind: SearchHitKind, _ label: String, _ child: UUID) {
                for f in c.files { add(kind, label, f.name, child) }
            }
            add(.item, "Name", item.name)
            if !item.tags.isEmpty { add(.item, "Tags", item.tags.joined(separator: ", ")) }
            if !isGated(item) {
                add(.item, "Description", item.description)
                add(.item, "Notes", XamlPlainText.searchText(item.container.richTextXaml))
                for f in item.container.files {
                    add(.file, "File \u{203A} \(f.kind.name)", f.name)
                    add(.file, "File \u{203A} \(f.kind.name) \u{203A} Path", f.path)
                }
                switch item {
                case let e as Equipment:
                    for c in e.components {
                        add(.component, "Component \u{203A} Name", c.name, c.id)
                        add(.component, "Component \u{203A} Notes", c.notes, c.id)
                        add(.component, "Component \u{203A} Container", XamlPlainText.searchText(c.container.richTextXaml), c.id)
                        addFiles(c.container, .component, "Component \u{203A} File", c.id)
                    }
                case let t as TaskItem:
                    var seen = Set<ObjectIdentifier>([ObjectIdentifier(t)])
                    func walk(_ parent: TaskItem) {
                        for s in parent.subtasks where seen.insert(ObjectIdentifier(s)).inserted {
                            add(.subtask, "Subtask \u{203A} Name", s.name, s.id)
                            add(.subtask, "Subtask \u{203A} Description", s.description, s.id)
                            add(.subtask, "Subtask \u{203A} Container", XamlPlainText.searchText(s.container.richTextXaml), s.id)
                            addFiles(s.container, .subtask, "Subtask \u{203A} File", s.id)
                            walk(s)
                        }
                    }
                    walk(t)
                case let p as Procedure:
                    for s in p.steps {
                        add(.step, "Step \u{203A} Title", s.title, s.id)
                        add(.step, "Step \u{203A} Container", XamlPlainText.searchText(s.container.richTextXaml), s.id)
                        addFiles(s.container, .step, "Step \u{203A} File", s.id)
                    }
                default:
                    break
                }
            }
            docs.append(SearchDocument(ownerID: item.id, ownerKind: item.kind,
                                       ownerHeader: "[\(item.kind.name)] \(item.name)", fields: fields))
        }
        return docs
    }

    /// REPO-101: the query is trimmed (blank → no hits); each field yields at most one hit, at its first
    /// case-insensitive ordinal occurrence; at most `maxHits` hits. `isCancelled` is polled between documents.
    public static func search(_ docs: [SearchDocument], query: String,
                              isCancelled: @Sendable () -> Bool = { false }) -> [SearchHit] {
        guard !NetText.isBlank(query) else { return [] }
        let q = NetText.trim(query)
        let qLength = q.utf16.count
        var hits: [SearchHit] = []
        for doc in docs {
            if hits.count >= maxHits || isCancelled() { break }
            for f in doc.fields {
                if hits.count >= maxHits { break }
                guard let idx = NetText.indexOfIgnoreCase(f.text, q) else { continue }
                let (snippet, start) = makeSnippet(text: f.text, matchIndex: idx, matchLength: qLength)
                hits.append(SearchHit(id: hits.count, ownerID: doc.ownerID, ownerKind: doc.ownerKind,
                                      ownerHeader: doc.ownerHeader, kind: f.kind, whereLabel: f.whereLabel,
                                      snippet: snippet, matchStart: start, matchLength: qLength, childID: f.childID))
            }
        }
        return hits
    }

    /// REPO-103: up to 60 UTF-16 units either side of the match, `…` where cut, every run of white space collapsed to
    /// one space (no trimming), and the match offset recomputed by searching the compacted snippet for the matched
    /// text (falling back to `prefix + (idx − start)` when the match itself contained a collapsed run).
    public static func makeSnippet(text: String, matchIndex: Int, matchLength: Int) -> (snippet: String, start: Int) {
        let u = Array(text.utf16)
        let idx = min(max(matchIndex, 0), u.count)
        var start = max(0, idx - 60)
        var end = min(u.count, idx + max(0, matchLength) + 60)
        // Never cut a surrogate pair in half (Swift cannot hold a lone surrogate; .NET would keep it).
        if start > 0, start < u.count, UTF16.isTrailSurrogate(u[start]) { start -= 1 }
        if end < u.count, end > 0, UTF16.isLeadSurrogate(u[end - 1]) { end += 1 }
        var s: [UInt16] = []
        let prefix = start > 0 ? 1 : 0
        if start > 0 { s.append(0x2026) }
        s.append(contentsOf: u[start..<end])
        if end < u.count { s.append(0x2026) }
        var compact: [UInt16] = []
        compact.reserveCapacity(s.count)
        var inSpace = false
        for c in s {
            if NetText.isWhiteSpace(c) {
                if !inSpace { compact.append(0x20); inSpace = true }
            } else {
                compact.append(c)
                inSpace = false
            }
        }
        let snippet = String(decoding: compact, as: UTF16.self)
        let matchEnd = min(u.count, idx + max(0, matchLength))
        let matched = String(decoding: u[idx..<matchEnd], as: UTF16.self)
        let newIndex = NetText.indexOfIgnoreCase(snippet, matched) ?? (prefix + (idx - start))
        return (snippet, newIndex)
    }
}
