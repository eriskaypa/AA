// Tests: 12 §7.1 (TV-BANK-1…5), §7.3 TV-ID-BANK, §7.4 TV-TAG-BANK, Addendum A.6 (TV-KW-4, TV-TAGX-1/2, TV-DOM-*,
//        TV-TAGX-BANK-2, TV-TAGX-FP), A.4.1 metadata, SIRE-001/002 (lazy load, cached failure). Aggregates and
//        AA's own keyword strings only — no bank text is copied into tests (§7).
import CryptoKit
import Foundation
import Testing
@testable import AACore

/// The real bank, decoded once for every suite.
enum SireTestBank {
    static let data: Data = AAResources.data(name: "sire2_question_bank", ext: "json") ?? Data()
    static let contents: SireBankContents = (try? SireBankDecoder.load(data)) ?? SireBankContents()
    static func q(_ n: String) -> SireQuestion { contents.question(n)! }
}

@Suite struct SireBankTests {
    let bank = SireTestBank.contents

    // TV: 12 TV-BANK-1
    @Test func bundledResourceIsByteIdentical() {
        let d = SireTestBank.data
        #expect(d.count == 3_350_301)
        #expect(SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
                == "e05d3c59572625b639005c498f5090c88a6ea67cdff9b45581df3f8658eb8bcf")
    }

    // TV: 12 TV-BANK-2, A.4.1
    @Test func questionsChaptersSections() {
        #expect(bank.questions.count == 410)
        let counts = bank.byChapter().map { "\($0.chapter):\($0.questions.count)" }
        #expect(counts == ["1:25", "2:19", "3:22", "4:37", "5:88", "6:16", "7:6", "8:91", "9:14", "10:32", "11:54", "12:6"])
        #expect(Set(bank.questions.map(\.section)).count == 72)
        let numbers = bank.questions.map(\.questionNumber)
        #expect(Set(numbers).count == 410)
        #expect(SireOrder.sortedByNumber(bank.questions).map(\.questionNumber) == numbers)
        #expect(bank.questions.allSatisfy { $0.questionNumber.hasPrefix($0.section + ".") })
        #expect(bank.metadata.totalQuestions == 410)
        #expect(bank.metadata.title == "SIRE 2.0 Question Library" && bank.metadata.version == "1.0")
        #expect(bank.metadata.date == "January 2022")
        #expect(bank.metadata.source == "OCIMF - Oil Companies International Marine Forum")
    }

    // TV: 12 TV-BANK-3
    @Test func typeDistribution() {
        var types: [String: Int] = [:]
        for q in bank.questions { types[q.questionTypeDisplay, default: 0] += 1 }
        #expect(types == ["Data Field": 25, "Inspection": 331, "Photograph": 54])
        #expect(bank.questions.filter { $0.vesselTypes.isEmpty }.count == 25)
        #expect(bank.questions.filter(\.isDetailedQuestion).count == 332)
        #expect(SireTestBank.q("11.1.1").isDetailedQuestion)
        #expect(SireTestBank.q("1.1.1").shortQuestionText.isEmpty)
    }

    // TV: 12 TV-BANK-4
    @Test func filterLists() {
        let b = SireBrowser(bank)
        #expect(b.chapterOptions.count == 12)
        #expect(b.chapterOptions.first?.label == "Ch 1: Vessel, Operator and Inspection Particulars (25)")
        #expect(b.chapterOptions.last?.label == "Ch 12: Ice Operations (6)")
        #expect(b.chapterOptions[4].label == "Ch 5: Safety Management (88)")
        #expect(b.vesselOptions.map(\.label) == ["Chemical", "LNG", "LPG", "Oil"])
        #expect(b.typeOptions.map(\.label) == ["Data Field", "Inspection", "Photograph"])
    }

    // TV: 12 TV-BANK-5
    @Test func roviqLocationCount() {
        var seen = Set<String>()
        for q in bank.questions { for l in q.roviqLocations { seen.insert(NetText.toUpperInvariant(l)) } }
        #expect(seen.count == 39)
    }

    // TV: 12 TV-ID-BANK
    @Test func identifiedTasksOverTheBank() {
        let id = bank.identified
        #expect(id.count == 332)
        #expect(id.totalTasks == 6106)
        #expect(id.pairs.map(\.tasks.count).min() == 6)
        #expect(id.pairs.map(\.tasks.count).max() == 39)
        #expect(Array(id.keys.prefix(3)) == ["2.1.1", "2.2.1", "2.2.2"])
        var perChapter: [String: Int] = [:]
        for p in id.pairs { perChapter[SireTestBank.q(p.key).chapter, default: 0] += p.tasks.count }
        #expect(perChapter == ["2": 325, "3": 348, "4": 641, "5": 1718, "6": 330, "7": 116, "8": 1705, "9": 248,
                               "10": 585, "11": 6, "12": 84])
        #expect(id.tasks(for: "1.1.1").isEmpty)
        // Keys are in bank order.
        let order = bank.questions.map(\.questionNumber).filter { id[$0] != nil }
        #expect(order == id.keys)
    }

    // TV: 12 TV-TAG-BANK, TV-TAGX-BANK-2
    @Test func tagAggregates() {
        var dom: [String: Int] = [:]
        for q in bank.questions { dom[SireTagExtractor.dominantCategory(q), default: 0] += 1 }
        #expect(dom == ["Procedure": 187, "Equipment": 144, "Task": 79])
        #expect(bank.questions.filter { $0.evidenceTags.isEmpty }.count == 54)
        #expect(SireTestBank.q("1.1.1").evidenceTags.isEmpty)
        let all = bank.questions.flatMap(\.evidenceTags)
        #expect(all.count == 1568)
        var byCat: [String: Int] = [:]
        for t in all { byCat[String(t.split(separator: ":")[0]), default: 0] += 1 }
        #expect(byCat == ["Equipment": 302, "Document": 247, "Procedure": 529, "Record": 210, "Personnel": 280])
        func n(_ tag: String) -> Int { bank.questions.filter { $0.evidenceTags.contains(tag) }.count }
        #expect(n("Procedure: procedure") == 272 && n("Personnel: rating") == 113 && n("Record: log book") == 74)
        #expect(n("Document: DOC") == 61 && n("Procedure: checklist") == 58 && n("Personnel: SSO") == 56)
        #expect(n("Document: certificate") == 47 && n("Record: bridge log") == 45 && n("Personnel: Master") == 43)
        #expect(n("Equipment: cargo tank") == 39)
        // TV-TAGX-FP: false-positive tags present (counts of questions carrying them).
        #expect(n("Equipment: AIS") == 10 && n("Equipment: UPS") == 2 && n("Procedure: COW") == 4)
        #expect(n("Procedure: NCR") == 5 && n("Document: COF") == 5 && n("Equipment: OWS") == 2 && n("Equipment: anchor") == 12)
        // 66 questions differ between culture and ordinal order (SIRE-051).
        let differing = bank.questions.filter {
            $0.evidenceTags != $0.evidenceTags.sorted { Ordinal.compare($0, $1) == .orderedAscending }
        }
        #expect(differing.count == 66)
    }

    // TV: 12 TV-KW-4
    @Test func keywordCoverage() {
        let present = Set(bank.questions.flatMap(\.evidenceTags))
        #expect(present.count == 182)
        let never = ["Equipment: life jacket", "Equipment: life raft", "Equipment: oxygen analyzer", "Equipment: derrick",
                     "Equipment: magnetic compass", "Equipment: autopilot", "Equipment: oily water separator",
                     "Equipment: sewage treatment", "Equipment: PV valve", "Equipment: pressure vacuum",
                     "Equipment: loading arm", "Equipment: water spray", "Equipment: fire flap",
                     "Equipment: quick-closing valve", "Equipment: high level alarm", "Equipment: overflow",
                     "Equipment: vent riser",
                     "Document: ISPP", "Document: SMC", "Document: ISPS", "Document: permit to work", "Document: JSA",
                     "Document: job safety analysis", "Document: loading manual", "Document: trim and stability",
                     "Document: ISPS plan", "Document: external audit", "Document: MSDS", "Document: material safety",
                     "Document: IHM", "Document: inventory of hazardous materials", "Document: PWOM",
                     "Procedure: VRP", "Procedure: shipboard oil pollution", "Procedure: working aloft",
                     "Procedure: working overside", "Procedure: lockout tagout", "Procedure: LOTO",
                     "Procedure: isolation procedure", "Procedure: fatigue management", "Procedure: bridge procedure",
                     "Record: work rest", "Record: gas reading", "Record: atmosphere test", "Record: IG pressure",
                     "Record: induction record", "Record: near miss", "Record: incident report", "Record: accident report",
                     "Record: superintendent report", "Record: navigational audit",
                     "Personnel: officer of the watch", "Personnel: duty officer", "Personnel: designated person",
                     "Personnel: pre-job briefing"]
        #expect(never.count == 55)
        #expect(never.allSatisfy { !present.contains($0) })
    }

    // TV: 12 TV-TAGX-1, TV-TAGX-2, TV-DOM-E/P/T, TV-DOM-X
    @Test func realQuestionVectors() {
        #expect(SireTestBank.q("2.1.1").evidenceTags == [
            "Document: certificate", "Document: class survey", "Document: classification", "Document: CSSR",
            "Document: DOC", "Document: HVPQ", "Document: survey status", "Procedure: defect reporting",
            "Procedure: procedure"])
        #expect(SireTagExtractor.dominantCategory(SireTestBank.q("2.1.1")) == "Procedure")
        let smart = SireFlow.buildQuestion(SireTestBank.q("2.1.1")).blocks.last
        #expect(smart == SireFlow.line("Smart tags: Document: certificate   ·   Document: class survey   ·   Document: classification   ·   Document: CSSR   ·   Document: DOC   ·   Document: HVPQ   ·   Document: survey status   ·   Procedure: defect reporting   ·   Procedure: procedure", 10, SireFlow.muted))
        #expect(SireTestBank.q("12.1.1").evidenceTags == [
            "Document: certificate", "Document: polar water operational manual", "Personnel: Chief Mate",
            "Personnel: competency", "Personnel: Master", "Personnel: rating"])
        #expect(SireTagExtractor.dominantCategory(SireTestBank.q("12.1.1")) == "Task")
        #expect(SireTestBank.q("10.5.2").evidenceTags == ["Document: oil record book", "Equipment: AIS", "Personnel: rating",
                                                          "Procedure: procedure"])
        #expect(SireTagExtractor.dominantCategory(SireTestBank.q("10.5.2")) == "Equipment")
        #expect(SireTestBank.q("2.3.1").evidenceTags == ["Document: classification", "Document: DOC", "Procedure: defect reporting"])
        #expect(SireTagExtractor.dominantCategory(SireTestBank.q("2.3.1")) == "Procedure")
        let rows: [(String, [String], String)] = [
            ("9.3.1", ["Equipment: AIS", "Equipment: anchor", "Equipment: windlass", "Procedure: anchoring procedure",
                       "Procedure: checklist", "Procedure: procedure", "Record: bridge log", "Record: log book",
                       "Record: maintenance record"], "Equipment"),
            ("7.1.1", ["Document: passage plan", "Document: risk assessment", "Document: voyage plan", "Equipment: AIS",
                       "Procedure: checklist", "Record: bridge log", "Record: log book"], "Equipment"),
            ("3.5.1", ["Equipment: OWS", "Personnel: deck officer", "Personnel: engineer officer", "Personnel: familiarisation",
                       "Personnel: rating", "Procedure: procedure", "Record: familiarisation record"], "Equipment"),
            ("5.6.2", ["Equipment: ballast tank", "Equipment: cargo tank", "Equipment: UPS", "Procedure: procedure",
                       "Record: calibration record"], "Equipment"),
            ("5.2.8", ["Equipment: fire damper", "Equipment: fire door", "Equipment: ventilation", "Procedure: COW",
                       "Procedure: emergency plan"], "Equipment"),
            ("4.2.3", ["Equipment: AIS", "Equipment: ECDIS", "Personnel: Master", "Personnel: OOW", "Procedure: daily orders",
                       "Procedure: NCR", "Procedure: procedure", "Procedure: standing orders"], "Procedure"),
            ("1.1.1", [], "Task"), ("11.1.2", [], "Task"),
        ]
        for (n, tags, dom) in rows {
            #expect(SireTestBank.q(n).evidenceTags == tags, "\(n)")
            #expect(SireTagExtractor.dominantCategory(SireTestBank.q(n)) == dom, "\(n)")
        }
    }

    // TV: 12 TV-TAGX-BANK-2 (Evidence category filter counts)
    @Test func evidenceFilterCounts() {
        let b = SireBrowser(bank)
        let s = SireSessionSnapshot()
        var counts: [String: Int] = [:]
        for e in SireEvidenceFilter.items { counts[e] = b.apply(SireFilterCriteria(evidence: e), session: s).count }
        #expect(counts == ["All": 410, "Equipment": 198, "Document": 148, "Procedure": 299, "Record": 133, "Personnel": 199])
    }

    // TV: 12 §7.12 step 1 (stats footer with the shipped bank and an empty session)
    @Test func statsFooter() {
        #expect(SireBrowser(bank).statsText(session: SireSessionSnapshot())
                == "410 questions · 6106 auto-identified tasks\nSession — ✓ 0  ⧗ 0  N/A 0  ★ 0  tasks 0")
    }
}

@MainActor @Suite struct SireBankLoaderTests {
    // SIRE-001: one load per process; concurrent callers share it.
    @Test func loadsOnceAndCaches() async {
        let bank = SireBank(source: { SireTestBank.data })
        #expect(bank.phase == .notLoaded)
        async let a = bank.load()
        async let b = bank.load()
        let (ra, rb) = await (a, b)
        #expect((try? ra.get().questions.count) == 410)
        #expect((try? rb.get().questions.count) == 410)
        #expect(bank.phase == .loaded && bank.isLoaded && bank.loadError == nil)
    }

    // SIRE-002: the failure texts, cached until restart.
    @Test func failuresAreCached() async {
        let missing = SireBank(source: { nil })
        _ = await missing.load()
        #expect(missing.loadError == "Embedded SIRE question bank not found.")
        #expect(missing.contents?.questions.isEmpty == true)
        let again = await missing.load()
        #expect((try? again.get()) == nil)
        #expect(missing.loadError == "Embedded SIRE question bank not found.")

        let empty = SireBank(source: { Data(#"{"metadata":{},"questions":[]}"#.utf8) })
        _ = await empty.load()
        #expect(empty.loadError == "SIRE question bank is empty.")

        let bad = SireBank(source: { Data("{not json".utf8) })
        _ = await bad.load()
        #expect(bad.loadError?.isEmpty == false)
    }

    // §4.1: null strings → "", absent keys default, unknown keys ignored; wrong types fail the load.
    @Test func tolerantDecoding() throws {
        let json = #"{"metadata":null,"questions":[{"question_number":"1.1.1","chapter":"1","short_question_text":null,"vessel_types":null,"extra":42},{"question_number":"2.1.1","vessel_types":["Oil",null]}],"parts":[]}"#
        let d = try SireBankDecoder.decode(Data(json.utf8))
        #expect(d.questions.count == 2)
        #expect(d.questions[0].shortQuestionText == "" && d.questions[0].vesselTypes == [] && d.questions[0].section == "")
        #expect(d.questions[1].vesselTypes == ["Oil", ""])
        #expect(d.metadata == SireBankMetadata())
        #expect(throws: SireBankError.self) { _ = try SireBankDecoder.decode(Data(#"{"questions":[{"chapter":5}]}"#.utf8)) }
    }
}
