// Spec: 01 MP.6.2 (scenes stay suppressed until the launch coordinator opens them), 03 SHELL-526 (Window-menu
//       exclusions, no window tabbing), DECISIONS 08 OQ-3 (single Search / Activity-log windows); ARCHITECTURE.md §7.1
//       (bootstrap scene + SceneOpener: the only way non-view code opens, dismisses or finds scenes).
import AppKit
import SwiftUI
import AACore

/// Opens scenes from outside a view (the bootstrap view captured the SwiftUI actions) and keeps the registry of AA
/// windows (role, dialog presenter, sheet kind) that the router, the quit pipeline and the snapshot hook use.
@MainActor
final class SceneOpener {
    static let shared = SceneOpener()

    private(set) var ready = false
    private var openWindowAction: OpenWindowAction?
    private var dismissWindowAction: DismissWindowAction?
    private var openSettingsAction: OpenSettingsAction?
    private var pending: [@MainActor () -> Void] = []

    private struct Entry {
        weak var window: NSWindow?
        var role: KeyWindowRole
        weak var dialogs: DialogPresenter?
    }

    private struct SheetEntry {
        weak var window: NSWindow?
        var kind: SheetKind
        var role: KeyWindowRole?
        var explicit: Bool
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var sheets: [ObjectIdentifier: SheetEntry] = [:]
    private var willCloseObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    /// Presenters of panels that are not SwiftUI scenes (kept alive here).
    private var panelPresenters: [ObjectIdentifier: DialogPresenter] = [:]

    /// Called once by `BootstrapView`.
    func install(open: OpenWindowAction, dismiss: DismissWindowAction, openSettings: OpenSettingsAction) {
        openWindowAction = open
        dismissWindowAction = dismiss
        openSettingsAction = openSettings
        guard !ready else { return }
        ready = true
        let queued = pending
        pending.removeAll()
        for body in queued { body() }
    }

    func whenReady(_ body: @escaping @MainActor () -> Void) {
        if ready { body() } else { pending.append(body) }
    }

    // MARK: Opening

    func open(_ id: SceneID) {
        guard ready else { whenReady { [weak self] in self?.open(id) }; return }
        switch id {
        case .settings:
            openSettings()
        case .due:
            if let env = LaunchCoordinator.shared.env { DueDatesPanelController.shared.show(env: env) }
        case .switcher:
            if let env = LaunchCoordinator.shared.env { QuickSwitcherPanelController.shared.show(env: env) }
        case .bootstrap, .item, .unitConverter:
            if id == .unitConverter { open(.unitConverter, value: UUID()) }
        default:
            if let w = window(for: id), w.isVisible || w.isMiniaturized {
                if w.isMiniaturized { w.deminiaturize(nil) }
                w.makeKeyAndOrderFront(nil)
                NSApp.activate()
            } else {
                openWindowAction?(id: id.rawValue)
            }
        }
    }

    func open<V: Codable & Hashable>(_ id: SceneID, value: V) {
        guard ready else { whenReady { [weak self] in self?.open(id, value: value) }; return }
        openWindowAction?(id: id.rawValue, value: value)
    }

    func dismiss(_ id: SceneID) {
        guard ready else { return }
        dismissWindowAction?(id: id.rawValue)
    }

    func openSettings() {
        guard ready else { whenReady { [weak self] in self?.openSettings() }; return }
        NSApp.activate()
        openSettingsAction?()
    }

    // MARK: Registry

    /// Registers an AA window (from `.aaWindowRoot`): role, presenter, Window-menu and restoration rules.
    func register(window: NSWindow, role: KeyWindowRole, dialogs: DialogPresenter) {
        let key = ObjectIdentifier(window)
        entries[key] = Entry(window: window, role: role, dialogs: dialogs)
        window.isRestorable = false
        switch role {
        case .splash, .login, .due, .switcher: window.isExcludedFromWindowsMenu = true
        default: break
        }
        if willCloseObservers[key] == nil {
            willCloseObservers[key] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowWillClose(key) }
            }
        }
        if role == .main { LaunchCoordinator.shared.mainWindowRegistered(window) }
        if role == .login { LaunchCoordinator.shared.loginWindowRegistered(window) }
    }

    func registerSheet(window: NSWindow, kind: SheetKind, role: KeyWindowRole?, explicit: Bool) {
        let key = ObjectIdentifier(window)
        if let existing = sheets[key], existing.explicit, !explicit { return }
        sheets[key] = SheetEntry(window: window, kind: kind, role: role ?? sheets[key]?.role, explicit: explicit)
    }

    private func windowWillClose(_ key: ObjectIdentifier) {
        let role = entries[key]?.role
        entries[key] = nil
        sheets[key] = nil
        if let o = willCloseObservers.removeValue(forKey: key) { NotificationCenter.default.removeObserver(o) }
        if role == .login { LaunchCoordinator.shared.loginWindowWillClose() }
    }

    func role(of window: NSWindow) -> KeyWindowRole? { entries[ObjectIdentifier(window)]?.role }

    func sheetInfo(of window: NSWindow) -> (kind: SheetKind, role: KeyWindowRole?)? {
        sheets[ObjectIdentifier(window)].map { ($0.kind, $0.role) }
    }

    /// The window of a scene (first live match). Panels `due` / `switcher` register themselves the same way.
    func window(for id: SceneID) -> NSWindow? {
        entries.values.first { $0.window != nil && $0.role.sceneID == id }?.window
    }

    func windows(for id: SceneID) -> [NSWindow] {
        entries.values.filter { $0.role.sceneID == id }.compactMap(\.window)
    }

    /// The window showing item `id` (item scene), if open.
    func itemWindow(_ id: UUID) -> NSWindow? {
        entries.values.first { $0.role == .item(id) }?.window
    }

    func dialogs(for id: SceneID) -> DialogPresenter? {
        entries.values.first { $0.window != nil && $0.role.sceneID == id }?.dialogs
    }

    func dialogs(forItem id: UUID) -> DialogPresenter? {
        entries.values.first { $0.role == .item(id) }?.dialogs
    }

    /// The presenter of a given window.
    func dialogs(of window: NSWindow) -> DialogPresenter? { entries[ObjectIdentifier(window)]?.dialogs }

    /// Every registered item window (quit pipeline: flush and close them first).
    var itemWindows: [NSWindow] {
        entries.values.compactMap { e -> NSWindow? in
            if case .item = e.role { return e.window }
            return nil
        }
    }

    /// Registers a panel that is not a SwiftUI scene (`due`, `switcher` controllers).
    func registerPanel(_ panel: NSWindow, as id: SceneID) {
        let role: KeyWindowRole = id == .due ? .due : (id == .switcher ? .switcher : .other)
        let presenter = DialogPresenter()
        presenter.window = panel
        panelPresenters[ObjectIdentifier(panel)] = presenter
        register(window: panel, role: role, dialogs: presenter)
    }
}

/// The 1×1, invisible, always-present helper scene's content (ARCHITECTURE.md §7.1).
struct BootstrapView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .background(ShellWindowCapture { window in
                window.orderOut(nil)
                window.ignoresMouseEvents = true
                window.isExcludedFromWindowsMenu = true
                window.isRestorable = false
                window.collectionBehavior = [.transient, .ignoresCycle]
                window.alphaValue = 0
            })
            .onAppear {
                SceneOpener.shared.install(open: openWindow, dismiss: dismissWindow, openSettings: openSettings)
                LaunchCoordinator.shared.bootstrapReady()
            }
    }
}
