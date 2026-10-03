// Spec: 08 §2.2 (QUICK-042…049, QUICK-060…062), §3.2 (`RefreshPending` row building and sort — exact; `Subtitle`;
//       `RefreshPinned`; `BuildTile`; `ChildProgress`), §6.3 (pure, injected `today`), §7.2 (T-QW-1…6, T-QW-12);
//       07 VIEW-153 (an item shows under each of its — at most two — buckets), VIEW-154 (BucketId migrated by F1).
import Foundation

/// The All / Tasks / Procedures radio group (08 QUICK-042).
public enum QuickWorkFilter: String, Sendable, Hashable, CaseIterable {
    case all = "All", tasks = "Tasks", procedures = "Procedures"
}

/// One left-list row: an item under one of its buckets (or `(No bucket)`).
public struct QuickWorkRow: Sendable, Identifiable, Hashable {
    /// `"{item id}|{bucket key}"` (08 §6.2-B `RowID`).
    public var id: String { "\(itemID.netString)|\(bucketKey)" }
    public var itemID: UUID
    public var kind: ItemKind
    public var title: String
    public var subtitle: String
    public var isDone: Bool
    /// Display name of the group: bucket name, `(unnamed bucket)` or `(No bucket)`.
    public var bucket: String
    /// Group key: the bucket id (lower-case) or `""` for none.
    public var bucketKey: String
    /// Group ordering: lower-cased bucket name; `(No bucket)` sorts last explicitly.
    public var bucketSort: String
    public var deadlineTicks: Int64?

    public init(itemID: UUID, kind: ItemKind, title: String, subtitle: String, isDone: Bool, bucket: String,
                bucketKey: String, bucketSort: String, deadlineTicks: Int64?) {
        self.itemID = itemID; self.kind = kind; self.title = title; self.subtitle = subtitle; self.isDone = isDone
        self.bucket = bucket; self.bucketKey = bucketKey; self.bucketSort = bucketSort; self.deadlineTicks = deadlineTicks
    }
}

/// A bucket group of the left list (absent when no bucket is defined at all).
public struct QuickWorkGroup: Sendable, Identifiable, Hashable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var rows: [QuickWorkRow]

    public init(key: String, name: String, rows: [QuickWorkRow]) { self.key = key; self.name = name; self.rows = rows }

    /// `🪣 {name} ({rowCount})` (08 QUICK-046; the Mac draws the bucket with an SF Symbol, the text keeps the count).
    public var header: String { "\u{1FAA3} \(name) (\(rows.count))" }
}

public struct QuickWorkListing: Sendable, Hashable {
    /// Sorted rows (flat order = group order then row order).
    public var rows: [QuickWorkRow]
    /// Bucket groups in display order; empty when no bucket is defined (flat list).
    public var groups: [QuickWorkGroup]
    public var isGrouped: Bool
    public var countLine: String
    public var itemCount: Int

    public init(rows: [QuickWorkRow] = [], groups: [QuickWorkGroup] = [], isGrouped: Bool = false, countLine: String = "0 item(s).",
                itemCount: Int = 0) {
        self.rows = rows; self.groups = groups; self.isGrouped = isGrouped; self.countLine = countLine
        self.itemCount = itemCount
    }
}

/// A pinned square (08 QUICK-062).
public struct QuickWorkTile: Sendable, Identifiable, Hashable {
    public var id: UUID
    public var kind: ItemKind
    public var name: String
    public var isDone: Bool
    /// `1/3 subtasks done`, `0/1 step done`, `completed`, `no items yet`.
    public var progressText: String
    /// Done / total of direct children (total 0 = no children → no bar).
    public var progressDone: Int
    public var progressTotal: Int
    /// `OVERDUE 09-28` / `due 09-28`, nil without a deadline.
    public var deadlineText: String?
    public var deadlineIsOverdue: Bool

    public init(id: UUID, kind: ItemKind, name: String, isDone: Bool, progressText: String,
                progressDone: Int, progressTotal: Int, deadlineText: String?, deadlineIsOverdue: Bool) {
        self.id = id; self.kind = kind; self.name = name; self.isDone = isDone; self.progressText = progressText
        self.progressDone = progressDone; self.progressTotal = progressTotal; self.deadlineText = deadlineText
        self.deadlineIsOverdue = deadlineIsOverdue
    }

    /// The bar fraction (0 when there are no children).
    public var fraction: Double { progressTotal > 0 ? Double(progressDone) / Double(progressTotal) : 0 }

    /// Header line `✓ Task` / `📋 Procedure` (the Mac shows the glyph as an SF Symbol).
    public var kindLabel: String { kind == .task ? "Task" : "Procedure" }
    public var displayName: String { NetText.isBlank(name) ? "(unnamed)" : name }
}

@MainActor public enum QuickWorkRows {
    /// 08 QUICK-043…048 / §3.2 `RefreshPending`: top-level Tasks then Procedures (filter), name contains the trimmed
    /// query (OrdinalIgnoreCase); one row per distinct valid bucket (ids that no longer resolve are ignored, a
    /// duplicate collapsed) or one `(No bucket)` row; grouped when any bucket is defined (group by lower-cased bucket
    /// name, then bucket id; `(No bucket)` last); within a group: active before done → deadline ascending (no deadline
    /// last) → title (culture-aware). The count line counts distinct items.
    public static func build(store: AppStore, filter: QuickWorkFilter, query: String, today: CivilDate,
                             locale: Locale = .current) -> QuickWorkListing {
        let q = NetText.trim(query)
        var items: [HierarchyItem] = []
        if filter != .procedures { items.append(contentsOf: store.data.tasks as [HierarchyItem]) }
        if filter != .tasks { items.append(contentsOf: store.data.procedures as [HierarchyItem]) }
        if !q.isEmpty { items = items.filter { NetText.containsIgnoreCase($0.name, q) } }

        var bucketByID: [UUID: QuickBucket] = [:]
        for b in store.data.quickBuckets where bucketByID[b.id] == nil { bucketByID[b.id] = b }

        var rows: [QuickWorkRow] = []
        for i in items {
            let title = NetText.isBlank(i.name) ? "(unnamed)" : i.name
            let sub = subtitle(i, today: today)
            let done = isDone(i)
            let dl = deadline(i)?.ticks
            var seen = Set<UUID>()
            let buckets = i.bucketIds.compactMap { id -> QuickBucket? in
                guard let b = bucketByID[id], seen.insert(b.id).inserted else { return nil }
                return b
            }
            if buckets.isEmpty {
                rows.append(QuickWorkRow(itemID: i.id, kind: i.kind, title: title, subtitle: sub, isDone: done,
                                         bucket: "(No bucket)", bucketKey: "", bucketSort: "", deadlineTicks: dl))
            } else {
                for b in buckets {
                    let bn = b.name.isEmpty ? "(unnamed bucket)" : b.name
                    rows.append(QuickWorkRow(itemID: i.id, kind: i.kind, title: title, subtitle: sub, isDone: done,
                                             bucket: bn, bucketKey: b.id.netString,
                                             bucketSort: NetText.toLowerInvariant(bn), deadlineTicks: dl))
                }
            }
        }
        let grouped = !store.data.quickBuckets.isEmpty
        func culture(_ a: String, _ b: String) -> ComparisonResult { a.compare(b, options: [], range: nil, locale: locale) }
        let sorted = rows.enumerated().sorted { x, y in
            let a = x.element, b = y.element
            if grouped {
                let aNone = a.bucketKey.isEmpty, bNone = b.bucketKey.isEmpty
                if aNone != bNone { return bNone }
                let c = culture(a.bucketSort, b.bucketSort)
                if c != .orderedSame { return c == .orderedAscending }
                let k = culture(a.bucketKey, b.bucketKey)
                if k != .orderedSame { return k == .orderedAscending }
            }
            if a.isDone != b.isDone { return !a.isDone }
            let da = a.deadlineTicks ?? Int64.max, db = b.deadlineTicks ?? Int64.max
            if da != db { return da < db }
            let t = culture(a.title, b.title)
            if t != .orderedSame { return t == .orderedAscending }
            return x.offset < y.offset
        }.map(\.element)

        var groups: [QuickWorkGroup] = []
        if grouped {
            for r in sorted {
                if let last = groups.last, last.key == r.bucketKey { groups[groups.count - 1].rows.append(r) }
                else { groups.append(QuickWorkGroup(key: r.bucketKey, name: r.bucket, rows: [r])) }
            }
        }
        let doneCount = items.filter(isDone).count
        let line = doneCount > 0
            ? "\(items.count) item(s) \u{2014} \(items.count - doneCount) active, \(doneCount) completed/done."
            : "\(items.count) item(s)."
        return QuickWorkListing(rows: sorted, groups: groups, isGrouped: grouped, countLine: line, itemCount: items.count)
    }

    /// 08 QUICK-045 `Subtitle`: `Task|Procedure`, `✓ completed` when done, the deadline part (`due {yyyy-MM-dd}
    /// (OVERDUE {n}d)` — even when completed —, `due today`, `due {yyyy-MM-dd} (in {n}d)`), and `{n} subtask(s)` /
    /// `{n} step(s)` for direct children, joined by `"  ·  "`.
    public static func subtitle(_ i: HierarchyItem, today: CivilDate) -> String {
        var parts = [i is TaskItem ? "Task" : "Procedure"]
        if isDone(i) { parts.append("\u{2713} completed") }
        if let d = deadline(i) {
            let days = today.days(to: d.civilDate)
            parts.append(days < 0 ? "due \(d.format(.isoDate)) (OVERDUE \(-days)d)"
                         : days == 0 ? "due today" : "due \(d.format(.isoDate)) (in \(days)d)")
        }
        let children = (i as? TaskItem)?.subtasks.count ?? (i as? Procedure)?.steps.count ?? 0
        if children > 0 { parts.append("\(children) " + (i is TaskItem ? "subtask(s)" : "step(s)")) }
        return parts.joined(separator: "  \u{00B7}  ")
    }

    // MARK: Pinned board (QUICK-060…062)

    /// 08 QUICK-061 `RefreshPinned`: resolves every pin with `FindById` (top-level items); ids that are not a live
    /// TaskItem / Procedure are removed from `Ui.QuickViewPinIds` and the store is marked dirty. Tiles: active before
    /// done, then name (OrdinalIgnoreCase, stable). Pins ignore the list's filter and search.
    public static func pinnedTiles(store: AppStore, today: CivilDate) -> [QuickWorkTile] {
        let ui = store.data.ui
        var live: [HierarchyItem] = []
        var keep: [UUID] = []
        var pruned = false
        for id in ui.quickViewPinIds {
            if let it = store.item(id: id), it is TaskItem || it is Procedure {
                live.append(it)
                keep.append(id)
            } else {
                pruned = true
            }
        }
        if pruned {
            ui.quickViewPinIds = keep
            store.markDirty()
        }
        let ordered = live.enumerated().sorted { a, b in
            let da = isDone(a.element), db = isDone(b.element)
            if da != db { return !da }
            let c = NetText.compareIgnoreCase(a.element.name, b.element.name)
            return c == .orderedSame ? a.offset < b.offset : c == .orderedAscending
        }.map(\.element)
        return ordered.map { tile($0, today: today) }
    }

    /// 08 QUICK-062 tile model.
    public static func tile(_ i: HierarchyItem, today: CivilDate) -> QuickWorkTile {
        let done = isDone(i)
        let (pd, pt) = childProgress(i)
        let progressText: String
        if pt > 0 {
            let noun = i is TaskItem ? (pt == 1 ? "subtask" : "subtasks") : (pt == 1 ? "step" : "steps")
            progressText = "\(pd)/\(pt) \(noun) done"
        } else {
            progressText = done ? "completed" : "no items yet"
        }
        var chip: String?
        var overdue = false
        if let d = deadline(i) {
            let days = today.days(to: d.civilDate)
            overdue = days < 0 && !done
            let mmdd = String(d.format(.isoDate).dropFirst(5))
            chip = overdue ? "OVERDUE \(mmdd)" : "due \(mmdd)"
        }
        return QuickWorkTile(id: i.id, kind: i.kind, name: i.name, isDone: done, progressText: progressText,
                             progressDone: pd, progressTotal: pt, deadlineText: chip, deadlineIsOverdue: overdue)
    }

    /// Direct children only: task `(Subtasks.Count(IsComplete), Subtasks.Count)`, procedure `(Steps.Count(Done), …)`.
    public static func childProgress(_ i: HierarchyItem) -> (done: Int, total: Int) {
        if let t = i as? TaskItem { return (t.subtasks.filter(\.isComplete).count, t.subtasks.count) }
        if let p = i as? Procedure { return (p.steps.filter(\.done).count, p.steps.count) }
        return (0, 0)
    }

    // MARK: Accessors (tasks and procedures share these)

    public static func isDone(_ i: HierarchyItem) -> Bool {
        if let t = i as? TaskItem { return t.isComplete }
        if let p = i as? Procedure { return p.status == .done }
        return false
    }

    public static func deadline(_ i: HierarchyItem) -> NetDateTime? {
        if let t = i as? TaskItem { return t.deadline }
        if let p = i as? Procedure { return p.deadline }
        return nil
    }

    public static func status(_ i: HierarchyItem) -> WorkStatus {
        if let t = i as? TaskItem { return t.status }
        if let p = i as? Procedure { return p.status }
        return .todo
    }

    public static func recurrence(_ i: HierarchyItem) -> RecurrenceKind {
        if let t = i as? TaskItem { return t.recurrence }
        if let p = i as? Procedure { return p.recurrence }
        return .none
    }
}
