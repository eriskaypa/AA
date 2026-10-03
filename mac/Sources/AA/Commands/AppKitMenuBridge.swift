// Spec: 03 SHELL-508 (stable identifiers, NSMenuItem tooltips = Windows tooltips), SHELL-509 (the four hidden aliases:
//       ⇧⌘O, ⇧⌘V, ⌘=, ⌃⌘=), SHELL-522 (Crew badge on the View-menu item), §6.5.1.13 (an idempotent AppKit bridge that
//       re-applies after SwiftUI rebuilds the menu; Spelling / Substitutions / Transformations / Speech re-added),
//       SHELL-526 (no window tabbing items); ARCHITECTURE.md §7.6.
import AppKit
import AACore

/// Decorates the SwiftUI-built main menu: identifiers, tooltips, hidden aliases, badges and the standard text submenus.
@MainActor
final class AppKitMenuBridge: NSObject, NSMenuItemValidation {
    static let shared = AppKitMenuBridge()

    private var observers: [NSObjectProtocol] = []
    private var viewMenuProxy: ShellMenuDelegateProxy?
    private var scheduled = false
    private var applying = false

    func start() {
        guard observers.isEmpty else { return }
        let names: [Notification.Name] = [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification,
                                          NSMenu.didRemoveItemNotification, NSMenu.didBeginTrackingNotification]
        for n in names {
            observers.append(NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
        schedule()
    }

    private func schedule() {
        guard !scheduled, !applying else { return }
        scheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            self?.scheduled = false
            self?.apply()
        }
    }

    /// Idempotent: safe to run after every SwiftUI menu rebuild.
    func apply() {
        guard let main = NSApp.mainMenu else { return }
        applying = true
        defer { applying = false }
        for top in main.items {
            guard let menu = top.submenu else { continue }
            decorate(menu, path: [top.title == ProcessInfo.processInfo.processName ? "AA" : top.title])
        }
        if let view = main.items.first(where: { $0.title == "View" })?.submenu {
            if !(view.delegate is ShellMenuDelegateProxy) {
                let proxy = ShellMenuDelegateProxy(original: view.delegate) { [weak self] m in self?.orderViewMenu(m) }
                viewMenuProxy = proxy
                view.delegate = proxy
            }
            orderViewMenu(view)
        }
        insertPasteAndMatchStyle(main)
        insertAliases(main)
        insertTextSubmenus(main)
        updateCrewBadge(main)
    }

    // MARK: Identifiers and tooltips

    private func decorate(_ menu: NSMenu, path: [String]) {
        for item in menu.items {
            if let sub = item.submenu {
                decorate(sub, path: path + [item.title])
                continue
            }
            guard !item.isSeparatorItem, item.identifier?.rawValue.hasPrefix("aa.alias.") != true else { continue }
            if let row = match(item, path: path) {
                let ident = NSUserInterfaceItemIdentifier(row.itemIdentifier)
                if item.identifier != ident { item.identifier = ident }
                // DATA-174: a gated command carries its own help ("Not available in a read-only copy of AA.").
                let gatedHelp = LaunchCoordinator.shared.env?.router.decision(row.command).help
                if let tip = gatedHelp ?? row.help, !tip.isEmpty, item.toolTip != tip { item.toolTip = tip }
            }
        }
    }

    /// Matches a built item to its registry row by menu path + title, or by key equivalent for dynamic titles.
    private func match(_ item: NSMenuItem, path: [String]) -> ShortcutRow? {
        let menuName = path.first ?? ""
        let candidates = ShortcutRegistry.rows.filter { $0.isMenuItem && $0.menuPath.first == menuName }
        if let r = candidates.first(where: { $0.title == item.title }) { return r }
        let key = item.keyEquivalent.lowercased()
        guard !key.isEmpty else { return nil }
        return candidates.first { r in
            guard let chord = r.chord else { return false }
            return ShellKeyMapping.keyEquivalent(chord.key).map { String($0.character).lowercased() } == key
        }
    }

    // MARK: View menu order (§6.5.1.6: sections, Previous/Next Section, Planner, then sidebar / toolbar / toggles)

    private func orderViewMenu(_ view: NSMenu) {
        guard let anchor = view.items.firstIndex(where: { $0.title == "Shortcut Bar" }) else { return }
        let standard = view.items.enumerated().filter { _, item in
            ["Show Toolbar", "Hide Toolbar", "Customize Toolbar…", "Show Sidebar", "Hide Sidebar"].contains(item.title)
        }
        guard let firstStandard = standard.first?.offset, firstStandard < anchor - standard.count else { return }
        // Keep sidebar before toolbar (Show/Hide Sidebar, Hide/Show Toolbar, Customize Toolbar…).
        let ordered = standard.map(\.element).sorted { a, b in
            func rank(_ t: String) -> Int { t.contains("Sidebar") ? 0 : (t.contains("Customize") ? 2 : 1) }
            return rank(a.title) < rank(b.title)
        }
        for item in ordered { view.removeItem(item) }
        guard var at = view.items.firstIndex(where: { $0.title == "Shortcut Bar" }) else { return }
        for item in ordered {
            view.insertItem(item, at: at)
            at += 1
        }
        // Collapse separators that ended up doubled or leading.
        var i = 0
        while i < view.items.count {
            let sep = view.items[i].isSeparatorItem
            let prevSep = i == 0 || view.items[i - 1].isSeparatorItem
            if sep && prevSep { view.removeItem(at: i) } else { i += 1 }
        }
    }

    // MARK: Paste and Match Style (SHELL-578; SwiftUI's pasteboard group omits it)

    private func insertPasteAndMatchStyle(_ main: NSMenu) {
        guard let edit = main.items.first(where: { $0.title == "Edit" })?.submenu,
              findItem(edit, identifier: "aa.cmd.pasteAndMatchStyle") == nil,
              let paste = edit.items.firstIndex(where: { $0.title == "Paste" }) else { return }
        let item = NSMenuItem(title: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)),
                              keyEquivalent: "v")
        item.keyEquivalentModifierMask = [.option, .shift, .command]
        item.identifier = NSUserInterfaceItemIdentifier("aa.cmd.pasteAndMatchStyle")
        edit.insertItem(item, at: paste + 1)
    }

    // MARK: Hidden aliases (SHELL-509)

    private func insertAliases(_ main: NSMenu) {
        for row in ShortcutRegistry.rows where row.isMenuItem && !row.aliases.isEmpty {
            guard let owner = findItem(main, identifier: row.itemIdentifier) ?? findItem(main, title: row.title),
                  let menu = owner.menu else { continue }
            for alias in row.aliasChords {
                let ident = NSUserInterfaceItemIdentifier("aa.alias.\(row.command.rawValue).\(alias.description)")
                if menu.items.contains(where: { $0.identifier == ident }) { continue }
                guard let key = ShellKeyMapping.keyEquivalent(alias.key) else { continue }
                let item = NSMenuItem(title: row.title, action: #selector(performAlias(_:)), keyEquivalent: String(key.character))
                item.keyEquivalentModifierMask = Self.mask(alias.modifiers)
                item.identifier = ident
                item.isHidden = true
                item.allowsKeyEquivalentWhenHidden = true
                item.target = self
                item.representedObject = row.command.rawValue
                if row.command == .pasteAndMatchStyle {                 // nil-targeted like the visible item
                    item.action = #selector(NSTextView.pasteAsPlainText(_:))
                    item.target = nil
                }
                let index = menu.index(of: owner)
                menu.insertItem(item, at: index + 1)
            }
        }
    }

    static func mask(_ names: [String]) -> NSEvent.ModifierFlags {
        var m: NSEvent.ModifierFlags = []
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

    @objc func performAlias(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let c = CommandID(rawValue: raw) else { return }
        LaunchCoordinator.shared.env?.router.perform(c)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let raw = item.representedObject as? String, let c = CommandID(rawValue: raw),
              let router = LaunchCoordinator.shared.env?.router else { return false }
        return router.decision(c).enabled
    }

    // MARK: Standard text submenus (§6.5.1.13: re-add Spelling, Substitutions, Transformations, Speech)

    private func insertTextSubmenus(_ main: NSMenu) {
        guard let edit = main.items.first(where: { $0.title == "Edit" })?.submenu,
              edit.items.first(where: { $0.identifier?.rawValue == "aa.edit.spelling" }) == nil else { return }
        let findIndex = edit.items.firstIndex { $0.title == "Find" } ?? (edit.items.count - 1)
        var at = findIndex + 1
        for (ident, title, items) in Self.textSubmenus {
            let sub = NSMenu(title: title)
            for (t, sel, key) in items {
                let mi = NSMenuItem(title: t, action: sel, keyEquivalent: key)
                if key == ":" { mi.keyEquivalentModifierMask = [.command] }
                sub.addItem(mi)
            }
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.identifier = NSUserInterfaceItemIdentifier(ident)
            holder.submenu = sub
            edit.insertItem(holder, at: min(at, edit.items.count))
            at += 1
        }
    }

    static let textSubmenus: [(String, String, [(String, Selector, String)])] = [
        ("aa.edit.spelling", "Spelling and Grammar", [
            ("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":"),
            ("Check Document Now", #selector(NSText.checkSpelling(_:)), ";"),
            ("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:)), ""),
            ("Check Grammar With Spelling", #selector(NSTextView.toggleGrammarChecking(_:)), ""),
            ("Correct Spelling Automatically", #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)), ""),
        ]),
        ("aa.edit.substitutions", "Substitutions", [
            ("Show Substitutions", #selector(NSTextView.orderFrontSubstitutionsPanel(_:)), ""),
            ("Smart Copy/Paste", #selector(NSTextView.toggleSmartInsertDelete(_:)), ""),
            ("Smart Quotes", #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)), ""),
            ("Smart Dashes", #selector(NSTextView.toggleAutomaticDashSubstitution(_:)), ""),
            ("Smart Links", #selector(NSTextView.toggleAutomaticLinkDetection(_:)), ""),
            ("Data Detectors", #selector(NSTextView.toggleAutomaticDataDetection(_:)), ""),
            ("Text Replacement", #selector(NSTextView.toggleAutomaticTextReplacement(_:)), ""),
        ]),
        ("aa.edit.transformations", "Transformations", [
            ("Make Upper Case", #selector(NSResponder.uppercaseWord(_:)), ""),
            ("Make Lower Case", #selector(NSResponder.lowercaseWord(_:)), ""),
            ("Capitalize", #selector(NSResponder.capitalizeWord(_:)), ""),
        ]),
        ("aa.edit.speech", "Speech", [
            ("Start Speaking", #selector(NSTextView.startSpeaking(_:)), ""),
            ("Stop Speaking", #selector(NSTextView.stopSpeaking(_:)), ""),
        ]),
    ]

    // MARK: Crew badge (SHELL-522)

    private func updateCrewBadge(_ main: NSMenu) {
        guard let env = LaunchCoordinator.shared.env, env.mainLoaded,
              let view = main.items.first(where: { $0.title == "View" })?.submenu,
              let crew = view.items.first(where: { $0.title == SectionID.crew.title }) else { return }
        let n = CrewExpiry.expiringCount(env.store.data.crew, today: env.clock.today())
        let badge: NSMenuItemBadge? = n > 0 ? NSMenuItemBadge(count: n) : nil
        if crew.badge?.itemCount != badge?.itemCount { crew.badge = badge }
    }

    // MARK: Lookup and dump

    private func findItem(_ menu: NSMenu, identifier: String) -> NSMenuItem? {
        for item in menu.items {
            if item.identifier?.rawValue == identifier { return item }
            if let sub = item.submenu, let found = findItem(sub, identifier: identifier) { return found }
        }
        return nil
    }

    private func findItem(_ menu: NSMenu, title: String) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title, item.submenu == nil { return item }
            if let sub = item.submenu, let found = findItem(sub, title: title) { return found }
        }
        return nil
    }

    /// A text rendering of the live menu bar (debug / verification).
    static func dump() -> String {
        var lines: [String] = []
        func walk(_ menu: NSMenu, depth: Int) {
            menu.delegate?.menuNeedsUpdate?(menu)            // what AppKit does when the menu opens
            menu.update()
            for item in menu.items {
                let pad = String(repeating: "  ", count: depth)
                if item.isSeparatorItem { lines.append(pad + "─"); continue }
                var key = ""
                if !item.keyEquivalent.isEmpty {
                    let m = item.keyEquivalentModifierMask
                    key = (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "")
                        + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "") + item.keyEquivalent
                }
                let flags = (item.isHidden ? " [hidden]" : "") + (item.isEnabled ? "" : " [disabled]")
                    + (item.state == .on ? " ✓" : "")
                lines.append(pad + item.title + (key.isEmpty ? "" : "\t" + key) + flags)
                if let sub = item.submenu { walk(sub, depth: depth + 1) }
            }
        }
        if let main = NSApp.mainMenu {
            for top in main.items {
                lines.append(top.title)
                if let sub = top.submenu { walk(sub, depth: 1) }
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Forwards SwiftUI's menu delegate and re-applies a fix-up after every `menuNeedsUpdate` (menus are rebuilt on open).
final class ShellMenuDelegateProxy: NSObject, NSMenuDelegate, @unchecked Sendable {
    private weak var original: NSMenuDelegate?
    private let fixUp: @MainActor (NSMenu) -> Void

    init(original: NSMenuDelegate?, fixUp: @escaping @MainActor (NSMenu) -> Void) {
        self.original = original
        self.fixUp = fixUp
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        original?.menuNeedsUpdate?(menu)
        MainActor.assumeIsolated { fixUp(menu) }
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return original?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let o = original, o.responds(to: aSelector) { return o }
        return super.forwardingTarget(for: aSelector)
    }
}
