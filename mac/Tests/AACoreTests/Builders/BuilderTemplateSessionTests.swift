// Tests for 06 BUILD-063 + §8 D3 (template editor session), 03 T-KB-40 / T-KB-45 (closing or quitting with a builder
// open persists its items), and the remaining 06 §7.6 / §7.8 string vectors this owner holds (W-BUILD).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct BuilderTemplateSessionTests {
    private func store(with t: ChecklistTemplate) -> StoreFactory.Made {
        let made = StoreFactory.make()
        made.store.data.checklistTemplates = [t]
        return made
    }

    @Test func unchangedSessionWritesNothing() {
        // D3 / DECISIONS 02 Q-12: open + close without edits keeps container ids and leaves the store clean.
        let t = ChecklistTemplate(name: "Deck", items: [ChecklistTemplateItem(title: "A"), ChecklistTemplateItem(title: "B")])
        let made = store(with: t)
        let containerIDs = t.items.map(\.container.id)
        let s = BuilderTemplateSession(store: made.store, templateID: t.id)
        #expect(s.steps.map(\.title) == ["A", "B"])
        #expect(s.steps.map(\.container.id) != containerIDs)          // detached clones (ToSteps)
        #expect(!s.hasChanges)
        #expect(s.finish())
        #expect(t.items.map(\.container.id) == containerIDs)
        #expect(!made.store.isDirty)
    }

    @Test func editsAreWrittenBackWithoutDeadlineOrDone() {
        // BUILD-063: write-back replaces the items; deadline / done are never stored; Id, Name, GroupId, CreatedUtc kept.
        let g = UUID()
        let t = ChecklistTemplate(name: "Deck", items: [ChecklistTemplateItem(title: "A")])
        t.groupId = g
        let created = t.createdUtc
        let made = store(with: t)
        let s = BuilderTemplateSession(store: made.store, templateID: t.id)
        let engine = BuilderEngine(store: made.store, kind: .steps, logKind: "Saved-list item", owner: { s.ownerName },
                                   read: { s.steps }, write: { s.steps = $0 })
        engine.addAll(text: "B\nC", replace: false)
        s.steps[0].done = true
        s.steps[0].deadline = NetDateTime(year: 2026, month: 10, day: 2, kind: .unspecified)
        #expect(made.store.data.log.last!.kind == "Saved-list item" && made.store.data.log.last!.detail == "Deck")
        #expect(s.hasChanges)
        #expect(s.finish())
        #expect(t.items.map(\.title) == ["A", "B", "C"])
        #expect(t.groupId == g && t.name == "Deck" && t.createdUtc == created)
        #expect(made.store.data.checklistTemplates.count == 1)
        #expect(s.finish())                                            // idempotent
    }

    @Test func renameWhileEditingIsShownAndKept() {
        // BUILD-063 quirk: "Manage saved lists…" may rename the template being edited — the owner name follows it.
        let t = ChecklistTemplate(name: "Deck", items: [ChecklistTemplateItem(title: "A")])
        let made = store(with: t)
        let s = BuilderTemplateSession(store: made.store, templateID: t.id)
        #expect(BuilderSavedLists.rename(made.store, t, rawName: " Bridge "))
        #expect(s.ownerName == "Bridge")
        s.steps[0].title = "A2"
        #expect(s.finish())
        #expect(t.name == "Bridge" && t.items.map(\.title) == ["A2"])
    }

    @Test func vanishedTemplateOffersSaveAsNewList() {
        // D3: the template deleted meanwhile → write-back refuses; "Save as New List" keeps the edits.
        let t = ChecklistTemplate(name: "Deck", items: [ChecklistTemplateItem(title: "A")])
        let made = store(with: t)
        let s = BuilderTemplateSession(store: made.store, templateID: t.id)
        s.steps.append(ChecklistStep(title: "B"))
        BuilderSavedLists.delete(made.store, t)
        #expect(s.ownerName == "Deck")
        #expect(!s.finish())
        let rescued = s.saveAsNewList()
        #expect(rescued.name == "Deck" && rescued.items.map(\.title) == ["A", "B"] && rescued.id != t.id)
        #expect(made.store.data.checklistTemplates.last === rescued)
        let log = made.store.data.log.last!
        #expect(log.action == "Added" && log.kind == "Saved list" && log.detail == "2 item(s)")
    }

    @Test func reloadedTemplateIsResolvedById() {
        // 06 §8 R1: a reload replaces the template object; the write-back lands on the new one (same id).
        let t = ChecklistTemplate(name: "Deck", items: [ChecklistTemplateItem(title: "A")])
        let made = store(with: t)
        let s = BuilderTemplateSession(store: made.store, templateID: t.id)
        let reloaded = ChecklistTemplate(id: t.id, name: "Deck", items: [ChecklistTemplateItem(title: "A")])
        made.store.data.checklistTemplates = [reloaded]
        s.steps[0].title = "Z"
        #expect(s.finish())
        #expect(reloaded.items.map(\.title) == ["Z"] && t.items.map(\.title) == ["A"])
    }

    @Test func tKB45ClosingTheBuilderPersistsItsItems() throws {
        // TV: 03 T-KB-45 / T-KB-40 — the procedure builder edits the live steps (MarkDirty); closing flushes
        // (FlushIfDirty) and the items are on disk; the template editor's write-back + Save persists too.
        let made = StoreFactory.make()
        let p = Procedure(name: "Bunkering")
        made.store.data.procedures = [p]
        let t = ChecklistTemplate(name: "Deck", items: [ChecklistTemplateItem(title: "A")])
        made.store.data.checklistTemplates = [t]
        try made.store.save()
        let engine = BuilderEngine(store: made.store, kind: .steps, logKind: "Checklist step", owner: { p.name },
                                   read: { p.steps }, write: { p.steps = $0 })
        engine.addAll(text: "Pre-transfer meeting\nESD test", replace: false)
        #expect(made.store.isDirty)
        try made.store.flushIfDirty()                                   // BUILD-018 close = Flush
        #expect(!made.store.isDirty)
        let s = BuilderTemplateSession(store: made.store, templateID: t.id)
        s.steps.append(ChecklistStep(title: "B"))
        #expect(s.finish())
        try made.store.save()                                           // BUILD-063 close = Save
        let back = made.dataStore.load()
        #expect(back.procedures.first?.steps.map(\.title) == ["Pre-transfer meeting", "ESD test"])
        #expect(back.checklistTemplates.first?.items.map(\.title) == ["A", "B"])
    }

    @Test func remainingStringVectors() {
        // TV: 06 §7.6 ScheduleTemplate.Display; §7.8 Sanitize (saved lists / schedule fallbacks).
        let a = ScheduleTemplate(name: "Rotation A")
        a.entries = [ScheduleEntry(title: "Drill")]
        a.vesselName = "MV Atlas"
        #expect(a.display == "Rotation A  ·  1 entry  ·  MV Atlas")
        let b = ScheduleTemplate(name: "")
        b.entries = [ScheduleEntry(), ScheduleEntry(), ScheduleEntry()]
        #expect(b.display == "(unnamed)  ·  3 entries")
        #expect(WindowsFileName.sanitize("Deck/Engine: daily?", fallback: "saved-lists") == "Deck_Engine_ daily_")
        #expect(WindowsFileName.sanitize("", fallback: "saved-lists") == "saved-lists")
        #expect(WindowsFileName.sanitize("   ", fallback: "saved-lists") == "saved-lists")
        #expect(WindowsFileName.sanitize(" A ", fallback: "saved-lists") == "A")
        #expect(WindowsFileName.sanitize("a|b", fallback: "saved-lists") == "a_b")
        #expect(WindowsFileName.sanitize("  \t ", fallback: "saved-lists") == "_")
        #expect("Schedule-\(WindowsFileName.sanitize("", fallback: "crew")).aasched.json" == "Schedule-crew.aasched.json")
        // 06 §7.5: a group named "" → entries untagged, file name saved-lists.pdf
        let d = AppData()
        let g = ListGroup(name: "")
        d.listGroups = [g]
        let t = ChecklistTemplate(name: "T"); t.groupId = g.id
        d.checklistTemplates = [t]
        let entries = SavedListOrder.groupEntries(d, groupID: g.id) ?? []
        #expect(entries.count == 1 && entries[0].group == nil)
        #expect(WindowsFileName.sanitize(g.name, fallback: "saved-lists") + ".pdf" == "saved-lists.pdf")
        // BUILD-064: ItemToTask → To Do, top-level shape
        let item = ChecklistTemplateItem(title: "Check A", durationMinutes: 45, isJob: true)
        let task = ChecklistTemplateService.itemToTask(item)
        #expect(task.name == "Check A" && task.status == .todo && !task.isComplete && task.durationMinutes == 45 && task.isJob)
        #expect(task.container.id != item.container.id)
    }
}
