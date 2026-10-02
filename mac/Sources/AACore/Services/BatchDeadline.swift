// Spec: 02 REPO-052, §3.5 (BatchDeadline), REPO-053 (prefill), 04 §3.12, §7.4; DECISIONS Q-6 (a set deadline is a
//       calendar date, `.unspecified`; equality compares ticks, kind ignored).
import Foundation

@MainActor public enum BatchDeadline {
    /// Applies `date?.Date` (nil clears) to one item; true only on a real change. TaskItem: clearing clears BOTH
    /// Deadline and RangeStart (a range cannot exist without its end); otherwise `WorkRange.coerce(RangeStart, d,
    /// editedStart: false)` — a later start is clamped onto the new deadline, an earlier one kept. Procedure /
    /// ChecklistStep: set unless equal. Anything else → false.
    public static func setDeadline(_ item: AnyObject?, date: NetDateTime?) -> Bool {
        let d = date.map { $0.date.asCalendarDate }
        switch SvcSelection.unwrap(item) {
        case let t as TaskItem:
            guard let d else {
                if t.deadline == nil && t.rangeStart == nil { return false }
                t.deadline = nil
                t.rangeStart = nil
                return true
            }
            let (ns, nd) = WorkRange.coerce(start: t.rangeStart, deadline: d, editedStart: false)
            if t.deadline == nd && t.rangeStart == ns { return false }
            t.rangeStart = ns
            t.deadline = nd
            return true
        case let p as Procedure:
            if p.deadline == d { return false }
            p.deadline = d
            return true
        case let s as ChecklistStep:
            if s.deadline == d { return false }
            s.deadline = d
            return true
        default:
            return false
        }
    }

    /// Applies to every item; returns how many actually changed.
    public static func setDeadlineAll(_ items: [AnyObject], date: NetDateTime?) -> Int {
        items.reduce(0) { $0 + (setDeadline($1, date: date) ? 1 : 0) }
    }

    /// REPO-053 prefill: the distinct current deadlines of the selection (non-dated objects count as nil, equality
    /// by ticks). Exactly one distinct value → `.some(value)` (`.some(nil)` = every item has no deadline);
    /// mixed → nil. An empty selection → `.some(nil)`.
    public static func sharedDeadline(of items: [AnyObject]) -> NetDateTime?? {
        var first: NetDateTime??
        for i in items {
            let current = currentDeadline(i)
            if let f = first {
                if f != current { return nil }
            } else {
                first = .some(current)
            }
        }
        return first ?? .some(nil)
    }

    static func currentDeadline(_ item: AnyObject?) -> NetDateTime? {
        switch SvcSelection.unwrap(item) {
        case let t as TaskItem: return t.deadline
        case let p as Procedure: return p.deadline
        case let s as ChecklistStep: return s.deadline
        default: return nil
        }
    }
}
