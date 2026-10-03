// Spec: 08 QUICK-196, 01 DATA-101, §3.16, §7.9; 08 T-DF-10 (tick-exact comparison).
import Foundation

public enum AgeVerdict {
    /// `"Incoming saved: {inc}\nCurrent saved:  {cur}\n{verdict}"` — each date `yyyy-MM-dd HH:mm:ss` (the stored
    /// wall clock) or `"(no save date)"`; note the two spaces after `Current saved:`.
    public static func text(incoming: NetDateTime?, current: NetDateTime?) -> String {
        let verdict: String
        switch (incoming, current) {
        case let (i?, c?):
            if i.ticks > c.ticks { verdict = "\u{279C} The incoming data is NEWER than your current data." }
            else if i.ticks < c.ticks { verdict = "\u{279C} The incoming data is OLDER than your current data." }
            else { verdict = "\u{279C} The incoming data is the SAME age as your current data." }
        case (_?, nil):
            verdict = "\u{279C} Your current data has no save date; relative age is unknown."
        case (nil, _?):
            verdict = "\u{279C} The incoming data has no save date (older format); it may be older."
        case (nil, nil):
            verdict = "\u{279C} Neither copy has a save date; relative age is unknown."
        }
        return "Incoming saved: \(stamp(incoming))\nCurrent saved:  \(stamp(current))\n\(verdict)"
    }

    static func stamp(_ d: NetDateTime?) -> String { d?.format(.isoSecond) ?? "(no save date)" }
}
