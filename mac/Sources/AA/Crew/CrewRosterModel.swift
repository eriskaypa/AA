// Spec: 09 §B CREW-012…018 (per-page roster state: search, Expiring-only toggle — not persisted, survives reloads —,
//       selection by Key, status line overwritten by the import summary until the next refresh — tab selection and
//       every data reload refresh, §3.7), CREW-005 (navigate in),
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
    @ObservationIgnored private weak var attachedStore: AppStore?
    @ObservationIgnored private var replaceSubscription: EventSubscription?

    /// §3.7: `Init → Refresh()` runs on every data (re)load, so a reload ends the import summary (CREW-016/038).
    /// The search text and the Expiring-only toggle survive (CREW-014); the selection is re-kept by Key (CREW-017).
    func attach(_ store: AppStore) {
        guard attachedStore !== store else { return }
        attachedStore = store
        keyLookup = { [weak store] id in store?.crewMember(id: id)?.key }
        replaceSubscription = store.dataReplaced.subscribe { [weak self] _ in self?.dataReplaced() }
    }

    /// CREW-001 / §3.7 Refresh: the day counts are recomputed and the import summary gives way to the status line.
    func refresh(today: CivilDate) {
        self.today = today
        statusOverride = nil
    }

    private func dataReplaced() {
        statusOverride = nil
    }

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
