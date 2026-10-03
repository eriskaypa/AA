// Spec: 02 REPO-042 (BatchDone.SetDone / SetDoneAll), REPO-040 (Status ⇄ IsComplete), 04 §3.11, §7.5; 08 §3.8.
import Foundation

/// The one shared definition of "mark done / not done" across a heterogeneous selection. Reports only real
/// changes, so a no-op selection never triggers a save (callers: `markDirty(); flushIfDirty()` when n > 0).
@MainActor public enum BatchDone {
    /// TaskItem: no-op when `isComplete == done` (InProgress/Blocked untouched), else sets `isComplete` (Status
    /// follows). ChecklistStep: no-op when equal, else sets `done`. Procedure: done → `Status = Done` unless already
    /// Done; not done → only a Done procedure becomes Todo. Anything else (nil, Equipment, Vessel, rows…) → false.
    public static func setDone(_ item: AnyObject?, done: Bool) -> Bool {
        switch SvcSelection.unwrap(item) {
        case let t as TaskItem:
            guard t.isComplete != done else { return false }
            t.isComplete = done
            return true
        case let s as ChecklistStep:
            guard s.done != done else { return false }
            s.done = done
            return true
        case let p as Procedure:
            if done {
                guard p.status != .done else { return false }
                p.status = .done
            } else {
                guard p.status == .done else { return false }
                p.status = .todo
            }
            return true
        default:
            return false
        }
    }

    /// Applies to each item; returns how many actually changed.
    public static func setDoneAll(_ items: [AnyObject], done: Bool) -> Int {
        items.reduce(0) { $0 + (setDone($1, done: done) ? 1 : 0) }
    }
}

/// Row wrappers in selections (02 §5.3 "a protocol ModelRow { var model }"): a list row that is not itself a model
/// exposes the model it shows, so batch services accept either.
@MainActor public protocol SvcModelRow: AnyObject {
    var svcRowModel: AnyObject? { get }
}

@MainActor enum SvcSelection {
    /// `BatchDelete.Unwrap`: a model passes through; a `SvcModelRow` yields its model; any other object exposing a
    /// stored property named `item` (or the `@Observable` backing `_item`) holding a model yields it, else the object itself.
    static func unwrap(_ o: AnyObject?) -> AnyObject? {
        guard let o else { return nil }
        if o is HierarchyItem || o is ChecklistStep { return o }
        if let row = o as? SvcModelRow { return row.svcRowModel ?? o }
        for child in Mirror(reflecting: o).children where child.label == "item" || child.label == "_item" {
            if let h = child.value as? HierarchyItem { return h }
            if let s = child.value as? ChecklistStep { return s }
            if let c = child.value as? CrewMember { return c }
        }
        return o
    }
}
