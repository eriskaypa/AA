// Spec: 08 §2.6 (QUICK-170…178), §3.6, §6.2-F (a sheet on the main window, Table with multi-select, destructive
//       confirmations, Close / Esc); 02 REPO-078 (window), REPO-080 (permanent removal), §6.4 (Finder wording);
//       01 DATA-113; DECISIONS 02 Q-5 ("Put Back" / "Delete Immediately", "Restore" in tooltips); 03 SHELL-675
//       (in-sheet keys ⌘⌫ / ⌥⌘⌫ / ⇧⌘⌫), §6.5.1.5 (close-type sheet: ⌘W / ⎋ close); 01 DATA-174 (read-only copy:
//       Put Back / Delete Immediately / Empty Trash disabled, "Not available in a read-only copy of AA."); ARCHITECTURE.md
//       §7.5, §7.7.
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

    /// 01 DATA-174: a read-only copy of AA never changes the Trash (the in-memory change would never be saved).
    private var readOnly: Bool { env.isReadOnlyInstance || env.settings.isWriteGated }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, AASpacing.l)
                .padding(.top, AASpacing.l)
                .padding(.bottom, AASpacing.m)
            content
                .padding(.horizontal, AASpacing.l)
                .padding(.bottom, AASpacing.m)
            Divider()
            footer
                .padding(.horizontal, AASpacing.l)
                .frame(height: 44)
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
        HStack(alignment: .top, spacing: AASpacing.m) {
            BuilderSheetHeader(title: TrashText.windowTitle, subtitle: TrashText.info, symbol: "trash")
            if !entries.isEmpty {
                AAStatusCapsule(text: TrashText.count(entries.count), color: AAColor.muted)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }

    /// QUICK-172: the live list; an empty Trash shows the empty state over a plain background (no table, no stripes).
    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            AAEmptyState(title: TrashText.emptyListMessage, symbol: "trash", message: TrashText.emptyListHint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            table
        }
    }

    private var table: some View {
        Table(entries, selection: $selection) {
            TableColumn(TrashText.columns[0]) { e in
                // REPO-078 / T-TR-15: the raw Name, as the WPF list binds it (an empty name shows an empty cell).
                HStack(spacing: AASpacing.s) {
                    Image(systemName: symbol(for: e))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(kindTint(e))
                        .frame(width: 16)
                    Text(e.name)
                        .font(.aaMono(AAType.body))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .padding(.vertical, AASpacing.xs)
                .help(e.name)
            }
            .width(min: 180, ideal: 300)
            TableColumn(TrashText.columns[1]) { e in
                Text(e.kindLabel).font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted).lineLimit(1)
            }
            .width(min: 90, ideal: 160)
            TableColumn(TrashText.columns[2]) { e in
                Text(e.deletedLocal).font(.aaMono(AAType.caption)).monospacedDigit().foregroundStyle(AAColor.muted)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 150)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                Button { putBack(Array(ids)) } label: { Label(TrashText.putBack, systemImage: "arrow.uturn.backward") }
                    .disabled(readOnly)
                Button(role: .destructive) { deleteImmediately(Array(ids)) } label: {
                    Label(TrashText.deleteImmediately, systemImage: "trash.slash")
                }
                .disabled(readOnly)
            }
        } primaryAction: { ids in
            putBack(Array(ids))
        }
        .aaListCommands(ListCommands(role: .trashTable, selectionCount: selection.count))
    }

    private var footer: some View {
        HStack(spacing: AASpacing.s) {
            if readOnly {
                Label(PersistReadOnlyText.disabledHelp, systemImage: "lock.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: AASpacing.s)

            Button { putBack(orderedSelection) } label: {
                Label(TrashText.putBack, systemImage: "arrow.uturn.backward")
            }
            .aaProminent()
            .keyboardShortcut(.delete, modifiers: .command)
            .help(TrashText.help(TrashText.putBackHelp, readOnly: readOnly))
            .disabled(readOnly || selection.isEmpty || busy)

            Button(TrashText.deleteImmediately) { deleteImmediately(orderedSelection) }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .help(TrashText.help(TrashText.deleteImmediatelyHelp, readOnly: readOnly))
                .disabled(readOnly || selection.isEmpty || busy)

            Button(TrashText.emptyTrash) { emptyTrash() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .help(TrashText.help(TrashText.emptyTrashHelp, readOnly: readOnly))
                .disabled(readOnly || entries.isEmpty || busy)

            Button(TrashText.close) { close() }
                .frame(minWidth: 80)
                .padding(.leading, AASpacing.m)
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
        guard !ids.isEmpty, !busy, !readOnly else { return }
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
        guard !ids.isEmpty, !busy, !readOnly else { return }
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
        guard !entries.isEmpty, !busy, !readOnly else { return }
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
