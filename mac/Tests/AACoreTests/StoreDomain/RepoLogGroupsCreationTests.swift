// Tests for 02 §2.I (REPO-090/091, T-LOG-1…3, T-LOG-5), 08 T-AL-5/6, QUICK-154; 02 §2.L (REPO-120, T-GRP-1…3);
// 02 §2.D (REPO-025…027, REPO-035/036 creation catalogue and Kind strings).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct RepoLogGroupsCreationTests {
    static let clock = FixedClock(local: "2026-09-29T11:15:30", zone: TZ.athens)

    @Test func logNormalisesNamesAndStampsUtc() throws {
        // TV: 02 T-LOG-1, T-LOG-2, T-LOG-5; 08 T-AL-6
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        store.logAdded(kind: "Task", name: "  Pump  ")
        let e = try #require(store.data.log.last)
        #expect(e.name == "Pump" && e.detail == "" && e.action == "Added" && e.kind == "Task")
        #expect(e.timestampUtc.kind == .utc && e.timeUtc == "2026-09-29 08:15:30 UTC")
        store.logRemoved(kind: "Task", name: "   ")
        #expect(store.data.log.last?.name == "(unnamed)" && store.data.log.last?.action == "Removed")
        store.logAdded(kind: "Task", name: nil, detail: nil)
        #expect(store.data.log.last?.name == "(unnamed)" && store.data.log.last?.detail == "")
        store.logAdded(kind: "Task", name: "\u{00A0}x\u{3000}")      // .NET Trim covers Unicode white space
        #expect(store.data.log.last?.name == "x")
        #expect(store.isDirty)
    }

    @Test func logIsCappedFromTheFront() {
        // TV: 02 T-LOG-3; 01 §7.11; 08 T-AL-5
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        store.data.log = (0..<AppStore.maxLogEntries).map { LogEntry(action: "Added", kind: "K", name: "n\($0)") }
        store.logAdded(kind: "K", name: "last")
        #expect(store.data.log.count == 10_000)
        #expect(store.data.log.first?.name == "n1" && store.data.log.last?.name == "last")
    }

    @Test func clearLog() {
        // QUICK-154
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        store.clearLog()
        #expect(!store.isDirty)
        store.logAdded(kind: "K", name: "a")
        store.clearLog()
        #expect(store.data.log.isEmpty && store.isDirty)
    }

    @Test func groups() {
        // TV: 02 T-GRP-1, T-GRP-2, T-GRP-3; 01 DATA-136
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        let g = store.createGroup(kind: .task, name: "  ")
        #expect(g.name == "New group" && g.kind == .task && store.data.groups.count == 1)
        let h = store.createGroup(kind: .equipment, name: "  Engine room ")
        #expect(h.name == "Engine room")
        store.renameGroup(g, to: "")
        #expect(g.name == "New group")
        store.renameGroup(g, to: " Deck ")
        #expect(g.name == "Deck")
        #expect(store.groups(for: .task).map(\.id) == [g.id])
        let e = Equipment(name: "e"), t = TaskItem(name: "t")
        store.data.equipment = [e]; store.data.tasks = [t]
        store.assign([e, t], toGroup: g.id)
        #expect(e.groupId == g.id && t.groupId == g.id)
        store.deleteGroup(g)
        #expect(e.groupId == nil && t.groupId == nil)
        #expect(store.data.groups.map(\.id) == [h.id])
        store.assign([t], toGroup: nil)
        #expect(t.groupId == nil)
    }

    @Test func creationCatalogue() throws {
        // REPO-035 catalogue, REPO-025…027 Kind strings (REPO-091)
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        let e = store.createItem(kind: .equipment) as! Equipment
        let t = store.createItem(kind: .task)
        let p = store.createItem(kind: .procedure) as! Procedure
        let v = store.createItem(kind: .vessel, name: "Aurora")
        #expect([e.name, t.name, p.name, v.name] == ["New Equipment/Area", "New Task", "New Procedure", "Aurora"])
        #expect(store.data.log.map(\.kind) == ["Equipment/Area", "Task", "Procedure", "Vessel"])
        #expect(store.data.log.allSatisfy { $0.action == "Added" && $0.detail == "" })

        let lp = store.createLinkedProcedure(named: " Bunkering", for: e)
        #expect(lp.name == " Bunkering" && e.procedureIds == [lp.id] && store.data.procedures.last === lp)
        #expect(store.data.log.last?.kind == "Procedure" && store.data.log.last?.detail == "linked to New Equipment/Area")
        let lt = store.createLinkedTask(named: "Filter", for: e)
        #expect(e.taskIds == [lt.id] && store.data.log.last?.detail == "linked to New Equipment/Area")
        #expect(lt.relatedIds.isEmpty)
        let step = store.addStep(titled: "Check", to: p)
        #expect(p.steps.map(\.id) == [step.id])
        #expect(store.data.log.last?.kind == "Checklist step" && store.data.log.last?.detail == "New Procedure")
        let st = store.createLinkedTask(named: "Sample", for: step)
        #expect(step.taskIds == [st.id] && store.data.log.last?.detail == "linked to step 'Check'")

        let task = try #require(t as? TaskItem)
        let sub = store.addSubtask(named: "Drain", to: task)
        #expect(task.subtasks.map(\.id) == [sub.id])
        #expect(store.data.log.last?.kind == "Subtask" && store.data.log.last?.detail == "New Task")
        let logCount = store.data.log.count
        _ = store.addSubtask(named: "quiet", to: task, log: false)
        let comp = store.addComponent(named: "Pump", to: e)
        #expect(store.data.log.count == logCount && e.components.map(\.id) == [comp.id])

        store.removeSubtask(sub, from: task)
        #expect(store.data.log.last?.action == "Removed" && store.data.log.last?.kind == "Subtask")
        store.removeStep(step, from: p)
        #expect(p.steps.isEmpty && store.data.log.last?.kind == "Checklist step")
        store.removeComponent(comp, from: e)
        #expect(e.components.isEmpty && store.data.log.last?.kind == "Checklist step")

        let board = store.createTopLevelTask(named: "Board card")
        #expect(store.data.tasks.last === board && store.data.log.last?.kind == "Task")
        let n = store.data.log.count
        _ = store.createTopLevelTask(named: "silent", logKind: nil)
        #expect(store.data.log.count == n)
        let proc = store.createTopLevelProcedure(named: "Quick proc")
        #expect(store.data.procedures.last === proc && store.data.log.last?.kind == "Procedure")
    }
}
