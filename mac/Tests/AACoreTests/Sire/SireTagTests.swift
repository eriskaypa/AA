// Tests: 12 §7.2 (QuestionNumberComparer), §7.4 (TagExtractor / DominantCategory), §7.5 (ROVIQ), Addendum A.6
//        (TV-KW-1…3, TV-TAGX-SYN) and the SIRE-049 verbatim diff against TagExtractor.cs when the repo is present.
import CryptoKit
import Foundation
import Testing
@testable import AACore

private func sireQ(short: String = "", objective: String = "", ee: String = "", sia: String = "") -> SireQuestion {
    SireQuestion(questionNumber: "9.9.9", type: "inspection_question", shortQuestionText: short, objective: objective,
                 suggestedInspectorActions: sia, expectedEvidence: ee)
}

private func sha(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }

@Suite struct SireOrderTests {
    // TV: 12 §7.2
    @Test func naturalSort() {
        let s = SireOrder.stableSorted(["1.1.10", "2.1.1", "1.1.2", "10.1.1", "1.1.1"]) { SireOrder.compareNumbers($0, $1) }
        #expect(s == ["1.1.1", "1.1.2", "1.1.10", "2.1.1", "10.1.1"])
    }

    @Test func comparerEdgeCases() {
        #expect(SireOrder.compareNumbers("1.1", "1.1.0") == .orderedSame)
        #expect(SireOrder.compareNumbers("x.1", "0.1") == .orderedSame)
        #expect(SireOrder.compareNumbers("11.1.95", "11.1.100") == .orderedAscending)
        #expect(SireOrder.compareNumbers(nil, "1") == .orderedAscending)
        #expect(SireOrder.compareNumbers("1", nil) == .orderedDescending)
        #expect(SireOrder.compareNumbers(nil, nil) == .orderedSame)
        #expect(SireOrder.compareNumbers("2.1.2", "2.1.10") == .orderedAscending)
    }

    @Test func netInt32Rules() {
        #expect(SireOrder.netInt32(" 12 ") == 12)
        #expect(SireOrder.netInt32("+7") == 7 && SireOrder.netInt32("-3") == -3)
        #expect(SireOrder.netInt32("2147483647") == 2_147_483_647)
        #expect(SireOrder.netInt32("2147483648") == nil)
        #expect(SireOrder.netInt32("-2147483648") == -2_147_483_648)
        #expect(SireOrder.netInt32("1a") == nil && SireOrder.netInt32("") == nil && SireOrder.netInt32("+") == nil)
        #expect(SireOrder.netInt32("١") == nil)                     // Arabic-Indic digit: not an ASCII digit
        #expect(SireOrder.chapterRank("x") == 999 && SireOrder.chapterRank("12") == 12)
    }
}

@Suite struct SireKeywordTests {
    // TV: 12 TV-KW-1
    @Test func counts() {
        #expect(SireTagKeywords.equipment.count == 87)
        #expect(SireTagKeywords.document.count == 52)
        #expect(SireTagKeywords.procedure.count == 47)
        #expect(SireTagKeywords.record.count == 27)
        #expect(SireTagKeywords.personnel.count == 24)
        #expect(SireTagKeywords.scanOrder.map(\.keywords.count).reduce(0, +) == 237)
        #expect(SireTagKeywords.scanOrder.map(\.category) == ["Equipment", "Document", "Procedure", "Record", "Personnel"])
    }

    // TV: 12 TV-KW-2 (fingerprints of A.2.6 and spot checks)
    @Test func fingerprints() {
        #expect(sha(SireTagKeywords.equipment.joined(separator: "\n")) == "71fc38c576a7d8e4c816f6ab3516aef9c9bf922a37818b58268d1a4ad2a3950d")
        #expect(sha(SireTagKeywords.document.joined(separator: "\n")) == "7d7358cc49ce401598bb0676ae2c32d89c4f7fd9b8f67022c944f6c8654a8152")
        #expect(sha(SireTagKeywords.procedure.joined(separator: "\n")) == "3b2c452614b74da4fedf63870f0ca48e8f40e34789c72c10b7f5c47806a2b673")
        #expect(sha(SireTagKeywords.record.joined(separator: "\n")) == "93e255324590bd54ee18b711d25176a3450e0b371ebaf9591dd43f94ca267bd8")
        #expect(sha(SireTagKeywords.personnel.joined(separator: "\n")) == "2c8ab7131f23c3a8c887a66b65e81daa6caa3f7d1a4c5f959f8ee301367041a6")
        let all = SireTagKeywords.scanOrder.flatMap { c in c.keywords.map { "\(c.category): \($0)" } }
        #expect(sha(all.joined(separator: "\n")) == "e37775a1e34e0588e69bede4b3260628a7437fe439324cd96bf60ac2be7ef5e1")
        #expect(Data(SireTagKeywords.equipment.joined(separator: "\n").utf8).count == 1012)
        #expect(SireTagKeywords.equipment[14] == "oxygen analyser" && SireTagKeywords.equipment[15] == "oxygen analyzer")
        #expect(SireTagKeywords.equipment[3] == "lifejacket" && SireTagKeywords.equipment[4] == "life jacket")
        #expect(SireTagKeywords.document[5] == "DOC" && SireTagKeywords.document[16] == "Document of Compliance")
        #expect(SireTagKeywords.procedure[0] == "procedure" && SireTagKeywords.procedure[22] == "COW")
        #expect(SireTagKeywords.record[0] == "log book" && SireTagKeywords.record[1] == "logbook")
        #expect(SireTagKeywords.personnel[0] == "Master" && SireTagKeywords.personnel[9] == "rating")
    }

    // TV: 12 TV-KW-3
    @Test func uniquenessContainmentAndComparator() {
        let all = SireTagKeywords.scanOrder.flatMap { c in c.keywords.map { (c.category, $0) } }
        let folded = all.map { NetText.toUpperInvariant($0.1) }
        #expect(Set(folded).count == 237)
        var pairs = 0
        for (i, a) in folded.enumerated() {
            for (j, b) in folded.enumerated() where i != j && b.count > a.count && b.contains(a) { pairs += 1 }
        }
        #expect(pairs == 19)
        let tags = all.map { "\($0.0): \($0.1)" }
        var same = 0
        for i in tags.indices { for j in tags.indices where i < j && SireOrder.compareCulture(tags[i], tags[j]) == .orderedSame { same += 1 } }
        #expect(same == 0)
    }

    // SIRE-049: line-by-line diff against the Windows source when the full repository is checked out.
    @Test func verbatimAgainstCSharpSource() throws {
        let cs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "AA/Sire/TagExtractor.cs")
        guard let text = try? String(contentsOf: cs, encoding: .utf8) else { return }   // Mac-only checkout: fingerprints cover it
        let arrays = try NSRegularExpression(pattern: #"private static readonly string\[\] (\w+)Keywords =\s*\[(.*?)\];"#,
                                             options: [.dotMatchesLineSeparators])
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
        let ns = text as NSString
        var found: [String: [String]] = [:]
        for m in arrays.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2)) as NSString
            found[name] = literal.matches(in: body as String, range: NSRange(location: 0, length: body.length))
                .map { body.substring(with: $0.range(at: 1)) }
        }
        #expect(found["Equipment"] == SireTagKeywords.equipment)
        #expect(found["Document"] == SireTagKeywords.document)
        #expect(found["Procedure"] == SireTagKeywords.procedure)
        #expect(found["Record"] == SireTagKeywords.record)
        #expect(found["Personnel"] == SireTagKeywords.personnel)
    }
}

@Suite struct SireTagExtractorTests {
    // TV: 12 TV-TAG-1
    @Test func cultureOrderAndDominant() {
        let q = sireQ(short: "Fire pump and SCBA readiness", objective: "To ensure the fire pump is maintained per the PMS.",
                      ee: "• Maintenance records\n• Muster list", sia: "• Interview the Chief Engineer")
        let tags = SireTagExtractor.extractTags(q)
        #expect(tags == ["Equipment: fire pump", "Equipment: SCBA", "Personnel: Chief Engineer", "Procedure: muster list",
                         "Procedure: PMS", "Record: maintenance record"])
        #expect(SireTagExtractor.dominantCategory(tags: tags) == "Equipment")
    }

    // TV: 12 TV-TAG-2
    @Test func substringFalsePositives() {
        let tags = SireTagExtractor.extractTags(sireQ(short: "Operating groups raised the document"))
        #expect(tags == ["Document: DOC", "Equipment: AIS", "Equipment: UPS", "Personnel: rating"])
        #expect(SireTagExtractor.dominantCategory(tags: tags) == "Equipment")
    }

    // TV: 12 TV-TAG-3
    @Test func punctuationOrdering() {
        let tags = SireTagExtractor.extractTags(sireQ(short: "Crane and derrick; P/V valve, PV valve and pressure vacuum"))
        #expect(tags == ["Equipment: crane", "Equipment: derrick", "Equipment: P/V valve", "Equipment: pressure vacuum",
                         "Equipment: PV valve"])
    }

    // TV: 12 TV-TAG-4
    @Test func dominantRules() {
        #expect(SireTagExtractor.extractTags(sireQ()) == [])
        #expect(SireTagExtractor.dominantCategory(tags: []) == "Task")
        #expect(SireTagExtractor.dominantCategory(tags: ["Procedure: a", "Procedure: b"]) == "Procedure")
        #expect(SireTagExtractor.dominantCategory(tags: ["Equipment: a", "Equipment: b", "Procedure: a", "Procedure: b",
                                                          "Procedure: c"]) == "Procedure")
        #expect(SireTagExtractor.dominantCategory(tags: ["Document: a", "Document: b", "Document: c", "Record: a",
                                                          "Record: b"]) == "Task")
        #expect(SireTagExtractor.dominantCategory(tags: ["equipment: x"]) == "Task")
        #expect(SireTagExtractor.dominantCategory(tags: [":Equipment", "Equipment"]) == "Task")
    }

    // TV: 12 TV-TAGX-SYN 1–10
    @Test func syntheticVectors() {
        func check(_ q: SireQuestion, _ expected: [String], _ dom: String, sourceLocation: SourceLocation = #_sourceLocation) {
            let t = SireTagExtractor.extractTags(q)
            #expect(t == expected, sourceLocation: sourceLocation)
            #expect(SireTagExtractor.dominantCategory(tags: t) == dom, sourceLocation: sourceLocation)
        }
        check(sireQ(ee: "fire\npump"), [], "Task")
        check(sireQ(ee: "fire  pump"), [], "Task")
        check(sireQ(ee: "Check the fire", sia: "pump room"), ["Equipment: fire pump"], "Equipment")
        check(sireQ(short: "\u{FB01}re pump"), [], "Task")
        check(sireQ(short: "FIRE PUMP"), ["Equipment: fire pump"], "Equipment")
        check(sireQ(short: "Harbour MASTER"), ["Personnel: Master"], "Task")
        check(sireQ(short: "anchoring procedure"), ["Equipment: anchor", "Procedure: anchoring procedure", "Procedure: procedure"],
              "Procedure")
        check(sireQ(short: "hot work permit"), ["Document: hot work permit", "Document: work permit", "Procedure: hot work"],
              "Procedure")
        check(sireQ(short: "Windlass checklist"), ["Equipment: windlass", "Procedure: checklist"], "Equipment")
        check(sireQ(short: "Documented"), ["Document: DOC"], "Task")
    }

    @Test func noFoundationFolding() {
        #expect(!SireTagExtractor.containsOrdinalIgnoreCaseASCII("\u{212A}ey".utf16.map(SireTagExtractor.asciiFold),
                                                                  "key".utf16.map(SireTagExtractor.asciiFold)))
        #expect(SireTagExtractor.extractTags(searchText: "STRA\u{00DF}E") == [])
    }

    // TV: 12 §7.5
    @Test func roviqLocations() {
        #expect(SireTagExtractor.extractRoviqLocations("Documentation, Pre-board") == ["Documentation", "Pre-board"])
        #expect(SireTagExtractor.extractRoviqLocations("Main Deck, Pre-board, Documentation") == ["Documentation", "Main Deck", "Pre-board"])
        #expect(SireTagExtractor.extractRoviqLocations("Bridge., bridge") == ["Bridge"])
        #expect(SireTagExtractor.extractRoviqLocations("Bridge .") == ["Bridge "])
        #expect(SireTagExtractor.extractRoviqLocations(" , ,") == [])
        #expect(SireTagExtractor.extractRoviqLocations("") == [])
        #expect(SireTagExtractor.extractRoviqLocations("Interview -\nRating") == ["Interview -\nRating"])
        #expect(SireTagExtractor.extractRoviqLocations("...") == [])
    }
}
