// TV: 05 CONT-020…028 (toggle semantics, family token, size step, colours, clear formatting), K-3 (independent
//     underline / strike), D-4 (Highlight and Clear formatting keep the lock), CONT-030 (baseline variants), §7.2 item 10
//     (paragraph indent 0 → 24 → 48; outdent clamps at 0; Auto counts as 0), §7.4 (lock geometry), CONT-060/061
//     (lock / unlock stretch), CONT-032 / K-15 (table shape and placement), §6.6 (paste routing, sanitising,
//     plain text).
import AppKit
import Foundation
import Testing
@testable import AACore

@MainActor private enum EditorFx {
    static let ink = EditorFormatting.editorInk
    static var base: [NSAttributedString.Key: Any] { EditorFormatting.defaultTypingAttributes() }

    static func text(_ s: String) -> NSMutableAttributedString { NSMutableAttributedString(string: s, attributes: base) }

    static func bold(_ s: NSMutableAttributedString, _ r: NSRange) {
        let f = s.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
        s.addAttribute(.font, value: EditorFormatting.font(f, bold: true), range: r)
    }

    static func isBold(_ s: NSAttributedString, _ i: Int) -> Bool {
        EditorFormatting.isBold(s.attribute(.font, at: i, effectiveRange: nil) as? NSFont)
    }
}

@MainActor @Suite struct EditorFormattingTests {
    // TV: 05 CONT-023 — uniformly bold → normal; mixed / normal → bold
    @Test func boldToggleSemantics() {
        let s = EditorFx.text("abcdef")
        EditorFx.bold(s, NSRange(location: 0, length: 3))
        EditorFormatting.apply(.bold, to: s, range: NSRange(location: 0, length: 6))         // mixed → bold
        #expect((0..<6).allSatisfy { EditorFx.isBold(s, $0) })
        EditorFormatting.apply(.bold, to: s, range: NSRange(location: 0, length: 6))         // uniform → normal
        #expect((0..<6).allSatisfy { !EditorFx.isBold(s, $0) })
    }

    @Test func boldDropsWeightToken() {
        let s = EditorFx.text("ab")
        s.addAttribute(.aaFontWeightToken, value: "SemiBold", range: NSRange(location: 0, length: 2))
        EditorFormatting.apply(.bold, to: s, range: NSRange(location: 0, length: 2))
        #expect(s.attribute(.aaFontWeightToken, at: 0, effectiveRange: nil) == nil)
    }

    @Test func italicToggle() {
        let s = NSMutableAttributedString(string: "ab", attributes: [.font: NSFont(name: "Helvetica", size: 14)!,
                                                                    .aaFontFamilyName: "Helvetica",
                                                                    .aaFontStyleToken: "Oblique"])
        let r = NSRange(location: 0, length: 2)
        EditorFormatting.apply(.italic, to: s, range: r)
        #expect(EditorFormatting.isItalic(s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont))
        #expect(s.attribute(.aaFontStyleToken, at: 0, effectiveRange: nil) == nil)
        #expect(EditorFormatting.familyToken(s.attributes(at: 0, effectiveRange: nil)) == "Helvetica")
        EditorFormatting.apply(.italic, to: s, range: r)
        #expect(!EditorFormatting.isItalic(s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont))
    }

    // TV: 05 K-3 — the Mac toggles underline and strike independently
    @Test func underlineAndStrikeIndependent() {
        let s = EditorFx.text("abc")
        let r = NSRange(location: 0, length: 3)
        EditorFormatting.apply(.underline, to: s, range: r)
        EditorFormatting.apply(.strikethrough, to: s, range: r)
        #expect(s.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(s.attribute(.strikethroughStyle, at: 1, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        EditorFormatting.apply(.strikethrough, to: s, range: r)
        #expect(s.attribute(.strikethroughStyle, at: 1, effectiveRange: nil) == nil)
        #expect(s.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
    }

    // TV: 05 CONT-020 / XD.5 — picking a family replaces the stored token
    @Test func fontFamilySetsToken() {
        let s = EditorFx.text("abc")
        EditorFormatting.apply(.fontFamily("Helvetica"), to: s, range: NSRange(location: 0, length: 3))
        #expect(s.attribute(.aaFontFamilyName, at: 0, effectiveRange: nil) as? String == "Helvetica")
        #expect((s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName == "Helvetica")
    }

    @Test func fontFamilyKeepsBold() {
        let s = EditorFx.text("abc")
        EditorFx.bold(s, NSRange(location: 0, length: 3))
        EditorFormatting.apply(.fontFamily("Helvetica"), to: s, range: NSRange(location: 0, length: 3))
        #expect(EditorFx.isBold(s, 0))
    }

    // TV: 05 CONT-021 / CONT-030 — explicit size; WPF built-in step 0.75 per press, bounded
    @Test func sizesAndSteps() {
        let s = EditorFx.text("abc")
        let r = NSRange(location: 0, length: 3)
        EditorFormatting.apply(.fontSize(16), to: s, range: r)
        #expect((s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 16)
        EditorFormatting.apply(.step(bigger: true), to: s, range: r)
        #expect((s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 16.75)
        EditorFormatting.apply(.step(bigger: false), to: s, range: r)
        EditorFormatting.apply(.step(bigger: false), to: s, range: r)
        #expect((s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 15.25)
        EditorFormatting.apply(.fontSize(0), to: s, range: r)                              // ignored (CONT-021 > 0)
        #expect((s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 15.25)
        let tiny = EditorFormatting.transform([.font: EditorFormatting.defaultFont(size: 0.75)], .step(bigger: false), on: true)
        #expect((tiny[.font] as? NSFont)?.pointSize == 0.75)
    }

    // TV: 05 CONT-025 — text colour drops link styling flags
    @Test func foregroundColour() {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let a = EditorFormatting.transform([.aaLinkStyled: true, .aaUnderlyingForeground: EditorFx.ink], .foreground(red), on: true)
        #expect(a[.foregroundColor] as? NSColor == red)
        #expect(a[.aaLinkStyled] == nil && a[.aaUnderlyingForeground] == nil)
    }

    // TV: 05 D-4 — Highlight never overwrites the sentinel; a sentinel highlight creates a lock
    @Test func highlightKeepsLocks() {
        let s = EditorFx.text("abcDEFghi")
        EditorLocking.lock(s, range: NSRange(location: 3, length: 3))
        let yellow = NSColor(srgbRed: 1, green: 0.96, blue: 0.62, alpha: 1)
        EditorFormatting.apply(.highlight(yellow), to: s, range: NSRange(location: 0, length: 9))
        #expect(EditorLocking.isLocked(s, at: 4))
        #expect(s.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor == yellow)
        EditorFormatting.apply(.highlight(nil), to: s, range: NSRange(location: 0, length: 9))
        #expect(EditorLocking.isLocked(s, at: 4))
        #expect(s.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
        EditorFormatting.apply(.highlight(EditorLocking.sentinelColor), to: s, range: NSRange(location: 0, length: 1))
        #expect(EditorLocking.isLocked(s, at: 0))
    }

    // TV: 05 CONT-028 + D-4 — clear formatting: weight/style/decorations/ink/background reset, lock kept
    @Test func clearFormatting() {
        let s = EditorFx.text("abcDEF")
        let all = NSRange(location: 0, length: 6)
        EditorFx.bold(s, all)
        s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: all)
        s.addAttribute(.foregroundColor, value: NSColor.red, range: all)
        s.addAttribute(.backgroundColor, value: NSColor.green, range: NSRange(location: 0, length: 3))
        EditorLocking.lock(s, range: NSRange(location: 3, length: 3))
        EditorFormatting.apply(.clearFormatting, to: s, range: all)
        #expect(!EditorFx.isBold(s, 0))
        #expect(s.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
        #expect(s.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == EditorFx.ink)
        #expect(s.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
        #expect(EditorLocking.isLocked(s, at: 3))
        #expect(s.attribute(.aaFontFamilyName, at: 0, effectiveRange: nil) as? String == "Consolas")   // family kept
    }

    // TV: 05 CONT-030 — super/subscript write Typography.Variants
    @Test func baselineVariants() {
        let sup = EditorFormatting.transform([:], .baseline(1), on: true)
        #expect(sup[.superscript] as? Int == 1)
        #expect((sup[.aaInheritedExtras] as? [String: String])?["Typography.Variants"] == "Superscript")
        let sub = EditorFormatting.transform(sup, .baseline(-1), on: true)
        #expect((sub[.aaInheritedExtras] as? [String: String])?["Typography.Variants"] == "Subscript")
        let def = EditorFormatting.transform(sub, .baseline(0), on: true)
        #expect(def[.superscript] == nil && def[.aaInheritedExtras] == nil)
    }

    @Test func listMarkersAreSkipped() {
        let s = EditorFx.text("\t•\tItem")
        s.addAttribute(.aaListMarker, value: true, range: NSRange(location: 0, length: 3))
        EditorFormatting.apply(.bold, to: s, range: NSRange(location: 0, length: 7))
        #expect(!EditorFx.isBold(s, 1))
        #expect(EditorFx.isBold(s, 4))
    }

    // TV: 05 CONT-027 — alignment on every touched paragraph
    @Test func alignment() {
        let s = EditorFx.text("one\ntwo\nthree")
        EditorFormatting.setAlignment(.center, in: s, range: NSRange(location: 1, length: 5))
        func align(_ i: Int) -> NSTextAlignment? { (s.attribute(.paragraphStyle, at: i, effectiveRange: nil) as? NSParagraphStyle)?.alignment }
        #expect(align(0) == .center && align(4) == .center)
        #expect(align(9) != .center)
    }

    // TV: 05 §7.2 item 10 — 0 → 24 → 48; outdent from 10 → 0; NaN treated as 0
    @Test func paragraphIndent() {
        let s = EditorFx.text("para")
        let r = NSRange(location: 0, length: 0)
        func head() -> CGFloat { (s.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? -1 }
        func first() -> CGFloat { (s.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent ?? -1 }
        EditorFormatting.indentParagraphs(in: s, range: r, increase: true)
        #expect(head() == 24 && first() == 24)
        EditorFormatting.indentParagraphs(in: s, range: r, increase: true)
        #expect(head() == 48)
        let p = NSMutableParagraphStyle()
        p.headIndent = 10
        s.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: 4))
        EditorFormatting.indentParagraphs(in: s, range: r, increase: false)
        #expect(head() == 0 && first() == 0)
        let nan = NSMutableParagraphStyle()
        nan.headIndent = .nan
        s.addAttribute(.paragraphStyle, value: nan, range: NSRange(location: 0, length: 4))
        EditorFormatting.indentParagraphs(in: s, range: r, increase: true)
        #expect(head() == 24)
    }

    // TV: 05 CONT-022 — the summary reflects family and size (and B/I/U/S on the Mac)
    @Test func summary() {
        let s = EditorFx.text("abcdef")
        EditorFx.bold(s, NSRange(location: 0, length: 6))
        var sum = EditorFormatting.summary(s, selection: NSRange(location: 0, length: 6), typing: [:])
        #expect(sum.family == "Consolas" && sum.size == 14 && sum.bold && !sum.underline && sum.hasSelection)
        EditorFormatting.apply(.fontSize(20), to: s, range: NSRange(location: 0, length: 2))
        sum = EditorFormatting.summary(s, selection: NSRange(location: 0, length: 6), typing: [:])
        #expect(sum.size == nil)                                                           // mixed
        sum = EditorFormatting.summary(s, selection: NSRange(location: 2, length: 0),
                                       typing: EditorFormatting.defaultTypingAttributes())
        #expect(sum.size == 14 && !sum.hasSelection && !sum.bold)
    }

    @Test func plainBaseAttributesDropLocksAndLinks() {
        var a = EditorFormatting.defaultTypingAttributes()
        a[.backgroundColor] = EditorLocking.sentinelColor
        a[.link] = URL(string: "https://x/")!
        a[.font] = EditorFormatting.font(EditorFormatting.defaultFont(), bold: true)
        let b = EditorFormatting.plainBaseAttributes(from: a)
        #expect(b[.backgroundColor] == nil && b[.link] == nil)
        #expect(!EditorFormatting.isBold(b[.font] as? NSFont))
        #expect(b[.aaFontFamilyName] as? String == "Consolas")
    }

    // TV: 05 §6.4 / §4.3.7 rule 6 — text typed right after a list marker takes the item's first character, never the
    // marker tag (the writer drops marker text, so a tagged typed run would vanish on save)
    @Test func typingAfterAListMarkerTakesTheItemText() {
        let s = NSMutableAttributedString()
        var marker = EditorFx.base
        marker[.aaListMarker] = true
        marker[.foregroundColor] = NSColor.systemGray
        s.append(NSAttributedString(string: "\t•\t", attributes: marker))
        var item = EditorFx.base
        item[.font] = EditorFormatting.font(EditorFormatting.defaultFont(), bold: true)
        s.append(NSAttributedString(string: "Check oil\n", attributes: item))
        let typing = s.attributes(at: 2, effectiveRange: nil)            // what NSTextView takes at caret 3
        #expect(EditorFormatting.needsCleaning(typing))
        let clean = EditorFormatting.cleanTypingAttributes(typing, in: s, caret: 3)
        #expect(clean[.aaListMarker] == nil)
        #expect(EditorFormatting.isBold(clean[.font] as? NSFont))
        #expect((clean[.foregroundColor] as? NSColor) == EditorFormatting.editorInk)
        // An empty item (marker then the terminator): only the tag goes.
        let empty = NSMutableAttributedString(string: "\t•\t", attributes: marker)
        empty.append(NSAttributedString(string: "\n", attributes: EditorFx.base))
        let c2 = EditorFormatting.cleanTypingAttributes(empty.attributes(at: 2, effectiveRange: nil), in: empty, caret: 3)
        #expect(c2[.aaListMarker] == nil && (c2[.foregroundColor] as? NSColor) == NSColor.systemGray)
    }

    // TV: XD.3 / CONT-166 — in-run newline sequences, preserved fragments, attachments and locks never spread
    @Test func typingNeverInheritsStoredOnlyAttributes() {
        var a = EditorFx.base
        a[.aaInRunNewline] = "\r\n"
        a[.aaPreservedXaml] = "<Figure/>"
        a[.attachment] = NSTextAttachment()
        a[.backgroundColor] = EditorLocking.sentinelColor
        let s = NSAttributedString(string: "x", attributes: a)
        #expect(EditorFormatting.needsCleaning(a))
        let clean = EditorFormatting.cleanTypingAttributes(a, in: s, caret: 1)
        #expect(clean[.aaInRunNewline] == nil && clean[.aaPreservedXaml] == nil && clean[.attachment] == nil)
        #expect(clean[.backgroundColor] == nil)
        #expect(clean[.aaFontFamilyName] as? String == "Consolas")
        #expect(!EditorFormatting.needsCleaning(EditorFx.base))
        // Plain paste and link insertion use the same rule.
        var typing = EditorFx.base
        typing[.aaListMarker] = true
        typing[.aaInRunNewline] = "\r\n"
        let p = EditorRichSanitiser.plain("abc", typing: typing)
        #expect(p.attribute(.aaListMarker, at: 0, effectiveRange: nil) == nil)
        #expect(p.attribute(.aaInRunNewline, at: 0, effectiveRange: nil) == nil)
        let edit = EditorLinkRules.insertion(url: "https://x.org/", in: NSAttributedString(), selection: NSRange(location: 0, length: 0),
                                             typing: typing, linkColor: EditorLinkRules.editorLinkColor)
        #expect(edit.replacement.attribute(.aaListMarker, at: 0, effectiveRange: nil) == nil)
    }

    @Test func numberedListDetection() {
        #expect(EditorFormatting.isNumbered(NSTextList(markerFormat: .decimal, options: 0)))
        #expect(EditorFormatting.isNumbered(NSTextList(markerFormat: .lowercaseAlpha, options: 0)))
        #expect(EditorFormatting.isNumbered(NSTextList(markerFormat: .lowercaseRoman, options: 0)))
        #expect(!EditorFormatting.isNumbered(NSTextList(markerFormat: .disc, options: 0)))
        #expect(!EditorFormatting.isNumbered(NSTextList(markerFormat: .square, options: 0)))
    }
}

@MainActor @Suite struct EditorLockingTests {
    /// `abcDEFghi` with `DEF` locked (indices 3…5).
    private func doc() -> NSMutableAttributedString {
        let s = EditorFx.text("abcDEFghi")
        EditorLocking.lock(s, range: NSRange(location: 3, length: 3))
        return s
    }

    // TV: 05 §7.4 lock geometry table
    @Test func geometry() {
        let s = doc()
        func ins(_ i: Int) -> Bool { EditorLocking.blocksEdit(s, range: NSRange(location: i, length: 0)) }
        func rep(_ a: Int, _ b: Int) -> Bool { EditorLocking.blocksEdit(s, range: NSRange(location: a, length: b - a)) }
        #expect(!ins(3))                 // insert between c and D
        #expect(ins(4) && ins(5))
        #expect(!ins(6))                 // after F
        #expect(!rep(2, 3))              // Backspace at 3 deletes c
        #expect(rep(3, 4) && rep(5, 6))  // Backspace at 4 / 6
        #expect(!rep(2, 3))              // Delete at 2 deletes c
        #expect(rep(3, 4))               // Delete at 3 deletes D
        #expect(!rep(0, 3) && !rep(6, 9))
        #expect(rep(2, 4) && rep(5, 7))
        #expect(EditorLocking.editBlocked(s, range: NSRange(location: 4, length: 0), replacementLength: 5))  // paste-text-only at 4
        #expect(!EditorLocking.blocksEdit(s, range: NSRange(location: 0, length: 0)))
        #expect(!EditorLocking.blocksEdit(s, range: NSRange(location: 9, length: 0)))
    }

    @Test func hasAnyLock() {
        #expect(EditorLocking.hasAnyLock(doc()))
        #expect(!EditorLocking.hasAnyLock(EditorFx.text("plain")))
        let gold = EditorFx.text("gold")
        gold.addAttribute(.backgroundColor, value: NSColor(srgbRed: 1, green: 230 / 255.0, blue: 152 / 255.0, alpha: 1),
                          range: NSRange(location: 0, length: 4))
        #expect(!EditorLocking.hasAnyLock(gold))                       // only the exact sentinel counts
    }

    // TV: 05 §7.4 — unlock selecting only E unlocks the whole DEF stretch
    @Test func unlockWholeStretch() {
        let s = doc()
        let stretches = EditorLocking.lockedStretches(s, touching: NSRange(location: 4, length: 1))
        #expect(stretches == [NSRange(location: 3, length: 3)])
        #expect(EditorLocking.unlock(s, stretches: stretches))
        #expect(!EditorLocking.hasAnyLock(s))
    }

    @Test func unlockKeepsOtherBackgrounds() {
        let s = EditorFx.text("xxDEF")
        let green = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        s.addAttribute(.backgroundColor, value: green, range: NSRange(location: 0, length: 2))
        EditorLocking.lock(s, range: NSRange(location: 2, length: 3))
        EditorLocking.unlock(s, stretches: EditorLocking.lockedStretches(s, touching: NSRange(location: 0, length: 5)))
        #expect(s.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor == green)
        #expect(s.attribute(.backgroundColor, at: 3, effectiveRange: nil) == nil)
    }

    // TV: XD.3 — stored lock sources (inlineAncestor, block) and a block's carried Background
    @Test func unlockStoredSources() {
        let s = EditorFx.text("ab\ncd\n")
        s.addAttribute(.aaLockSource, value: "inlineAncestor", range: NSRange(location: 0, length: 2))
        s.addAttribute(.aaLockSource, value: "block", range: NSRange(location: 3, length: 3))
        s.addAttribute(.aaParagraphAttrs, value: [["Background", "", "#FFFFE699"], ["Margin", "", "0,1,0,1"]],
                       range: NSRange(location: 3, length: 3))
        #expect(EditorLocking.isLocked(s, at: 0) && EditorLocking.isLocked(s, at: 4))
        EditorLocking.unlock(s, stretches: EditorLocking.lockedStretches(s, touching: NSRange(location: 0, length: 6)))
        #expect(!EditorLocking.hasAnyLock(s))
        #expect((s.attribute(.aaParagraphAttrs, at: 4, effectiveRange: nil) as? [[String]]) == [["Margin", "", "0,1,0,1"]])
    }

    // TV: XD.3 `block` row / REQ-W-CONT-03 — a lock carried on a ListItem / TableCell does not come back after save
    @Test func unlockCarriedContainerSentinels() {
        for body in [##"<List MarkerStyle="Disc"><ListItem Background="#FFFFE699"><Paragraph><Run>item</Run></Paragraph></ListItem></List>"##,
                     ##"<Table CellSpacing="0"><TableRowGroup><TableRow><TableCell Background="#FFFFE699"><Paragraph><Run>cell</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table>"##] {
            let (s, m) = RichTest.read(RichTest.doc(body))
            let e = NSMutableAttributedString(attributedString: s)
            #expect(EditorLocking.hasAnyLock(e))
            #expect(EditorLocking.unlock(e, stretches: EditorLocking.lockedStretches(e, touching: NSRange(location: 0, length: e.length))))
            #expect(!EditorLocking.hasAnyLock(e))
            let xaml = XamlWriter.write(e, metadata: m, context: .containerEditor)
            #expect(!xaml.contains("FFFFE699"))
            #expect(!EditorLocking.hasAnyLock(RichTest.read(xaml).0))
        }
    }

    @Test func markersNeverCountAsLocked() {
        let s = EditorFx.text("\t•\tx")
        s.addAttribute(.backgroundColor, value: EditorLocking.sentinelColor, range: NSRange(location: 0, length: 3))
        s.addAttribute(.aaListMarker, value: true, range: NSRange(location: 0, length: 3))
        #expect(!EditorLocking.isLocked(s, at: 1))
        #expect(!EditorLocking.hasAnyLock(s))
    }

    @Test func typingAttributesNeverExtendALock() {
        let a: [NSAttributedString.Key: Any] = [.backgroundColor: EditorLocking.sentinelColor, .aaLockSource: "block"]
        let t = EditorLocking.unlockedTypingAttributes(a)
        #expect(t[.backgroundColor] == nil && t[.aaLockSource] == nil)
        let plain: [NSAttributedString.Key: Any] = [.backgroundColor: NSColor.green]
        #expect(EditorLocking.unlockedTypingAttributes(plain)[.backgroundColor] as? NSColor == NSColor.green)
    }

    @Test func texts() {
        #expect(EditorLocking.hintText == "🔒 Highlighted/touched text is locked. Select it and click 🔓 to unlock.")
        #expect(EditorLocking.lockNeedsSelection.title == "Lock highlighted text")
        #expect(EditorLocking.lockNeedsSelection.text == "Highlight the text you want to protect from editing, then click 🔒.")
        #expect(EditorLocking.unlockNeedsSelection.title == "Unlock highlighted text")
        #expect(EditorLocking.unlockNeedsSelection.text == "Highlight the locked text you want to unlock, then click 🔓.")
        #expect(EditorLocking.isSentinel(EditorLocking.sentinelColor))
        #expect(LockRules.sentinel == ARGB(a: 0xFF, r: 0xFF, g: 0xE6, b: 0x99))
    }
}

@MainActor @Suite struct EditorTableTests {
    private func blocks(_ s: NSAttributedString) -> [NSTextTableBlock] {
        var out: [NSTextTableBlock] = []
        let text = s.string as NSString
        var i = 0
        while i < text.length {
            let pr = text.paragraphRange(for: NSRange(location: i, length: 0))
            if let st = s.attribute(.paragraphStyle, at: i, effectiveRange: nil) as? NSParagraphStyle,
               let b = st.textBlocks.first as? NSTextTableBlock { out.append(b) }
            i = NSMaxRange(pr)
        }
        return out
    }

    // TV: 05 CONT-032 — cells, header row bold, borders 0.6 #9AA0A6, padding 3,1,3,1
    @Test func tableShape() {
        let t = EditorTableBuilder.makeTable(rows: 2, columns: 3, base: EditorFormatting.defaultTypingAttributes())
        #expect(t.string == String(repeating: "\n", count: 6))
        let b = blocks(t)
        #expect(b.count == 6)
        #expect(b[0].table.numberOfColumns == 3)
        #expect(b[0].table.collapsesBorders)
        #expect(b.map(\.startingRow) == [0, 0, 0, 1, 1, 1])
        #expect(b.map(\.startingColumn) == [0, 1, 2, 0, 1, 2])
        #expect(abs(b[0].width(for: .border, edge: .minX) - 0.6) < 0.0001)
        #expect(b[0].width(for: .padding, edge: .minX) == 3 && b[0].width(for: .padding, edge: .minY) == 1)
        #expect(b[0].width(for: .padding, edge: .maxX) == 3 && b[0].width(for: .padding, edge: .maxY) == 1)
        #expect(EditorLocking.isSentinel(b[0].borderColor(for: .minX)) == false)
        #expect(EditorFormatting.isBold(t.attribute(.font, at: 0, effectiveRange: nil) as? NSFont))   // header
        #expect(!EditorFormatting.isBold(t.attribute(.font, at: 3, effectiveRange: nil) as? NSFont))
        #expect(Set(b.map { ObjectIdentifier($0.table) }).count == 1)
    }

    // TV: 05 K-15 — after the caret's paragraph, trailing paragraph when nothing follows, caret in the first cell
    @Test func insertionAfterParagraph() {
        let s = EditorFx.text("first\nsecond\n")
        let e = EditorTableBuilder.insertion(rows: 3, columns: 3, in: s, selection: NSRange(location: 2, length: 0),
                                             base: EditorFormatting.defaultTypingAttributes())
        #expect(e.range == NSRange(location: 6, length: 0))
        #expect(e.replacement.string == String(repeating: "\n", count: 9))   // followed by text: no extra paragraph
        #expect(e.selectionAfter == NSRange(location: 6, length: 0))
    }

    @Test func insertionAtEndAddsBreakAndTrailingParagraph() {
        let s = EditorFx.text("only")
        let e = EditorTableBuilder.insertion(rows: 1, columns: 2, in: s, selection: NSRange(location: 4, length: 0),
                                             base: EditorFormatting.defaultTypingAttributes())
        #expect(e.range == NSRange(location: 4, length: 0))
        #expect(e.replacement.string == "\n" + "\n\n" + "\n")
        #expect(e.selectionAfter == NSRange(location: 5, length: 0))
        let last = e.replacement.attribute(.paragraphStyle, at: e.replacement.length - 1, effectiveRange: nil) as? NSParagraphStyle
        #expect(last?.textBlocks.isEmpty == true)
    }

    @Test func insertionIntoEmptyDocument() {
        let s = NSAttributedString()
        let e = EditorTableBuilder.insertion(rows: 2, columns: 2, in: s, selection: NSRange(location: 0, length: 0),
                                             base: EditorFormatting.defaultTypingAttributes())
        #expect(e.range == NSRange(location: 0, length: 0))
        #expect(e.replacement.string == "\n\n\n\n\n")
        #expect(e.selectionAfter.location == 0)
    }

    @Test func insertionAfterWholeList() {
        let s = EditorFx.text("a\nb\nc\nafter\n")
        let p = NSMutableParagraphStyle()
        p.textLists = [NSTextList(markerFormat: .disc, options: 0)]
        s.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: 6))
        let e = EditorTableBuilder.insertion(rows: 1, columns: 1, in: s, selection: NSRange(location: 2, length: 0),
                                             base: EditorFormatting.defaultTypingAttributes())
        #expect(e.range.location == 6)
    }

    @Test func insertionAfterWholeTable() {
        let s = NSMutableAttributedString(attributedString: EditorFx.text("x\n"))
        s.append(EditorTableBuilder.makeTable(rows: 2, columns: 2, base: EditorFormatting.defaultTypingAttributes()))
        let e = EditorTableBuilder.insertion(rows: 1, columns: 1, in: s, selection: NSRange(location: 3, length: 0),
                                             base: EditorFormatting.defaultTypingAttributes())
        #expect(e.range.location == 6)
        #expect(e.replacement.string == "\n\n")                          // table + trailing paragraph
    }

    @Test func paragraphRanges() {
        let s = EditorFx.text("one\ntwo\nthree")
        #expect(EditorBlocks.paragraphRanges(s, touching: NSRange(location: 1, length: 0)) == [NSRange(location: 0, length: 4)])
        #expect(EditorBlocks.paragraphRanges(s, touching: NSRange(location: 0, length: 4)) == [NSRange(location: 0, length: 4)])
        #expect(EditorBlocks.paragraphRanges(s, touching: NSRange(location: 2, length: 4)).count == 2)
        #expect(EditorBlocks.paragraphRanges(s, touching: NSRange(location: 0, length: 13)).count == 3)
    }
}

@MainActor @Suite struct EditorPasteTests {
    typealias T = NSPasteboard.PasteboardType

    // TV: 05 §6.6 — order: own XAML, file URLs, RTFD, RTF, HTML, plain; image-only clipboards are images
    @Test func preferredKinds() {
        #expect(EditorPaste.preferredKind([.string, .rtf, EditorPaste.xamlType]) == .aaXaml)
        #expect(EditorPaste.preferredKind([.string, .rtf, .html]) == .rtf)
        #expect(EditorPaste.preferredKind([.string, .html]) == .html)
        #expect(EditorPaste.preferredKind([.string]) == .string)
        #expect(EditorPaste.preferredKind([.png, .html]) == .image)               // browser "Copy Image"
        #expect(EditorPaste.preferredKind([.tiff]) == .image)
        #expect(EditorPaste.preferredKind([.fileURL, .string]) == .fileURLs)
        #expect(EditorPaste.preferredKind([.rtfd, .rtf, .string]) == .rtfd)
        #expect(EditorPaste.preferredKind([.png, .string]) == .string)
        #expect(EditorPaste.preferredKind([]) == nil)
    }

    // TV: 05 CONT-034 — CR LF / CR become paragraph breaks
    @Test func plainText() {
        #expect(EditorPaste.plainText("a\r\nb\rc\nd") == "a\nb\nc\nd")
        #expect(EditorPaste.plainText("plain") == "plain")
    }

    @Test func plainPasteUsesDestinationAttributes() {
        var typing = EditorFormatting.defaultTypingAttributes()
        typing[.backgroundColor] = EditorLocking.sentinelColor
        typing[.link] = URL(string: "https://x/")!
        typing[.aaLinkStyled] = true
        typing[.aaUnderlyingForeground] = EditorFormatting.editorInk
        let p = EditorRichSanitiser.plain("x\r\ny", typing: typing)
        #expect(p.string == "x\ny")
        #expect(p.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
        #expect(p.attribute(.link, at: 0, effectiveRange: nil) == nil)
        #expect(p.attribute(.aaFontFamilyName, at: 0, effectiveRange: nil) as? String == "Consolas")
    }

    // TV: 05 §6.6 / DECISIONS 05 — foreign RTF reduced to the storable subset; images extracted for the file bank
    @Test func sanitiseRich() throws {
        let src = NSMutableAttributedString(string: "Hello ", attributes: [
            .font: NSFont(name: "Helvetica-Bold", size: 18)!, .foregroundColor: NSColor.red,
            .shadow: NSShadow(), .kern: 2, .backgroundColor: NSColor.clear])
        let att = NSTextAttachment()
        att.contents = Data([0x89, 0x50, 0x4E, 0x47])
        src.append(NSAttributedString(attachment: att))
        src.append(NSAttributedString(string: "world", attributes: [.underlineStyle: NSUnderlineStyle.double.rawValue]))
        let (clean, images) = EditorRichSanitiser.sanitise(src, base: EditorFormatting.defaultTypingAttributes(),
                                                          now: Date(timeIntervalSince1970: 0))
        #expect(clean.string == "Hello world")
        #expect(images.count == 1)
        #expect(images[0].data == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(images[0].name.hasPrefix("Pasted image "))
        #expect(clean.attribute(.shadow, at: 0, effectiveRange: nil) == nil)
        #expect(clean.attribute(.kern, at: 0, effectiveRange: nil) == nil)
        #expect(clean.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)          // K-13 transparent
        #expect(clean.attribute(.aaFontFamilyName, at: 0, effectiveRange: nil) as? String == "Helvetica")
        #expect(clean.attribute(.underlineStyle, at: 7, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(clean.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor == EditorFormatting.editorInk)
    }

    // TV: 05 §6.4 — pasted TextKit 1 list markers are tagged, never stored as text
    @Test func pastedListMarkersAreTagged() {
        let p = NSMutableParagraphStyle()
        p.textLists = [NSTextList(markerFormat: .disc, options: 0)]
        let s = NSMutableAttributedString(string: "\t•\tOne\n\t•\tTwo\nplain\ttab\n",
                                          attributes: [.font: NSFont.systemFont(ofSize: 12)])
        s.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: 14))
        let (clean, _) = EditorRichSanitiser.sanitise(s, base: EditorFormatting.defaultTypingAttributes())
        #expect(clean.attribute(.aaListMarker, at: 0, effectiveRange: nil) as? Bool == true)
        #expect(clean.attribute(.aaListMarker, at: 2, effectiveRange: nil) as? Bool == true)
        #expect(clean.attribute(.aaListMarker, at: 3, effectiveRange: nil) == nil)
        #expect(clean.attribute(.aaListMarker, at: 7, effectiveRange: nil) as? Bool == true)
        #expect(clean.attribute(.aaListMarker, at: 19, effectiveRange: nil) == nil)          // ordinary tab
    }

    @Test func pastedImageName() {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 2; c.hour = 14; c.minute = 5; c.second = 9
        let d = Calendar(identifier: .gregorian).date(from: c)!
        #expect(EditorPaste.pastedImageName(at: d, ext: "png") == "Pasted image 2026-10-02 14.05.09.png")
    }
}
