// Pure CommandRouter tests (F3): 03 §6.5.1.14 T-KB rows whose outcome is decided by the router table
// (CommandRouterCore). UI-only halves (the confirmation itself, the text deleting, focus moves) are Stage V checks.
import Foundation
import Testing
@testable import AACore

@Suite struct ShellRouterTests {
    typealias R = CommandRouterCore

    func ctx(_ section: SectionID = .tasks, _ f: (inout CommandContext) -> Void = { _ in }) -> CommandContext {
        var c = CommandContext()
        c.section = section
        f(&c)
        return c
    }

    let sidebar3 = ShellListState(role: "hierarchySidebar", selectionCount: 3, deleteTitle: "Move to Trash",
                                  hasDelete: true, hasPrimary: true)

    // TV: T-KB-01 — text focused → Delete family disabled; step F forwards the text meaning
    @Test func tkb01() {
        let c = ctx { $0.responder = .text(hasSelection: false, editable: true); $0.list = sidebar3 }
        #expect(R.state(.deleteFamily, c) == CommandDecision(enabled: false, title: "Delete"))
        #expect(R.perform(.deleteFamily, c) == .forwardText("deleteToBeginningOfLine:"))
        let sel = ctx { $0.responder = .text(hasSelection: true, editable: true) }
        #expect(R.perform(.deleteFamily, sel) == .forwardText("delete:"))
    }

    // TV: T-KB-02 / T-KB-03 — sidebar with 3 selected → "Move to Trash"
    @Test func tkb02() {
        let d = R.state(.deleteFamily, ctx { $0.list = sidebar3 })
        #expect(d.enabled && d.title == "Move to Trash" && d.effect == .listDelete)
    }

    // TV: T-KB-04 — file bank in an item window → "Remove"
    @Test func tkb04() {
        let id = UUID()
        let fb = ShellListState(role: "fileBank", selectionCount: 2, deleteTitle: "Remove", hasDelete: true,
                                hasQuickLook: true)
        let d = R.state(.deleteFamily, ctx { $0.keyWin = .item(id); $0.list = fb })
        #expect(d.enabled && d.title == "Remove")
        #expect(R.state(.quickLook, ctx { $0.keyWin = .item(id); $0.list = fb }).effect == .listQuickLook)
    }

    // TV: T-KB-06 — Board column → "Delete Task"
    @Test func tkb06() {
        let col = ShellListState(role: "boardColumn", selectionCount: 1, deleteTitle: "Delete Task", hasDelete: true)
        #expect(R.state(.deleteFamily, ctx(.board) { $0.list = col }).title == "Delete Task")
    }

    // TV: T-KB-07…T-KB-11 — Find routing
    @Test func findRouting() {
        let rich = ctx { $0.responder = .richText(.container, editable: true, hasSelection: false) }
        #expect(R.state(.find, rich).effect == .richFind(.showFind))                               // 07
        #expect(R.state(.searchAll, rich).effect == .openSearch)                                   // 08
        #expect(R.state(.find, ctx { $0.list = sidebar3 }).effect == .openSearch)                  // 09
        #expect(R.state(.find, ctx { $0.responder = .text(hasSelection: false, editable: true) }).effect == .openSearch) // 10
        #expect(R.state(.find, ctx { $0.keyWin = .search }).effect == .focusSearchQuery)           // 11
        #expect(R.state(.findNext, rich).effect == .richFind(.findNext))
        #expect(!R.state(.findNext, ctx()).enabled)
        #expect(!R.state(.useSelectionForFind, rich).enabled)
    }

    // TV: T-KB-12…T-KB-14 — Search Current List
    @Test func searchCurrentList() {
        let board = ctx(.board) { $0.filterTargetAvailable = true }
        #expect(R.state(.searchCurrentList, board) == CommandDecision(enabled: true, title: "Search Current List", effect: .focusFilter))
        #expect(!R.state(.searchCurrentList, ctx(.calendar) { $0.filterTargetAvailable = false }).enabled)
        #expect(!R.state(.searchCurrentList, ctx(.board) { $0.filterTargetAvailable = true; $0.filterTargetFocused = true }).enabled)
        #expect(R.state(.searchCurrentList, ctx(.vessels) { $0.filterTargetAvailable = true }).enabled)
        #expect(!R.state(.searchCurrentList, ctx { $0.keyWin = .unitConverter; $0.filterTargetAvailable = true }).enabled)
    }

    // TV: T-KB-15…T-KB-20 — Undo routing
    @Test func undoRouting() {
        let typing = ctx {
            $0.responder = .richText(.container, editable: true, hasSelection: false)
            $0.responderUndo = ShellUndoState(canUndo: true, undoTitle: "Undo Typing")
            $0.pendingUndoCount = 4
        }
        #expect(R.state(.undo, typing) == CommandDecision(enabled: true, title: "Undo Typing", effect: .textUndo))   // 15
        #expect(R.state(.undo, ctx { $0.list = sidebar3 }) == CommandDecision(enabled: false, title: "Undo"))          // 16
        #expect(R.state(.undo, ctx { $0.pendingUndoCount = 1 }) == CommandDecision(enabled: true, title: "Undo Move to Trash", effect: .undoDelete)) // 17
        #expect(R.state(.undo, ctx { $0.pendingUndoCount = 7 }).title == "Undo Move to Trash (7 Items)")               // 18
        #expect(!R.state(.undo, ctx { $0.pendingUndoCount = 3; $0.safeMode = true }).enabled)                          // 19
        let item = R.state(.undo, ctx { $0.keyWin = .item(UUID()); $0.pendingUndoCount = 3 })                           // 20
        #expect(!item.enabled && item.effect == .windowUndo)
        #expect(!R.state(.redo, ctx()).enabled)
    }

    // TV: T-KB-21, T-KB-22 — ⌘T Show Fonts only in rich text; ⇧⌘T Today in the Planner
    @Test func showFontsAndToday() {
        #expect(R.state(.showFonts, ctx { $0.responder = .richText(.container, editable: true, hasSelection: false) }).effect == .richFormat(.showFonts))
        let planner = ctx(.planner) { $0.plannerCommandsAvailable = true }
        #expect(!R.state(.showFonts, planner).enabled)
        #expect(R.state(.plannerToday, planner).effect == .run)
        #expect(R.state(.plannerPrevious, planner).enabled)
        let typing = ctx(.planner) { $0.plannerCommandsAvailable = true; $0.responder = .text(hasSelection: false, editable: true) }
        #expect(!R.state(.plannerPrevious, typing).enabled)
        #expect(R.perform(.plannerPrevious, typing) == .forwardText("moveToBeginningOfLine:"))
        #expect(R.perform(.plannerNext, typing) == .forwardText("moveToEndOfLine:"))
        #expect(R.state(.plannerToday, typing).enabled)
    }

    // TV: T-KB-26 … T-KB-28 — Bigger/Smaller routing
    @Test func textSize() {
        var scale = 15.0
        var steps: [Double] = []
        for _ in 0..<9 {
            let c = ctx(.calendar) { $0.calendarFontScale = scale; $0.canSetCalendarFontScale = true }
            guard case .calendarFontScale(let s) = R.state(.bigger, c).effect else { Issue.record("no step"); return }
            steps.append(s); scale = s
        }
        #expect(steps == [16.5, 18, 19.5, 21, 22.5, 24, 25.5, 27, 28])
        let at = ctx(.calendar) { $0.calendarFontScale = 28; $0.canSetCalendarFontScale = true }
        #expect(R.state(.bigger, at) == CommandDecision(enabled: true, title: "Bigger", effect: .calendarFontScale(28)))
        let twelve = ctx(.calendar) { $0.calendarFontScale = 12; $0.canSetCalendarFontScale = true }
        #expect(R.state(.smaller, twelve).effect == .calendarFontScale(11))                                      // 27
        let editor = ctx(.calendar) { $0.responder = .richText(.container, editable: true, hasSelection: true); $0.calendarFontScale = 12; $0.canSetCalendarFontScale = true }
        #expect(R.state(.bigger, editor).effect == .richFontStep(bigger: true))                                  // 28
        #expect(!R.state(.bigger, ctx(.calendar) { $0.responder = .richText(.sireBody, editable: true, hasSelection: false) }).enabled)
        #expect(!R.state(.bigger, ctx(.tasks)).enabled)
    }

    // TV: T-KB-29, T-KB-30 — ⌘R is CMD (due-dates) even in the editor; ⌘} aligns right
    @Test func dueDatesAndAlign() {
        let rich = ctx { $0.responder = .richText(.container, editable: true, hasSelection: false) }
        #expect(R.state(.dueDates, rich).effect == .run)
        #expect(R.state(.alignRight, rich).effect == .richFormat(.alignRight))
    }

    // TV: T-KB-31 … T-KB-34 — Move Up/Down/To
    @Test func moveRouting() {
        let rich = ctx { $0.responder = .richText(.container, editable: true, hasSelection: false) }
        #expect(R.state(.moveUp, rich).effect == .richMove(up: true))                                         // 31
        let builder = ShellListState(role: "builderItems", selectionCount: 2, hasDelete: true, canMoveUp: true,
                                     canMoveDown: true, hasMove: true, hasMoveTo: true)
        #expect(R.state(.moveUp, ctx { $0.keyWinIsSheetOrModal = true; $0.list = builder }).effect == .listMove(up: true)) // 32
        let sortedAZ = ShellListState(role: "savedLists", selectionCount: 1, hasMove: false, hasMoveTo: false)
        #expect(!R.state(.moveUp, ctx(.lists) { $0.list = sortedAZ }).enabled)                                // 33
        #expect(!R.state(.moveTo, ctx(.lists) { $0.list = sortedAZ }).enabled)
        let name = ctx { $0.responder = .text(hasSelection: false, editable: true); $0.list = builder }      // 34
        #expect(!R.state(.moveTo, name).enabled && !R.state(.moveUp, name).enabled)
        #expect(R.perform(.moveTo, name) == .beep)
    }

    // TV: T-KB-35, T-KB-36 — New {Kind}
    @Test func newKind() {
        let tasks = ctx(.tasks) { $0.newItemAvailable = true; $0.responder = .richText(.container, editable: true, hasSelection: false) }
        #expect(R.state(.newItem, tasks) == CommandDecision(enabled: true, title: "New Task", effect: .run))   // 35
        #expect(R.state(.newItem, ctx(.calendar) { $0.newItemAvailable = true }) == CommandDecision(enabled: false, title: "New Item")) // 36
        #expect(R.state(.newItem, ctx(.buckets) { $0.newItemAvailable = true }).title == "New Bucket…")
        #expect(R.state(.newItem, ctx(.tasks) { $0.newItemAvailable = true; $0.safeMode = true }).enabled)
    }

    // TV: T-KB-37, T-KB-58 — sections by display position, also while typing
    @Test func sections() {
        let typing = ctx { $0.responder = .richText(.container, editable: true, hasSelection: false) }
        #expect(R.state(.section7, typing).effect == .selectSection(.planner))
        #expect(R.state(.bulletedList, typing).effect == .richFormat(.bulletedList))
        #expect(R.state(.numberedList, typing).effect == .richFormat(.numberedList))
        let sireFirst = ctx { $0.sectionOrder = SectionID.applyTabOrder(["TabSire"]) }
        #expect(R.state(.section1, sireFirst) == CommandDecision(enabled: true, title: "SIRE 2.0", effect: .selectSection(.sire)))
        let checked = R.state(.section2, ctx(.tasks))
        #expect(checked.checked && checked.title == "Tasks")
        #expect(R.state(.nextSection, ctx(.sire)).effect == .selectSection(.equipment))     // wraps
        #expect(R.state(.previousSection, ctx(.equipment)).effect == .selectSection(.sire))
    }

    // TV: T-KB-38 — a prompt sheet on main disables ⌘S / ⌘1 / ⌘N
    @Test func modalSuppression() {
        let sheet = ctx { $0.keyWinIsSheetOrModal = true; $0.decisionSheetOpen = true }
        for c: CommandID in [.save, .section1, .quickWork, .dueDates, .newItem, .searchAll, .lockNow] {
            #expect(!R.state(c, sheet).enabled, "\(c)")
        }
        #expect(R.state(.quit, sheet).enabled)
        #expect(R.state(.keyboardShortcuts, sheet).enabled)
        #expect(!R.state(.close, sheet).enabled)                                             // T-KB-44: decision sheet beeps
        #expect(R.state(.find, ctx { $0.keyWinIsSheetOrModal = true; $0.responder = .richText(.container, editable: true, hasSelection: false) }).enabled)
    }

    // TV: T-KB-49 … T-KB-51 — Export as PDF / Print target
    @Test func exportTarget() {
        let id = UUID()
        #expect(R.state(.exportPDF, ctx { $0.keyWin = .item(id) }).effect == .run)                             // 49
        #expect(!R.state(.exportPDF, ctx { $0.keyWin = .item(id); $0.itemWindowGated = true }).enabled)
        let detached = ctx { $0.hierSelection = ShellHierarchySelection(primary: id, count: 1, gated: false, detached: true) }
        #expect(!R.state(.exportPDF, detached).enabled && !R.state(.print, detached).enabled)                   // 50
        let gated = ctx { $0.hierSelection = ShellHierarchySelection(primary: id, count: 1, gated: true, detached: false) }
        #expect(!R.state(.exportPDF, gated).enabled)                                                            // 51
        let ok = ctx { $0.hierSelection = ShellHierarchySelection(primary: id, count: 1) }
        #expect(R.state(.exportPDF, ok).enabled)
        #expect(!R.state(.exportPDF, ctx(.calendar) { $0.hierSelection = ShellHierarchySelection(primary: id, count: 1) }).enabled)
    }

    // TV: T-KB-52 — ⌘S saves while the editor holds a locked selection (CMD class)
    @Test func saveIsCommandClass() {
        #expect(R.state(.save, ctx { $0.responder = .richText(.container, editable: true, hasSelection: true) }).effect == .run)
    }

    // TV: T-KB-53 — SIRE body: only B/I/U are enabled
    @Test func sireBody() {
        let sire = ctx(.sire) { $0.responder = .richText(.sireBody, editable: true, hasSelection: true) }
        #expect(R.state(.bold, sire).enabled && R.state(.italic, sire).enabled && R.state(.underline, sire).enabled)
        #expect(!R.state(.strikethrough, sire).enabled)
        #expect(!R.state(.deleteFamily, sire).enabled)
        let viewer = ctx { $0.responder = .richText(.viewer, editable: false, hasSelection: true) }
        #expect(!R.state(.bold, viewer).enabled)
        #expect(R.state(.find, viewer).effect == .richFind(.showFind))
    }

    // TV: T-KB-54 — login phase
    @Test func loginPhase() {
        let login = ctx { $0.phase = .login; $0.keyWin = .login }
        for c: CommandID in [.save, .find, .section1, .searchAll, .keyboardShortcuts, .settings] {
            #expect(!R.state(c, login).enabled, "\(c)")
        }
        #expect(R.state(.quit, login).enabled && R.state(.about, login).enabled)
        let typing = ctx { $0.phase = .login; $0.responder = .text(hasSelection: false, editable: true)
            $0.responderUndo = ShellUndoState(canUndo: true, undoTitle: "Undo Typing") }
        #expect(R.state(.undo, typing).enabled)
    }

    // SHELL-507 safe mode and the other enablement rules
    @Test func miscRules() {
        #expect(R.state(.save, ctx { $0.safeMode = true }).enabled)                                 // shows D4
        #expect(R.state(.encryptLocalData, ctx { $0.encryptLocalData = true }).checked)
        #expect(!R.state(.checkSharedSaveNow, ctx()).enabled)
        #expect(R.state(.checkSharedSaveNow, ctx { $0.sharedSaveConfigured = true }).enabled)
        #expect(!R.state(.recoverConflictCopies, ctx()).enabled)
        #expect(!R.state(.driveUpload, ctx { $0.inFlight = [.check] }).enabled)
        #expect(R.state(.driveUpload, ctx { $0.inFlight = [.push] }).enabled)
        #expect(!R.state(.quickSwitcher, ctx { $0.hasRepo = false }).enabled)
        #expect(!R.state(.vesselImportWorkOrders, ctx(.vessels)).enabled)
        #expect(R.state(.vesselImportWorkOrders, ctx(.vessels) { $0.vesselMenuAvailable = true }).enabled)
        #expect(!R.state(.rename, ctx { $0.hierSelection = ShellHierarchySelection(primary: UUID(), count: 1); $0.renameAvailable = true; $0.responder = .text(hasSelection: false, editable: true) }).enabled)
        #expect(R.state(.rename, ctx { $0.hierSelection = ShellHierarchySelection(primary: UUID(), count: 1); $0.renameAvailable = true }).enabled)
        #expect(R.state(.darkMode, ctx { $0.darkMode = true }).checked)
        #expect(R.state(.shortcutBar, ctx()).checked)
        #expect(R.isTextClass(.deleteFamily) && !R.isTextClass(.save))
    }
}
