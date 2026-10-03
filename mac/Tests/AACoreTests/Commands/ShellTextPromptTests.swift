// Tests: 06 Addendum §Add.7 TV-PR-01…11 (the shared text prompt: OK always enabled, raw value, fire-once, cancel paths,
//        line-break cut, select-all on open, no substitutions, secure field, wrapped label at ≥ 440 pt), §Add.6
//        (ScriptedPrompter records every request); 03 SHELL-505 G2 with the quick switcher key (FIX-F3, V-03).
import AppKit
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct ShellTextPromptTests {
    final class Box { var results: [TextPromptResult] = [] }

    func session(_ initial: String = "", secure: Bool = false) -> (TextPromptSession, Box) {
        let box = Box()
        let s = TextPromptSession(request: TextPromptRequest(title: "New Task", prompt: "Name:", initial: initial,
                                                             isSecure: secure)) { box.results.append($0) }
        return (s, box)
    }

    // TV: TV-PR-01 — initial ""; OK at once → enabled, .ok("")
    @Test func tvpr01() {
        let (s, box) = session()
        #expect(s.canSubmit)
        s.ok()
        #expect(box.results == [.ok("")])
    }

    // TV: TV-PR-02 — "Deck"; clear; Return → .ok(""), finish exactly once
    @Test func tvpr02() {
        let (s, box) = session("Deck")
        #expect(s.text == "Deck")
        s.setText("")
        s.ok(); s.ok(); s.cancel()
        #expect(box.results == [.ok("")])
        #expect(s.result == .ok(""))
    }

    // TV: TV-PR-03 / 04 / 05 — whitespace, padded and NBSP values come back raw, OK enabled
    @Test func tvpr03to05() {
        for raw in ["   ", "  Pump 1  ", "\u{00A0}"] {
            let (s, box) = session()
            s.setText(raw)
            #expect(s.canSubmit)
            s.ok()
            #expect(box.results == [.ok(raw)])
        }
    }

    // TV: TV-PR-06 — Esc / ⌘. / Cancel / parent window closes → .cancelled
    @Test func tvpr06() {
        #expect(ShellRawFieldEditing.command(for: #selector(NSResponder.cancelOperation(_:))) == .cancel)   // Esc, ⌘.
        #expect(ShellRawFieldEditing.command(for: #selector(NSResponder.insertNewline(_:))) == .submit)
        #expect(ShellRawFieldEditing.command(for: #selector(NSResponder.insertTab(_:))) == .none)
        for _ in 0..<2 {                                    // the Cancel button, and the sheet's onDisappear
            let (s, box) = session("x")
            s.cancel(); s.ok()
            #expect(box.results == [.cancelled])
        }
        let field = NSTextField()
        var cancelled = 0
        let d = ShellRawFieldDelegate(onChange: { _ in }, onSubmit: { _ in }, onCancel: { cancelled += 1 })
        #expect(d.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(cancelled == 1)
    }

    // TV: TV-PR-07 — pasting "Line 1\nLine 2" keeps "Line 1"
    @Test func tvpr07() {
        let (s, box) = session()
        #expect(s.setText("Line 1\nLine 2") == "Line 1")
        #expect(s.text == "Line 1")
        s.ok()
        #expect(box.results == [.ok("Line 1")])
        for sep in ["\r", "\r\n", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"] {
            #expect(ShellPromptText.singleLine("a\(sep)b") == "a")
        }
        // The field delegate cuts the control's own value too.
        let field = NSTextField(string: "Line 1\nLine 2")
        var changed: [String] = []
        let d = ShellRawFieldDelegate(onChange: { changed.append($0) }, onSubmit: { _ in }, onCancel: {})
        d.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(field.stringValue == "Line 1")
        #expect(changed == ["Line 1"])
        var submitted: [String] = []
        let d2 = ShellRawFieldDelegate(onChange: { _ in }, onSubmit: { submitted.append($0) }, onCancel: {})
        field.stringValue = "A\nB"
        #expect(d2.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(submitted == ["A"])
    }

    // TV: TV-PR-08 — "https://" is fully selected, so typing "x" replaces it
    @Test func tvpr08() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 80), styleMask: [.titled],
                              backing: .buffered, defer: true)
        let field = NSTextField(string: "https://")
        field.frame = NSRect(x: 10, y: 10, width: 400, height: 22)
        window.contentView?.addSubview(field)
        #expect(window.makeFirstResponder(field))
        guard let editor = field.currentEditor() as? NSTextView else {
            Issue.record("no field editor")
            return
        }
        editor.selectAll(nil)
        editor.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.string == "x")
        let (s, box) = session("https://")
        s.setText(editor.string)
        s.ok()
        #expect(box.results == [.ok("x")])
    }

    // TV: TV-PR-09 — smart quotes / dashes / replacement / autocorrect are off in the field editor
    @Test func tvpr09() {
        let tv = NSTextView()
        tv.isAutomaticQuoteSubstitutionEnabled = true
        tv.isAutomaticDashSubstitutionEnabled = true
        tv.isAutomaticTextReplacementEnabled = true
        tv.isAutomaticSpellingCorrectionEnabled = true
        ShellRawFieldEditing.configure(tv)
        #expect(!tv.isAutomaticQuoteSubstitutionEnabled && !tv.isAutomaticDashSubstitutionEnabled)
        #expect(!tv.isAutomaticTextReplacementEnabled && !tv.isAutomaticSpellingCorrectionEnabled)
        #expect(!tv.isAutomaticLinkDetectionEnabled && !tv.isAutomaticDataDetectionEnabled && !tv.smartInsertDeleteEnabled)
        tv.insertText("it's -- \"ok\"", replacementRange: NSRange(location: 0, length: 0))
        let (s, box) = session()
        s.setText(tv.string)
        s.ok()
        #expect(box.results == [.ok("it's -- \"ok\"")])
    }

    // TV: TV-PR-10 — secure, "AIzaOld", cleared, OK → .ok("")
    @Test func tvpr10() {
        let (s, box) = session("AIzaOld", secure: true)
        #expect(s.request.isSecure)
        s.setText("")
        #expect(s.canSubmit)
        s.ok()
        #expect(box.results == [.ok("")])
    }

    // TV: TV-PR-11 — the sheet is at least 440 pt wide (its label wraps, BUILD-141)
    @Test func tvpr11() {
        #expect(TextPromptLayout.minWidth >= 440)
    }

    // §Add.6: ScriptedPrompter returns its results in order and records every request
    @Test func scriptedPrompter() async {
        let p = ScriptedPrompter(results: [.ok("  X  "), .cancelled])
        let r1 = TextPromptRequest(title: "New group", prompt: "Name:")
        let r2 = TextPromptRequest(title: "Web link", prompt: "URL:", initial: "https://")
        #expect(await p.prompt(r1) == .ok("  X  "))
        #expect(await p.prompt(r2) == .cancelled)
        #expect(await p.prompt(r1) == .cancelled)
        #expect(p.requests == [r1, r2, r1])
    }

    // SHELL-505 G2: while the quick switcher is key, APP / MAIN commands are disabled; ⌘W and Quit stay available.
    @Test func switcherKeyDisablesAppAndMainCommands() {
        var c = CommandContext()
        c.section = .tasks
        c.keyWin = .switcher
        for cmd in [CommandID.save, .quickWork, .dueDates, .searchAll, .reloadFromDisk] {
            #expect(!CommandRouterCore.state(cmd, c).enabled, "\(cmd)")
        }
        #expect(CommandRouterCore.state(.quit, c).enabled)
        var main = c
        main.keyWin = .main
        #expect(CommandRouterCore.state(.save, main).enabled)
    }
}
