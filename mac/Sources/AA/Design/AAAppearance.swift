// Spec: 03 SHELL-002 (appearance before any window), SHELL-110/151/152 (live switching), §6.6.2, W-11 (re-apply after
//       every reload), DECISIONS 03 Q-2 (System / Light / Dark per device; Light/Dark write DarkMode; System leaves it),
//       "Appearance defaults to System on first launch unless settings.json says DarkMode: true", SHELL-638 (the ✓
//       follows a macOS light/dark switch while Appearance = System); ARCHITECTURE.md §8.1.
import AppKit
import AACore

/// Per-device appearance choice (UserDefaults `aa.appearance`).
enum AppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

extension MacPreferences.Key {
    /// Documented raw value kept verbatim (ARCH §6.1 note).
    static let shellAppearance = MacPreferences.Key("aa.appearance")
}

@MainActor
enum ShellAppearance {
    /// Debug snapshots force an appearance without touching preferences or settings.
    static var forcedForSnapshot: AppearanceMode?

    /// The stored mode; on first launch `.dark` when settings.json says `DarkMode: true`, else `.system`.
    static func storedMode(settings: SettingsStore, prefs: MacPreferences = .shared) -> AppearanceMode {
        if let forced = forcedForSnapshot { return forced }
        if let raw = prefs.string(.shellAppearance), let m = AppearanceMode(rawValue: raw) { return m }
        return settings.values.darkMode ? .dark : .system
    }

    /// Applies the stored mode; after a reload the synced `DarkMode` wins over a stale Light/Dark choice (W-11).
    static func apply(settings: SettingsStore, prefs: MacPreferences = .shared) {
        var mode = storedMode(settings: settings, prefs: prefs)
        if forcedForSnapshot == nil, mode != .system {
            let synced: AppearanceMode = settings.values.darkMode ? .dark : .light
            if synced != mode {
                mode = synced
                prefs.set(mode.rawValue, .shellAppearance)
            }
        }
        NSApp.appearance = mode.nsAppearance
    }

    /// Settings ▸ General picker: Light/Dark also write `DarkMode`; System leaves it untouched.
    static func set(_ mode: AppearanceMode, settings: SettingsStore, prefs: MacPreferences = .shared) {
        prefs.set(mode.rawValue, .shellAppearance)
        switch mode {
        case .light: if settings.values.darkMode { settings.setDarkMode(false) }
        case .dark: if !settings.values.darkMode { settings.setDarkMode(true) }
        case .system: break
        }
        NSApp.appearance = mode.nsAppearance
    }

    /// True when the app currently renders dark.
    static var isEffectivelyDark: Bool {
        (NSApp.appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    nonisolated(unsafe) private static var effectiveObservation: NSKeyValueObservation?

    /// SHELL-638 / W-11: with Appearance = System, macOS can switch light/dark under a running app (Auto appearance at
    /// sunset); the View ▸ Dark Mode ✓ and anything else derived from `isEffectivelyDark` follow it through `onChange`.
    static func observeEffectiveAppearance(_ onChange: @escaping @MainActor () -> Void) {
        effectiveObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { onChange() }
            } else {
                DispatchQueue.main.async { onChange() }
            }
        }
    }

    /// View ▸ Dark Mode ✓ toggles Light ⇄ Dark (SHELL-110/638); returns the status text.
    @discardableResult
    static func toggleDarkMode(settings: SettingsStore, prefs: MacPreferences = .shared) -> String {
        let turnOn = !isEffectivelyDark
        set(turnOn ? .dark : .light, settings: settings, prefs: prefs)
        return turnOn ? ShellStatusText.darkModeOn : ShellStatusText.darkModeOff
    }
}

/// SF Symbols that replace WPF emoji used as icons (§8.5). Emoji that are user data keep their characters.
enum AASymbol {
    static let lock = "lock", lockFill = "lock.fill", unlock = "lock.open", delete = "trash"
    static let markDone = "checkmark.circle", notDone = "circle", setDeadline = "calendar.badge.clock"
    static let builder = "hammer", restore = "arrow.uturn.backward", saveAsList = "square.and.arrow.down"
    static let loadList = "list.clipboard", export = "square.and.arrow.up", importFile = "square.and.arrow.down.on.square"
    static let pdf = "doc.richtext", edit = "pencil", schedule = "calendar", insertSavedList = "list.bullet.indent"
    static let due = "pin", darkMode = "moon", shortcutBar = "keyboard", tabColors = "paintpalette", link = "link"
    static let webLink = "globe", folder = "folder", bucket = "tray.2", notifyOn = "bell.fill", notifyOff = "bell.slash"
    static let warning = "exclamationmark.triangle.fill", table = "tablecells", moveUp = "arrow.up.to.line"
    static let moveDown = "arrow.down.to.line", undo = "arrow.uturn.backward", redo = "arrow.uturn.forward"
    static let search = "magnifyingglass", portsHeader = "ferry", flashSync = "qrcode"
}
