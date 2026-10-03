// Spec: 03 §6.5.1.6 (final menu bar: View = sections, Previous/Next Section, ─, Planner, ─, Show/Hide Sidebar,
//       Hide/Show Toolbar · Customize Toolbar…, Shortcut Bar · Dark Mode · Customize Tab Colors…, ─, Enter Full
//       Screen; File = … ─ Export as PDF… · Print…), §6.5.1.13 (the AppKit bridge re-orders after SwiftUI rebuilds).
import Foundation

/// Pure re-ordering of SwiftUI-built menus into the §6.5.1.6 tree (the bridge is F3's `AppKitMenuBridge`).
public enum ShellMenuOrder {
    public enum Entry: Sendable, Equatable {
        case item(String)
        case separator
        /// View ▸ Enter / Exit Full Screen (`toggleFullScreen:`; AppKit retitles it).
        case fullScreen
    }

    static let viewAnchor = "Shortcut Bar"

    /// SwiftUI's sidebar / toolbar items, in tree order (sidebar first, then toolbar, then Customize Toolbar…).
    static func standardRank(_ title: String) -> Int? {
        switch title {
        case "Show Sidebar", "Hide Sidebar": return 0
        case "Show Toolbar", "Hide Toolbar": return 1
        case "Customize Toolbar…": return 2
        default: return nil
        }
    }

    /// The View menu as indices into `items`; `nil` = a new separator. The sidebar / toolbar items go right before
    /// "Shortcut Bar"; Enter Full Screen goes last, after a separator; doubled, leading and trailing separators are
    /// dropped. Without "Shortcut Bar" the menu is returned unchanged (SwiftUI has not built it yet).
    public static func viewMenu(_ items: [Entry]) -> [Int?] {
        guard let anchor = items.firstIndex(of: .item(viewAnchor)) else { return items.indices.map { $0 } }
        var standard: [(rank: Int, index: Int)] = []
        var fullScreen: [Int] = []
        for (i, e) in items.enumerated() {
            switch e {
            case .item(let t): if let r = standardRank(t) { standard.append((r, i)) }
            case .fullScreen: fullScreen.append(i)
            case .separator: break
            }
        }
        let moved = Set(standard.map(\.index) + fullScreen)
        let orderedStandard = standard.enumerated().sorted { a, b in
            a.element.rank != b.element.rank ? a.element.rank < b.element.rank : a.offset < b.offset
        }.map(\.element.index)
        var out: [Int?] = []
        for i in items.indices where !moved.contains(i) {
            if i == anchor { out.append(contentsOf: orderedStandard.map { Optional($0) }) }
            out.append(i)
        }
        if !fullScreen.isEmpty {
            out.append(nil)
            out.append(contentsOf: fullScreen.map { Optional($0) })
        }
        return collapse(out) { idx in idx.map { items[$0] == .separator } ?? true }
    }

    /// The File menu: no separator between "Export as PDF…" and "Print…" (one group in the tree).
    public static func fileMenu(_ items: [Entry]) -> [Int?] {
        var out: [Int?] = []
        for (i, e) in items.enumerated() {
            if e == .separator, i > 0, items[i - 1] == .item("Export as PDF…"), i + 1 < items.count,
               items[i + 1] == .item("Print…") { continue }
            out.append(i)
        }
        return out
    }

    /// Drops doubled, leading and trailing separators.
    static func collapse(_ order: [Int?], isSeparator: (Int?) -> Bool) -> [Int?] {
        var out: [Int?] = []
        for o in order {
            if isSeparator(o), out.isEmpty || isSeparator(out.last!) { continue }
            out.append(o)
        }
        while let last = out.last, isSeparator(last) { out.removeLast() }
        return out
    }
}
