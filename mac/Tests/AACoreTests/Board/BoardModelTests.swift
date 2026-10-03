// Tests for 07 §8.2 (B1…B13), VIEW-040…056, VIEW-202 / VIEW-214 (saved-list add, SL1 / SL3), 06 BUILD-101 vector,
// DECISIONS 02 Q-4 (Board deletes through the Trash, nested cards via trashSubtask), 07 Q-03 (logged creation),
// 03 T-KB-06 (⌘⌫ title on a focused column).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct BoardModelTests {
    typealias D = CalTestData

    @Test func columns() {
        // VIEW-041
        #expect(BoardModel.columns.map(\.title) == ["To Do", "In Progress", "Blocked", "Done"])
        #expect(BoardModel.columns.map(\.colorHex) == ["#546E7A", "#1E88E5", "#E53935", "#2E7D32"])
        #expect(BoardModel.columns.map(\.status.rawValue) == [0, 1, 2, 3])
    }

    @Test func metaOverdueAndRecurrence() {
        // TV: 07 B1, B2, B3, B4
        let t = D.task("t", deadline: "2026-09-20")
        t.recurrence = .weekly
        #expect(BoardModel.meta(t, today: D.today) == "Due 2026-09-20  \u{00B7}  OVERDUE   \u{00B7}   Weekly")
        // The card draws the same parts with OVERDUE as a chip (V-DESIGN rule 8).
        #expect(BoardModel.metaParts(t, today: D.today)
                == .init(dates: "Due 2026-09-20", overdue: true, recurrence: "Weekly"))
        #expect(BoardModel.isOverdue(t, today: D.today))
        t.status = .done
        #expect(BoardModel.meta(t, today: D.today) == "Due 2026-09-20   \u{00B7}   Weekly")
        #expect(!BoardModel.isOverdue(t, today: D.today) && t.isComplete)
        let r = D.task("r", start: "2026-09-25", deadline: "2026-10-02")
        #expect(BoardModel.meta(r, today: D.today) == "2026-09-25 \u{2192} 2026-10-02")
        let late = D.task("late", start: "2026-09-10", deadline: "2026-09-20")
        late.status = .inProgress
        #expect(BoardModel.meta(late, today: D.today) == "2026-09-10 \u{2192} 2026-09-20  \u{00B7}  OVERDUE")
        #expect(BoardModel.meta(TaskItem(name: "x"), today: D.today) == "")
    }

    @Test func badges() {
        // TV: 07 B5
        let t = TaskItem(name: "t")
        t.container.files = [FileItem(name: "a", path: "files/a")]
        let s1 = TaskItem(name: "1"); s1.isComplete = true
        t.subtasks = [s1, TaskItem(name: "2"), TaskItem(name: "3")]
        #expect(BoardModel.badges(t) == "\u{1F4CE} 1 file    \u{2611} 1/3")
        t.container.files.append(FileItem(name: "b", path: "files/b"))
        #expect(BoardModel.badges(t) == "\u{1F4CE} 2 files    \u{2611} 1/3")
        #expect(BoardModel.badges(TaskItem(name: "e")) == "")
    }

    @Test func parentPaths() {
        // TV: 07 B6, B7
        let a = TaskItem(name: "A"), blank = TaskItem(name: ""), c = TaskItem(name: "C")
        blank.subtasks = [c]
        a.subtasks = [blank]
        let cards = BoardModel.flatten(D.data(tasks: [a]))
        #expect(cards.map(\.task.name) == ["A", "", "C"])
        #expect(cards[0].parentLine == nil && !cards[0].isSubtask)
        #expect(cards[1].parentLine == "\u{21B3} A")
        #expect(cards[2].parentLine == "\u{21B3} A \u{203A} (unnamed)")
        #expect(BoardModel.cards(cards, in: .todo).count == 3)
    }

    @Test func searchAndHideDone() {
        // TV: 07 B11, VIEW-044, VIEW-045
        let pump = TaskItem(name: "Fuel pump overhaul")
        let done = TaskItem(name: "Pump log"); done.status = .done
        let other = TaskItem(name: "Galley")
        let cards = BoardModel.flatten(D.data(tasks: [pump, done, other]))
        #expect(BoardModel.filter(cards, query: " PUMP ", hideDone: false).map(\.task.name) == ["Fuel pump overhaul", "Pump log"])
        #expect(BoardModel.filter(cards, query: "", hideDone: true).map(\.task.name) == ["Fuel pump overhaul", "Galley"])
        #expect(BoardModel.cards(BoardModel.filter(cards, query: "", hideDone: true), in: .done).isEmpty)
    }

    @Test func dragChangesStatus() {
        // TV: 07 B9, B10, VIEW-047
        let t = TaskItem(name: "t")
        #expect(BoardModel.setStatus(t, .done) && t.status.rawValue == 3 && t.isComplete)
        #expect(BoardModel.setStatus(t, .blocked) && t.status.rawValue == 2 && !t.isComplete)
        #expect(!BoardModel.setStatus(t, .blocked))
    }

    @Test func duplicateIdsGetOneCard() {
        // TV: 07 B12
        let a = TaskItem(name: "first"), b = TaskItem(id: a.id, name: "second")
        #expect(BoardModel.flatten(D.data(tasks: [a, b])).map(\.task.name) == ["first"])
    }

    @Test func deleteMessageCountsAllDescendants() {
        // TV: 07 B8, VIEW-052
        let x = TaskItem(name: "X"), s1 = TaskItem(name: "s1"), s2 = TaskItem(name: "s2")
        s1.subtasks = [TaskItem(name: "s11")]
        x.subtasks = [s1, s2]
        #expect(BoardModel.deleteMessage(x) == "Delete task 'X'?\n\nThis also deletes its 3 subtask(s).")
        #expect(BoardModel.deleteMessage(s2) == "Delete task 's2'?")
        #expect(BoardModel.deleteMenuTitle == "Delete Task" && BoardModel.confirmTitle == "Confirm")   // T-KB-06
    }

    @Test func deletesGoThroughTheTrash() throws {
        // DECISIONS 02 Q-4 / 07 Q-01, 07 Q-02: undoable; a nested card leaves its parent.
        let x = TaskItem(name: "X"), sub = TaskItem(name: "sub"), keep = TaskItem(name: "keep")
        x.subtasks = [sub]
        keep.relatedIds = [sub.id]
        let made = StoreFactory.make(data: D.data(tasks: [x, keep]))
        let store = made.store
        #expect(BoardModel.moveToTrash(sub, store: store))
        #expect(x.subtasks.isEmpty && keep.relatedIds.isEmpty && store.data.trash.count == 1)
        #expect(BoardModel.moveToTrash(x, store: store))
        #expect(store.data.tasks.map(\.name) == ["keep"] && store.data.trash.count == 2)
        #expect(store.pendingUndoCount() >= 1)
        _ = store.undoLastDelete()
        #expect(store.data.tasks.contains { $0.name == "X" })
        #expect(!BoardModel.moveToTrash(TaskItem(name: "detached"), store: store))
    }

    @Test func newTaskIsRawAndLogged() {
        // VIEW-053 (raw, not trimmed; blank → nothing), DECISIONS 07 Q-03 (logged)
        let made = StoreFactory.make()
        let store = made.store
        #expect(BoardModel.createTask(named: "   ", store: store) == nil)
        let t = BoardModel.createTask(named: "  Pump ", store: store)
        #expect(t?.name == "  Pump " && t?.status == .todo && store.data.tasks.count == 1)
        let log = store.data.log.last
        #expect(log?.action == "Added" && log?.kind == "Task" && log?.name == "Pump")
    }

    @Test func openAllThreshold() {
        // TV: 07 B13, VIEW-051
        #expect(BoardModel.openAllNeedsConfirmation(fileCount: 16) && !BoardModel.openAllNeedsConfirmation(fileCount: 15))
        #expect(BoardModel.openAllConfirmation(count: 16, name: "X") == "Open all 16 files for 'X'?")
        #expect(BoardModel.noFilesMessage == "This task has no files yet. Open the task and add some to the file bank.")
    }

    // MARK: Saved-list add (VIEW-202, VIEW-214)

    static func savedLists() -> AppData {
        let d = AppData()
        let engine = ChecklistTemplate(name: "Engine", items: [ChecklistTemplateItem(title: "Pump"),
                                                               ChecklistTemplateItem(title: "Valve")])
        let winchFile = FileItem(name: "manual.pdf", path: "files/abc_manual.pdf")
        let deck = ChecklistTemplate(name: "Deck", items: [
            ChecklistTemplateItem(title: "Winch", durationMinutes: 30, isJob: true,
                                  container: Container(richTextXaml: "<Section/>", files: [winchFile])),
        ])
        d.checklistTemplates = [engine, deck]
        return d
    }

    @Test func savedListCandidates() throws {
        // VIEW-202 rows; 06 BUILD-101 vector ("Deck  ›  Check A   · schedulable")
        guard case .rows(let rows) = BoardSavedListAdd.candidates(Self.savedLists()) else {
            Issue.record("expected rows"); return
        }
        #expect(rows.map(\.display) == ["Engine  \u{203A}  Pump", "Engine  \u{203A}  Valve",
                                         "Deck  \u{203A}  Winch   \u{00B7} schedulable"])
        #expect(BoardSavedListAdd.display(listName: "", title: "", isJob: false) == "(unnamed list)  \u{203A}  (untitled)")
        #expect(BoardSavedListAdd.display(listName: "Deck", title: "Check A", isJob: true) == "Deck  \u{203A}  Check A   \u{00B7} schedulable")
        guard case .noLists = BoardSavedListAdd.candidates(AppData()) else { Issue.record("noLists"); return }
        let empty = AppData(); empty.checklistTemplates = [ChecklistTemplate(name: "x")]
        guard case .noItems = BoardSavedListAdd.candidates(empty) else { Issue.record("noItems"); return }
    }

    @Test func savedListAddKeepsPickOrder() throws {
        // TV: 07 SL1, SL3, VIEW-214; 07 S8 ItemToTask
        let data = Self.savedLists()
        let existing = TaskItem(name: "existing")
        data.tasks = [existing]
        let made = StoreFactory.make(data: data)
        let store = made.store
        let deck = data.checklistTemplates[1], engine = data.checklistTemplates[0]
        let created = BoardSavedListAdd.apply([BoardSavedListTag(templateID: deck.id, index: 0),
                                               BoardSavedListTag(templateID: engine.id, index: 0),
                                               BoardSavedListTag(templateID: UUID(), index: 0),
                                               BoardSavedListTag(templateID: engine.id, index: 9)], store: store)
        #expect(created.map(\.name) == ["Winch", "Pump"])
        #expect(store.data.tasks.map(\.name) == ["existing", "Winch", "Pump"])
        let winch = created[0]
        #expect(winch.isJob && winch.durationMinutes == 30 && winch.status == .todo && winch.deadline == nil)
        let src = deck.items[0].container
        #expect(winch.container.id != src.id && winch.container.richTextXaml == "<Section/>")
        #expect(winch.container.files.first?.path == "files/abc_manual.pdf" && winch.container.files.first?.id != src.files[0].id)
        #expect(store.data.log.suffix(2).map(\.detail) == ["from saved list 'Deck'", "from saved list 'Engine'"])
        // Board To Do order follows: Winch before Pump.
        #expect(BoardModel.cards(BoardModel.flatten(store.data), in: .todo).map(\.task.name) == ["existing", "Winch", "Pump"])
        #expect(deck.items.count == 1 && engine.items.count == 2)
        // SL3: nothing ticked → nothing created, nothing dirtied.
        let made2 = StoreFactory.make(data: Self.savedLists())
        #expect(BoardSavedListAdd.apply([], store: made2.store).isEmpty && !made2.store.isDirty)
    }
}
