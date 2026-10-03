// Tests for 08 §7.4 (T-SR-4 highlight clamp, T-SR-10 status), §7.6 (T-TR-1…5 through the Trash window's actions),
// §7.7 (summary line of T-DF-1 / T-DF-9), §7.3 (T-QS-11 navigation, REQ-F2-02 lock gating), 08 QUICK-102 tags.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct WindowsSearchTrashReviewTests {
    // MARK: Search

    @Test func statusText() {
        // TV: 08 T-SR-10; 02 REPO-100
        #expect(SearchWindowText.status(count: 1, query: "pump") == "1 result for \"pump\".")
        #expect(SearchWindowText.status(count: 0, query: "pump") == "No results for \"pump\".")
        #expect(SearchWindowText.status(count: 500, query: "a b") == "500 results for \"a b\".")
    }

    @Test func highlightSplitAndClamp() {
        // TV: 08 T-SR-1, T-SR-4 (BuildHighlighted clamping)
        let h = SearchHighlight.split("The main engine lube oil pump was overhauled", start: 25, length: 4)
        #expect(h.prefix == "The main engine lube oil " && h.match == "pump" && h.suffix == " was overhauled")
        let c = SearchHighlight.split("x y", start: 0, length: 4)
        #expect(c.prefix == "" && c.match == "x y" && c.suffix == "")
        let out = SearchHighlight.split("abc", start: 9, length: 1)
        #expect(out.prefix == "" && out.match == "a" && out.suffix == "bc")
        let neg = SearchHighlight.split("abc", start: 1, length: -3)
        #expect(neg.prefix == "a" && neg.match == "" && neg.suffix == "bc")
        let emoji = SearchHighlight.split("a\u{1F600}b", start: 2, length: 1)     // never split a surrogate pair
        #expect(emoji.prefix == "a" && emoji.match == "\u{1F600}" && emoji.suffix == "b")
    }

    @Test func searchWithLockGateEndToEnd() {
        // TV: 08 T-SR-8 through the window's path (documents built with the session gate, scan off-main)
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "Secret plan"); t.description = "valve codes"; t.tags = ["codes"]
        t.lockHash = "h"; t.lockSalt = "s"
        store.data.tasks = [t]
        let locks = ItemLockService()
        let docs = SearchService.makeDocuments(store: store, isGated: locks.isGated)
        #expect(SearchService.search(docs, query: "valve").isEmpty)
        #expect(SearchService.search(docs, query: "secret").map(\.whereLabel) == ["Name"])
        #expect(SearchService.search(docs, query: "codes").map(\.whereLabel) == ["Tags"])
    }

    // MARK: Trash

    @Test func restoreThroughTheWindow() throws {
        // TV: 08 T-TR-1, T-TR-2, T-TR-4
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "T"); t.subtasks = [TaskItem(name: "a"), TaskItem(name: "b")]
        let m = CrewMember(); m.firstName = "Ann"
        store.data.tasks = [t]; store.data.crew = [m]
        let et = try #require(store.trash(t))
        let ec = store.trash(m)
        #expect(store.data.tasks.isEmpty && store.data.crew.isEmpty)
        let types = TrashActions.restore(entryIDs: [et.id, ec.id], store: store)
        #expect(types == [.task, .crew])
        #expect(store.data.tasks.first?.subtasks.count == 2 && store.data.trash.isEmpty)
        #expect(store.data.log.last?.detail == "restored from Trash")

        // Collision: a live task already has the id → not duplicated, entry still consumed.
        let e2 = try #require(store.trash(store.data.tasks[0]))
        store.data.tasks.append(TaskItem(id: e2.itemId, name: "T again"))
        #expect(TrashActions.restore(entryIDs: [e2.id], store: store) == [.task])
        #expect(store.data.tasks.count == 1 && store.data.trash.isEmpty)
    }

    @Test func corruptPayloadKeepsTheEntry() {
        // TV: 08 T-TR-3
        let made = StoreFactory.make(); let store = made.store
        let bad = TrashedItem(itemType: "Task", itemId: UUID(), name: "Broken", kindLabel: "Task",
                              deletedUtc: NetDateTime(parsing: "2026-09-29T10:00:00Z")!, payloadJson: "{")
        store.data.trash = [bad]
        #expect(TrashActions.restore(entryIDs: [bad.id], store: store).isEmpty)
        #expect(store.data.trash.count == 1)
        #expect(TrashText.restoreFailed == "Couldn't restore the selected item(s)." && TrashText.restoreFailedTitle == "Restore")
    }

    @Test func permanentDeleteScrubsReferences() throws {
        // TV: 08 T-TR-5; QUICK-175, QUICK-176
        let made = StoreFactory.make(); let store = made.store
        let p = Procedure(name: "P"); let e = Equipment(name: "E"); e.procedureIds = [p.id]
        store.data.procedures = [p]; store.data.equipment = [e]
        let entry = try #require(store.trash(p))
        #expect(e.procedureIds == [p.id])
        #expect(TrashActions.purge(entryIDs: [entry.id, UUID()], store: store) == 1)
        #expect(e.procedureIds.isEmpty && store.data.trash.isEmpty)
        #expect(TrashText.deleteMessage(3) == "Permanently delete 3 item(s) from the Trash? This cannot be undone.")
        #expect(TrashText.emptyMessage(2) == "Permanently remove all 2 item(s) in the Trash? This cannot be undone.")
    }

    @Test func deletedColumnIsLocalMinutes() {
        // TV: 08 QUICK-172 (DeletedUtc in local time, yyyy-MM-dd HH:mm)
        let e = TrashedItem(itemType: "Task", itemId: UUID(), name: "x", kindLabel: "Task",
                            deletedUtc: NetDateTime(parsing: "2026-09-29T11:03:12Z")!, payloadJson: "{}")
        #expect(e.deletedUtc.toLocalTime(zone: TZ.athens).format(.isoMinute) == "2026-09-29 14:03")
    }

    // MARK: Review changes

    @Test func summaryLines() {
        // TV: 08 T-DF-1 summary, T-DF-9; QUICK-191 spacing
        #expect(ReviewChangesText.summary(DiffResult(roots: [DiffNode(change: .changed, text: "[Task] x")], changed: 1))
                == "This import will   \u{FF0B} add 0     \u{FF5E} change 1     \u{FF0D} remove 0   item(s).  Expand a row to see details.")
        #expect(ReviewChangesText.summary(DiffResult())
                == "No differences detected \u{2014} the incoming data appears identical to your current data.")
        #expect(ReviewChangesText.source("data.json") == "Importing from: data.json")
        #expect(ReviewChangesText.glyph(.added) == "\u{FF0B}" && ReviewChangesText.glyph(.removed) == "\u{FF0D}"
                && ReviewChangesText.glyph(.changed) == "\u{FF5E}")
    }

    @Test func tagOnlyChangeIsNotCovered() {
        // TV: 08 T-DF-9 end to end with the Windows-scope compare + the Mac "Other data" section
        let cur = AppData(), inc = AppData()
        let a = TaskItem(name: "A"); let b = TaskItem(id: a.id, name: "A"); b.tags = ["new"]
        cur.tasks = [a]; inc.tasks = [b]
        let m = CrewMember(); m.firstName = "Ann"; inc.crew = [m]
        #expect(ReviewChangesText.summary(DataDiff.compare(current: cur, incoming: inc)) == ReviewChangesText.noDifferences)
        let other = DataDiff.compareOtherData(current: cur, incoming: inc)
        #expect(other.hasChanges && ReviewChangesText.otherSummary(other).hasPrefix("Other data:"))
    }

    // MARK: Quick switcher

    @Test func switcherMoveClamps() {
        // TV: 08 T-QS-11; QUICK-106
        #expect(SwitcherText.move(selected: 0, delta: -1, count: 3) == 0)
        var i: Int? = 0
        for _ in 0..<3 { i = SwitcherText.move(selected: i, delta: 1, count: 3) }
        #expect(i == 2)
        #expect(SwitcherText.move(selected: nil, delta: -1, count: 3) == 0)
        #expect(SwitcherText.move(selected: nil, delta: 1, count: 0) == nil)
    }

    @Test func switcherTagsAndLockGatedRanking() {
        // TV: 08 QUICK-102; DECISIONS 08 OQ-8 via REQ-F2-02 (`rows(store:isGated:)` with the session lock state)
        #expect(SwitcherText.tags(["a", "b"]) == "#a  #b" && SwitcherText.tags([]) == "")
        let made = StoreFactory.make(); let store = made.store
        let v = Vessel(name: "Aurora"); v.description = "Aframax tanker"; v.lockHash = "h"; v.lockSalt = "s"
        store.data.vessels = [v]
        let locks = ItemLockService()
        let gatedRows = QuickSwitcherScoring.rows(store: store, isGated: locks.isGated)
        #expect(QuickSwitcherScoring.rank(gatedRows, query: "tanker").isEmpty)
        let open = QuickSwitcherScoring.rows(store: store, isGated: { _ in false })
        #expect(QuickSwitcherScoring.rank(open, query: "tanker").map(\.name) == ["Aurora"])
    }
}
