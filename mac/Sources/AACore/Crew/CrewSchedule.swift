// Spec: 06 §I BUILD-110…125 (crew schedule builder), BUILD-A15 (NormTime), BUILD-A16 (timeline grouping), §4.5
//       (.aasched.json via F2's ScheduleService), §6.5, §7.2, §7.9; 09 §H CREW-080…086, §3.11, §7.14; 02 REPO-155;
//       DECISIONS 06 ("log the unlogged actions": schedule add / delete / apply get additive log entries).
import Foundation

/// `NormTime`, BUILD-A15.
public enum CrewScheduleTime {
    /// Trim; `^([0-9]{1,2}):([0-9]{2})$` → hour zero-padded to two digits + `:` + minutes; anything else → `""`.
    /// No range check (`25:99` stays). ASCII digits only (06 D6: Windows crashed on other digits).
    public static func normalize(_ s: String) -> String {
        let u = Array(NetText.trim(s).utf16)
        guard let colon = u.firstIndex(of: 0x3A) else { return "" }
        let h = u[..<colon], m = u[(colon + 1)...]
        guard (1...2).contains(h.count), m.count == 2,
              h.allSatisfy(CrewDateResolver.isDigit), m.allSatisfy(CrewDateResolver.isDigit) else { return "" }
        let hour = CrewDateResolver.int(h)
        return CivilDate.pad(hour, 2) + ":" + String(decoding: m, as: UTF16.self)
    }
}

/// One timeline group (BUILD-116).
public struct CrewScheduleGroup: Sendable, Equatable, Identifiable {
    public var label: String
    /// `yyyy-MM-dd` of the parsed date, or U+FFFF for undated entries.
    public var sortKey: String
    public var entryIDs: [UUID]
    public var id: String { sortKey }

    public var count: Int { entryIDs.count }

    public init(label: String, sortKey: String, entryIDs: [UUID]) {
        self.label = label; self.sortKey = sortKey; self.entryIDs = entryIDs
    }
}

public enum CrewScheduleTimeline {
    public static let noDate = "(no date)"

    /// BUILD-A16: sorted by date key (undated last) then by time (`""` sorts as `00:00`), stable; grouped by label in
    /// first-appearance order. `locale` supplies the weekday abbreviation (Gregorian calendar; tests pin en_US_POSIX).
    @MainActor public static func groups(_ entries: [ScheduleEntry], today: CivilDate,
                                         locale: Locale = .current) -> [CrewScheduleGroup] {
        struct Item { let id: UUID; let key: String; let time: String; let civil: CivilDate?; let offset: Int }
        let items = entries.enumerated().map { (k, e) -> Item in
            let civil = e.when?.civilDate
            return Item(id: e.id, key: civil?.iso ?? "\u{FFFF}", time: e.time.isEmpty ? "00:00" : e.time, civil: civil,
                        offset: k)
        }
        let sorted = items.sorted { a, b in
            if !Ordinal.equals(a.key, b.key) { return Ordinal.compare(a.key, b.key) == .orderedAscending }
            if !Ordinal.equals(a.time, b.time) { return Ordinal.compare(a.time, b.time) == .orderedAscending }
            return a.offset < b.offset
        }
        var out: [CrewScheduleGroup] = []
        var index: [String: Int] = [:]
        for it in sorted {
            let label = self.label(it.civil, today: today, locale: locale)
            if let k = index[label] {
                out[k].entryIDs.append(it.id)
            } else {
                index[label] = out.count
                out.append(CrewScheduleGroup(label: label, sortKey: it.key, entryIDs: [it.id]))
            }
        }
        return out
    }

    /// `(no date)` | `Today` | `Tomorrow` | `ddd, yyyy-MM-dd`.
    public static func label(_ d: CivilDate?, today: CivilDate, locale: Locale = .current) -> String {
        guard let d else { return noDate }
        if d == today { return "Today" }
        if d == today.addingDays(1) { return "Tomorrow" }
        return weekdayAbbrev(d, locale: locale) + ", " + d.iso
    }

    /// The abbreviated weekday name in `locale`, Gregorian calendar (DECISIONS 07 Q-09; 06 §6.5).
    public static func weekdayAbbrev(_ d: CivilDate, locale: Locale) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        let names = cal.shortWeekdaySymbols                     // Sunday first, matches CivilDate.weekday
        return names.indices.contains(d.weekday) ? names[d.weekday] : ""
    }

    /// `"🗓 {label}"` group header text (the count is shown muted beside it as `" ({count})"`).
    public static func header(_ g: CrewScheduleGroup) -> String { "\u{1F5D3} \(g.label)" }

    /// BUILD-120 count line.
    @MainActor public static func countLine(_ entries: [ScheduleEntry]) -> String {
        if entries.isEmpty { return "No entries yet — pick a date, choose what, and click \u{201C}+ Add\u{201D}." }
        let done = entries.filter(\.done).count
        return CrewScheduleText.entries(entries.count) + (done > 0 ? " \u{00B7} \(done) done" : "")
    }
}

/// Every user-visible string of the schedule builder (BUILD-111…124 / CREW-080…086).
public enum CrewScheduleText {
    /// `"{n} entry"` / `"{n} entries"`.
    public static func entries(_ n: Int) -> String { "\(n) entr" + (n == 1 ? "y" : "ies") }

    public static let linkedVessel = "Linked vessel:"
    public static let linkedVesselHelp = "Link this schedule to a vessel (optional)."
    public static let noVessel = "(none)"
    public static let saveAs = "Save as..."
    public static let saveAsHelp = "Save this schedule as a reusable one that can be applied to any crew."
    public static let applySaved = "Apply saved..."
    public static let applySavedHelp = "Apply a saved schedule to this crew member (append or replace)."
    public static let export = "Export..."
    public static let exportHelp = "Export this schedule to a file you can share/import elsewhere."
    public static let importTitle = "Import..."
    public static let importHelp = "Import a schedule file and apply it to this crew member."
    public static let add = "Add:"
    public static let timeHelp = "Time (HH:mm), optional."
    public static let timePlaceholder = "HH:mm"
    public static let titlePlaceholder = "What... (or pick an item)"
    public static let pickItem = "Pick item..."
    public static let pickItemHelp = "Pick an existing Task / Procedure / Equipment to schedule."
    public static let addButton = "+ Add"
    public static let editHelp = "Edit title/notes"
    public static let deleteHelp = "Delete this entry"

    /// Kind names (the enum names: `Note`, `Task`, `Procedure`, `Equipment`).
    public static func kindName(_ k: ScheduleKind) -> String { ScheduleKind.names[k.rawValue] ?? "Note" }
    public static let kinds: [ScheduleKind] = [.note, .task, .procedure, .equipment]

    public static let pickTitle = "Pick item"
    public static func noItems(_ k: ScheduleKind) -> String { "No \(kindName(k)) items exist yet to schedule." }
    public static func pickPrompt(_ k: ScheduleKind) -> String { "Pick a \(kindName(k)) to schedule" }

    public static let addEntryTitle = "Add entry"
    public static let addEntryEmpty = "Type what to schedule (or pick an item)."
    public static let editEntryTitle = "Edit entry"
    public static let editEntryPrompt = "Title:"

    public static let saveTitle = "Save schedule"
    public static let saveEmpty = "Add some entries first."
    public static let savePrompt = "Name for this reusable schedule:"
    public static func saved(_ name: String) -> String { "Saved '\(name)'. You can apply it to any crew member." }

    public static let applyTitle = "Apply schedule"
    public static let applyNone = "No saved schedules yet. Build one and click 'Save as...'."
    public static let applyPicker = "Apply a saved schedule"
    /// Always "entries" (BUILD-122). The Mac buttons are Replace / Append / Cancel; the legend lines are kept.
    public static func applyQuestion(name: String, count: Int, crew: String) -> String {
        "Apply '\(name)' (\(count) entries) to \(crew).\n\nYes = replace this crew's schedule\nNo = append\nCancel = nothing"
    }
    public static func applied(_ n: Int, crew: String) -> String { "Applied \(entries(n)) to \(crew)." }

    public static let exportEmptyTitle = "Export"
    public static let exportEmpty = "No schedule to export."
    public static let exportPanelTitle = "Export schedule"
    public static let exportDoneTitle = "Export complete"
    public static func exported(_ path: String) -> String { "Exported to:\n\(path)" }
    public static let exportFailedTitle = "Export failed"
    public static func exportFailed(_ msg: String) -> String { "Could not export:\n\n\(msg)" }

    public static let importPanelTitle = "Import schedule"
    public static let importFailedTitle = "Import failed"
    public static func importFailed(_ msg: String) -> String { "Could not import the schedule:\n\n\(msg)" }

    /// `Schedule-{Sanitize(FullName)}.aasched.json` (blank → `crew`).
    public static func exportFileName(fullName: String) -> String {
        "Schedule-\(WindowsFileName.sanitize(fullName, fallback: "crew")).aasched.json"
    }
}

/// The schedule operations (main actor; the caller persists with `Save()` / `MarkDirty()` as BUILD-115…124 say).
@MainActor public enum CrewScheduleOps {
    /// Items of a kind for "Pick item…": top-level Tasks / Procedures / Equipment, sorted by name (ordinal ignore-case,
    /// stable).
    public static func candidates(_ kind: ScheduleKind, data: AppData) -> [(id: UUID, name: String)] {
        let items: [HierarchyItem]
        switch kind {
        case .task: items = data.tasks
        case .procedure: items = data.procedures
        case .equipment: items = data.equipment
        default: items = []
        }
        return items.enumerated().sorted { a, b in
            let c = NetText.compareIgnoreCase(a.element.name, b.element.name)
            return c == .orderedSame ? a.offset < b.offset : c == .orderedAscending
        }.map { ($0.element.id, $0.element.name) }
    }

    /// BUILD-115: appends `{Title, Kind, RefId (nil for Note), Date, Time = NormTime}`; returns nil when the trimmed
    /// title is empty. Logs `Added / "Schedule entry" / title / crew` (DECISIONS 06, additive).
    @discardableResult
    public static func addEntry(to crew: CrewMember, title: String, kind: ScheduleKind, refID: UUID?, date: CivilDate?,
                                time: String, store: AppStore) -> ScheduleEntry? {
        let t = NetText.trim(title)
        if t.isEmpty { return nil }
        let e = ScheduleEntry(title: t, kind: kind, refId: kind == .note ? nil : refID, date: date?.iso ?? "",
                              time: CrewScheduleTime.normalize(time))
        crew.schedule.append(e)
        store.logAdded(kind: "Schedule entry", name: t, detail: crew.fullName)
        return e
    }

    /// BUILD-118: a non-blank prompt answer replaces the title (trimmed); returns whether it changed anything.
    @discardableResult public static func editTitle(_ e: ScheduleEntry, to text: String) -> Bool {
        if NetText.isBlank(text) { return false }
        e.title = NetText.trim(text)
        return true
    }

    /// BUILD-119: immediate removal, no confirmation. Logs `Removed / "Schedule entry" / title / crew` (additive).
    public static func deleteEntry(_ e: ScheduleEntry, from crew: CrewMember, store: AppStore) {
        guard let k = crew.schedule.firstIndex(where: { $0 === e }) else { return }
        crew.schedule.remove(at: k)
        store.logRemoved(kind: "Schedule entry", name: e.title, detail: crew.fullName)
    }

    /// BUILD-121: captures the crew schedule as a reusable template, appends it, logs
    /// `Added / "Schedule" / name / "{n} entr{y|ies}"`.
    @discardableResult
    public static func saveAsTemplate(_ crew: CrewMember, name: String, store: AppStore) -> ScheduleTemplate {
        let t = ScheduleService.captureFromCrew(name: name, crew: crew, data: store.data)
        store.data.scheduleTemplates.append(t)
        store.logAdded(kind: "Schedule", name: t.name, detail: CrewScheduleText.entries(t.entries.count))
        return t
    }

    /// BUILD-122: replace or append clones; a template vessel overwrites the crew's link. Logs
    /// `Added / "Schedule" / name / "{n} entr{y|ies} applied to {crew}"` (additive).
    @discardableResult
    public static func apply(_ t: ScheduleTemplate, to crew: CrewMember, replace: Bool, store: AppStore) -> Int {
        let n = ScheduleService.applyToCrew(t, crew: crew, replace: replace)
        store.logAdded(kind: "Schedule", name: t.name,
                       detail: "\(CrewScheduleText.entries(n)) applied to \(crew.fullName)" + (replace ? " (replaced)" : ""))
        return n
    }

    /// BUILD-124: parses a schedule file (fresh ids) and keeps it as a saved schedule.
    @discardableResult
    public static func importTemplate(_ data: Data, store: AppStore) throws -> ScheduleTemplate {
        let t = try ScheduleService.importJSON(data)
        store.data.scheduleTemplates.append(t)
        return t
    }

    /// BUILD-123: `{FullName} schedule` (trimmed) as `.aasched.json` bytes; does not add a saved template.
    public static func exportData(_ crew: CrewMember, store: AppStore) throws -> Data {
        let t = ScheduleService.captureFromCrew(name: crew.fullName + " schedule", crew: crew, data: store.data)
        return try ScheduleService.exportJSON(t)
    }

    /// BUILD-111: `(none)` then every vessel in data order (`(unnamed)` for blank names).
    public static func vesselChoices(_ data: AppData) -> [(id: UUID?, name: String)] {
        [(nil, CrewScheduleText.noVessel)] + data.vessels.map { (Optional($0.id), NetText.isBlank($0.name) ? CrewRoster.unnamed : $0.name) }
    }

    /// The combo selection: the linked vessel if it exists, else `(none)` (a dangling id stays stored).
    public static func selectedVessel(_ crew: CrewMember, data: AppData) -> UUID? {
        guard let v = crew.scheduleVesselId, data.vessels.contains(where: { $0.id == v }) else { return nil }
        return v
    }
}
