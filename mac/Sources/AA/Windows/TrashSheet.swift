// Spec: 08 §2.6 (QUICK-170…178), §3.6, §6.2-F (a sheet on the main window, Table with multi-select, destructive
//       confirmations, Close / Esc); 02 REPO-078 (window), REPO-080 (permanent removal), §6.4 (Finder wording);
//       01 DATA-113; DECISIONS 02 Q-5 ("Put Back" / "Delete Immediately", "Restore" in tooltips); 03 SHELL-675
//       (in-sheet keys ⌘⌫ / ⌥⌘⌫ / ⇧⌘⌫), §6.5.1.5 (close-type sheet: ⌘W / ⎋ close); ARCHITECTURE.md §7.5, §7.7.
import AppKit
import SwiftUI
import AACore

/// The Trash (File ▸ Trash…): live list of `Data.Trash` in stored order (oldest deletion first, no sort).
struct TrashSheet: View {
    let onFinish: (() -> Void)?

    init(onFinish: (() -> Void)? = nil) { self.onFinish = onFinish }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<UUID>()
    @State private var busy = false

    private var entries: [TrashedItem] { env.store.data.trash }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)
            table
                .padding(.horizontal, 18)
            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 680, idealWidth: 680, minHeight: 480, idealHeight: 480)
        .background(AAColor.bg.opacity(0.0001))
        .aaSheet(.closeType, onClose: { onFinish?() })
        .onChange(of: entries.map(\.id)) { _, ids in
            let live = Set(ids)
            selection = selection.filter { live.contains($0) }
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(AAColor.tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(TrashText.windowTitle).font(.system(size: 17, weight: .bold))
                    if !entries.isEmpty {
                        AAStatusCapsule(text: TrashText.count(entries.count), color: AAColor.muted)
                    }
                }
                AAHelpText(TrashText.info)
            }
        }
    }

    private var table: some View {
        Table(entries, selection: $selection) {
            TableColumn(TrashText.columns[0]) { e in
                HStack(spacing: 6) {
                    Image(systemName: symbol(for: e)).foregroundStyle(kindTint(e)).frame(width: 16)
                    Text(e.name.isEmpty ? "(unnamed)" : e.name).lineLimit(1).truncationMode(.tail)
                }
                .help(e.name)
            }
            .width(min: 180, ideal: 300)
            TableColumn(TrashText.columns[1]) { e in
                Text(e.kindLabel).foregroundStyle(AAColor.muted).lineLimit(1)
            }
            .width(min: 90, ideal: 160)
            TableColumn(TrashText.columns[2]) { e in
                Text(e.deletedLocal).monospacedDigit().foregroundStyle(AAColor.muted).lineLimit(1)
            }
            .width(min: 120, ideal: 150)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                Button { putBack(Array(ids)) } label: { Label(TrashText.putBack, systemImage: "arrow.uturn.backward") }
                Button(role: .destructive) { deleteImmediately(Array(ids)) } label: {
                    Label(TrashText.deleteImmediately, systemImage: "trash.slash")
                }
            }
        } primaryAction: { ids in
            putBack(Array(ids))
        }
        .overlay {
            if entries.isEmpty {
                AAEmptyState(title: TrashText.emptyListMessage, symbol: "trash")
                    .allowsHitTesting(false)
            }
        }
        .aaListCommands(ListCommands(role: .trashTable, selectionCount: selection.count))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { putBack(orderedSelection) } label: {
                Label(TrashText.putBack, systemImage: "arrow.uturn.backward")
            }
            .aaProminent()
            .keyboardShortcut(.delete, modifiers: .command)
            .help(TrashText.putBackHelp)
            .disabled(selection.isEmpty || busy)

            Button(TrashText.deleteImmediately) { deleteImmediately(orderedSelection) }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .help(TrashText.deleteImmediatelyHelp)
                .disabled(selection.isEmpty || busy)

            Button(TrashText.emptyTrash) { emptyTrash() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .help(TrashText.emptyTrashHelp)
                .disabled(entries.isEmpty || busy)

            Spacer(minLength: 18)

            Button(TrashText.close) { close() }
                .frame(minWidth: 80)
        }
    }

    // MARK: Helpers

    /// The selection in stored order (restore order follows the list, like the WPF `SelectedItems` walk).
    private var orderedSelection: [UUID] { entries.map(\.id).filter { selection.contains($0) } }

    private func symbol(for e: TrashedItem) -> String {
        switch e.type {
        case .equipment: return "shippingbox"
        case .task: return "checkmark.circle"
        case .procedure: return "list.clipboard"
        case .vessel: return "ferry"
        case .crew: return "person.crop.circle"
        case .none: return "questionmark.circle"
        }
    }

    private func kindTint(_ e: TrashedItem) -> Color {
        switch e.type {
        case .equipment: return AAColor.kindGlyph(.equipment)
        case .task: return AAColor.kindGlyph(.task)
        case .procedure: return AAColor.kindGlyph(.procedure)
        case .vessel: return AAColor.kindGlyph(.vessel)
        case .crew: return AAColor.Status.crewAccent
        case .none: return AAColor.muted
        }
    }

    private func close() {
        onFinish?()
        dismiss()
    }

    // MARK: Actions (QUICK-174…176)

    private func putBack(_ ids: [UUID]) {
        guard !ids.isEmpty, !busy else { return }
        let ordered = entries.map(\.id).filter { Set(ids).contains($0) }
        let types = TrashActions.restore(entryIDs: ordered, store: env.store)
        if types.isEmpty {
            Task { @MainActor in await dialogs.warning(TrashText.restoreFailedTitle, TrashText.restoreFailed) }
            return
        }
        QuickWorkPersist.save(env, dialogs: dialogs)
        env.refreshAfterTrashChange()
        withAnimation(.snappy) { selection.subtract(ids) }
    }

    private func deleteImmediately(_ ids: [UUID]) {
        guard !ids.isEmpty, !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            let ok = await dialogs.confirm(TrashText.deleteTitle, TrashText.deleteMessage(ids.count),
                                           confirm: "Delete Immediately", destructive: true, defaultIsCancel: true)
            guard ok else { return }
            TrashActions.purge(entryIDs: ids, store: env.store)
            QuickWorkPersist.save(env, dialogs: dialogs)
            env.refreshAfterTrashChange()
            selection.removeAll()
        }
    }

    private func emptyTrash() {
        guard !entries.isEmpty, !busy else { return }
        busy = true
        let n = entries.count
        Task { @MainActor in
            defer { busy = false }
            let ok = await dialogs.confirm(TrashText.emptyTitle, TrashText.emptyMessage(n),
                                           confirm: "Empty Trash", destructive: true, defaultIsCancel: true)
            guard ok else { return }
            env.store.emptyTrash()
            QuickWorkPersist.save(env, dialogs: dialogs)
            env.refreshAfterTrashChange()
            selection.removeAll()
        }
    }
}
