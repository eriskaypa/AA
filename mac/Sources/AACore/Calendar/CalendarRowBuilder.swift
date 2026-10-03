// Spec: 07 §3.1 VIEW-002…021 (Calendar rows, filters, ordering, Agenda fan-out, titles, font scale), §4.1.1–4.1.5
//       (Refresh, ScheduleRow, DateGroupConverter), §2.1–2.3 (item universe, enumeration order, completion),
//       09 CREW-091 (crew checklist rows), DECISIONS 07 Q-09 (weekday names via the user's locale), Q-12 (Overdue
//       group in All Upcoming / Agenda — additive), W-02 / W-03 (rows bind to the live model).
// Pure logic over the live model (main actor); the SwiftUI page only renders what this builds.
import Foundation

/// The five Calendar views (VIEW-004). The raw value is the persisted `Ui.CalendarViewMode` string.
public enum CalViewMode: String, CaseIterable, Sendable, Hashable {
    case day = "Day", week = "Week", month = "Month", all = "All", agenda = "Agenda"

    /// VIEW-004 / C19: the stored value is matched exactly ("Week"/"Month"/"All"/"Agenda"); anything else → Day.
    public init(stored: String?) {
        switch stored {
        case "Week": self = .week
        case "Month": self = .month
        case "All": self = .all
        case "Agenda": self = .agenda
        default: self = .day
        }
    }

    /// Radio / segment label (VIEW-004).
    public var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .all: return "All Upcoming"
        case .agenda: return "Agenda"
        }
    }

    /// The Agenda radio's tooltip (VIEW-004); nil for the others.
    public var help: String? { self == .agenda ? "All upcoming tasks grouped by day." : nil }
}

/// What a Calendar row wraps (VIEW-012).
public enum CalRowKind: Sendable, Hashable { case task, procedure, step, crewStep }

/// One schedule row (C# `ScheduleRow`, 07 §4.1.4). Name, dates and recurrence are captured when the list is built;
/// `status` and `isComplete` read the LIVE model (W-02 / W-03: every Agenda occurrence of an item shows the same
/// Done state the instant one of them is toggled).
@MainActor
public struct CalScheduleRow: @MainActor Identifiable {
    public let id: String
    public let item: AnyObject
    public let itemID: UUID
    public let kind: CalRowKind
    /// The parent procedure (steps) or crew member (crew items); nil for tasks and procedures.
    public let ownerID: UUID?
    public let name: String
    public let deadline: NetDateTime
    public let rangeStart: NetDateTime?
    public let recurrence: String
    /// Agenda only: the covered day this occurrence represents.
    public let occurrenceDate: CivilDate?

    init(id: String, item: AnyObject, itemID: UUID, kind: CalRowKind, ownerID: UUID?, name: String,
         deadline: NetDateTime, rangeStart: NetDateTime?, recurrence: String, occurrenceDate: CivilDate? = nil) {
        self.id = id; self.item = item; self.itemID = itemID; self.kind = kind; self.ownerID = ownerID
        self.name = name; self.deadline = deadline; self.rangeStart = rangeStart; self.recurrence = recurrence
        self.occurrenceDate = occurrenceDate
    }

    /// `RangeStart.Date` when both are set and in order, else the RAW deadline (it may carry a time).
    public var effectiveStart: NetDateTime {
        if let s = rangeStart, s.civilDate <= deadline.civilDate { return s.date }
        return deadline
    }

    /// Both set and `RangeStart.Date < Deadline.Date`.
    public var isRanged: Bool {
        guard let s = rangeStart else { return false }
        return s.civilDate < deadline.civilDate
    }

    /// `EffectiveStart.Date <= day <= Deadline.Date`.
    public func covers(_ day: CivilDate) -> Bool {
        effectiveStart.civilDate <= day && deadline.civilDate >= day
    }

    /// "When" column: `"yyyy-MM-dd → yyyy-MM-dd"` when ranged, else the deadline day.
    public var rangeDisplay: String {
        if isRanged, let s = rangeStart { return s.format(.isoDate) + " \u{2192} " + deadline.format(.isoDate) }
        return deadline.format(.isoDate)
    }

    /// `OccurrenceDate ?? Deadline` (full value — the deadline keeps its time for ordering).
    public var groupKey: NetDateTime {
        if let o = occurrenceDate { return NetDateTime.calendarDate(o) }
        return deadline
    }

    /// The day the group label is computed from.
    public var groupDay: CivilDate { occurrenceDate ?? deadline.civilDate }

    /// Status column, read live: task/procedure enum name (`Todo`, `InProgress`, `Blocked`, `Done`), step
    /// `"Done"`/`"Step"`.
    public var status: String {
        switch item {
        case let t as TaskItem: return t.status.name
        case let p as Procedure: return p.status.name
        case let s as ChecklistStep: return s.done ? "Done" : "Step"
        default: return ""
        }
    }

    /// Done column, read live: task `IsComplete`, procedure `Status == Done`, step `Done`.
    public var isComplete: Bool {
        switch item {
        case let t as TaskItem: return t.isComplete
        case let p as Procedure: return p.status == .done
        case let s as ChecklistStep: return s.done
        default: return false
        }
    }

    /// VIEW-013: writes the Done state through to the model (procedure: tick → Done, untick → Todo). Returns
    /// whether anything changed; the caller then saves immediately (model first, then save — W-02).
    @discardableResult
    public func setComplete(_ value: Bool) -> Bool {
        guard value != isComplete else { return false }
        switch item {
        case let t as TaskItem: t.isComplete = value
        case let p as Procedure: p.status = value ? .done : .todo
        case let s as ChecklistStep: s.done = value
        default: return false
        }
        return true
    }

    /// Overdue = the deadline (range end) is before today and the item is not complete (DECISIONS 07 Q-12,
    /// the Board's rule VIEW-043).
    public func isOverdue(today: CivilDate) -> Bool { deadline.civilDate < today && !isComplete }

    /// A copy pinned to one covered day (Agenda fan-out).
    func at(_ day: CivilDate) -> CalScheduleRow {
        CalScheduleRow(id: id + "@" + day.iso, item: item, itemID: itemID, kind: kind, ownerID: ownerID, name: name,
                       deadline: deadline, rangeStart: rangeStart, recurrence: recurrence, occurrenceDate: day)
    }

    func withID(_ newID: String) -> CalScheduleRow {
        CalScheduleRow(id: newID, item: item, itemID: itemID, kind: kind, ownerID: ownerID, name: name,
                       deadline: deadline, rangeStart: rangeStart, recurrence: recurrence,
                       occurrenceDate: occurrenceDate)
    }
}

/// One section of the schedule list (Agenda day groups, the Overdue group, or the single flat group).
@MainActor
public struct CalScheduleGroup: @MainActor Identifiable {
    public enum Role: Sendable, Hashable { case flat, overdue, upcoming, day }
    public let id: String
    public let role: Role
    /// Header label (`"Today"`, `"Tomorrow"`, `"Thu, 2026-10-01"`, `"Overdue"`, `"Upcoming"`); nil for a flat list.
    public let label: String?
    public let rows: [CalScheduleRow]
    /// `" ({count})"` as the WPF header prints it after the label.
    public var countText: String { " (\(rows.count))" }
}

/// The built list for one mode.
@MainActor
public struct CalSchedule {
    public let title: String
    public let groups: [CalScheduleGroup]
    public var rows: [CalScheduleRow] { groups.flatMap(\.rows) }
    public var isGrouped: Bool { groups.contains { $0.label != nil } }
}

@MainActor
public enum CalendarRowBuilder {
    /// VIEW-002: the title before the first refresh.
    public static let initialTitle = "Schedule Matrix"
    /// VIEW-011 header tooltip of the "When" column.
    public static let whenHelp = "Working range (start → deadline) when set, otherwise the due date."
    /// DECISIONS 07 Q-12 group labels (Mac additions).
    public static let overdueLabel = "Overdue"
    public static let upcomingLabel = "Upcoming"

    // MARK: Rows (07 §4.1.3, §2.2 order)

    /// Every dated row, in enumeration order: tasks pre-order with all nested subtasks, then each procedure followed
    /// by its steps, then each crew member's checklist items. Row ids are unique (`kind-id`, a suffix for a repeat).
    public static func allRows(_ data: AppData) -> [CalScheduleRow] {
        var out: [CalScheduleRow] = []
        var used: [String: Int] = [:]
        func add(_ r: CalScheduleRow) {
            let n = used[r.id, default: 0]
            used[r.id] = n + 1
            out.append(n == 0 ? r : r.withID(r.id + "#\(n)"))
        }
        var seen = Set<ObjectIdentifier>()
        func walk(_ t: TaskItem) {
            guard seen.insert(ObjectIdentifier(t)).inserted else { return }
            if let d = t.deadline { add(forTask(t, deadline: d)) }
            for s in t.subtasks { walk(s) }
        }
        for t in data.tasks { walk(t) }
        for p in data.procedures {
            if let d = p.deadline { add(forProcedure(p, deadline: d)) }
            for s in p.steps { if let d = s.deadline { add(forStep(s, procedure: p, deadline: d)) } }
        }
        for c in data.crew {
            for s in c.checklist { if let d = s.deadline { add(forCrewStep(s, member: c, deadline: d)) } }
        }
        return out
    }

    static func forTask(_ t: TaskItem, deadline: NetDateTime) -> CalScheduleRow {
        CalScheduleRow(id: "t-" + t.id.netString, item: t, itemID: t.id, kind: .task, ownerID: nil, name: t.name,
                       deadline: deadline, rangeStart: t.rangeStart, recurrence: t.recurrence.name)
    }

    static func forProcedure(_ p: Procedure, deadline: NetDateTime) -> CalScheduleRow {
        CalScheduleRow(id: "p-" + p.id.netString, item: p, itemID: p.id, kind: .procedure, ownerID: nil, name: p.name,
                       deadline: deadline, rangeStart: nil, recurrence: p.recurrence.name)
    }

    /// `"{Title}   ·  [{Procedure}]"` (3 spaces, U+00B7, 2 spaces).
    static func forStep(_ s: ChecklistStep, procedure p: Procedure, deadline: NetDateTime) -> CalScheduleRow {
        CalScheduleRow(id: "s-" + s.id.netString, item: s, itemID: s.id, kind: .step, ownerID: p.id,
                       name: stepName(s.title, procedure: p.name), deadline: deadline, rangeStart: nil, recurrence: "")
    }

    /// CREW-091: `"{Title}   ·  👤 {FullName or (unnamed)}"`.
    static func forCrewStep(_ s: ChecklistStep, member c: CrewMember, deadline: NetDateTime) -> CalScheduleRow {
        CalScheduleRow(id: "c-" + s.id.netString, item: s, itemID: s.id, kind: .crewStep, ownerID: c.id,
                       name: crewStepName(s.title, fullName: c.fullName), deadline: deadline, rangeStart: nil,
                       recurrence: "")
    }

    public static func stepName(_ title: String, procedure: String) -> String {
        "\(title)   \u{00B7}  [\(procedure)]"
    }

    public static func crewStepName(_ title: String, fullName: String) -> String {
        "\(title)   \u{00B7}  \u{1F464} \(fullName.isEmpty ? "(unnamed)" : fullName)"
    }

    // MARK: Filters, ordering and grouping (VIEW-005…010, §4.1.3)

    /// The Sunday on or before `d` (week math is Sunday-start regardless of locale, 07 §0).
    public static func weekStart(_ d: CivilDate) -> CivilDate { d.addingDays(-d.weekday) }

    /// The first of `d`'s month.
    public static func monthStart(_ d: CivilDate) -> CivilDate { CivilDate(year: d.year, month: d.month, day: 1)! }

    /// VIEW-005…008 titles.
    public static func title(mode: CalViewMode, selected d: CivilDate) -> String {
        switch mode {
        case .day: return "Schedule \u{2014} \(d.iso)"
        case .week: return "Schedule \u{2014} week of \(weekStart(d).iso)"
        case .month: return "Schedule \u{2014} " + String(d.iso.prefix(7))
        case .all: return "Schedule \u{2014} all upcoming"
        case .agenda: return "Agenda \u{2014} upcoming by day"
        }
    }

    /// The rows a mode keeps, before ordering.
    public static func filter(_ rows: [CalScheduleRow], mode: CalViewMode, selected d: CivilDate,
                              today: CivilDate) -> [CalScheduleRow] {
        switch mode {
        case .day:
            return rows.filter { $0.covers(d) }
        case .week:
            let start = weekStart(d), end = start.addingDays(7)
            return rows.filter { $0.effectiveStart.civilDate < end && $0.deadline.civilDate >= start }
        case .month:
            let ms = monthStart(d), me = ms.addingMonths(1)
            return rows.filter { $0.effectiveStart.civilDate < me && $0.deadline.civilDate >= ms }
        case .all, .agenda:
            return rows.filter { $0.deadline.civilDate >= today || $0.covers(today) }
        }
    }

    /// VIEW-009: stable `OrderBy(EffectiveStart).ThenBy(Deadline)` over full values.
    public static func ordered(_ rows: [CalScheduleRow]) -> [CalScheduleRow] {
        stableSorted(rows) { a, b in
            if a.effectiveStart.ticks != b.effectiveStart.ticks { return a.effectiveStart.ticks < b.effectiveStart.ticks }
            return a.deadline.ticks < b.deadline.ticks
        }
    }

    /// VIEW-010 fan-out: a ranged row yields one occurrence per covered day from `max(start, today)` to the deadline,
    /// unless that span is more than 31 days (then one occurrence on the deadline day).
    public static func fanOut(_ rows: [CalScheduleRow], today: CivilDate) -> [CalScheduleRow] {
        var occ: [CalScheduleRow] = []
        for r in rows {
            guard r.isRanged else { occ.append(r); continue }
            let from = max(r.effectiveStart.civilDate, today), to = r.deadline.civilDate
            if from.days(to: to) > 31 { occ.append(r.at(to)); continue }
            var day = from
            while day <= to {
                occ.append(r.at(day))
                day = day.addingDays(1)
            }
        }
        return stableSorted(occ) { a, b in
            if a.groupKey.ticks != b.groupKey.ticks { return a.groupKey.ticks < b.groupKey.ticks }
            return NetText.compareCulture(a.name, b.name) == .orderedAscending
        }
    }

    /// DateGroupConverter (07 §4.1.5): "Today", "Tomorrow", else `"{ddd}, yyyy-MM-dd"` in the user's locale
    /// (DECISIONS 07 Q-09; tests pin en_US).
    public static func dayLabel(_ day: CivilDate, today: CivilDate, locale: Locale = .current) -> String {
        if day == today { return "Today" }
        if day == today.addingDays(1) { return "Tomorrow" }
        return CalDateText.format(day, "EEE", locale: locale) + ", " + day.iso
    }

    /// DECISIONS 07 Q-12: the past-due, not-done rows (one per item, never fanned out).
    public static func overdue(_ rows: [CalScheduleRow], today: CivilDate) -> [CalScheduleRow] {
        rows.filter { $0.isOverdue(today: today) }
    }

    /// The whole list for one mode (07 §4.1.3) plus the additive Overdue group for All Upcoming / Agenda.
    public static func build(data: AppData, mode: CalViewMode, selected: CivilDate, today: CivilDate,
                             locale: Locale = .current) -> CalSchedule {
        build(rows: allRows(data), mode: mode, selected: selected, today: today, locale: locale)
    }

    public static func build(rows: [CalScheduleRow], mode: CalViewMode, selected: CivilDate, today: CivilDate,
                             locale: Locale = .current) -> CalSchedule {
        let t = title(mode: mode, selected: selected)
        let filtered = filter(rows, mode: mode, selected: selected, today: today)
        switch mode {
        case .day, .week, .month:
            return CalSchedule(title: t, groups: [CalScheduleGroup(id: "flat", role: .flat, label: nil,
                                                                    rows: ordered(filtered))])
        case .all:
            let late = ordered(overdue(rows, today: today))
            let main = ordered(filtered)
            guard !late.isEmpty else {
                return CalSchedule(title: t, groups: [CalScheduleGroup(id: "flat", role: .flat, label: nil, rows: main)])
            }
            var groups = [CalScheduleGroup(id: "overdue", role: .overdue, label: overdueLabel, rows: late)]
            if !main.isEmpty {
                groups.append(CalScheduleGroup(id: "upcoming", role: .upcoming, label: upcomingLabel, rows: main))
            }
            return CalSchedule(title: t, groups: groups)
        case .agenda:
            var groups: [CalScheduleGroup] = []
            let late = stableSorted(overdue(rows, today: today)) { a, b in
                if a.deadline.ticks != b.deadline.ticks { return a.deadline.ticks < b.deadline.ticks }
                return NetText.compareCulture(a.name, b.name) == .orderedAscending
            }
            if !late.isEmpty {
                groups.append(CalScheduleGroup(id: "overdue", role: .overdue, label: overdueLabel,
                                               rows: late.map { $0.withID("o-" + $0.id) }))
            }
            var currentDay: CivilDate?
            var bucket: [CalScheduleRow] = []
            func close() {
                guard let d = currentDay, !bucket.isEmpty else { return }
                groups.append(CalScheduleGroup(id: "d-" + d.iso, role: .day,
                                               label: dayLabel(d, today: today, locale: locale), rows: bucket))
            }
            for r in fanOut(filtered, today: today) {
                if r.groupDay != currentDay {
                    close()
                    currentDay = r.groupDay
                    bucket = []
                }
                bucket.append(r)
            }
            close()
            return CalSchedule(title: t, groups: groups)
        }
    }

    /// LINQ `OrderBy` is stable; Swift's `sort` is not guaranteed to be, so ties keep the input order explicitly.
    public static func stableSorted<T>(_ items: [T], by less: (T, T) -> Bool) -> [T] {
        items.enumerated().sorted { a, b in
            if less(a.element, b.element) { return true }
            if less(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}

/// VIEW-017: the list text size stepper (A- / A+, ⌘− / ⌘+).
public enum CalFontScale {
    public static let defaultSize = 15.0
    public static let minimum = 11.0
    public static let maximum = 28.0
    public static let step = 1.5
    public static let smallerHelp = "Smaller list text"
    public static let biggerHelp = "Bigger list text"

    /// A stored `Ui.CalendarFontScale` is applied only when `10 <= v <= 30` (wider than the stepper's clamp).
    public static func initial(stored: Double?) -> Double {
        guard let v = stored, v.isFinite, v >= 10, v <= 30 else { return defaultSize }
        return v
    }

    /// `clamp(current ± 1.5, 11, 28)`.
    public static func stepped(_ current: Double, bigger: Bool) -> Double {
        clamp(current + (bigger ? step : -step))
    }

    public static func clamp(_ v: Double) -> Double { min(max(v, minimum), maximum) }
}

/// Locale-aware day / month names for chrome (DECISIONS 07 Q-09) over invariant civil dates.
public enum CalDateText {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    /// Formats a civil date with a `DateFormatter` pattern (`EEE`, `EEEE`, `MMM d`, `MMMM yyyy`, …) in the Gregorian
    /// calendar and the given locale. The date is anchored at noon UTC so no zone can move it to another day.
    public static func format(_ day: CivilDate, _ pattern: String, locale: Locale = .current) -> String {
        let key = pattern + "|" + locale.identifier
        lock.lock()
        let f: DateFormatter
        if let cached = cache[key] {
            f = cached
        } else {
            f = DateFormatter()
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            f.calendar = cal
            f.timeZone = cal.timeZone
            f.locale = locale
            f.dateFormat = pattern
            cache[key] = f
        }
        let date = Date(timeIntervalSince1970: TimeInterval(day.daysFromCivil) * 86_400 + 43_200)
        let s = f.string(from: date)
        lock.unlock()
        return s
    }

    /// Sunday-first short weekday symbols in the locale (Planner Month header, DECISIONS 07 Q-09).
    public static func shortWeekdaySymbols(locale: Locale = .current) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        return cal.shortWeekdaySymbols
    }
}
