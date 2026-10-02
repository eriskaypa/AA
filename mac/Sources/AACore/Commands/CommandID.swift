// Spec: 03 §6.5.1.3 (menu-bar commands SHELL-530…663), §6.5.1.4 (in-window keys SHELL-665…695), DECISIONS R-70
//       (File ▸ Recover Conflict Copies…); ARCHITECTURE.md §6.9.
import Foundation

/// One case per row of the shortcut & menu registry (03 §6.5.1.3 menu rows and §6.5.1.4 in-window rows).
/// The raw value is the stable identifier (`aa.cmd.<raw>` on NSMenuItems, SHELL-508).
public enum CommandID: String, CaseIterable, Sendable, Codable {
    // AA menu
    case about, settings, services, hideApp, hideOthers, showAll, quit
    // File menu
    case newItem, openInNewWindow, rename, quickLook, deleteFamily, close, save, saveCopyAs, reloadFromDisk,
         recoverConflictCopies, importFromFile, trash, encryptLocalData, setSharedSaveFile, stopSharedSaveFile,
         checkSharedSaveNow, setAppIdentity, openDataFolder, exportDataFolder, importDataFolder, exportTextOnly,
         driveSaveCopy, driveSetFolder, driveUpload, driveLoad, driveSetOAuthClient, driveSignOut, driveSyncOnSave,
         driveCheckNewer, flashSync, exportPDF, print
    // Edit menu
    case undo, redo, cut, copy, paste, pasteAndMatchStyle, delete, selectAll, moveUp, moveDown, moveTo,
         find, searchAll, searchCurrentList, findNext, findPrevious, useSelectionForFind, jumpToSelection,
         spellingAndGrammar, checkDocumentNow, substitutions, transformations, speech, systemTextServices
    // Format menu
    case showFonts, bold, italic, underline, strikethrough, bigger, smaller, baselineDefault, superscript,
         `subscript`, showColors, highlight, alignLeft, center, justify, alignRight, bulletedList, numberedList,
         indent, outdent, insertLink, insertTable, insertSavedList, clearFormatting, lockSelection, unlockSelection
    // View menu (sections by display position, SHELL-630)
    case section1, section2, section3, section4, section5, section6, section7, section8, section9, section10,
         section11, section12, section13
    case previousSection, nextSection, plannerPrevious, plannerToday, plannerNext, toggleSidebar, toggleToolbar,
         customizeToolbar, shortcutBar, darkMode, tabColors, fullScreen
    // Tools menu
    case folderBuilder, dateCalculator, dueDates, quickWork, quickSwitcher, activityLog, unitConverter,
         importCompasCrew, checkCrewExpiries, vesselImportWorkOrders, vesselExportWorkOrders, vesselImportPorts,
         vesselExportPorts, vesselNewQuickCard, sireExport, setGeminiKey, setPassword, lockNow
    // Window and Help menus
    case minimize, zoom, bringAllToFront, keyboardShortcuts, helpSearch
    // In-window keys, native text keys and platform gestures (non-menu, §6.5.1.4)
    case kbDefaultButton, kbCancel, kbListPrimary, kbBulkPrimary, kbSpace, kbListDelete, kbOpenFile, kbSwitcherKeys,
         kbSearchReturn, kbFieldReturn, kbTrashSheetKeys, kbFlashSyncKeys, kbMultiSelect, kbOpenLink, kbDropModifiers,
         kbEditorTab, kbEditorReturn, kbEditorBackspace, kbDeleteWord, kbTextNavigation, kbEscapeInRichText,
         kbOvertype, kbResetFormat, kbSireBodyKeys, kbLockedText, kbAccessKeys, kbContextMenuKey, kbAltF4, kbCtrlTab,
         kbPopUpKeys, kbTypeAhead

    /// The View-menu section commands by 1-based display position.
    public static let sectionCommands: [CommandID] = [.section1, .section2, .section3, .section4, .section5,
                                                       .section6, .section7, .section8, .section9, .section10,
                                                       .section11, .section12, .section13]

    /// 0-based display position for `.section1…13`.
    public var sectionPosition: Int? { CommandID.sectionCommands.firstIndex(of: self) }

    /// True for rows that are not menu items (§6.5.1.4).
    public var isInWindowKey: Bool { rawValue.hasPrefix("kb") }
}
