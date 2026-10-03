// Spec: 07 VIEW-001 / VIEW-003 (mini-month picker), VIEW-011 (Calendar column widths), VIEW-087 / 089 / 090 / 094
//       (Planner Week columns, all-day strip, chip), §7.1 Mac header count line; DECISIONS "Stage V rulings" (date
//       pickers show ISO dates), AA Mac design rules 1, 5, 13, 14 (round 2). Stage V round 2 fixes FIX2-W-PLAN.
// Pure value math for the Calendar / Planner views (no SwiftUI), so the layout decisions are unit-tested.
import Foundation

// MARK: Calendar header count line (Mac addition)

public extension CalSchedule {
    /// Distinct underlying items in the view. Agenda fans a ranged task out to one row per covered day (VIEW-010), so
    /// the row count would count it once per day; the header counts each item once in every mode.
    var distinctItemCount: Int { Set(rows.map(\.itemID)).count }

    /// The muted line under the title: `"{n} item(s)"`, plus `"  ·  {k} overdue"` when the Overdue group exists.
    var summaryLine: String {
        let n = distinctItemCount
        var text = n == 1 ? "1 item" : "\(n) items"
        if let late = groups.first(where: { $0.role == .overdue }) { text += "  \u{00B7}  \(late.rows.count) overdue" }
        return text
    }
}

// MARK: Calendar table columns (VIEW-011)

/// Column widths of the Calendar table for a list text size. Done / When / Status / Recurrence hug their content (their
/// maximum is the widest value they can show, so they never take spare width); the Task column has no maximum and
/// receives every extra point when the pane grows. Every minimum scales with the text size, so a large size never
/// breaks words in the Task column — the table scrolls horizontally instead. Windows widths 56 / 210 / 120 / 420 / 110.
public struct CalColumnWidths: Sendable, Equatable {
    public struct Width: Sendable, Equatable {
        public let min: Double
        public let ideal: Double
        public let max: Double?
    }

    public let done: Width
    public let when: Width
    public let status: Width
    public let task: Width
    public let recurrence: Width

    /// Advance of one character of the brand mono face (`aaMono`) at `size`.
    public static func charWidth(_ size: Double) -> Double { size * 0.6 }
    /// Cell insets (NSTableView intercell spacing plus the cell's own padding).
    public static let cellPadding = 16.0
    /// The Task cell's kind stripe (4) and its spacing (8).
    public static let stripe = 12.0
    /// Longest word the Task column shows without breaking it, in characters ("Turbocharger", "preparation").
    public static let taskWordChars = 14.0
    /// "yyyy-MM-dd →" — a range wraps after the arrow; a single date fits on one line.
    public static let whenLineChars = 12.0
    /// "In Progress".
    public static var statusChars: Double {
        Double(WorkStatus.allStatuses.map(\.friendlyLabel.count).max() ?? 11)
    }
    /// "Monthly" (and "None").
    public static var recurrenceChars: Double {
        Double(RecurrenceKind.allKinds.map(\.friendlyLabel.count).max() ?? 7)
    }
    /// A header title's width in the 13-pt system header font (≈ 7.2 pt per character) plus the cell insets: no
    /// column's minimum or ideal is narrower than its header (design rule 5), so "Done" and "Recurrence" are never
    /// truncated, even when a large text size makes the table scroll.
    public static func headerWidth(_ title: String) -> Double { (Double(title.count) * 7.2 + cellPadding).rounded(.up) }

    /// The Task column's ideal at the default size: the five ideals then fit the pane of an 1100-pt window.
    public static let taskIdealAtDefault = 164.0

    public static func forSize(_ size: Double) -> CalColumnWidths {
        let c = charWidth(size)
        let p = cellPadding
        let whenW = Swift.max(headerWidth("When"), (whenLineChars * c + p).rounded(.up))
        let statusW = Swift.max(headerWidth("Status"), (statusChars * c + p).rounded(.up))
        let recurrenceW = Swift.max(headerWidth("Recurrence"), (recurrenceChars * c + p).rounded(.up))
        let taskMin = (taskWordChars * c + stripe + p).rounded(.up)
        return CalColumnWidths(
            done: Width(min: headerWidth("Done"), ideal: headerWidth("Done"), max: 70),
            when: Width(min: Swift.max(headerWidth("When"), (10 * c + p).rounded(.up)), ideal: whenW, max: whenW),
            status: Width(min: Swift.max(headerWidth("Status"), (7 * c + p).rounded(.up)), ideal: statusW, max: statusW),
            task: Width(min: taskMin, ideal: Swift.max(taskIdealAtDefault, taskMin), max: nil),
            recurrence: Width(min: Swift.max(headerWidth("Recurrence"), (4 * c + p).rounded(.up)), ideal: recurrenceW,
                              max: recurrenceW))
    }

    public var idealSum: Double { done.ideal + when.ideal + status.ideal + task.ideal + recurrence.ideal }
    public var minSum: Double { done.min + when.min + status.min + task.min + recurrence.min }
}

// MARK: Date pickers (DECISIONS Stage V ruling, design rule 14)

public extension CalDateText {
    /// The locale every date picker carries (`.environment(\.locale, …)` on the picker only): its short date is
    /// `yyyy-MM-dd` and its weeks start on Sunday like the Calendar and Planner week math.
    static let pickerLocale = Locale(identifier: "en_CA")
}

// MARK: Planner Week horizontal scroll (VIEW-087 / VIEW-094)

public extension PlannerGeometry {
    /// The narrowest a Week column may shrink to so the whole week fits the pane (Windows: a fixed 132).
    static let dayWidthWeekMin = 96.0

    /// The day column width for a pane `available` points wide: the columns fill the pane (never narrower than 700 in
    /// Day view; in Week view they shrink to fit the 7 days down to `dayWidthWeekMin`, so a default window shows the
    /// whole week with its hour gutter). Block geometry always uses this actual width.
    static func fittedDayWidth(mode: PlannerMode, available: Double, count: Int) -> Double {
        let floor = mode == .week ? dayWidthWeekMin : dayWidth(mode)
        let fill = ((available - gutterWidth - 1) / Double(Swift.max(1, count))).rounded(.down)
        return Swift.max(floor, fill)
    }

    /// The horizontal offset the Day / Week grid scrolls to after every rebuild. A week still wider than the pane (Week
    /// columns at their 96-pt minimum in a narrow pane): when today's column would sit (partly) past the right edge,
    /// the grid scrolls so today is centred (clamped to the content); otherwise it stays at the leading edge (the hour
    /// gutter and Sunday visible). Day view and weeks without today always start at 0.
    static func initialScrollX(mode: PlannerMode, days: [CivilDate], today: CivilDate, dayWidth: Double,
                               viewport: Double) -> Double {
        guard mode == .week, viewport > 0, let i = days.firstIndex(of: today) else { return 0 }
        let total = gutterWidth + dayWidth * Double(days.count)
        let maxX = Swift.max(0, total - viewport)
        let start = gutterWidth + dayWidth * Double(i)
        if start + dayWidth <= viewport { return 0 }
        let centred = start + dayWidth / 2 - viewport / 2
        return Swift.min(maxX, Swift.max(0, centred)).rounded()
    }

    // MARK: All-day strip (VIEW-089 / VIEW-090)

    /// Height of the "+N more" / "Show less" row under a day's chip stack.
    static let allDayMoreRowHeight = 18.0
    /// The strip's cap while expanded with "+N more" (three times the Windows cap of 108).
    static let allDayExpandedMaxHeight = 324.0

    /// A wrapped chip's estimated height: 11-pt brand mono (≈ 6.6 pt per character), 2 pt padding top and bottom,
    /// 3 pt gap. Only sizes the strip; hidden chips are counted from their measured frames.
    static func allDayChipHeight(_ text: String, width: Double) -> Double {
        let perLine = Swift.max(1, Int((width - 6 - 12) / 6.6))
        let lines = Swift.max(1, Int((Double(text.count) / Double(perLine)).rounded(.up)))
        return Double(lines) * 14 + 4 + 3
    }

    /// The strip height for the given per-day chip texts: the tallest stack (6 pt margins), at least 28, at most the
    /// cap (108, or `allDayExpandedMaxHeight` when expanded).
    static func allDayStripHeight(_ perDay: [[String]], dayWidth: Double, expanded: Bool) -> Double {
        let tallest = perDay.map { $0.reduce(6.0) { $0 + allDayChipHeight($1, width: dayWidth) } }.max() ?? 0
        let cap = expanded ? allDayExpandedMaxHeight : allDayMaxHeight
        return Swift.min(cap, Swift.max(28, tallest))
    }

    /// How many chips of a day's stack are not fully visible: frames are (minY, maxY) in the scroll view's visible
    /// coordinate space, `visibleHeight` its height. A chip cut at either edge counts as hidden.
    static func hiddenChipCount(_ frames: [(minY: Double, maxY: Double)], visibleHeight: Double) -> Int {
        frames.filter { $0.minY < -0.5 || $0.maxY > visibleHeight + 0.5 }.count
    }

    /// The text of the row under a day's stack (clicking it toggles the expansion): collapsed — `"+N more"` when
    /// chips are hidden, else no row; expanded — `"Show less"`, prefixed with `"+N more · "` when chips are still
    /// hidden (the stack scrolls).
    static func allDayMoreLabel(hidden: Int, expanded: Bool) -> String? {
        if expanded { return hidden > 0 ? "+\(hidden) more \u{00B7} Show less" : "Show less" }
        return hidden > 0 ? "+\(hidden) more" : nil
    }

    /// VIEW-090 chip label colour (design rule 13): white on a full-opacity chip (the Windows colours); on a ghost
    /// chip (opacity < 1, the non-deadline days of a span) the fill alone fades and the label uses the foreground
    /// colour, because white on the faded fill falls under 3:1.
    static func chipLabelIsWhite(opacity: Double) -> Bool { opacity >= 1 }
}
