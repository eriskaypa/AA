// Spec: 03 §6.8 (MenuBarExtra always present while AA runs), DECISIONS 03 Q-4 / 02 Q-13 (on by default, a toggle in
//       Settings ▸ General); REQ-W-SHELL-02 (the scene binding can persist "off" while the item is not meant to be
//       shown — splash, login, snapshot and smoke runs — so the item would never appear again); ARCHITECTURE.md §9.3,
//       §12.2 (`aa.<area>.*` preference keys), §12.3 (local workaround).
import Foundation

/// Tells a deliberate "hide the menu-bar item" apart from the spurious `false` the MenuBarExtra binding writes while
/// the item is not shown. Only a change made while AA runs in the main phase (Settings ▸ General toggle, or ⌘-dragging
/// the item out of the menu bar) is the user's; everything else is undone when the reminders start.
public enum ShellXMenuBarPolicy {
    /// Per-Mac record that the user hid the item on purpose (`MacPreferences`, never in data or settings files).
    public static let userHiddenKey = MacPreferences.Key("aa.shellx.menuBarUserHidden")

    /// At the start of the main phase: whether the stored `aa.menuBarExtra = false` must be turned back on.
    public static func shouldRestore(enabled: Bool, userHidden: Bool) -> Bool {
        !enabled && !userHidden
    }

    /// A change of `aa.menuBarExtra` observed while the reminders run (main phase, not a snapshot or smoke run):
    /// the new value of the "hidden by the user" record.
    public static func userHidden(afterChangeTo enabled: Bool) -> Bool { !enabled }
}

/// The `MacPreferences` side of the policy.
public struct ShellXMenuBarGuardStore: Sendable {
    private let prefs: MacPreferences

    public init(prefs: MacPreferences = .shared) { self.prefs = prefs }

    public var userHidden: Bool { prefs.bool(ShellXMenuBarPolicy.userHiddenKey, default: false) }

    public func record(enabled: Bool) {
        prefs.set(ShellXMenuBarPolicy.userHidden(afterChangeTo: enabled), ShellXMenuBarPolicy.userHiddenKey)
    }
}
