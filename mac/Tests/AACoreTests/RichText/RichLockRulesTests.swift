// TV: 05 §7.4 (lock geometry on `abcDEFghi` with DEF locked), §3.1 (geometry rules), CONT-060/061 (lock / unlock
//     granularity), CONT-065 (scan; no gold-colour false positives), CONT-159 (sources), §XD.3 lockSource row,
//     §7.7 item 5 (lock sentinel round trip), XD-C15 (root sentinel locks nothing).
import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct RichLockRulesTests {
    static func abc() -> NSMutableAttributedString {
        let (s, _) = RichTest.read(RichTest.doc(##"<Paragraph><Run>abc</Run><Run Background="#FFFFE699">DEF</Run><Run>ghi</Run></Paragraph>"##))
        return NSMutableAttributedString(attributedString: s)
    }

    @Test func geometryTable() {
        let s = Self.abc()
        func ins(_ at: Int) -> Bool { LockRules.blocksEdit(s, range: NSRange(location: at, length: 0), replacementLength: 1) }
        func del(_ a: Int, _ b: Int) -> Bool { LockRules.blocksEdit(s, range: NSRange(location: a, length: b - a), replacementLength: 0) }
        #expect(!ins(3))                    // between c and D
        #expect(ins(4) && ins(5))           // inside
        #expect(!ins(6))                    // after F
        #expect(!del(2, 3))                 // Backspace at 3 deletes c
        #expect(del(3, 4) && del(5, 6))     // Backspace at 4 (D) / at 6 (F)
        #expect(!del(2, 3))                 // Delete at 2 deletes c
        #expect(del(3, 4))                  // Delete at 3 deletes D
        #expect(!del(0, 3) && !del(6, 9))   // replace [0,3) / [6,9)
        #expect(del(2, 4) && del(5, 7))     // replace [2,4) / [5,7)
        #expect(!ins(0) && !ins(9) && !ins(10))   // out-of-range neighbours count as unlocked
        #expect(!LockRules.blocksEdit(s, range: NSRange(location: 4, length: 0), replacementLength: 0))   // no-op edit
    }

    @Test func unlockingPartOfAStretchUnlocksTheWholeStretch() {
        let s = Self.abc()
        #expect(LockRules.lockedRanges(s, touching: NSRange(location: 4, length: 1)) == [NSRange(location: 3, length: 3)])
        #expect(LockRules.lockedRanges(s, touching: NSRange(location: 6, length: 0)) == [NSRange(location: 3, length: 3)])
        #expect(LockRules.lockedRanges(s, touching: NSRange(location: 0, length: 2)).isEmpty)
        let done = LockRules.unlock(s, range: NSRange(location: 4, length: 1))
        #expect(done == [NSRange(location: 3, length: 3)])
        #expect(!LockRules.hasAnyLock(s))
        #expect((0..<s.length).allSatisfy { !LockRules.isLocked(s, at: $0) })
    }

    @Test func hasAnyLockScans() throws {
        #expect(!LockRules.quickHasAnyLock(""))
        #expect(!LockRules.quickHasAnyLock(RichTest.doc("<Paragraph><Run>x</Run></Paragraph>")))
        #expect(LockRules.quickHasAnyLock(try RichTest.sample("S-06-lock-linebreak-tab-lang.xaml")))
        // Gold colours that are not the sentinel do not count (the old substring test false-positived).
        #expect(!LockRules.quickHasAnyLock(RichTest.doc(##"<Paragraph><Run Background="#80FFE699">x</Run><Run Foreground="#FFFFE6990">y</Run></Paragraph>"##)))
        #expect(!LockRules.quickHasAnyLock(RichTest.doc(##"<Paragraph><Run Tag="FFE699">x</Run></Paragraph>"##)))
        #expect(LockRules.quickHasAnyLock(RichTest.doc(##"<Paragraph Background="#ffe699"><Run>x</Run></Paragraph>"##)))
        #expect(LockRules.quickHasAnyLock(RichTest.doc(##"<Paragraph><Run><Run.Background><SolidColorBrush Color="#FFE699" Opacity="0.2"/></Run.Background>x</Run></Paragraph>"##)))
        #expect(!LockRules.quickHasAnyLock(##"<Section xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Background="#FFFFE699"><Paragraph/></Section>"##))
        #expect(!LockRules.quickHasAnyLock("<Section><Paragraph Background=\"#FFFFE699\">"))      // unparseable
        let (s, m) = RichTest.read(RichTest.doc(##"<Paragraph><Run>x</Run></Paragraph>"##))
        #expect(!m.hasAnyLock && !LockRules.hasAnyLock(s))
    }

    @Test func paragraphSentinelLocksEveryCharacterButNotTheBoundary() {
        let (s, _) = RichTest.read(RichTest.doc(##"<Paragraph Background="#FFFFE699"><Run>abc</Run></Paragraph><Paragraph><Run>x</Run></Paragraph>"##))
        #expect((0..<3).allSatisfy { LockRules.isLocked(s, at: $0) })
        #expect(!LockRules.isLocked(s, at: 3))                                       // the terminator
        #expect(!LockRules.blocksEdit(s, range: NSRange(location: 3, length: 0), replacementLength: 1))   // typing at the end
        #expect(LockRules.blocksEdit(s, range: NSRange(location: 1, length: 0), replacementLength: 1))
    }

    @Test func listMarkersAreNeverLocked() {
        let (s, _) = RichTest.read(RichTest.doc(##"<List><ListItem Background="#FFFFE699"><Paragraph><Run>item</Run></Paragraph></ListItem></List>"##))
        #expect(!LockRules.isLocked(s, at: 0) && !LockRules.isLocked(s, at: 1) && !LockRules.isLocked(s, at: 2))
        #expect(LockRules.isLocked(s, at: 3))
        #expect(!LockRules.blocksEdit(s, range: NSRange(location: 0, length: 3), replacementLength: 0))
    }

    @Test func lockAndUnlockRoundTripThroughTheWriter() {
        let (s, m) = RichTest.read(RichTest.doc("<Paragraph><Run>alpha beta</Run></Paragraph>"))
        let e = NSMutableAttributedString(attributedString: s)
        LockRules.lock(e, range: NSRange(location: 6, length: 4))
        #expect(LockRules.hasAnyLock(e))
        #expect(RichTest.body(XamlWriter.write(e, metadata: m, context: .containerEditor))
                == ##"<Paragraph><Run>alpha </Run><Run Background="#FFFFE699">beta</Run></Paragraph>"##)
        LockRules.unlock(e, range: NSRange(location: 7, length: 0))
        #expect(RichTest.body(XamlWriter.write(e, metadata: m, context: .containerEditor))
                == "<Paragraph><Run>alpha beta</Run></Paragraph>")
    }

    @Test func unlockingInlineAncestorAndBlockLocks() {
        // inlineAncestor: the lock Span goes, the run's own highlight stays.
        let (a, ma) = RichTest.read(RichTest.doc(##"<Paragraph><Span Background="#FFFFE699"><Run Background="#FFFFFF00">x</Run></Span><Run>y</Run></Paragraph>"##))
        let ea = NSMutableAttributedString(attributedString: a)
        LockRules.unlock(ea, range: NSRange(location: 0, length: 1))
        #expect(RichTest.body(XamlWriter.write(ea, metadata: ma, context: .containerEditor))
                == ##"<Paragraph><Run Background="#FFFFFF00">x</Run><Run>y</Run></Paragraph>"##)
        // block: the sentinel leaves the paragraph (and its display block), the whole element unlocks.
        let (b, mb) = RichTest.read(RichTest.doc(##"<Paragraph Background="#FFFFE699" Margin="0,2,0,2"><Run>abc</Run><Run>def</Run></Paragraph>"##))
        let eb = NSMutableAttributedString(attributedString: b)
        LockRules.unlock(eb, range: NSRange(location: 4, length: 1))
        #expect(!LockRules.hasAnyLock(eb))
        #expect(RichTest.body(XamlWriter.write(eb, metadata: mb, context: .containerEditor))
                == ##"<Paragraph Margin="0,2,0,2"><Run>abcdef</Run></Paragraph>"##)
        let ps = eb.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        #expect(ps.textBlocks.allSatisfy { $0.backgroundColor == nil })
        // A container sentinel (ListItem) unlocks every paragraph of that item.
        let (c, mc) = RichTest.read(RichTest.doc(##"<List MarkerStyle="Disc"><ListItem Background="#FFFFE699"><Paragraph><Run>p1</Run></Paragraph><Paragraph><Run>p2</Run></Paragraph></ListItem></List>"##))
        let ec = NSMutableAttributedString(attributedString: c)
        LockRules.unlock(ec, range: NSRange(location: 3, length: 1))
        #expect(!LockRules.hasAnyLock(ec))
        #expect(!XamlWriter.write(ec, metadata: mc, context: .containerEditor).contains("FFE699"))
    }

    /// CONT-061: the unit is the element carrying the sentinel (`LockedAncestor`, cleared once per element) — a
    /// separately locked neighbour outside the selection stays locked; every element the selection touches unlocks.
    @Test func unlockGranularityIsTheLockedElement() {
        let xaml = RichTest.doc(##"<Paragraph><Run FontWeight="Bold" Background="#FFFFE699">AB</Run><Run Background="#FFFFE699">CD</Run><Run>ef</Run></Paragraph>"##)
        let (s, m) = RichTest.read(xaml)
        #expect(LockRules.lockedElement(s, at: 1) == NSRange(location: 0, length: 2))
        #expect(LockRules.lockedElement(s, at: 2) == NSRange(location: 2, length: 2))
        #expect(LockRules.lockedElement(s, at: 4) == nil)
        let e = NSMutableAttributedString(attributedString: s)
        #expect(LockRules.unlock(e, range: NSRange(location: 1, length: 1)) == [NSRange(location: 0, length: 2)])
        #expect(!LockRules.isLocked(e, at: 0) && LockRules.isLocked(e, at: 2) && LockRules.isLocked(e, at: 3))
        #expect(RichTest.body(XamlWriter.write(e, metadata: m, context: .containerEditor))
                == ##"<Paragraph><Run FontWeight="Bold">AB</Run><Run Background="#FFFFE699">CD</Run><Run>ef</Run></Paragraph>"##)
        // A selection across both elements unlocks both.
        let both = NSMutableAttributedString(attributedString: s)
        #expect(LockRules.unlock(both, range: NSRange(location: 1, length: 2)) == [NSRange(location: 0, length: 2), NSRange(location: 2, length: 2)])
        #expect(!LockRules.hasAnyLock(both))
        // A caret (empty range) unlocks the element at or just before it.
        let caret = NSMutableAttributedString(attributedString: s)
        #expect(LockRules.unlock(caret, range: NSRange(location: 4, length: 0)) == [NSRange(location: 2, length: 2)])
        #expect(LockRules.unlock(caret, range: NSRange(location: 5, length: 0)).isEmpty)
    }

    /// Windows clears only the nearest sentinel: a locked run inside a locked paragraph stays locked by the paragraph.
    @Test func unlockingARunInsideALockedBlockLeavesTheBlockLock() {
        let (s, m) = RichTest.read(RichTest.doc(##"<Paragraph Background="#FFFFE699"><Run Background="#FFFFE699">ab</Run><Run>cd</Run></Paragraph>"##))
        let e = NSMutableAttributedString(attributedString: s)
        #expect(e.attribute(.aaLockSource, at: 0, effectiveRange: nil) as? String == "inlineRun")
        LockRules.unlock(e, range: NSRange(location: 0, length: 1))
        #expect(LockRules.isLocked(e, at: 0) && e.attribute(.aaLockSource, at: 0, effectiveRange: nil) as? String == "block")
        #expect(RichTest.body(XamlWriter.write(e, metadata: m, context: .containerEditor))
                == ##"<Paragraph Background="#FFFFE699"><Run>abcd</Run></Paragraph>"##)
        // The second unlock removes the block sentinel.
        LockRules.unlock(e, range: NSRange(location: 0, length: 1))
        #expect(!LockRules.hasAnyLock(e))
        #expect(RichTest.body(XamlWriter.write(e, metadata: m, context: .containerEditor)) == "<Paragraph><Run>abcd</Run></Paragraph>")
    }

    @Test func highlightPickedAsTheSentinelIsALock() {
        let s = NSMutableAttributedString(string: "gold\n", attributes: RichEditTree.defaultCharacterAttributes)
        s.addAttribute(.backgroundColor, value: NSColor(srgbRed: 1, green: 230.0 / 255, blue: 153.0 / 255, alpha: 1),
                       range: NSRange(location: 0, length: 4))
        #expect(LockRules.isLocked(s, at: 0) && LockRules.hasAnyLock(s))
    }
}

@MainActor
@Suite struct RichPerformanceTests {
    /// §XD.5 budget: parse + resolve of a 1 MB string under 50 ms on Apple silicon (release build). Debug builds run
    /// the same pass with a looser bound; the measured times are printed.
    @Test func oneMegabyteParseAndResolve() throws {
        var body = ""
        var k = 0
        while body.utf8.count < 1_000_000 {
            body += ##"<Paragraph><Run>Line \##(k) — check the main engine </Run><Run FontWeight="Bold" Foreground="#FFC00000">oil level</Run><Span Background="#FFFFFF00"><Run> and log it.</Run></Span></Paragraph>"##
            k += 1
        }
        let xaml = RichTest.doc(body)
        let t0 = Date()
        guard case .success(let d) = XamlDOM.parse(xaml) else { Issue.record("parse"); return }
        let r = XamlStyleResolver(d, context: .containerEditor)
        let elapsed = Date().timeIntervalSince(t0)
        #expect(r.computed(d.root).fontSize == 14 && d.nodes.count > 20_000)
        #if DEBUG
        let budget = 1.5
        #else
        let budget = 0.05
        #endif
        print("RichPerformance: parse+resolve of \(xaml.utf8.count) bytes, \(d.nodes.count) nodes: \(Int(elapsed * 1000)) ms")
        #expect(elapsed < budget, "parse + resolve took \(elapsed) s")
        // The full read (projection into NSAttributedString) of the same note stays interactive.
        let t1 = Date()
        _ = XamlReader.read(xaml, context: .containerEditor)
        print("RichPerformance: full read \(Int(Date().timeIntervalSince(t1) * 1000)) ms")
        #expect(LockRules.quickHasAnyLock(xaml) == false)
    }
}
