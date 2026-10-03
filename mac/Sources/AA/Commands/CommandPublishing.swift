// Spec: 03 §6.5.1.10 (ListCommands, list roles, section inputs, filter targets), SHELL-516…520, SHELL-670 (⌫ only where
//       Windows confirms); ARCHITECTURE.md §7.6 ("How views publish context" — the only integration points for wave
//       agents).
import AppKit
import SwiftUI
import AACore

enum ListRole: String {
    case hierarchySidebar, sectionList, crewRoster, boardColumn, calendarTable, builderItems, savedLists, buckets,
         bucketMembers, fileBank, viewerFiles, workOrders, portsOfCall, quickCards, relationships, components,
         subtasks, steps, quickWorkList, quickWorkChildren, crewChecklist, crewSchedule, crewTableColumns, trashTable,
         searchResults, switcherResults, other
}

enum MoveDirection { case up, down }

/// What a focused List / Table publishes (03 §6.5.1.10 ListCommands).
struct ListCommands {
    var role: ListRole
    var selectionCount: Int
    var deleteTitle: String? = nil
    var delete: (() -> Void)? = nil
    var deleteConfirms = true
    var canMoveUp = false
    var canMoveDown = false
    var move: ((MoveDirection) -> Void)? = nil
    var moveTo: (() -> Void)? = nil
    var quickLook: (() -> Void)? = nil
    var primary: (() -> Void)? = nil

    /// The value part the router's decision table reads.
    var state: ShellListState {
        ShellListState(role: role.rawValue, selectionCount: selectionCount, deleteTitle: deleteTitle,
                       hasDelete: delete != nil, canMoveUp: canMoveUp, canMoveDown: canMoveDown, hasMove: move != nil,
                       hasMoveTo: moveTo != nil, hasQuickLook: quickLook != nil, hasPrimary: primary != nil)
    }
}

struct HierarchySelectionState: Equatable { var primary: UUID?; var count: Int; var gated: Bool; var detached: Bool }

struct VesselMenuActions {
    var importWorkOrders, exportWorkOrders, importPorts, exportPorts, newQuickCard: () -> Void
}

/// What each section root publishes (03 §6.5.1.10 section inputs).
struct SectionCommands {
    var newItemTitle: String? = nil
    var newItem: (() -> Void)? = nil
    var rename: (() -> Void)? = nil
    var openInNewWindow: (() -> Void)? = nil
    var hierarchySelection: HierarchySelectionState? = nil
    var plannerPrevious: (() -> Void)? = nil
    var plannerToday: (() -> Void)? = nil
    var plannerNext: (() -> Void)? = nil
    var calendarFontScale: Double? = nil
    var setCalendarFontScale: ((Double) -> Void)? = nil
    var focusSearchField: (() -> Void)? = nil
    var searchFieldIsFocused = false
    var vessel: VesselMenuActions? = nil

    /// Equatable summary (the observed part; closures live outside observation).
    var summary: ShellSectionSummary {
        ShellSectionSummary(hasNewItem: newItem != nil, newItemTitle: newItemTitle, hasRename: rename != nil,
                            hasOpenInNewWindow: openInNewWindow != nil, hierarchySelection: hierarchySelection,
                            hasPlanner: plannerToday != nil || plannerPrevious != nil || plannerNext != nil,
                            calendarFontScale: calendarFontScale, canSetCalendarFontScale: setCalendarFontScale != nil,
                            hasSearchField: focusSearchField != nil, searchFieldIsFocused: searchFieldIsFocused,
                            hasVessel: vessel != nil)
    }
}

struct ShellSectionSummary: Equatable {
    var hasNewItem: Bool
    var newItemTitle: String?
    var hasRename: Bool
    var hasOpenInNewWindow: Bool
    var hierarchySelection: HierarchySelectionState?
    var hasPlanner: Bool
    var calendarFontScale: Double?
    var canSetCalendarFontScale: Bool
    var hasSearchField: Bool
    var searchFieldIsFocused: Bool
    var hasVessel: Bool
}

/// The key window as published by `.aaWindowRoot(role)`.
enum KeyWindowRole: Hashable {
    case main, item(UUID), search, quickWork, due, switcher, activityLog, unitConverter, dateCalc, folderBuilder,
         crewTable, viewer, flashSync, settings, shortcuts, about, login, splash, other

    var shell: ShellKeyWindow {
        switch self {
        case .main: return .main
        case .item(let id): return .item(id)
        case .search: return .search
        case .quickWork: return .quickWork
        case .due: return .due
        case .switcher: return .switcher
        case .activityLog: return .activityLog
        case .unitConverter: return .unitConverter
        case .dateCalc: return .dateCalc
        case .folderBuilder: return .folderBuilder
        case .crewTable: return .crewTable
        case .viewer: return .viewer
        case .flashSync: return .flashSync
        case .settings: return .settings
        case .shortcuts: return .shortcuts
        case .about: return .about
        case .login: return .login
        case .splash: return .splash
        case .other: return .other
        }
    }

    /// The scene id a window of this role belongs to (for `SceneOpener.window(for:)`).
    var sceneID: SceneID? {
        switch self {
        case .main: return .main
        case .item: return .item
        case .search: return .search
        case .quickWork: return .quickWork
        case .due: return .due
        case .switcher: return .switcher
        case .activityLog: return .activityLog
        case .unitConverter: return .unitConverter
        case .dateCalc: return .dateCalculator
        case .folderBuilder: return .folderBuilder
        case .crewTable: return .crewTable
        case .flashSync: return .flashSync
        case .settings: return .settings
        case .shortcuts: return .shortcuts
        case .about: return .about
        case .login: return .login
        case .splash: return .splash
        case .viewer, .other: return nil
        }
    }
}

// MARK: Environment

extension EnvironmentValues {
    /// The router of the running app (nil outside a window root).
    @Entry var aaRouter: CommandRouter? = nil
    /// The role of the window this view lives in.
    @Entry var aaWindowRole: KeyWindowRole = .other
}

// MARK: Publishing modifiers

extension View {
    /// On the focusable List / Table (03 §6.5.1.10 "list": publish while focused, identity token per list).
    func aaListCommands(_ c: ListCommands) -> some View { modifier(ShellListCommandsModifier(commands: c)) }

    /// On each section root.
    func aaSectionCommands(_ section: SectionID, _ c: SectionCommands) -> some View {
        modifier(ShellSectionCommandsModifier(section: section, commands: c))
    }

    /// ⌥⌘F target (SHELL-517). In non-main windows: the window's filter field. In the main window an embedded panel's
    /// field wins over `SectionCommands.focusSearchField` while its panel contains the first responder.
    func aaFilterField(for window: KeyWindowRole) -> some View { modifier(ShellFilterFieldModifier(window: window)) }
}

struct ShellListCommandsModifier: ViewModifier {
    let commands: ListCommands
    @Environment(\.aaRouter) private var router
    @FocusState private var focused: Bool
    @State private var token = UUID()

    func body(content: Content) -> some View {
        let deleteOnKey = commands.deleteConfirms && commands.delete != nil
        return content
            .focused($focused)
            .onDeleteCommand(perform: deleteOnKey ? { commands.delete?() } : nil)       // SHELL-670
            .onChange(of: focused, initial: true) { _, isFocused in
                if isFocused { router?.publishList(commands, token: token) } else { router?.withdrawList(token: token) }
            }
            .onChange(of: commands.state) { _, _ in
                if focused { router?.publishList(commands, token: token) }
            }
            .background(ShellListClosureRefresher(commands: commands, token: token, active: focused, router: router))
            .onDisappear { router?.withdrawList(token: token) }
    }
}

/// Keeps the router's list closures fresh after every render of the publishing list (closures are not observed).
private struct ShellListClosureRefresher: View {
    let commands: ListCommands
    let token: UUID
    let active: Bool
    let router: CommandRouter?

    var body: some View {
        if active { router?.refreshListClosures(commands, token: token) }
        return Color.clear.frame(width: 0, height: 0)
    }
}

struct ShellSectionCommandsModifier: ViewModifier {
    let section: SectionID
    let commands: SectionCommands
    @Environment(\.aaRouter) private var router

    func body(content: Content) -> some View {
        content
            .background(ShellSectionClosureRefresher(section: section, commands: commands, router: router))
            .onChange(of: commands.summary, initial: true) { _, _ in router?.publishSection(section, commands) }
    }
}

private struct ShellSectionClosureRefresher: View {
    let section: SectionID
    let commands: SectionCommands
    let router: CommandRouter?

    var body: some View {
        router?.refreshSectionClosures(section, commands)
        return Color.clear.frame(width: 0, height: 0)
    }
}

struct ShellFilterFieldModifier: ViewModifier {
    let window: KeyWindowRole
    @Environment(\.aaRouter) private var router
    @FocusState private var focused: Bool
    @State private var token = UUID()
    @State private var anchor = ShellViewAnchor()

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .background(ShellViewAnchorView(anchor: anchor))
            .onAppear {
                router?.registerFilter(ShellFilterRegistration(token: token, window: window, anchor: anchor,
                                                               focus: { focused = true }, isFocused: { focused }))
            }
            .onChange(of: focused) { _, _ in router?.filterFocusChanged() }
            .onDisappear { router?.unregisterFilter(token: token) }
    }
}

/// Holds the NSView behind a SwiftUI view (filter fields, section roots, sheets) — used for focus-within tests.
@MainActor final class ShellViewAnchor {
    weak var view: NSView?
}

struct ShellViewAnchorView: NSViewRepresentable {
    let anchor: ShellViewAnchor
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        anchor.view = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { anchor.view = nsView }
}

/// One ⌥⌘F target.
@MainActor struct ShellFilterRegistration {
    let token: UUID
    let window: KeyWindowRole
    let anchor: ShellViewAnchor
    let focus: () -> Void
    let isFocused: () -> Bool
}
