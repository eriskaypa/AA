// Spec: 12 SIRE-036/037, §3.10 (SireExport.Build — exact text layout of all 16 modes), §3.11 (GetStatus /
//       CountByStatus over the raw stored strings), §4.5 (UTF-8 without BOM, default file name), Q-3 (Selected
//       Questions = the Mac multi-selection), Q-12 (LF line endings), Q-14 (fixed `:` and Gregorian en_US_POSIX),
//       §7.10 goldens.
import Foundation

/// A value snapshot of `SireState` (built on the main actor) so exports and filters run as pure functions.
public struct SireSessionSnapshot: Sendable {
    public struct Entry: Sendable, Hashable {
        public var questionNumber: String
        public var text: String
        public var isCompleted: Bool
        public var createdAt: NetDateTime
        public init(questionNumber: String, text: String, isCompleted: Bool, createdAt: NetDateTime) {
            self.questionNumber = questionNumber; self.text = text; self.isCompleted = isCompleted; self.createdAt = createdAt
        }
    }

    /// Raw `QuestionStatuses` pairs in stored order.
    public var statuses: [(key: String, value: String)]
    public var bookmarks: [String]
    public var forExport: [String]
    public var tasks: [Entry]
    private var statusIndex: [Ordinal.Key: String]
    private var taskIndex: [Ordinal.Key: [Int]]
    private var bookmarkSet: Set<Ordinal.Key>
    private var exportSet: Set<Ordinal.Key>

    public init(statuses: [(String, String)] = [], bookmarks: [String] = [], forExport: [String] = [], tasks: [Entry] = []) {
        self.statuses = statuses.map { (key: $0.0, value: $0.1) }
        self.bookmarks = bookmarks; self.forExport = forExport; self.tasks = tasks
        var si: [Ordinal.Key: String] = [:]
        for (k, v) in statuses { si[Ordinal.Key(k)] = v }
        statusIndex = si
        var ti: [Ordinal.Key: [Int]] = [:]
        for (i, t) in tasks.enumerated() { ti[Ordinal.Key(t.questionNumber), default: []].append(i) }
        taskIndex = ti
        bookmarkSet = Set(bookmarks.map(Ordinal.Key.init))
        exportSet = Set(forExport.map(Ordinal.Key.init))
    }

    @MainActor public init(_ s: SireState) {
        self.init(statuses: s.questionStatuses.pairs.map { ($0.key, $0.value) }, bookmarks: s.bookmarks,
                  forExport: s.forExport,
                  tasks: s.tasks.map { Entry(questionNumber: $0.questionNumber, text: $0.text, isCompleted: $0.isCompleted,
                                            createdAt: $0.createdAt) })
    }

    public func status(_ q: String) -> SireQuestionStatus { SireQuestionStatus.parse(statusIndex[Ordinal.Key(q)]) }
    public func count(of s: SireQuestionStatus) -> Int { statuses.filter { Ordinal.equals($0.value, s.rawValue) }.count }
    public func isBookmarked(_ q: String) -> Bool { bookmarkSet.contains(Ordinal.Key(q)) }
    public func isForExport(_ q: String) -> Bool { exportSet.contains(Ordinal.Key(q)) }
    public func tasks(for q: String) -> [Entry] { (taskIndex[Ordinal.Key(q)] ?? []).map { tasks[$0] } }
    public func hasTasks(_ q: String) -> Bool { taskIndex[Ordinal.Key(q)] != nil }
    public var completedTaskCount: Int { tasks.filter(\.isCompleted).count }
}

/// The 16 text export modes (SireExport.cs).
public enum SireExport {
    public static let modes = [
        "All Tasks", "Completed Tasks", "Pending Tasks", "Questions with Tasks",
        "Selected Questions", "For Export Tagged", "Bookmarked Questions", "Current Filter Results",
        "By Chapter", "By ROVIQ Location", "By Status", "By Vessel Type",
        "Print Checklist", "Inspection Summary", "Full Session Report", "Identified Tasks",
    ]
    public static let defaultMode = "Print Checklist"

    static let rule = String(repeating: "=", count: 60)

    /// `QuestionStatus.ToString()` names (`InProgress`, `NotApplicable`, …).
    static func enumName(_ s: SireQuestionStatus) -> String { s.rawValue }

    /// `StatusDisplay` ("In Progress" / "Checked" / "N/A" / "").
    public static func statusDisplay(_ s: SireQuestionStatus) -> String {
        switch s {
        case .inProgress: return "In Progress"
        case .checked: return "Checked"
        case .notApplicable: return "N/A"
        case .none: return ""
        }
    }

    static func mark(_ t: SireSessionSnapshot.Entry) -> String { t.isCompleted ? "[x]" : "[ ]" }

    /// `yyyy-MM-dd HH:mm` (Gregorian, en_US_POSIX, the given zone — Q-14).
    public static func stamp(_ now: Date, zone: TimeZone, format: String = "yyyy-MM-dd HH:mm") -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = format
        return f.string(from: now)
    }

    /// `SIRE_{mode with ' '→'_'}_{yyyyMMdd_HHmm}.txt`.
    public static func defaultFileName(mode: String, now: Date, zone: TimeZone = .current) -> String {
        "SIRE_\(mode.replacingOccurrences(of: " ", with: "_"))_\(stamp(now, zone: zone, format: "yyyyMMdd_HHmm")).txt"
    }

    /// `SireExport.Build(mode, all, state, identified, filtered)` with LF line endings. `selected` is the Mac
    /// multi-selection (Q-3); `filtered` is the on-screen list in its sort order.
    public static func build(mode: String, all: [SireQuestion], session: SireSessionSnapshot,
                             identified: SireIdentifiedTasks, filtered: [SireQuestion], selected: Set<String> = [],
                             now: Date = Date(), zone: TimeZone = .current) -> String {
        var w = Lines()
        w.add(rule)
        w.add("  SIRE 2.0 Knowledge Bank Export — \(mode)")
        w.add("  Generated: \(stamp(now, zone: zone))")
        w.add(rule)
        w.add()
        let byNumber = { (qs: [SireQuestion]) in SireOrder.sortedByNumber(qs) }
        switch mode {
        case "All Tasks": allTasks(&w, all, session)
        case "Completed Tasks": tasksByCompletion(&w, all, session, completed: true)
        case "Pending Tasks": tasksByCompletion(&w, all, session, completed: false)
        case "Questions with Tasks": questionsWithTasks(&w, all, session)
        case "Selected Questions":
            let keys = Set(selected.map(Ordinal.Key.init))
            questionList(&w, byNumber(all.filter { keys.contains(Ordinal.Key($0.questionNumber)) }), "Selected Questions", session)
        case "For Export Tagged":
            questionList(&w, byNumber(all.filter { session.isForExport($0.questionNumber) }), "Questions Tagged for Export", session)
        case "Bookmarked Questions":
            questionList(&w, byNumber(all.filter { session.isBookmarked($0.questionNumber) }), "Bookmarked Questions", session)
        case "Current Filter Results": questionList(&w, filtered, "Current Filter Results", session)
        case "By Chapter": byChapter(&w, all, session)
        case "By ROVIQ Location": byKey(&w, all) { $0.roviqLocations }
        case "By Status": byStatus(&w, all, session)
        case "By Vessel Type": byKey(&w, all) { $0.vesselTypes }
        case "Print Checklist": printChecklist(&w, all, session)
        case "Inspection Summary": inspectionSummary(&w, all, session)
        case "Full Session Report": fullReport(&w, all, session)
        case "Identified Tasks": identifiedTasks(&w, all, identified)
        default: break
        }
        w.add()
        w.add(rule)
        w.add("  Generated by AA — SIRE 2.0 Knowledge Bank")
        w.add(rule)
        return w.text
    }

    /// `AppendLine` with `\n` (Q-12).
    struct Lines {
        var text = ""
        mutating func add(_ s: String = "") { text += s; text += "\n" }
    }

    static func shortText(_ all: [SireQuestion], _ number: String) -> String {
        all.first { Ordinal.equals($0.questionNumber, number) }?.shortQuestionText ?? ""
    }

    /// `GroupBy(QuestionNumber)` (first appearance) then `OrderBy(Key, QC)`.
    static func groupedByQuestion(_ tasks: [SireSessionSnapshot.Entry]) -> [(key: String, tasks: [SireSessionSnapshot.Entry])] {
        var order: [String] = []
        var groups: [Ordinal.Key: [SireSessionSnapshot.Entry]] = [:]
        for t in tasks {
            let k = Ordinal.Key(t.questionNumber)
            if groups[k] == nil { order.append(t.questionNumber); groups[k] = [] }
            groups[k]!.append(t)
        }
        let pairs = order.map { (key: $0, tasks: groups[Ordinal.Key($0)] ?? []) }
        return SireOrder.stableSorted(pairs) { SireOrder.compareNumbers($0.key, $1.key) }
    }

    static func taskGroups(_ w: inout Lines, _ all: [SireQuestion], _ tasks: [SireSessionSnapshot.Entry]) {
        for g in groupedByQuestion(tasks) {
            w.add("Q \(g.key) — \(shortText(all, g.key))")
            for t in SireOrder.stableSorted(g.tasks, by: { $0.createdAt < $1.createdAt }) { w.add("  \(mark(t)) \(t.text)") }
            w.add()
        }
    }

    static func allTasks(_ w: inout Lines, _ all: [SireQuestion], _ s: SireSessionSnapshot) {
        if s.tasks.isEmpty { w.add("  No tasks found."); return }
        taskGroups(&w, all, s.tasks)
    }

    static func tasksByCompletion(_ w: inout Lines, _ all: [SireQuestion], _ s: SireSessionSnapshot, completed: Bool) {
        let tasks = s.tasks.filter { $0.isCompleted == completed }
        if tasks.isEmpty { w.add("  No \(completed ? "completed" : "pending") tasks found."); return }
        w.add("  \(completed ? "Completed" : "Pending") Tasks: \(tasks.count)"); w.add()
        taskGroups(&w, all, tasks)
    }

    static func questionsWithTasks(_ w: inout Lines, _ all: [SireQuestion], _ s: SireSessionSnapshot) {
        let qs = SireOrder.sortedByNumber(all.filter { s.hasTasks($0.questionNumber) })
        w.add("  Questions with Tasks: \(qs.count)"); w.add()
        for q in qs {
            w.add("Q \(q.questionNumber) — \(q.shortQuestionText)")
            for t in s.tasks(for: q.questionNumber) { w.add("  \(mark(t)) \(t.text)") }
            w.add()
        }
    }

    static func questionList(_ w: inout Lines, _ qs: [SireQuestion], _ title: String, _ s: SireSessionSnapshot) {
        w.add("  \(title): \(qs.count) questions"); w.add()
        for q in qs {
            w.add("Q \(q.questionNumber) [\(q.questionTypeDisplay)]")
            w.add("  \(q.shortQuestionText)")
            if !q.fullQuestionText.isEmpty { w.add("  Full: \(q.fullQuestionText)") }
            w.add("  Vessel: \(q.vesselTypesDisplay) | Chapter: \(q.chapterDisplay)")
            if !q.roviqSequence.isEmpty { w.add("  ROVIQ: \(q.roviqSequence)") }
            let st = s.status(q.questionNumber)
            if st != .none { w.add("  Status: \(statusDisplay(st))") }
            for t in s.tasks(for: q.questionNumber) { w.add("  \(mark(t)) \(t.text)") }
            w.add()
        }
    }

    static func byChapter(_ w: inout Lines, _ all: [SireQuestion], _ s: SireSessionSnapshot) {
        var order: [String] = []
        var groups: [Ordinal.Key: [SireQuestion]] = [:]
        for q in all {
            let k = Ordinal.Key(q.chapterDisplay)
            if groups[k] == nil { order.append(q.chapterDisplay); groups[k] = [] }
            groups[k]!.append(q)
        }
        let pairs = order.map { (key: $0, qs: groups[Ordinal.Key($0)] ?? []) }
        for g in SireOrder.stableSorted(pairs, by: {
            SireOrder.chapterRank($0.qs.first?.chapter ?? "") < SireOrder.chapterRank($1.qs.first?.chapter ?? "")
        }) {
            w.add("--- \(g.key) (\(g.qs.count) questions) ---")
            for q in SireOrder.sortedByNumber(g.qs) {
                let st = s.status(q.questionNumber)
                let tag = st != .none ? " [\(enumName(st))]" : ""
                w.add("  Q \(q.questionNumber)\(tag) — \(q.shortQuestionText)")
            }
            w.add()
        }
    }

    /// `By ROVIQ Location` / `By Vessel Type`: case-insensitive keys (first casing kept), culture-ordered.
    static func byKey(_ w: inout Lines, _ all: [SireQuestion], _ keys: (SireQuestion) -> [String]) {
        var order: [String] = []
        var map: [String: [SireQuestion]] = [:]
        for q in all {
            for k in keys(q) {
                let folded = NetText.toUpperInvariant(k)
                if map[folded] == nil { order.append(k); map[folded] = [] }
                map[folded]!.append(q)
            }
        }
        for k in SireOrder.sortedCulture(order) {
            let qs = map[NetText.toUpperInvariant(k)] ?? []
            w.add("--- \(k) (\(qs.count) questions) ---")
            for q in SireOrder.sortedByNumber(qs) { w.add("  Q \(q.questionNumber) — \(q.shortQuestionText)") }
            w.add()
        }
    }

    static func byStatus(_ w: inout Lines, _ all: [SireQuestion], _ s: SireSessionSnapshot) {
        for st in [SireQuestionStatus.checked, .inProgress, .notApplicable, .none] {
            let qs = SireOrder.sortedByNumber(all.filter { s.status($0.questionNumber) == st })
            let label = st == .none ? "Not Started" : enumName(st)
            w.add("--- \(label) (\(qs.count)) ---")
            for q in qs { w.add("  Q \(q.questionNumber) — \(q.shortQuestionText)") }
            w.add()
        }
    }

    static func printChecklist(_ w: inout Lines, _ all: [SireQuestion], _ s: SireSessionSnapshot) {
        w.add("  INSPECTION CHECKLIST")
        w.add("  Total questions: \(all.count)"); w.add()
        for q in SireOrder.sortedByNumber(all) {
            let mark: String
            switch s.status(q.questionNumber) {
            case .checked: mark = "[x]"
            case .inProgress: mark = "[~]"
            case .notApplicable: mark = "[N/A]"
            case .none: mark = "[ ]"
            }
            w.add("\(mark) Q \(q.questionNumber) — \(q.shortQuestionText)")
            for t in s.tasks(for: q.questionNumber) { w.add("      \(Self.mark(t)) \(t.text)") }
        }
    }

    static func inspectionSummary(_ w: inout Lines, _ all: [SireQuestion], _ s: SireSessionSnapshot) {
        let qs = s.statuses.isEmpty ? SireOrder.sortedByNumber(all)
                                    : SireOrder.sortedByNumber(all.filter { s.status($0.questionNumber) != .none })
        w.add("  Inspection Summary: \(qs.count) questions"); w.add()
        for q in qs {
            w.add("--- Q \(q.questionNumber) [\(enumName(s.status(q.questionNumber)))] ---")
            w.add("  \(q.shortQuestionText)")
            if !q.fullQuestionText.isEmpty { w.add("  \(q.fullQuestionText)") }
            w.add("  Vessel: \(q.vesselTypesDisplay) | Chapter: \(q.chapterDisplay)")
            if !q.objective.isEmpty { w.add("  Objective: \(q.objective)") }
            if !q.expectedEvidence.isEmpty { w.add("  Evidence: \(q.expectedEvidence)") }
            if !q.potentialNegativeObservationGrounds.isEmpty { w.add("  Neg. Obs. Grounds: \(q.potentialNegativeObservationGrounds)") }
            let tasks = s.tasks(for: q.questionNumber)
            if !tasks.isEmpty {
                w.add("  Tasks:")
                for t in tasks { w.add("    \(mark(t)) \(t.text)") }
            }
            w.add()
        }
    }

    static func fullReport(_ w: inout Lines, _ all: [SireQuestion], _ s: SireSessionSnapshot) {
        w.add("-- PROGRESS SUMMARY --")
        w.add("  Checked:        \(s.count(of: .checked))")
        w.add("  In Progress:    \(s.count(of: .inProgress))")
        w.add("  Not Applicable: \(s.count(of: .notApplicable))")
        w.add("  Not Started:    \(all.count - s.statuses.count)")
        w.add("  Bookmarked:     \(s.bookmarks.count)")
        w.add("  For Export:     \(s.forExport.count)")
        w.add("  Total Tasks:    \(s.tasks.count) (\(s.completedTaskCount) completed)")
        w.add()
        byStatus(&w, all, s)
        w.add("-- ALL TASKS --"); w.add()
        allTasks(&w, all, s)
    }

    static func identifiedTasks(_ w: inout Lines, _ all: [SireQuestion], _ identified: SireIdentifiedTasks) {
        if identified.isEmpty { w.add("  No identified tasks available."); return }
        w.add("  Identified Tasks: \(identified.totalTasks) tasks across \(identified.count) questions")
        w.add("  (Pre-identified from question guidance text — no AI required)"); w.add()
        var order: [String] = []
        var groups: [Ordinal.Key: [(key: String, tasks: [String], q: SireQuestion)]] = [:]
        for p in identified.pairs {
            guard let q = all.first(where: { Ordinal.equals($0.questionNumber, p.key) }) else { continue }
            let k = Ordinal.Key(q.chapterDisplay)
            if groups[k] == nil { order.append(q.chapterDisplay); groups[k] = [] }
            groups[k]!.append((p.key, p.tasks, q))
        }
        let chapters = order.map { (title: $0, items: groups[Ordinal.Key($0)] ?? []) }
        for c in SireOrder.stableSorted(chapters, by: {
            SireOrder.chapterRank($0.items.first?.q.chapter ?? "") < SireOrder.chapterRank($1.items.first?.q.chapter ?? "")
        }) {
            w.add("-- \(c.title) --"); w.add()
            for item in SireOrder.stableSorted(c.items, compare: { SireOrder.compareNumbers($0.key, $1.key) }) {
                w.add("  Q \(item.key) — \(item.q.shortQuestionText)")
                for t in item.tasks { w.add("    [ ] \(t)") }
                w.add()
            }
        }
    }

    /// The file bytes: UTF-8 without BOM (§4.5).
    public static func fileData(_ text: String) -> Data { Data(text.utf8) }
}
