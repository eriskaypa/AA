// TV: 11 §7.12 (saved-lists document structure), §7.13 (item PDF DOM goldens, checklist-only rows), PDF-027 (export
//     order), PDF-030…055 (page setup, header/footer, styles, sections), DECISIONS 11 Q6 (gated related items: name
//     only), PDF-105, BUILD-A17. Notes bodies go through the fallback path in this worktree and through W-RICH after
//     the merge; both print the same visible text for these one-paragraph notes.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite("W-PDF document builders")
struct PdfBuilderTests {
    let stamp = "2026-09-29 14:05"

    func texts(_ doc: PdfDoc) -> [String] { doc.body.compactMap(\.paragraph).map(\.plainText) }
    func styled(_ doc: PdfDoc) -> [(PdfStyleName, String)] { doc.body.compactMap(\.paragraph).map { ($0.style, $0.plainText) } }

    // MARK: §7.12

    func savedListsDoc(_ scope: PdfExport.SavedListsScopeRequest, numbered: Bool = false) -> PdfDoc? {
        let made = StoreFactory.make(data: PdfTestData.savedLists())
        guard case .entries(let title, let entries) = PdfExport.savedListsSelection(scope, data: made.store.data) else { return nil }
        return PdfSavedListsBuilder.build(title: title, entries: entries, numbered: numbered, stamp: stamp)
    }

    // TV: 11 §7.12 row "ALL, bulleted"
    @Test func savedListsAllBulleted() throws {
        let doc = try #require(savedListsDoc(.all))
        #expect(doc.title == "All saved lists" && doc.author == "AA")
        let s = styled(doc)
        let expected: [(PdfStyleName, String)] = [
            (.title, "All saved lists"), (.subtitle, "Saved checklists  \u{00B7}  4 lists"),
            (.h1, "Deck"), (.h2, "Anchoring   (1 item)"), (.bullet, "\u{2022}  Clear the hawse"),
            (.h1, "engine"), (.h2, "Mooring   (2 items)"), (.bullet, "\u{2022}  item1  (schedulable)"), (.bullet, "\u{2022}  item2"),
            (.h2, "Bunkering   (1 item)"), (.bullet, "\u{2022}  Sound tanks"),
            (.h1, "Ungrouped"), (.h2, "Ungrp A   (0 items)"),
        ]
        #expect(s.map(\.0) == expected.map(\.0))
        #expect(s.map(\.1) == expected.map(\.1))
        #expect(doc.header.first?.plainText == "Saved lists: All saved lists\t\(stamp)")
        #expect(PdfExport.savedListsFileName(title: doc.title) == "All saved lists.pdf")
        // Marker bold; "(schedulable)" grey italic.
        let item1 = doc.body.compactMap(\.paragraph).first { $0.plainText.contains("item1") }!
        #expect(item1.inlines.first == .text("\u{2022}  ", .bold))
        #expect(item1.inlines.last == .text("(schedulable)", PdfCharFormat(italic: true, color: .muted)))
    }

    // TV: 11 §7.12 row "ALL, numbered" — numbering restarts per list; DOM markers differ from bulleted
    @Test func savedListsAllNumbered() throws {
        let n = try #require(savedListsDoc(.all, numbered: true))
        let b = try #require(savedListsDoc(.all, numbered: false))
        #expect(texts(n).contains("1. item1  (schedulable)") && texts(n).contains("2. item2"))
        #expect(texts(n).contains("1. Sound tanks") && texts(n).contains("1. Clear the hawse"))
        #expect(n.body != b.body)
    }

    // TV: 11 §7.12 rows "Group (T4 selected)", "This list (T3)", "Group (T2 selected)"
    @Test func savedListsGroupListAndUngrouped() throws {
        let group = try #require(savedListsDoc(.group(ofList: G(204))))
        #expect(group.title == "engine")
        #expect(texts(group).filter { $0.contains("(") && !$0.contains("schedulable") && !$0.hasPrefix("Saved") }
                == ["Mooring   (2 items)", "Bunkering   (1 item)"])
        #expect(styled(group)[2] == (.h1, "engine"))
        let one = try #require(savedListsDoc(.list(G(203))))
        #expect(one.title == "Anchoring")
        #expect(styled(one).map(\.0) == [.title, .subtitle, .h2, .bullet])                // no H1
        #expect(texts(one)[1] == "Saved checklists  \u{00B7}  1 list")
        let ungrouped = try #require(savedListsDoc(.group(ofList: G(202))))
        #expect(ungrouped.title == "Ungrouped lists")
        #expect(styled(ungrouped).map(\.0) == [.title, .subtitle, .h2])
        #expect(PdfExport.savedListsFileName(title: "engine") == "engine.pdf")
        #expect(PdfExport.savedListsFileName(title: ungrouped.title) == "Ungrouped lists.pdf")
    }

    // TV: PDF-020/021/022/026 selection edge cases
    @Test func savedListsSelectionEdges() {
        let data = PdfTestData.savedLists()
        #expect(PdfExport.savedListsSelection(.list(nil), data: data) == .needSelection)
        #expect(PdfExport.savedListsSelection(.group(ofList: UUID()), data: data) == .needSelection)
        #expect(PdfExport.savedListsSelection(.all, data: AppData()) == .noSavedLists)
        // A list whose GroupId dangles: "Ungrouped lists", and the list itself is not included.
        let dangling = ChecklistTemplate(name: "Lost", groupId: UUID())
        let d = AppData(); d.checklistTemplates = [dangling]
        #expect(PdfExport.savedListsSelection(.group(ofList: dangling.id), data: d) == .entries(title: "Ungrouped lists", []))
        // Empty name → "Saved list".
        let unnamed = ChecklistTemplate(name: "")
        let u = AppData(); u.checklistTemplates = [unnamed]
        if case .entries(let title, _) = PdfExport.savedListsSelection(.list(unnamed.id), data: u) { #expect(title == "Saved list") }
        else { Issue.record("expected entries") }
    }

    // TV: PDF-052 contiguity rules — empty group name = no group; adjacent same names merge; first null → no heading
    @Test func headingStateMachine() {
        let e = { (g: String?, n: String) in PdfSavedListEntry(group: g, name: n, items: []) }
        let doc = PdfSavedListsBuilder.build(title: "T", entries: [e("", "a"), e(nil, "b"), e("X", "c"), e("X", "d"),
                                                                  e("x", "e"), e(nil, "f"), e("  ", "g")],
                                             numbered: false, stamp: stamp)
        #expect(styled(doc).dropFirst(2).map { "\($0.0.rawValue):\($0.1)" } == [
            "H2:a   (0 items)", "H2:b   (0 items)", "H1:X", "H2:c   (0 items)", "H2:d   (0 items)",
            "H1:x", "H2:e   (0 items)", "H1:Ungrouped", "H2:f   (0 items)", "H2:g   (0 items)"])
        let unnamed = PdfSavedListsBuilder.build(title: "T", entries: [e(nil, " ")], numbered: true, stamp: stamp)
        #expect(texts(unnamed).last == "(unnamed list)   (0 items)")
        // Ordinal equality: a precomposed and a decomposed "Pont" + é are two groups on Windows (no merge).
        let accents = PdfSavedListsBuilder.build(title: "T", entries: [e("Pont\u{00E9}", "a"), e("Ponte\u{0301}", "b")],
                                                 numbered: false, stamp: stamp)
        #expect(styled(accents).dropFirst(2).filter { $0.0 == .h1 }.count == 2)
        #expect(PdfSavedListsBuilder.ordinalEqual(nil, nil) && !PdfSavedListsBuilder.ordinalEqual("a", nil))
    }

    // TV: PDF-055 item notes at 0.6 cm and the file list
    @Test func savedListItemNotesAndFiles() {
        let item = PdfSavedListItemSnapshot(title: "Rig pilot ladder", container: PdfContainerSnapshot(
            xaml: PdfTestData.xaml(["Check the manropes"]),
            files: [PdfFileSnapshot(name: "ladder.jpg", path: "files/x_ladder.jpg", kind: .image),
                    PdfFileSnapshot(name: "SOLAS.pdf", path: "files/y_SOLAS.pdf", kind: .document)]))
        let doc = PdfSavedListsBuilder.build(title: "Pilot", entries: [PdfSavedListEntry(group: nil, name: "Pilot", items: [item])],
                                             numbered: false, stamp: stamp)
        let ps = doc.body.compactMap(\.paragraph)
        let note = ps.first { $0.plainText == "Check the manropes" }
        #expect(note?.format.leftIndent == 0.6)
        let files = ps.last!
        #expect(files.style == .muted && files.format.leftIndent == 0.6)
        #expect(files.plainText == "Files: ladder.jpg, SOLAS.pdf")
        #expect(files.inlines.first == .text("Files: ", .italic))
    }

    // MARK: §7.13

    // TV: 11 §7.13 Task "Pump overhaul"
    @Test func taskGolden() {
        let g = PdfTestData.golden()
        let doc = PdfItemBuilder.build(PdfSnapshotBuilder.item(g.overhaul, store: g.made.store, isGated: { _ in false }), stamp: stamp)
        #expect(doc.header.first?.plainText == "Task: Pump overhaul\t\(stamp)")
        #expect(doc.header.first?.format.tabStops == [PdfTabStop(positionCm: 16, alignment: .right)])
        #expect(doc.footer.first?.plainText == "Page # / #")
        #expect(doc.footer.first?.format.alignment == .right)
        #expect(doc.title == "Task - Pump overhaul" && doc.author == "AA")
        #expect(doc.pageSetup == .pdfExporter)
        #expect(PdfExport.itemFileName(kind: .task, name: g.overhaul.name) == "Task-Pump overhaul.pdf")
        let blocks = doc.body
        let ps = blocks.compactMap(\.paragraph)
        #expect(ps[0].style == .title && ps[0].plainText == "Pump overhaul")
        #expect(ps[1].style == .subtitle && ps[1].plainText == "Task")
        #expect(ps[2].style == .bodyItalic && ps[2].plainText == "Yearly job")
        #expect(ps[3].style == .h1 && ps[3].plainText == "Notes")
        #expect(ps[4].plainText == "See https://x.io")
        #expect(ps[5].style == .h1 && ps[5].plainText == "Task Details")
        let kv = blocks.compactMap(\.table).first!
        #expect(kv.columns == [4, 12] && kv.borders == nil && kv.padding == .migraDocDefault)
        #expect(kv.rows.map { $0.cells.map { $0.blocks[0].paragraph!.plainText } } == [
            ["Working range", "2026-07-08 \u{2192} 2026-07-10"], ["Deadline", "2026-07-10"],
            ["Recurrence", "Yearly"], ["Status", "Open"]])
        #expect(kv.rows[0].cells[0].blocks[0].paragraph!.format.font == PdfCharFormat(bold: true, color: PdfColor(80, 80, 80)))
        #expect(ps[6].style == .h2 && ps[6].plainText == "Subtasks (1)")
        // Subtask head @0.6, SpaceBefore 6, KWN; meta grey italic.
        #expect(ps[7].plainText == "[ ] Drain  (due 2026-07-09)")
        #expect(ps[7].format.leftIndent == 0.6 && ps[7].format.spaceBefore == 6 && ps[7].format.spaceAfter == 2)
        #expect(ps[7].format.keepWithNext == true)
        #expect(ps[7].inlines.first == .text("[ ] ", .bold))
        #expect(ps[7].inlines.last == .text("(due 2026-07-09)", PdfCharFormat(italic: true, color: .muted)))
        #expect(ps[8].plainText == "Use tray" && ps[8].format.leftIndent == 0.6)
        #expect(ps[9].plainText == "[ ] Check level" && ps[9].format.leftIndent == 1.2 && ps[9].format.spaceBefore == 3)
        #expect(ps[10].style == .h1 && ps[10].plainText == "Relationships (2)")
        #expect(ps[11].style == .bodyItalic && ps[11].plainText == "Items linked to this one, grouped by tab.")
        #expect(ps[12].style == .h2 && ps[12].plainText == "Equipment/Area (1)")
        #expect(ps[13].style == .bullet && ps[13].plainText == "Pump room \u{2014} Aft")
        #expect(ps[13].inlines.first == .text("Pump room", .bold))
        #expect(ps[14].plainText == "Procedure (1)" && ps[15].plainText == "LOTO")
        #expect(ps[16].style == .h1 && ps[16].plainText == "Attached Files (1)")
        let files = blocks.compactMap(\.table).last!
        #expect(files.columns == [5, 2, 9])
        #expect(files.borders == PdfBorder(width: 0.5, color: PdfColor(200, 200, 200)))
        #expect(files.padding == PdfPadding(left: 3, right: 3, top: 2, bottom: 2))
        #expect(files.rows[0].headingFormat && files.rows[0].shading == .tableHeader)
        #expect(files.rows.map { $0.cells.map { $0.blocks[0].paragraph!.plainText } } == [
            ["Name", "Kind", "Path / Link"], ["manual.pdf", "Document", "files/manual.pdf"]])
        #expect(files.rows[1].cells[2].blocks[0].paragraph!.format.font.size == 9)
    }

    // TV: 11 §7.13 Procedure "LOTO" (+ checklist-only PDF rows)
    @Test func procedureGolden() {
        let g = PdfTestData.golden()
        let doc = PdfItemBuilder.build(PdfSnapshotBuilder.item(g.loto, store: g.made.store, isGated: { _ in false }), stamp: stamp)
        let ps = doc.body.compactMap(\.paragraph)
        #expect(ps[2].style == .h1 && ps[2].plainText == "Checklist (2 steps)")
        #expect(ps[3].inlines == [.text("1. [x] ", PdfCharFormat(bold: true, color: PdfColor(0, 120, 0))),
                                  .text("Isolate", .bold),
                                  .text("   (due 2026-07-01)", PdfCharFormat(italic: true, color: PdfColor(100, 100, 100)))])
        #expect(ps[3].format.spaceBefore == 6 && ps[3].format.keepWithNext == true)
        #expect(ps[4].style == .muted && ps[4].format.leftIndent == 0.6 && ps[4].plainText == "Equipment/Area: Pump room")
        #expect(ps[4].inlines.first == .text("Equipment/Area: ", .italic))
        #expect(ps[5].plainText == "Tasks: Pump overhaul")
        #expect(ps[6].inlines == [.text("2. [ ] ", PdfCharFormat(bold: true, color: PdfColor(100, 100, 100))), .text("Tag", .bold)])
        #expect(ps.count == 7)                                                              // no relationships, no files

        let cl = PdfChecklistBuilder.build(PdfSnapshotBuilder.checklist(g.loto, store: g.made.store))
        #expect(cl.title == "Checklist - LOTO" && cl.header.isEmpty && cl.pageSetup == .checklist)
        #expect(cl.styles == .checklist)
        let cps = cl.body.compactMap(\.paragraph)
        #expect(cps[0].plainText == "LOTO" && cps[0].format.font == PdfCharFormat(size: 22, bold: true) && cps[0].format.spaceAfter == 2)
        #expect(cps[1].plainText == "Checklist" && cps[1].format.font.color == .muted && cps[1].format.spaceAfter == 10)
        let t = cl.body.compactMap(\.table).first!
        #expect(t.columns == [0.9, 1.0, 7.2, 2.2, 5.0])
        #expect(t.padding == PdfPadding(left: 3, right: 3, top: 3, bottom: 3))
        #expect(t.borders == PdfBorder(width: 0.5, color: PdfColor(180, 180, 180)))
        #expect(t.rows[0].headingFormat && t.rows[0].shading == .tableHeader)
        #expect(t.rows.map { $0.cells.map { $0.blocks[0].paragraph!.plainText } } == [
            ["#", "Done", "Step", "Due", "Tasks / Equipment-Area"],
            ["1", "[x]", "Isolate", "2026-07-01", "T: Pump overhaul\nE/A: Pump room"],
            ["2", "[  ]", "Tag", "", ""]])
        #expect(PdfExport.checklistFileName(procedureName: "LOTO", excel: false) == "checklist-LOTO.pdf")
    }

    // TV: 11 §7.13 Equipment "Pump room"
    @Test func equipmentGolden() {
        let g = PdfTestData.golden()
        let doc = PdfItemBuilder.build(PdfSnapshotBuilder.item(g.pumpRoom, store: g.made.store, isGated: { _ in false }), stamp: stamp)
        #expect(doc.header.first?.plainText == "Equipment/Area: Pump room\t\(stamp)")
        #expect(doc.title == "Equipment - Pump room")
        #expect(PdfExport.itemFileName(kind: .equipment, name: "Pump room") == "Equipment-Pump room.pdf")
        #expect(styled(doc).map { "\($0.0.rawValue):\($0.1)" } == [
            "Title:Pump room", "Subtitle:Equipment/Area", "BodyItalic:Aft",
            "H1:Equipment/Area Details", "H2:Components (1)",
            "H2:Linked Procedures (2)", "H3:LOTO", "Bullet:1. [x] Isolate", "Bullet:2. [ ] Tag",
            "H1:Relationships (1)", "BodyItalic:Items linked to this one, grouped by tab.", "H2:Procedure (1)", "Bullet:LOTO"])
        let comp = doc.body.compactMap(\.table).first!
        #expect(comp.columns == [5, 11] && comp.borders == PdfBorder(width: 0.5, color: PdfColor(180, 180, 180)))
        #expect(comp.rows.map { $0.cells.map { $0.blocks[0].paragraph!.plainText } } == [["Component", "Notes"], ["Impeller", "Check wear"]])
        #expect(comp.rows[0].cells[0].blocks[0].paragraph!.format.font.bold == true)
    }

    // TV: 11 §7.13 Vessel "MV Aurora" — title + subtitle only, one page
    @Test func vesselGolden() {
        let g = PdfTestData.golden()
        let doc = PdfItemBuilder.build(PdfSnapshotBuilder.item(g.aurora, store: g.made.store, isGated: { _ in false }), stamp: stamp)
        #expect(texts(doc) == ["MV Aurora", "Vessel"])
        #expect(PdfRenderer.pageCount(doc) == 1)
    }

    // TV: PDF-037 Linked Tasks + PDF-040 task summary; PDF-044 sort ordinal-ignore-case; Q6 gated names
    @Test func linkedTasksRelationshipsAndGating() {
        let g = PdfTestData.golden()
        let store = g.made.store
        let a = TaskItem(name: "beta"); a.description = "second"
        let b = TaskItem(name: "Alpha"); b.description = "first\r\nline"; b.deadline = PdfTestData.day(2026, 8, 1); b.recurrence = .weekly
        b.isComplete = true
        let secret = TaskItem(name: "Secret job"); secret.description = "classified"
        secret.lockHash = "h"; secret.lockSalt = "s"
        store.data.tasks += [a, b, secret]
        g.pumpRoom.taskIds = [a.id, b.id, secret.id, UUID()]
        g.pumpRoom.relatedIds = [a.id, b.id, secret.id, g.pumpRoom.id]
        let locks = ItemLockService()
        let doc = PdfItemBuilder.build(PdfSnapshotBuilder.item(g.pumpRoom, store: store, isGated: locks.isGated), stamp: stamp)
        let t = texts(doc)
        let linked = t.firstIndex(of: "Linked Tasks (4)")!
        #expect(Array(t[(linked + 1)...(linked + 5)]) == [
            "[ ] beta", "second", "[x] Alpha  (due 2026-08-01, weekly)", "first\nline", "Secret job"])
        let rel = t.firstIndex(of: "Relationships (5)")!                                   // self-reference included
        #expect(Array(t[(rel + 2)...]) == [
            "Equipment/Area (1)", "Pump room \u{2014} Aft",
            "Task (3)", "Alpha \u{2014} first  line", "beta \u{2014} second", "Secret job",
            "Procedure (1)", "LOTO"])
        #expect(!t.contains { $0.contains("classified") })
        let summaryDesc = doc.body.compactMap(\.paragraph).first { $0.plainText == "second" }!
        #expect(summaryDesc.style == .muted && summaryDesc.format.leftIndent == 0.6)
    }

    // TV: PDF-036 — a blank body prints nothing, not even the heading; PDF-043/045 omitted sections
    @Test func emptySectionsOmitted() {
        let s = PdfItemSnapshot(kind: .vessel, name: "", container: PdfContainerSnapshot(xaml: "   "), specifics: .vessel)
        let doc = PdfItemBuilder.build(s, stamp: stamp)
        #expect(texts(doc) == ["", "Vessel"])
        #expect(doc.title == "Vessel - ")
        let eq = PdfItemSnapshot(kind: .equipment, name: "E", specifics: .equipment(components: [], procedureIds: [], taskIds: []))
        #expect(!texts(PdfItemBuilder.build(eq, stamp: stamp)).contains("Equipment/Area Details"))
        let p = PdfItemSnapshot(kind: .procedure, name: "P", specifics: .procedure(steps: [PdfStepSnapshot(title: "only")]))
        #expect(texts(PdfItemBuilder.build(p, stamp: stamp)).contains("Checklist (1 step)"))
    }

    // TV: 11 §7.16 #9 — the DOM is appearance-independent (fixed sRGB values only)
    @Test func domIsDeterministic() {
        let g = PdfTestData.golden()
        let a = PdfItemBuilder.build(PdfSnapshotBuilder.item(g.overhaul, store: g.made.store, isGated: { _ in false }), stamp: stamp)
        let b = PdfItemBuilder.build(PdfSnapshotBuilder.item(g.overhaul, store: g.made.store, isGated: { _ in false }), stamp: stamp)
        #expect(a == b)
    }

    // TV: 11 §6.7 / PDF-044 — FindById first-wins, distinct related items, stored calendar dates
    @Test func snapshots() {
        let g = PdfTestData.golden()
        let store = g.made.store
        let dup = Vessel(id: g.pumpRoom.id, name: "Shadow")                                 // same id later in order
        store.data.vessels.append(dup)
        let lookup = PdfTestData.lookup(g)
        #expect(lookup.find(g.pumpRoom.id)?.name == "Pump room")
        #expect(lookup.find(g.loto.id)?.steps.map(\.title) == ["Isolate", "Tag"])
        g.overhaul.relatedIds = [g.pumpRoom.id, g.pumpRoom.id, g.loto.id, UUID()]
        let s = PdfSnapshotBuilder.item(g.overhaul, store: store, isGated: { _ in false })
        #expect(s.related.map(\.name) == ["Pump room", "LOTO"])
        guard case .task(let t) = s.specifics else { Issue.record("task"); return }
        #expect(t.deadline == CivilDate(year: 2026, month: 7, day: 10) && t.subtasks.first?.subtasks.first?.name == "Check level")
        // An offset-bearing stored date prints its wall-clock calendar day.
        g.overhaul.deadline = NetDateTime(parsing: "2026-07-10T00:00:00")
        #expect(PdfSnapshotBuilder.task(g.overhaul).deadline == CivilDate(year: 2026, month: 7, day: 10))
    }
}
