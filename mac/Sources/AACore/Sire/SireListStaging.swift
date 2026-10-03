// Spec: 12 SIRE-014/015 (the question list shows the filtered questions in sort order; the selection survives a
//       re-filter), §6.2 (`List(selection:)`); design rule 18 (no AppKit/SwiftUI runtime warning on any section).
//       Stage V round 2 findings V2-J7 / V2-DESIGN: AppKit logged "Application performed a reentrant operation in its
//       NSTableView delegate. This warning will become an assert in the future." whenever the question list filled.
import Foundation

/// A row of the SIRE question `List`: the element plus an identity that changes when the list is rebuilt.
public struct SireStagedRow<Element: Identifiable>: Identifiable where Element.ID: Hashable {
    public struct Key: Hashable {
        public let generation: Int
        public let id: Element.ID
    }
    public let id: Key
    public let element: Element
}

extension SireStagedRow: Sendable where Element: Sendable, Element.ID: Sendable {}
extension SireStagedRow.Key: Sendable where Element.ID: Sendable {}

/// What the SIRE question `List` shows, and how a new filter result reaches it.
///
/// Measured on macOS 27 (Stage V round 2, lldb on `NSLog`; 410-question bank, self-sizing rows): SwiftUI hands a
/// changed list to NSTableView as one insert/remove diff, and when that diff INSERTS rows the table's row-height
/// estimation (`-[NSTableRowHeightData _cacheRowSpansInRange:]`) can re-enter itself through `_updateTableViewSize`,
/// which AppKit reports as the reentrant-delegate warning. It warned for 0 → 250/410 rows, 24 → 410, 410 → 198
/// (Equipment) → 148 (Document) and search "valve" (106) → "alarm" (99); it stayed silent for 0 → 40, 0 → 200,
/// pure removals (410 → 24 / 49 / 198), re-sorts, and appending rows after a measured contiguous block (40 → 410).
///
/// So a publish that only removes or re-orders rows is a plain diff, and a publish that ADDS rows rebuilds the list:
/// every row gets a new identity (`generation`), so the table drops the old rows and inserts the new ones as one
/// contiguous block from row 0 — and when there are more than `seed` of them, only the first `seed` go in first; the
/// host calls `reveal()` on a later run-loop turn to append the rest after the measured block. A rebuild scrolls the
/// list back to the top, as the Windows `ListBox` does when `ApplyFilters` swaps its `ItemsSource`; the selection is
/// kept by the host (SIRE-015), because selection tags are the element ids, not the row identities.
public struct SireStagedRows<Element: Identifiable> where Element.ID: Hashable {
    /// Rows the first step of a rebuild publishes (inside the measured silent 0 → 200; more than a screenful).
    public static var defaultSeed: Int { 40 }

    /// What the list shows now.
    public private(set) var rows: [Element] = []
    /// The complete list waiting for `reveal()` (nil when `rows` is complete).
    public private(set) var pending: [Element]?
    /// Bumped by every rebuild; part of each row's identity.
    public private(set) var generation = 0
    public let seed: Int

    public init(seed: Int = SireStagedRows.defaultSeed) { self.seed = max(1, seed) }

    /// The rows with their identities, for `ForEach`.
    public var keyed: [SireStagedRow<Element>] {
        let g = generation
        return rows.map { SireStagedRow(id: SireStagedRow.Key(generation: g, id: $0.id), element: $0) }
    }

    /// The identity of the row showing `id` (for `ScrollViewProxy.scrollTo`).
    public func key(for id: Element.ID) -> SireStagedRow<Element>.Key {
        SireStagedRow.Key(generation: generation, id: id)
    }

    /// Publishes `list`. Returns true when only the first `seed` rows went in and the caller must call `reveal()` on
    /// a later run-loop turn. A publish supersedes any pending one.
    @discardableResult
    public mutating func publish(_ list: [Element]) -> Bool {
        let shown = Set(rows.map(\.id))
        let adds = list.contains { !shown.contains($0.id) }
        guard adds else {                                       // removals / re-order: a plain diff
            rows = list
            pending = nil
            return false
        }
        generation += 1
        if list.count > seed {
            rows = Array(list.prefix(seed))
            pending = list
            return true
        }
        rows = list
        pending = nil
        return false
    }

    /// Completes a staged publish by appending the rest (no-op when nothing is pending, e.g. a later publish already
    /// superseded it). Returns true when rows were added.
    @discardableResult
    public mutating func reveal() -> Bool {
        guard let p = pending else { return false }
        rows = p
        pending = nil
        return true
    }

    public var isStaged: Bool { pending != nil }
}

extension SireStagedRows: Sendable where Element: Sendable, Element.ID: Sendable {}
