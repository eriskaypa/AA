// Spec: 07 §3.4 VIEW-140…152, VIEW-155 (Buckets tab: grouped list, counts, status line, members, new / rename /
//       set category / delete, open and remove member), §4.4.1–4.4.4, 06 BUILD-145 B3 / B4 (blank category clears /
//       means none; Cancel on the category prompt still creates the bucket), 02 REPO-091 (log Kind "Bucket"),
//       DECISIONS 07 Q-11 (categories merged case-insensitively for display only).
import Foundation

/// A bucketable member row (07 §4.4.1).
@MainActor
public struct BucketMemberRow: @MainActor Identifiable {
    public enum Kind: String, Sendable { case task = "Task", subtask = "Subtask", procedure = "Procedure",
                                         step = "Checklist step" }
    public let id: String
    public let kind: Kind
    /// `NameOr(name)` — `"(unnamed)"` only for an empty name.
    public let name: String
    /// Raw parent name (immediate parent task, or the step's procedure); nil for top-level items.
    public let parent: String?
    public let item: any Bucketable
    public let itemID: UUID

    /// `"[{Kind}]  {Name}"` or `"[{Kind}]  {Name}   —   in {Parent}"`.
    public var text: String {
        let head = "[\(kind.rawValue)]  \(name)"
        guard let parent else { return head }
        return head + "   \u{2014}   in \(parent)"
    }
}

/// One list row (VIEW-142).
@MainActor
public struct BucketRow: @MainActor Identifiable {
    public let bucket: QuickBucket
    public let count: Int
    public var id: UUID { bucket.id }
    /// Display name — `"(unnamed)"` when empty.
    public var displayName: String { bucket.name.isEmpty ? "(unnamed)" : bucket.name }
    /// Always the plural word (`"1 items"`), as on Windows.
    public var countText: String { "\(count) items" }
}

/// One category group (VIEW-142; DECISIONS 07 Q-11 merges spellings that differ only by case).
@MainActor
public struct BucketGroup: @MainActor Identifiable {
    public let id: String
    public let label: String
    public let rows: [BucketRow]
    public var countText: String { " (\(rows.count))" }
}

@MainActor
public enum BucketsModel {
    public static let header = "\u{1FAA3} Buckets"
    public static let headerTitle = "Buckets"
    public static let help = MacKeyStrings.render("Predefine buckets here \u{2014} a location, a rank, a department, anything. Then sort tasks & procedures into up to two of them (in the Ctrl+N quick-work window).")
    public static let newBucketTitle = "+ New bucket"
    public static let renameTitle = "Rename"
    public static let setCategoryTitle = "Set category..."
    public static let setCategoryHelp = "Label what this bucket represents (Location, Rank, ...). Buckets are grouped by category."
    public static let deleteTitle = "Delete"
    public static let uncategorised = "(Uncategorised)"
    public static let emptyStatus = "No buckets yet. Click \u{201C}+ New bucket\u{201D} to define one (e.g. name \u{201C}Engine room\u{201D}, category \u{201C}Location\u{201D})."
    public static let noSelectionHeader = "Select a bucket to see the tasks & procedures in it."
    public static let membersHelp = "Double-click an item to open it. Right-click to remove it from this bucket."
    public static let selectFirstMessage = "Select a bucket first."
    public static let openTitle = "Open"
    public static let removeMemberTitle = "Remove from this bucket"
    // Prompts (06 Add.2.1 rows 23–26)
    public static let newPromptTitle = "New bucket"
    public static let newPromptLabel = "Bucket name (e.g. a location or a rank):"
    public static let categoryPromptTitle = "Category (optional)"
    public static let categoryPromptLabel = "What does it represent? (e.g. Location, Rank) \u{2014} leave blank for none:"
    public static let renamePromptTitle = "Rename bucket"
    public static let renamePromptLabel = "New name:"
    public static let setCategoryPromptTitle = "Set category"
    public static let setCategoryPromptLabel = "Category (e.g. Location, Rank) \u{2014} blank clears it:"
    public static let deleteAlertTitle = "Delete bucket"

    // MARK: Rows (§4.4.1)

    public static func nameOr(_ s: String) -> String { s.isEmpty ? "(unnamed)" : s }

    /// Tasks (each followed by its subtasks, recursively, parent = the immediate parent task's raw name), then
    /// procedures each followed by its steps (parent = the procedure's raw name). Crew items are not bucketable here.
    public static func memberRows(_ data: AppData) -> [BucketMemberRow] {
        var out: [BucketMemberRow] = []
        var seen = Set<ObjectIdentifier>()
        func taskRows(_ t: TaskItem, parent: String?) {
            guard seen.insert(ObjectIdentifier(t)).inserted else { return }
            out.append(BucketMemberRow(id: "t\(out.count)-" + t.id.netString, kind: parent == nil ? .task : .subtask,
                                       name: nameOr(t.name), parent: parent, item: t, itemID: t.id))
            for s in t.subtasks { taskRows(s, parent: t.name) }
        }
        for t in data.tasks { taskRows(t, parent: nil) }
        for p in data.procedures {
            out.append(BucketMemberRow(id: "p\(out.count)-" + p.id.netString, kind: .procedure, name: nameOr(p.name),
                                       parent: nil, item: p, itemID: p.id))
            for s in p.steps {
                out.append(BucketMemberRow(id: "s\(out.count)-" + s.id.netString, kind: .step, name: nameOr(s.title),
                                           parent: p.name, item: s, itemID: s.id))
            }
        }
        return out
    }

    /// VIEW-143: members whose `BucketIds` contains the bucket id.
    public static func members(of bucketID: UUID, in rows: [BucketMemberRow]) -> [BucketMemberRow] {
        let m = rows.filter { $0.item.bucketIds.contains(bucketID) }
        return CalendarRowBuilder.stableSorted(m) { a, b in
            let k = NetText.compareIgnoreCase(a.kind.rawValue, b.kind.rawValue)
            if k != .orderedSame { return k == .orderedAscending }
            return NetText.compareIgnoreCase(a.name, b.name) == .orderedAscending
        }
    }

    // MARK: Grouped list (§4.4.2)

    /// Sorted by category lower-cased (empty last), then display name (culture compare); grouped by the category
    /// merged case-insensitively (DECISIONS 07 Q-11 — display only; the stored strings are untouched). The group
    /// label is the first spelling in that order; an empty category is `"(Uncategorised)"`.
    public static func groups(_ data: AppData, rows memberRows: [BucketMemberRow]? = nil) -> [BucketGroup] {
        let members = memberRows ?? self.memberRows(data)
        var counts: [UUID: Int] = [:]
        for m in members { for id in Set(m.item.bucketIds) { counts[id, default: 0] += 1 } }
        let sorted = CalendarRowBuilder.stableSorted(data.quickBuckets) { a, b in
            if a.category.isEmpty != b.category.isEmpty { return !a.category.isEmpty }   // "(Uncategorised)" last
            let c = NetText.compareCulture(sortKey(a.category), sortKey(b.category))
            if c != .orderedSame { return c == .orderedAscending }
            return NetText.compareCulture(nameOr(a.name), nameOr(b.name)) == .orderedAscending
        }
        var order: [String] = []
        var labels: [String: String] = [:]
        var byKey: [String: [BucketRow]] = [:]
        for b in sorted {
            let key = b.category.isEmpty ? "\u{FFFF}" : NetText.toLowerInvariant(b.category)
            if byKey[key] == nil {
                order.append(key)
                labels[key] = b.category.isEmpty ? uncategorised : b.category
            }
            byKey[key, default: []].append(BucketRow(bucket: b, count: counts[b.id, default: 0]))
        }
        return order.map { BucketGroup(id: $0, label: labels[$0] ?? $0, rows: byKey[$0] ?? []) }
    }

    /// `CategorySort`: empty → U+FFFF (always last), else lower-cased invariant.
    static func sortKey(_ category: String) -> String {
        category.isEmpty ? "\u{FFFF}" : NetText.toLowerInvariant(category)
    }

    /// VIEW-144.
    public static func statusLine(bucketCount: Int) -> String {
        bucketCount == 0 ? emptyStatus : "\(bucketCount) bucket(s)."
    }

    /// VIEW-146 members header.
    public static func membersHeader(_ b: QuickBucket?, memberCount: Int) -> String {
        guard let b else { return noSelectionHeader }
        var s = "\u{1FAA3} " + nameOr(b.name)
        if !b.category.isEmpty { s += "  \u{00B7}  " + b.category }
        return s + "   \u{2014}   \(memberCount) item(s)"
    }

    /// VIEW-150 (raw name; trailing space kept when the bucket has no members).
    public static func deleteMessage(_ b: QuickBucket, memberCount: Int) -> String {
        "Delete bucket '\(b.name)'? "
            + (memberCount > 0 ? "Its \(memberCount) item(s) will be removed from it (the items themselves are kept)." : "")
    }

    // MARK: Mutations (VIEW-147…152). The caller saves (Windows `Save()`).

    /// VIEW-147: a blank / cancelled name aborts (nil); the category is trimmed, and a cancelled category prompt
    /// still creates the bucket with no category (B4). Logged `Added / Bucket / name / category`.
    @discardableResult
    public static func create(name: String?, category: String?, store: AppStore) -> QuickBucket? {
        guard let name, !NetText.isBlank(name) else { return nil }
        let b = QuickBucket(name: NetText.trim(name), category: NetText.trim(category ?? ""),
                            createdUtc: store.clock.utcNow())
        store.data.quickBuckets.append(b)
        store.logAdded(kind: "Bucket", name: name, detail: b.category)
        return b
    }

    /// VIEW-148: a non-blank value renames (trimmed); blank → no change.
    @discardableResult
    public static func rename(_ b: QuickBucket, to value: String) -> Bool {
        guard !NetText.isBlank(value) else { return false }
        b.name = NetText.trim(value)
        return true
    }

    /// VIEW-149 (B3): every OK sets the trimmed value (blank clears).
    public static func setCategory(_ b: QuickBucket, to value: String) {
        b.category = NetText.trim(value)
    }

    /// VIEW-150: removes the id from every member's `BucketIds`, removes the bucket and logs
    /// `Removed / Bucket / name / ""`.
    public static func delete(_ b: QuickBucket, store: AppStore) {
        for m in memberRows(store.data) where m.item.bucketIds.contains(b.id) {
            m.item.bucketIds.removeAll { $0 == b.id }
        }
        store.data.quickBuckets.removeAll { $0 === b }
        store.logRemoved(kind: "Bucket", name: b.name, detail: "")
    }

    /// VIEW-152: removes the bucket's id from that item's `BucketIds` (no confirmation).
    @discardableResult
    public static func removeMember(_ item: any Bucketable, from bucketID: UUID) -> Bool {
        guard item.bucketIds.contains(bucketID) else { return false }
        item.bucketIds.removeAll { $0 == bucketID }
        return true
    }
}
