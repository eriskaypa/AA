// Spec: 07 §3.3 VIEW-080…099, VIEW-108 (Planner constants, labels, navigation, hour grid, overlap layout, month
//       grid, durations), §4.3.1–4.3.6 (constants, helpers, LayoutDayBlocks, AddBlock, BuildMonth), §4.3.7 (snap with
//       banker's rounding), DECISIONS 07 Q-09 (locale weekday / month names), W-18 (clip at 24:00).
// Pure value math (nonisolated): no model access.
import Foundation

/// Day / Week / Month (VIEW-080). Not persisted: every Init starts in Day, anchored on today.
public enum PlannerMode: String, CaseIterable, Sendable, Hashable {
    case day = "Day", week = "Week", month = "Month"
}

/// One block placed in a day column (VIEW-095/096).
public struct PlannerBlockSlot: Sendable, Hashable {
    public var index: Int          // index into the input array
    public var column: Int
    public var columns: Int
    public var top: Double
    public var height: Double
    public var left: Double
    public var width: Double
    public var showsSubtitle: Bool

    public init(index: Int, column: Int, columns: Int, top: Double, height: Double, left: Double, width: Double,
                showsSubtitle: Bool) {
        self.index = index; self.column = column; self.columns = columns; self.top = top; self.height = height
        self.left = left; self.width = width; self.showsSubtitle = showsSubtitle
    }
}

/// A timed block's interval on its start day, in minutes from that day's midnight (`end` may pass 1440).
public struct PlannerInterval: Sendable, Hashable {
    public var start: Int
    public var end: Int
    public init(start: Int, end: Int) { self.start = start; self.end = end }
}

public enum PlannerGeometry {
    // 07 §4.3.1 constants
    public static let hourHeight = 46.0
    public static let gutterWidth = 52.0
    public static let dayStartHour = 0
    public static let dayEndHour = 24
    public static let snapMinutes = 15
    public static let dayWidthDay = 700.0
    public static let dayWidthWeek = 132.0
    public static let allDayMaxHeight = 108.0
    public static let initialScrollHour = 7
    public static let minBlockHeight = 20.0
    public static let minDuration = 15
    public static let subtitleThreshold = 34.0
    public static let minBlockWidth = 24.0
    /// 24 × 46.
    public static let gridHeight = Double(dayEndHour - dayStartHour) * hourHeight
    public static let monthHeaderEnglish = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    public static func dayWidth(_ mode: PlannerMode) -> Double { mode == .week ? dayWidthWeek : dayWidthDay }

    // MARK: Durations (VIEW-108)

    /// `< 60` → `"{m}m"` (0 and negatives included), else `"{h}h"` / `"{h}h {m}m"`.
    public static func durFmt(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Layout always uses `max(15, Duration)` minutes.
    public static func layoutMinutes(_ duration: Int) -> Int { max(minDuration, duration) }

    // MARK: Hour grid (VIEW-087, 092, 095, 100)

    /// §4.3.7: `round_half_even(y / 46 × 60 / 15) × 15`, clamped to [0, 1425].
    public static func snappedMinutes(y: Double) -> Int {
        let slots = (y / hourHeight * 60.0 / Double(snapMinutes)).rounded(.toNearestOrEven)
        let mins = Int(slots) * snapMinutes
        return max(0, min(24 * 60 - snapMinutes, mins))
    }

    /// The y of a minute offset from midnight.
    public static func y(minutes: Int) -> Double { Double(minutes) / 60.0 * hourHeight }

    /// `max(20, max(15, dur) / 60 × 46)`.
    public static func blockHeight(duration: Int) -> Double {
        max(minBlockHeight, Double(layoutMinutes(duration)) / 60.0 * hourHeight)
    }

    /// The second line shows only when the block is at least 34 tall.
    public static func showsSubtitle(height: Double) -> Bool { height >= subtitleThreshold }

    /// Gutter labels "00:00" … "24:00" (25 labels).
    public static let hourLabels: [String] = (0...24).map { String(format: "%02d:00", $0) }

    /// `top = h × 46 − 7` for gutter label `h`.
    public static func hourLabelTop(_ h: Int) -> Double { Double(h) * hourHeight - 7 }

    /// §4.3.4 LayoutDayBlocks: `intervals` must already be in stable start order. Clusters are transitively
    /// overlapping runs (strict `<`, so touching blocks do not cluster); inside a cluster each block takes the
    /// first column whose last end is `<=` its start (greedy first-fit). Geometry per §4.3.5; a block is clipped
    /// at 24:00 (W-18) — its height never runs past the bottom of the day.
    public static func layoutDay(_ intervals: [PlannerInterval], dayWidth: Double) -> [PlannerBlockSlot] {
        var out: [PlannerBlockSlot] = []
        var i = 0
        while i < intervals.count {
            var cluster = [i]
            var clusterEnd = intervals[i].end
            var j = i + 1
            while j < intervals.count && intervals[j].start < clusterEnd {
                cluster.append(j)
                clusterEnd = max(clusterEnd, intervals[j].end)
                j += 1
            }
            var colEnds: [Int] = []
            var col: [Int: Int] = [:]
            for k in cluster {
                let it = intervals[k]
                if let c = colEnds.firstIndex(where: { $0 <= it.start }) {
                    colEnds[c] = it.end
                    col[k] = c
                } else {
                    colEnds.append(it.end)
                    col[k] = colEnds.count - 1
                }
            }
            let cols = max(1, colEnds.count)
            let w = (dayWidth - 2) / Double(cols)
            for k in cluster {
                let it = intervals[k]
                let c = col[k] ?? 0
                let top = y(minutes: it.start)
                let full = max(minBlockHeight, Double(it.end - it.start) / 60.0 * hourHeight)
                let height = min(full, max(minBlockHeight, gridHeight - top))
                out.append(PlannerBlockSlot(index: k, column: c, columns: cols, top: top, height: height,
                                            left: Double(c) * w + 1, width: max(minBlockWidth, w - 3),
                                            showsSubtitle: showsSubtitle(height: full)))
            }
            i = j
        }
        return out.sorted { $0.index < $1.index }
    }

    // MARK: Days, labels and navigation (VIEW-081, 082, 087, 088, 097)

    /// Week view: Sunday → Saturday of the anchor's week; Day view: the anchor.
    public static func days(mode: PlannerMode, anchor: CivilDate) -> [CivilDate] {
        switch mode {
        case .day: return [anchor]
        case .week:
            let s = anchor.addingDays(-anchor.weekday)
            return (0..<7).map { s.addingDays($0) }
        case .month: return monthCells(anchor: anchor)
        }
    }

    /// The 42 cells (6 weeks) starting on the Sunday on or before the 1st of the anchor's month.
    public static func monthCells(anchor: CivilDate) -> [CivilDate] {
        let first = CivilDate(year: anchor.year, month: anchor.month, day: 1)!
        let start = first.addingDays(-first.weekday)
        return (0..<42).map { start.addingDays($0) }
    }

    /// ◀ / ▶: 1 day, 7 days, or 1 calendar month (end-of-month clamp).
    public static func step(_ anchor: CivilDate, mode: PlannerMode, forward: Bool) -> CivilDate {
        let n = forward ? 1 : -1
        switch mode {
        case .day: return anchor.addingDays(n)
        case .week: return anchor.addingDays(7 * n)
        case .month: return anchor.addingMonths(n)
        }
    }

    /// VIEW-082: Day `"{dddd}, yyyy-MM-dd"`, Week `"Week of {sunday}"`, Month `"{MMMM yyyy}"`.
    public static func rangeLabel(mode: PlannerMode, anchor: CivilDate, locale: Locale = .current) -> String {
        switch mode {
        case .day: return CalDateText.format(anchor, "EEEE", locale: locale) + ", " + anchor.iso
        case .week: return "Week of " + anchor.addingDays(-anchor.weekday).iso
        case .month: return CalDateText.format(anchor, "MMMM yyyy", locale: locale)
        }
    }

    /// VIEW-088: Day `"{dddd}, {MMM d}"`; Week `"{ddd}\n{MMM d}"`.
    public static func dayHeader(mode: PlannerMode, day: CivilDate, locale: Locale = .current) -> String {
        if mode == .week {
            return CalDateText.format(day, "EEE", locale: locale) + "\n" + CalDateText.format(day, "MMM d", locale: locale)
        }
        return CalDateText.format(day, "EEEE", locale: locale) + ", " + CalDateText.format(day, "MMM d", locale: locale)
    }

    /// Month header, Sunday first (DECISIONS 07 Q-09: the user's locale).
    public static func monthHeader(locale: Locale = .current) -> [String] {
        let s = CalDateText.shortWeekdaySymbols(locale: locale)
        return s.count == 7 ? s : monthHeaderEnglish
    }

    /// The scroll offset of the initial 07:00 position.
    public static var initialScrollY: Double { Double(initialScrollHour) * hourHeight }
}
