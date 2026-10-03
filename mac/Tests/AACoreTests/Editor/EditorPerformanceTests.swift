// TV: ARCHITECTURE.md §9.7 (large notes stay responsive): the per-selection format-bar summary, the lock scan and the
//     "unchanged → never rewritten" comparison on a ≈1 MB note. Bounds are generous (shared build machine); they
//     guard against accidental quadratic work, not micro-timings.
import AppKit
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct EditorPerformanceTests {
    /// ≈1 MB of text in 20 000 paragraphs with alternating bold runs.
    static func bigNote() -> NSMutableAttributedString {
        let base = EditorFormatting.defaultTypingAttributes()
        var bold = base
        bold[.font] = EditorFormatting.font(EditorFormatting.defaultFont(), bold: true)
        let s = NSMutableAttributedString()
        s.beginEditing()
        for i in 0..<20_000 {
            s.append(NSAttributedString(string: "Line \(i): check the purifier ", attributes: base))
            s.append(NSAttributedString(string: "sludge discharge", attributes: bold))
            s.append(NSAttributedString(string: " interval before departure.\n", attributes: base))
        }
        s.endEditing()
        return s
    }

    @Test func selectAllSummaryIsFast() {
        let s = Self.bigNote()
        #expect(s.length > 1_000_000)
        let t0 = Date()
        let sum = EditorFormatting.summary(s, selection: NSRange(location: 0, length: s.length),
                                           typing: EditorFormatting.defaultTypingAttributes())
        let dt = Date().timeIntervalSince(t0)
        #expect(!sum.bold)
        #expect(dt < 1.0, "summary took \(dt) s")
    }

    @Test func caretSummaryIsInstant() {
        let s = Self.bigNote()
        let t0 = Date()
        for i in stride(from: 0, to: 2000, by: 1) {
            _ = EditorFormatting.summary(s, selection: NSRange(location: i * 400, length: 0),
                                         typing: EditorFormatting.defaultTypingAttributes())
        }
        let dt = Date().timeIntervalSince(t0)
        #expect(dt < 1.0, "2 000 caret summaries took \(dt) s")
    }

    @Test func lockScanIsLinear() {
        let s = Self.bigNote()
        EditorLocking.lock(s, range: NSRange(location: s.length - 10, length: 5))
        let t0 = Date()
        #expect(EditorLocking.hasAnyLock(s))
        #expect(EditorLocking.blocksEdit(s, range: NSRange(location: 0, length: s.length)))
        #expect(!EditorLocking.blocksEdit(s, range: NSRange(location: 100, length: 0)))
        #expect(Date().timeIntervalSince(t0) < 1.0)
    }

    @Test func unchangedNoteComparisonIsFast() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "DOC")
        let note = Self.bigNote()
        let s = EditorSession(reader: { _, ctx in .document(note, RichTextMetadata(context: ctx)) },
                              writer: { _, _, _ in "WRITTEN" }, engineAvailable: { true })
        let storage = NSTextStorage()
        s.textProvider = { NSAttributedString(attributedString: storage) }
        storage.setAttributedString(s.load(c, store: made.store, passwords: nil).text)
        s.rebaseLoadedText(storage)
        s.noteEdited()
        let t0 = Date()
        s.flushPending()
        #expect(Date().timeIntervalSince(t0) < 1.0)
        #expect(c.richTextXaml == "DOC")                // identical text: never rewritten
    }
}
