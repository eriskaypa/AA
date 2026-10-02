// Spec: 03 §6.5.1.6 (final menu bar), §6.5.1.13 (menu construction), SHELL-525/526, DECISIONS R-70 (Recover Conflict
//       Copies… after Reload from Disk).
import Foundation

/// One entry of a menu in the final menu bar.
public indirect enum ShellMenuNode: Sendable, Equatable {
    case item(CommandID)
    case separator
    case submenu(String, [ShellMenuNode])
    /// The 13 section items in the current display order (SHELL-630).
    case sections
}

public struct ShellMenu: Sendable, Equatable {
    public let title: String
    public let nodes: [ShellMenuNode]
    /// True when AppKit/SwiftUI build the menu themselves (Window).
    public let isSystem: Bool
}

/// The menu bar of 03 §6.5.1.6 as data: the AppKit/SwiftUI menu construction and the menu-tree test read it.
public enum ShellMenuTree {
    public static let menus: [ShellMenu] = [
        ShellMenu(title: "AA", nodes: [
            .item(.about), .separator, .item(.settings), .separator, .item(.services), .separator,
            .item(.hideApp), .item(.hideOthers), .item(.showAll), .separator, .item(.quit),
        ], isSystem: false),
        ShellMenu(title: "File", nodes: [
            .item(.newItem), .item(.openInNewWindow), .separator,
            .item(.rename), .item(.quickLook), .item(.deleteFamily), .separator,
            .item(.close), .item(.save), .item(.saveCopyAs), .item(.reloadFromDisk), .item(.recoverConflictCopies),
            .item(.importFromFile), .separator,
            .item(.trash), .item(.encryptLocalData), .separator,
            .submenu("Shared Save", [.item(.setSharedSaveFile), .item(.stopSharedSaveFile), .separator,
                                     .item(.checkSharedSaveNow)]),
            .item(.setAppIdentity), .separator,
            .item(.openDataFolder), .item(.exportDataFolder), .item(.importDataFolder), .item(.exportTextOnly), .separator,
            .submenu("Google Drive", [.item(.driveSaveCopy), .item(.driveSetFolder), .separator,
                                      .item(.driveUpload), .item(.driveLoad), .item(.driveSetOAuthClient),
                                      .item(.driveSignOut), .separator,
                                      .item(.driveSyncOnSave), .item(.driveCheckNewer)]),
            .separator, .item(.flashSync), .separator, .item(.exportPDF), .item(.print),
        ], isSystem: false),
        ShellMenu(title: "Edit", nodes: [
            .item(.undo), .item(.redo), .separator,
            .item(.cut), .item(.copy), .item(.paste), .item(.pasteAndMatchStyle), .item(.delete), .item(.selectAll),
            .separator,
            .item(.moveUp), .item(.moveDown), .item(.moveTo), .separator,
            .submenu("Find", [.item(.find), .item(.searchAll), .item(.searchCurrentList), .separator,
                              .item(.findNext), .item(.findPrevious), .item(.useSelectionForFind),
                              .item(.jumpToSelection)]),
            .submenu("Spelling and Grammar", [.item(.spellingAndGrammar), .item(.checkDocumentNow)]),
            .item(.substitutions), .item(.transformations), .item(.speech),
        ], isSystem: false),
        ShellMenu(title: "Format", nodes: [
            .submenu("Font", [.item(.showFonts), .separator,
                              .item(.bold), .item(.italic), .item(.underline), .item(.strikethrough), .separator,
                              .item(.bigger), .item(.smaller), .separator,
                              .submenu("Baseline", [.item(.baselineDefault), .item(.superscript), .item(.subscript)]),
                              .separator, .item(.showColors), .item(.highlight)]),
            .submenu("Text", [.item(.alignLeft), .item(.center), .item(.justify), .item(.alignRight)]),
            .submenu("Lists", [.item(.bulletedList), .item(.numberedList), .separator, .item(.indent), .item(.outdent)]),
            .submenu("Insert", [.item(.insertLink), .item(.insertTable), .item(.insertSavedList)]),
            .separator, .item(.clearFormatting), .separator, .item(.lockSelection), .item(.unlockSelection),
        ], isSystem: false),
        ShellMenu(title: "View", nodes: [
            .sections, .item(.previousSection), .item(.nextSection), .separator,
            .item(.plannerPrevious), .item(.plannerToday), .item(.plannerNext), .separator,
            .item(.toggleSidebar), .item(.toggleToolbar), .item(.customizeToolbar),
            .item(.shortcutBar), .item(.darkMode), .item(.tabColors), .separator,
            .item(.fullScreen),
        ], isSystem: false),
        ShellMenu(title: "Tools", nodes: [
            .item(.folderBuilder), .item(.dateCalculator), .item(.dueDates), .item(.quickWork), .item(.quickSwitcher),
            .item(.activityLog), .item(.unitConverter), .separator,
            .item(.importCompasCrew), .item(.checkCrewExpiries), .separator,
            .submenu("Vessel", [.item(.vesselImportWorkOrders), .item(.vesselExportWorkOrders), .separator,
                                .item(.vesselImportPorts), .item(.vesselExportPorts), .separator,
                                .item(.vesselNewQuickCard)]),
            .separator, .item(.sireExport), .item(.setGeminiKey), .separator,
            .item(.setPassword), .item(.lockNow),
        ], isSystem: false),
        ShellMenu(title: "Window", nodes: [.item(.minimize), .item(.zoom), .item(.bringAllToFront)], isSystem: true),
        ShellMenu(title: "Help", nodes: [.item(.helpSearch), .item(.keyboardShortcuts)], isSystem: false),
    ]

    public static func menu(_ title: String) -> ShellMenu? { menus.first { $0.title == title } }

    /// Every command that appears in the tree (sections excluded).
    public static var allCommands: [CommandID] {
        func walk(_ nodes: [ShellMenuNode]) -> [CommandID] {
            nodes.flatMap { n -> [CommandID] in
                switch n {
                case .item(let c): return [c]
                case .submenu(_, let sub): return walk(sub)
                case .separator, .sections: return []
                }
            }
        }
        return menus.flatMap { walk($0.nodes) }
    }

    /// A plain-text rendering (one line per entry, two spaces per level, `─` for separators, key after a tab),
    /// with the sections expanded in `order`.
    public static func render(order: [SectionID]) -> String {
        var lines: [String] = []
        func emit(_ nodes: [ShellMenuNode], depth: Int) {
            let pad = String(repeating: "  ", count: depth)
            for n in nodes {
                switch n {
                case .separator: lines.append(pad + "─")
                case .item(let c):
                    let r = ShortcutRegistry.row(c)
                    let key = r?.keyDisplay ?? ""
                    lines.append(pad + (r?.title ?? c.rawValue) + (key.isEmpty ? "" : "\t" + key))
                case .submenu(let t, let sub):
                    lines.append(pad + t + " ▸")
                    emit(sub, depth: depth + 1)
                case .sections:
                    for (i, s) in order.enumerated() {
                        lines.append(pad + s.title + (i < 9 ? "\t⌘\(i + 1)" : ""))
                    }
                }
            }
        }
        for m in menus {
            lines.append(m.title)
            emit(m.nodes, depth: 1)
        }
        return lines.joined(separator: "\n")
    }
}
