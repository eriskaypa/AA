// Spec: 01 DATA-181 (recovery list: name, kind, size, LastModified read without loading; "Show in Finder" and
//       "Restore…" — change preview with source name = the file name, then applied like ApplySyncedData, never
//       repointing CurrentDataFile), DECISIONS R-70 (File ▸ Recover Conflict Copies…); ARCHITECTURE.md §6.6, §7.5, §7.7.
import AppKit
import SwiftUI
import AACore

struct ConflictCopiesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dialogs) private var dialogs
    @State private var entries: [ConflictCopies.Entry] = []
    @State private var selection: ConflictCopies.Entry.ID?
    @State private var busy = false

    private var env: AppEnvironment? { LaunchCoordinator.shared.env }
    private var selected: ConflictCopies.Entry? { entries.first { $0.id == selection } }
    /// Restoring writes the data file: not in a read-only copy, nor while editing is stopped (§MP.3.5).
    private var canRestore: Bool {
        guard let env else { return false }
        return !env.isReadOnlyInstance && env.dataFileGuard?.state.mode != .stoppedEditing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if entries.isEmpty {
                AAEmptyState(title: "No conflict copies", symbol: "doc.on.doc", message: PersistUIText.conflictCopiesEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
            Divider()
            footer
        }
        .frame(width: 680, height: 420)
        .onAppear(perform: reload)
        .aaSheet(.closeType)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AASpacing.m) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 26))
                .foregroundStyle(AAColor.tint)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 3) {
                Text("Conflict Copies").font(.system(size: 15, weight: .bold))
                Text(PersistUIText.conflictCopiesHelp)
                    .font(.system(size: AAType.small))
                    .foregroundStyle(AAColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(AASpacing.l)
    }

    private var table: some View {
        Table(entries, selection: $selection) {
            TableColumn("Name") { e in
                HStack(spacing: 6) {
                    Image(systemName: e.isTheirs ? "doc.badge.arrow.up" : "person.crop.circle")
                        .foregroundStyle(e.isTheirs ? AAColor.Status.dueSoon : AAColor.tint)
                    Text(e.fileName).font(.aaMono(AAType.small)).lineLimit(1).truncationMode(.middle)
                }
                .help(e.fileName)
            }
            .width(min: 230, ideal: 290)
            TableColumn("Kind") { e in
                Text(e.isTheirs ? "Theirs" : "Mine")
                    .font(.system(size: AAType.small, weight: .medium))
                    .foregroundStyle(e.isTheirs ? AAColor.Status.dueSoon : AAColor.tint)
            }
            .width(60)
            TableColumn("Size") { e in
                Text(ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file))
                    .font(.system(size: AAType.small)).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(70)
            TableColumn("Last saved") { e in
                Text(e.lastModified.map { $0.toLocalTime().format(.isoSecond) } ?? "—")
                    .font(.aaMono(AAType.small)).monospacedDigit()
                    .foregroundStyle(e.lastModified == nil ? AAColor.muted : AAColor.fg)
            }
            .width(min: 140, ideal: 150)
        }
        .contextMenu(forSelectionType: ConflictCopies.Entry.ID.self) { ids in
            if let id = ids.first, let e = entries.first(where: { $0.id == id }) {
                Button("Show in Finder") { reveal(e) }
                Button("Restore…") { restore(e) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let e = entries.first(where: { $0.id == id }) { restore(e) }
        }
    }

    private var footer: some View {
        HStack(spacing: AASpacing.s) {
            Button("Show in Finder") { if let e = selected { reveal(e) } else { revealFolder() } }
                .help(selected == nil ? "Open the conflicts folder in Finder" : "Show the selected copy in Finder")
            Spacer()
            Button("Restore…") { if let e = selected { restore(e) } }
                .disabled(selected == nil || busy || !canRestore)
                .help(canRestore ? "Preview the copy's changes, then make it your data" : PersistReadOnlyText.disabledHelp)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .aaProminent()
        }
        .padding(AASpacing.m)
    }

    private func reload() {
        guard let env else { return }
        entries = ConflictCopies.list(env.dataStore)
        if selection == nil { selection = entries.first?.id }
    }

    private func reveal(_ e: ConflictCopies.Entry) {
        guard let env else { return }
        NSWorkspace.shared.activateFileViewerSelecting([ConflictCopies.url(of: e, env.dataStore)])
    }

    private func revealFolder() {
        guard let env else { return }
        NSWorkspace.shared.activateFileViewerSelecting([PersistConflictStore.folder(env.dataStore.appFolder)])
    }

    /// Change preview (source name = the file name), then applied into the default data file and reloaded.
    private func restore(_ e: ConflictCopies.Entry) {
        guard let env, !busy, canRestore else { return }
        guard let incoming = ConflictCopies.peekData(e, env.dataStore) else {
            Task { await dialogs.error("Restore failed", "“\(e.fileName)” can't be opened on this Mac.") }
            return
        }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            let ok = await env.reviewAndConfirmImport(incoming: incoming, incomingStamp: incoming.lastModified,
                                                      sourceName: e.fileName, presenter: dialogs)
            guard ok else { return }
            env.flushAllEditors()
            do {
                try ConflictCopies.restore(e, env.dataStore)
                env.loadDataAndInitUI(reason: .importFile, status: "Restored \(e.fileName) from the conflicts folder.")
                PersistUIBridge.shared.refreshConflictCopies()
                reload()
            } catch {
                await dialogs.error("Restore failed", error.localizedDescription)
            }
        }
    }
}
