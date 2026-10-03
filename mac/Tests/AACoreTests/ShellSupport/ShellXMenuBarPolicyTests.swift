// Spec: 03 §6.8, DECISIONS 03 Q-4 / 02 Q-13 (MenuBarExtra on by default, Settings toggle), REQ-W-SHELL-02 workaround.
import Foundation
import Testing
@testable import AACore

@Suite struct ShellXMenuBarPolicyTests {
    @Test func spuriousOffIsRestoredButAUserChoiceIsKept() {
        // Pre-main "not inserted" pushes wrote off, the user never hid the item → restore.
        #expect(ShellXMenuBarPolicy.shouldRestore(enabled: false, userHidden: false))
        // The user hid it (Settings toggle or ⌘-drag) → keep it hidden.
        #expect(!ShellXMenuBarPolicy.shouldRestore(enabled: false, userHidden: true))
        // Already on → nothing to do.
        #expect(!ShellXMenuBarPolicy.shouldRestore(enabled: true, userHidden: false))
        #expect(!ShellXMenuBarPolicy.shouldRestore(enabled: true, userHidden: true))
    }

    @Test func storeRecordsMainPhaseChanges() {
        let suite = "aa.tests.shellx.menubar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShellXMenuBarGuardStore(prefs: MacPreferences(defaults: defaults))
        #expect(!store.userHidden)                                   // default: never hidden by the user
        store.record(enabled: false)
        #expect(store.userHidden)
        #expect(defaults.bool(forKey: "aa.shellx.menuBarUserHidden"))
        store.record(enabled: true)                                  // turned back on in Settings
        #expect(!store.userHidden)
        #expect(ShellXMenuBarPolicy.userHiddenKey.rawValue.hasPrefix("aa.shellx."))
    }
}
