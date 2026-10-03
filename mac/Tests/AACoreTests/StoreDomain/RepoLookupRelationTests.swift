// Tests for 02 §2.B/§2.C (REPO-010…029), 01 §3.24 (DATA-137/138); DECISIONS 02 Q-3 (widened purge).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct RepoLookupRelationTests {
    private func fresh() -> (StoreFactory.Made, AppStore) {
        let made = StoreFactory.make()
        return (made, made.store)
    }

    @Test func addRelationTwiceAndSelf() {
        // TV: 02 T-REL-1, T-REL-2, T-REL-3
        let (made, store) = fresh(); _ = made
        let a = TaskItem(name: "A"), b = TaskItem(name: "B")
        store.data.tasks = [a, b]
        store.addRelation(a, b)
        store.addRelation(a, b)
        #expect(a.relatedIds == [b.id])
        #expect(b.relatedIds == [a.id])
        store.addRelation(a, a)
        #expect(a.relatedIds == [b.id])
        store.removeRelation(a, b)
        #expect(a.relatedIds.isEmpty && b.relatedIds.isEmpty)
        store.removeRelation(a, b)                       // no-op when absent
        #expect(a.relatedIds.isEmpty)
    }

    @Test func relatedItemsOfEquipmentAndProcedure() {
        // TV: 02 T-REL-4, T-REL-5
        let (made, store) = fresh(); _ = made
        let e = Equipment(name: "E"), v = Vessel(name: "V"), p = Procedure(name: "P"), t = TaskItem(name: "T")
        store.data.equipment = [e]; store.data.vessels = [v]; store.data.procedures = [p]; store.data.tasks = [t]
        e.relatedIds = [v.id]; e.procedureIds = [p.id]; e.taskIds = [t.id, v.id]
        #expect(store.relatedItems(of: e).map(\.id) == [v.id, p.id, t.id])
        let s = ChecklistStep(title: "s"); s.taskIds = [t.id]; p.steps = [s]
        #expect(store.relatedItems(of: p).isEmpty)
    }

    @Test func referencedByUsesAllItemsOrder() {
        // TV: 02 T-REL-6
        let (made, store) = fresh(); _ = made
        let e = Equipment(name: "E"), t = TaskItem(name: "T"), p = Procedure(name: "P"), x = Vessel(name: "X")
        store.data.equipment = [e]; store.data.tasks = [t]; store.data.procedures = [p]; store.data.vessels = [x]
        e.taskIds = [t.id]
        let s = ChecklistStep(title: "s"); s.taskIds = [t.id]; p.steps = [s]
        x.relatedIds = [t.id]
        #expect(store.referencedBy(t).map(\.id) == [e.id, p.id, x.id])
        #expect(store.relatedItems(of: t).isEmpty)
    }

    @Test func labelsAndKindLabels() {
        // TV: 02 T-REL-7, T-REL-8; REPO-015
        let (made, store) = fresh(); _ = made
        let e = Equipment(name: "E"), t = TaskItem(name: "Pump")
        let p = Procedure(name: "P")
        store.data.equipment = [e]; store.data.tasks = [t]
        e.procedureIds = [p.id]                             // P not in the data (trashed)
        #expect(store.label(for: p.id) == "(missing)")
        #expect(store.relatedItems(of: e).isEmpty)
        #expect(store.label(for: t.id) == "[Task] Pump")
        #expect(store.label(for: e.id) == "[Equipment] E")
        #expect(AppStore.kindLabel(.equipment) == "Equipment/Area")
        #expect(AppStore.kindLabel(.task) == "Task")
        #expect(AppStore.kindLabel(.procedure) == "Procedure")
        #expect(AppStore.kindLabel(.vessel) == "Vessel")
        #expect(AppStore.kindLabel(ItemKind(rawValue: 9)) == "9")
    }

    @Test func findByIdFirstWinsAndLookups() {
        // TV: 02 T-REL-10
        let (made, store) = fresh(); _ = made
        let z = UUID()
        let e = Equipment(id: z, name: "E"), t = TaskItem(id: z, name: "T")
        store.data.equipment = [e]; store.data.tasks = [t]
        #expect(store.item(id: z) === e)
        #expect(store.items(of: .task).count == 1)
        #expect(store.allItems().count == 2)
    }

    @Test func nestedLookups() {
        let (made, store) = fresh(); _ = made
        let t = TaskItem(name: "T"), s = TaskItem(name: "S"), ss = TaskItem(name: "SS")
        s.subtasks = [ss]; t.subtasks = [s]
        store.data.tasks = [t]
        let p = Procedure(name: "P"), st = ChecklistStep(title: "step"); p.steps = [st]; store.data.procedures = [p]
        let e = Equipment(name: "E"), comp = Component(name: "C"); e.components = [comp]; store.data.equipment = [e]
        let m = CrewMember(); let cs = ChecklistStep(title: "crew"); m.checklist = [cs]; store.data.crew = [m]
        let v = Vessel(name: "V"); store.data.vessels = [v]
        let tpl = ChecklistTemplate(name: "L"); store.data.checklistTemplates = [tpl]
        let b = QuickBucket(name: "B"); store.data.quickBuckets = [b]

        #expect(store.task(id: ss.id) === ss)
        #expect(store.item(id: ss.id) == nil)
        #expect(store.parentTask(of: ss.id) === s)
        #expect(store.parentTask(of: t.id) == nil)
        #expect(store.topLevelTask(containing: ss.id) === t)
        #expect(store.step(id: st.id)?.owner == .procedure(p.id))
        #expect(store.step(id: cs.id)?.owner == .crew(m.id))
        #expect(store.component(id: comp.id)?.equipment === e)
        #expect(store.crewMember(id: m.id) === m)
        #expect(store.template(id: tpl.id) === tpl)
        #expect(store.bucket(id: b.id) === b)
        #expect(store.vessel(id: v.id) === v)
        func owner(_ id: UUID) -> [UUID?] {
            guard let o = store.topLevelOwner(ofAnyID: id) else { return [] }
            return [o.owner.id, o.childID]
        }
        #expect(owner(ss.id) == [t.id, ss.id])
        #expect(owner(st.id) == [p.id, st.id])
        #expect(owner(comp.id) == [e.id, comp.id])
        #expect(owner(e.id) == [e.id, nil])
        #expect(owner(cs.id).isEmpty)
    }

    @Test func allJobsOrder() {
        // TV: 02 T-REL-11
        let (made, store) = fresh(); _ = made
        let t = TaskItem(name: "T"); t.isJob = true
        let s = TaskItem(name: "S"); s.isJob = true
        let ss = TaskItem(name: "SS")
        s.subtasks = [ss]; t.subtasks = [s]
        let p = Procedure(name: "P")
        let s1 = ChecklistStep(title: "s1"); s1.isJob = true
        let s2 = ChecklistStep(title: "s2")
        p.steps = [s1, s2]
        let c = CrewMember(); let cs = ChecklistStep(title: "cs"); cs.isJob = true; c.checklist = [cs]
        store.data.tasks = [t]; store.data.procedures = [p]; store.data.crew = [c]
        let jobs = store.allJobs()
        #expect(jobs.map(\.id) == [t.id, s.id, s1.id, cs.id])
        #expect(jobs.map { store.jobOwnerLabel($0) } == ["Task", "Subtask", "Step", "Crew"])
        p.isJob = true
        #expect(store.allJobs().map(\.id) == [t.id, s.id, p.id, s1.id, cs.id])
        #expect(store.jobOwnerLabel(p) == "Procedure")
    }

    @Test func allContainersOrder() {
        // REPO-012
        let (made, store) = fresh(); _ = made
        let e = Equipment(name: "E"); let c1 = Component(name: "c1"); e.components = [c1]
        let t = TaskItem(name: "T"); let s = TaskItem(name: "S"); t.subtasks = [s]
        let p = Procedure(name: "P"); let st = ChecklistStep(title: "st"); p.steps = [st]
        let v = Vessel(name: "V")
        let m = CrewMember(); let cs = ChecklistStep(title: "cs"); m.checklist = [cs]
        let tpl = ChecklistTemplate(name: "L", items: [ChecklistTemplateItem(title: "i")])
        store.data.equipment = [e]; store.data.tasks = [t]; store.data.procedures = [p]; store.data.vessels = [v]
        store.data.crew = [m]; store.data.checklistTemplates = [tpl]
        let expected = [e.container, c1.container, t.container, s.container, p.container, st.container, v.container,
                        cs.container, tpl.items[0].container].map(\.id)
        #expect(store.allContainers().map(\.id) == expected)
    }

    @Test func purgeReferencesWidened() {
        // TV: 02 T-REL-9 as amended by DECISIONS 02 Q-3 (nested subtasks scrubbed too; every occurrence removed)
        let (made, store) = fresh(); _ = made
        let d = UUID()
        let e = Equipment(name: "E"); e.relatedIds = [d, d]; e.procedureIds = [d]; e.taskIds = [d]
        let p = Procedure(name: "P"); let step = ChecklistStep(title: "s"); step.equipmentIds = [d]; step.taskIds = [d]
        p.steps = [step]
        let t = TaskItem(name: "T"); let sub = TaskItem(name: "S"); sub.relatedIds = [d]; t.subtasks = [sub]
        let m = CrewMember(); let cs = ChecklistStep(title: "cs"); cs.taskIds = [d]; cs.equipmentIds = [d]
        let f = FileItem(name: "f"); f.linkedItemIds = [d]; cs.container.files = [f]; m.checklist = [cs]
        let entry = ScheduleEntry(title: "drill", kind: .task, refId: d); m.schedule = [entry]
        let saved = ScheduleTemplate(name: "Rot", entries: [ScheduleEntry(title: "x", kind: .task, refId: d)])
        store.data.equipment = [e]; store.data.procedures = [p]; store.data.tasks = [t]; store.data.crew = [m]
        store.data.scheduleTemplates = [saved]
        store.data.ui.quickViewPinIds = [d, t.id]
        store.data.ui.selectedEquipmentId = d; store.data.ui.selectedTaskId = d; store.data.ui.selectedProcedureId = d
        store.data.ui.selectedVesselId = d; store.data.ui.mapFocusedItemId = d

        store.purgeReferences(to: d)
        #expect(e.relatedIds.isEmpty && e.procedureIds.isEmpty && e.taskIds.isEmpty)
        #expect(step.taskIds.isEmpty && step.equipmentIds.isEmpty)
        #expect(sub.relatedIds.isEmpty)
        #expect(cs.taskIds.isEmpty && cs.equipmentIds.isEmpty && f.linkedItemIds.isEmpty)
        #expect(entry.refId == nil && saved.entries[0].refId == nil)
        #expect(store.data.ui.quickViewPinIds == [t.id])
        #expect(store.data.ui.selectedEquipmentId == nil && store.data.ui.selectedTaskId == nil)
        #expect(store.data.ui.selectedProcedureId == nil && store.data.ui.selectedVesselId == nil)
        #expect(store.data.ui.mapFocusedItemId == nil)
        #expect(!store.isDirty)                              // never marks dirty — callers do
    }

    @Test func linkReplaceSemantics() {
        // REPO-023, REPO-024, REPO-027
        let (made, store) = fresh(); _ = made
        let e = Equipment(name: "E"); e.procedureIds = [UUID()]; e.taskIds = [UUID()]
        let a = UUID(), b = UUID()
        store.linkProcedures([a, b], to: e)
        store.linkTasks([b], to: e)
        #expect(e.procedureIds == [a, b] && e.taskIds == [b])
        let s = ChecklistStep(title: "s"); s.taskIds = [UUID()]
        store.linkTasks([a], to: s)
        store.linkEquipment([b], to: s)
        #expect(s.taskIds == [a] && s.equipmentIds == [b])
    }
}
