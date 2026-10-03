// Regression tests for the Stage V round-2 findings of W-CREW: duplicate schedule entry ids (V2-COMPAT, blocker),
// the Crew section's minimum width (V2-J5), the crew table's starting column widths (V2-J5 / V2-DESIGN) and the single
// flag of the card's Review notes header (V2-J5).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct CrewRound2RegressionTests {
    static let en = Locale(identifier: "en_US_POSIX")

    // MARK: V2-COMPAT — duplicate ScheduleEntry ids (Windows binds by reference, so such a data.json is valid there)

    @Test func duplicateScheduleIdsSurviveReloadAndResolveByPosition() throws {
        let made = StoreFactory.make(clock: CrewTestDates.clock); let store = made.store
        let m = CrewMember(); m.firstName = "Jane"; m.lastName = "Doe"
        let a = ScheduleEntry(title: "Dup entry", date: "2026-10-05", time: "09:00")
        let b = ScheduleEntry(title: "Dup entry (copy)", date: "2026-10-05", time: "09:00")
        let c = ScheduleEntry(title: "Other", date: "2026-10-01", time: "")
        b.id = a.id                                                    // the hand-edited file's duplicate Id
        m.schedule = [a, c, b]
        store.data.crew = [m]
        try store.save()

        // The duplicate survives the data.json round trip (the reader keeps both entries, as Windows does).
        let back = made.dataStore.load()
        let entries = try #require(back.crew.first).schedule
        #expect(entries.count == 3 && entries[0].id == entries[2].id)

        // The timeline addresses rows by position: one row per entry, each resolving to its own object (the view used
        // to build `Dictionary(uniqueKeysWithValues:)` from the ids and trapped here).
        let groups = CrewScheduleTimeline.groups(entries, today: CrewTestDates.today, locale: Self.en)
        #expect(groups.map(\.label) == ["Thu, 2026-10-01", "Mon, 2026-10-05"])
        #expect(groups.map(\.entryOffsets) == [[1], [0, 2]])
        #expect(groups.allSatisfy { $0.entryOffsets.count == $0.entryIDs.count })
        let resolved = groups[1].entryOffsets.map { entries[$0] }
        #expect(resolved.map(\.title) == ["Dup entry", "Dup entry (copy)"])
        #expect(resolved[0] !== resolved[1])

        // Delete is by reference (BUILD-119): removing the copy keeps the original with the same Id.
        let live = try #require(store.data.crew.first)
        CrewScheduleOps.deleteEntry(b, from: live, store: store)
        #expect(live.schedule.map(\.title) == ["Dup entry", "Other"])
    }

    @Test func groupOffsetsAreParallelToIds() {
        let e = ["2026-10-02", "2026-09-29", "", "2026-09-29"].map { ScheduleEntry(title: $0, date: $0, time: "") }
        let g = CrewScheduleTimeline.groups(e, today: CrewTestDates.today, locale: Self.en)
        for group in g {
            #expect(group.entryOffsets.map { e[$0].id } == group.entryIDs)
        }
        #expect(g.map(\.entryOffsets) == [[1, 3], [0], [2]])
    }

    // MARK: V2-J5 — the Crew section fits the main window's minimum width

    @Test func crewSectionFitsTheMainWindowMinimum() {
        // Before: 290 + 420 panes, and the split view under the floating sidebar added 2 × 228 → 1167 pt (clipped
        // below ~1170). Now the split view sits inside the safe area and the panes shrink to 240 / 340.
        #expect(CrewLayout.sectionMinWidth == CGFloat(582))         // 1 + 240 + 1 + 340
        #expect(CrewLayout.fits(window: CrewLayout.mainWindowMinWidth))
        #expect(CrewLayout.sidebarIdealWidth + CrewLayout.sectionMinWidth <= 860)
        #expect(CrewLayout.rosterMinWidth <= CrewLayout.rosterIdealWidth && CrewLayout.rosterIdealWidth <= CrewLayout.rosterMaxWidth)
    }

    // MARK: V2-J5 / V2-DESIGN — table columns start wide enough for their header and cells

    /// Monospaced stand-ins for aaMono 13 (headers) and aaMono 12 (cells).
    static func header(_ s: String) -> CGFloat { CGFloat(s.count) * 7.8 }
    static func cell(_ s: String) -> CGFloat { CGFloat(s.count) * 7.2 }

    @Test func defaultColumnsFitTheirHeaders() throws {
        for key in CrewColumns.defaultKeys {
            let col = try #require(CrewColumns.column(key))
            let w = CrewTableSizing.idealWidth(key: key, header: col.header, cells: [],
                                               measureHeader: Self.header, measureCell: Self.cell)
            #expect(w >= Self.header(col.header) + CrewTableSizing.headerChrome, "\(col.header)")
            #expect(w >= CrewTableSizing.baseWidth(key))
        }
        // The three headers that were cut (`Date of Bir…`, `Sign-Off Da…`, `Contract Stat…`) now start wide enough.
        func ideal(_ key: String) -> CGFloat {
            CrewTableSizing.idealWidth(key: key, header: CrewColumns.column(key)!.header, cells: [],
                                       measureHeader: Self.header, measureCell: Self.cell)
        }
        #expect(ideal("DateOfBirth") == 124 && ideal("SignOffDate") == 124 && ideal("ContractStatus") == 139)
        #expect(ideal("Cid") == 60)                                   // short header: the base width stays
    }

    @Test func columnsFitTheirWidestCellWithinACap() {
        let w = CrewTableSizing.idealWidth(key: "Nationality", header: "Nationality",
                                           cells: ["India", "United Kingdom", ""],
                                           measureHeader: Self.header, measureCell: Self.cell)
        #expect(w == (Self.cell("United Kingdom") + CrewTableSizing.cellChrome).rounded(.up))   // `United Kingd…` before
        let long = String(repeating: "x", count: 200)
        let capped = CrewTableSizing.idealWidth(key: "SourceFile", header: "Source File", cells: [long],
                                                measureHeader: Self.header, measureCell: Self.cell)
        #expect(capped == CrewTableSizing.maxIdealWidth)
        let empty = CrewTableSizing.idealWidth(key: "Company", header: "Company", cells: ["", ""],
                                               measureHeader: Self.header, measureCell: Self.cell)
        #expect(empty == CrewTableSizing.baseWidth("Company"))
    }

    // MARK: V2-J5 — one flag on the Review notes header

    @Test func reviewNotesHeaderHasOneFlag() {
        #expect(CrewRoster.reviewNotesLabel(2) == "Review notes (2)")
        #expect(!CrewRoster.reviewNotesLabel(2).contains("\u{2691}"))
        #expect(CrewRoster.reviewNotesTitle(2) == "\u{2691} Review notes (2)")       // CREW-024 text (accessibility)
    }
}
