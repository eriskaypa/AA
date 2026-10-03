// Spec: 03 SHELL-004 (the login gate: Exit at login writes nothing), §6.1 (everything data-bound stays disabled until
//       the main phase), §6.4 (Settings scene), DEVIATIONS SHELL-506 (AA ▸ Settings… stays enabled during login);
//       Stage V round 2 finding V2-J8 (Settings ▸ General wrote settings.json before sign-in).
import Foundation

/// Which Settings ▸ General controls work before sign-in. The Settings window opens during the login phase
/// (SHELL-506), so every control that writes `settings.json` or reaches into the data folder waits for the main
/// phase; only Mac-level preferences (the menu-bar item, System Settings ▸ Notifications) work at login.
public enum ShellXSettingsGate {
    public enum GeneralControl: String, CaseIterable, Sendable {
        /// Name field, Use Mac Name and the focus-loss commit (writes `AppIdentity`).
        case appIdentity
        /// System / Light / Dark (Light and Dark write `DarkMode`).
        case appearance
        /// Show the keyboard shortcut bar (writes `Ui.ShowShortcutBar` in the data file).
        case shortcutBar
        /// Data Folder ▸ Show in Finder.
        case showDataFolder
        /// Show AA in the menu bar (a Mac preference only).
        case menuBarExtra
        /// Notification Settings… (opens System Settings).
        case notificationSettings
    }

    /// True when `control` may be used; `mainLoaded` is false during splash and login.
    public static func isEnabled(_ control: GeneralControl, mainLoaded: Bool) -> Bool {
        switch control {
        case .menuBarExtra, .notificationSettings: return true
        case .appIdentity, .appearance, .shortcutBar, .showDataFolder: return mainLoaded
        }
    }

    /// The notice shown above data-bound settings before sign-in.
    public static let signInNotice = "Sign in to AA to change these settings."
}
