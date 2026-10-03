// Spec: 07 §3.3 VIEW-084…106 (unscheduled pool, deadline-aware placement, due span, chips, tooltips, drops), §4.3.2–
//       4.3.7, §2.1/§2.2 (item universe and order), 09 CREW-091 (crew items placed), DECISIONS 07 Q-06 (grey every
//       completed item), Q-6 / ARCH §3.4 (placements and dates written as Unspecified calendar values).
import Foundation

/// What a Planner drag carries (VIEW-103): the job's id and family, plus the day a due-only chip represents.
public struct PlannerJobRef: Codable, Sendable, Hashable {
    public enum Family: String, Codable, Sendable { case task, procedure, step }
    public var id: UUID
    public var family: Family
    /// `"AAJobDay"`: the day of the due-only chip that was dragged (yyyy-MM-dd); nil otherwise.
    public var anchorDay: String?

    public init(id: UUID, family: Family, anchorDay: CivilDate? = nil) {
        self.id = id; self.family = family; self.anchorDay = anchorDay?.iso
    }

    public var anchor: CivilDate? { anchorDay.flatMap { CivilDate(iso: $0) } }
}

/// A chip in the all-day strip or a month cell (VIEW-090, VIEW-098).
@MainActor
public struct PlannerChip: @MainActor Identifiable {
    public let id: String
    public let job: any SchedulableJob
    public let ref: PlannerJobRef
    public let text: String
    public let isTimed: Bool
    public let isBold: Bool
    public let opacity: Double
    public let isDone: Bool
    public let tooltip: String
}

/// A timed block in a day column (VIEW-095).
@MainActor
public struct PlannerBlock: @MainActor Identifiable {
    public let id: String
    public let job: any SchedulableJob
    public let ref: PlannerJobRef
    public let slot: PlannerBlockSlot
    public let title: String
    public let subtitle: String
    public let isDone: Bool
    public let tooltip: String
}

/// A row of the Unscheduled Jobs pool (VIEW-084).
@MainActor
public struct PlannerPoolRow: @MainActor Identifiable {
    public let id: String
    public let job: any SchedulableJob
    public let ref: PlannerJobRef
    public let text: String
    public let isDone: Bool
}

@MainActor
public enum PlannerPlacement {
    public static let poolTitle = "Unscheduled Jobs"
    public static let poolHint = "Drag a job onto the grid to schedule it. Drag a scheduled block back here to unschedule. Double-click to edit."
    public static let poolSearchPrompt = "Search jobs..."
    public static let poolSearchHelp = "Filter the schedulable jobs by name."
    public static let savedListButton = "+ Saved list"
    public static let savedListHelp = "Search your saved lists and add items as real, schedulable tasks"
    public static let dueGutterLabel = "due"

    // MARK: Universe (§2.1, §2.2, §4.3.2)

    /// `AllSchedulable`: every task and nested subtask (pre-order), every procedure followed by its steps, every
    /// crew member's checklist items — jobs or not.
    public static func allSchedulable(_ data: AppData) -> [any SchedulableJob] {
        var out: [any SchedulableJob] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ t: TaskItem) {
            guard seen.insert(ObjectIdentifier(t)).inserted else { return }
            out.append(t)
            for s in t.subtasks { walk(s) }
        }
        for t in data.tasks { walk(t) }
        for p in data.procedures {
            out.append(p)
            for s in p.steps { out.append(s) }
        }
        for c in data.crew { for s in c.checklist { out.append(s) } }
        return out
    }

    public static func family(_ job: any SchedulableJob) -> PlannerJobRef.Family {
        switch job {
        case is TaskItem: return .task
        case is Procedure: return .procedure
        default: return .step
        }
    }

    public static func ref(_ job: any SchedulableJob, anchor: CivilDate? = nil) -> PlannerJobRef {
        PlannerJobRef(id: job.id, family: family(job), anchorDay: anchor)
    }

    /// Resolves a drag payload at drop time, by id, across tasks (recursive), procedures, procedure steps and crew
    /// checklist items (07 §7.3 "Payload").
    public static func resolve(_ ref: PlannerJobRef, store: AppStore) -> (any SchedulableJob)? {
        switch ref.family {
        case .task: return store.task(id: ref.id)
        case .procedure: return store.data.procedures.first { $0.id == ref.id }
        case .step: return store.step(id: ref.id)?.step
        }
    }

    /// `DeadlineOf`: task / procedure / step deadline.
    public static func deadline(of job: any SchedulableJob) -> NetDateTime? {
        switch job {
        case let t as TaskItem: return t.deadline
        case let p as Procedure: return p.deadline
        case let s as ChecklistStep: return s.deadline
        default: return nil
        }
    }

    /// `RangeStartOf`: tasks only.
    public static func rangeStart(of job: any SchedulableJob) -> NetDateTime? { (job as? TaskItem)?.rangeStart }

    /// `WhenOf = ScheduledStart ?? Deadline`.
    public static func when(of job: any SchedulableJob) -> NetDateTime? { job.scheduledStart ?? deadline(of: job) }

    /// DECISIONS 07 Q-06: every completed item greys (task IsComplete, procedure Done, step Done). Windows greyed
    /// only completed tasks (W-08).
    public static func isDone(_ job: any SchedulableJob) -> Bool {
        switch job {
        case let t as TaskItem: return t.isComplete
        case let p as Procedure: return p.status == .done
        case let s as ChecklistStep: return s.done
        default: return false
        }
    }

    /// VIEW-086 `DueSpan`: end = Deadline.Date; start = RangeStart.Date for a task whose range start is on or
    /// before the end, else the end. Procedures, steps and crew items are single-day points.
    public static func dueSpan(_ job: any SchedulableJob) -> (start: CivilDate, end: CivilDate)? {
        guard let d = deadline(of: job) else { return nil }
        let end = d.civilDate
        if let s = rangeStart(of: job), s.civilDate <= end { return (s.civilDate, end) }
        return (end, end)
    }

    // MARK: Pool (VIEW-084)

    /// Every job with neither ScheduledStart nor Deadline, filtered by the trimmed query (`JobName` contains,
    /// OrdinalIgnoreCase); done jobs stay; `AllJobs` order.
    public static func pool(store: AppStore, query: String) -> [PlannerPoolRow] {
        let q = NetText.trim(query)
        var out: [PlannerPoolRow] = []
        var used: [String: Int] = [:]
        for job in store.allJobs() where job.scheduledStart == nil && deadline(of: job) == nil {
            if !q.isEmpty && !NetText.containsIgnoreCase(job.jobName, q) { continue }
            let base = "pool-" + family(job).rawValue + "-" + job.id.netString
            let n = used[base, default: 0]
            used[base] = n + 1
            out.append(PlannerPoolRow(id: n == 0 ? base : base + "#\(n)", job: job, ref: ref(job),
                                      text: poolText(job), isDone: isDone(job)))
        }
        return out
    }

    /// `"{JobName}   ·   {DurFmt(DurationMinutes)}"` (3 spaces, U+00B7, 3 spaces).
    public static func poolText(_ job: any SchedulableJob) -> String {
        "\(job.jobName)   \u{00B7}   \(PlannerGeometry.durFmt(job.durationMinutes))"
    }

    // MARK: Placement (VIEW-085)

    /// `_placed`: every schedulable item with `ScheduledStart ?? Deadline`.
    public static func placed(_ data: AppData) -> [any SchedulableJob] {
        allSchedulable(data).filter { when(of: $0) != nil }
    }

    /// VIEW-091 `RangeGlyph`: single-day `"• "`; multi-day: deadline day `"⚑ "`, start day `"▸ "`, middle `"· "`.
    public static func rangeGlyph(_ job: any SchedulableJob, day: CivilDate) -> String {
        guard let span = dueSpan(job), span.start < span.end else { return "\u{2022} " }
        if day == span.end { return "\u{2691} " }
        if day == span.start { return "\u{25B8} " }
        return "\u{00B7} "
    }

    /// VIEW-099 `ChipTip`.
    public static func chipTooltip(_ job: any SchedulableJob) -> String {
        if let s = job.scheduledStart {
            return "\(job.jobName)\n\(s.format(.time)) (\(PlannerGeometry.durFmt(job.durationMinutes)))"
        }
        if let t = job as? TaskItem, let rs = t.rangeStart, let d = t.deadline, rs.civilDate < d.civilDate {
            let m = rs.civilDate.days(to: d.civilDate) + 1
            return "\(job.jobName)\n\(rs.format(.isoDate)) \u{2192} \(d.format(.isoDate))  (\(m) days)\n"
                + "Drag in Month to move the whole range \u{2022} double-click to edit"
        }
        let d = deadline(of: job)?.format(.isoDate) ?? ""
        return "\(job.jobName)\ndue \(d) (no time)\nDrag onto the grid to give it a time \u{2022} double-click to edit"
    }

    /// `JobEnd = ScheduledStart + max(15, Duration)` minutes.
    public static func jobEnd(_ job: any SchedulableJob) -> NetDateTime? {
        guard let s = job.scheduledStart else { return nil }
        return s.addingTicks(Int64(PlannerGeometry.layoutMinutes(job.durationMinutes)) * NetDateTime.ticksPerMinute)
    }

    /// VIEW-095 block tooltip.
    public static func blockTooltip(_ job: any SchedulableJob) -> String {
        guard let s = job.scheduledStart, let e = jobEnd(job) else { return job.jobName }
        return "\(job.jobName)\n\(s.format(.time))\u{2013}\(e.format(.time)) (\(PlannerGeometry.durFmt(job.durationMinutes)))\n"
            + "Drag to move \u{2022} double-click to edit"
    }

    /// VIEW-095 block subtitle: `"{HH:mm}–{HH:mm}  ({DurFmt})"`.
    public static func blockSubtitle(_ job: any SchedulableJob) -> String {
        guard let s = job.scheduledStart, let e = jobEnd(job) else { return "" }
        return "\(s.format(.time))\u{2013}\(e.format(.time))  (\(PlannerGeometry.durFmt(job.durationMinutes)))"
    }

    /// VIEW-095/096: the timed blocks of one day column.
    public static func blocks(_ placed: [any SchedulableJob], day: CivilDate, dayWidth: Double) -> [PlannerBlock] {
        let timed = CalendarRowBuilder.stableSorted(placed.filter { $0.scheduledStart?.civilDate == day }) {
            $0.scheduledStart!.ticks < $1.scheduledStart!.ticks
        }
        let intervals = timed.map { j -> PlannerInterval in
            let start = j.scheduledStart!.minutesOfDay
            return PlannerInterval(start: start, end: start + PlannerGeometry.layoutMinutes(j.durationMinutes))
        }
        let slots = PlannerGeometry.layoutDay(intervals, dayWidth: dayWidth)
        return slots.map { slot in
            let j = timed[slot.index]
            return PlannerBlock(id: "b-\(day.iso)-\(slot.index)-\(j.id.netString)", job: j, ref: ref(j), slot: slot,
                                title: j.jobName, subtitle: blockSubtitle(j), isDone: isDone(j),
                                tooltip: blockTooltip(j))
        }
    }

    /// VIEW-089/090: due-only chips whose span covers `day`, ordered by span start then `JobName`
    /// (OrdinalIgnoreCase); text = glyph + name; bold on the deadline day of a multi-day span; opacity 0.6 on the
    /// other days of the span.
    public static func allDayChips(_ placed: [any SchedulableJob], day: CivilDate) -> [PlannerChip] {
        let due = placed.compactMap { j -> (any SchedulableJob, CivilDate, CivilDate)? in
            guard j.scheduledStart == nil, let span = dueSpan(j), span.start <= day, day <= span.end else { return nil }
            return (j, span.start, span.end)
        }
        let sorted = CalendarRowBuilder.stableSorted(due) { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            return NetText.compareIgnoreCase(a.0.jobName, b.0.jobName) == .orderedAscending
        }
        return sorted.enumerated().map { k, e in
            let (j, start, end) = e
            let multi = start < end
            return PlannerChip(id: "a-\(day.iso)-\(k)-\(j.id.netString)", job: j, ref: ref(j, anchor: day),
                               text: rangeGlyph(j, day: day) + j.jobName, isTimed: false,
                               isBold: multi && day == end, opacity: multi && day != end ? 0.6 : 1.0,
                               isDone: isDone(j), tooltip: chipTooltip(j))
        }
    }

    /// VIEW-098: month-cell chips — timed items on that date first, then due-only items covering it; ordered timed
    /// first, then by ScheduledStart (due-only = MinValue), then `JobName` OrdinalIgnoreCase. Timed text
    /// `"{HH:mm} {JobName}"`; due-only `RangeGlyph + JobName`, bold on the deadline day of a multi-day span,
    /// opacity 0.55 on its other days.
    public static func monthChips(_ placed: [any SchedulableJob], day: CivilDate) -> [PlannerChip] {
        var entries: [(job: any SchedulableJob, timed: Bool, key: Int64)] = []
        for j in placed {
            if let s = j.scheduledStart {
                if s.civilDate == day { entries.append((j, true, s.ticks)) }
            } else if let span = dueSpan(j), span.start <= day, day <= span.end {
                entries.append((j, false, Int64.min))
            }
        }
        let sorted = CalendarRowBuilder.stableSorted(entries) { a, b in
            if a.timed != b.timed { return a.timed }
            if a.key != b.key { return a.key < b.key }
            return NetText.compareIgnoreCase(a.job.jobName, b.job.jobName) == .orderedAscending
        }
        return sorted.enumerated().map { k, e in
            let j = e.job
            if e.timed {
                return PlannerChip(id: "m-\(day.iso)-\(k)-\(j.id.netString)", job: j, ref: ref(j),
                                   text: "\(j.scheduledStart!.format(.time)) \(j.jobName)", isTimed: true,
                                   isBold: false, opacity: 1, isDone: isDone(j), tooltip: chipTooltip(j))
            }
            let span = dueSpan(j)!
            let multi = span.start < span.end
            return PlannerChip(id: "m-\(day.iso)-\(k)-\(j.id.netString)", job: j, ref: ref(j, anchor: day),
                               text: rangeGlyph(j, day: day) + j.jobName, isTimed: false,
                               isBold: multi && day == span.end, opacity: multi && day != span.end ? 0.55 : 1.0,
                               isDone: isDone(j), tooltip: chipTooltip(j))
        }
    }

    // MARK: Drops (VIEW-100…102, §4.3.7). The caller saves after every drop (VIEW-106).

    /// Hour canvas drop on `day` at pointer `y`: `ScheduledStart = day + snapped minutes`; a task WITH a range start
    /// has its window extended so the scheduled day is inside it. Values are Unspecified (DECISIONS Q-6).
    public static func dropOnHourGrid(_ job: any SchedulableJob, day: CivilDate, y: Double) {
        dropOnHourGrid(job, day: day, minutes: PlannerGeometry.snappedMinutes(y: y))
    }

    public static func dropOnHourGrid(_ job: any SchedulableJob, day: CivilDate, minutes: Int) {
        job.scheduledStart = NetDateTime.calendarDateTime(day, minutes: minutes)
        if let t = job as? TaskItem, let rs = t.rangeStart {
            if let d = t.deadline, day > d.civilDate { t.deadline = NetDateTime.calendarDate(day) }
            if day < rs.civilDate { t.rangeStart = NetDateTime.calendarDate(day) }
        }
    }

    /// Month cell drop: a timed job keeps its time on the new date; a task with both RangeStart and Deadline slides
    /// its whole window by `cell − anchor` (length kept; without an anchor the window ends on the cell); any other
    /// item (incl. a pool job) gets `Deadline = cell`.
    public static func dropOnMonthCell(_ job: any SchedulableJob, cell: CivilDate, anchor: CivilDate?) {
        if let s = job.scheduledStart {
            job.scheduledStart = NetDateTime.calendarDateTime(cell, minutes: s.minutesOfDay)
            return
        }
        if let t = job as? TaskItem, let rs = t.rangeStart, let d = t.deadline {
            if let anchor {
                let delta = anchor.days(to: cell)
                t.rangeStart = NetDateTime.calendarDate(rs.civilDate.addingDays(delta))
                t.deadline = NetDateTime.calendarDate(d.civilDate.addingDays(delta))
            } else {
                let length = rs.civilDate.days(to: d.civilDate)
                t.deadline = NetDateTime.calendarDate(cell)
                t.rangeStart = NetDateTime.calendarDate(cell.addingDays(-length))
            }
            return
        }
        setDeadline(job, NetDateTime.calendarDate(cell))
    }

    /// Unscheduled list drop: `ScheduledStart = null` (a dated item returns to the due strip, not the pool).
    public static func dropOnPool(_ job: any SchedulableJob) {
        job.scheduledStart = nil
    }

    /// `SetDeadlineOf` (task / procedure / step).
    static func setDeadline(_ job: any SchedulableJob, _ d: NetDateTime?) {
        switch job {
        case let t as TaskItem: t.deadline = d
        case let p as Procedure: p.deadline = d
        case let s as ChecklistStep: s.deadline = d
        default: break
        }
    }

    // MARK: Editors (VIEW-104, DECISIONS 07 Q-07)

    public enum EditorTarget: Sendable, Equatable {
        case task(UUID), step(UUID), navigate(UUID)
    }

    /// TaskItem → the subtask editor; ChecklistStep → the checklist step editor; Procedure → navigate to it
    /// (DECISIONS 07 Q-07; Windows opened nothing).
    public static func editorTarget(_ job: any SchedulableJob) -> EditorTarget {
        switch job {
        case let t as TaskItem: return .task(t.id)
        case let p as Procedure: return .navigate(p.id)
        default: return .step(job.id)
        }
    }
}
