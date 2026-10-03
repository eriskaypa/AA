// Tests for SectionID, tab colours and the item-picker selection model (F3): 03 §7.1 (ApplyTabOrder, tab drop,
// selected tab restore, tab contrast, TryBrush, colour picker output), ARCH §6.9 writeTabOrder, 07 VIEW-208…211.
import Foundation
import Testing
@testable import AACore

@Suite struct ShellSectionIDTests {
    typealias S = SectionID

    // TV: 03 §7.1 "ApplyTabOrder"
    @Test func applyTabOrder() {
        #expect(S.applyTabOrder([]) == S.defaultOrder)
        #expect(S.applyTabOrder(["TabSire", "TabTasks", "Bogus", "TabTasks"])
                == [.sire, .tasks, .equipment, .procedures, .vessels, .calendar, .board, .planner, .map, .crew, .lists,
                    .buckets, .ports])
        #expect(S.applyTabOrder(["CrewTab"]) == [.crew] + S.defaultOrder.filter { $0 != .crew })
        #expect(S.applyTabOrder(["TabMap", "TabMap", "TabMap"]) == [.map] + S.defaultOrder.filter { $0 != .map })
    }

    // TV: 03 §7.1 "Tab drop"
    @Test func tabDrop() {
        let d: [S] = [.equipment, .tasks, .procedures, .vessels]           // A, B, C, D
        #expect(S.dropOrder(d, dragged: .equipment, onto: .procedures) == [.tasks, .procedures, .equipment, .vessels])
        #expect(S.dropOrder(d, dragged: .vessels, onto: .tasks) == [.equipment, .vessels, .tasks, .procedures])
        #expect(S.dropOrder(d, dragged: .tasks, onto: .tasks) == nil)
        #expect(S.dropOrder(d, dragged: .procedures, onto: .equipment) == [.procedures, .equipment, .tasks, .vessels])
    }

    // TV: 03 §7.1 "Selected tab restore (Mac, fixed)" — W-1
    @Test func selectedTabRestore() {
        let order = S.applyTabOrder(["TabSire"])
        #expect(S.restoredSelection(order: order, selectedIndex: 0) == .sire)
        #expect(S.restoredSelection(order: order, selectedIndex: 99) == .sire)
        #expect(S.restoredSelection(order: S.defaultOrder, selectedIndex: 8) == .crew)
    }

    // TV: ARCH §6.9 writeTabOrder — unknown entries re-inserted after their original predecessor
    @Test func writeTabOrderPreservesUnknownEntries() {
        let all = S.defaultOrder.map(\.rawValue)
        #expect(S.writeTabOrder(S.defaultOrder, preserving: []) == all)
        // unknown after a known id follows that id wherever it moved
        let stored = ["TabEquipment", "TabFuture", "TabTasks"]
        let order: [S] = [.tasks, .equipment] + S.defaultOrder.filter { $0 != .tasks && $0 != .equipment }
        let w = S.writeTabOrder(order, preserving: stored)
        #expect(Array(w.prefix(3)) == ["TabTasks", "TabEquipment", "TabFuture"])
        #expect(w.count == 14)
        // unknown at the front stays at the front; chains of unknowns keep their order
        let w2 = S.writeTabOrder(S.defaultOrder, preserving: ["X1", "X2", "TabMap", "X3"])
        #expect(Array(w2.prefix(2)) == ["X1", "X2"])
        let mapIdx = w2.firstIndex(of: "TabMap")!
        #expect(w2[mapIdx + 1] == "X3")
        #expect(w2.count == 16)
        // round trip: re-applying never loses the unknown names and yields the same known order
        #expect(S.applyTabOrder(w2) == S.defaultOrder)
        // duplicate unknowns are kept
        #expect(S.writeTabOrder([.sire], preserving: ["TabSire", "Y", "Y"]).filter { $0 == "Y" }.count == 2)
    }

    @Test func titlesSymbolsKinds() {
        #expect(S.crew.rawValue == "CrewTab")
        #expect(S.map.title == "Relationship Map")
        #expect(S.sire.title == "SIRE 2.0")
        #expect(S.procedures.symbol == "list.number")
        #expect(S.vessels.itemKind == .vessel)
        #expect(S.section(for: .procedure) == .procedures)
        #expect(S.board.newItemTitle == "New Task…")
        #expect(S.calendar.newItemTitle == nil)
    }
}

@Suite struct ShellTabColorTests {
    // TV: 03 §7.1 "Tab contrast"
    @Test func contrast() {
        let rows: [(String, Bool)] = [("#FFFFFF", true), ("#1E88E5", false), ("#FDD835", true), ("#FB8C00", true),
                                      ("#7CB342", false), ("#00FF00", false), ("#969696", false), ("#979797", true),
                                      ("#80FF0000", false)]
        for (hex, black) in rows {
            #expect(ShellTabColor.textIsBlack(ShellTabColor.parse(hex)!) == black, "\(hex)")
        }
    }

    // TV: 03 §7.1 "TryBrush for tabs", "Colour picker output"
    @Test func parsingAndPicker() {
        #expect(ShellTabColor.parse("#12345") == nil)
        let t = ShellTabColor.parse("transparent")!
        #expect(t == ARGB(a: 0, r: 255, g: 255, b: 255))
        #expect(ShellTabColor.textIsBlack(t))
        #expect(ShellTabColor.hex(red: 0.5, green: 0.25, blue: 1.0) == "#8040FF")
    }
}

@Suite struct ShellPickerSelectionTests {
    let rows = ["Pump 1", "Pump 2", "Valve A", "Valve B", "Engine"]

    // TV: 07 VIEW-208 pre-selection order and toggles
    @Test func multiSelectionOrder() {
        var s = ShellPickerSelection(displays: rows, preselected: [3, 0], single: false)
        #expect(s.order == [0, 3])                         // candidate order, not preselect order
        s.toggle(4); s.toggle(1)
        #expect(s.order == [0, 3, 4, 1])
        s.toggle(0)
        #expect(s.order == [3, 4, 1])
        s.toggle(0)                                        // re-tick appends at the end
        #expect(s.order == [3, 4, 1, 0])
    }

    // TV: 07 VIEW-210 hidden selections keep their place; footer texts
    @Test func filteringKeepsSelections() {
        var s = ShellPickerSelection(displays: rows, preselected: [], single: false)
        s.toggle(0)
        s.query = " valve "
        #expect(s.visible == [2, 3])
        s.toggle(3)
        #expect(s.footer == "2 selected · 1 hidden by search")
        s.query = ""
        #expect(s.order == [0, 3])
        #expect(s.footer == "2 selected")
        s.query = "pump"
        s.selectAllVisible()
        #expect(s.order == [0, 3, 1])
    }

    // TV: 07 VIEW-211 single mode
    @Test func singleMode() {
        var s = ShellPickerSelection(displays: rows, preselected: [4, 2], single: true)
        #expect(s.order == [2])
        s.toggle(1)
        #expect(s.order == [1])
        s.query = "valve"
        #expect(s.order == [1])                            // the hidden choice survives
        var e = ShellPickerSelection(displays: rows, preselected: [], single: true)
        #expect(!e.canConfirm)
        e.toggle(0)
        #expect(e.canConfirm)
        #expect(s.result(candidateOrder: false) == [1])
    }

    // TV: 07 VIEW-212 row 23 (candidate order) and VIEW-216 (equal displays stay distinct rows)
    @Test func candidateOrderAndDuplicates() {
        var s = ShellPickerSelection(displays: ["a", "a", "b"], preselected: [0, 1, 2], single: false)
        s.toggle(0); s.toggle(0)
        #expect(s.result(candidateOrder: false) == [1, 2, 0])
        #expect(s.result(candidateOrder: true) == [0, 1, 2])
    }
}
