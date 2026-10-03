// Regression tests for the round-2 verification findings on the hierarchy sidebar:
// V2-COMPAT — items sharing an Id each keep their own row (HierRowKey);
// V2-SCALE — the reveal target of a selected row (HIER-120/121, §3.2 `SelectItemsByIds` "reveals the first").
import Foundation
import Testing
@testable import AACore

@Suite struct HierRowKeyTests {
    // Unique ids are their own keys; later items sharing an id get distinct, stable derived keys.
    @Test func keysForDuplicateIDs() {
        let a = G(1), b = G(2)
        let keys = HierRowKey.keys(for: [a, b, a, a])
        #expect(keys[0] == a && keys[1] == b)
        #expect(keys[2] != a && keys[3] != a && keys[2] != keys[3])
        #expect(Set(keys).count == 4)
        #expect(HierRowKey.keys(for: [a, b, a, a]) == keys)                 // deterministic across rebuilds
        #expect(keys[2] == HierRowKey.derived(a, occurrence: 1))
        #expect(HierRowKey.keys(for: [a, b]) == [a, b])                     // well-formed data is unchanged
    }

    // Journey (V2-COMPAT snaphostile): Tasks[0] duplicated under the same Id and renamed "… (DUP)" — the list shows
    // both rows, each with its own name and its own selection key.
    @Test func duplicateIDsKeepTheirOwnRows() {
        let g = HierSidebarGroup(id: G(100), name: "Engine room")
        let items = [HierSidebarItem(id: G(1), name: "Change main engine lube oil filter", groupID: g.id),
                     HierSidebarItem(id: G(2), name: "Purifier bowl clean", groupID: g.id),
                     HierSidebarItem(id: G(1), name: "Change main engine lube oil filter (DUP)", groupID: g.id)]
        let s = HierSidebarBuilder.build(kind: .task, items: items, groups: [g], query: "", sortAZ: false)
        let rows = s.sections[0].rows
        #expect(rows.count == 3 && s.sections[0].count == 3)
        #expect(Set(rows.map(\.id)).count == 3)                               // distinct List identities
        let keys = HierRowKey.keys(for: items.map(\.id))
        let nameByKey = Dictionary(uniqueKeysWithValues: zip(keys, items.map(\.name)))
        #expect(rows.compactMap { $0.itemID.flatMap { nameByKey[$0] } }
                == ["Change main engine lube oil filter", "Purifier bowl clean",
                    "Change main engine lube oil filter (DUP)"])
        #expect(s.visibleItemIDs == keys)
        #expect(rows[0].itemID == G(1))                                       // the first keeps its real Id

        // A→Z and search keep each duplicate's own key.
        let az = HierSidebarBuilder.build(kind: .task, items: items, groups: [g], query: "", sortAZ: true)
        #expect(az.sections[0].rows.compactMap(\.itemID) == [keys[0], keys[2], keys[1]])
        let found = HierSidebarBuilder.build(kind: .task, items: items, groups: [g], query: "(DUP)", sortAZ: false)
        #expect(found.visibleItemIDs == [keys[2]])
    }

    // V2-SCALE: the reveal scrolls to the row itself, or to its section header when the group is collapsed.
    @Test func revealTarget() {
        let g = HierSidebarGroup(id: G(100), name: "Navigation")
        let items = (0..<300).map { HierSidebarItem(id: G($0 + 1), name: "Equipment \($0)",
                                                     groupID: $0 >= 150 ? g.id : nil) }
        let s = HierSidebarBuilder.build(kind: .equipment, items: items, groups: [g], query: "", sortAZ: false)
        let target = G(200)
        #expect(s.revealRowID(for: target) { _ in true } == target.netString)
        #expect(s.revealRowID(for: target) { _ in false } == HierSidebar.headerRowID("group:\(g.id.netString)"))
        #expect(s.revealRowID(for: G(5)) { $0.groupID != nil } == HierSidebar.headerRowID("ungrouped"))
        #expect(s.revealRowID(for: G(9_999)) { _ in true } == nil)
        // The target row's List identity is the one the reveal scrolls to.
        #expect(s.sections.flatMap(\.rows).contains { $0.id == target.netString })
    }
}
