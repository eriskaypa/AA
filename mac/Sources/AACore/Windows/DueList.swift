// Spec: 08 §2.1 (QUICK-007…020, QUICK-022, QUICK-025), §3.1 (Refresh / Collect / CollectUpcoming / CollectOverdue /
//       MkOverdue / JobNav — exact), §6.3 (a pure builder with an injected `today`), §7.1 (T-DUE-*), Q-3 (a scheduled
//       subtask job navigates to its root task — P2 fix), Q-17 (`ddd, dd MMM` in the current locale, Gregorian);
//       09 CREW-090 (crew checklist items); 02 REPO-044 (tick done from the window), REPO-114 (same inclusion rules as
//       the reminder counts, different buckets); DECISIONS 02 Q-11 (a row carries the matched child for selection).
// Every comparison uses the calendar day of the stored wall clock (`.Date`); day differences are calendar-day
// arithmetic (`CivilDate`), never `timeInterval / 86400` (T-DUE-15).
import Foundation

/// The glyph family of a due row (08 QUICK-010; the Mac view maps each to an SF Symbol, 08 §6.2-A).
public enum DueIcon: String, Sendable, Hashable, CaseIterable {
    case task, subtask, procedure, step, crew, job

    /// The Windows glyph (kept for accessibility labels and tests).
    public var glyph: String {
        switch self {
        case .task: return "\u{2713}"
        case .subtask: return "\u{21B3}"
        case .procedure: return "\u{1F4CB}"
        case .step: return "\u{2611}"
        case .crew: return "\u{1F9D1}\u{200D}\u{2708}\u{FE0F}"
        case .job: return "\u{1F552}"
        }
    }

    /// The SF Symbol used on the Mac (08 §6.2-A).
    public var symbol: String {
        switch self {
        case .task: return "checkmark.circle"
        case .subtask: return "arrow.turn.down.right"
        case .procedure: return "list.clipboard"
        case .step: return "checklist"
        case .crew: return "person.crop.circle.badge.checkmark"
        case .job: return "clock"
        }
    }
}

/// The row accent (08 QUICK-010 table; theme-independent, QUICK-025).
public enum DueAccent: String, Sendable, Hashable {
    case task, procedure, crew, job, overdue

    /// `#RRGGBB`.
    public var hex: String {
        switch self {
        case .task: return "#FFB74D"
        case .procedure: return "#2E9E5B"
        case .crew: return "#9C6ADE"
        case .job: return "#4FC3F7"
        case .overdue: return "#E05252"
        }
    }
}

/// Where a click on a row goes (08 QUICK-020). `.none` rows are not clickable (orphan step jobs).
public enum DueTarget: Sendable, Hashable {
    /// `Navigator.navigate(to: item, childID: child)`.
    case item(UUID, child: UUID?)
    /// `Navigator.navigateToCrew(member)`.
    case crew(UUID)
    case none
}

/// The completable model behind a row (08 QUICK-022), resolved again by id when ticked (ARCH §2.4).
public enum DueCompletable: Sendable, Hashable {
    case task(UUID), procedure(UUID), step(UUID)
}

public enum DueSectionKind: String, Sendable, Hashable, CaseIterable {
    case overdue = "OVERDUE", today = "TODAY", tomorrow = "TOMORROW", nextSevenDays = "NEXT 7 DAYS"
}

public struct DueRow: Sendable, Identifiable, Hashable {
    /// `"{section}|{model id}"` (+ `#n` for a duplicated id) — TODAY and TOMORROW may hold the same object (§6.3).
    public var id: String
    public var icon: DueIcon
    public var accent: DueAccent
    public var title: String
    public var subtitle: String
    public var target: DueTarget
    public var completable: DueCompletable

    public init(id: String, icon: DueIcon, accent: DueAccent, title: String, subtitle: String, target: DueTarget,
                completable: DueCompletable) {
        self.id = id; self.icon = icon; self.accent = accent; self.title = title; self.subtitle = subtitle
        self.target = target; self.completable = completable
    }

    public var isClickable: Bool { target != .none }
}

public struct DueSection: Sendable, Identifiable, Hashable {
    public var kind: DueSectionKind
    public var rows: [DueRow]

    public init(kind: DueSectionKind, rows: [DueRow]) { self.kind = kind; self.rows = rows }

    public var id: String { kind.rawValue }
    /// `"{LABEL}   ({count})"` (three spaces, 08 QUICK-008).
    public var header: String { "\(kind.rawValue)   (\(rows.count))" }
    public var isOverdue: Bool { kind == .overdue }
    /// TODAY / TOMORROW show `— nothing —` when empty (OVERDUE / NEXT 7 DAYS are omitted instead).
    public var showsNothingLine: Bool { rows.isEmpty }
}

public struct DueList: Sendable, Hashable {
    public var sections: [DueSection]
    public var headerSubtitle: String
    public var overdueCount: Int
    /// All four lists empty → the 🎉 line after TODAY and TOMORROW (08 QUICK-009).
    public var isEverythingEmpty: Bool

    public init(sections: [DueSection] = [], headerSubtitle: String = DueList.initialSubtitle, overdueCount: Int = 0,
                isEverythingEmpty: Bool = true) {
        self.sections = sections; self.headerSubtitle = headerSubtitle; self.overdueCount = overdueCount
        self.isEverythingEmpty = isEverythingEmpty
    }

    /// 08 QUICK-002 / QUICK-003 strings.
    public static let windowTitle = "Overdue, today & tomorrow"
    public static let headerTitle = "Due dates"
    public static let initialSubtitle = "Today & tomorrow"
    public static let nothingLine = "\u{2014} nothing \u{2014}"
    public static let emptyMessage = "Nothing overdue, or due in the next 7 days \u{1F389}"
    public static let markDoneHelp = "Mark done"
    public static let refreshHelp = "Refresh"
    public static let closeHelp = "Close"
    public static let resizeHelp = "Drag to resize"
    /// Header `📌 Due` tooltip (08 §1.1).
    public static let toolbarHelp = "Show a small floating window of tasks and procedures due today and tomorrow. (Ship work-order notifications live in each vessel's Work Orders tab.)"
}

@MainActor public enum DueListBuilder {
    /// One collected row before it is given its section id.
    struct Collected {
        let object: AnyObject
        let modelID: UUID
        var row: DueRow
        var sortDay: CivilDate
    }

    /// 08 §3.1 `Refresh` — OVERDUE (sorted oldest deadline first, stable), TODAY, TOMORROW, NEXT 7 DAYS (today+2 …
    /// today+7, each object once, excluding anything shown above, ` · due {ddd, dd MMM}` appended).
    public static func build(store: AppStore, today: CivilDate, locale: Locale = .current) -> DueList {
        let tomorrow = today.addingDays(1)
        let overdue = collectOverdue(store: store, today: today, locale: locale)
        let todayRows = collect(store: store, day: today)
        let tomorrowRows = collect(store: store, day: tomorrow)
        var shown = Set<ObjectIdentifier>()
        for c in overdue + todayRows + tomorrowRows { shown.insert(ObjectIdentifier(c.object)) }
        var upcoming: [Collected] = []
        var d = today.addingDays(2)
        let end = today.addingDays(7)
        while d <= end {
            for var c in collect(store: store, day: d) where shown.insert(ObjectIdentifier(c.object)).inserted {
                c.row.subtitle += " \u{00B7} due \(dayText(d, locale: locale))"
                upcoming.append(c)
            }
            d = d.addingDays(1)
        }

        var sections: [DueSection] = []
        if !overdue.isEmpty { sections.append(section(.overdue, overdue)) }
        sections.append(section(.today, todayRows))
        sections.append(section(.tomorrow, tomorrowRows))
        if !upcoming.isEmpty { sections.append(section(.nextSevenDays, upcoming)) }
        let subtitle = (overdue.isEmpty ? "" : "\(overdue.count) overdue  \u{00B7}  ")
            + "Today \(dayText(today, locale: locale))  \u{00B7}  Tomorrow \(dayText(tomorrow, locale: locale))"
        let empty = overdue.isEmpty && todayRows.isEmpty && tomorrowRows.isEmpty && upcoming.isEmpty
        return DueList(sections: sections, headerSubtitle: subtitle, overdueCount: overdue.count, isEverythingEmpty: empty)
    }

    /// `{d:ddd, dd MMM}` with the current culture's abbreviations on the Gregorian calendar (08 Q-17).
    public nonisolated static func dayText(_ d: CivilDate, locale: Locale = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var dc = DateComponents()
        dc.year = d.year; dc.month = d.month; dc.day = d.day; dc.hour = 12
        guard let date = cal.date(from: dc) else { return d.iso }
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = locale
        f.dateFormat = "EEE, dd MMM"
        return f.string(from: date)
    }

    /// 08 QUICK-022 / REPO-044: `BatchDone.setDone(model, done)` on the row's model (resolved by id). True when
    /// something changed (the caller then `markDirty(); flushIfDirty()`).
    public static func setDone(_ c: DueCompletable, done: Bool, store: AppStore) -> Bool {
        guard let model = resolve(c, store: store) else { return false }
        return BatchDone.setDone(model, done: done)
    }

    /// The live model behind a completable (nil when it vanished, e.g. after a reload).
    public static func resolve(_ c: DueCompletable, store: AppStore) -> AnyObject? {
        switch c {
        case .task(let id): return store.task(id: id)
        case .procedure(let id): return store.data.procedures.first { $0.id == id }
        case .step(let id): return store.step(id: id)?.step
        }
    }

    // MARK: Sections

    private static func section(_ kind: DueSectionKind, _ rows: [Collected]) -> DueSection {
        var used: [String: Int] = [:]
        let out = rows.map { c -> DueRow in
            var r = c.row
            let base = "\(kind.rawValue)|\(c.modelID.netString)"
            let n = used[base, default: 0]
            used[base] = n + 1
            r.id = n == 0 ? base : "\(base)#\(n)"
            return r
        }
        return DueSection(kind: kind, rows: out)
    }

    private static func crewName(_ m: CrewMember) -> String { m.fullName.isEmpty ? "(unnamed)" : m.fullName }

    // MARK: Collect(day) — tasks → procedures (+ steps) → crew steps → jobs, per-day Guid dedupe

    static func collect(store: AppStore, day: CivilDate) -> [Collected] {
        var items: [Collected] = []
        var seen = Set<UUID>()
        for t in store.data.tasks {
            var visited = Set<ObjectIdentifier>()
            collectTask(owner: t, t, day: day, into: &items, seen: &seen, visited: &visited)
        }
        for p in store.data.procedures {
            if p.status != .done, let d = p.deadline, d.civilDate == day, seen.insert(p.id).inserted {
                items.append(Collected(object: p, modelID: p.id, row: DueRow(
                    id: "", icon: .procedure, accent: .procedure, title: p.name, subtitle: "Procedure",
                    target: .item(p.id, child: nil), completable: .procedure(p.id)), sortDay: day))
            }
            for s in p.steps where !s.done {
                if let d = s.deadline, d.civilDate == day, seen.insert(s.id).inserted {
                    items.append(Collected(object: s, modelID: s.id, row: DueRow(
                        id: "", icon: .step, accent: .procedure, title: s.title,
                        subtitle: "Checklist step \u{00B7} \(p.name)", target: .item(p.id, child: s.id),
                        completable: .step(s.id)), sortDay: day))
                }
            }
        }
        for m in store.data.crew {
            for s in m.checklist where !s.done {
                if let d = s.deadline, d.civilDate == day, seen.insert(s.id).inserted {
                    items.append(Collected(object: s, modelID: s.id, row: DueRow(
                        id: "", icon: .crew, accent: .crew, title: s.title,
                        subtitle: "Crew checklist \u{00B7} \(crewName(m))", target: .crew(m.id),
                        completable: .step(s.id)), sortDay: day))
                }
            }
        }
        for j in store.allJobs() {
            guard let start = j.scheduledStart, start.civilDate == day, !jobDone(j), seen.insert(j.id).inserted else { continue }
            let (target, ctx, completable) = jobNav(j, store: store)
            items.append(Collected(object: j, modelID: j.id, row: DueRow(
                id: "", icon: .job, accent: .job, title: j.jobName,
                subtitle: "Scheduled \(start.format(.time))" + (ctx.isEmpty ? "" : " \u{00B7} \(ctx)"),
                target: target, completable: completable), sortDay: day))
        }
        return items
    }

    /// 08 QUICK-013: `!IsComplete && CoversDay(D)`; recursion continues into subtasks whatever the parent's state.
    private static func collectTask(owner: TaskItem, _ t: TaskItem, day: CivilDate, into items: inout [Collected],
                                    seen: inout Set<UUID>, visited: inout Set<ObjectIdentifier>) {
        guard visited.insert(ObjectIdentifier(t)).inserted else { return }
        if !t.isComplete && t.coversDay(day) && seen.insert(t.id).inserted {
            let isSub = owner !== t
            var kind = isSub ? "Subtask \u{00B7} \(owner.name)" : "Task"
            if t.hasRange, let d = t.deadline, let s = t.rangeStart {
                let w = day == d.civilDate ? "ends today" : (day == s.civilDate ? "starts today" : "ongoing")
                kind += " \u{00B7} \(w)"
            }
            items.append(Collected(object: t, modelID: t.id, row: DueRow(
                id: "", icon: isSub ? .subtask : .task, accent: .task, title: t.name, subtitle: kind,
                target: .item(owner.id, child: isSub ? t.id : nil), completable: .task(t.id)), sortDay: day))
        }
        for st in t.subtasks { collectTask(owner: owner, st, day: day, into: &items, seen: &seen, visited: &visited) }
    }

    private static func jobDone(_ j: any SchedulableJob) -> Bool {
        switch j {
        case let t as TaskItem: return t.isComplete
        case let s as ChecklistStep: return s.done
        case let p as Procedure: return p.status == .done
        default: return false
        }
    }

    /// 08 §3.1 `JobNav`: task → `Task job` (Q-3 fix: a subtask job opens its root task with the subtask selected);
    /// procedure → `Procedure job`; step → the first procedure whose Steps contains it (`Step job · {name}`), else
    /// the first crew member (`Crew step job · {name|(unnamed)}`), else `Step job` (not clickable).
    private static func jobNav(_ j: any SchedulableJob, store: AppStore) -> (DueTarget, String, DueCompletable) {
        switch j {
        case let t as TaskItem:
            if let root = store.topLevelTask(containing: t.id), root !== t {
                return (.item(root.id, child: t.id), "Task job", .task(t.id))
            }
            return (.item(t.id, child: nil), "Task job", .task(t.id))
        case let p as Procedure:
            return (.item(p.id, child: nil), "Procedure job", .procedure(p.id))
        case let s as ChecklistStep:
            if let owner = store.data.procedures.first(where: { pr in pr.steps.contains { $0 === s } }) {
                return (.item(owner.id, child: s.id), "Step job \u{00B7} \(owner.name)", .step(s.id))
            }
            if let m = store.data.crew.first(where: { c in c.checklist.contains { $0 === s } }) {
                return (.crew(m.id), "Crew step job \u{00B7} \(crewName(m))", .step(s.id))
            }
            return (.none, "Step job", .step(s.id))
        default:
            return (.none, "", .task(j.id))
        }
    }

    // MARK: CollectOverdue

    /// 08 QUICK-012: deadline day strictly before today and not done — tasks/subtasks (pre-order, a completed parent
    /// does not hide its subtasks), procedures, every step regardless of its procedure's status, crew checklist
    /// steps. Sorted by deadline day (stable). Scheduled jobs never count.
    static func collectOverdue(store: AppStore, today: CivilDate, locale: Locale) -> [Collected] {
        var items: [Collected] = []
        var seen = Set<UUID>()
        func mk(_ object: AnyObject, _ id: UUID, _ icon: DueIcon, _ title: String, _ kind: String, _ due: NetDateTime,
                _ target: DueTarget, _ completable: DueCompletable) -> Collected {
            let dueDay = due.civilDate
            let days = dueDay.days(to: today)
            return Collected(object: object, modelID: id, row: DueRow(
                id: "", icon: icon, accent: .overdue, title: title,
                subtitle: "\(kind) \u{00B7} \(days)d overdue (was due \(dayText(dueDay, locale: locale)))",
                target: target, completable: completable), sortDay: dueDay)
        }
        for t in store.data.tasks {
            var visited = Set<ObjectIdentifier>()
            func walk(_ x: TaskItem) {
                guard visited.insert(ObjectIdentifier(x)).inserted else { return }
                if !x.isComplete, let d = x.deadline, d.civilDate < today, seen.insert(x.id).inserted {
                    let isSub = x !== t
                    items.append(mk(x, x.id, isSub ? .subtask : .task, x.name, isSub ? "Subtask \u{00B7} \(t.name)" : "Task",
                                    d, .item(t.id, child: isSub ? x.id : nil), .task(x.id)))
                }
                for s in x.subtasks { walk(s) }
            }
            walk(t)
        }
        for p in store.data.procedures {
            if p.status != .done, let d = p.deadline, d.civilDate < today, seen.insert(p.id).inserted {
                items.append(mk(p, p.id, .procedure, p.name, "Procedure", d, .item(p.id, child: nil), .procedure(p.id)))
            }
            for s in p.steps where !s.done {
                if let d = s.deadline, d.civilDate < today, seen.insert(s.id).inserted {
                    items.append(mk(s, s.id, .step, s.title, "Checklist step \u{00B7} \(p.name)", d,
                                    .item(p.id, child: s.id), .step(s.id)))
                }
            }
        }
        for m in store.data.crew {
            for s in m.checklist where !s.done {
                if let d = s.deadline, d.civilDate < today, seen.insert(s.id).inserted {
                    items.append(mk(s, s.id, .crew, s.title, "Crew checklist \u{00B7} \(crewName(m))", d, .crew(m.id),
                                    .step(s.id)))
                }
            }
        }
        // `OrderBy(SortDate)` — stable.
        return items.enumerated().sorted { a, b in
            a.element.sortDay != b.element.sortDay ? a.element.sortDay < b.element.sortDay : a.offset < b.offset
        }.map(\.element)
    }
}

/// 08 QUICK-004 / QUICK-005 / §6.2-A: default and minimum size, size restore (values below the minimum are ignored,
/// not clamped) and the bottom-right initial origin (AppKit y grows upward).
public enum DueWindowGeometry {
    public static let defaultWidth = 350.0, defaultHeight = 480.0
    public static let minWidth = 260.0, minHeight = 220.0
    public static let inset = 16.0

    /// `Ui.DueWindowWidth ≥ MinWidth` → used, else the default (same for the height). A value larger than the
    /// visible screen (e.g. arriving from a Windows machine, 08 §4.4) is clamped to it.
    public static func restoredSize(width: Double?, height: Double?, maxWidth: Double = .infinity,
                                    maxHeight: Double = .infinity) -> (width: Double, height: Double) {
        var w = defaultWidth, h = defaultHeight
        if let v = width, v.isFinite, v >= minWidth { w = v }
        if let v = height, v.isFinite, v >= minHeight { h = v }
        return (max(minWidth, min(w, maxWidth)), max(minHeight, min(h, maxHeight)))
    }

    /// `x = visible.maxX − w − 16`, `y = visible.minY + 16`.
    public static func initialOrigin(visibleX: Double, visibleY: Double, visibleWidth: Double, width: Double)
        -> (x: Double, y: Double) {
        (visibleX + visibleWidth - width - inset, visibleY + inset)
    }

    /// 08 QUICK-006: the persisted pair after a resize (rounded to whole points like the WPF DIPs it mirrors).
    public static func persisted(width: Double, height: Double) -> (width: Double, height: Double) {
        (max(minWidth, width.rounded()), max(minHeight, height.rounded()))
    }
}
