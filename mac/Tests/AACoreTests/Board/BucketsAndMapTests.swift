// Tests for 07 §8.4 (K1…K5, K8), VIEW-140…152, 06 BUILD-145 B3 / B4, DECISIONS 07 Q-11; 07 §8.5 (M1…M7), A.7 R6,
// VIEW-170…182, 02 REPO-031, W-19.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct BucketsModelTests {
    typealias D = CalTestData

    @Test func groupingAndOrder() {
        // TV: 07 K1 as amended by DECISIONS 07 Q-11 (case-insensitive merge for display)
        let d = AppData()
        d.quickBuckets = [QuickBucket(name: "Engine room", category: "Location"),
                          QuickBucket(name: "Bridge", category: "location"),
                          QuickBucket(name: "Captain", category: "Rank"),
                          QuickBucket(name: "Misc", category: "")]
        let groups = BucketsModel.groups(d)
        #expect(groups.map(\.label) == ["location", "Rank", "(Uncategorised)"])
        #expect(groups[0].rows.map(\.displayName) == ["Bridge", "Engine room"])
        #expect(groups[0].countText == " (2)" && groups.last?.rows.map(\.displayName) == ["Misc"])
        #expect(d.quickBuckets[0].category == "Location")      // display only: the stored text is untouched
    }

    @Test func countsMembersAndTexts() throws {
        // TV: 07 K2, K3, VIEW-143, VIEW-146
        let b = QuickBucket(name: "Name", category: "Cat")
        let t = TaskItem(name: "Task"), sub = TaskItem(name: "Sub")
        t.subtasks = [sub]
        let p = Procedure(name: "Proc"), st = ChecklistStep(title: "Step")
        p.steps = [st]
        t.bucketIds = [b.id]; sub.bucketIds = [b.id, b.id]; st.bucketIds = [b.id]
        let crew = CrewMember(); let cs = ChecklistStep(title: "crew"); cs.bucketIds = [b.id]; crew.checklist = [cs]
        let d = D.data(tasks: [t], procedures: [p], crew: [crew])
        d.quickBuckets = [b]
        let row = try #require(BucketsModel.groups(d).first?.rows.first)
        #expect(row.count == 3 && row.countText == "3 items")
        let members = BucketsModel.members(of: b.id, in: BucketsModel.memberRows(d))
        #expect(members.map(\.text) == ["[Checklist step]  Step   \u{2014}   in Proc", "[Subtask]  Sub   \u{2014}   in Task",
                                        "[Task]  Task"])
        #expect(BucketsModel.membersHeader(b, memberCount: 1) == "\u{1FAA3} Name  \u{00B7}  Cat   \u{2014}   1 item(s)")
        #expect(BucketsModel.membersHeader(nil, memberCount: 0) == "Select a bucket to see the tasks & procedures in it.")
        let one = QuickBucket(name: "", category: "")
        #expect(BucketRow(bucket: one, count: 1).countText == "1 items" && BucketRow(bucket: one, count: 1).displayName == "(unnamed)")
        #expect(BucketsModel.membersHeader(one, memberCount: 0) == "\u{1FAA3} (unnamed)   \u{2014}   0 item(s)")
    }

    @Test func deleteBucket() {
        // TV: 07 K4, VIEW-150
        let made = StoreFactory.make()
        let store = made.store
        let b = QuickBucket(name: "X", category: "C")
        let t = TaskItem(name: "t"), p = Procedure(name: "p")
        t.bucketIds = [b.id]; p.bucketIds = [UUID(), b.id]
        store.data.tasks = [t]; store.data.procedures = [p]; store.data.quickBuckets = [b]
        #expect(BucketsModel.deleteMessage(b, memberCount: 2) == "Delete bucket 'X'? Its 2 item(s) will be removed from it (the items themselves are kept).")
        #expect(BucketsModel.deleteMessage(b, memberCount: 0) == "Delete bucket 'X'? ")
        BucketsModel.delete(b, store: store)
        #expect(t.bucketIds.isEmpty && p.bucketIds.count == 1 && store.data.quickBuckets.isEmpty)
        let e = store.data.log.last
        #expect(e?.action == "Removed" && e?.kind == "Bucket" && e?.name == "X" && e?.detail == "")
    }

    @Test func createRenameAndCategory() throws {
        // TV: 07 K5, VIEW-147…149; 06 B3 (blank clears), B4 (Cancel on the category prompt still creates)
        let made = StoreFactory.make()
        let store = made.store
        #expect(BucketsModel.create(name: nil, category: nil, store: store) == nil)
        #expect(BucketsModel.create(name: "  ", category: "x", store: store) == nil)
        let b = try #require(BucketsModel.create(name: "  Galley  ", category: nil, store: store))
        #expect(b.name == "Galley" && b.category == "" && b.createdUtc.kind == .utc)
        let e = store.data.log.last
        #expect(e?.action == "Added" && e?.kind == "Bucket" && e?.name == "Galley" && e?.detail == "")
        let c = try #require(BucketsModel.create(name: "Bridge", category: "  Location ", store: store))
        #expect(c.category == "Location" && store.data.log.last?.detail == "Location")
        #expect(!BucketsModel.rename(c, to: "   ") && c.name == "Bridge")
        #expect(BucketsModel.rename(c, to: " Nav bridge ") && c.name == "Nav bridge")
        BucketsModel.setCategory(c, to: "   ")
        #expect(c.category == "")
        BucketsModel.setCategory(c, to: " Rank ")
        #expect(c.category == "Rank")
    }

    @Test func removeMemberAndStatusLine() {
        // TV: 07 K8, VIEW-144, VIEW-152
        #expect(BucketsModel.statusLine(bucketCount: 0) == "No buckets yet. Click \u{201C}+ New bucket\u{201D} to define one (e.g. name \u{201C}Engine room\u{201D}, category \u{201C}Location\u{201D}).")
        #expect(BucketsModel.statusLine(bucketCount: 3) == "3 bucket(s).")
        let id = UUID(), other = UUID()
        let s = ChecklistStep(title: "s")
        s.bucketIds = [other, id]
        #expect(BucketsModel.removeMember(s, from: id) && s.bucketIds == [other])
        #expect(!BucketsModel.removeMember(s, from: id))
        #expect(BucketsModel.help.contains("(in the \u{2318}N quick-work window)"))
    }
}

@MainActor
@Suite struct MapLayoutTests {
    typealias D = CalTestData

    @Test func circlePositions() {
        // TV: 07 M1, M2
        let four = MapLayout.circlePositions(count: 4)
        let expected = [(1010.0, 450.0), (700.0, 760.0), (390.0, 450.0), (700.0, 140.0)]
        for (p, e) in zip(four, expected) { #expect(abs(p.x - e.0) < 1e-9 && abs(p.y - e.1) < 1e-9) }
        let one = MapLayout.circlePositions(count: 1)
        #expect(abs(one[0].x - 1010) < 1e-9 && abs(one[0].y - 450) < 1e-9)
        #expect(MapLayout.circlePositions(count: 0).isEmpty)
    }

    @Test func graphContentAndTitle() throws {
        // TV: 07 M3, M4, VIEW-174, VIEW-175; A.7 R6 positions
        let e = Equipment(name: "E"), p = Procedure(name: "P"), t = TaskItem(name: "T"), v = Vessel(name: "V")
        e.relatedIds = [v.id]; e.procedureIds = [p.id]; e.taskIds = [t.id, v.id, UUID()]
        let d = D.data(tasks: [t], procedures: [p]); d.equipment = [e]; d.vessels = [v]
        let made = StoreFactory.make(data: d)
        let g = MapLayout.graph(centre: e, store: made.store)
        #expect(g.related.map(\.name) == ["V", "P", "T"])
        #expect(g.positions[e.id] == MapLayout.centre)
        let pt = try #require(g.positions[t.id])
        #expect(abs(pt.x - 545) < 1e-4 && abs(pt.y - 181.5321) < 1e-4)
        let pp = try #require(g.positions[p.id])
        #expect(abs(pp.x - 545) < 1e-4 && abs(pp.y - 718.4679) < 1e-4)
        #expect(MapLayout.related(of: t, store: made.store).isEmpty)
        #expect(MapLayout.title(e) == "Relationship Map \u{2014} E" && MapLayout.title(nil) == "Relationship Map")
        let lone = MapLayout.graph(centre: v, store: made.store)
        #expect(lone.related.isEmpty && lone.positions.count == 1)
    }

    @Test func dashedEdgesCheckOneDirection() {
        // TV: 07 M5
        let r1 = TaskItem(name: "R1"), r2 = TaskItem(name: "R2")
        r1.relatedIds = [r2.id]
        #expect(MapLayout.dashedEdges([r1, r2]).map { [$0.0, $0.1] } == [[0, 1]])
        r1.relatedIds = []; r2.relatedIds = [r1.id]
        #expect(MapLayout.dashedEdges([r1, r2]).isEmpty)
    }

    @Test func inspectRowsAndSearch() {
        // TV: 07 M6, VIEW-171, VIEW-172
        let e = Equipment(name: "Pump room"), t1 = TaskItem(name: "Fix"), t2 = TaskItem(name: "Paint")
        let d = D.data(tasks: [t1, t2]); d.equipment = [e]
        let made = StoreFactory.make(data: d)
        let rows = MapLayout.inspectRows(store: made.store)
        #expect(rows.map(\.text) == ["[Equipment] Pump room", "[Task] Fix", "[Task] Paint"])
        #expect(MapLayout.filter(rows, query: " task ").map(\.text) == ["[Task] Fix", "[Task] Paint"])
        #expect(MapLayout.filter(rows, query: "").count == 3)
    }

    @Test func persistedFocus() {
        // TV: 07 M7, VIEW-180
        let t = TaskItem(name: "t")
        let made = StoreFactory.make(data: D.data(tasks: [t]))
        made.store.data.ui.mapFocusedItemId = UUID()
        #expect(MapLayout.persistedFocus(store: made.store) == nil)
        made.store.data.ui.mapFocusedItemId = t.id
        #expect(MapLayout.persistedFocus(store: made.store) === t)
    }

    @Test func selfRelationIsExcluded() {
        // W-19: an item listing its own id is not drawn as its own neighbour.
        let t = TaskItem(name: "t"), u = TaskItem(name: "u")
        t.relatedIds = [t.id, u.id]
        let made = StoreFactory.make(data: D.data(tasks: [t, u]))
        let g = MapLayout.graph(centre: t, store: made.store)
        #expect(g.related.map(\.name) == ["u"] && g.positions[t.id] == MapLayout.centre)
    }
}
