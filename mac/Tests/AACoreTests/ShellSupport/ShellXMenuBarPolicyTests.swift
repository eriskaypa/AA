// Spec: 03 §6.8, DECISIONS 03 Q-4 / 02 Q-13 (MenuBarExtra on by default, Settings toggle), REQ-W-SHELL-02 (one-time
//       repair of a preference written by builds before the scene-binding fix).
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

    @Test func repairRunsOnce() {
        let suite = "aa.tests.shellx.menubar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShellXMenuBarGuardStore(prefs: MacPreferences(defaults: defaults))
        #expect(!store.userHidden && !store.repaired)                // defaults
        defaults.set(true, forKey: "aa.shellx.menuBarUserHidden")
        #expect(store.userHidden)
        store.markRepaired()
        #expect(store.repaired)
        #expect(defaults.bool(forKey: "aa.shellx.menuBarRepaired"))
        #expect(ShellXMenuBarPolicy.repairedKey.rawValue.hasPrefix("aa.shellx."))
    }
}
