// Spec: 12 SIRE-031…035, SIRE-046/047, §3.7 (SireToAa: CreateItem, AttachChildTasks, AddQuestionChild,
//       SpawnTopLevelTasks, AddGroup, Truncate, body XAML), §6.10 (build the objects first, insert them in one batch,
//       observation fires once), §7.11 vectors; 02 REPO-030 (cross-linking caller: AddRelation two-way, Equipment
//       TaskIds, `Added` log of the parent only).
import Foundation

/// The AA item kind a quick-add creates (`SireToAa.Kind`; raw values are the C# enum names used in summaries).
public enum SireAddKind: String, Sendable, CaseIterable, Hashable {
    case procedure = "Procedure", task = "Task", equipment = "Equipment"

    /// Picker label (`Equipment / Area` for equipment, SIRE-034).
    public var pickerLabel: String { self == .equipment ? "Equipment / Area" : rawValue }

    /// SIRE-034 smart default from `TagExtractor.DominantCategory`.
    public static func fromDominantCategory(_ c: String) -> SireAddKind {
        c == "Equipment" ? .equipment : c == "Procedure" ? .procedure : .task
    }
}

/// `SireToAa.Result`.
public struct SireAddResult {
    public let itemsCreated: Int
    public let tasksCreated: Int
    public let primary: HierarchyItem?
    public let summary: String
}

/// The quick-add bridge into Equipment / Task / Procedure.
@MainActor
public enum SireToAa {
    /// `AddQuestion(repo, q, kind, createTopLevelTasks)`.
    public static func addQuestion(_ q: SireQuestion, kind: SireAddKind, identified: SireIdentifiedTasks, store: AppStore,
                                   createTopLevelTasks: Bool = true) -> SireAddResult {
        let parent = makeItem(kind, name: "SIRE Q\(q.questionNumber) — \(q.shortQuestionText)",
                              bodyXaml: SireFlowXaml.questionXaml(q))
        let tasks = identified.tasks(for: q.questionNumber)
        attachChildTasks(parent, tasks)
        var spawned: [TaskItem] = []
        if createTopLevelTasks { spawned = spawnTopLevelTasks(parent, q, tasks, store: store) }
        insert(parent, spawned, store: store)
        store.logAdded(kind: AppStore.kindLabel(parent.kind), name: parent.name, detail: "from SIRE Q\(q.questionNumber)")
        let n = spawned.count
        return SireAddResult(itemsCreated: 1, tasksCreated: n, primary: parent,
                             summary: "Added “\(parent.name)” as \(kind.rawValue)" + (n > 0 ? " with \(n) linked task(s)." : "."))
    }

    /// `AddSection(repo, section, …)` → parent `SIRE Section {section}`.
    public static func addSection(_ section: String, kind: SireAddKind, bank: SireBankContents, store: AppStore,
                                  createTopLevelTasks: Bool = true) -> SireAddResult {
        addGroup(bank.inSection(section), kind: kind, identified: bank.identified, store: store,
                 createTopLevelTasks: createTopLevelTasks, parentName: "SIRE Section \(section)")
    }

    /// `AddChapter(repo, chapter, …)` → parent `SIRE Ch{chapter} — {chapterName}` (or `SIRE Ch{chapter}`).
    public static func addChapter(_ chapter: String, kind: SireAddKind, bank: SireBankContents, store: AppStore,
                                  createTopLevelTasks: Bool = true) -> SireAddResult {
        let qs = bank.inChapter(chapter)
        let name = qs.isEmpty ? "SIRE Ch\(chapter)" : "SIRE Ch\(chapter) — \(qs[0].chapterName)"
        return addGroup(qs, kind: kind, identified: bank.identified, store: store,
                        createTopLevelTasks: createTopLevelTasks, parentName: name)
    }

    /// `AddGroup`.
    public static func addGroup(_ qs: [SireQuestion], kind: SireAddKind, identified: SireIdentifiedTasks, store: AppStore,
                                createTopLevelTasks: Bool, parentName: String) -> SireAddResult {
        if qs.isEmpty { return SireAddResult(itemsCreated: 0, tasksCreated: 0, primary: nil,
                                             summary: "No questions found for that selection.") }
        let parent = makeItem(kind, name: parentName, bodyXaml: SireFlowXaml.overviewXaml(title: parentName, questions: qs))
        var spawned: [TaskItem] = []
        for q in qs {
            addQuestionChild(parent, q)
            if createTopLevelTasks {
                spawned += spawnTopLevelTasks(parent, q, identified.tasks(for: q.questionNumber), store: store)
            }
        }
        insert(parent, spawned, store: store)
        store.logAdded(kind: AppStore.kindLabel(parent.kind), name: parent.name, detail: "from SIRE (\(qs.count) questions)")
        let n = spawned.count
        return SireAddResult(itemsCreated: 1, tasksCreated: n, primary: parent,
                             summary: "Added “\(parent.name)” as \(kind.rawValue) with \(qs.count) question(s)"
                                + (n > 0 ? " and \(n) linked task(s)." : "."))
    }

    // MARK: Item creation

    /// `CreateItem` without the append (the caller inserts in one batch): name, body XAML, tag "SIRE", defaults.
    static func makeItem(_ kind: SireAddKind, name: String, bodyXaml: String) -> HierarchyItem {
        let item: HierarchyItem
        switch kind {
        case .procedure: item = Procedure(name: name)
        case .task: item = TaskItem(name: name)
        case .equipment: item = Equipment(name: name)
        }
        item.container.richTextXaml = bodyXaml
        item.tags.append("SIRE")
        return item
    }

    /// Appends the parent to its collection, then the spawned tasks — one mutation per collection.
    static func insert(_ parent: HierarchyItem, _ spawned: [TaskItem], store: AppStore) {
        switch parent {
        case let e as Equipment: store.data.equipment.append(e)
        case let p as Procedure: store.data.procedures.append(p)
        case let t as TaskItem:
            store.data.tasks.append(contentsOf: [t] + spawned)
            return
        default: break
        }
        if !spawned.isEmpty { store.data.tasks.append(contentsOf: spawned) }
    }

    /// `AttachChildTasks`: Procedure → steps, Task → subtasks, Equipment → components (Name truncated to 80).
    static func attachChildTasks(_ parent: HierarchyItem, _ tasks: [String]) {
        switch parent {
        case let p as Procedure: p.steps.append(contentsOf: tasks.map { ChecklistStep(title: $0) })
        case let t as TaskItem: t.subtasks.append(contentsOf: tasks.map { TaskItem(name: $0) })
        case let e as Equipment: e.components.append(contentsOf: tasks.map { Component(name: truncate($0, 80), notes: $0) })
        default: break
        }
    }

    /// `AddQuestionChild`: the whole question as one child with its own body.
    static func addQuestionChild(_ parent: HierarchyItem, _ q: SireQuestion) {
        let title = "Q\(q.questionNumber) — \(q.shortQuestionText)"
        let body = SireFlowXaml.questionXaml(q)
        switch parent {
        case let p as Procedure:
            let step = ChecklistStep(title: title)
            step.container.richTextXaml = body
            p.steps.append(step)
        case let t as TaskItem:
            let sub = TaskItem(name: title)
            sub.container.richTextXaml = body
            t.subtasks.append(sub)
        case let e as Equipment:
            let c = Component(name: truncate(title, 90), notes: q.fullQuestionText)
            c.container.richTextXaml = body
            e.components.append(c)
        default: break
        }
    }

    /// `SpawnTopLevelTasks`: one tagged Task per identified task, related both ways; Equipment also lists it in
    /// `TaskIds`.
    static func spawnTopLevelTasks(_ parent: HierarchyItem, _ q: SireQuestion, _ identified: [String],
                                   store: AppStore) -> [TaskItem] {
        var out: [TaskItem] = []
        for text in identified {
            let task = TaskItem(name: text)
            task.tags.append("SIRE")
            task.description = "SIRE Q\(q.questionNumber) — \(q.shortQuestionText)"
            store.addRelation(parent, task)
            if let eq = parent as? Equipment, !eq.taskIds.contains(task.id) { eq.taskIds.append(task.id) }
            out.append(task)
        }
        return out
    }

    /// `Truncate(s, max)`: UTF-16 length; `s[..max].TrimEnd() + "…"`, never splitting a surrogate pair.
    public nonisolated static func truncate(_ s: String, _ max: Int) -> String {
        let u = Array(s.utf16)
        if u.count <= max { return s }
        var cut = max
        if cut > 0, UTF16.isLeadSurrogate(u[cut - 1]) { cut -= 1 }
        return SireText.string(SireText.trimEnd(Array(u[..<cut]))) + "…"
    }
}
