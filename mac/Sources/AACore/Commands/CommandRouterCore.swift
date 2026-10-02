// Spec: 03 §6.5.1.10 (CommandRouter: global gates G1–G3, resolution of routed commands, step F forwarding),
//       SHELL-502 (text-first precedence), SHELL-505 (modal suppression), SHELL-506 (phase gating), SHELL-507 (safe
//       mode), SHELL-516…522 (delete, find, ⌘T, text size, move, undo, sections); ARCHITECTURE.md §7.6 (the pure
//       decision table lives in AACore so AACoreTests cover T-KB-01…58). Vectors: 03 §6.5.1.14.
import Foundation

public enum ShellAppPhase: Sendable, Equatable { case instanceCheck, blocked, splash, login, main }

/// The key window as the router sees it (03 §6.5.1.10 `KeyWin`).
public enum ShellKeyWindow: Hashable, Sendable {
    case main, item(UUID), search, quickWork, due, switcher, activityLog, unitConverter, dateCalc, folderBuilder,
         crewTable, viewer, flashSync, settings, shortcuts, about, login, splash, other, none
}

public enum ShellRichKind: Sendable, Equatable { case container, sireBody, viewer }

/// The first responder class (03 §6.5.1.10 `Responder`).
public enum ShellResponder: Sendable, Equatable {
    case richText(ShellRichKind, editable: Bool, hasSelection: Bool)
    case text(hasSelection: Bool, editable: Bool)
    case none
}

/// What the focused list published (03 §6.5.1.10 `ListCommands`, reduced to values).
public struct ShellListState: Sendable, Equatable {
    public var role: String
    public var selectionCount: Int
    public var deleteTitle: String?
    public var hasDelete: Bool
    public var canMoveUp: Bool
    public var canMoveDown: Bool
    public var hasMove: Bool
    public var hasMoveTo: Bool
    public var hasQuickLook: Bool
    public var hasPrimary: Bool

    public init(role: String, selectionCount: Int, deleteTitle: String? = nil, hasDelete: Bool = false,
                canMoveUp: Bool = false, canMoveDown: Bool = false, hasMove: Bool = false, hasMoveTo: Bool = false,
                hasQuickLook: Bool = false, hasPrimary: Bool = false) {
        self.role = role; self.selectionCount = selectionCount; self.deleteTitle = deleteTitle; self.hasDelete = hasDelete
        self.canMoveUp = canMoveUp; self.canMoveDown = canMoveDown; self.hasMove = hasMove; self.hasMoveTo = hasMoveTo
        self.hasQuickLook = hasQuickLook; self.hasPrimary = hasPrimary
    }
}

public struct ShellHierarchySelection: Sendable, Equatable {
    public var primary: UUID?
    public var count: Int
    public var gated: Bool
    public var detached: Bool
    public init(primary: UUID? = nil, count: Int = 0, gated: Bool = false, detached: Bool = false) {
        self.primary = primary; self.count = count; self.gated = gated; self.detached = detached
    }
}

/// An undo manager's state (the text responder's or the key window's).
public struct ShellUndoState: Sendable, Equatable {
    public var canUndo: Bool
    public var undoTitle: String
    public var canRedo: Bool
    public var redoTitle: String
    public init(canUndo: Bool = false, undoTitle: String = "Undo", canRedo: Bool = false, redoTitle: String = "Redo") {
        self.canUndo = canUndo; self.undoTitle = undoTitle; self.canRedo = canRedo; self.redoTitle = redoTitle
    }
}

public enum ShellDriveOperation: String, Sendable, Hashable { case upload, load, check, push }

/// Every input of the decision table, as plain values (03 §6.5.1.10 "State").
public struct CommandContext: Sendable, Equatable {
    public var phase: ShellAppPhase = .main
    public var keyWin: ShellKeyWindow = .main
    public var keyWinIsSheetOrModal = false
    public var decisionSheetOpen = false
    public var responder: ShellResponder = .none
    public var list: ShellListState?
    public var section: SectionID = .equipment
    public var sectionOrder: [SectionID] = SectionID.defaultOrder
    public var hierSelection = ShellHierarchySelection()
    /// The key item window's item is gated (Export as PDF / Print).
    public var itemWindowGated = false
    public var plannerCommandsAvailable = false
    public var calendarFontScale: Double?
    public var canSetCalendarFontScale = false
    public var safeMode = false
    public var hasRepo = true
    public var pendingUndoCount = 0
    public var inFlight: Set<ShellDriveOperation> = []
    public var responderUndo = ShellUndoState()
    public var keyWindowUndo = ShellUndoState()
    public var newItemAvailable = false
    public var renameAvailable = false
    public var openInNewWindowAvailable = false
    public var filterTargetAvailable = false
    public var filterTargetFocused = false
    public var sharedSaveConfigured = false
    public var conflictCopiesExist = false
    public var vesselMenuAvailable = false
    public var printShipped = true
    public var encryptLocalData = false
    public var textOnlyExport = false
    public var syncOnSave = false
    public var darkMode = false
    public var showShortcutBar = true

    public init() {}
}

public enum ShellFindAction: Sendable, Equatable { case showFind, findNext, findPrevious, useSelectionForFind, jumpToSelection }

/// What `perform` does after the decision (the AA router executes it).
public enum CommandEffect: Sendable, Equatable {
    case none
    /// The command's own app-level action (open a window, run a flow, toggle a setting…).
    case run
    case richFind(ShellFindAction)
    case focusSearchQuery
    case openSearch
    case textUndo, textRedo, windowUndo, windowRedo
    case undoDelete
    case listDelete
    case listMove(up: Bool)
    case listMoveTo
    case listQuickLook
    case richMove(up: Bool)
    case richFormat(CommandID)
    case richFontStep(bigger: Bool)
    case calendarFontScale(Double)
    case selectSection(SectionID)
    case focusFilter
    /// Step F: forward this standard text selector (`deleteToBeginningOfLine:` …) to the first responder.
    case forwardText(String)
    case beep
}

public struct CommandDecision: Sendable, Equatable {
    public var enabled: Bool
    public var title: String
    public var checked: Bool
    public var effect: CommandEffect
    public init(enabled: Bool, title: String, checked: Bool = false, effect: CommandEffect = .none) {
        self.enabled = enabled; self.title = title; self.checked = checked; self.effect = effect
    }
}

/// The pure decision table (03 §6.5.1.10).
public enum CommandRouterCore {
    static let calendarScaleMin = 11.0, calendarScaleMax = 28.0, calendarScaleStep = 1.5

    /// Commands enabled while the phase is not `.main` (SHELL-506; text Edit items resolve normally).
    static let phaseExempt: Set<CommandID> = [.about, .quit, .hideApp, .hideOthers, .showAll, .services, .close]
    /// Commands that stay enabled while a sheet / modal is key (SHELL-505).
    static let modalExempt: Set<CommandID> = [.quit, .hideApp, .hideOthers, .showAll, .services, .keyboardShortcuts,
                                              .about]
    /// List-scoped commands act inside the key window (also inside builder sheets) — G2 does not apply.
    static let listScoped: Set<CommandID> = [.deleteFamily, .moveTo, .quickLook]
    static let formatCommands: Set<CommandID> = [.showFonts, .bold, .italic, .underline, .strikethrough,
        .baselineDefault, .superscript, .subscript, .showColors, .highlight, .alignLeft, .center, .justify,
        .alignRight, .bulletedList, .numberedList, .indent, .outdent, .insertLink, .insertTable, .insertSavedList,
        .clearFormatting, .lockSelection, .unlockSelection]
    static let sireBodyFormat: Set<CommandID> = [.bold, .italic, .underline]
    static let systemCommands: Set<CommandID> = [.services, .hideApp, .hideOthers, .showAll, .cut, .copy, .paste,
        .pasteAndMatchStyle, .delete, .selectAll, .spellingAndGrammar, .checkDocumentNow, .substitutions,
        .transformations, .speech, .systemTextServices, .toggleSidebar, .toggleToolbar, .customizeToolbar,
        .fullScreen, .minimize, .zoom, .bringAllToFront, .helpSearch]

    public static func state(_ c: CommandID, _ ctx: CommandContext) -> CommandDecision {
        let title = staticTitle(c, ctx)
        if c.isInWindowKey { return CommandDecision(enabled: true, title: title) }
        if systemCommands.contains(c) { return CommandDecision(enabled: true, title: title) }

        // Edit items that act on text resolve before the gates (login fields, text inside sheets).
        switch c {
        case .undo, .redo, .find, .findNext, .findPrevious, .useSelectionForFind, .jumpToSelection:
            return resolveEditFind(c, ctx, title: title)
        default: break
        }
        if formatCommands.contains(c) || c == .bigger || c == .smaller {
            return resolveFormat(c, ctx, title: title)
        }

        // G1 — phase
        if ctx.phase != .main && !phaseExempt.contains(c) { return CommandDecision(enabled: false, title: title) }
        if ctx.phase != .main { return CommandDecision(enabled: true, title: title, effect: .run) }
        // G2 — sheet / modal key window
        if ctx.keyWinIsSheetOrModal && !modalExempt.contains(c) && !listScoped.contains(c) && !moveCommand(c) {
            return CommandDecision(enabled: false, title: title)
        }
        return resolve(c, ctx, title: title)
    }

    static func moveCommand(_ c: CommandID) -> Bool { c == .moveUp || c == .moveDown }

    static func staticTitle(_ c: CommandID, _ ctx: CommandContext) -> String {
        if let pos = c.sectionPosition {
            return pos < ctx.sectionOrder.count ? ctx.sectionOrder[pos].title : ShortcutRegistry.title(c)
        }
        return ShortcutRegistry.title(c)
    }

    static func disabled(_ title: String) -> CommandDecision { CommandDecision(enabled: false, title: title) }

    // MARK: Edit / Find (SHELL-517, SHELL-521)

    static func resolveEditFind(_ c: CommandID, _ ctx: CommandContext, title: String) -> CommandDecision {
        switch c {
        case .undo:
            switch ctx.responder {
            case .text, .richText:
                return CommandDecision(enabled: ctx.responderUndo.canUndo, title: ctx.responderUndo.undoTitle,
                                       effect: .textUndo)
            case .none:
                if ctx.phase != .main { return disabled("Undo") }
                if ctx.keyWin == .main && !ctx.keyWinIsSheetOrModal {
                    let n = ctx.pendingUndoCount
                    if !ctx.hasRepo || ctx.safeMode || n == 0 { return disabled("Undo") }
                    return CommandDecision(enabled: true, title: n == 1 ? "Undo Move to Trash" : "Undo Move to Trash (\(n) Items)",
                                           effect: .undoDelete)
                }
                return CommandDecision(enabled: ctx.keyWindowUndo.canUndo, title: ctx.keyWindowUndo.undoTitle,
                                       effect: .windowUndo)
            }
        case .redo:
            switch ctx.responder {
            case .text, .richText:
                return CommandDecision(enabled: ctx.responderUndo.canRedo, title: ctx.responderUndo.redoTitle,
                                       effect: .textRedo)
            case .none:
                if ctx.phase != .main || ctx.keyWin == .main { return disabled("Redo") }
                return CommandDecision(enabled: ctx.keyWindowUndo.canRedo, title: ctx.keyWindowUndo.redoTitle,
                                       effect: .windowRedo)
            }
        case .find:
            if case .richText = ctx.responder, ctx.phase == .main {
                return CommandDecision(enabled: true, title: title, effect: .richFind(.showFind))
            }
            if ctx.phase != .main || ctx.keyWinIsSheetOrModal { return disabled(title) }
            if ctx.keyWin == .search { return CommandDecision(enabled: true, title: title, effect: .focusSearchQuery) }
            return CommandDecision(enabled: true, title: title, effect: .openSearch)
        default:
            guard ctx.phase == .main, case .richText(_, _, let hasSelection) = ctx.responder else { return disabled(title) }
            let action: ShellFindAction
            switch c {
            case .findNext: action = .findNext
            case .findPrevious: action = .findPrevious
            case .useSelectionForFind:
                if !hasSelection { return disabled(title) }
                action = .useSelectionForFind
            default: action = .jumpToSelection
            }
            return CommandDecision(enabled: true, title: title, effect: .richFind(action))
        }
    }

    // MARK: Format (SHELL-503, SHELL-519)

    static func resolveFormat(_ c: CommandID, _ ctx: CommandContext, title: String) -> CommandDecision {
        guard ctx.phase == .main else { return disabled(title) }
        if c == .bigger || c == .smaller {
            switch ctx.responder {
            case .richText(.container, editable: true, _):
                return CommandDecision(enabled: true, title: title, effect: .richFontStep(bigger: c == .bigger))
            case .richText, .text:
                return disabled(title)
            case .none:
                guard ctx.keyWin == .main, !ctx.keyWinIsSheetOrModal, ctx.section == .calendar,
                      ctx.canSetCalendarFontScale else { return disabled(title) }
                let cur = ctx.calendarFontScale ?? 13
                let next = c == .bigger ? cur + calendarScaleStep : cur - calendarScaleStep
                return CommandDecision(enabled: true, title: title,
                                       effect: .calendarFontScale(min(max(next, calendarScaleMin), calendarScaleMax)))
            }
        }
        switch ctx.responder {
        case .richText(.container, editable: true, _):
            return CommandDecision(enabled: true, title: title, effect: .richFormat(c))
        case .richText(.sireBody, _, _) where sireBodyFormat.contains(c):
            return CommandDecision(enabled: true, title: title, effect: .richFormat(c))
        default:
            return disabled(title)
        }
    }

    // MARK: Everything else

    static func resolve(_ c: CommandID, _ ctx: CommandContext, title: String) -> CommandDecision {
        let main = ctx.keyWin == .main && !ctx.keyWinIsSheetOrModal
        let noText = ctx.responder == .none
        func run(_ enabled: Bool, _ t: String? = nil, checked: Bool = false) -> CommandDecision {
            CommandDecision(enabled: enabled, title: t ?? title, checked: checked, effect: enabled ? .run : .none)
        }
        if let pos = c.sectionPosition {
            guard pos < ctx.sectionOrder.count else { return disabled(title) }
            let s = ctx.sectionOrder[pos]
            return CommandDecision(enabled: true, title: s.title, checked: s == ctx.section, effect: .selectSection(s))
        }
        switch c {
        case .about, .quit, .close, .settings, .keyboardShortcuts:
            return run(true)
        case .newItem:
            guard main, let t = ctx.section.newItemTitle, ctx.newItemAvailable else { return disabled("New Item") }
            return run(true, t)
        case .openInNewWindow:
            return run(main && ctx.section.isHierarchy && ctx.hierSelection.count >= 1 && ctx.openInNewWindowAvailable)
        case .rename:
            return run(main && ctx.section.isHierarchy && noText && ctx.hierSelection.primary != nil && ctx.renameAvailable)
        case .quickLook:
            guard noText, let l = ctx.list, l.hasQuickLook, l.selectionCount >= 1 else { return disabled(title) }
            return CommandDecision(enabled: true, title: title, effect: .listQuickLook)
        case .deleteFamily:
            guard noText else { return disabled("Delete") }
            guard let l = ctx.list, l.hasDelete, l.selectionCount > 0 else { return disabled("Delete") }
            return CommandDecision(enabled: true, title: l.deleteTitle ?? "Delete", effect: .listDelete)
        case .moveUp, .moveDown:
            let up = c == .moveUp
            if case .richText(.container, editable: true, _) = ctx.responder {
                return CommandDecision(enabled: true, title: title, effect: .richMove(up: up))
            }
            guard noText, let l = ctx.list, l.hasMove, up ? l.canMoveUp : l.canMoveDown else { return disabled(title) }
            return CommandDecision(enabled: true, title: title, effect: .listMove(up: up))
        case .moveTo:
            guard noText, let l = ctx.list, l.hasMoveTo, l.selectionCount >= 1 else { return disabled(title) }
            return CommandDecision(enabled: true, title: title, effect: .listMoveTo)
        case .searchAll:
            return CommandDecision(enabled: true, title: title, effect: .openSearch)
        case .searchCurrentList:
            let windowWithFilter: Bool
            switch ctx.keyWin {
            case .main, .quickWork, .activityLog, .search: windowWithFilter = true
            default: windowWithFilter = false
            }
            let ok = windowWithFilter && ctx.filterTargetAvailable && !ctx.filterTargetFocused
            return CommandDecision(enabled: ok, title: title, effect: ok ? .focusFilter : .none)
        case .checkSharedSaveNow:
            return run(ctx.sharedSaveConfigured)
        case .recoverConflictCopies:
            return run(ctx.conflictCopiesExist)
        case .encryptLocalData:
            return run(true, checked: ctx.encryptLocalData)
        case .exportTextOnly:
            return run(true, checked: ctx.textOnlyExport)
        case .driveSyncOnSave:
            return run(true, checked: ctx.syncOnSave)
        case .driveUpload, .driveLoad:
            return run(ctx.inFlight.isDisjoint(with: [.upload, .load, .check]))
        case .driveCheckNewer:
            return run(!ctx.inFlight.contains(.check))
        case .exportPDF, .print:
            if c == .print && !ctx.printShipped { return disabled(title) }
            if case .item = ctx.keyWin, !ctx.keyWinIsSheetOrModal { return run(!ctx.itemWindowGated) }
            guard main, ctx.section.isHierarchy, !ctx.hierSelection.detached, ctx.hierSelection.primary != nil else {
                return disabled(title)
            }
            return run(!ctx.hierSelection.gated)
        case .previousSection, .nextSection:
            guard let i = ctx.sectionOrder.firstIndex(of: ctx.section), !ctx.sectionOrder.isEmpty else { return disabled(title) }
            let n = ctx.sectionOrder.count
            let j = c == .nextSection ? (i + 1) % n : (i - 1 + n) % n
            return CommandDecision(enabled: true, title: title, effect: .selectSection(ctx.sectionOrder[j]))
        case .plannerPrevious, .plannerNext:
            return run(main && ctx.section == .planner && ctx.plannerCommandsAvailable && noText)
        case .plannerToday:
            return run(main && ctx.section == .planner && ctx.plannerCommandsAvailable)
        case .shortcutBar:
            return run(true, checked: ctx.showShortcutBar)
        case .darkMode:
            return run(true, checked: ctx.darkMode)
        case .quickSwitcher:
            return run(ctx.hasRepo)
        case .vesselImportWorkOrders, .vesselExportWorkOrders, .vesselImportPorts, .vesselExportPorts,
             .vesselNewQuickCard:
            return run(main && ctx.section == .vessels && ctx.vesselMenuAvailable)
        default:
            return run(true)
        }
    }

    // MARK: perform (step F)

    /// The effect of invoking `c` now. A disabled TXT-class command invoked while text is first responder forwards the
    /// standard text meaning (step F); other disabled commands do nothing.
    public static func perform(_ c: CommandID, _ ctx: CommandContext) -> CommandEffect {
        let d = state(c, ctx)
        if d.enabled { return d.effect }
        let responder = ctx.responder
        if responder == .none { return .none }
        let hasSelection: Bool
        switch responder {
        case .text(let sel, _): hasSelection = sel
        case .richText(_, _, let sel): hasSelection = sel
        case .none: hasSelection = false
        }
        switch c {
        case .deleteFamily: return .forwardText(hasSelection ? "delete:" : "deleteToBeginningOfLine:")
        case .plannerPrevious: return .forwardText("moveToBeginningOfLine:")
        case .plannerNext: return .forwardText("moveToEndOfLine:")
        case .rename, .moveTo, .moveUp, .moveDown, .searchCurrentList: return .beep
        default: return .none
        }
    }

    /// The precedence class of a command (registry `precedence`).
    public static func isTextClass(_ c: CommandID) -> Bool { ShortcutRegistry.row(c)?.precedence == "TXT" }
}
