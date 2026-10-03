// Tests for 02 §7.10 (T-TPL-1…9), 06 §7.10 (capture/apply), DECISIONS 02 Q-12 (skip unchanged write-back);
// 02 §7.11 (T-SCH-1…8), 06 §7.11, OC-41 (`.aasched.json` bytes: indented, CRLF, nulls, default escaping).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct SvcTemplateScheduleTests {
    private func d(_ s: String) -> NetDateTime { NetDateTime.calendarDate(CivilDate(iso: s)!) }

    private func step() -> ChecklistStep {
        let s = ChecklistStep(title: "Check A")
        s.done = true; s.deadline = d("2026-07-10"); s.isJob = true; s.durationMinutes = 45
        s.bucketIds = [UUID()]; s.taskIds = [UUID()]; s.equipmentIds = [UUID()]; s.scheduledStart = d("2026-07-09")
        s.container.richTextXaml = "<Section>X</Section>"
        s.container.files = [FileItem(name: "a.pdf", path: "files/a.pdf", kind: .document, linkedItemIds: [UUID()])]
        return s
    }

    @Test func captureFromSteps() {
        // TV: 02 T-TPL-1; 06 §7.10
        let s = step()
        let t = ChecklistTemplateService.captureFromSteps(name: "  Daily rounds ", steps: [s])
        #expect(t.name == "Daily rounds" && t.groupId == nil && t.items.count == 1)
        let it = t.items[0]
        #expect(it.title == "Check A" && it.durationMinutes == 45 && it.isJob)
        #expect(it.container.id != s.container.id && it.container.richTextXaml == "<Section>X</Section>")
        #expect(it.container.isLocked == s.container.isLocked)
        let f = it.container.files[0], g = s.container.files[0]
        #expect(f.id != g.id && f.name == g.name && f.path == g.path && f.kind == g.kind && f.added == g.added)
        #expect(f.isLink == g.isLink && f.linkInPlace == g.linkInPlace && f.linkedItemIds == g.linkedItemIds)
        let json = it.toJSON()
        #expect(json["Deadline"] == nil && json["Done"] == nil && json["TaskIds"] == nil)
    }

    @Test func captureFromSubtasksDropsNesting() {
        // TV: 02 T-TPL-2; 06 §7.10 last line
        let s1 = TaskItem(name: "S1"); s1.description = "d"; s1.subtasks = [TaskItem(name: "S1a")]
        let t = ChecklistTemplateService.captureFromSubtasks(name: "L", subtasks: [s1])
        #expect(t.items.map(\.title) == ["S1"])
        #expect(t.items[0].toJSON().keys == ["Title", "DurationMinutes", "IsJob", "Container"])
    }

    @Test func applyAndClone() {
        // TV: 02 T-TPL-3…6; 06 §7.10 apply rows
        let tpl = ChecklistTemplate(name: "Deck", items: [
            ChecklistTemplateItem(title: "Check A", durationMinutes: 45, isJob: true, container: Container(richTextXaml: "X")),
            ChecklistTemplateItem(title: "Check B")], groupId: UUID())
        let s0 = ChecklistStep(title: "s0")
        var steps = [s0]
        #expect(ChecklistTemplateService.applyToSteps(tpl, steps: &steps, replace: false) == 2)
        #expect(steps.count == 3 && steps[0] === s0)
        let n1 = steps[1]
        #expect(!n1.done && n1.deadline == nil && n1.bucketIds.isEmpty && n1.taskIds.isEmpty && n1.equipmentIds.isEmpty)
        #expect(n1.scheduledStart == nil && n1.durationMinutes == 45 && n1.isJob)
        n1.container.richTextXaml = "changed"
        #expect(tpl.items[0].container.richTextXaml == "X")

        var subs = [TaskItem(name: "x"), TaskItem(name: "y")]
        #expect(ChecklistTemplateService.applyToSubtasks(tpl, subtasks: &subs, replace: true) == 2)
        #expect(subs.map(\.name) == ["Check A", "Check B"] && subs.allSatisfy { $0.status == .todo && !$0.isComplete })
        #expect(subs[0].recurrence == .none)

        let c = ChecklistTemplateService.clone(tpl, newName: "Deck (copy)")
        #expect(c.id != tpl.id && c.groupId == tpl.groupId && c.name == "Deck (copy)")
        #expect(c.items.map(\.title) == ["Check A", "Check B"] && c.items[0].container.id != tpl.items[0].container.id)
        let task = ChecklistTemplateService.itemToTask(tpl.items[0])
        #expect(task.name == "Check A" && task.durationMinutes == 45 && task.isJob && task.status == .todo)
        #expect(task.deadline == nil && task.container.richTextXaml == "X" && task.container.id != tpl.items[0].container.id)
    }

    @Test func editRoundTrip() {
        // TV: 02 T-TPL-7; DECISIONS 02 Q-12 (no write-back when nothing changed)
        let tpl = ChecklistTemplate(name: "L", items: [ChecklistTemplateItem(title: "a"), ChecklistTemplateItem(title: "b")])
        let originalContainers = tpl.items.map(\.container.id)
        let steps = ChecklistTemplateService.toSteps(tpl)
        #expect(!ChecklistTemplateService.hasChanges(tpl, steps: steps))
        ChecklistTemplateService.writeBackFromSteps(tpl, steps: steps)
        #expect(tpl.items.map(\.container.id) == originalContainers)
        steps[0].title = "A2"; steps[0].deadline = d("2026-10-01")
        ChecklistTemplateService.writeBackFromSteps(tpl, steps: steps)
        #expect(tpl.items.map(\.title) == ["A2", "b"])
        #expect(tpl.items[0].toJSON()["Deadline"] == nil)
        #expect(tpl.items[0].container.id != originalContainers[0])
        ChecklistTemplateService.writeBackFromSteps(tpl, steps: Array(steps.prefix(1)))
        #expect(tpl.items.count == 1)
    }

    @Test func cloneContainer() {
        // TV: 02 T-TPL-8, T-TPL-9; 06 BUILD-A19
        let fresh = ChecklistTemplateService.cloneContainer(nil)
        #expect(fresh.richTextXaml.isEmpty && fresh.files.isEmpty)
        let c = Container(richTextXaml: "enc:QUJD", sharedWithContainerIds: [UUID()], isLocked: true)
        let k = ChecklistTemplateService.cloneContainer(c)
        #expect(k.isLocked && k.richTextXaml == "enc:QUJD" && k.sharedWithContainerIds == c.sharedWithContainerIds && k.id != c.id)
    }

    @Test func captureAndApplySchedules() {
        // TV: 02 T-SCH-1…4; 06 §7.11
        let data = AppData()
        let v = Vessel(name: "MV Atlas"); data.vessels = [v]
        let crew = CrewMember()
        let r1 = UUID()
        let e1 = ScheduleEntry(title: "Drill", kind: .procedure, refId: r1, date: "2026-10-02", time: "09:00", done: true, notes: "n")
        let e2 = ScheduleEntry(title: "Note")
        crew.schedule = [e1, e2]; crew.scheduleVesselId = v.id
        let t = ScheduleService.captureFromCrew(name: " Rot ", crew: crew, data: data)
        #expect(t.name == "Rot" && t.vesselId == v.id && t.vesselName == "MV Atlas" && t.entries.count == 2)
        #expect(t.entries[0].id != e1.id && !t.entries[0].done && t.entries[0].refId == r1 && t.entries[0].kind == .procedure)
        #expect(t.entries[0].notes == "n" && t.entries[0].date == "2026-10-02" && t.entries[0].time == "09:00")

        crew.scheduleVesselId = UUID()
        #expect(ScheduleService.captureFromCrew(name: "x", crew: crew, data: data).vesselName == "")

        let other = CrewMember(); let v9 = UUID(); other.scheduleVesselId = v9
        other.schedule = [ScheduleEntry(title: "old")]
        let noVessel = ScheduleTemplate(name: "nv", entries: [ScheduleEntry(title: "a")])
        #expect(ScheduleService.applyToCrew(noVessel, crew: other, replace: false) == 1)
        #expect(other.schedule.map(\.title) == ["old", "a"] && other.scheduleVesselId == v9)
        #expect(ScheduleService.applyToCrew(t, crew: other, replace: true) == 2)
        #expect(other.schedule.map(\.title) == ["Drill", "Note"] && other.scheduleVesselId == v.id)
        #expect(other.schedule[0].id != t.entries[0].id)
    }

    @Test func exportBytesAndImport() throws {
        // TV: 02 T-SCH-5, T-SCH-8; OC-41 (indented, CRLF, explicit nulls, PascalCase, ints, lower-case GUIDs)
        let t = ScheduleTemplate(id: UUID(netString: "5d1c0000-0000-0000-0000-000000000001")!, name: "Rotation A",
                                 vesselId: nil, vesselName: "",
                                 entries: [ScheduleEntry(id: UUID(netString: "9a4e0000-0000-0000-0000-000000000002")!,
                                                         title: "Safety drill", kind: .task,
                                                         refId: UUID(netString: "C1D7A0A2-7D7E-4F39-8A5D-0A4E5F2B9E10")!,
                                                         date: "2026-10-01", time: "09:00")],
                                 createdUtc: NetDateTime(parsing: "2026-09-29T08:15:30.1234567Z")!)
        t.extra.set("Unknown", .string("kept in memory only"))
        let bytes = try ScheduleService.exportJSON(t)
        let expected = [
            "{",
            "  \"Id\": \"5d1c0000-0000-0000-0000-000000000001\",",
            "  \"Name\": \"Rotation A\",",
            "  \"VesselId\": null,",
            "  \"VesselName\": \"\",",
            "  \"Entries\": [",
            "    {",
            "      \"Id\": \"9a4e0000-0000-0000-0000-000000000002\",",
            "      \"Title\": \"Safety drill\",",
            "      \"Kind\": 1,",
            "      \"RefId\": \"c1d7a0a2-7d7e-4f39-8a5d-0a4e5f2b9e10\",",
            "      \"Date\": \"2026-10-01\",",
            "      \"Time\": \"09:00\",",
            "      \"EndDate\": \"\",",
            "      \"EndTime\": \"\",",
            "      \"Done\": false,",
            "      \"Notes\": \"\"",
            "    }",
            "  ],",
            "  \"CreatedUtc\": \"2026-09-29T08:15:30.1234567Z\"",
            "}",
        ].joined(separator: "\r\n")
        #expect(String(decoding: bytes, as: UTF8.self) == expected)
        #expect(bytes.first == UInt8(ascii: "{"))                       // no BOM

        let back = try ScheduleService.importJSON(bytes)
        #expect(back.id != t.id && back.entries[0].id != t.entries[0].id)
        #expect(back.name == t.name && back.vesselId == nil && back.vesselName == "")
        #expect(back.createdUtc == t.createdUtc && back.entries[0].refId == t.entries[0].refId)
        #expect(back.entries[0].title == "Safety drill" && back.entries[0].kind == .task)
    }

    @Test func importEdgeCases() throws {
        // TV: 02 T-SCH-6, T-SCH-7; 06 §7.11 (`null`, wrong-case keys)
        do {
            _ = try ScheduleService.importJSON(Data("null".utf8))
            Issue.record("null must fail")
        } catch {
            #expect(error == .notASchedule && error.localizedDescription == "This file is not a valid schedule.")
        }
        let windows = Data("\u{FEFF}{\"Name\":\"Caf\\u00E9\",\"VesselId\":null,\"Entries\":[{\"Title\":\"x\",\"RefId\":null,\"Kind\":0}]}".utf8)
        let t = try ScheduleService.importJSON(windows)
        #expect(t.name == "Café" && t.vesselId == nil && t.entries[0].refId == nil)
        let wrongCase = try ScheduleService.importJSON(Data("{\"name\":\"x\"}".utf8))
        #expect(wrongCase.name == "" && wrongCase.entries.isEmpty)
        #expect(throws: ScheduleImportError.self) { _ = try ScheduleService.importJSON(Data("{".utf8)) }
        #expect(throws: ScheduleImportError.self) { _ = try ScheduleService.importJSON(Data("{\"Kind\":\"x\",\"Entries\":[{\"Kind\":\"1\"}]}".utf8)) }
        #expect(throws: ScheduleImportError.self) { _ = try ScheduleService.importJSON(Data("[]".utf8)) }
    }
}
