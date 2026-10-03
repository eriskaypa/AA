// Tests: FIX-F3 (Stage V findings) — 01 §6.5 / DECISIONS 01 DPAPI (safe-mode text names a Windows-encrypted file or a
//        missing Keychain key), 01 DATA-183 (crash.log appended with O_APPEND, one write per block), V-DESIGN rule 3
//        (subtitle path abbreviated), DECISIONS 01 Q-4 (three-field change-password prompt), 03 §6.9 / Q-7 (shared-save
//        help says "every computer").
import Foundation
import Testing
@testable import AACore

@Suite struct ShellLaunchFixTests {
    @Test func safeModeMessageCarriesTheMacParenthetical() {
        #expect(ShellStatusText.safeModeMessage.contains("created under a different user account or on another computer (a file encrypted by AA on Windows can only be opened on that PC — export a bundle there and import it here).\n\nAA opened in READ-ONLY safe mode"))
    }

    @Test func safeModeMessageNamesTheCause() {
        let win = ShellStatusText.safeModeMessage(cause: .windowsEncrypted)
        #expect(win.hasPrefix(DataLoadError.windowsEncrypted.errorDescription! + "\n\n"))
        #expect(win.hasSuffix(ShellStatusText.safeModeMessage))
        let key = ShellStatusText.safeModeMessage(cause: .macKeyUnavailable)
        #expect(key.hasPrefix("The key that encrypts this Mac's data file could not be read from the Keychain.\n\n"))
        #expect(ShellStatusText.safeModeMessage(cause: .unreadable("locked")) == ShellStatusText.safeModeMessage)
        #expect(ShellStatusText.safeModeMessage(cause: nil) == ShellStatusText.safeModeMessage)
        #expect(ShellStatusText.safeModeStatus(cause: nil) == ShellStatusText.safeModeStatus)
        #expect(ShellStatusText.safeModeStatus(cause: .windowsEncrypted).hasPrefix(ShellStatusText.safeModeStatus))
        #expect(ShellStatusText.safeModeStatus(cause: .windowsEncrypted).contains("Windows"))
    }

    @Test func subtitleAbbreviatesPaths() {
        let home = "/Users/mate"
        #expect(ShellStatusText.subtitleDisplay("Loaded — /Users/mate/Library/Application Support/AA/data.json", home: home)
                == "Loaded — ~/Library/Application Support/AA/data.json")
        let long = "Loaded — /tmp/claude-501/-Users-eriskay-erisdev-AA/a38bfcef-845f-48dd-86e4-b31452c20ad6/r/data.json"
        let shown = ShellStatusText.subtitleDisplay(long, home: home)
        #expect(shown.hasPrefix("Loaded — /tmp/"))
        #expect(shown.hasSuffix("/r/data.json"))
        #expect(shown.contains("…"))
        #expect(shown.count - "Loaded — ".count == 60)
        #expect(ShellStatusText.subtitleDisplay("Saved 12:00:01", home: home) == "Saved 12:00:01")
        #expect(ShellStatusText.subtitleDisplay("", home: home) == "")
        #expect(ShellStatusText.subtitleDisplay("/Users/mate", home: home) == "~")
        #expect(ShellStatusText.subtitleDisplay("Loaded — /Users/mateX/a.json", home: home) == "Loaded — /Users/mateX/a.json")
    }

    @Test func changePasswordPromptNamesTheLineBelow() {
        #expect(ShellPasswordMode.changeExisting.prompt == "Enter the new password and confirm it on the line below.")
    }

    @Test func sharedSaveHelpSaysEveryComputer() {
        let rows = ShortcutRegistry.rows.compactMap(\.help).filter { $0.hasPrefix("Use ONE save file") }
        #expect(!rows.isEmpty)
        for h in rows {
            #expect(h.hasSuffix("point every computer at the same file to keep them in sync."))
            #expect(!h.contains("every PC"))
        }
    }

    // 01 DATA-183: blocks appended concurrently are all kept whole.
    @Test func crashLogAppendsAtomically() throws {
        let t = TempFolder("aa-crash-append")
        let url = t.url.appending(path: "crash.log")
        let fallback = t.url.appending(path: "fallback/crash.log")
        let n = 300
        DispatchQueue.concurrentPerform(iterations: n) { i in
            CrashLog.append("entry-\(i)-" + String(repeating: "x", count: 900), appFolder: t.url, fallback: fallback, at: Date())
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let blocks = text.components(separatedBy: "\r\n\r\n").filter { !$0.isEmpty }
        #expect(blocks.count == n)
        #expect(Set(blocks.map { $0.split(separator: " ")[2] }).count == n)
        #expect(!FileManager.default.fileExists(atPath: fallback.path))
    }
}
