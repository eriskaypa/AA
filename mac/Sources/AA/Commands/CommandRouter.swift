// Spec: 03 §6.5.1.10 (CommandRouter state, keeping the inputs current, step F), SHELL-512, SHELL-516…522, §7.8 menu
//       command → implementation table, SHELL-047 (undo delete), FLASH-002 (flush + save before Flash Sync);
//       ARCHITECTURE.md §7.6, §7.8.
import AppKit
import SwiftUI
import AACore

/// The app's single command router: `state(_:)` feeds every menu item, `perform(_:)` runs it.
@MainActor @Observable
final class CommandRouter {
    @ObservationIgnored weak var env: AppEnvironment?

    // Observed inputs (03 §6.5.1.10 "State").
    var phase: ShellAppPhase = .instanceCheck
    var keyWin: ShellKeyWindow = .none
    var keyWinIsSheetOrModal = false
    var decisionSheetOpen = false
    var responder: ShellResponder = .none
    var responderUndo = ShellUndoState()
    var keyWindowUndo = ShellUndoState()
    var list: ShellListState?
    var sections: [SectionID: ShellSectionSummary] = [:]
    var pendingUndoCount = 0
    var conflictCopiesExist = false
    var darkModeChecked = false
    var filterVersion = 0
    var itemWindowGated = false

    // Closures and registrations (never observed: they change on every render).
    @ObservationIgnored private var listCommands: (token: UUID, commands: ListCommands)?
    @ObservationIgnored private var sectionClosures: [SectionID: SectionCommands] = [:]
    @ObservationIgnored private var filters: [UUID: ShellFilterRegistration] = [:]
    @ObservationIgnored private var updateObserver: NSObjectProtocol?

    init() {}

    // MARK: Publishing

    func publishList(_ c: ListCommands, token: UUID) {
        listCommands = (token, c)
        if list != c.state { list = c.state }
    }

    func refreshListClosures(_ c: ListCommands, token: UUID) {
        if listCommands?.token == token { listCommands = (token, c) }
    }

    func withdrawList(token: UUID) {
        guard listCommands?.token == token else { return }
        listCommands = nil
        if list != nil { list = nil }
    }

    func publishSection(_ s: SectionID, _ c: SectionCommands) {
        sectionClosures[s] = c
        if sections[s] != c.summary { sections[s] = c.summary }
    }

    func refreshSectionClosures(_ s: SectionID, _ c: SectionCommands) { sectionClosures[s] = c }

    func registerFilter(_ r: ShellFilterRegistration) {
        filters[r.token] = r
        filterVersion += 1
    }

    func unregisterFilter(token: UUID) {
        if filters.removeValue(forKey: token) != nil { filterVersion += 1 }
    }

    func filterFocusChanged() { filterVersion += 1 }

    func sectionCommands(_ s: SectionID) -> SectionCommands? { sectionClosures[s] }

    // MARK: Keeping the inputs current

    /// Starts tracking the key window, sheets and the first responder (NSApplication.didUpdate fires after every event).
    func startTracking() {
        guard updateObserver == nil else { return }
        updateObserver = NotificationCenter.default.addObserver(forName: NSApplication.didUpdateNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshKeyState() }
        }
    }

    func refreshKeyState() {
        guard let kw = NSApp.keyWindow else { return }
        let opener = SceneOpener.shared
        var isSheet = kw.sheetParent != nil || NSApp.modalWindow != nil
        var role: KeyWindowRole = opener.role(of: kw) ?? .other
        var decision = false
        if let parent = kw.sheetParent {
            let sheetRole = opener.sheetInfo(of: kw)
            if let sr = sheetRole?.role { role = sr } else { role = opener.role(of: parent) ?? .other }
            decision = (sheetRole?.kind ?? .decision) == .decision
        } else if NSApp.modalWindow != nil {
            decision = true
        }
        if kw is NSPanel, kw.isFloatingPanel == false, kw.sheetParent == nil, opener.role(of: kw) == nil {
            isSheet = isSheet || kw.level == .modalPanel
        }
        let shellRole = role.shell
        if keyWin != shellRole { keyWin = shellRole }
        if keyWinIsSheetOrModal != isSheet { keyWinIsSheetOrModal = isSheet }
        if decisionSheetOpen != decision { decisionSheetOpen = decision }

        let fr = kw.firstResponder
        var newResponder: ShellResponder = .none
        var undoState = ShellUndoState()
        if let rich = fr as? AARichTextResponder {
            newResponder = .richText(rich.aaRichKind.shellKind, editable: rich.isEditable,
                                     hasSelection: rich.selectedRange().length > 0)
            undoState = Self.undoState(rich.undoManager)
        } else if let text = fr as? NSTextView {
            newResponder = .text(hasSelection: text.selectedRange().length > 0, editable: text.isEditable)
            undoState = Self.undoState(text.undoManager)
        } else if fr is NSText {
            newResponder = .text(hasSelection: false, editable: true)
            undoState = Self.undoState(fr?.undoManager)
        }
        if responder != newResponder { responder = newResponder }
        if responderUndo != undoState { responderUndo = undoState }
        let winUndo = Self.undoState(kw.undoManager)
        if keyWindowUndo != winUndo { keyWindowUndo = winUndo }
        if case .item(let id) = shellRole, let env {
            let gated = env.store.item(id: id).map { env.locks.isGated($0) } ?? false
            if itemWindowGated != gated { itemWindowGated = gated }
        }
    }

    static func undoState(_ um: UndoManager?) -> ShellUndoState {
        guard let um else { return ShellUndoState() }
        return ShellUndoState(canUndo: um.canUndo, undoTitle: um.undoMenuItemTitle, canRedo: um.canRedo,
                              redoTitle: um.redoMenuItemTitle)
    }

    // MARK: Context

    /// The decision table's input, built from the observed state (03 §6.5.1.10).
    var context: CommandContext {
        var c = CommandContext()
        c.phase = phase
        c.keyWin = keyWin
        c.keyWinIsSheetOrModal = keyWinIsSheetOrModal
        c.decisionSheetOpen = decisionSheetOpen
        c.responder = responder
        c.responderUndo = responderUndo
        c.keyWindowUndo = keyWindowUndo
        c.list = list
        c.itemWindowGated = itemWindowGated
        c.pendingUndoCount = pendingUndoCount
        c.conflictCopiesExist = conflictCopiesExist
        c.darkMode = darkModeChecked
        guard let env else {
            c.hasRepo = false
            return c
        }
        let section = env.navigator.selectedSection
        c.section = section
        c.sectionOrder = env.navigator.sectionOrder
        c.safeMode = env.isSafeMode
        c.writeGated = env.isReadOnlyInstance || env.dataFileGuard?.state.mode == .stoppedEditing
        c.hasRepo = phase == .main
        let s = sections[section]
        c.newItemAvailable = s?.hasNewItem ?? false
        c.renameAvailable = s?.hasRename ?? false
        c.openInNewWindowAvailable = s?.hasOpenInNewWindow ?? false
        if let h = s?.hierarchySelection {
            c.hierSelection = ShellHierarchySelection(primary: h.primary, count: h.count, gated: h.gated, detached: h.detached)
        }
        c.plannerCommandsAvailable = s?.hasPlanner ?? false
        c.calendarFontScale = s?.calendarFontScale
        c.canSetCalendarFontScale = s?.canSetCalendarFontScale ?? false
        c.vesselMenuAvailable = s?.hasVessel ?? false
        let filter = filterTarget(section: s)
        c.filterTargetAvailable = filter.available
        c.filterTargetFocused = filter.focused
        let settings = env.settings.values
        c.sharedSaveConfigured = !NetText.isBlank(settings.sharedSaveFile)
        c.encryptLocalData = settings.encryptLocalData
        c.textOnlyExport = settings.textOnlyExport
        c.syncOnSave = settings.syncOnSave
        c.showShortcutBar = env.store.data.ui.showShortcutBar
        c.inFlight = Set(env.driveSync.inFlight.map { op -> ShellDriveOperation in
            switch op {
            case .upload: return .upload
            case .load: return .load
            case .check: return .check
            case .push: return .push
            }
        })
        return c
    }

    // MARK: Filter targets (SHELL-517)

    private func filterTarget(section: ShellSectionSummary?) -> (available: Bool, focused: Bool, focus: (() -> Void)?) {
        _ = filterVersion
        switch keyWin {
        case .main:
            if let panel = mainPanelFilterWithFocusWithin() {
                return (true, panel.isFocused(), panel.focus)
            }
            if let s = section, s.hasSearchField {
                let closure = sectionClosures[env?.navigator.selectedSection ?? .equipment]?.focusSearchField
                return (true, s.searchFieldIsFocused, closure)
            }
            return (false, false, nil)
        case .quickWork, .activityLog, .search:
            let role: KeyWindowRole = keyWin == .quickWork ? .quickWork : (keyWin == .search ? .search : .activityLog)
            if let r = filters.values.first(where: { $0.window == role }) { return (true, r.isFocused(), r.focus) }
            return (false, false, nil)
        default:
            return (false, false, nil)
        }
    }

    /// A main-window panel field whose panel contains the first responder (ARCH §7.6 rule).
    private func mainPanelFilterWithFocusWithin() -> ShellFilterRegistration? {
        guard let kw = NSApp.keyWindow, let frView = kw.firstResponder as? NSView else { return nil }
        for r in filters.values where r.window == .main {
            guard let fieldView = r.anchor.view, fieldView.window === kw, !fieldView.isHiddenOrHasHiddenAncestor,
                  let panel = Self.panelRoot(of: fieldView) else { continue }
            if frView.isDescendant(of: panel) { return r }
        }
        return nil
    }

    /// The child of the nearest split view / tab view / content view on the path to `view` (the field's "panel").
    static func panelRoot(of view: NSView) -> NSView? {
        var child: NSView = view
        var current = view.superview
        while let c = current {
            if c is NSSplitView || c is NSTabView || c === view.window?.contentView { return child }
            child = c
            current = c.superview
        }
        return nil
    }

    // MARK: Decisions

    func decision(_ c: CommandID) -> CommandDecision {
        var d = CommandRouterCore.state(c, context)
        if d.enabled, case .richFormat(let cmd) = d.effect, let f = FormatCommand.forCommand(cmd),
           let rich = NSApp.keyWindow?.firstResponder as? AARichTextResponder, !rich.aaValidate(f) {
            d.enabled = false
        }
        return d
    }

    func state(_ c: CommandID) -> (enabled: Bool, title: String) {
        let d = decision(c)
        return (d.enabled, d.title)
    }

    // MARK: Perform

    func perform(_ c: CommandID) {
        let effect = CommandRouterCore.perform(c, context)
        execute(effect, command: c)
    }

    private var richResponder: AARichTextResponder? { NSApp.keyWindow?.firstResponder as? AARichTextResponder }

    private func execute(_ effect: CommandEffect, command c: CommandID) {
        switch effect {
        case .none: return
        case .beep: NSSound.beep()
        case .forwardText(let sel): NSApp.sendAction(Selector(sel), to: nil, from: nil)
        case .run: run(c)
        case .richFind(let a): richResponder?.aaPerform(a.formatCommand)
        case .focusSearchQuery: SearchWindowActions.focusQuery(selectAll: true)
        case .openSearch:
            env?.open(.search)
            SearchWindowActions.focusQuery(selectAll: true)
        case .textUndo: NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        case .textRedo: NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
        case .windowUndo: NSApp.keyWindow?.undoManager?.undo()
        case .windowRedo: NSApp.keyWindow?.undoManager?.redo()
        case .undoDelete: env?.undoDelete()
        case .listDelete: listCommands?.commands.delete?()
        case .listMove(let up): listCommands?.commands.move?(up ? .up : .down)
        case .listMoveTo: listCommands?.commands.moveTo?()
        case .listQuickLook: listCommands?.commands.quickLook?()
        case .richMove(let up): richResponder?.aaPerform(up ? .moveItemUp : .moveItemDown)
        case .richFormat(let cmd):
            if let f = FormatCommand.forCommand(cmd), let r = richResponder, r.aaValidate(f) { r.aaPerform(f) }
        case .richFontStep(let bigger): richResponder?.aaPerform(bigger ? .bigger : .smaller)
        case .calendarFontScale(let s): sectionClosures[.calendar]?.setCalendarFontScale?(s)
        case .selectSection(let s): env?.navigator.select(s)
        case .focusFilter: filterTarget(section: sections[env?.navigator.selectedSection ?? .equipment]).focus?()
        }
    }

    /// Highlight swatches (Format ▸ Font ▸ Highlight ▸, CONT-026; the lock sentinel #FFE699 is never offered).
    static let highlightSwatches: [(name: String, color: ARGB)] = [
        ("Yellow", ARGB(r: 0xFF, g: 0xF5, b: 0x9D)), ("Green", ARGB(r: 0xC5, g: 0xE1, b: 0xA5)),
        ("Blue", ARGB(r: 0xB3, g: 0xE5, b: 0xFC)), ("Pink", ARGB(r: 0xF8, g: 0xBB, b: 0xD0)),
        ("Orange", ARGB(r: 0xFF, g: 0xCC, b: 0x80)), ("Purple", ARGB(r: 0xD1, g: 0xC4, b: 0xE9)),
    ]

    func performHighlight(_ color: ARGB?, other: Bool = false) {
        guard decision(.highlight).enabled, let r = richResponder else { return }
        let f: FormatCommand = other ? .highlightOther : .highlight(color)
        if r.aaValidate(f) { r.aaPerform(f) }
    }

    // MARK: App-level actions (ARCHITECTURE.md §7.8)

    private func run(_ c: CommandID) {
        guard let env else {
            switch c {
            case .quit: NSApp.terminate(nil)
            case .close: NSApp.keyWindow?.performClose(nil)
            case .about: SceneOpener.shared.open(.about)
            default: break
            }
            return
        }
        let dialogs = env.mainDialogs
        let section = env.navigator.selectedSection
        switch c {
        case .about: env.open(.about)
        case .settings: env.open(.settings(tab: nil))
        case .quit: NSApp.terminate(nil)
        case .close: NSApp.keyWindow?.performClose(nil)
        case .keyboardShortcuts: env.open(.shortcuts)
        case .newItem:
            env.flushAllEditors()
            sectionClosures[section]?.newItem?()
        case .openInNewWindow: sectionClosures[section]?.openInNewWindow?()
        case .rename: sectionClosures[section]?.rename?()
        case .save: env.doSave()
        case .saveCopyAs, .reloadFromDisk, .importFromFile, .encryptLocalData, .setSharedSaveFile, .stopSharedSaveFile,
             .checkSharedSaveNow, .setAppIdentity, .openDataFolder, .exportDataFolder, .importDataFolder,
             .exportTextOnly, .setPassword, .lockNow:
            Task { @MainActor in await ShellFlows.perform(c, env: env, dialogs: dialogs) }
        case .recoverConflictCopies:
            env.showMainWindow()
            Task { @MainActor in await dialogs.presentSheet(.closeType) { _ in ConflictCopiesSheet() } }
        case .trash:
            env.showMainWindow()
            Task { @MainActor in
                await dialogs.presentSheet(.closeType) { _ in TrashSheet(onFinish: { env.refreshAfterTrashChange() }) }
                env.refreshAfterTrashChange()
            }
        case .driveSaveCopy: Task { @MainActor in await DriveActions.saveCopyToSyncedFolder(env: env, dialogs: dialogs) }
        case .driveSetFolder: Task { @MainActor in await DriveActions.setDriveFolder(env: env, dialogs: dialogs) }
        case .driveUpload: Task { @MainActor in await DriveActions.uploadBackup(env: env, dialogs: dialogs) }
        case .driveLoad: Task { @MainActor in await DriveActions.loadBackup(env: env, dialogs: dialogs) }
        case .driveSetOAuthClient: Task { @MainActor in await DriveActions.setOAuthClient(env: env, dialogs: dialogs) }
        case .driveSignOut: Task { @MainActor in await DriveActions.signOut(env: env, dialogs: dialogs) }
        case .driveSyncOnSave: Task { @MainActor in await DriveActions.toggleSyncOnSave(env: env, dialogs: dialogs) }
        case .driveCheckNewer: Task { @MainActor in await DriveActions.checkForNewer(env: env, dialogs: dialogs) }
        case .flashSync:
            // FLASH-002: flush every editor and save synchronously before the window prepares anything.
            env.flushAllEditors()
            if env.store.isDirty { try? env.saveQuietly() }
            env.open(.flashSync)
        case .exportPDF, .print:
            let target: UUID?
            var targetDialogs = dialogs
            if case .item(let id) = keyWin {
                target = id
                targetDialogs = SceneOpener.shared.dialogs(forItem: id) ?? dialogs
            } else {
                target = sections[section]?.hierarchySelection?.primary
            }
            guard let id = target else { return }
            env.flushAllEditors()
            if c == .exportPDF {
                Task { @MainActor in await PdfExportFlows.exportItem(itemID: id, env: env, dialogs: targetDialogs) }
            } else {
                Task { @MainActor in await PdfExportFlows.printItem(itemID: id, env: env, dialogs: targetDialogs) }
            }
        case .shortcutBar: env.setShortcutBarVisible(!env.store.data.ui.showShortcutBar)
        case .darkMode:
            env.postSettingStatus(ShellAppearance.toggleDarkMode(settings: env.settings))
            darkModeChecked = ShellAppearance.isEffectivelyDark
        case .tabColors:
            env.showMainWindow()
            Task { @MainActor in await dialogs.presentSheet(.decision) { dismiss in TabColorsSheet(dismiss: dismiss) } }
        case .plannerPrevious: sectionClosures[.planner]?.plannerPrevious?()
        case .plannerToday: sectionClosures[.planner]?.plannerToday?()
        case .plannerNext: sectionClosures[.planner]?.plannerNext?()
        case .folderBuilder: env.open(.folderBuilder)
        case .dateCalculator: env.open(.dateCalculator)
        case .dueDates: env.open(.dueDates)
        case .quickWork: env.open(.quickWork)
        case .quickSwitcher: env.open(.quickSwitcher)
        case .activityLog: env.open(.activityLog)
        case .unitConverter: env.open(.unitConverter)
        case .importCompasCrew:
            env.navigator.select(.crew)
            Task { @MainActor in await CrewActions.importCompas(env: env, dialogs: dialogs) }
        case .checkCrewExpiries:
            env.navigator.select(.crew)
            Task { @MainActor in await CrewActions.checkExpiries(env: env, dialogs: dialogs, showWhenNone: true) }
        case .vesselImportWorkOrders: sectionClosures[.vessels]?.vessel?.importWorkOrders()
        case .vesselExportWorkOrders: sectionClosures[.vessels]?.vessel?.exportWorkOrders()
        case .vesselImportPorts: sectionClosures[.vessels]?.vessel?.importPorts()
        case .vesselExportPorts: sectionClosures[.vessels]?.vessel?.exportPorts()
        case .vesselNewQuickCard: sectionClosures[.vessels]?.vessel?.newQuickCard()
        case .sireExport: Task { @MainActor in await SireActions.showExportDialog(env: env, dialogs: dialogs) }
        case .setGeminiKey: Task { @MainActor in await SireActions.setGeminiKey(env: env, dialogs: dialogs) }
        default: break
        }
    }
}
