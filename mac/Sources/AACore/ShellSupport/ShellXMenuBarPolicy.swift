// Spec: 03 §6.8 (MenuBarExtra always present while AA runs), DECISIONS 03 Q-4 / 02 Q-13 (on by default, a toggle in
//       Settings ▸ General); REQ-W-SHELL-02 (resolved in F3's scene binding: a "not inserted" push while the item is
//       not meant to be shown no longer persists "off"; this file keeps the one-time repair of a preference that
//       earlier builds wrote); ARCHITECTURE.md §9.3, §12.2 (`aa.<area>.*` preference keys).
import Foundation

/// The one-time repair of `aa.menuBarExtra = false` written by builds before the binding fix.
public enum ShellXMenuBarPolicy {
    /// Per-Mac record (kept by the earlier guard) that the user hid the item on purpose.
    public static let userHiddenKey = MacPreferences.Key("aa.shellx.menuBarUserHidden")
    /// Set once the repair ran on this Mac.
    public static let repairedKey = MacPreferences.Key("aa.shellx.menuBarRepaired")

    /// Whether the stored `aa.menuBarExtra = false` must be turned back on.
    public static func shouldRestore(enabled: Bool, userHidden: Bool) -> Bool {
        !enabled && !userHidden
    }
}

/// The `MacPreferences` side of the repair.
public struct ShellXMenuBarGuardStore: Sendable {
    private let prefs: MacPreferences

    public init(prefs: MacPreferences = .shared) { self.prefs = prefs }

    public var userHidden: Bool { prefs.bool(ShellXMenuBarPolicy.userHiddenKey, default: false) }
    public var repaired: Bool { prefs.bool(ShellXMenuBarPolicy.repairedKey, default: false) }

    public func markRepaired() { prefs.set(true, ShellXMenuBarPolicy.repairedKey) }
}
