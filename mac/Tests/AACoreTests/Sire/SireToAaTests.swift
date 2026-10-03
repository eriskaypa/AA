// Tests: 12 §7.11 (quick-add vectors for every kind, sections, chapters, Truncate), SIRE-046/047, 02 REPO-030
//        (two-way relations, Equipment TaskIds, one `Added` log entry for the parent only), §3.7 scale note.
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct SireToAaTests {
    static let long = String(repeating: "L", count: 100)
    static let identified = SireIdentifiedTasks([("2.1.10", ["Verify X", long])])

    @Test func equipmentQuestion() {
        let m = StoreFactory.make()
        let r = SireToAa.addQuestion(SireSynthetic.q2110, kind: .equipment, identified: Self.identified, store: m.store)
        let data = m.store.data
        #expect(data.equipment.count == 1 && data.tasks.count == 2 && data.procedures.isEmpty)
        let eq = data.equipment[0]
        #expect(r.primary === eq && r.itemsCreated == 1 && r.tasksCreated == 2)
        #expect(eq.name == "SIRE Q2.1.10 — Beta check" && eq.tags == ["SIRE"])
        #expect(eq.container.richTextXaml.hasPrefix("<Section ") && eq.container.richTextXaml.contains(##"Foreground="#FF334155""##))
        #expect(eq.components.count == 2)
        #expect(eq.components[0].name == "Verify X" && eq.components[0].notes == "Verify X")
        #expect(eq.components[1].name == String(repeating: "L", count: 80) + "…" && eq.components[1].notes == Self.long)
        for t in data.tasks {
            #expect(t.tags == ["SIRE"] && t.description == "SIRE Q2.1.10 — Beta check")
            #expect(eq.relatedIds.contains(t.id) && eq.taskIds.contains(t.id) && t.relatedIds == [eq.id])
        }
        #expect(data.tasks.map(\.name) == ["Verify X", Self.long])
        #expect(data.log.count == 1)
        let log = data.log[0]
        #expect(log.action == "Added" && log.kind == "Equipment/Area" && log.name == "SIRE Q2.1.10 — Beta check")
        #expect(log.detail == "from SIRE Q2.1.10")
        #expect(r.summary == "Added “SIRE Q2.1.10 — Beta check” as Equipment with 2 linked task(s).")
        #expect(m.store.isDirty)
    }

    @Test func procedureQuestion() {
        let m = StoreFactory.make()
        let r = SireToAa.addQuestion(SireSynthetic.q2110, kind: .procedure, identified: Self.identified, store: m.store)
        let p = m.store.data.procedures[0]
        #expect(r.primary === p)
        #expect(p.steps.map(\.title) == ["Verify X", Self.long])
        #expect(p.steps.allSatisfy { $0.container.richTextXaml.isEmpty })
        #expect(m.store.data.tasks.count == 2 && p.relatedIds.count == 2)
        #expect(m.store.data.log[0].kind == "Procedure")
        #expect(r.summary == "Added “SIRE Q2.1.10 — Beta check” as Procedure with 2 linked task(s).")
    }

    @Test func taskQuestion() {
        let m = StoreFactory.make()
        let r = SireToAa.addQuestion(SireSynthetic.q2110, kind: .task, identified: Self.identified, store: m.store)
        let tasks = m.store.data.tasks
        #expect(tasks.count == 3)
        #expect(tasks[0] === r.primary)
        #expect(tasks[0].subtasks.map(\.name) == ["Verify X", Self.long])
        #expect(tasks[0].subtasks.allSatisfy { $0.tags.isEmpty })
        #expect(tasks[1].name == "Verify X" && tasks[2].name == Self.long)
        #expect(r.summary == "Added “SIRE Q2.1.10 — Beta check” as Task with 2 linked task(s).")
    }

    @Test func questionWithoutTasks() {
        let m = StoreFactory.make()
        let r = SireToAa.addQuestion(SireSynthetic.q111, kind: .task, identified: Self.identified, store: m.store)
        #expect(r.summary == "Added “SIRE Q1.1.1 — ” as Task.")
        #expect(m.store.data.tasks.count == 1 && r.tasksCreated == 0)
        #expect(m.store.data.tasks[0].name == "SIRE Q1.1.1 — ")
    }

    @Test func section() {
        let m = StoreFactory.make()
        let r = SireToAa.addSection("2.1", kind: .procedure, bank: SireSynthetic.contents, store: m.store)
        let p = m.store.data.procedures[0]
        #expect(p.name == "SIRE Section 2.1")
        #expect(p.container.richTextXaml.contains("2 SIRE 2.0 question(s). Imported from the SIRE 2.0 Knowledge Bank."))
        #expect(p.container.richTextXaml.contains("<Run>Q 2.1.2 — Alpha check</Run>") && p.container.richTextXaml.contains("<Run>Q 2.1.10 — Beta check</Run>"))
        #expect(p.steps.map(\.title) == ["Q2.1.2 — Alpha check", "Q2.1.10 — Beta check"])
        #expect(p.steps[0].container.richTextXaml == SireFlowXaml.questionXaml(SireSynthetic.q212))
        let tasks = m.store.data.tasks
        #expect(tasks.map(\.name) == ["Verify Y", "Verify Z", "Verify X"])
        #expect(tasks.map(\.description) == ["SIRE Q2.1.2 — Alpha check", "SIRE Q2.1.2 — Alpha check", "SIRE Q2.1.10 — Beta check"])
        #expect(tasks.allSatisfy { $0.relatedIds == [p.id] } && p.relatedIds == tasks.map(\.id))
        #expect(m.store.data.log.count == 1 && m.store.data.log[0].detail == "from SIRE (2 questions)")
        #expect(r.summary == "Added “SIRE Section 2.1” as Procedure with 2 question(s) and 3 linked task(s).")
    }

    @Test func chapterAndEquipmentChildren() {
        let m = StoreFactory.make()
        let r = SireToAa.addChapter("2", kind: .equipment, bank: SireSynthetic.contents, store: m.store)
        let e = m.store.data.equipment[0]
        #expect(e.name == "SIRE Ch2 — Certs")
        #expect(e.components.map(\.name) == ["Q2.1.2 — Alpha check", "Q2.1.10 — Beta check"])
        #expect(e.components.map(\.notes) == ["Is alpha ok?", "Is beta ok?"])
        #expect(e.taskIds.count == 3)
        #expect(r.summary == "Added “SIRE Ch2 — Certs” as Equipment with 2 question(s) and 3 linked task(s).")
        let none = SireToAa.addChapter("99", kind: .task, bank: SireSynthetic.contents, store: m.store)
        #expect(none.primary == nil && none.summary == "No questions found for that selection.")
    }

    @Test func groupWithoutTasksAndTaskChildren() {
        let m = StoreFactory.make()
        let r = SireToAa.addGroup([SireSynthetic.q111], kind: .task, identified: SireIdentifiedTasks(), store: m.store,
                                  createTopLevelTasks: true, parentName: "SIRE Section 1.1")
        #expect(r.summary == "Added “SIRE Section 1.1” as Task with 1 question(s).")
        let t = m.store.data.tasks[0]
        #expect(t.subtasks.map(\.name) == ["Q1.1.1 — "] && !t.subtasks[0].container.richTextXaml.isEmpty)
    }

    // TV: 12 §7.11 Truncate
    @Test func truncate() {
        #expect(SireToAa.truncate("abc", 80) == "abc")
        #expect(SireToAa.truncate(String(repeating: "a", count: 79) + "  bbbb", 80) == String(repeating: "a", count: 79) + "…")
        let emoji = String(repeating: "a", count: 79) + "😀tail"
        #expect(SireToAa.truncate(emoji, 80) == String(repeating: "a", count: 79) + "…")
    }

    @Test func kindDefaults() {
        #expect(SireAddKind.fromDominantCategory("Equipment") == .equipment)
        #expect(SireAddKind.fromDominantCategory("Procedure") == .procedure)
        #expect(SireAddKind.fromDominantCategory("Task") == .task)
        #expect(SireAddKind.allCases.map(\.pickerLabel) == ["Procedure", "Task", "Equipment / Area"])
    }

    // §3.7 scale note: a whole real chapter 8 as Equipment in one batch.
    @Test func chapterScale() {
        let m = StoreFactory.make()
        let r = SireToAa.addChapter("8", kind: .equipment, bank: SireTestBank.contents, store: m.store)
        #expect(m.store.data.equipment[0].components.count == 91)
        #expect(m.store.data.tasks.count == 1705 && r.tasksCreated == 1705)
        #expect(m.store.data.equipment[0].name == "SIRE Ch8 — Cargo and Ballast Systems")
    }
}
