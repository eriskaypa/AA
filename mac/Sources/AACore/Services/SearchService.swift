// Spec: 02 §2.J, §3.2 (REPO-100…105), §7.7; 08 §3.4, §7.4 (T-SR-*); OC-11 (a gated item: Name and Tags only);
//       DECISIONS 02 Q-11 (a hit carries the matched child's id); 10 VESSEL-283 (vessel work orders, quick cards and
//       ports are not searched); ARCHITECTURE.md §6.5, §9.7 (the snapshot is taken on the main actor; Stage V2
//       V2-SCALE: the XAML → plain-text conversion and the scan run off it, memoised by `SearchTextCache`).
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

/// V2-SCALE: the main-actor snapshot of the search scope — each field's raw text, container XAML still unconverted
/// (`SearchService.snapshot` → `SearchService.documents(from:)` off the main actor).
public struct SearchSnapshot: Sendable {
    public struct Field: Sendable {
        public var kind: SearchHitKind
        public var whereLabel: String
        public var raw: String
        /// `raw` is container XAML (REPO-104 plain text is taken off-main).
        public var isXaml: Bool
        public var childID: UUID?
    }

    public struct Document: Sendable {
        public var ownerID: UUID
        public var ownerKind: ItemKind
        public var ownerHeader: String
        public var fields: [Field]
    }

    public var documents: [Document]
}

/// V2-SCALE: XAML → search plain text memo shared by every `SearchService.documents(from:)` pass. Thread-safe; each
/// pass replaces the table with the entries it used, so it holds the current database's notes only.
public final class SearchTextCache: @unchecked Sendable {
    public static let shared = SearchTextCache()

    private let lock = NSLock()
    private var table: [String: String] = [:]
    private var parsedTotal = 0

    public init() {}

    /// Entries currently held.
    public var count: Int { lock.lock(); defer { lock.unlock() }; return table.count }

    /// XAML strings actually parsed since creation (cache misses).
    public var conversions: Int { lock.lock(); defer { lock.unlock() }; return parsedTotal }

    struct Pass {
        let cache: SearchTextCache
        let previous: [String: String]
        var used: [String: String] = [:]
        var parsed = 0

        init(_ cache: SearchTextCache) {
            self.cache = cache
            cache.lock.lock(); previous = cache.table; cache.lock.unlock()
        }

        mutating func plainText(_ xaml: String) -> String {
            if let t = used[xaml] { return t }
            let t: String
            if let hit = previous[xaml] { t = hit } else { t = XamlPlainText.searchText(xaml); parsed += 1 }
            used[xaml] = t
            return t
        }

        func commit() {
            cache.lock.lock(); defer { cache.lock.unlock() }
            cache.table = used
            cache.parsedTotal += parsed
        }
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
    /// Synchronous convenience = `documents(from: snapshot(…))` — the whole XAML → plain-text conversion runs on the
    /// caller's (main) actor. The Search window takes the `snapshot` on main and calls `documents(from:)` off it
    /// (Stage V2 V2-SCALE: 779 ms of main-thread blocking per query on a full ship database otherwise).
    @MainActor public static func makeDocuments(store: AppStore, isGated: (HierarchyItem) -> Bool) -> [SearchDocument] {
        documents(from: snapshot(store: store, isGated: isGated))
    }

    /// V2-SCALE, main-actor half: walks the live graph and copies every field's RAW text (container XAML is NOT
    /// converted here; Swift strings are copy-on-write, so this is a reference walk). The gate is decided here, on
    /// the main actor. Cheap enough to run per query (no XML parsing).
    @MainActor public static func snapshot(store: AppStore, isGated: (HierarchyItem) -> Bool) -> SearchSnapshot {
        var docs: [SearchSnapshot.Document] = []
        for item in store.allItems() {
            var fields: [SearchSnapshot.Field] = []
            func add(_ kind: SearchHitKind, _ label: String, _ text: String, _ child: UUID? = nil, xaml: Bool = false) {
                if !text.isEmpty {
                    fields.append(SearchSnapshot.Field(kind: kind, whereLabel: label, raw: text, isXaml: xaml,
                                                       childID: child))
                }
            }
            func addFiles(_ c: Container, _ kind: SearchHitKind, _ label: String, _ child: UUID) {
                for f in c.files { add(kind, label, f.name, child) }
            }
            add(.item, "Name", item.name)
            if !item.tags.isEmpty { add(.item, "Tags", item.tags.joined(separator: ", ")) }
            if !isGated(item) {
                add(.item, "Description", item.description)
                add(.item, "Notes", item.container.richTextXaml, xaml: true)
                for f in item.container.files {
                    add(.file, "File \u{203A} \(f.kind.name)", f.name)
                    add(.file, "File \u{203A} \(f.kind.name) \u{203A} Path", f.path)
                }
                switch item {
                case let e as Equipment:
                    for c in e.components {
                        add(.component, "Component \u{203A} Name", c.name, c.id)
                        add(.component, "Component \u{203A} Notes", c.notes, c.id)
                        add(.component, "Component \u{203A} Container", c.container.richTextXaml, c.id, xaml: true)
                        addFiles(c.container, .component, "Component \u{203A} File", c.id)
                    }
                case let t as TaskItem:
                    var seen = Set<ObjectIdentifier>([ObjectIdentifier(t)])
                    func walk(_ parent: TaskItem) {
                        for s in parent.subtasks where seen.insert(ObjectIdentifier(s)).inserted {
                            add(.subtask, "Subtask \u{203A} Name", s.name, s.id)
                            add(.subtask, "Subtask \u{203A} Description", s.description, s.id)
                            add(.subtask, "Subtask \u{203A} Container", s.container.richTextXaml, s.id, xaml: true)
                            addFiles(s.container, .subtask, "Subtask \u{203A} File", s.id)
                            walk(s)
                        }
                    }
                    walk(t)
                case let p as Procedure:
                    for s in p.steps {
                        add(.step, "Step \u{203A} Title", s.title, s.id)
                        add(.step, "Step \u{203A} Container", s.container.richTextXaml, s.id, xaml: true)
                        addFiles(s.container, .step, "Step \u{203A} File", s.id)
                    }
                default:
                    break
                }
            }
            docs.append(SearchSnapshot.Document(ownerID: item.id, ownerKind: item.kind,
                                                ownerHeader: "[\(item.kind.name)] \(item.name)", fields: fields))
        }
        return SearchSnapshot(documents: docs)
    }

    /// V2-SCALE, off-main half (any thread): converts every XAML field to its REPO-104 plain text
    /// (`XamlPlainText.searchText`) and drops fields that end up empty. Conversions are memoised in `cache` by the
    /// raw XAML, so a repeat query over an unchanged database parses nothing; the cache keeps only the XAML of the
    /// latest pass (edited notes do not accumulate).
    public static func documents(from snapshot: SearchSnapshot,
                                 cache: SearchTextCache = .shared) -> [SearchDocument] {
        var pass = SearchTextCache.Pass(cache)
        let docs = snapshot.documents.map { d -> SearchDocument in
            var fields: [SearchField] = []
            fields.reserveCapacity(d.fields.count)
            for f in d.fields {
                let text = f.isXaml ? pass.plainText(f.raw) : f.raw
                if !text.isEmpty {
                    fields.append(SearchField(kind: f.kind, whereLabel: f.whereLabel, text: text, childID: f.childID))
                }
            }
            return SearchDocument(ownerID: d.ownerID, ownerKind: d.ownerKind, ownerHeader: d.ownerHeader,
                                  fields: fields)
        }
        pass.commit()
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
