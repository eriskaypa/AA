// Regression tests for the Stage V round-2 fixes FIX2-W-PLAN (CalendarLayout.swift): Agenda header count (V2-J2),
// Calendar column widths (V2-J2, rule 5), ISO picker locale (V2-DESIGN, DECISIONS Stage V ruling), Planner Week fit and
// today scroll (V2-J2, VIEW-087 / 094), hidden due-strip chips (V2-J2, VIEW-089), ghost-chip label contrast (V2-DESIGN,
// rule 13).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct CalendarLayoutTests {
    typealias D = CalTestData

    // MARK: Agenda summary counts items, not fan-out rows

    @Test func agendaSummaryCountsDistinctItems() {
        // V2-J2: a ranged task fans out to one Agenda row per covered day; the header counted rows ("73 items" vs
        // "53 items" in All Upcoming for the same data).
        let data = D.data(tasks: [D.task("R", start: "2026-09-29", deadline: "2026-10-03"),
                                  D.task("P", deadline: "2026-10-01"),
                                  D.task("late", deadline: "2026-09-20")])
        let agenda = CalendarRowBuilder.build(data: data, mode: .agenda, selected: D.today, today: D.today, locale: D.enUS)
        let all = CalendarRowBuilder.build(data: data, mode: .all, selected: D.today, today: D.today, locale: D.enUS)
        #expect(agenda.rows.count == 7)                 // 5 days of R + P + the overdue row
        #expect(agenda.distinctItemCount == 3)
        #expect(agenda.summaryLine == "3 items  \u{00B7}  1 overdue")
        #expect(all.summaryLine == agenda.summaryLine)
        let one = CalendarRowBuilder.build(data: D.data(tasks: [D.task("R", start: "2026-09-29", deadline: "2026-10-01")]),
                                           mode: .agenda, selected: D.today, today: D.today, locale: D.enUS)
        #expect(one.rows.count == 3 && one.summaryLine == "1 item")
    }

    // MARK: Calendar columns give the spare width to Task and scale with the text size

    @Test func calendarColumnsFavourTheTaskColumn() throws {
        // V2-J2: When took ~240 pt while Task wrapped at ~200 pt. When / Status / Recurrence now hug their content
        // (max = ideal) and only Task can take spare width.
        let w = CalColumnWidths.forSize(CalFontScale.defaultSize)
        #expect(w.task.max == nil)
        for col in [w.when, w.status, w.recurrence, w.done] {
            let max = try #require(col.max)
            #expect(max <= col.ideal + 30 && col.min <= col.ideal)
        }
        #expect(w.when.max == w.when.ideal && w.status.max == w.status.ideal && w.recurrence.max == w.recurrence.ideal)
        #expect(w.task.ideal >= w.when.ideal && w.task.ideal >= w.status.ideal)
        // "yyyy-MM-dd →" fits one line of When; "In Progress" fits Status (aaMono advance 0.6 em).
        let c = CalColumnWidths.charWidth(CalFontScale.defaultSize)
        #expect(w.when.ideal >= 12 * c + 12 && w.status.ideal >= 11 * c + 12)
        // All five ideals still fit the pane an 1100-pt window leaves (≈ 560 pt): no horizontal scroll at default.
        #expect(w.idealSum <= 560)
    }

    @Test func calendarColumnIdealsAreAtLeastTheirHeaders() {
        // Rule 5: "Recurrence" was truncated to "Recurren…" once its maximum hugged the longest value ("Monthly").
        // At A+ 28 the table shrank Done and Recurrence to their minimums ("Do…", "Recurren…").
        for size in [CalFontScale.minimum, CalFontScale.defaultSize, CalFontScale.maximum] {
            let w = CalColumnWidths.forSize(size)
            for (col, title) in [(w.done, "Done"), (w.when, "When"), (w.status, "Status"), (w.task, "Task"),
                                 (w.recurrence, "Recurrence")] {
                #expect(col.min >= CalColumnWidths.headerWidth(title) && col.ideal >= col.min)
            }
        }
    }

    @Test func calendarMinimumsScaleWithTheTextSize() {
        // V2-J2: at A+ 28, Task broke words ("Turbocharg/er", "preparatio/n") because its width ignored the font.
        let small = CalColumnWidths.forSize(CalFontScale.minimum)
        let big = CalColumnWidths.forSize(CalFontScale.maximum)
        let c = CalColumnWidths.charWidth(CalFontScale.maximum)
        for word in ["Turbocharger", "preparation", "calibration"] {
            #expect(big.task.min >= Double(word.count) * c + CalColumnWidths.stripe)
        }
        #expect(big.task.min > small.task.min && big.when.min > small.when.min)
        // Status grows with the text; Recurrence ("Monthly") stays held by its header width up to 28.
        #expect(big.status.min > small.status.min && big.recurrence.min >= small.recurrence.min)
        #expect(big.recurrence.ideal >= CalColumnWidths.recurrenceChars * c)
        #expect(big.task.ideal >= big.task.min)
    }

    // MARK: Date pickers

    @Test func pickerLocaleShowsISODates() {
        // V2-DESIGN / DECISIONS Stage V ruling: the Calendar mini-month carries the en_CA locale → yyyy-MM-dd.
        let f = DateFormatter()
        f.locale = CalDateText.pickerLocale
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateStyle = .short
        f.timeStyle = .none
        let date = Date(timeIntervalSince1970: TimeInterval(D.day("2026-10-04").daysFromCivil) * 86_400 + 43_200)
        #expect(f.string(from: date) == "2026-10-04")
        var cal = Calendar(identifier: .gregorian)
        cal.locale = CalDateText.pickerLocale
        #expect(cal.firstWeekday == 1)                   // Sunday, like the Calendar / Planner week math
    }

    // MARK: Planner Week fits the default window, and today is scrolled into view otherwise

    @Test func weekColumnsShrinkToFitTheDefaultPane() {
        // V2-J2: at the default 1280 × 820 window the grid is ≈ 790 pt; 132-pt columns cut Friday and hid Saturday.
        let week = PlannerGeometry.days(mode: .week, anchor: D.day("2026-10-03"))
        let w = PlannerGeometry.fittedDayWidth(mode: .week, available: 790, count: week.count)
        #expect(w < PlannerGeometry.dayWidthWeek && w >= PlannerGeometry.dayWidthWeekMin)
        #expect(PlannerGeometry.gutterWidth + w * 7 <= 790)
        // Wider panes still fill; a narrow pane stops at the 96-pt minimum; Day view never goes below 700.
        #expect(PlannerGeometry.fittedDayWidth(mode: .week, available: 1453, count: 7) == 200)
        #expect(PlannerGeometry.fittedDayWidth(mode: .week, available: 500, count: 7) == PlannerGeometry.dayWidthWeekMin)
        #expect(PlannerGeometry.fittedDayWidth(mode: .day, available: 500, count: 1) == 700)
        #expect(PlannerGeometry.fittedDayWidth(mode: .day, available: 1200, count: 1) == 1147)
        // The grid scrolls nowhere when everything fits.
        #expect(PlannerGeometry.initialScrollX(mode: .week, days: week, today: D.day("2026-10-03"), dayWidth: w,
                                               viewport: 790) == 0)
    }

    @Test func narrowWeekScrollsTodayIntoView() {
        // V2-J2: in a pane narrower than the week, today's column (Saturday) must be visible after a rebuild.
        let week = PlannerGeometry.days(mode: .week, anchor: D.day("2026-10-03"))
        let w = PlannerGeometry.dayWidthWeekMin
        let viewport = 500.0
        let x = PlannerGeometry.initialScrollX(mode: .week, days: week, today: D.day("2026-10-03"), dayWidth: w,
                                               viewport: viewport)
        let start = PlannerGeometry.gutterWidth + w * 6
        #expect(start >= x && start + w <= x + viewport)                     // Saturday fully visible
        #expect(x <= PlannerGeometry.gutterWidth + w * 7 - viewport)         // clamped to the content
        // Today early in the week: stays at the leading edge (gutter and Sunday visible).
        #expect(PlannerGeometry.initialScrollX(mode: .week, days: week, today: D.day("2026-09-28"), dayWidth: w,
                                               viewport: viewport) == 0)
        // A week without today, and Day view, start at 0.
        #expect(PlannerGeometry.initialScrollX(mode: .week, days: week, today: D.day("2026-10-20"), dayWidth: w,
                                               viewport: viewport) == 0)
        #expect(PlannerGeometry.initialScrollX(mode: .day, days: [D.day("2026-10-03")], today: D.day("2026-10-03"),
                                               dayWidth: 700, viewport: viewport) == 0)
        // Mid-week today in a narrow pane is centred.
        let wed = PlannerGeometry.initialScrollX(mode: .week, days: week, today: D.day("2026-09-30"), dayWidth: w,
                                                 viewport: 300)
        #expect(wed == (PlannerGeometry.gutterWidth + w * 3 + w / 2 - 150).rounded())
    }

    // MARK: All-day strip: hidden chips are announced

    @Test func dueStripCountsHiddenChips() {
        // V2-J2: Day view 2026-10-03 had 8 due chips; the 108-pt strip showed 5 with no cue for the other 3.
        let texts = (1...8).map { "\u{2022} Due item number \($0)" }
        let collapsed = PlannerGeometry.allDayStripHeight([texts], dayWidth: 700, expanded: false)
        #expect(collapsed == PlannerGeometry.allDayMaxHeight)
        let expanded = PlannerGeometry.allDayStripHeight([texts], dayWidth: 700, expanded: true)
        #expect(expanded > collapsed && expanded <= PlannerGeometry.allDayExpandedMaxHeight)
        // Measured frames: 8 chips of 19 pt with a 3-pt gap; 90 pt visible (108 minus the "+N more" row).
        let frames: [(minY: Double, maxY: Double)] = (0..<8).map { (i: Int) -> (minY: Double, maxY: Double) in
            let top: Double = 3 + Double(i) * 22
            return (minY: top, maxY: top + 19)
        }
        let hidden = PlannerGeometry.hiddenChipCount(frames, visibleHeight: 90)
        #expect(hidden == 4)                              // 4 fully visible, 4 below
        #expect(PlannerGeometry.allDayMoreLabel(hidden: hidden, expanded: false) == "+4 more")
        // Scrolled to the end: the first four are hidden above and the fifth is cut at the top edge.
        let scrolled: [(minY: Double, maxY: Double)] = frames.map { f in (minY: f.minY - 100, maxY: f.maxY - 100) }
        #expect(PlannerGeometry.hiddenChipCount(scrolled, visibleHeight: 90) == 5)
        // Everything visible: no row while collapsed; "Show less" while expanded.
        #expect(PlannerGeometry.hiddenChipCount(Array(frames.prefix(3)), visibleHeight: 90) == 0)
        #expect(PlannerGeometry.allDayMoreLabel(hidden: 0, expanded: false) == nil)
        #expect(PlannerGeometry.allDayMoreLabel(hidden: 0, expanded: true) == "Show less")
        #expect(PlannerGeometry.allDayMoreLabel(hidden: 2, expanded: true) == "+2 more \u{00B7} Show less")
        // A short stack keeps the 28-pt minimum.
        #expect(PlannerGeometry.allDayStripHeight([[]], dayWidth: 132, expanded: false) == 28)
    }

    // MARK: Ghost chips keep a readable label

    @Test func ghostChipLabelsAreNotWhiteOnTheFadedFill() throws {
        // V2-DESIGN rule 13: `.opacity(chip.opacity)` faded the white text with the chip (≈ 2:1 on the light strip).
        let t = D.task("name", start: "2026-10-03", deadline: "2026-10-05")
        let placed = PlannerPlacement.placed(D.data(tasks: [t]))
        let ghost = try #require(PlannerPlacement.allDayChips(placed, day: D.day("2026-10-04")).first)
        let deadline = try #require(PlannerPlacement.allDayChips(placed, day: D.day("2026-10-05")).first)
        let monthGhost = try #require(PlannerPlacement.monthChips(placed, day: D.day("2026-10-04")).first)
        #expect(!PlannerGeometry.chipLabelIsWhite(opacity: ghost.opacity))
        #expect(!PlannerGeometry.chipLabelIsWhite(opacity: monthGhost.opacity))
        #expect(PlannerGeometry.chipLabelIsWhite(opacity: deadline.opacity))
        // Why: #1E88E5 at 0.6 over the light strip (#FFFFFF) vs white text, and vs the light foreground (#000000).
        let faded = Self.blend(fg: (0x1E, 0x88, 0xE5), bg: (0xFF, 0xFF, 0xFF), alpha: ghost.opacity)
        #expect(Self.contrast(faded, (255, 255, 255)) < 3)
        #expect(Self.contrast(faded, (0, 0, 0)) >= 4.5)
        // Dark strip (#2D2D30) with the dark foreground (#F0F0F0).
        let fadedDark = Self.blend(fg: (0x1E, 0x88, 0xE5), bg: (0x2D, 0x2D, 0x30), alpha: ghost.opacity)
        #expect(Self.contrast(fadedDark, (0xF0, 0xF0, 0xF0)) >= 4.5)
    }

    private typealias RGB = (Double, Double, Double)

    private static func blend(fg: RGB, bg: RGB, alpha: Double) -> RGB {
        (fg.0 * alpha + bg.0 * (1 - alpha), fg.1 * alpha + bg.1 * (1 - alpha), fg.2 * alpha + bg.2 * (1 - alpha))
    }

    private static func luminance(_ c: RGB) -> Double {
        func lin(_ v: Double) -> Double {
            let s = v / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
    }

    private static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
