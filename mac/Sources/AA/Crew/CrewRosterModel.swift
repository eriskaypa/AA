// Spec: 09 §B CREW-012…018 (per-page roster state: search, Expiring-only toggle — not persisted, survives reloads —,
//       selection by Key, status line overwritten by the import summary until the next refresh), CREW-005 (navigate in),
//       CREW-015 (sort mode in Ui.CrewSortMode), §8 Q15 (Mac: refresh at day rollover); ARCHITECTURE.md §2.4 (hold ids,
//       never model references), §8.2 (expiry colours are the fixed semantic tokens).
import AppKit
import SwiftUI
import AACore

/// What the Crew page remembers between renders (one main window → one Crew page, shared with `CrewActions`).
@MainActor @Observable
final class CrewRosterModel {
    static let shared = CrewRosterModel()

    var query = "" { didSet { if query != oldValue { statusOverride = nil } } }
    var expiringOnly = false { didSet { if expiringOnly != oldValue { statusOverride = nil } } }
    /// The selected member's id (re-resolved through the store on every use).
    var selectedID: UUID? { didSet { if let id = selectedID, let key = keyLookup?(id) { selectedKey = key } } }
    /// The Key remembered before a refresh (CREW-017).
    private(set) var selectedKey: String?
    /// CREW-038: the import summary replaces the status line until the next refresh.
    var statusOverride: String?
    /// The COMPAS import is running (replaces the wait cursor, 09 §6.4).
    var importing = false
    /// Today's date (refreshed on selection of the tab and at day rollover, 09 §8 Q15).
    var today: CivilDate = SystemClock().today()
    /// The editor sheet request (CREW-070).
    var editor: CrewEditorRequest?
    /// A member to scroll to after a navigation / import.
    var scrollTarget: UUID?

    @ObservationIgnored var keyLookup: ((UUID) -> String?)?

    /// CREW-017: keeps the selection on the remembered key, else the first row, else nothing.
    func reconcile(rows: [CrewRosterRow]) {
        if let id = selectedID, rows.contains(where: { $0.id == id }) { return }
        let next = CrewRoster.selection(after: rows, keepKey: selectedID == nil ? nil : selectedKey)
        if selectedID != next { selectedID = next }
    }

    /// CREW-005 / CREW-074: clear the filters (navigation only) and select the member by id, else by key.
    func select(memberID: UUID, key: String?, clearFilters: Bool) {
        if clearFilters {
            if expiringOnly { expiringOnly = false }
            if !query.isEmpty { query = "" }
        }
        selectedKey = key
        selectedID = memberID
        scrollTarget = memberID
    }

    func open(_ tab: CrewEditorTab, for memberID: UUID) {
        editor = CrewEditorRequest(memberID: memberID, tab: tab)
    }
}

/// Which tab the editor opens on.
enum CrewEditorTab: Hashable { case details, checklist, schedule }

struct CrewEditorRequest: Identifiable, Equatable {
    let id = UUID()
    let memberID: UUID
    let tab: CrewEditorTab
}

/// The five fixed contract colours and the three flag severities (identical in both appearances, CREW-024/051).
enum CrewPalette {
    static func color(_ tone: CrewExpiryTone) -> Color {
        switch tone {
        case .neutral: return AAColor.Status.neutral
        case .red: return AAColor.Status.danger
        case .orange: return AAColor.Status.dueSoon
        case .amber: return AAColor.Status.warning
        case .green: return AAColor.Status.ok
        }
    }

    static func color(_ s: CrewFlagSeverity) -> Color {
        switch s {
        case .error: return AAColor.Status.danger
        case .warning: return AAColor.Status.dueSoon
        default: return AAColor.Status.neutral
        }
    }

    static func severityName(_ s: CrewFlagSeverity) -> String {
        switch s {
        case .error: return "Error"
        case .warning: return "Warning"
        default: return "Info"
        }
    }
}

/// Saves the store the way Windows' `Save()` did, reporting a failure through the shell (ARCH §9.1).
@MainActor enum CrewPersist {
    static func save(_ env: AppEnvironment) {
        do { try env.store.save() } catch { env.reportError(error, context: "Crew") }
    }

    static func flush(_ env: AppEnvironment) {
        do { try env.store.flushIfDirty() } catch { env.reportError(error, context: "Crew") }
    }
}

/// ⌥⌘F for the Crew section: focuses the roster search field (SHELL-517 table).
@MainActor enum CrewSearchFocus {
    static func focus() {
        guard let root = SceneOpener.shared.window(for: .main)?.contentView else { return }
        if let field = find(in: root) { field.window?.makeFirstResponder(field) }
    }

    private static func find(in view: NSView) -> NSSearchField? {
        if let f = view as? NSSearchField, f.placeholderString == CrewRoster.searchPrompt, !f.isHiddenOrHasHiddenAncestor {
            return f
        }
        for sub in view.subviews { if let f = find(in: sub) { return f } }
        return nil
    }
}

/// A wrapping row of controls (the WPF WrapPanel toolbars).
struct CrewFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += lineHeight + lineSpacing; lineHeight = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, s.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}
