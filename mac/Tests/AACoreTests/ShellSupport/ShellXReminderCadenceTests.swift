// TV: OWNERSHIP W-SHELL acceptance "reminder dedup/digest cadence tests with FixedClock (launch, 30-min, day change,
//     wake)"; 02 §7.8 "Digest" (LastDigestDate == today → nothing; otherwise set it and mark dirty even when nothing
//     is due), 03 §7.1 "Digest"; 02 REPO-112 (dedup key, reset when nothing is due, forced digest notification),
//     REPO-113; 09 CREW-092 (crew suffix); DECISIONS 02 Q-7 (day rollover; per-device digest date beats a pulled
//     LastDigestDate), Q-13 (Dock badge = overdue count).
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct ShellXReminderCadenceTests {
    nonisolated private static func day(_ local: String) -> CivilDate {
        FixedClock(local: local, zone: TZ.athens).today()
    }

    nonisolated private static let sep29 = day("2026-09-29T08:00")
    nonisolated private static let sep30 = day("2026-09-30T00:00:05")

    private func input(_ s: ReminderSummary, crew: Int = 0, today: CivilDate = sep29, ui: String? = nil,
                       device: String? = nil, safe: Bool = false) -> ShellXReminderInput {
        ShellXReminderInput(summary: s, crewExpiring: crew, today: today, uiLastDigestDate: ui,
                            deviceDigestDate: device, safeMode: safe)
    }

    // MARK: Digest planner (02 §7.8 / 03 §7.1)

    @Test func digestVectors() {
        let today = Self.sep29
        // LastDigestDate == today → nothing, no dirty mark.
        #expect(ShellXDigestPlanner.decide(uiLastDigestDate: "2026-09-29", deviceDigestDate: nil, today: today,
                                           safeMode: false) == .none)
        // Yesterday → set it (mark dirty) and show.
        #expect(ShellXDigestPlanner.decide(uiLastDigestDate: "2026-09-28", deviceDigestDate: nil, today: today,
                                           safeMode: false) == ShellXDigestDecision(markUiDate: true, showDigest: true))
        // Never → set and show.
        #expect(ShellXDigestPlanner.decide(uiLastDigestDate: nil, deviceDigestDate: nil, today: today,
                                           safeMode: false) == ShellXDigestDecision(markUiDate: true, showDigest: true))
        // Safe mode → nothing (REPO-113 "not in safe mode").
        #expect(ShellXDigestPlanner.decide(uiLastDigestDate: nil, deviceDigestDate: nil, today: today,
                                           safeMode: true) == .none)
    }

    @Test func perDeviceDigestDateBeatsAPulledLastDigestDate() {
        let today = Self.sep29
        // A shared-save pull from another computer carries LastDigestDate = today; this Mac last showed it yesterday.
        #expect(ShellXDigestPlanner.decide(uiLastDigestDate: "2026-09-29", deviceDigestDate: "2026-09-28", today: today,
                                           safeMode: false) == ShellXDigestDecision(markUiDate: false, showDigest: true))
        // This Mac already showed today's digest, the data file says yesterday (e.g. restored backup): mark only.
        #expect(ShellXDigestPlanner.decide(uiLastDigestDate: "2026-09-28", deviceDigestDate: "2026-09-29", today: today,
                                           safeMode: false) == ShellXDigestDecision(markUiDate: true, showDigest: false))
    }

    // MARK: Dedup (REPO-112)

    @Test func dedupKeyAndReset() {
        var engine = ShellXReminderEngine()
        let s = ReminderSummary(overdue: 2, dueToday: 2, dueWeek: 3)
        let body = engine.check(s, crewExpiring: 0, today: Self.sep29, force: false)
        #expect(body == "2 overdue  ·  2 due today  ·  3 due this week")
        #expect(engine.lastKey == "2026-09-29|2|2|3|0")
        #expect(engine.check(s, crewExpiring: 0, today: Self.sep29, force: false) == nil)      // unchanged → silent
        #expect(engine.check(s, crewExpiring: 0, today: Self.sep29, force: true) == body)      // forced (digest)
        #expect(engine.check(s, crewExpiring: 1, today: Self.sep29, force: false)
                == "2 overdue  ·  2 due today  ·  3 due this week  ·  1 crew contract(s) expiring")
        #expect(engine.lastKey == "2026-09-29|2|2|3|1")
        // Nothing due and no crew → no notification and the key resets, so the same situation re-announces later.
        #expect(engine.check(ReminderSummary(), crewExpiring: 0, today: Self.sep29, force: true) == nil)
        #expect(engine.lastKey == nil)
        #expect(engine.check(s, crewExpiring: 1, today: Self.sep29, force: false) != nil)
        // Only crew expiring still notifies (CREW-092).
        var e2 = ShellXReminderEngine()
        #expect(e2.check(ReminderSummary(), crewExpiring: 3, today: Self.sep29, force: false)
                == "Nothing due.  ·  3 crew contract(s) expiring")
    }

    // MARK: Cadence (launch, 30-min, day change, wake)

    @Test func cadenceAcrossLaunchTimerDayChangeAndWake() {
        var engine = ShellXReminderEngine()
        let due = ReminderSummary(overdue: 1, dueToday: 2, dueWeek: 0)

        // Launch on 09-29, digest never shown: set LastDigestDate, record the device date, open the panel, notify.
        var a = engine.run(.launch, input(due, ui: "2026-09-28"))
        #expect(a.setUiDigestDate == "2026-09-29")
        #expect(a.setDeviceDigestDate == "2026-09-29")
        #expect(a.openDuePanel)
        #expect(a.notificationBody == "1 overdue  ·  2 due today")
        #expect(a.dockBadge == "1")
        #expect(a.headline == "1 overdue  ·  2 due today")
        #expect(a.runWorkOrderDigest)

        // 30-min timer, same situation: nothing new (the timer never runs the digest).
        a = engine.run(.timer, input(due, ui: "2026-09-29", device: "2026-09-29"))
        #expect(a.setUiDigestDate == nil && a.setDeviceDigestDate == nil && !a.openDuePanel)
        #expect(a.notificationBody == nil)
        #expect(a.runWorkOrderDigest)                                  // work orders on every pass (ARCH §9.3)

        // Timer after a change: one more task due today.
        let more = ReminderSummary(overdue: 1, dueToday: 3, dueWeek: 0)
        a = engine.run(.timer, input(more, ui: "2026-09-29", device: "2026-09-29"))
        #expect(a.notificationBody == "1 overdue  ·  3 due today")

        // Wake later the same day: the digest is already done; no new notification.
        a = engine.run(.wake, input(more, ui: "2026-09-29", device: "2026-09-29"))
        #expect(a.setUiDigestDate == nil && !a.openDuePanel && a.notificationBody == nil)

        // Midnight rollover (NSCalendarDayChanged) while AA stays open: the new day's digest runs and forces.
        let next = ReminderSummary(overdue: 4, dueToday: 0, dueWeek: 2)
        a = engine.run(.dayChanged, input(next, today: Self.sep30, ui: "2026-09-29", device: "2026-09-29"))
        #expect(a.setUiDigestDate == "2026-09-30")
        #expect(a.setDeviceDigestDate == "2026-09-30")
        #expect(a.openDuePanel)
        #expect(a.notificationBody == "4 overdue  ·  2 due this week")
        #expect(engine.lastKey == "2026-09-30|4|0|2|0")

        // Wake that crossed midnight without a day-change notification still gets the digest.
        var e2 = ShellXReminderEngine()
        a = e2.run(.wake, input(next, today: Self.sep30, ui: "2026-09-29", device: "2026-09-29"))
        #expect(a.setUiDigestDate == "2026-09-30" && a.openDuePanel && a.notificationBody != nil)
    }

    @Test func digestWithNothingDueStillMarksTheDate() {
        var engine = ShellXReminderEngine()
        let a = engine.run(.launch, input(ReminderSummary(), ui: nil))
        #expect(a.setUiDigestDate == "2026-09-29")                    // "mark dirty even when nothing is due"
        #expect(a.setDeviceDigestDate == "2026-09-29")
        #expect(!a.openDuePanel)
        #expect(a.notificationBody == nil)
        #expect(a.dockBadge == nil)
        #expect(a.headline == "Nothing due.")
    }

    @Test func safeModeRunsNothing() {
        var engine = ShellXReminderEngine()
        let a = engine.run(.launch, input(ReminderSummary(overdue: 3), safe: true))
        #expect(a.setUiDigestDate == nil && a.setDeviceDigestDate == nil && !a.openDuePanel)
        #expect(a.notificationBody == nil)
        #expect(!a.runWorkOrderDigest)
        #expect(engine.lastKey == nil)
    }

    @Test func reasonsThatRunTheDigest() {
        #expect(ShellXReminderReason.launch.includesDigest)
        #expect(ShellXReminderReason.dayChanged.includesDigest)
        #expect(ShellXReminderReason.wake.includesDigest)
        #expect(!ShellXReminderReason.timer.includesDigest)
    }

    // MARK: Integration with F2's ReminderService and the store

    @Test func launchPassOverARealStore() {
        let clock = FixedClock(local: "2026-09-29T09:00", zone: TZ.athens)
        let data = AppData()
        let overdue = TaskItem(name: "Calibrate gas detectors")
        overdue.deadline = NetDateTime(year: 2026, month: 9, day: 28, kind: .unspecified)
        let today = TaskItem(name: "Check purifier")
        today.deadline = NetDateTime(year: 2026, month: 9, day: 29, kind: .unspecified)
        data.tasks = [overdue, today]
        let m = StoreFactory.make(data: data, clock: clock)
        let s = ReminderService.compute(store: m.store, today: clock.today())
        var engine = ShellXReminderEngine()
        let a = engine.run(.launch, ShellXReminderInput(summary: s, crewExpiring: 0, today: clock.today(),
                                                        uiLastDigestDate: m.store.data.ui.lastDigestDate,
                                                        deviceDigestDate: nil))
        #expect(a.notificationBody == "1 overdue  ·  1 due today")
        #expect(a.dockBadge == "1")
        #expect(ReminderService.dedupKey(s, crewExpiring: 0, today: clock.today()) == "2026-09-29|1|1|0|0")
    }

    // MARK: Per-device digest store

    @Test func deviceDigestStoreRecordsPerDataFile() {
        let temp = TempDefaults("aa.tests.shellx")
        defer { temp.remove() }
        let defaults = temp.defaults
        let store = ShellXDeviceDigestStore(prefs: MacPreferences(defaults: defaults))
        let a = URL(fileURLWithPath: "/Users/u/Library/Application Support/AA/data.json")
        let b = URL(fileURLWithPath: "/Volumes/STICK/AA Data/data.json")
        #expect(store.date(for: a) == nil)
        store.record("2026-09-29", for: a)
        store.record("2026-09-28", for: b)
        #expect(store.date(for: a) == "2026-09-29")
        #expect(store.date(for: URL(fileURLWithPath: "/Volumes/stick/AA Data/./data.json")) == "2026-09-28")
        store.record("2026-09-30", for: a)
        #expect(store.date(for: a) == "2026-09-30")
        for i in 0..<(ShellXDeviceDigestStore.capacity + 5) {
            store.record("2026-10-01", for: URL(fileURLWithPath: "/tmp/f\(i)/data.json"))
        }
        #expect(store.date(for: a) == nil)                            // oldest entries are dropped
        #expect(store.date(for: URL(fileURLWithPath: "/tmp/f36/data.json")) == "2026-10-01")
    }
}
