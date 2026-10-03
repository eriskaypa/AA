// The list-command states W-BUILD's views publish (03 §6.5.1.10 roles builderItems / savedLists / steps), checked
// against F3's router decision table: T-KB-32 (builder ⌃⌘↑) and T-KB-33 (Saved Lists with Sort A–Z on) (W-BUILD).
import Foundation
import Testing
@testable import AACore

@Suite struct BuilderCommandTests {
    typealias R = CommandRouterCore

    private func ctx(_ section: SectionID, sheet: Bool = false, _ list: ShellListState) -> CommandContext {
        var c = CommandContext()
        c.section = section
        c.keyWinIsSheetOrModal = sheet
        c.list = list
        return c
    }

    @Test func builderSheetPublishesMovableSelection() {
        // TV: 03 T-KB-32 — the builder (a close-type sheet) with rows [2,3] of 5 selected: ⌃⌘↑ moves the list rows.
        let s = ShellListState(role: "builderItems", selectionCount: 2, deleteTitle: "Delete", hasDelete: true,
                               canMoveUp: true, canMoveDown: true, hasMove: true, hasMoveTo: true, hasPrimary: true)
        #expect(R.state(.moveUp, ctx(.procedures, sheet: true, s)).effect == .listMove(up: true))
        #expect(R.state(.moveTo, ctx(.procedures, sheet: true, s)).enabled)
    }

    @Test func savedListsWithSortAZDisableArranging() {
        // TV: 03 T-KB-33 — what SavedListsTabView publishes while Sort A-Z is on: move handler present, but no
        // movable selection and no Move-to picker.
        let s = ShellListState(role: "savedLists", selectionCount: 1, deleteTitle: "Delete", hasDelete: true,
                               canMoveUp: false, canMoveDown: false, hasMove: true, hasMoveTo: false, hasPrimary: true)
        #expect(!R.state(.moveUp, ctx(.lists, s)).enabled)
        #expect(!R.state(.moveDown, ctx(.lists, s)).enabled)
        #expect(!R.state(.moveTo, ctx(.lists, s)).enabled)
        #expect(R.state(.delete, ctx(.lists, s)).enabled)
    }
}
