// Spec: 06 §B (BUILD-020…024 step editor), §E (BUILD-050…057 subtask / task editor), BUILD-A5 (duration),
//       BUILD-A6 / 02 REPO-050 (WorkRange coercion — the model's partner value is used, the fixed rule for long-lived
//       panes), 01 DATA-130 (Status ⇄ IsComplete sync lives in the model), DECISIONS Q-6 (edited calendar dates are
//       written Unspecified — the pickers already produce `.unspecified` midnights).
// Live field writes of the two editors: every change goes straight to the model and marks the store dirty; writes
// that change nothing are skipped (DECISIONS 02 Q-12: no no-op write-backs), so opening an editor never dirties data.
import Foundation

@MainActor public enum BuilderEditing {
    // MARK: Checklist step (BUILD-021, 022)

    public static func setTitle(_ store: AppStore, _ step: ChecklistStep, _ text: String) {
        guard step.title != text else { return }
        step.title = text
        store.markDirty()
    }

    /// Deadline set/cleared (no range for steps).
    public static func setDeadline(_ store: AppStore, _ step: ChecklistStep, _ date: NetDateTime?) {
        guard !sameDate(step.deadline, date) else { return }
        step.deadline = date
        store.markDirty()
    }

    public static func setDone(_ store: AppStore, _ step: ChecklistStep, _ done: Bool) {
        guard step.done != done else { return }
        step.done = done
        store.markDirty()
    }

    public static func setJob(_ store: AppStore, _ job: any SchedulableJob, _ isJob: Bool) {
        guard job.isJob != isJob else { return }
        job.isJob = isJob
        store.markDirty()
    }

    /// BUILD-022 / A5: valid (> 0) text updates `DurationMinutes`; anything else leaves the model unchanged.
    @discardableResult
    public static func setDuration(_ store: AppStore, _ job: any SchedulableJob, text: String) -> Bool {
        guard let m = BuilderDuration.parse(text) else { return false }
        if job.durationMinutes != m {
            job.durationMinutes = m
            store.markDirty()
        }
        return true
    }

    // MARK: Task / subtask (BUILD-051…056)

    public static func setName(_ store: AppStore, _ task: TaskItem, _ text: String) {
        guard task.name != text else { return }
        task.name = text
        store.markDirty()
    }

    public static func setDescription(_ store: AppStore, _ task: TaskItem, _ text: String) {
        guard task.description != text else { return }
        task.description = text
        store.markDirty()
    }

    /// BUILD-052: the deadline picker changed → `WorkRange.coerce(start: model start, deadline: new, editedStart: false)`.
    /// Clearing the deadline while a start exists refills the deadline with the start date.
    public static func setDeadline(_ store: AppStore, _ task: TaskItem, _ date: NetDateTime?) {
        let r = WorkRange.coerce(start: task.rangeStart, deadline: date, editedStart: false)
        apply(store, task, r)
    }

    /// BUILD-052: the start picker changed → `coerce(start: new, deadline: model deadline, editedStart: true)`.
    public static func setStart(_ store: AppStore, _ task: TaskItem, _ date: NetDateTime?) {
        let r = WorkRange.coerce(start: date, deadline: task.deadline, editedStart: true)
        apply(store, task, r)
    }

    /// BUILD-053 "Clear range": `RangeStart = null` (the deadline is kept).
    public static func clearRange(_ store: AppStore, _ task: TaskItem) {
        guard task.rangeStart != nil else { return }
        task.rangeStart = nil
        store.markDirty()
    }

    public static func setRecurrence(_ store: AppStore, _ task: TaskItem, _ r: RecurrenceKind) {
        guard task.recurrence != r else { return }
        task.recurrence = r
        store.markDirty()
    }

    /// BUILD-055: the model keeps `IsComplete` in sync (`Done` ⇔ complete).
    public static func setStatus(_ store: AppStore, _ task: TaskItem, _ s: WorkStatus) {
        guard task.status != s else { return }
        task.status = s
        store.markDirty()
    }

    /// BUILD-055: true ⇒ `Done`; false on a Done task ⇒ `Todo`; false on another status leaves it.
    public static func setComplete(_ store: AppStore, _ task: TaskItem, _ done: Bool) {
        guard task.isComplete != done else { return }
        task.isComplete = done
        store.markDirty()
    }

    /// The deadline picker's earliest day (BUILD-053: the deadline calendar starts at `RangeStart`).
    public static func deadlineEarliest(_ task: TaskItem) -> CivilDate? { task.rangeStart?.civilDate }

    /// The start picker's latest day (BUILD-053: the start calendar ends at `Deadline`).
    public static func startLatest(_ task: TaskItem) -> CivilDate? { task.deadline?.civilDate }

    // MARK: Internals

    static func apply(_ store: AppStore, _ task: TaskItem, _ r: (start: NetDateTime?, deadline: NetDateTime?)) {
        var changed = false
        if !sameDate(task.rangeStart, r.start) { task.rangeStart = r.start; changed = true }
        if !sameDate(task.deadline, r.deadline) { task.deadline = r.deadline; changed = true }
        if changed { store.markDirty() }
    }

    /// Same instant and kind (a re-picked identical date is not an edit; DECISIONS Q-6 keeps the original text).
    static func sameDate(_ a: NetDateTime?, _ b: NetDateTime?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return x.ticks == y.ticks && x.kind == y.kind
        default: return false
        }
    }
}
