// W-FILES — container owners, shared containers (SharedWithContainerIds UI), backlinks ("Linked to" / item
// backlinks, DECISIONS 05), the Link-to-items picker rows (CONT-093, VIEW-212 row 26, VIEW-215).
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct FileBankDirectoryTests {
    struct World {
        let made: StoreFactory.Made
        let pump: Equipment, motor: Component, task: TaskItem, sub: TaskItem, proc: Procedure, step: ChecklistStep
        let vessel: Vessel, crew: CrewMember, crewStep: ChecklistStep, list: ChecklistTemplate
        var store: AppStore { made.store }
    }

    private func world() -> World {
        let made = StoreFactory.make()
        let d = made.store.data
        let pump = Equipment(name: "Cargo pump 1")
        let motor = Component(name: "Motor")
        pump.components = [motor]
        let task = TaskItem(name: "Check purifier")
        let sub = TaskItem(name: "Clean bowl")
        let subsub = TaskItem(name: "Replace O-ring")
        sub.subtasks = [subsub]
        task.subtasks = [sub]
        let proc = Procedure(name: "Bunkering")
        let step = ChecklistStep(title: "Sound tanks")
        proc.steps = [step]
        let vessel = Vessel(name: "BW Pavilion Aranda")
        let crew = CrewMember()
        crew.firstName = "Ana"; crew.lastName = "Reyes"
        let crewStep = ChecklistStep(title: "Medical")
        crew.checklist = [crewStep]
        let list = ChecklistTemplate(name: "Engine rounds", items: [ChecklistTemplateItem(title: "Lube oil")])
        d.equipment = [pump]; d.tasks = [task]; d.procedures = [proc]; d.vessels = [vessel]; d.crew = [crew]
        d.checklistTemplates = [list]
        return World(made: made, pump: pump, motor: motor, task: task, sub: sub, proc: proc, step: step, vessel: vessel,
                     crew: crew, crewStep: crewStep, list: list)
    }

    @Test func ownerLabelsAndNavigationTargets() {
        let w = world()
        let dir = FileBankDirectory(store: w.store)
        #expect(dir.entries.count == w.store.allContainers().count)
        #expect(dir.owner(of: w.pump.container)?.label == "[Equipment] Cargo pump 1")
        let m = dir.owner(of: w.motor.container)
        #expect(m?.label == "[Equipment] Cargo pump 1 ▸ Motor" && m?.itemID == w.pump.id && m?.childID == w.motor.id)
        #expect(m?.role == .component && m?.gatingItemID == w.pump.id)
        let deep = dir.owner(of: w.sub.subtasks[0].container)
        #expect(deep?.label == "[Task] Check purifier ▸ Clean bowl ▸ Replace O-ring")
        #expect(deep?.itemID == w.task.id && deep?.childID == w.sub.subtasks[0].id && deep?.gatingItemID == w.task.id)
        #expect(dir.owner(of: w.step.container)?.label == "[Procedure] Bunkering ▸ Sound tanks")
        #expect(dir.owner(of: w.vessel.container)?.label == "[Vessel] BW Pavilion Aranda")
        let c = dir.owner(of: w.crewStep.container)
        #expect(c?.label == "[Crew] Ana Reyes ▸ Medical" && c?.crewMemberID == w.crew.id && c?.itemID == nil)
        let l = dir.owner(of: w.list.items[0].container)
        #expect(l?.label == "[Saved list] Engine rounds ▸ Lube oil" && l?.savedListID == w.list.id)
        #expect(dir.owner(of: Container()) == nil)
    }

    @Test func subtaskCyclesDoNotHang() {
        let w = world()
        w.sub.subtasks.append(w.task)                                 // malformed: the task is its own descendant
        let dir = FileBankDirectory(store: w.store)
        #expect(dir.owner(of: w.sub.container) != nil)
    }

    @Test func sharedIntoAndSharedWith() {
        // DECISIONS 05: A.SharedWithContainerIds = [B] → A's files are listed in B's "Shared" view
        let w = world()
        w.task.container.sharedWithContainerIds = [w.pump.container.id, UUID()]
        w.step.container.sharedWithContainerIds = [w.pump.container.id]
        w.pump.container.sharedWithContainerIds = [w.pump.container.id]            // self is never listed
        let dir = FileBankDirectory(store: w.store)
        #expect(dir.sharedInto(w.pump.container).map(\.owner.label) ==
                ["[Task] Check purifier", "[Procedure] Bunkering ▸ Sound tanks"])
        #expect(dir.sharedWith(w.task.container).map(\.owner.label) == ["[Equipment] Cargo pump 1"])
        #expect(dir.sharedWith(w.pump.container).isEmpty)
    }

    @Test func sharePickKeepsUnknownIdsAndDropsSelf() {
        // CONT-095: ids naming no loaded container round-trip untouched; picks replace the rest
        let w = world()
        let unknown = UUID()
        let c = w.pump.container
        c.sharedWithContainerIds = [w.task.container.id, unknown]
        let dir = FileBankDirectory(store: w.store)
        #expect(dir.applyingSharePick([w.task.container.id], to: c) == nil)            // unchanged → nil
        let next = dir.applyingSharePick([w.vessel.container.id, c.id, w.vessel.container.id, w.task.container.id], to: c)
        #expect(next == [w.vessel.container.id, w.task.container.id, unknown])
        #expect(dir.applyingSharePick([], to: c) == [unknown])
        #expect(!dir.shareCandidates(excluding: c).contains { $0.container === c })
        #expect(dir.shareCandidates(excluding: c).count == dir.entries.count - 1)
    }

    @Test func backlinksAcrossContainers() {
        // DECISIONS 05 item backlinks — REPO-012 container order, then file order
        let w = world()
        let target = w.vessel.id
        let f1 = FileItem(name: "manual.pdf", linkedItemIds: [target])
        let f2 = FileItem(name: "photo.png", linkedItemIds: [UUID()])
        let f3 = FileItem(name: "plan.pdf", linkedItemIds: [UUID(), target])
        let f4 = FileItem(name: "list.pdf", linkedItemIds: [target])
        w.step.container.files = [f3]
        w.pump.container.files = [f1, f2]
        w.list.items[0].container.files = [f4]
        // The same entry object in two containers (Windows cut/paste) is reported once per container.
        w.vessel.container.files = [f1]
        let links = FileBankDirectory(store: w.store).backlinks(to: target)
        #expect(links.map(\.file.name) == ["manual.pdf", "plan.pdf", "manual.pdf", "list.pdf"])
        #expect(links.map(\.owner.label) == ["[Equipment] Cargo pump 1", "[Procedure] Bunkering ▸ Sound tanks",
                                             "[Vessel] BW Pavilion Aranda", "[Saved list] Engine rounds ▸ Lube oil"])
        #expect(Set(links.map(\.id)).count == 4)
    }

    @Test func linkPickerRows() {
        // TV: 05 CONT-093 / 07 VIEW-212 row 26 — top-level only, kind order then OrdinalIgnoreCase name, stable
        let made = StoreFactory.make()
        let d = made.store.data
        let e1 = Equipment(name: "pump"), e2 = Equipment(name: "Aft winch"), e3 = Equipment(name: "Pump")
        let t1 = TaskItem(name: "zeta"), t2 = TaskItem(name: "Alpha")
        t1.subtasks = [TaskItem(name: "hidden subtask")]
        let p1 = Procedure(name: "Bunkering"), v1 = Vessel(name: "Aranda")
        d.vessels = [v1]; d.procedures = [p1]; d.tasks = [t1, t2]; d.equipment = [e1, e2, e3]
        let rows = FileBankLinkPicker.rows(made.store)
        #expect(rows.map(\.display) == ["[Equipment] Aft winch", "[Equipment] pump", "[Equipment] Pump", "[Task] Alpha",
                                        "[Task] zeta", "[Procedure] Bunkering", "[Vessel] Aranda"])
        #expect(rows[1].id == e1.id && rows[2].id == e3.id)                         // stable for equal names
    }

    @Test func linkPickerApplyNormalisesAndMarksDirty() {
        // TV: 07 VIEW-215 (row 26): replace, collapse duplicates, MarkDirty (even when unchanged)
        let made = StoreFactory.make()
        let a = UUID(), b = UUID()
        let f = FileItem(name: "x", linkedItemIds: [b])
        #expect(!made.store.isDirty)
        FileBankLinkPicker.apply([a, b, a], to: f, store: made.store)
        #expect(f.linkedItemIds == [a, b] && made.store.isDirty)
        #expect(FileBankLinkPicker.normalized([b, b, a, b]) == [b, a])
        made.store.cancelPendingAutosave()
    }

    @Test func linkedSummary() {
        let made = StoreFactory.make()
        let e = Equipment(name: "Main engine"), t = TaskItem(name: "Check purifier")
        made.store.data.equipment = [e]; made.store.data.tasks = [t]
        let index = FileBankItemIndex(store: made.store)
        #expect(index.linkedSummary([t.id, UUID(), e.id]) == "Check purifier, Main engine")
        #expect(index.linkedSummary([]) == "")
        #expect(index.kind(of: e.id) == .equipment && index.name(of: t.id) == "Check purifier")
    }
}
