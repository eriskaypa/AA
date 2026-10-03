// Regression tests for the Stage V round-2 W-QUICK findings: V2-SCALE (due-dates build at 7k rows, dayText formatter,
// no animated diff over huge lists), V2-J2 (no dangling `·` in the due-panel subtitle), V2-J7 / V2-DESIGN (Activity
// log columns fit the 860-pt window; Kind holds `Equipment/Area` on one line), V2-DESIGN rule 17 (no empty Search
// status bar before the first search).
import AppKit
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct WindowsRound2FixTests {
    nonisolated static let today = CivilDate(year: 2026, month: 10, day: 3)!
    nonisolated static let en = Locale(identifier: "en_US")

    func day(_ d: CivilDate, _ h: Int = 0, _ m: Int = 0) -> NetDateTime {
        NetDateTime(year: d.year, month: d.month, day: d.day, hour: h, minute: m, kind: .unspecified)
    }

    /// A mixed graph: ranged / plain tasks with subtasks, procedures with steps, crew checklist steps and scheduled
    /// jobs spread over today … today+7 (plus overdue ones), so every collector path runs on every day.
    func mixedStore(scale: Int) -> AppStore {
        let store = StoreFactory.make().store
        var tasks: [TaskItem] = []
        var procs: [Procedure] = []
        var crew: [CrewMember] = []
        for i in 0..<scale {
            let off = (i % 12) - 3                       // −3 … +8 days
            let t = TaskItem(name: "Task \(i)")
            t.deadline = day(Self.today.addingDays(off))
            if i % 5 == 0 { t.rangeStart = day(Self.today.addingDays(off - 2)) }
            if i % 7 == 0 { t.status = .done }
            let sub = TaskItem(name: "Sub \(i)"); sub.deadline = day(Self.today.addingDays(off + 1))
            if i % 4 == 0 { sub.isJob = true; sub.scheduledStart = day(Self.today.addingDays(off), 9, 30) }
            t.subtasks = [sub]
            tasks.append(t)
            if i % 3 == 0 {
                let p = Procedure(name: "Proc \(i)"); p.deadline = day(Self.today.addingDays(off + 2))
                let s = ChecklistStep(title: "Step \(i)"); s.deadline = day(Self.today.addingDays(off))
                if i % 6 == 0 { s.isJob = true; s.scheduledStart = day(Self.today.addingDays(off + 1), 8, 0) }
                p.steps = [s]
                procs.append(p)
            }
            if i % 9 == 0 {
                let m = CrewMember(); m.firstName = "Crew"; m.lastName = "\(i)"
                let s = ChecklistStep(title: "Cert \(i)"); s.deadline = day(Self.today.addingDays(off))
                m.checklist = [s]
                crew.append(m)
            }
        }
        store.data.tasks = tasks
        store.data.procedures = procs
        store.data.crew = crew
        return store
    }

    // MARK: V2-SCALE — DueListBuilder

    @Test func collectingAllDaysInOneWalkEqualsCollectingEachDay() {
        // The single-pass collector must give every day exactly what a per-day `Collect(day)` gives: same rows, same
        // order (tasks → procedures → steps → crew → jobs), per-day Guid dedupe (a ranged task on several days).
        let store = mixedStore(scale: 120)
        let days = (0...7).map { Self.today.addingDays($0) }
        let together = DueListBuilder.collectDays(store: store, days: days)
        #expect(together.count == days.count)
        for (k, d) in days.enumerated() {
            let alone = DueListBuilder.collectDays(store: store, days: [d])[0]
            #expect(together[k].map(\.row) == alone.map(\.row), "day \(d.iso)")
            #expect(together[k].allSatisfy { $0.sortDay == d })
            #expect(!alone.isEmpty)
        }
        // A ranged task covering today and tomorrow is listed on both days (per-day dedupe, not global).
        let both = Set(together[0].map(\.modelID)).intersection(together[1].map(\.modelID))
        #expect(!both.isEmpty)
    }

    @Test func buildWithThousandsOfOverdueRowsIsFast() {
        // V2-SCALE: 7,299 rows (4,653 overdue) took 781 ms in release because every overdue row built its own
        // Calendar + DateFormatter and the graph was walked once per day. A debug build of this store (~6,000 rows,
        // ~3,000 overdue) must stay well under a second.
        let store = mixedStore(scale: 6_000)
        _ = DueListBuilder.build(store: store, today: Self.today, locale: Self.en)    // warm the formatter cache
        let clock = ContinuousClock()
        var list = DueList()
        let elapsed = clock.measure { list = DueListBuilder.build(store: store, today: Self.today, locale: Self.en) }
        #expect(list.overdueCount > 2_000)
        #expect(list.rowCount > 5_000)
        #expect(elapsed < .milliseconds(1_000), "build took \(elapsed)")
    }

    @Test func dayTextIsCachedAndUnchanged() {
        let d = CivilDate(year: 2026, month: 10, day: 2)!
        #expect(DueListBuilder.dayText(d, locale: Self.en) == "Fri, 02 Oct")
        #expect(DueListBuilder.dayText(d, locale: Self.en) == CalDateText.format(d, "EEE, dd MMM", locale: Self.en))
        let de = DueListBuilder.dayText(d, locale: Locale(identifier: "de_DE"))
        #expect(de.contains("02") && de != "Fri, 02 Oct")
        // 10,000 calls reuse one formatter (a fresh DateFormatter each took ~0.17 ms).
        let clock = ContinuousClock()
        let elapsed = clock.measure { for k in 0..<10_000 { _ = DueListBuilder.dayText(d.addingDays(-(k % 90)), locale: Self.en) } }
        #expect(elapsed < .milliseconds(500), "10k dayText took \(elapsed)")
    }

    @Test func hugeListsAreNotAnimated() {
        // The panel animates the tick-off fade only on everyday lists; a 7k-row diff is applied without animation.
        #expect(DueList.animatesChange(from: 0, to: 12))
        #expect(DueList.animatesChange(from: 12, to: 11))
        #expect(DueList.animatesChange(from: DueList.animationRowLimit, to: DueList.animationRowLimit))
        #expect(!DueList.animatesChange(from: 0, to: 7_299))
        #expect(!DueList.animatesChange(from: 7_299, to: 7_298))
        #expect(!DueList.animatesChange(from: DueList.animationRowLimit + 1, to: 3))
    }

    // MARK: V2-J2 — header subtitle parts

    @Test func headerPartsJoinToTheSubtitle() {
        let store = mixedStore(scale: 30)
        let l = DueListBuilder.build(store: store, today: Self.today, locale: Self.en)
        #expect(l.headerParts == ["\(l.overdueCount) overdue", "Today Sat, 03 Oct", "Tomorrow Sun, 04 Oct"])
        #expect(l.headerSubtitle == l.headerParts.joined(separator: "  \u{00B7}  "))
        #expect(l.headerSubtitle == "\(l.overdueCount) overdue  \u{00B7}  Today Sat, 03 Oct  \u{00B7}  Tomorrow Sun, 04 Oct")

        let empty = DueListBuilder.build(store: StoreFactory.make().store, today: Self.today, locale: Self.en)
        #expect(empty.headerParts == ["Today Sat, 03 Oct", "Tomorrow Sun, 04 Oct"])
        #expect(DueList().headerParts == [DueList.initialSubtitle])
    }

    @Test func headerLinesNeverEndInASeparator() {
        // Every candidate layout of the subtitle puts `·` only between parts on the same line; the first candidate
        // is the one-line form, the last one part per line.
        #expect(DueList.headerLineGroupings(1) == [[0..<1]])
        #expect(DueList.headerLineGroupings(2) == [[0..<2], [0..<1, 1..<2]])
        #expect(DueList.headerLineGroupings(3) == [[0..<3], [0..<2, 2..<3], [0..<1, 1..<3], [0..<1, 1..<2, 2..<3]])
        let l = DueList(sections: [], headerSubtitle: "12 overdue  \u{00B7}  Today Sat, 03 Oct  \u{00B7}  Tomorrow Sun, 04 Oct",
                        headerParts: ["12 overdue", "Today Sat, 03 Oct", "Tomorrow Sun, 04 Oct"])
        for grouping in DueList.headerLineGroupings(3) {
            #expect(grouping.flatMap { Array($0) } == [0, 1, 2])          // every part once, in order
            for r in grouping {
                let line = l.headerLine(r)
                #expect(!line.hasSuffix("\u{00B7}") && !line.hasSuffix("\u{00B7} ") && !line.hasPrefix("\u{00B7}"))
                #expect(!NetText.trim(line).hasSuffix("\u{00B7}"))
            }
        }
        #expect(l.headerLine(0..<2) == "12 overdue  \u{00B7}  Today Sat, 03 Oct")
        #expect(l.headerLine(2..<3) == "Tomorrow Sun, 04 Oct")
    }

    // MARK: V2-J7 / V2-DESIGN — Activity log columns

    @Test func activityLogColumnsFitTheDefaultWindow() {
        let w = ActivityLogText.columnWidths
        #expect(w.count == ActivityLogText.columns.count)
        #expect(ActivityLogText.windowWidth == 860)
        // Every column (and the table chrome, with a legacy scroller showing) fits the 860-pt window.
        #expect(ActivityLogText.idealTableWidth <= ActivityLogText.windowWidth, "\(ActivityLogText.idealTableWidth)")
        for c in w { #expect(c.min <= c.ideal && c.min > 0) }

        // Content widths in the brand mono at 11 pt (system monospaced: the widest of the two brand faces).
        func width(_ s: String, weight: NSFont.Weight = .regular) -> Double {
            let f = NSFont.monospacedSystemFont(ofSize: 11, weight: weight)
            return Double((s as NSString).size(withAttributes: [.font: f]).width)
        }
        #expect(w[0].min >= width("2026-10-01 05:07:00 UTC"))
        #expect(w[1].min >= width("2026-09-30 23:07:00"))
        #expect(w[2].min >= width("Removed", weight: .semibold) + 12)    // capsule padding 6 + 6
        #expect(w[3].min >= width("Equipment/Area"))                      // Kind on one line (V2-DESIGN)
        #expect(w[3].min >= width("Ports import"))
        // Header titles fit too (V-DESIGN rule 5).
        for (k, title) in ActivityLogText.columns.enumerated() {
            #expect(w[k].ideal >= width(title), "\(title)")
        }
        // Detail is not the narrowest wrap column any more (it was 106 pt and clipped).
        #expect(w[5].ideal >= 120)
    }

    // MARK: V2-DESIGN rule 17 — Search status bar

    @Test func searchStatusBarOnlyWhenThereIsSomethingToShow() {
        #expect(!SearchWindowText.showsStatusBar(isRunning: false, hitCount: 0))   // before the first search / no hits
        #expect(SearchWindowText.showsStatusBar(isRunning: true, hitCount: 0))     // "Searching…"
        #expect(SearchWindowText.showsStatusBar(isRunning: false, hitCount: 3))    // "3 results for …"
        #expect(SearchWindowText.showsStatusBar(isRunning: true, hitCount: 3))
    }
}
