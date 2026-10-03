// Tests for 04 §7.1 (TagParser), §7.9 (safe file names), §7.12 (messages), HIER-058 (lock dialog validation),
// §3.5 (duration text), HIER-001/006 (titles and hints), DECISIONS 04 Q-A / Q-E.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct HierTagAndTextTests {
    // TV: 04 §7.1 — main-pane parser
    @Test func tagParserVectors() {
        #expect(TagParser.parse("pump, #Engine;  main\tpump") == ["pump", "Engine", "main"])
        #expect(TagParser.parse("##a b") == ["a", "b"])
        #expect(TagParser.parse("#") == [])
        #expect(TagParser.parse(", ,;") == [])
        #expect(TagParser.parse("") == [])
        #expect(TagParser.parse("a,A,a") == ["a"])
        #expect(TagParser.parse("Été été ÉTÉ") == ["Été"])
        #expect(TagParser.parse("x\r\ny") == ["x", "y"])
    }

    // TV: 04 §7.1 — display join and the Windows item-window parser
    @Test func tagDisplayAndCommaOnly() {
        #expect(TagParser.display(["a", "b"]) == "a, b")
        #expect(TagParser.display([]) == "")
        #expect(TagParser.parseCommaOnly("#a b, c ,,d, c") == ["#a b", "c", "d", "c"])
    }

    @Test func tagParserEdgeCases() {
        // Only U+0020 splits; other white space is trimmed from the parts (TrimEntries).
        #expect(TagParser.parse("a\u{00A0}b") == ["a\u{00A0}b"])
        #expect(TagParser.parse("\u{3000}x\u{3000},y") == ["x", "y"])
        // Leading # only; inner and trailing # kept.
        #expect(TagParser.parse("#c#, d#") == ["c#", "d#"])
        // First spelling wins.
        #expect(TagParser.parse("Pump PUMP pump") == ["Pump"])
        // Round trip through the display normalisation.
        #expect(TagParser.parse(TagParser.display(["safety", "drill"])) == ["safety", "drill"])
    }

    // DECISIONS 04 Q-E — `#tag` sidebar search
    @Test func hashQueryMatching() {
        let tags = ["machinery", "Engine"]
        #expect(TagParser.matches(tags, hashQuery: "#engine"))
        #expect(TagParser.matches(tags, hashQuery: "#eng"))
        #expect(TagParser.matches(tags, hashQuery: "##MACH"))
        #expect(!TagParser.matches(tags, hashQuery: "#pump"))
        #expect(TagParser.matches(tags, hashQuery: "#"))
        #expect(TagParser.matches(tags, hashQuery: "#eng #mach"))
        #expect(!TagParser.matches(tags, hashQuery: "#eng #pump"))
        #expect(!TagParser.matches([], hashQuery: "#a"))
        #expect(TagParser.isHashQuery("#a") && !TagParser.isHashQuery("a#"))
    }

    // TV: 04 §7.9
    @Test func safeFileNames() {
        #expect(HierExportName.itemPDF(kind: .task, name: "Pump: A/B?") == "Task-Pump_ A_B_.pdf")
        #expect(HierExportName.checklist(name: "Fire drill", ext: "xlsx") == "checklist-Fire drill.xlsx")
        #expect(HierExportName.itemPDF(kind: .vessel, name: "") == "Vessel-.pdf")
        #expect(HierExportName.safe("a\tb") == "a_b")
        #expect(HierExportName.safe("\"<>|:*?\\/") == "_________")
        #expect(HierExportName.safe("  dots. & ⚓ ") == "  dots. & ⚓ ")
        #expect(HierExportName.itemPDF(kind: .equipment, name: "Engine room") == "Equipment-Engine room.pdf")
    }

    // TV: 04 §7.12 — messages
    @Test func messages() {
        #expect(BatchDelete.statusAfterDelete(count: 1, firstName: "Pump") == "'Pump' moved to Trash — ⌘Z to undo.")
        #expect(BatchDelete.statusAfterDelete(count: 4, firstName: "x") == "4 items moved to Trash — ⌘Z to undo them all.")
        #expect(HierText.moveToGroupTitle(count: 1, firstName: "Pump") == "Move 'Pump' to group")
        #expect(HierText.moveToGroupTitle(count: 3, firstName: "Pump") == "Move 3 items to group")
        #expect(HierText.wrongPassword == "Wrong password. Use the entry's password or the master password (“redemption”).")
        #expect(HierText.unlockedStatus("Pump") == "'Pump' unlocked for this session.")
        #expect(HierText.lockedAgainStatus("Pump") == "'Pump' locked again — the password is needed to open it.")
        #expect(HierText.nowLockedStatus("Pump") == "'Pump' is now locked.")
        #expect(HierText.hint(nil) == "(No hint was set.)" && HierText.hint("  ") == "(No hint was set.)")
        #expect(HierText.hint("usual") == "Hint: usual")
        #expect(HierText.confirmDeleteGroup("Spare") == "Delete group 'Spare'?")
        #expect(HierText.groupCreated("Deck").hasPrefix("Group 'Deck' created."))
        #expect(HierText.setDeadlinePrompt(1) == "Apply one deadline to 1 selected item:")
        #expect(HierText.setDeadlinePrompt(3) == "Apply one deadline to 3 selected items:")
        #expect(HierText.itemWindowTitle(kind: .task, name: "") == "Task — (unnamed)")
        #expect(HierText.itemWindowTitle(kind: .equipment, name: "Pump") == "Equipment — Pump")
        #expect(HierText.deleteSelectedHelp == "Move every selected item to the Trash. Restore from File ▸ Trash, or undo with ⌘Z.")
        #expect(HierText.tagsHelp.hasSuffix("the quick switcher (⌘O)."))
    }

    // TV: 04 HIER-001, HIER-006, HIER-050
    @Test func titlesAndHints() {
        #expect(HierText.pageTitle(.equipment) == "Equipment/Area" && HierText.pageTitle(.task) == "Tasks")
        #expect(HierText.pageTitle(.procedure) == "Procedures" && HierText.pageTitle(.vessel) == "Vessels")
        #expect(HierText.pageTitle(ItemKind(rawValue: 9)) == "Items")
        #expect(HierText.specificsHeader(.equipment) == "Components / Procedures / Tasks")
        #expect(HierText.specificsHeader(.task) == "Schedule & Subtasks")
        #expect(HierText.specificsHeader(.procedure) == "Checklist")
        #expect(HierText.specificsHeader(.vessel) == "Specifics")
        #expect(HierText.emptyKindHint(.task) == "No tasks yet.\n\nClick “+ New” to add a task, or ⌘N for the quick-work window.")
        #expect(HierText.emptyKindHint(.equipment) == "No equipment or areas yet.\n\nClick “+ New” to add your first one.")
        #expect(HierText.emptyKindHint(.vessel).hasPrefix("No vessels yet."))
        #expect(HierText.emptyKindHint(ItemKind(rawValue: 7)) == "Nothing here yet.\n\nClick “+ New” to add one.")
        #expect(HierText.lockedTitle(.equipment) == "This equipment/area is locked.")
        #expect(HierText.lockedTitle(ItemKind(rawValue: 5)) == "This entry is locked.")
    }

    // TV: 04 §7.8 lock dialog validation (HIER-058)
    @Test func lockFormValidation() {
        #expect(HierLockForm.validate(password: "", confirm: "") == "Password cannot be empty.")
        #expect(HierLockForm.validate(password: "abc", confirm: "abc") == "Password must be at least 4 characters.")
        #expect(HierLockForm.validate(password: "abcd", confirm: "abce") == "Passwords do not match.")
        #expect(HierLockForm.validate(password: "😀😀", confirm: "😀😀") == nil)          // 4 UTF-16 units
        #expect(HierLockForm.validate(password: "abcd", confirm: "abcd") == nil)
        #expect(HierLockForm.validate(password: "abcd", confirm: "ABCD") == "Passwords do not match.")
    }

    // 04 §3.5 duration text
    @Test func durationParse() {
        #expect(HierDuration.parse("90") == 90)
        #expect(HierDuration.parse("  45 ") == 45)
        #expect(HierDuration.parse("+30") == 30)
        #expect(HierDuration.parse("0") == nil)
        #expect(HierDuration.parse("-5") == nil)
        #expect(HierDuration.parse("1,000") == nil)
        #expect(HierDuration.parse("12a") == nil)
        #expect(HierDuration.parse("") == nil && HierDuration.parse("  ") == nil && HierDuration.parse("+") == nil)
        #expect(HierDuration.parse("2147483647") == 2_147_483_647)
        #expect(HierDuration.parse("2147483648") == nil)
        #expect(HierDuration.parse("٣") == nil)                                         // non-ASCII digit
        #expect(HierDuration.parse("\t15\n") == 15)
    }

    // T-KB-02 / 03 / 24 / 35 / 36 / 49…51 — what the hierarchy pages publish drives the router as the registry says
    @Test func publishedRouterState() {
        typealias R = CommandRouterCore
        var c = CommandContext()
        c.section = .tasks
        c.list = HierCommandState.sidebarList(selectionCount: 3)
        let d = R.state(.deleteFamily, c)
        #expect(d.enabled && d.title == "Move to Trash" && d.effect == .listDelete)               // T-KB-02/03
        let id = UUID()
        c.hierSelection = HierCommandState.selection(primary: id, count: 1, gated: false, detached: false)
        c.renameAvailable = true; c.newItemAvailable = true; c.openInNewWindowAvailable = true
        #expect(R.state(.rename, c).enabled)                                                       // T-KB-24 (Rename)
        #expect(R.state(.openInNewWindow, c).enabled)                                              // T-KB-25
        #expect(R.state(.newItem, c).title == "New Task")                                          // T-KB-35
        var cal = c; cal.section = .calendar
        #expect(!R.state(.newItem, cal).enabled)                                                   // T-KB-36
        #expect(R.state(.exportPDF, c).enabled)
        c.hierSelection = HierCommandState.selection(primary: id, count: 1, gated: false, detached: true)
        #expect(!R.state(.exportPDF, c).enabled)                                                   // T-KB-50
        c.hierSelection = HierCommandState.selection(primary: id, count: 1, gated: true, detached: false)
        #expect(!R.state(.exportPDF, c).enabled)                                                   // T-KB-51
        var w = CommandContext(); w.keyWin = .item(id)
        #expect(R.state(.exportPDF, w).effect == .run)                                             // T-KB-49
    }
}
