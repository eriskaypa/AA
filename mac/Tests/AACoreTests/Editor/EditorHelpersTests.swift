// TV: 05 §7.3 (insert-table size vectors incl. the Mac overflow fix; BuildLines vectors and footers), 06 §7.12
//     (insert-into-note lines), 06 BUILD-145 B5 (blank / non-ASCII digits → 3×3), 05 CONT-031 / K-14 (link
//     normalisation), CONT-048 (grouping in arranged order, search on name or item title), CONT-064 (hint throttle).
import AppKit
import Foundation
import Testing
@testable import AACore

@Suite struct EditorTablePlanTests {
    // TV: 05 §7.3 regex rows
    @Test(arguments: [
        ("3x4", 3, 4), (" 10 X 2 ", 10, 2), ("2*5", 2, 5), ("100x100", 50, 20), ("0x0", 1, 1), ("abc", 3, 3),
        ("3x", 3, 3), ("3\u{00D7}4", 3, 3), ("99999999999x2", 50, 2), ("", 3, 3), ("   ", 3, 3),
        ("\u{0663}x4", 3, 3),           // Arabic-Indic digit: no match on the Mac (B5)
        ("1x1", 1, 1), ("50x20", 50, 20), ("51X21", 50, 20), ("\t4 * 6\n", 4, 6), ("4x6x2", 3, 3),
    ])
    func parse(_ text: String, _ rows: Int, _ cols: Int) {
        let r = EditorTablePlan.parse(text)
        #expect(r.rows == rows && r.columns == cols, "\(text)")
    }

    @Test func nilIsDefault() {
        let r = EditorTablePlan.parse(nil)
        #expect(r.rows == 3 && r.columns == 3)
    }

    // TV: 06 Add. row 33 — exact prompt texts
    @Test func promptTexts() {
        #expect(EditorTablePlan.promptTitle == "Insert table")
        #expect(EditorTablePlan.promptLabel == "Size as rows x columns (e.g. 3x4):")
        #expect(EditorTablePlan.promptInitial == "3x3")
    }
}

@Suite struct EditorSavedListLinesTests {
    // TV: 05 §7.3 BuildLines
    static let items = [
        EditorSavedListItemInfo(title: "Check oil", minutes: 60),
        EditorSavedListItemInfo(title: "", minutes: 30),
        EditorSavedListItemInfo(title: "  Log  ", minutes: 0),
        EditorSavedListItemInfo(title: "Test", minutes: 15),
    ]

    @Test func buildLinesWithoutDuration() {
        #expect(EditorSavedListInsert.lines(Self.items, includeDuration: false) == ["Check oil", "Log", "Test"])
    }

    @Test func buildLinesWithDuration() {
        #expect(EditorSavedListInsert.lines(Self.items, includeDuration: true)
                == ["Check oil  (60 min)", "Log", "Test  (15 min)"])
    }

    @Test func previews() {
        let lines = EditorSavedListInsert.lines(Self.items, includeDuration: true)
        #expect(EditorSavedListInsert.preview(lines, numbered: true) == "1. Check oil  (60 min)\n2. Log\n3. Test  (15 min)")
        #expect(EditorSavedListInsert.preview(lines, numbered: false) == "• Check oil  (60 min)\n• Log\n• Test  (15 min)")
        #expect(EditorSavedListInsert.preview([], numbered: true) == "(this saved list has no items)")
    }

    // TV: 05 §7.3 footers
    @Test func footers() {
        let withExtras = [EditorSavedListItemInfo(title: "a", minutes: 0, hasNotes: true, fileCount: 2),
                          EditorSavedListItemInfo(title: "b", minutes: 0), EditorSavedListItemInfo(title: "c", minutes: 0)]
        #expect(EditorSavedListInsert.footer(lineCount: 3, items: withExtras)
                == "3 lines will be inserted. Not carried over: 1 item has notes, 2 attached files.")
        #expect(EditorSavedListInsert.footer(lineCount: 1, items: [EditorSavedListItemInfo(title: "x", minutes: 0)])
                == "1 line will be inserted.")
        let many = [EditorSavedListItemInfo(title: "a", minutes: 0, hasNotes: true, fileCount: 1),
                    EditorSavedListItemInfo(title: "b", minutes: 0, hasNotes: true)]
        #expect(EditorSavedListInsert.footer(lineCount: 2, items: many)
                == "2 lines will be inserted. Not carried over: 2 items have notes, 1 attached file.")
        #expect(EditorSavedListInsert.footer(lineCount: 0, items: [EditorSavedListItemInfo(title: " ", minutes: 0, fileCount: 3)])
                == "0 lines will be inserted. Not carried over: 3 attached files.")
    }

    // TV: 06 §7.12
    @Test func insertIntoNoteVector() {
        let items = [EditorSavedListItemInfo(title: "Check A", minutes: 60),
                     EditorSavedListItemInfo(title: "  ", minutes: 30, hasNotes: true),
                     EditorSavedListItemInfo(title: "Check B", minutes: 0, fileCount: 1)]
        let lines = EditorSavedListInsert.lines(items, includeDuration: true)
        #expect(lines == ["Check A  (60 min)", "Check B"])
        #expect(EditorSavedListInsert.preview(lines, numbered: true) == "1. Check A  (60 min)\n2. Check B")
        #expect(EditorSavedListInsert.footer(lineCount: lines.count, items: items)
                == "2 lines will be inserted. Not carried over: 1 item has notes, 1 attached file.")
    }

    @Test func exactTexts() {
        #expect(EditorSavedListInsert.withheldTitle == "Nothing inserted")
        #expect(EditorSavedListInsert.withheldText == "This note can't be edited right now because its saved content isn't loaded — unlock it first (Tools ▸ Set / change password, then reopen).")
        #expect(EditorSavedListInsert.noListsFooter == "You have no saved lists yet. Build one in the Saved Lists tab first.")
        #expect(EditorSavedListInsert.buttonHelp == "Insert a saved list here as bullets or numbers. Your existing notes are not changed.")
    }
}

@MainActor @Suite struct EditorSavedListGroupingTests {
    static func template(_ name: String, _ titles: [String], group: UUID? = nil, notes: [String] = []) -> ChecklistTemplate {
        let items = titles.enumerated().map { i, t in
            ChecklistTemplateItem(title: t, durationMinutes: 0, isJob: false,
                                  container: Container(richTextXaml: i < notes.count ? notes[i] : ""))
        }
        return ChecklistTemplate(name: name, items: items, groupId: group)
    }

    // TV: 05 CONT-048 — arranged order, headers by first occurrence, "Ungrouped", exact group-id match
    @Test func groupsInArrangedOrder() {
        let engine = ListGroup(id: G(1), name: "Engine room")
        let deck = ListGroup(id: G(2), name: "Deck")
        let ts = [Self.template("Zeta", ["a"]), Self.template("Purifier", ["b"], group: G(1)),
                  Self.template("Mooring", ["c"], group: G(2)), Self.template("Boiler", ["d"], group: G(1)),
                  Self.template("Orphan", ["e"], group: G(99))]
        let groups = EditorSavedListInsert.groups(templates: ts, listGroups: [engine, deck], query: "")
        #expect(groups.map(\.name) == ["Ungrouped", "Engine room", "Deck"])
        #expect(groups[0].rows.map(\.display) == ["Zeta  ·  1 item", "Orphan  ·  1 item"])
        #expect(groups[1].rows.map(\.display) == ["Purifier  ·  1 item", "Boiler  ·  1 item"])
    }

    // TV: 05 §3.4 Search_Changed — name or any item title, trimmed, case-insensitive
    @Test func searchMatchesNameOrItemTitle() {
        let ts = [Self.template("Purifier overhaul", ["Open bowl", "Clean discs"]),
                  Self.template("Mooring", ["Brake lining"])]
        #expect(EditorSavedListInsert.groups(templates: ts, listGroups: [], query: "  PURIFIER ").flatMap(\.rows).count == 1)
        #expect(EditorSavedListInsert.groups(templates: ts, listGroups: [], query: "brake").flatMap(\.rows).first?.display
                == "Mooring  ·  1 item")
        #expect(EditorSavedListInsert.groups(templates: ts, listGroups: [], query: "zzz").isEmpty)
        #expect(EditorSavedListInsert.groups(templates: ts, listGroups: [], query: "").flatMap(\.rows).count == 2)
    }

    // TV: BUILD-A18 — notes counted on the raw string, blank-titled items included
    @Test func infosCountRawNotes() {
        let t = Self.template("L", ["a", " "], notes: ["", "<Section/>"])
        t.items[0].container.files = [FileItem(name: "x.pdf")]
        let infos = EditorSavedListInsert.infos(t)
        #expect(infos.map(\.hasNotes) == [false, true])
        #expect(infos.map(\.fileCount) == [1, 0])
    }
}

@Suite struct EditorLinkRulesTests {
    // TV: 05 CONT-031 — Uri.TryCreate(Absolute) + ToString()
    @Test(arguments: [
        ("https://example.com", "https://example.com/"),
        ("https://www.imo.org", "https://www.imo.org/"),
        ("  HTTPS://Example.COM/Path?q=1#x ", "https://example.com/Path?q=1#x"),
        ("http://example.com:80/a", "http://example.com/a"),
        ("https://example.com:8443", "https://example.com:8443/"),
        ("ftp://files.example.com/pub", "ftp://files.example.com/pub"),
        ("mailto:master@vessel.example", "mailto:master@vessel.example"),
        ("tel:+302101234567", "tel:+302101234567"),
        ("C:\\Manuals\\ME.pdf", "file:///C:/Manuals/ME.pdf"),
        ("\\\\server\\share\\doc.pdf", "file://server/share/doc.pdf"),
        ("https://example.com?x=1", "https://example.com/?x=1"),
    ])
    func normalises(_ input: String, _ expected: String) {
        #expect(EditorLinkRules.normalise(input) == expected)
    }

    // TV: 05 CONT-031 — silently nothing on Windows (the Mac sheet keeps Insert disabled, K-14)
    @Test(arguments: ["", "   ", "https://", "http://", "www.example.com", "example", "x:", "mailto:", "http:example.com",
                      "https://exa mple.com", "1http://x.com", "https://host:99999/"])
    func rejects(_ input: String) {
        #expect(EditorLinkRules.normalise(input) == nil, "\(input)")
    }

    @Test func sheetTexts() {
        #expect(EditorLinkRules.sheetTitle == "Insert hyperlink")
        #expect(EditorLinkRules.sheetLabel == "URL:")
        #expect(EditorLinkRules.sheetInitial == "https://")
    }

    @Test func urlFromLinkValues() {
        #expect(EditorLinkRules.url(from: URL(string: "https://a.example/")!)?.absoluteString == "https://a.example/")
        #expect(EditorLinkRules.url(from: "https://b.example/x")?.host == "b.example")
        #expect(EditorLinkRules.url(from: nil) == nil)
    }
}

@MainActor @Suite struct EditorLinkInsertionTests {
    let ink = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)
    let blue = EditorLinkRules.editorLinkColor

    // TV: 05 K-14 — empty selection inserts the normalised URL at the caret as link text
    @Test func insertAtCaret() {
        let s = NSAttributedString(string: "abc", attributes: [.foregroundColor: ink])
        let e = EditorLinkRules.insertion(url: "https://example.com/", in: s, selection: NSRange(location: 1, length: 0),
                                          typing: [.foregroundColor: ink], linkColor: blue)
        #expect(e.range == NSRange(location: 1, length: 0))
        #expect(e.replacement.string == "https://example.com/")
        #expect((e.replacement.attribute(.link, at: 0, effectiveRange: nil) as? URL)?.absoluteString == "https://example.com/")
        #expect(e.replacement.attribute(.aaLinkStyled, at: 0, effectiveRange: nil) as? Bool == true)
        #expect(e.replacement.attribute(.aaUnderlyingForeground, at: 0, effectiveRange: nil) as? NSColor == ink)
        #expect(e.selectionAfter == NSRange(location: 21, length: 0))
    }

    @Test func wrapSelection() {
        let s = NSAttributedString(string: "see manual here", attributes: [.foregroundColor: ink])
        let e = EditorLinkRules.insertion(url: "https://x.example/", in: s, selection: NSRange(location: 4, length: 6),
                                          typing: [:], linkColor: blue)
        #expect(e.replacement.string == "manual")
        #expect(e.selectionAfter == NSRange(location: 4, length: 6))
        #expect(e.replacement.attribute(.link, at: 5, effectiveRange: nil) != nil)
    }

    @Test func removingLinkRestoresInk() {
        let linked = EditorLinkRules.linkAttributes([.foregroundColor: ink], url: "https://x/", linkColor: blue)
        let back = EditorLinkRules.removingLink(linked)
        #expect(back[.link] == nil)
        #expect(back[.foregroundColor] as? NSColor == ink)
        #expect(back[.aaLinkStyled] == nil)
    }

    @Test func linkRange() {
        let m = NSMutableAttributedString(string: "go to site now")
        m.addAttribute(.link, value: URL(string: "https://s/")!, range: NSRange(location: 6, length: 4))
        #expect(EditorLinkRules.linkRange(m, at: 7) == NSRange(location: 6, length: 4))
        #expect(EditorLinkRules.linkRange(m, at: 2) == nil)
    }
}

@Suite struct EditorHintThrottleTests {
    // TV: 05 CONT-064 — at most one hint per 1.5 s
    @Test func throttles() {
        var t = EditorHintThrottle()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var shown: [Bool] = []
        for dt in [0, 1.0, 1.49, 1.5, 2.0] { shown.append(t.shouldShow(at: t0.addingTimeInterval(dt))) }
        #expect(shown == [true, false, false, true, false])
    }
}

@MainActor @Suite struct EditorFontCatalogTests {
    // TV: 05 CONT-020 — sorted case-insensitively, enumerated once
    @Test func familiesSorted() {
        let f = EditorFontCatalog.families
        #expect(!f.isEmpty)
        for (a, b) in zip(f, f.dropFirst()) { #expect(NetText.compareIgnoreCase(a, b) != .orderedDescending) }
        #expect(EditorFontCatalog.isInstalled("helvetica"))
    }

    // TV: 05 CONT-021 — parses > 0, rejects 0 / negatives / junk
    @Test func parseSize() {
        #expect(EditorFontCatalog.parseSize("16") == 16)
        #expect(EditorFontCatalog.parseSize(" 12.5 ") == 12.5)
        #expect(EditorFontCatalog.parseSize("0") == nil)
        #expect(EditorFontCatalog.parseSize("-3") == nil)
        #expect(EditorFontCatalog.parseSize("abc") == nil)
        #expect(EditorFontCatalog.parseSize("") == nil)
        #expect(EditorFontCatalog.parseSize("99999") == EditorFormatting.maxFontSize)
    }

    @Test func displaySize() {
        #expect(EditorFontCatalog.displaySize(14) == "14")
        #expect(EditorFontCatalog.displaySize(nil) == "")
        #expect(EditorFormatting.standardSizes == [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 72])
    }
}
