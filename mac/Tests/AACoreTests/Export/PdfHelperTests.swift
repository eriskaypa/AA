// TV: 11 §7.3 (strike), §7.4 (Shorten), §7.5 (TaskWhen / task details), §7.10 (font resolution), §7.15 (file
//     names), 04 §7.9 (safe names), PDF-101 / DEV-13 (AddText splitting), PDF-023 (prompts), PDF-025 (messages).
import Foundation
import Testing
@testable import AACore

@Suite("W-PDF helpers")
struct PdfHelperTests {
    // TV: 11 §7.3 — Windows ApplyStrike reference and the Mac predicate
    @Test func strikeReferenceAndPredicate() {
        #expect(PdfStrike.windowsApplyStrike("ab c") == "a\u{0336}b\u{0336} c\u{0336}")
        #expect(PdfStrike.windowsApplyStrike("😀x") == "😀\u{0336}x\u{0336}")
        #expect(PdfStrike.windowsApplyStrike("\t") == "\t")
        #expect(PdfStrike.windowsApplyStrike("") == "")
        #expect(PdfStrike.windowsApplyStrike("a\u{00A0}b") == "a\u{0336}\u{00A0}b\u{0336}")
        func struck(_ s: String) -> [Character] { s.filter(PdfStrike.strikes) }
        #expect(struck("ab c") == ["a", "b", "c"])
        #expect(struck("😀x") == ["😀", "x"])
        #expect(struck("\t").isEmpty)
        #expect(struck("a\u{00A0}b") == ["a", "b"])
    }

    // TV: 11 §7.4
    @Test func shorten() {
        #expect(PdfItemBuilder.shorten("abc", 180) == "abc")
        let long = PdfItemBuilder.shorten(String(repeating: "x", count: 200), 180)
        #expect(long == String(repeating: "x", count: 179) + "\u{2026}")
        #expect(long.utf16.count == 180)
        #expect(PdfItemBuilder.shorten("a\r\nb", 180) == "a  b")
        #expect(PdfItemBuilder.shorten("  x  ", 180) == "x")
        #expect(PdfItemBuilder.shorten(String(repeating: "x", count: 180), 180) == String(repeating: "x", count: 180))
        // Mac: never split a surrogate pair (back off to the previous boundary).
        let emoji = String(repeating: "a", count: 178) + "😀😀"
        #expect(PdfItemBuilder.shorten(emoji, 180) == String(repeating: "a", count: 178) + "\u{2026}")
    }

    // TV: 11 §7.5
    @Test func taskWhen() {
        let d10 = CivilDate(year: 2026, month: 7, day: 10)!, d8 = CivilDate(year: 2026, month: 7, day: 8)!
        let d12 = CivilDate(year: 2026, month: 7, day: 12)!
        #expect(PdfItemBuilder.taskWhen(deadline: nil, rangeStart: nil) == nil)
        #expect(PdfItemBuilder.taskWhen(deadline: d10, rangeStart: nil) == "due 2026-07-10")
        #expect(PdfItemBuilder.taskWhen(deadline: d10, rangeStart: d8) == "2026-07-08 \u{2013} 2026-07-10")
        #expect(PdfItemBuilder.taskWhen(deadline: d10, rangeStart: d10) == "due 2026-07-10")
        #expect(PdfItemBuilder.taskWhen(deadline: d10, rangeStart: d12) == "due 2026-07-10")
        #expect(PdfItemBuilder.taskWhen(deadline: nil, rangeStart: d8) == nil)
        let t = PdfTaskSnapshot(name: "Replace filter", deadline: CivilDate(year: 2026, month: 7, day: 10), recurrence: .monthly)
        #expect(PdfItemBuilder.meta(t) == ["due 2026-07-10", "monthly"])
    }

    // TV: 11 §7.5 — task details rows (range same day / out of order / none)
    @Test func taskDetailsRows() {
        func rows(_ start: CivilDate?, _ end: CivilDate?, done: Bool = false) -> [[String]] {
            let blocks = PdfItemBuilder.taskSpecifics(PdfTaskSnapshot(name: "T", deadline: end, rangeStart: start,
                                                                      recurrence: .yearly, isComplete: done))
            return blocks.compactMap(\.table).first!.rows.map { $0.cells.map { $0.blocks.first!.paragraph!.plainText } }
        }
        let d10 = CivilDate(year: 2026, month: 7, day: 10)!, d8 = CivilDate(year: 2026, month: 7, day: 8)!
        #expect(rows(nil, nil) == [["Deadline", "(none)"], ["Recurrence", "Yearly"], ["Status", "Open"]])
        #expect(rows(d8, d10).first == ["Working range", "2026-07-08 \u{2192} 2026-07-10"])
        #expect(rows(d10, d10).first == ["Deadline", "2026-07-10"])
        #expect(rows(nil, d10, done: true).last == ["Status", "Completed"])
    }

    // TV: 11 §7.15, 04 §7.9
    @Test func fileNames() {
        #expect(PdfExport.itemFileName(kind: .task, name: "Check: A/B") == "Task-Check_ A_B.pdf")
        #expect(PdfExport.itemFileName(kind: .equipment, name: "") == "Equipment-.pdf")
        #expect(PdfExport.itemFileName(kind: .task, name: "Pump: A/B?") == "Task-Pump_ A_B_.pdf")
        #expect(PdfExport.itemFileName(kind: .vessel, name: "") == "Vessel-.pdf")
        #expect(PdfExport.safe("a\tb") == "a_b")
        #expect(PdfExport.checklistFileName(procedureName: "Pre-arrival <v2>", excel: false) == "checklist-Pre-arrival _v2_.pdf")
        #expect(PdfExport.checklistFileName(procedureName: "Pre-arrival <v2>", excel: true) == "checklist-Pre-arrival _v2_.xlsx")
        #expect(PdfExport.checklistFileName(procedureName: "Fire drill", excel: true) == "checklist-Fire drill.xlsx")
        #expect(PdfExport.savedListsFileName(title: "   ") == "saved-lists.pdf")
        #expect(PdfExport.savedListsFileName(title: " Deck ") == "Deck.pdf")
        #expect(PdfExport.savedListsFileName(title: "a*b") == "a_b.pdf")
        #expect(PdfExport.savedListsFileName(title: "All saved lists") == "All saved lists.pdf")
        #expect(PdfExport.savedListsFileName(title: "") == "saved-lists.pdf")
    }

    // TV: 11 PDF-023, PDF-025, PDF-002, PDF-005/012
    @Test func strings() {
        #expect(PdfExport.listStylePrompt(entryCount: 1) == "How should the items in this list be shown in the PDF?")
        #expect(PdfExport.listStylePrompt(entryCount: 4) == "How should the items in these 4 lists be shown in the PDF?")
        #expect(PdfExport.completeMessage(path: "/x/y.pdf") == "Exported to:\n/x/y.pdf\n\nOpen it now?")
        #expect(PdfExport.failedMessage("disk full") == "Could not export the PDF:\n\ndisk full")
        #expect(PdfExport.lockedMessage == "Unlock this entry before exporting it to PDF.")
        #expect(PdfExport.itemFailurePrefix + "x" == "Failed to export PDF:\nx")
        #expect(PdfExport.checklistFailurePrefix + "x" == "Failed to export checklist:\nx")
        #expect(PdfExport.bulletedTitle == "\u{2022} Bulleted")
    }

    // TV: 11 §7.10 — stock macOS (no Office fonts) and a Mac with Office fonts installed
    @Test func fontResolutionStockMac() {
        let r = PdfFontResolver(installedFamilies: ["Helvetica Neue", "Helvetica", "Menlo", "Monaco", "Courier New",
                                                    "Arial", "Times New Roman", "Georgia", "Verdana", "Charter"])
        #expect(r.resolve("Consolas") == "Menlo")
        #expect(r.resolve("Calibri") == "Helvetica Neue")
        #expect(r.resolve("Segoe UI") == PdfFontResolver.systemUIFamily)
        #expect(r.resolve("Monospace") == "Menlo")
        #expect(r.resolve("Arial") == "Arial")
        #expect(r.resolve("Times New Roman, serif") == "Times New Roman")
        #expect(r.resolve("Global User Interface") == "Helvetica Neue")
        #expect(r.resolve(nil) == "Helvetica Neue")
        #expect(r.resolve("") == "Helvetica Neue")
        #expect(r.resolve("NoSuchFont, Georgia") == "Georgia")
        #expect(r.resolve("'Times New Roman'") == "Times New Roman")
        #expect(r.resolve("Sans Serif") == "Arial")
        #expect(r.resolve("Cambria") == "Charter")
        #expect(r.resolve("Tahoma") == "Verdana")
        #expect(r.resolveFont("Consolas").scale < 1)
        #expect(r.resolveFont("Arial").scale == 1)
        #expect(r.normalFont == "Helvetica Neue")
    }

    @Test func fontResolutionWithOfficeFonts() {
        let r = PdfFontResolver(installedFamilies: ["Calibri", "Consolas", "Arial", "Carlito"])
        #expect(r.resolve("Consolas") == "Consolas")
        #expect(r.resolve("Calibri, Arial") == "Calibri")
        #expect(r.resolve("Global User Interface") == "Calibri")
        #expect(r.resolveFont("Calibri").scale == 1)
        let carlito = PdfFontResolver(installedFamilies: ["Carlito", "Helvetica Neue"])
        #expect(carlito.resolve("Calibri") == "Carlito")
    }

    @Test func systemResolverAlwaysAnswers() {
        #expect(!PdfFontResolver.system.resolve("Consolas").isEmpty)
        #expect(!PdfFontResolver.system.normalFont.isEmpty)
    }

    // TV: 11 PDF-101, DEV-13
    @Test func addTextSplitting() {
        #expect(PdfText.inlines("a\nb\tc") == [.text("a", .plain), .lineBreak, .text("b", .plain), .tab, .text("c", .plain)])
        #expect(PdfText.inlines("a\r\nb\rc") == [.text("a", .plain), .lineBreak, .text("b", .plain), .lineBreak, .text("c", .plain)])
        #expect(PdfText.inlines("\n\n") == [.lineBreak, .lineBreak])
        #expect(PdfText.inlines("") == [])
    }

    // TV: 11 §3.1 units
    @Test func units() {
        #expect(abs(PdfUnits.a4Width - 595.276) < 0.01)
        #expect(abs(PdfUnits.a4Height - 841.890) < 0.01)
        #expect(abs(PdfUnits.cm(px: 24) - 0.635) < 1e-9)
        #expect(PdfItemBuilder.subtaskIndent(depth: 1) == 0.6)
        #expect(abs(PdfItemBuilder.subtaskIndent(depth: 3) - 1.8) < 1e-9)
        #expect(abs(PdfItemBuilder.subtaskIndent(depth: 7) - 2.4) < 1e-9)
        // Windows formats the indent "{x:0.##}cm": the stored value is the rounded one.
        #expect(PdfItemBuilder.subtaskIndent(depth: 2) == 1.2 && PdfItemBuilder.subtaskIndent(depth: 3) == 1.8)
        #expect(PdfItemBuilder.subtaskIndent(depth: 4) == 2.4)
    }
}
