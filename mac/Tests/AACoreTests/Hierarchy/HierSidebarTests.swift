// Tests for 04 §7.7 (sidebar build), HIER-005/006/010…015, §3.1 Mac decisions, §8 Q-02/Q-03/Q-11/Q-12/Q-30,
// DECISIONS 04 Q-E; HIER-013/015/121 Ui keys.
import Foundation
import Testing
@testable import AACore

@Suite struct HierSidebarTests {
    func item(_ n: Int, _ name: String, group: UUID? = nil, tags: [String] = []) -> HierSidebarItem {
        HierSidebarItem(id: G(n), name: name, groupID: group, tags: tags)
    }

    func names(_ s: HierSidebarSection, _ items: [HierSidebarItem]) -> [String] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.name) })
        return s.rows.compactMap { $0.itemID.flatMap { byID[$0] } }
    }

    // TV: 04 §7.7 row 1 — groups by name, Ungrouped last
    @Test func sectionOrder() {
        let beta = HierSidebarGroup(id: G(100), name: "beta"), alpha = HierSidebarGroup(id: G(101), name: "Alpha")
        let items = [item(1, "x", group: beta.id), item(2, "y"), item(3, "z", group: alpha.id)]
        let s = HierSidebarBuilder.build(kind: .task, items: items, groups: [beta, alpha], query: "", sortAZ: false)
        #expect(s.sections.map(\.title) == ["Alpha", "beta", "Ungrouped"])
        #expect(names(s.sections[0], items) == ["z"] && names(s.sections[1], items) == ["x"])
        #expect(names(s.sections[2], items) == ["y"])
        #expect(s.sections.map(\.count) == [1, 1, 1])
        #expect(s.visibleItemIDs == [G(3), G(1), G(2)])
        #expect(s.emptyHint == nil)
    }

    // TV: 04 §7.7 rows 2–3 — data order vs A→Z (ordinal upper)
    @Test func rowOrder() {
        let items = [item(1, "b"), item(2, "A"), item(3, "c")]
        let off = HierSidebarBuilder.build(kind: .task, items: items, groups: [], query: "", sortAZ: false)
        #expect(off.sections.count == 1 && off.sections[0].title == "Ungrouped")
        #expect(names(off.sections[0], items) == ["b", "A", "c"])
        let on = HierSidebarBuilder.build(kind: .task, items: items, groups: [], query: "", sortAZ: true)
        #expect(names(on.sections[0], items) == ["A", "b", "c"])
        let odd = ["_x", "Zed", "apple", "10", "9"].enumerated().map { item($0.offset + 1, $0.element) }
        let az = HierSidebarBuilder.build(kind: .task, items: odd, groups: [], query: "", sortAZ: true)
        #expect(names(az.sections[0], odd) == ["10", "9", "apple", "Zed", "_x"])
    }

    // Q-12 — A→Z is stable (equal keys keep data order, even for long lists)
    @Test func stableSort() {
        let items = (1...40).map { item($0, $0 % 2 == 0 ? "same" : "SAME") }
        let s = HierSidebarBuilder.build(kind: .equipment, items: items, groups: [], query: "", sortAZ: true)
        #expect(s.sections[0].rows.compactMap(\.itemID) == items.map(\.id))
    }

    // TV: 04 §7.7 — empty group placeholder (count 0, Q-02), hidden while searching (Q-03)
    @Test func emptyGroupPlaceholder() {
        let spare = HierSidebarGroup(id: G(100), name: "Spare")
        let items = [item(1, "Fuel pump"), item(2, "Boiler")]
        let idle = HierSidebarBuilder.build(kind: .equipment, items: items, groups: [spare], query: "", sortAZ: false)
        #expect(idle.sections.map(\.title) == ["Spare", "Ungrouped"])
        #expect(idle.sections[0].count == 0 && idle.sections[0].rows.count == 1 && idle.sections[0].rows[0].isPlaceholder)
        let search = HierSidebarBuilder.build(kind: .equipment, items: items, groups: [spare], query: "pump", sortAZ: false)
        #expect(search.sections.map(\.title) == ["Ungrouped"])
    }

    // TV: 04 §7.7 — query trimmed, case-insensitive, Name only; `#tag` (Q-E) matches tags
    @Test func searching() {
        let items = [item(1, "Fuel pump", tags: ["engine"]), item(2, "Boiler", tags: ["pump"])]
        let s = HierSidebarBuilder.build(kind: .equipment, items: items, groups: [], query: "  PuMp ", sortAZ: false)
        #expect(s.visibleItemIDs == [G(1)])
        let t = HierSidebarBuilder.build(kind: .equipment, items: items, groups: [], query: "#pump", sortAZ: false)
        #expect(t.visibleItemIDs == [G(2)])
        let none = HierSidebarBuilder.build(kind: .equipment, items: items, groups: [], query: "zzz", sortAZ: false)
        #expect(none.sections.isEmpty && none.emptyHint == "No items match your search.")
    }

    // TV: 04 §7.7 — a missing group id, or a group of another kind, lands in Ungrouped
    @Test func missingGroupIsUngrouped() {
        let items = [item(1, "a", group: G(999))]
        let s = HierSidebarBuilder.build(kind: .task, items: items, groups: [], query: "", sortAZ: false)
        #expect(s.sections.map(\.title) == ["Ungrouped"] && s.visibleItemIDs == [G(1)])
    }

    // §3.1 Mac decisions — sections by Id (Q-11), duplicate ids first-wins, creation-order ties
    @Test func sectionsByID() {
        let a1 = HierSidebarGroup(id: G(100), name: "Deck"), a2 = HierSidebarGroup(id: G(101), name: "deck")
        let fake = HierSidebarGroup(id: G(102), name: "Ungrouped"), dup = HierSidebarGroup(id: G(100), name: "Other")
        let items = [item(1, "x", group: a2.id), item(2, "y", group: a1.id), item(3, "z", group: fake.id), item(4, "w")]
        let s = HierSidebarBuilder.build(kind: .task, items: items, groups: [a1, a2, fake, dup], query: "", sortAZ: false)
        #expect(s.sections.map(\.title) == ["Deck", "deck", "Ungrouped", "Ungrouped"])
        #expect(s.sections.map(\.groupID) == [G(100), G(101), G(102), nil])
        #expect(s.sections.map(\.id) == ["group:\(G(100).netString)", "group:\(G(101).netString)",
                                         "group:\(G(102).netString)", "ungrouped"])
        #expect(s.visibleItemIDs == [G(2), G(1), G(3), G(4)])
    }

    // HIER-015 — expand keys by kind enum name and section name
    @Test func expandKeys() {
        let g = HierSidebarGroup(id: G(100), name: "Engine room")
        let s = HierSidebarBuilder.build(kind: .task, items: [item(1, "a", group: g.id), item(2, "b")], groups: [g],
                                         query: "", sortAZ: false)
        #expect(s.sections.map(\.expandKey) == ["Task|Engine room", "Task|Ungrouped"])
        #expect(HierSidebarBuilder.expandKey(kind: .equipment, sectionName: "Ungrouped") == "Equipment|Ungrouped")
    }

    // HIER-006 / Q-30 — hints; HIER-M01 empty Ungrouped drop target
    @Test func hintsAndUngroupedTarget() {
        let none = HierSidebarBuilder.build(kind: .task, items: [], groups: [], query: "", sortAZ: false)
        #expect(none.sections.isEmpty && none.emptyHint?.hasPrefix("No tasks yet.") == true)
        let g = HierSidebarGroup(id: G(100), name: "Deck")
        let onlyGroups = HierSidebarBuilder.build(kind: .vessel, items: [], groups: [g], query: "", sortAZ: false)
        #expect(onlyGroups.sections.map(\.title) == ["Deck"] && onlyGroups.emptyHint?.hasPrefix("No vessels yet.") == true)
        let allGrouped = HierSidebarBuilder.build(kind: .task, items: [item(1, "a", group: g.id)], groups: [g], query: "",
                                                  sortAZ: false)
        #expect(allGrouped.sections.map(\.title) == ["Deck", "Ungrouped"] && allGrouped.sections[1].count == 0)
        let searching = HierSidebarBuilder.build(kind: .task, items: [item(1, "a", group: g.id)], groups: [g],
                                                 query: "a", sortAZ: false)
        #expect(searching.sections.map(\.title) == ["Deck"])
    }

    // HIER-019 — thousands of rows build quickly
    @Test func scale() {
        let groups = (0..<20).map { HierSidebarGroup(id: G(10_000 + $0), name: "Group \($0)") }
        let items = (0..<5_000).map { item($0, "Item \(5_000 - $0)", group: $0 % 3 == 0 ? nil : groups[$0 % 20].id) }
        let start = Date()
        let s = HierSidebarBuilder.build(kind: .task, items: items, groups: groups, query: "", sortAZ: true)
        #expect(s.visibleItemIDs.count == 5_000)
        #expect(Date().timeIntervalSince(start) < 2.0)
    }
}

@MainActor
@Suite struct HierUiStateTests {
    // TV: 04 §7.7 — collapsing Ungrouped on Tasks writes GroupExpanded["Task|Ungrouped"] = false; HIER-015 only on change
    @Test func groupExpanded() {
        let ui = UiState()
        #expect(HierUiState.isExpanded(ui, key: "Task|Ungrouped"))
        #expect(!HierUiState.setExpanded(ui, key: "Task|Ungrouped", true))                // missing = expanded: no write
        #expect(ui.groupExpanded.isEmpty)
        #expect(HierUiState.setExpanded(ui, key: "Task|Ungrouped", false))
        #expect(ui.groupExpanded["Task|Ungrouped"] == false)
        #expect(!HierUiState.setExpanded(ui, key: "Task|Ungrouped", false))
        #expect(HierUiState.setExpanded(ui, key: "Task|Ungrouped", true))
        #expect(ui.groupExpanded["Task|Ungrouped"] == true)
    }

    // HIER-013 — SortAZ per kind enum name
    @Test func sortAZ() {
        let ui = UiState()
        #expect(!HierUiState.sortAZ(ui, kind: .equipment))
        #expect(HierUiState.setSortAZ(ui, kind: .equipment, true))
        #expect(ui.sortAZ["Equipment"] == true && HierUiState.sortAZ(ui, kind: .equipment))
        #expect(!HierUiState.setSortAZ(ui, kind: .equipment, true))
        #expect(HierUiState.setSortAZ(ui, kind: .task, false))                            // writes the explicit false
        #expect(ui.sortAZ.keys == ["Equipment", "Task"])
    }

    // HIER-121 — Selected{Kind}Id
    @Test func selectedIDs() {
        let ui = UiState()
        for (n, k) in ItemKind.allKinds.enumerated() {
            HierUiState.setSelectedID(ui, kind: k, G(n + 1))
            #expect(HierUiState.selectedID(ui, kind: k) == G(n + 1))
        }
        #expect(ui.selectedEquipmentId == G(1) && ui.selectedTaskId == G(2))
        #expect(ui.selectedProcedureId == G(3) && ui.selectedVesselId == G(4))
        HierUiState.setSelectedID(ui, kind: .task, nil)
        #expect(ui.selectedTaskId == nil)
    }
}
