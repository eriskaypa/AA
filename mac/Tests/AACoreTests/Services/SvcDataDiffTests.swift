// Tests for 01 §7.8 (DataDiff), §7.9 (AgeVerdict), 08 §7.7 (T-DF-1…11), OC-13 (count-aware file keys), DECISIONS 01
// Q-3 ("Other data").
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct SvcDataDiffTests {
    private func d(_ s: String) -> NetDateTime { NetDateTime.calendarDate(CivilDate(iso: s)!) }

    /// "＋ text" lines, children indented two spaces per level.
    private func render(_ nodes: [DiffNode], _ depth: Int = 0) -> [String] {
        nodes.flatMap { n -> [String] in
            let glyph = n.change == .added ? "+" : n.change == .removed ? "-" : "~"
            return [String(repeating: "  ", count: depth) + glyph + " " + n.text] + render(n.children, depth + 1)
        }
    }

    @Test func specExample() {
        // TV: 01 §7.8 main example
        let cur = AppData(), inc = AppData()
        let t1 = TaskItem(name: "Pump"), e1 = Equipment(name: "Boiler")
        cur.tasks = [t1]; cur.equipment = [e1]
        let t1b = TaskItem(id: t1.id, name: "Pump 2"); t1b.deadline = d("2026-10-01")
        t1b.subtasks = [TaskItem(name: "Check oil")]
        let v1 = Vessel(name: "Alpha"); v1.container.files = [FileItem(name: "manual.pdf", path: "files/x_manual.pdf")]
        inc.tasks = [t1b]; inc.vessels = [v1]
        let r = DataDiff.compare(current: cur, incoming: inc)
        #expect(r.added == 1 && r.changed == 1 && r.removed == 1 && r.hasChanges)
        #expect(render(r.roots) == [
            "+ [Vessel] Alpha", "  + file: manual.pdf",
            "~ [Task] Pump 2", "  ~ name: \"Pump\" \u{2192} \"Pump 2\"", "  ~ deadline: (none) \u{2192} 2026-10-01",
            "  + subtask: Check oil",
            "- [Equipment/Area] Boiler",
        ])
    }

    @Test func statusAndRecurrenceUseFriendlyLabels() {
        // DECISIONS 08 OQ-10: the change list shows "In Progress" / "To Do", never the raw enum names
        let cur = AppData(), inc = AppData()
        let t = TaskItem(name: "Survey"); t.status = .inProgress
        let tb = TaskItem(id: t.id, name: "Survey"); tb.status = .todo; tb.recurrence = .weekly
        cur.tasks = [t]; inc.tasks = [tb]
        let lines = render(DataDiff.compare(current: cur, incoming: inc).roots)
        #expect(lines == ["~ [Task] Survey", "  ~ recurrence: None \u{2192} Weekly",
                          "  ~ status: In Progress \u{2192} To Do"])
        #expect(!lines.contains { $0.contains("InProgress") || $0.contains("Todo") })
        #expect(tb.status.rawValue == 0 && t.status.rawValue == 1)
    }

    @Test func taskFieldChangesAndOrdering() {
        // TV: 08 T-DF-1, T-DF-6, T-DF-11
        let cur = AppData(), inc = AppData()
        let t = TaskItem(name: "Pump check"); t.deadline = d("2026-09-01")
        let tb = TaskItem(id: t.id, name: "Pump check"); tb.deadline = d("2026-09-05"); tb.status = .done
        cur.tasks = [t]; inc.tasks = [tb]
        let r = DataDiff.compare(current: cur, incoming: inc)
        #expect(render(r.roots) == ["~ [Task] Pump check", "  ~ deadline: 2026-09-01 \u{2192} 2026-09-05", "  ~ status: To Do \u{2192} Done"])
        #expect(r.added == 0 && r.changed == 1 && r.removed == 0)

        let tc = TaskItem(id: t.id, name: "Pump check")
        tc.deadline = NetDateTime(year: 2026, month: 9, day: 1, hour: 12, kind: .unspecified)
        inc.tasks = [tc]
        #expect(render(DataDiff.compare(current: cur, incoming: inc).roots).contains("  ~ deadline: 2026-09-01 \u{2192} 2026-09-01"))

        let c2 = AppData(), i2 = AppData()
        let a = TaskItem(name: "A"); let cRemoved = TaskItem(name: "c")
        c2.tasks = [a, cRemoved]
        let aChanged = TaskItem(id: a.id, name: "A"); aChanged.description = "x"
        i2.tasks = [TaskItem(name: "b"), aChanged, TaskItem(name: "a")]
        #expect(DataDiff.compare(current: c2, incoming: i2).roots.map(\.text) == ["[Task] a", "[Task] b", "[Task] A", "[Task] c"])
    }

    @Test func addedEquipmentContent() {
        // TV: 08 T-DF-2
        let cur = AppData(), inc = AppData()
        let t = TaskItem(name: "Pump check"); cur.tasks = [t]
        let tb = TaskItem(id: t.id, name: "Pump check")
        let e = Equipment(name: "Deck crane")
        let winch = Component(name: "Winch"); winch.container.files = [FileItem(name: "manual.pdf", path: "p")]
        e.components = [winch]; e.taskIds = [t.id]
        inc.tasks = [tb]; inc.equipment = [e]
        #expect(render(DataDiff.compare(current: cur, incoming: inc).roots) ==
                ["+ [Equipment/Area] Deck crane", "  + component: Winch", "    + file: manual.pdf", "  + linked task: Pump check"])
    }

    @Test func stepsComponentsAndLinks() {
        // TV: 01 §7.8 step done / notes line / linked subtask id; 08 T-DF-3, T-DF-7
        let cur = AppData(), inc = AppData()
        let p = Procedure(name: "P"); let s = ChecklistStep(title: "Test alarms"); p.steps = [s]
        let pb = Procedure(id: p.id, name: "P"); let sb = ChecklistStep(id: s.id, title: "Test alarms"); sb.done = true
        let unknown = UUID(); sb.taskIds = [unknown, unknown]; pb.steps = [sb]
        let e = Equipment(name: "E"); let c = Component(name: "c", notes: "a"); e.components = [c]
        let eb = Equipment(id: e.id, name: "E"); eb.components = [Component(id: c.id, name: "c", notes: "b")]
        cur.procedures = [p]; inc.procedures = [pb]; cur.equipment = [e]; inc.equipment = [eb]
        let lines = render(DataDiff.compare(current: cur, incoming: inc).roots)
        #expect(lines == ["~ [Equipment/Area] E", "  ~ component: c", "    ~ notes line: \"a\" \u{2192} \"b\"",
                          "~ [Procedure] P", "  ~ step: Test alarms", "    ~ done: False \u{2192} True",
                          "    + linked task: (unknown)"])
    }

    @Test func snipNotesAndNotCovered() {
        // TV: 01 §7.8 Snip / PlainText / identical / crew-only; 08 T-DF-4, T-DF-5, T-DF-9
        #expect(DataDiff.snip("a\r\nb") == "a  b")
        #expect(DataDiff.snip("line1\r\nline2") == "line1  line2")
        let s45 = String(repeating: "0123456789", count: 4) + "abcde"
        #expect(DataDiff.snip(s45) == String(repeating: "0123456789", count: 4) + "\u{2026}")
        #expect(DataDiff.snip(nil) == "")

        let cur = AppData(), inc = AppData()
        let t = TaskItem(name: "T"); t.container.richTextXaml = "<Paragraph><Run>Hi</Run></Paragraph>"
        let tb = TaskItem(id: t.id, name: "T"); tb.container.richTextXaml = "<Paragraph><Run FontWeight=\"Bold\">Hi</Run></Paragraph>"
        tb.tags = ["new"]
        cur.tasks = [t]; inc.tasks = [tb]
        let crew = CrewMember(); crew.lastName = "Cruz"; inc.crew = [crew]
        let r = DataDiff.compare(current: cur, incoming: inc)
        #expect(!r.hasChanges && r.roots.isEmpty)
        #expect(!DataDiff.compare(current: AppData(), incoming: AppData()).hasChanges)
        tb.container.richTextXaml = "<Paragraph><Run>Hello</Run></Paragraph>"
        #expect(render(DataDiff.compare(current: cur, incoming: inc).roots).contains("  ~ notes: \"Hi\" \u{2192} \"Hello\""))
    }

    @Test func fileKeysAreCountAware() {
        // TV: 08 T-DF-8; OC-13 / 01 §8 D-10 (duplicates never crash)
        let cur = AppData(), inc = AppData()
        let t = TaskItem(name: "T"); t.container.files = [FileItem(name: "a.pdf", path: "files/1_a.pdf")]
        let tb = TaskItem(id: t.id, name: "T"); tb.container.files = [FileItem(name: "b.pdf", path: "files/1_a.pdf")]
        cur.tasks = [t]; inc.tasks = [tb]
        #expect(render(DataDiff.compare(current: cur, incoming: inc).roots) == ["~ [Task] T", "  + file: b.pdf", "  - file: a.pdf"])

        let link = FileItem(name: "web", path: "https://x", isLink: true)
        t.container.files = [link, FileItem(name: "web", path: "https://x", isLink: true)]
        tb.container.files = [FileItem(name: "web", path: "https://x", isLink: true)]
        #expect(render(DataDiff.compare(current: cur, incoming: inc).roots) == ["~ [Task] T", "  - file: web"])
        tb.container.files = t.container.files.map { FileItem(name: $0.name, path: $0.path) }
        #expect(!DataDiff.compare(current: cur, incoming: inc).hasChanges)
    }

    @Test func ageVerdicts() {
        // TV: 01 §7.9; 08 T-DF-10
        let inc = NetDateTime(year: 2026, month: 9, day: 29, hour: 10, kind: .local)
        let cur = NetDateTime(year: 2026, month: 9, day: 28, hour: 9, kind: .local)
        #expect(AgeVerdict.text(incoming: inc, current: cur)
                == "Incoming saved: 2026-09-29 10:00:00\nCurrent saved:  2026-09-28 09:00:00\n\u{279C} The incoming data is NEWER than your current data.")
        #expect(AgeVerdict.text(incoming: nil, current: cur)
                == "Incoming saved: (no save date)\nCurrent saved:  2026-09-28 09:00:00\n\u{279C} The incoming data has no save date (older format); it may be older.")
        #expect(AgeVerdict.text(incoming: nil, current: nil).hasSuffix("\n\u{279C} Neither copy has a save date; relative age is unknown."))
        #expect(AgeVerdict.text(incoming: inc, current: nil).hasSuffix("\u{279C} Your current data has no save date; relative age is unknown."))
        #expect(AgeVerdict.text(incoming: cur, current: inc).hasSuffix("\u{279C} The incoming data is OLDER than your current data."))
        #expect(AgeVerdict.text(incoming: inc, current: inc).hasSuffix("\u{279C} The incoming data is the SAME age as your current data."))
        let a = NetDateTime(parsing: "2026-09-29T14:00:00+03:00", zone: TZ.athens)!
        let b = NetDateTime(parsing: "2026-09-28T10:00:00+03:00", zone: TZ.athens)!
        #expect(AgeVerdict.text(incoming: a, current: b).hasPrefix("Incoming saved: 2026-09-29 14:00:00\nCurrent saved:  2026-09-28 10:00:00\n"))
        let tick = a.addingTicks(1)
        #expect(AgeVerdict.text(incoming: tick, current: a).contains("NEWER"))
    }

    @Test func otherDataSection() {
        // DECISIONS 01 Q-3
        let cur = AppData(), inc = AppData()
        let m = CrewMember(); m.firstName = "Ana"; m.lastName = "Cruz"; m.rank = "AB"
        let mb = CrewMember(id: m.id); mb.firstName = "Ana"; mb.lastName = "Cruz"; mb.rank = "OS"
        let s = ChecklistStep(title: "Medical"); m.checklist = [s]
        let sb = ChecklistStep(id: s.id, title: "Medical"); sb.done = true; mb.checklist = [sb]
        cur.crew = [m]; inc.crew = [mb, CrewMember()]
        let tpl = ChecklistTemplate(name: "Deck", items: [ChecklistTemplateItem(title: "a")])
        let tplB = ChecklistTemplate(id: tpl.id, name: "Deck", items: [ChecklistTemplateItem(title: "a2"), ChecklistTemplateItem(title: "b")])
        cur.checklistTemplates = [tpl]; inc.checklistTemplates = [tplB]
        let port = PortRecord(name: "Bonny", country: "Nigeria", unLocode: "NGBON")
        let portB = PortRecord(id: port.id, name: "Bonny", country: "Nigeria", unLocode: "NGBON",
                               visits: [PortVisit(vesselName: "Alpha", arrivalDate: "2026-05-01", arrivalTime: "08:00")])
        cur.ports = [port]; inc.ports = [portB]
        inc.sire.setStatus(.checked, for: "1.2.3")
        inc.sire.toggleBookmark("4.5")
        cur.scheduleTemplates = [ScheduleTemplate(name: "Old rota")]

        let r = DataDiff.compareOtherData(current: cur, incoming: inc)
        let lines = render(r.roots)
        #expect(lines.contains("+ [Crew member] (unnamed)"))
        #expect(lines.contains("~ [Crew member] Ana Cruz"))
        #expect(lines.contains("  ~ Rank: \"AB\" \u{2192} \"OS\""))
        #expect(lines.contains("    ~ done: False \u{2192} True"))
        #expect(lines.contains("~ [Saved list] Deck"))
        #expect(lines.contains("  + item: b"))
        #expect(lines.contains("~ [Port] Bonny (NGBON), Nigeria"))
        #expect(lines.contains("  + visit: Alpha 2026-05-01 08:00"))
        #expect(lines.contains("~ [SIRE] session"))
        #expect(lines.contains("  ~ Q1.2.3 status: None \u{2192} Checked"))
        #expect(lines.contains("  + bookmark: Q4.5"))
        #expect(lines.contains("- [Saved schedule] Old rota"))
        #expect(r.added == 1 && r.removed == 1 && r.changed == 4)
        #expect(!DataDiff.compareOtherData(current: AppData(), incoming: AppData()).hasChanges)
        // The Windows-scope diff never shows any of it (DATA-103).
        #expect(!DataDiff.compare(current: cur, incoming: inc).hasChanges)
    }
}
