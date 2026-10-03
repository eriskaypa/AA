// Tests: 12 §7.3 (TV-ID-1…4) and the §3.4 helper rules.
import Foundation
import Testing
@testable import AACore

@Suite struct SireTaskIdentifierTests {
    // TV: 12 TV-ID-1
    @Test func allThreeModes() {
        let sia = "• review the planned maintenance records for the fire pump.\n• Note: inspectors must record this\n• 5.1.2 cross reference to other question\n• short\n• 1) check the emergency generator start log."
        let ee = "• The company procedure for bunkering.\n• Records of fire drills\n• oil record book entries, etc."
        let neg = "• There was no procedure for enclosed space entry.\n• There were no records of drills.\n• No gas detector was available.\n• The Master was not familiar with the SMS.\n• Records had not been kept up to date.\n• The crew had not completed training.\n• The OOW did not know the procedure.\n• SMS procedures were not followed.\n• Fire hoses were damaged."
        let q = SireQuestion(questionNumber: "5.1.1", type: "inspection_question", objective: "Obj",
                             suggestedInspectorActions: sia, expectedEvidence: ee, potentialNegativeObservationGrounds: neg)
        #expect(SireTaskIdentifier.identifyTasks(for: q) == [
            "Review the planned maintenance records for the fire pump",
            "Check the emergency generator start log",
            "The company procedure for bunkering",
            "Records of fire drills",
            "Verify availability of: oil record book entries, etc.",
            "Verify that there is a procedure for enclosed space entry",
            "Verify that there are records of drills",
            "Verify that no gas detector was available — confirm this is not the case",
            "Verify that the Master is familiar with the SMS",
            "Verify that records has been kept up to date",
            "Verify that the crew has completed training",
            "Verify that the OOW does know the procedure",
            "Verify that sMS procedures are followed",
            "Verify that fire hoses were damaged",
        ])
    }

    // TV: 12 TV-ID-2
    @Test func noBulletFallback() {
        #expect(SireTaskIdentifier.identifyTasks(suggestedInspectorActions: "Review the crew list against the manning certificate\nVerify rest hours",
                                                 expectedEvidence: "", negativeGrounds: "") == [
            "Review the crew list against the manning certificate Verify rest hours",
            "Review the crew list against the manning certificate",
            "Verify rest hours",
        ])
    }

    // TV: 12 TV-ID-3
    @Test func dedupSubItemAndPrefixes() {
        let sia = "o Oily water separator overboard valve sealed\n• - a. Verify the OWS alarm setting.\n• Verify the OWS alarm setting\n• VERIFY THE OWS ALARM SETTING!"
        #expect(SireTaskIdentifier.identifyTasks(suggestedInspectorActions: sia, expectedEvidence: "• Verify the OWS alarm setting",
                                                 negativeGrounds: "") == ["Verify the OWS alarm setting"])
    }

    // TV: 12 TV-ID-4
    @Test func onlyDetailedQuestions() {
        let field = SireQuestion(questionNumber: "1.1.1", type: "data_field", objective: "x",
                                 suggestedInspectorActions: "• Check the vessel name on the certificate")
        let noObjective = SireQuestion(questionNumber: "11.1.2", type: "inspection_question",
                                       suggestedInspectorActions: "• Check the vessel name on the certificate")
        let detailed = SireQuestion(questionNumber: "2.1.1", type: "inspection_question", objective: "x",
                                    suggestedInspectorActions: "• Check the vessel name on the certificate")
        let id = SireTaskIdentifier.identifyAllTasks([field, noObjective, detailed])
        #expect(id.keys == ["2.1.1"])
        #expect(id.tasks(for: "2.1.1") == ["Check the vessel name on the certificate"])
    }

    @Test func helperRules() {
        func u(_ s: String) -> [UInt16] { Array(s.utf16) }
        func s(_ u: [UInt16]) -> String { String(decoding: u, as: UTF16.self) }
        #expect(s(SireTaskIdentifier.cleanFragment(u("1. a. Check the hoses."))) == "Check the hoses")
        #expect(s(SireTaskIdentifier.cleanFragment(u("e.g."))) == "e.g.")
        #expect(s(SireTaskIdentifier.cleanFragment(u("i.e."))) == "i.e.")
        #expect(s(SireTaskIdentifier.collapseWhitespace(u("a \n\t b\u{00A0}\u{00A0}c "))) == "a b\u{00A0}\u{00A0}c")
        #expect(SireTaskIdentifier.isSkippableLine(u("note: something long")))
        #expect(SireTaskIdentifier.isSkippableLine(u("5.12 reference")))
        #expect(!SireTaskIdentifier.isSkippableLine(u("5a reference text")))
        #expect(SireTaskIdentifier.isSubItem(u("o Valve sealed")) && !SireTaskIdentifier.isSubItem(u("o valve sealed")))
        #expect(s(SireTaskIdentifier.formatEvidenceTask(u("Testing records"))) == "Testing records")
        #expect(s(SireTaskIdentifier.formatEvidenceTask(u("logbook entries"))) == "Verify availability of: logbook entries")
        #expect(s(SireTaskIdentifier.normalizeForDedup(u("  Check, the LOG!  "))) == "check the log")
        #expect(s(SireTaskIdentifier.ensureCapitalized(u("ßharp"))) == "ßharp")      // multi-scalar upper mapping → unchanged
    }
}
