// Spec: 02 REPO-050, §3.4 (WorkRange.Coerce), 04 §3.3, 06 §7.1; DECISIONS Q-6 / ARCHITECTURE.md §3.4 (a date the
//       coercion changes comes out `.asCalendarDate`; a kept date keeps its value AND its originalText).
import Foundation

public enum WorkRange {
    /// Normalises both dates to their day (time dropped) and enforces `start <= deadline`, the deadline being the
    /// LAST day of the range: no start → `(nil, deadline day)`; a start without a deadline → a one-day range;
    /// a start after the deadline → the deadline follows an edited start (`editedStart`), else the start is pulled
    /// back onto the deadline. Never shows a dialog.
    public static func coerce(start: NetDateTime?, deadline: NetDateTime?, editedStart: Bool)
        -> (start: NetDateTime?, deadline: NetDateTime?) {
        var s = start.map(svcDay)
        var d = deadline.map(svcDay)
        if let sv = s {
            if let dv = d {
                if sv.ticks > dv.ticks {
                    if editedStart { d = sv.asCalendarDate } else { s = dv.asCalendarDate }
                }
            } else {
                d = sv.asCalendarDate
            }
        }
        return (s, d)
    }

    /// `.Date`: unchanged when already midnight (value and originalText kept), else midnight as a calendar date.
    static func svcDay(_ d: NetDateTime) -> NetDateTime {
        d.timeOfDayTicks == 0 ? d : d.date.asCalendarDate
    }
}
