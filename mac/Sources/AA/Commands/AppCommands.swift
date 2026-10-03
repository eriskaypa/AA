// Spec: 03 §6.5.1.6 (final menu bar), §6.5.1.13 (SwiftUI Commands construction: replaced groups, Format menu built
//       explicitly, Tools menu, SidebarCommands / ToolbarCommands, Help replaced), SHELL-508 (titles, static except
//       Undo/Redo/Delete/New), SHELL-511 (layout-aware keys), SHELL-522 (sections in display order, ⌘1…⌘9 follow
//       reordering, checkmark on the active one), SHELL-526; ARCHITECTURE.md §7.6.
import AppKit
import SwiftUI
import AACore

struct AppCommands: Commands {
    let coordinator: LaunchCoordinator

    /// Read through the observable coordinator by every item view, so menus update once the environment exists.
    private var router: CommandRouter? { nil }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) { ShellMenuItem(command: .about, router: router) }
        // AA ▸ Settings… (⌘,) is SwiftUI's own item for the Settings scene (replacing it would duplicate it).

        // File
        CommandGroup(replacing: .newItem) { nodes(menu: "File", from: 0, to: 2) }
        CommandGroup(after: .newItem) { nodes(menu: "File", from: 2, to: 6) }      // SwiftUI separates the groups
        CommandGroup(replacing: .saveItem) { nodes(menu: "File", from: 7, to: 28) }
        CommandGroup(replacing: .importExport) { nodes(menu: "File", from: 29, to: 30) }
        CommandGroup(replacing: .printItem) { nodes(menu: "File", from: 30, to: 31) }

        // Edit (the default pasteboard group stays: Cut, Copy, Paste, Paste and Match Style, Delete, Select All)
        CommandGroup(replacing: .undoRedo) {
            ShellMenuItem(command: .undo, router: router)
            ShellMenuItem(command: .redo, router: router)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            ShellMenuItem(command: .moveUp, router: router)
            ShellMenuItem(command: .moveDown, router: router)
            ShellMenuItem(command: .moveTo, router: router)
        }
        CommandGroup(replacing: .textEditing) {
            if case .submenu(let title, let sub) = findNode {
                Menu(title) { ShellMenuNodesView(nodes: sub, router: router) }
            }
        }
        // Format (explicit, never TextFormattingCommands — §6.5.1.3)
        CommandMenu("Format") {
            ShellMenuNodesView(nodes: ShellMenuTree.menu("Format")?.nodes ?? [], router: router)
        }

        // View
        CommandGroup(before: .toolbar) {
            ShellSectionMenuItems(router: router)
            ShellMenuItem(command: .previousSection, router: router)
            ShellMenuItem(command: .nextSection, router: router)
            Divider()
            ShellMenuItem(command: .plannerPrevious, router: router)
            ShellMenuItem(command: .plannerToday, router: router)
            ShellMenuItem(command: .plannerNext, router: router)
            Divider()
        }
        SidebarCommands()
        ToolbarCommands()
        CommandGroup(after: .sidebar) {
            ShellMenuItem(command: .shortcutBar, router: router)
            ShellMenuItem(command: .darkMode, router: router)
            ShellMenuItem(command: .tabColors, router: router)
        }

        // Tools (Windows order kept)
        CommandMenu("Tools") {
            ShellMenuNodesView(nodes: ShellMenuTree.menu("Tools")?.nodes ?? [], router: router)
        }

        // Help
        CommandGroup(replacing: .help) { ShellMenuItem(command: .keyboardShortcuts, router: router) }
    }

    private var findNode: ShellMenuNode? {
        ShellMenuTree.menu("Edit")?.nodes.first { if case .submenu("Find", _) = $0 { return true }; return false }
    }

    private func nodes(menu: String, from: Int, to: Int) -> ShellMenuNodesView {
        let all = ShellMenuTree.menu(menu)?.nodes ?? []
        let lo = min(from, all.count), hi = min(to, all.count)
        return ShellMenuNodesView(nodes: Array(all[lo..<hi]), router: router)
    }
}

/// Renders a slice of the menu tree (recursively for submenus).
struct ShellMenuNodesView: View {
    let nodes: [ShellMenuNode]
    let router: CommandRouter?

    var body: some View {
        ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in
            switch node {
            case .separator:
                Divider()
            case .item(let c):
                if c == .highlight {
                    ShellHighlightMenu(router: router)
                } else if !ShellMenuNodesView.systemProvided.contains(c) {
                    ShellMenuItem(command: c, router: router)
                }
            case .submenu(let title, let sub):
                Menu(title) { ShellMenuNodesView(nodes: sub, router: router) }
            case .sections:
                ShellSectionMenuItems(router: router)
            }
        }
    }

    /// Items AppKit / SwiftUI provide themselves (built elsewhere or kept from the defaults).
    static let systemProvided: Set<CommandID> = [.services, .hideApp, .hideOthers, .showAll, .cut, .copy, .paste,
        .pasteAndMatchStyle, .delete, .selectAll, .spellingAndGrammar, .checkDocumentNow, .substitutions,
        .transformations, .speech, .systemTextServices, .toggleSidebar, .toggleToolbar, .customizeToolbar,
        .fullScreen, .minimize, .zoom, .bringAllToFront, .helpSearch]
}

/// One registry command as a menu item: router title and enablement, registry key, SF Symbol, checkmark.
struct ShellMenuItem: View {
    let command: CommandID
    private let given: CommandRouter?
    private var router: CommandRouter? { given ?? LaunchCoordinator.shared.env?.router }

    init(command: CommandID, router: CommandRouter?) {
        self.command = command
        given = router
    }

    static let checkable: Set<CommandID> = [.encryptLocalData, .exportTextOnly, .driveSyncOnSave, .shortcutBar, .darkMode]

    var body: some View {
        let row = ShortcutRegistry.row(command)
        let d = router?.decision(command)
            ?? CommandDecision(enabled: command == .about || command == .quit, title: ShortcutRegistry.title(command))
        let item = Group {
            if ShellMenuItem.checkable.contains(command) || command.sectionPosition != nil {
                Toggle(isOn: Binding(get: { d.checked }, set: { _ in perform() })) {
                    label(d.title, symbol: command.sectionPosition == nil ? row?.symbol : nil)
                }
            } else {
                Button { perform() } label: { label(d.title, symbol: row?.symbol) }
            }
        }
        .disabled(!d.enabled)
        if let chord = row?.chord, let key = ShellKeyMapping.keyEquivalent(chord.key) {
            item.keyboardShortcut(key, modifiers: ShellKeyMapping.modifiers(chord.modifiers))
        } else {
            item
        }
    }

    @ViewBuilder private func label(_ title: String, symbol: String?) -> some View {
        if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
    }

    private func perform() {
        if let router { router.perform(command) } else if command == .quit { NSApp.terminate(nil) }
        else if command == .about { SceneOpener.shared.open(.about) }
    }
}

/// View ▸ {13 sections}: display order, ⌘1…⌘9 on positions 1–9 (SHELL-522).
struct ShellSectionMenuItems: View {
    private let given: CommandRouter?
    private var router: CommandRouter? { given ?? LaunchCoordinator.shared.env?.router }
    init(router: CommandRouter?) { given = router }

    var body: some View {
        let order = router?.env?.navigator.sectionOrder ?? SectionID.defaultOrder
        ForEach(Array(order.enumerated()), id: \.element) { i, s in
            if i < CommandID.sectionCommands.count {
                ShellMenuItem(command: CommandID.sectionCommands[i], router: router)
            }
        }
    }
}

/// Format ▸ Font ▸ Highlight ▸ {swatches…, No Highlight, Other…}.
struct ShellHighlightMenu: View {
    private let given: CommandRouter?
    private var router: CommandRouter? { given ?? LaunchCoordinator.shared.env?.router }
    init(router: CommandRouter?) { given = router }

    var body: some View {
        let enabled = router?.decision(.highlight).enabled ?? false
        Menu {
            ForEach(CommandRouter.highlightSwatches, id: \.name) { swatch in
                Button { router?.performHighlight(swatch.color) } label: {
                    Label { Text(swatch.name) } icon: {
                        Image(nsImage: ShellSwatchImage.make(AAColor.ns(swatch.color)))
                    }
                }
            }
            Divider()
            Button("No Highlight") { router?.performHighlight(nil) }
            Button("Other…") { router?.performHighlight(nil, other: true) }
        } label: {
            Label("Highlight", systemImage: "highlighter")
        }
        .disabled(!enabled)
    }
}

/// A small rounded colour swatch image for menus.
enum ShellSwatchImage {
    @MainActor static func make(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let img = NSImage(size: size, flipped: false) { rect in
            let p = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            color.setFill(); p.fill()
            NSColor.separatorColor.setStroke(); p.lineWidth = 1; p.stroke()
            return true
        }
        return img
    }
}

/// Registry key names → SwiftUI key equivalents (layout-aware via the default `.automatic` localization).
enum ShellKeyMapping {
    static func keyEquivalent(_ key: String) -> KeyEquivalent? {
        switch key {
        case "delete": return .delete
        case "forwardDelete": return .deleteForward
        case "return": return .return
        case "escape": return .escape
        case "tab": return .tab
        case "space": return .space
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "up": return .upArrow
        case "down": return .downArrow
        default:
            if key.hasPrefix("F"), let n = Int(key.dropFirst()), (1...20).contains(n),
               let scalar = UnicodeScalar(UInt32(NSF1FunctionKey) + UInt32(n - 1)) {
                return KeyEquivalent(Character(scalar))
            }
            guard key.count == 1, let c = key.first else { return nil }
            return KeyEquivalent(c)
        }
    }

    static func modifiers(_ names: [String]) -> EventModifiers {
        var m: EventModifiers = []
        for n in names {
            switch n {
            case "command": m.insert(.command)
            case "shift": m.insert(.shift)
            case "option": m.insert(.option)
            case "control": m.insert(.control)
            default: break
            }
        }
        return m
    }
}
