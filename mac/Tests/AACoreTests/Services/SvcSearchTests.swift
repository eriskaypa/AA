// Tests for 02 §7.7 (search, snippets, plainTextFromXaml), 08 §7.4 (T-SR-1…12); OC-11 (locked: Name + Tags);
// DECISIONS 08 OQ-7 (runs of one paragraph join — supersedes T-SR-5's "no hit"); 01 §3.15 diff plain text.
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct SvcSearchTests {
    static let ns = #"xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xml:space="preserve""#

    private func search(_ store: AppStore, _ q: String, gated: Set<UUID> = []) -> [SearchHit] {
        SearchService.search(SearchService.makeDocuments(store: store, isGated: { gated.contains($0.id) }), query: q)
    }

    private func specStore() -> StoreFactory.Made {
        let made = StoreFactory.make(); let store = made.store
        let e = Equipment(name: "Main Engine"); e.tags = ["engine", "ME"]
        e.components = [Component(name: "Fuel pump", notes: "check every 500 h")]
        let t = TaskItem(name: "Replace the fuel filter on the main engine")
        let s = TaskItem(name: "Drain water")
        s.container.richTextXaml = "<Section \(Self.ns)><Paragraph><Run>Open the drain cock</Run></Paragraph></Section>"
        t.subtasks = [s]
        let p = Procedure(name: "Bunkering"); p.steps = [ChecklistStep(title: "Sample fuel")]
        let v = Vessel(name: "Aurora")
        store.data.equipment = [e]; store.data.tasks = [t]; store.data.procedures = [p]; store.data.vessels = [v]
        return made
    }

    @Test func fuelQuery() {
        // TV: 02 §7.7 query "FUEL"
        let made = specStore(); let store = made.store
        let hits = search(store, "FUEL")
        #expect(hits.map(\.ownerHeader) == ["[Equipment] Main Engine", "[Task] Replace the fuel filter on the main engine", "[Procedure] Bunkering"])
        #expect(hits.map(\.whereLabel) == ["Component \u{203A} Name", "Name", "Step \u{203A} Title"])
        #expect(hits.map(\.snippet) == ["Fuel pump", "Replace the fuel filter on the main engine", "Sample fuel"])
        #expect(hits.map(\.matchStart) == [0, 12, 7])
        #expect(hits.allSatisfy { $0.matchLength == 4 })
        #expect(hits.map(\.kind) == [.component, .item, .step])
        #expect(hits[0].childID == store.data.equipment[0].components[0].id && hits[1].childID == nil)
        #expect(hits.map(\.id) == [0, 1, 2])
    }

    @Test func engineQueryAndLocks() {
        // TV: 02 §7.7 "engine", locked "FUEL"/"ME", blank query; 08 T-SR-8
        let made = specStore(); let store = made.store
        let hits = search(store, "engine")
        #expect(hits.map(\.whereLabel) == ["Name", "Tags", "Name"])
        #expect(hits.map(\.matchStart) == [5, 0, 36])
        #expect(hits[1].snippet == "engine, ME")
        let eq = store.data.equipment[0].id
        #expect(search(store, "FUEL", gated: [eq]).count == 2)
        #expect(search(store, "ME", gated: [eq]).contains { $0.ownerID == eq && $0.whereLabel == "Tags" })
        #expect(search(store, "   ").isEmpty)

        let secret = TaskItem(name: "Secret plan"); secret.description = "valve codes"; secret.tags = ["codes"]
        store.data.tasks.append(secret)
        let g: Set<UUID> = [secret.id]
        #expect(!search(store, "valve", gated: g).contains { $0.ownerID == secret.id })
        #expect(search(store, "secret", gated: g).first { $0.ownerID == secret.id }?.whereLabel == "Name")
        #expect(search(store, "codes", gated: g).first { $0.ownerID == secret.id }?.whereLabel == "Tags")
    }

    @Test func capAndOrder() {
        // TV: 02 §7.7 501 items → 500; 08 T-SR-9
        let made = StoreFactory.make(); let store = made.store
        store.data.tasks = (0..<600).map { TaskItem(name: "pump \($0)") }
        store.data.equipment = [Equipment(name: "pump room")]
        let hits = search(store, "pump")
        #expect(hits.count == SearchService.maxHits)
        #expect(hits.first?.ownerKind == .equipment)
    }

    @Test func subtaskContainerAndFiles() {
        // TV: 08 T-SR-12; 08 §7.8 item 5 (Subtask › Container)
        let made = specStore(); let store = made.store
        let hits = search(store, "drain cock")
        #expect(hits.map(\.whereLabel) == ["Subtask \u{203A} Container"])
        #expect(hits.first?.kind == .subtask)
        let v = store.data.vessels[0]
        v.container.files = [FileItem(name: "deck.jpg", path: "files/1_deck.jpg", kind: .image)]
        let fh = search(store, "deck")
        #expect(fh.map(\.whereLabel) == ["File \u{203A} Image", "File \u{203A} Image \u{203A} Path"])
        #expect(fh.allSatisfy { $0.kind == .file })
        let cancelled = SearchService.search(SearchService.makeDocuments(store: store, isGated: { _ in false }),
                                             query: "deck", isCancelled: { true })
        #expect(cancelled.isEmpty)
    }

    @Test func vesselRecordsAreNotSearchedOrDiffed() {
        // 10 VESSEL-283: quick cards, work orders, port calls and the ports DB are neither searched nor diffed
        let made = StoreFactory.make(); let store = made.store
        let v = Vessel(name: "Aurora")
        let card = QuickCard(); card.title = "Bilge manual"; v.quickCards = [card]
        let job = ShipJob(jobNo: "J-1"); job.title = "Bilge pump overhaul"; v.jobs = [job]
        let call = PortCall(portName: "Bilgeport"); v.portCalls = [call]
        store.data.vessels = [v]
        store.data.ports = [PortRecord(name: "Bilge harbour")]
        #expect(search(store, "bilge").isEmpty)
        let before = AppData(); let after = AppData()
        let v0 = Vessel(id: v.id, name: "Aurora")
        before.vessels = [v0]; after.vessels = [v]
        #expect(!DataDiff.compare(current: before, incoming: after).hasChanges)
    }

    @Test func snippetVectors() {
        // TV: 02 §7.7 snippet table; 08 T-SR-1…4
        func snip(_ text: String, _ q: String) -> (String, Int) {
            let idx = NetText.indexOfIgnoreCase(text, q)!
            let r = SearchService.makeSnippet(text: text, matchIndex: idx, matchLength: q.utf16.count)
            return (r.snippet, r.start)
        }
        let a = String(repeating: "a", count: 100) + "needle" + String(repeating: "b", count: 100)
        let r1 = snip(a, "needle")
        #expect(r1.0 == "\u{2026}" + String(repeating: "a", count: 60) + "needle" + String(repeating: "b", count: 60) + "\u{2026}")
        #expect(r1.0.utf16.count == 128 && r1.1 == 61)
        #expect(snip("Line one\r\n\r\n   target here", "target") == ("Line one target here", 9))
        #expect(snip("one  two three", "one  two") == ("one two three", 0))
        let x = String(repeating: "x", count: 70) + "  \n\t  KEY " + String(repeating: "y", count: 10)
        let r4 = snip(x, "key")
        #expect(r4.0 == "\u{2026}" + String(repeating: "x", count: 54) + " KEY " + String(repeating: "y", count: 10))
        #expect(r4.1 == 56)
        let c = "Check " + String(repeating: "z", count: 55) + " pump pump"
        let r5 = snip(c, "PUMP")
        #expect(r5.0 == "\u{2026}eck " + String(repeating: "z", count: 55) + " pump pump" && r5.1 == 61)
        #expect(snip("The main engine lube oil pump was overhauled", "pump") == ("The main engine lube oil pump was overhauled", 25))
        let long = String(repeating: "a", count: 200) + "PUMP" + String(repeating: "b", count: 200)
        let r7 = snip(long, "pump")
        #expect(r7.0.utf16.count == 126 && r7.1 == 61)
        #expect(snip("a\r\n\r\nPUMP", "pump") == ("a PUMP", 2))
        #expect(snip("x  y", "x  y") == ("x y", 0))
    }

    @Test func plainTextFromXaml() {
        // TV: 02 §7.7 plainTextFromXaml table; 08 T-SR-6, T-SR-7, T-SR-11
        let ns = Self.ns
        #expect(XamlPlainText.searchText("") == "")
        #expect(XamlPlainText.searchText("<Section \(ns)><Paragraph><Run>Hello</Run></Paragraph><Paragraph><Run>World</Run></Paragraph></Section>") == " Hello  World ")
        #expect(XamlPlainText.searchText("<Section \(ns)><Paragraph><Run>A</Run><LineBreak /><Run>B</Run></Paragraph></Section>") == " A  B ")
        #expect(XamlPlainText.searchText("<Section \(ns)><List><ListItem><Paragraph><Run>One</Run></Paragraph></ListItem><ListItem><Paragraph><Run>Two</Run></Paragraph></ListItem></List></Section>") == "  One   Two ")
        #expect(XamlPlainText.searchText("<Section \(ns)><Paragraph><Run>Fish &amp; chips</Run></Paragraph></Section>") == " Fish & chips ")
        #expect(XamlPlainText.searchText("<Section \(ns)><Paragraph><Run> </Run></Paragraph></Section>") == "   ")
        #expect(XamlPlainText.searchText("enc:QUJD") == "enc:QUJD")
        #expect(XamlPlainText.searchText("<Paragraph><Run>Hi</Run>") == "  Hi ")
        #expect(XamlPlainText.searchText("<Run>a</Run><Run>b</Run>") == " a  b ")
        #expect(XamlPlainText.searchText("<Paragraph><Run>AT&amp;T</Run></Paragraph>") == " AT&T ")
        #expect(XamlPlainText.searchText("<Paragraph>\n  <Run>x</Run>\n</Paragraph>") == " x ")
        #expect(XamlPlainText.searchText("<Paragraph xml:space=\"preserve\"><Run>   </Run></Paragraph>") == "     ")
        #expect(XamlPlainText.searchText("<a>x<![CDATA[y]]>z<!-- c -->w</a>") == "x z w ")
        #expect(XamlPlainText.searchText("<a>&nbsp;</a>") == " &nbsp; ")      // undefined entity → regex fallback
    }

    @Test func runsOfOneParagraphJoin() {
        // DECISIONS 08 OQ-7 (supersedes 08 T-SR-5 "q Hello → no hit"): runs join inside a paragraph
        let xaml = "<Section xml:space=\"preserve\" xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"><Paragraph><Run>Hel</Run><Run>lo</Run></Paragraph></Section>"
        #expect(XamlPlainText.searchText(xaml) == " Hello ")
        let bold = "<Section \(Self.ns)><Paragraph><Run>Fuel </Run><Bold><Run>pump</Run></Bold><Run> room</Run></Paragraph></Section>"
        #expect(XamlPlainText.searchText(bold) == " Fuel pump room ")
        let made = StoreFactory.make(); let store = made.store
        let t = TaskItem(name: "t"); t.container.richTextXaml = xaml
        store.data.tasks = [t]
        #expect(search(store, "Hello").map(\.whereLabel) == ["Notes"])
        #expect(search(store, "lo").count == 1)
    }

    @Test func diffPlainText() {
        // TV: 01 §7.8 PlainText; 08 T-DF-5 basis
        #expect(XamlPlainText.diffText("") == "")
        #expect(XamlPlainText.diffText("<Section xmlns=\"x\"><Paragraph><Run>Hello</Run><Run> &amp; </Run><Run>world</Run></Paragraph></Section>") == "Hello & world")
        #expect(XamlPlainText.diffText("<Paragraph><Run>Hi</Run></Paragraph>") == XamlPlainText.diffText("<Paragraph><Run FontWeight=\"Bold\">Hi</Run></Paragraph>"))
        #expect(XamlPlainText.diffText("a&nbsp;b &eacute; &#65;&#x42; &unknown; &#xD800;") == "a b \u{E9} AB &unknown; &#xD800;")
        #expect(XamlPlainText.diffText("enc:QUJD") == "enc:QUJD")
        #expect(XamlPlainText.diffText("  <b>x</b>\r\n\ty  ") == "x y")
    }
}
