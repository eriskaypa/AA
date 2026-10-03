// Tests: Stage V round 2 findings for W-SIRE — design rule 18 (AppKit logged "reentrant operation in its
//        NSTableView delegate" whenever the SIRE question list filled or a filter added rows; `SireStagedRows` turns
//        such publishes into a rebuild whose first block goes in before the rest) and design rule 9 / DECISIONS Stage V ruling (the SIRE body is an inset
//        paper page, like the container editor). The binary-level journey (snapshot run of TabSire with
//        AA_SIRE_SELECT, stderr grep for "reentrant") is recorded in Docs/Progress/W-SIRE.md.
import Foundation
import Testing
@testable import AACore

/// A stand-in element (the SIRE list uses `SireQuestion`, whose id is the question number).
private struct Q: Identifiable, Equatable, Sendable {
    let id: String
}

@Suite struct SireListStagingTests {
    private static func qs(_ range: Range<Int>) -> [Q] { range.map { Q(id: "q\($0)") } }
    private static func ids(_ rows: [Q]) -> [String] { rows.map(\.id) }

    // V2-J7 / V2-DESIGN: the first fill of the bank (0 → 410) shows 40 rows, then all 410 on reveal(), appended
    // after the first block with the same row identities.
    @Test func firstFillOfTheBankIsStaged() {
        var s = SireStagedRows<Q>()
        #expect(s.seed == 40)
        do { let r = s.publish(Self.qs(0..<410)); #expect(r) }
        #expect(s.rows == Self.qs(0..<40))
        #expect(s.isStaged)
        #expect(s.generation == 1)
        let firstKeys = s.keyed.map(\.id)
        do { let r = s.reveal(); #expect(r) }
        #expect(s.rows == Self.qs(0..<410))
        #expect(!s.isStaged)
        #expect(Array(s.keyed.map(\.id).prefix(40)) == firstKeys)      // reveal appends; the first block keeps its rows
        do { let r = s.reveal(); #expect(!r) }                                             // nothing left to add
    }

    // Measured warnings: 24 → 410 (search cleared), 198 → 148 (evidence), 106 → 99 (search). Every publish that adds
    // rows is a rebuild: new identities for every row, first block then the rest.
    @Test func publishesThatAddRowsRebuild() {
        var s = SireStagedRows<Q>()
        s.publish(Self.qs(0..<410)); s.reveal()
        do { let r = s.publish(Array(Self.qs(0..<410).filter { $0.id.hasSuffix("2") })); #expect(!r) }   // 410 → 41: removal only
        #expect(s.generation == 1)
        let before = s.generation
        do { let r = s.publish(Self.qs(0..<410)); #expect(r) }                                            // search cleared: rebuild, staged
        #expect(s.generation == before + 1)
        #expect(s.rows.count == 40)
        s.reveal()
        #expect(s.rows.count == 410)
        s.publish(Self.qs(100..<206)); s.reveal()                                       // "valve"
        let g = s.generation
        do { let r = s.publish(Self.qs(150..<180) + [Q(id: "x1")]); #expect(!r) }                       // "alarm": adds one row, 31 ≤ seed
        #expect(s.generation == g + 1)
        #expect(!s.isStaged)
        #expect(Self.ids(s.rows).last == "x1")
        // Every row identity changed, so the table drops the old rows instead of interleaving inserts.
        #expect(Set(s.keyed.map(\.id.generation)) == [g + 1])
    }

    // Measured silent: removals and re-sorts are a plain diff (no rebuild, identities kept).
    @Test func removalsAndResortsAreAPlainDiff() {
        var s = SireStagedRows<Q>()
        s.publish(Self.qs(0..<410)); s.reveal()
        let g = s.generation
        do { let r = s.publish(Array(Self.qs(0..<410).reversed())); #expect(!r) }                       // re-sort
        #expect(s.generation == g)
        #expect(s.rows.first?.id == "q409")
        do { let r = s.publish(Self.qs(0..<24)); #expect(!r) }                                            // search narrows
        #expect(s.generation == g)
        do { let r = s.publish([]); #expect(!r) }                                                         // no match
        #expect(s.generation == g)
        #expect(s.rows.isEmpty)
        #expect(s.keyed.isEmpty)
    }

    // Small rebuilds (≤ seed rows) go in at once; exactly `seed` rows is not staged.
    @Test func smallRebuildsAreNotStaged() {
        var s = SireStagedRows<Q>()
        do { let r = s.publish(Self.qs(0..<40)); #expect(!r) }
        #expect(s.rows.count == 40)
        #expect(s.generation == 1)
        do { let r = s.publish(Self.qs(0..<41)); #expect(r) }
        #expect(s.rows.count == 40)
    }

    // A publish while a reveal is pending supersedes it; the stale reveal is a no-op.
    @Test func laterPublishSupersedesAPendingReveal() {
        var s = SireStagedRows<Q>()
        s.publish(Self.qs(0..<410))
        #expect(s.isStaged)
        do { let r = s.publish(Self.qs(0..<7)); #expect(!r) }                     // the user typed a search before the reveal
        #expect(s.rows == Self.qs(0..<7))
        #expect(!s.isStaged)
        do { let r = s.reveal(); #expect(!r) }
        #expect(s.rows.count == 7)
        do { let r = s.publish(Self.qs(300..<410)); #expect(r) }                   // and another one that adds rows
        #expect(s.rows == Self.qs(300..<340))
        do { let r = s.publish(Self.qs(300..<320)); #expect(!r) }                  // narrowing the staged block is a plain diff
        #expect(!s.isStaged)
        do { let r = s.reveal(); #expect(!r) }
        #expect(s.rows.count == 20)
    }

    // The scroll target of a question is its row in the current generation.
    @Test func keysFollowTheGeneration() {
        var s = SireStagedRows<Q>()
        s.publish(Self.qs(0..<10))
        #expect(s.key(for: "q3") == s.keyed[3].id)
        s.publish(Self.qs(0..<12))
        #expect(s.key(for: "q3") == s.keyed[3].id)
        #expect(s.key(for: "q3").generation == 2)
    }

    @Test func seedIsAtLeastOne() {
        #expect(SireStagedRows<Q>(seed: 0).seed == 1)
    }

    // MARK: App wiring (the AA target is not testable; these guard the source the fix lives in)

    private static var macRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()      // Sire
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()   // mac/
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: macRoot.appending(path: path), encoding: .utf8)
    }

    /// Only the code, without `//` comments (so a comment cannot satisfy or trip a check).
    private static func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            guard let r = line.range(of: "//") else { return line }
            return line[..<r.lowerBound]
        }.joined(separator: "\n")
    }

    @Test func questionListRendersTheStagedRows() throws {
        let tab = Self.code(try Self.source("Sources/AA/Sire/SireTabView.swift"))
        #expect(tab.contains("ForEach(vm.listRows.keyed)"))
        #expect(tab.contains(".tag(row.element.questionNumber)"))      // selection survives a rebuild (SIRE-015)
        #expect(tab.contains("proxy.scrollTo(vm.listRows.key(for:"))
        #expect(!tab.contains("ForEach(vm.displayed)"))
        let vm = Self.code(try Self.source("Sources/AA/Sire/SireViewModel.swift"))
        #expect(vm.contains("listRows.publish("))
        #expect(vm.contains("listRows.reveal()"))
        // Nothing but the stager writes the rows the List shows (the declaration is the only assignment).
        #expect(vm.components(separatedBy: "listRows = ").count == 2)
        #expect(vm.contains("private(set) var listRows = SireStagedRows<SireQuestion>()"))
    }

    @Test func sireBodyIsAnInsetPaperPage() throws {
        let pane = Self.code(try Self.source("Sources/AA/Sire/SireDetailPane.swift"))
        guard let start = pane.range(of: "struct SireBodyCard") else { Issue.record("SireBodyCard missing"); return }
        let card = String(pane[start.lowerBound...])
        guard let editor = card.range(of: "SireBodyEditor(controller: controller)") else {
            Issue.record("SireBodyEditor missing from SireBodyCard"); return
        }
        let paper = String(card[editor.upperBound...].prefix(700))
        #expect(paper.contains("RoundedRectangle(cornerRadius: EditorPane.paperRadius"))
        #expect(paper.contains("strokeBorder(AAColor.border, lineWidth: 1)"))
        #expect(paper.contains("colorScheme == .dark ? 0.45 : 0"))
        #expect(paper.contains(".padding(EditorPane.paperInset)"))
        #expect(card.contains(".background(AAColor.panelAlt)"))
        // Rule 11: the body hint wraps (no one-line truncation in the card).
        #expect(!card.contains(".lineLimit(1)"))
    }
}
