// Tests for 02 §7.6 (batch delete description), 04 §7.6; REPO-073…075; Mac key strings (03 §6.5.1.9).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct SvcBatchDeleteTests {
    @Test func describeTheSpecSelection() throws {
        // TV: 02 §7.6 (setup, field table, prompt, trashAll)
        let made = StoreFactory.make(); let store = made.store
        let a = TaskItem(name: "A"), s1 = TaskItem(name: "S1"), s1a = TaskItem(name: "S1a"), s2 = TaskItem(name: "S2")
        s1a.container.files = [FileItem(name: "f.pdf")]
        s1.subtasks = [s1a]; a.subtasks = [s1, s2]
        let p = Procedure(name: "P"); p.steps = [ChecklistStep(title: "1"), ChecklistStep(title: "2"), ChecklistStep(title: "3")]
        let x = Equipment(name: "X"); x.procedureIds = [p.id]
        let l = Equipment(name: "L")
        let v = Vessel(name: "V"); v.container.files = [FileItem(name: "v.pdf")]
        store.data.tasks = [a]; store.data.procedures = [p]; store.data.equipment = [x, l]; store.data.vessels = [v]
        let gated: (HierarchyItem) -> Bool = { $0 === l }
        let selection: [AnyObject] = [a, s1, p, l, v, a]

        #expect(BatchDelete.topLevel(selection).map(\.id) == [a.id, p.id, l.id, v.id])
        let d = BatchDelete.describe(selection, store: store, isGated: gated)
        #expect(d.tasks == 1 && d.procedures == 1 && d.equipment == 0 && d.vessels == 1)
        #expect(d.locked == 1 && d.descendants == 6 && d.withAttachments == 2 && d.linkedFromElsewhere == 1)
        #expect(d.total == 3 && !d.isEmpty)
        #expect(d.kindBreakdown() == "1 task, 1 procedure, 1 vessel")
        #expect(BatchDelete.nothingToDeleteMessage(d) == nil)

        let expected = """
        Move 3 items to the Trash?

            1 task, 1 procedure, 1 vessel
            6 subtask/step/components inside them will be deleted too.
            2 of them have attached files (the files stay on disk).
            1 is linked from other items; those links show "(missing)" until the Trash is emptied.
            1 locked item is selected and will be skipped.
            Note: the Trash holds 200 items, so the 2 oldest will be permanently removed.

        You can restore them from File \u{25B8} Trash, or undo with \u{2318}Z.
        """
        #expect(BatchDelete.confirmationMessage(d, trashCount: 199) == expected)

        #expect(BatchDelete.trashAll(selection, store: store, isGated: gated) == 3)
        #expect(store.data.trash.count == 3 && Set(store.data.trash.map(\.batchId)).count == 1)
        #expect(store.data.equipment.map(\.id) == [x.id, l.id])
    }

    @Test func emptyAndLockedSelections() throws {
        // TV: 02 §7.6 other cases; 04 §7.6
        let made = StoreFactory.make(); let store = made.store
        let empty = BatchDelete.describe([], store: store, isGated: { _ in false })
        #expect(empty.isEmpty)
        let m1 = try #require(BatchDelete.nothingToDeleteMessage(empty))
        #expect(m1.title == "Delete selected" && m1.message == "Select one or more items first.")

        let l = Equipment(name: "L"), l2 = Equipment(name: "L2")
        store.data.equipment = [l, l2]
        let one = BatchDelete.describe([l], store: store, isGated: { _ in true })
        #expect(one.total == 0 && one.locked == 1 && !one.isEmpty)
        let m2 = try #require(BatchDelete.nothingToDeleteMessage(one))
        #expect(m2.title == "Nothing deleted" && m2.message == "That item is locked. Unlock it before deleting it.")
        let two = BatchDelete.describe([l, l2], store: store, isGated: { _ in true })
        #expect(BatchDelete.nothingToDeleteMessage(two)?.message == "All 2 selected items are locked. Unlock them before deleting.")
        #expect(BatchDelete.trashAll([l, l2], store: store, isGated: { _ in true }) == 0)
    }

    @Test func singleEquipmentAndBreakdowns() {
        // TV: 02 §7.6 single Equipment with 1 component; 04 §7.6 KindBreakdown
        let made = StoreFactory.make(); let store = made.store
        let e = Equipment(name: "E"); e.components = [Component(name: "c")]
        store.data.equipment = [e]
        let d = BatchDelete.describe([e], store: store, isGated: { _ in false })
        #expect(d.kindBreakdown() == "1 equipment/area")
        let msg = BatchDelete.confirmationMessage(d, trashCount: 0)
        #expect(msg.hasPrefix("Move 1 item to the Trash?\n\n    1 equipment/area\n"))
        #expect(msg.contains("    1 subtask/step/component inside them will be deleted too."))
        #expect(BatchDelete.Description(equipment: 2).kindBreakdown() == "2 equipment/areas")
        #expect(BatchDelete.Description().kindBreakdown() == "nothing")
        #expect(BatchDelete.Description(tasks: 2, procedures: 3, vessels: 2).kindBreakdown() == "2 tasks, 3 procedures, 2 vessels")
    }

    @Test func specFourPrompt() {
        // TV: 04 §7.6 prompt (D 9, A 1, L 2, K 1, Trash 199)
        let d = BatchDelete.Description(equipment: 1, tasks: 1, procedures: 1, descendants: 9, withAttachments: 1,
                                        linkedFromElsewhere: 2, locked: 1)
        let lines = BatchDelete.confirmationMessage(d, trashCount: 199).components(separatedBy: "\n")
        #expect(lines[0] == "Move 3 items to the Trash?")
        #expect(lines[2] == "    1 task, 1 procedure, 1 equipment/area")
        #expect(lines[3] == "    9 subtask/step/components inside them will be deleted too.")
        #expect(lines[4] == "    1 of them has attached files (the files stay on disk).")
        #expect(lines[5] == "    2 are linked from other items; those links show \"(missing)\" until the Trash is emptied.")
        #expect(lines[6] == "    1 locked item is selected and will be skipped.")
        #expect(lines[7] == "    Note: the Trash holds 200 items, so the 2 oldest will be permanently removed.")
        let many = BatchDelete.Description(tasks: 1, locked: 3)
        #expect(BatchDelete.confirmationMessage(many, trashCount: 0).contains("    3 locked items are selected and will be skipped."))
    }

    @Test func descendantSelectionAndCycles() {
        // TV: 04 §7.6 (task + its own subtask); 02 §7.6 cycle guard
        let made = StoreFactory.make(); let store = made.store
        let a = TaskItem(name: "A"), b = TaskItem(name: "B"), c = TaskItem(name: "C"), d = TaskItem(name: "D")
        b.subtasks = [c]; a.subtasks = [b, d]
        store.data.tasks = [a]
        #expect(BatchDelete.topLevel([c, a]).map(\.id) == [a.id])
        let loop = TaskItem(name: "loop"); loop.subtasks = [loop]
        store.data.tasks.append(loop)
        // Terminates; like C# `TopLevel`, a task that is its own descendant is "covered" and drops out.
        let desc = BatchDelete.describe([loop], store: store, isGated: { _ in false })
        #expect(desc.total == 0)
    }

    @Test func statusLines() {
        // REPO-075 step 5 (Mac key names)
        #expect(BatchDelete.statusAfterDelete(count: 1, firstName: "Pump") == "'Pump' moved to Trash \u{2014} \u{2318}Z to undo.")
        #expect(BatchDelete.statusAfterDelete(count: 3, firstName: "Pump") == "3 items moved to Trash \u{2014} \u{2318}Z to undo them all.")
    }
}
