// Tests for the crew schedule builder: 06 §7.2 (NormTime), §7.9 (timeline grouping), §7.11 (capture/apply through F2),
// 09 §7.14 (schedule vectors), BUILD-111…124 texts and operations (incl. the DECISIONS 06 additive log entries), and the
// crew editor's Details form (09 CREW-071…074, DECISIONS 09 Q4).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct CrewScheduleTests {
    static let en = Locale(identifier: "en_US_POSIX")

    @Test func normTime() {
        // TV: 06 §7.2 and 09 §7.14 NormTime
        let cases = ["7:05": "07:05", " 9:30 ": "09:30", "09:30": "09:30", "25:99": "25:99", "123:45": "", "9:5": "",
                     "930": "", "12:345": "", "": "", "8:05": "08:05", "08:05": "08:05", " 7:30 ": "07:30", "8:5": "",
                     "0730": "", "\u{0669}:\u{0663}\u{0660}": ""]
        for (input, want) in cases { #expect(CrewScheduleTime.normalize(input) == want, "\(input)") }
    }

    func entries(_ pairs: [(String, String)]) -> [ScheduleEntry] { pairs.map { ScheduleEntry(title: $0.0 + $0.1, date: $0.0, time: $0.1) } }

    @Test func timelineGroups06() {
        // TV: 06 §7.9 (today 2026-09-29, Tuesday, en-US)
        let e = entries([("2026-10-02", "09:00"), ("2026-09-29", ""), ("2026-09-29", "08:30"), ("2026-09-30", "07:00"),
                         ("", ""), ("garbage", "10:00"), ("2026/10/03", "")])
        let g = CrewScheduleTimeline.groups(e, today: CrewTestDates.today, locale: Self.en)
        #expect(g.map(\.label) == ["Today", "Tomorrow", "Fri, 2026-10-02", "Sat, 2026-10-03", "(no date)"])
        #expect(g.map(\.count) == [2, 1, 1, 1, 2])
        #expect(g[0].entryIDs == [e[1].id, e[2].id])
        #expect(g[4].entryIDs == [e[4].id, e[5].id])
        #expect(CrewScheduleTimeline.header(g[0]) == "\u{1F5D3} Today")
    }

    @Test func timelineGroups09() {
        // TV: 09 §7.14 timeline order
        let e = entries([("2026-10-02", "09:00"), ("2026-10-01", ""), ("", "08:00"), ("2026-10-01", "07:30")])
        var g = CrewScheduleTimeline.groups(e, today: CrewTestDates.today, locale: Self.en)
        #expect(g.map(\.label) == ["Thu, 2026-10-01", "Fri, 2026-10-02", "(no date)"])
        #expect(g[0].entryIDs == [e[1].id, e[3].id])
        g = CrewScheduleTimeline.groups(e, today: CivilDate(year: 2026, month: 9, day: 30)!, locale: Self.en)
        #expect(g.map(\.label) == ["Tomorrow", "Fri, 2026-10-02", "(no date)"])
    }

    @Test func countLineAndTexts() {
        // TV: 06 BUILD-120, BUILD-114, BUILD-122, 09 §7.14 Sanitize
        #expect(CrewScheduleTimeline.countLine([]) == "No entries yet — pick a date, choose what, and click \u{201C}+ Add\u{201D}.")
        let e = entries([("", ""), ("", "")])
        #expect(CrewScheduleTimeline.countLine([e[0]]) == "1 entry")
        e[1].done = true
        #expect(CrewScheduleTimeline.countLine(e) == "2 entries \u{00B7} 1 done")
        #expect(CrewScheduleText.noItems(.task) == "No Task items exist yet to schedule.")
        #expect(CrewScheduleText.pickPrompt(.equipment) == "Pick a Equipment to schedule")
        #expect(CrewScheduleText.applyQuestion(name: "Rot", count: 1, crew: "Juan Cruz")
                == "Apply 'Rot' (1 entries) to Juan Cruz.\n\nYes = replace this crew's schedule\nNo = append\nCancel = nothing")
        #expect(CrewScheduleText.applied(1, crew: "J") == "Applied 1 entry to J.")
        #expect(CrewScheduleText.exportFileName(fullName: "Juan/Cruz:") == "Schedule-Juan_Cruz_.aasched.json")
        #expect(CrewScheduleText.exportFileName(fullName: "  ") == "Schedule-crew.aasched.json")
        #expect(CrewScheduleText.saved("Rot") == "Saved 'Rot'. You can apply it to any crew member.")
    }

    @Test func operations() throws {
        // 06 BUILD-114…122, 09 §7.14 ApplyToCrew; DECISIONS 06 additive logs
        let made = StoreFactory.make(clock: CrewTestDates.clock); let store = made.store
        let vessel = Vessel(); vessel.name = "MV Atlas"; store.data.vessels = [vessel]
        let t2 = TaskItem(); t2.name = "b pump"; let t1 = TaskItem(); t1.name = "A pump"
        store.data.tasks = [t2, t1]
        #expect(CrewScheduleOps.candidates(.task, data: store.data).map(\.name) == ["A pump", "b pump"])
        #expect(CrewScheduleOps.candidates(.note, data: store.data).isEmpty)

        let crew = CrewMember(); crew.firstName = "Juan"; crew.lastName = "Cruz"
        store.data.crew = [crew]
        #expect(CrewScheduleOps.addEntry(to: crew, title: "  ", kind: .note, refID: nil, date: nil, time: "", store: store) == nil)
        let e1 = try #require(CrewScheduleOps.addEntry(to: crew, title: " Drill ", kind: .task, refID: t1.id,
                                                       date: CivilDate(year: 2026, month: 10, day: 1), time: "8:00", store: store))
        #expect(e1.title == "Drill" && e1.refId == t1.id && e1.date == "2026-10-01" && e1.time == "08:00" && e1.kind == .task)
        #expect(store.data.log.last?.kind == "Schedule entry" && store.data.log.last?.detail == "Juan Cruz")
        let note = try #require(CrewScheduleOps.addEntry(to: crew, title: "Note", kind: .note, refID: t1.id, date: nil,
                                                         time: "x", store: store))
        #expect(note.refId == nil && note.date == "" && note.time == "")
        #expect(!CrewScheduleOps.editTitle(note, to: "  ") && note.title == "Note")
        #expect(CrewScheduleOps.editTitle(note, to: " Brief ") && note.title == "Brief")

        crew.scheduleVesselId = vessel.id
        #expect(CrewScheduleOps.selectedVessel(crew, data: store.data) == vessel.id)
        #expect(CrewScheduleOps.vesselChoices(store.data).map(\.name) == ["(none)", "MV Atlas"])
        let t = CrewScheduleOps.saveAsTemplate(crew, name: " Rot ", store: store)
        #expect(t.name == "Rot" && t.vesselId == vessel.id && t.vesselName == "MV Atlas" && t.entries.count == 2)
        #expect(store.data.scheduleTemplates.count == 1)
        #expect(store.data.log.last?.kind == "Schedule" && store.data.log.last?.name == "Rot" && store.data.log.last?.detail == "2 entries")

        let other = CrewMember(); other.firstName = "Ann"; let v9 = UUID(); other.scheduleVesselId = v9
        other.schedule = [ScheduleEntry(title: "old")]
        #expect(CrewScheduleOps.apply(t, to: other, replace: true, store: store) == 2)
        #expect(other.schedule.map(\.title) == ["Drill", "Brief"] && other.scheduleVesselId == vessel.id)
        #expect(other.schedule.allSatisfy { !$0.done } && other.schedule[0].id != e1.id)
        let noVessel = ScheduleTemplate(name: "x", entries: [ScheduleEntry(title: "z")])
        other.scheduleVesselId = v9
        #expect(CrewScheduleOps.apply(noVessel, to: other, replace: false, store: store) == 1)
        #expect(other.schedule.count == 3 && other.scheduleVesselId == v9)
        #expect(store.data.log.last?.detail == "1 entry applied to Ann")

        CrewScheduleOps.deleteEntry(note, from: crew, store: store)
        #expect(crew.schedule.map(\.title) == ["Drill"] && store.data.log.last?.action == "Removed")

        // A dangling vessel id shows (none) but stays stored.
        crew.scheduleVesselId = UUID()
        #expect(CrewScheduleOps.selectedVessel(crew, data: store.data) == nil && crew.scheduleVesselId != nil)
    }

    @Test func exportAndImport() throws {
        // TV: 09 §7.14 ImportJson; 06 §7.11; BUILD-123/124
        let made = StoreFactory.make(clock: CrewTestDates.clock); let store = made.store
        let crew = CrewMember(); crew.firstName = "Juan"
        crew.schedule = [ScheduleEntry(title: "Drill briefing", kind: .procedure, date: "2026-10-01", time: "08:00", notes: "n")]
        let data = try CrewScheduleOps.exportData(crew, store: store)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"Name\": \"Juan schedule\"") && text.contains("\"VesselId\": null") && text.contains("\"Kind\": 2"))
        #expect(store.data.scheduleTemplates.isEmpty)
        let imported = try CrewScheduleOps.importTemplate(data, store: store)
        #expect(imported.name == "Juan schedule" && imported.entries.count == 1 && imported.entries[0].notes == "n")
        #expect(imported.entries[0].id != crew.schedule[0].id && store.data.scheduleTemplates.count == 1)
        do {
            _ = try CrewScheduleOps.importTemplate(Data("null".utf8), store: store)
            Issue.record("expected a failure")
        } catch {
            #expect(CrewScheduleText.importFailed(error.localizedDescription) == "Could not import the schedule:\n\nThis file is not a valid schedule.")
        }
    }
}

@MainActor
@Suite struct CrewEditorFormTests {
    @Test func formShape() {
        // TV: 09 CREW-071
        #expect(CrewEditorForm.sections.map(\.heading) == ["Identity", "Employment & Sign-On / Sign-Off", "Travel Documents",
                                                           "Certificates & Medical", "Physical", "Next of Kin"])
        #expect(CrewEditorForm.allFields.count == 33)
        #expect(CrewEditorForm.allFields.filter(\.isDate).count == 10)
        let signOff = CrewEditorForm.allFields.first { $0.key == "SignOffDate" }
        #expect(signOff?.label == "Sign-off date  (contract)" && signOff?.emphasised == true)
        #expect(CrewEditorForm.heading(fullName: "") == "Edit crew member — (unnamed)")
        for f in CrewEditorForm.allFields { #expect(CrewMember.stringKeys.contains(f.key)) }
    }

    @Test func saveRules() {
        // TV: 09 CREW-072…074 (+ DECISIONS 09 Q4)
        let m = CrewMember()
        m.firstName = "Juan"; m.signOffDate = "03/04/2026"; m.dateOfBirth = "2026-3-4"; m.passportExpiry = "garbage"
        m.userType = "Crew"; m.signOnPortRaw = "Raw"
        var d = CrewEditorForm.draft(of: m)
        #expect(d["SignOffDate"] == "03/04/2026" && d["FirstName"] == "Juan")
        d["FirstName"] = "  Juan Carlos  "
        d["LastName"] = nil
        d["SignOnDate"] = " 2026-05-01T10:00 "
        d["HealthCertExpiry"] = "   "
        CrewEditorForm.apply(d, to: m)
        #expect(m.firstName == "Juan Carlos" && m.lastName == "")
        #expect(m.dateOfBirth == "2026-03-04")                 // unambiguous legacy text normalised (parity)
        #expect(m.signOffDate == "03/04/2026")                 // Q4: not re-read month-first
        #expect(m.passportExpiry == "garbage")                 // unparseable kept verbatim
        #expect(m.signOnDate == "2026-05-01" && m.healthCertExpiry == "")
        #expect(m.userType == "Crew" && m.signOnPortRaw == "Raw")   // not editable
        #expect(CrewEditorForm.pickerDate("03/04/2026") == nil)
        #expect(CrewEditorForm.pickerDate("2026-03-04") == CivilDate(year: 2026, month: 3, day: 4))
        #expect(CrewEditorForm.dateHint("03/04/2026")?.hasPrefix("Day and month") == true)
        #expect(CrewEditorForm.dateHint("2026-03-04") == nil && CrewEditorForm.dateHint("") == nil)
        #expect(CrewEditorForm.dateHint("zz") == "Not a date AA recognises — it is kept as typed.")
    }
}
