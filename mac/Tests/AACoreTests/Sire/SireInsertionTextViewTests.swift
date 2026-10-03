// Tests: 12 SIRE-022/025, §6.4 rules 1–7, §7.12 step 4 (select a word and type X → X before the word; ⌫ / ⌘X do
//        nothing; ⌘Z removes the insertion), 03 T-KB-53 (SIRE body focused, text selected: ⌘⌫ / ⌘X / ⌫ change
//        nothing; ⌘C copies), SHELL-688.
import AppKit
import Foundation
import Testing
@testable import AACore

@MainActor private final class SireUndoHost: NSObject, NSTextViewDelegate {
    let undo = UndoManager()
    func undoManager(for view: NSTextView) -> UndoManager? { undo }
}

@MainActor @Suite struct SireInsertionTextViewTests {
    fileprivate func make(_ text: String = "Check the fire pump") -> (SireInsertionTextView, SireUndoHost) {
        let v = SireInsertionTextView(textKit1Frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let host = SireUndoHost()
        v.delegate = host
        v.sireLoad(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        return (v, host)
    }

    @Test func typingWithASelectionInsertsBeforeIt() {
        let (v, _) = make()
        v.setSelectedRange(NSRange(location: 10, length: 4))          // "fire"
        v.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(v.string == "Check the Xfire pump")
        v.setSelectedRange(NSRange(location: 0, length: 5))
        v.insertText("Y", replacementRange: NSRange(location: 0, length: 5))     // an explicit replacement range too
        #expect(v.string == "YCheck the Xfire pump")
    }

    @Test func newlineAndTabInsertBeforeTheSelection() {
        let (v, _) = make()
        v.setSelectedRange(NSRange(location: 6, length: 3))
        v.insertNewline(nil)
        #expect(v.string == "Check \nthe fire pump")
        v.setSelectedRange(NSRange(location: 0, length: 5))
        v.insertTab(nil)
        #expect(v.string == "\tCheck \nthe fire pump")
    }

    // TV: 03 T-KB-53
    @Test func deletionCommandsAreBlocked() {
        let (v, _) = make()
        v.setSelectedRange(NSRange(location: 6, length: 3))
        for action in [v.deleteBackward, v.deleteForward, v.deleteWordBackward, v.deleteWordForward,
                       v.deleteToBeginningOfLine, v.deleteToEndOfLine, v.deleteToBeginningOfParagraph,
                       v.deleteToEndOfParagraph, v.deleteBackwardByDecomposingPreviousCharacter, v.cut, v.delete,
                       v.transpose, v.transposeWords, v.capitalizeWord, v.uppercaseWord, v.lowercaseWord, v.yank,
                       v.deleteToMark] as [@MainActor (Any?) -> Void] {
            action(nil)
        }
        #expect(v.string == "Check the fire pump")
        v.setSelectedRange(NSRange(location: 5, length: 0))
        v.deleteBackward(nil); v.deleteForward(nil)
        #expect(v.string == "Check the fire pump")
    }

    @Test func gateRefusesChangesToExistingText() {
        let (v, _) = make()
        #expect(!v.shouldChangeText(in: NSRange(location: 0, length: 1), replacementString: ""))
        #expect(!v.shouldChangeText(in: NSRange(location: 0, length: 5), replacementString: nil))   // attribute change
        #expect(v.shouldChangeText(in: NSRange(location: 3, length: 0), replacementString: "x"))
        #expect(!v.shouldChangeText(inRanges: [NSValue(range: NSRange(location: 0, length: 0)),
                                               NSValue(range: NSRange(location: 2, length: 2))], replacementStrings: nil))
        v.setSelectedRange(NSRange(location: 0, length: 5))
        v.underline(nil)                                                  // formatting over a selection is refused
        #expect(v.textStorage?.attribute(.underlineStyle, at: 1, effectiveRange: nil) == nil)
        v.alignCenter(nil)
        let style = v.textStorage?.attribute(.paragraphStyle, at: 1, effectiveRange: nil) as? NSParagraphStyle
        #expect(style == nil || style?.alignment != .center)
    }

    @Test func undoRemovesOwnInsertions() {
        let (v, host) = make()
        v.setSelectedRange(NSRange(location: 10, length: 4))
        v.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        v.breakUndoCoalescing()
        #expect(v.string == "Check the Xfire pump")
        #expect(host.undo.canUndo)
        host.undo.undo()
        #expect(v.string == "Check the fire pump")
        host.undo.redo()
        #expect(v.string == "Check the Xfire pump")
    }

    @Test func loadingIsNotUndoable() {
        let (v, host) = make()
        v.sireLoad(NSAttributedString(string: "Other body"))
        #expect(!host.undo.canUndo)
        #expect(v.string == "Other body" && v.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test func contextMenuAndValidation() {
        let (v, _) = make()
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let menu = v.menu(for: event)
        #expect(menu?.items.map(\.title) == ["Copy", "Paste (insert)", "Select All"])
        v.setSelectedRange(NSRange(location: 0, length: 5))
        #expect(!v.validateUserInterfaceItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")))
        #expect(!v.validateUserInterfaceItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")))
        let replace = NSMenuItem(title: "Replace", action: #selector(NSTextView.performTextFinderAction(_:)), keyEquivalent: "")
        replace.tag = NSTextFinder.Action.replaceAll.rawValue
        #expect(!v.validateUserInterfaceItem(replace))
        #expect(v.acceptableDragTypes.isEmpty)
        #expect(v.validRequestor(forSendType: .string, returnType: .string) == nil)
    }

    @Test func copyStillWorks() {
        let (v, _) = make()
        v.setSelectedRange(NSRange(location: 0, length: 5))
        #expect(v.validateUserInterfaceItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")))
        #expect(v.validateUserInterfaceItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")))
        #expect(v.attributedSubstring(forProposedRange: v.selectedRange(), actualRange: nil)?.string == "Check")
        #expect(!v.writablePasteboardTypes.isEmpty)
    }

    @Test func noRewritingServices() {
        let (v, _) = make()
        #expect(!v.isAutomaticSpellingCorrectionEnabled && !v.isAutomaticQuoteSubstitutionEnabled)
        #expect(!v.isAutomaticDashSubstitutionEnabled && !v.isAutomaticTextReplacementEnabled)
        #expect(!v.isAutomaticTextCompletionEnabled && !v.smartInsertDeleteEnabled)
        #expect(v.writingToolsBehavior == NSWritingToolsBehavior.none)
        #expect(v.usesFindBar && !v.usesInspectorBar && !v.usesFontPanel && !v.importsGraphics)
        #expect(v.layoutManager != nil)                                   // TextKit 1
    }

    @Test func pasteSanitisesAndInsertsAtTheSelectionStart() throws {
        let (v, _) = make()
        let pb = NSPasteboard(name: NSPasteboard.Name("aa-sire-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let rich = NSMutableAttributedString(string: "Note ")
        let att = NSTextAttachment(data: Data([0x89, 0x50]), ofType: "public.png")
        rich.append(NSAttributedString(attachment: att))
        rich.append(NSAttributedString(string: "end"))
        pb.clearContents()
        let rtfd = try #require(rich.rtfd(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]))
        pb.setData(rtfd, forType: .rtfd)
        pb.setString("plain text", forType: .string)
        let content = try #require(v.sirePasteContent(from: pb, rich: true))
        #expect(content.string == "Note end")
        #expect(v.sirePasteContent(from: pb, rich: false)?.string == "plain text")
        #expect(SireInsertionTextView.strippingAttachments(rich).string == "Note end")
    }
}
