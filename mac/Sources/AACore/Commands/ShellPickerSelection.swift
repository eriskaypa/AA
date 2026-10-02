// Spec: 07 VIEW-208 (selection order: pre-selection in candidate order, ticks append, re-tick moves to the end),
//       VIEW-210 (Mac: selections survive filtering, hidden ones keep their place, footer texts, ⌘A appends visible),
//       VIEW-211 (single mode: one choice, survives filtering, OK disabled until chosen), VIEW-215 (rows not offered are
//       dropped), VIEW-216 (rows identified by candidate index), 04 HIER-131 (trimmed ordinal-ignore-case filter).
import Foundation

/// The item picker's selection model over candidate indices (pure; the sheet is F3's `ItemPickerSheet`).
public struct ShellPickerSelection: Sendable, Equatable {
    public let displays: [String]
    public let single: Bool
    /// The ordered selection sequence (candidate indices, no duplicates).
    public private(set) var order: [Int]
    public var query: String = ""

    /// `preselected` = indices whose tag is in the caller's preselect set (any order). Multi: all, in candidate order;
    /// single: the first in candidate order.
    public init(displays: [String], preselected: Set<Int>, single: Bool) {
        self.displays = displays
        self.single = single
        let pre = displays.indices.filter { preselected.contains($0) }
        order = single ? Array(pre.prefix(1)) : pre
    }

    /// Indices shown for the current query (trimmed; `Display` contains it, ordinal ignore-case; empty → all).
    public var visible: [Int] {
        let q = NetText.trim(query)
        if q.isEmpty { return Array(displays.indices) }
        return displays.indices.filter { NetText.containsIgnoreCase(displays[$0], q) }
    }

    public func isSelected(_ i: Int) -> Bool { order.contains(i) }

    /// Multi: toggle (untick removes, tick appends at the end). Single: replace the choice (choosing the chosen row
    /// keeps it).
    public mutating func toggle(_ i: Int) {
        guard displays.indices.contains(i) else { return }
        if single {
            order = [i]
            return
        }
        if let p = order.firstIndex(of: i) { order.remove(at: p) } else { order.append(i) }
    }

    /// ⌘A (multi only): append every visible, not-yet-selected row in display order.
    public mutating func selectAllVisible() {
        guard !single else { return }
        for i in visible where !order.contains(i) { order.append(i) }
    }

    public var selectedCount: Int { order.count }
    public var hiddenSelectedCount: Int {
        let v = Set(visible)
        return order.filter { !v.contains($0) }.count
    }

    /// VIEW-210 footer: `"{n} selected"` / `"{n} selected · {k} hidden by search"`.
    public var footer: String {
        let k = hiddenSelectedCount
        return k > 0 ? "\(order.count) selected · \(k) hidden by search" : "\(order.count) selected"
    }

    /// VIEW-211: OK is disabled until a row is chosen in single mode; always enabled in multi mode.
    public var canConfirm: Bool { single ? !order.isEmpty : true }

    /// The result in selection order, or in candidate order for `candidateOrder` callers (VIEW-212 row 23).
    public func result(candidateOrder: Bool) -> [Int] { candidateOrder ? order.sorted() : order }
}
