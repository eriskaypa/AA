// Spec: 01 DATA-180 (the outside-change sheet: messageText, informativeText, Keep Mine (default) / Use Theirs /
//       Review Changes… / Stop Editing Here; unreadable and deleted variants), DATA-100 via `env.reviewAndConfirmImport`
//       (Import = Use Theirs, Cancel returns here), DATA-181 + ARCH §6.6 ("Conflict Copies…" button), MP.6.5
//       (exclamationmark.triangle.fill); ARCHITECTURE.md §7.5 (sheet contract), §7.7.
import AppKit
import SwiftUI
import AACore

struct DataFileConflictSheet: View {
    let conflict: DataFileConflict
    let finish: (DataFileConflictChoice) -> Void
    @Environment(\.dialogs) private var dialogs
    @State private var done = false
    @State private var reviewing = false

    init(conflict: DataFileConflict, finish: @escaping (DataFileConflictChoice) -> Void) {
        self.conflict = conflict; self.finish = finish
    }

    private var isChanged: Bool { if case .changed = conflict.kind { return true }; return false }

    private func complete(_ c: DataFileConflictChoice) {
        guard !done else { return }
        done = true
        finish(c)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            HStack(alignment: .top, spacing: AASpacing.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(AAColor.Status.dueSoon)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: AASpacing.s) {
                    Text(PersistConflictText.title)
                        .font(.system(size: 14, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(PersistConflictText.message(conflict))
                        .font(.system(size: AAType.body))
                        .foregroundStyle(AAColor.fg)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    PersistConflictFacts(conflict: conflict)
                        .padding(.top, 2)
                }
            }
            HStack(spacing: AASpacing.s) {
                Button(PersistConflictText.conflictCopies) {
                    Task { await dialogs.presentSheet(.closeType) { _ in ConflictCopiesSheet() } }
                }
                .help("Versions kept in the data folder's “conflicts” folder")
                .fixedSize()
                Spacer(minLength: AASpacing.s)
                Button(PersistConflictText.stopEditing) { complete(.stopEditingHere) }
                    .help("Stop saving in this window; it keeps showing the data")
                    .fixedSize()
                if isChanged {
                    Button(PersistConflictText.review) { review() }
                        .disabled(reviewing)
                        .fixedSize()
                    Button(PersistConflictText.useTheirs) { complete(.useTheirs) }
                        .fixedSize()
                }
                Button(PersistConflictText.keepMine) { complete(.keepMine) }
                    .keyboardShortcut(.defaultAction)
                    .aaProminent()
                    .fixedSize()
            }
        }
        .padding(AASpacing.l)
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
        .aaSheet(.decision)
    }

    /// DATA-180 "Review Changes…": the change preview with their file as the incoming data; Import = Use Theirs.
    private func review() {
        guard let env = LaunchCoordinator.shared.env, let r = env.dataFileGuard?.reviewData(conflict) else { return }
        reviewing = true
        Task { @MainActor in
            let ok = await env.reviewAndConfirmImport(incoming: r.data, incomingStamp: r.stamp,
                                                      sourceName: PersistConflictText.reviewSource(conflict.fileName),
                                                      presenter: dialogs)
            reviewing = false
            if ok { complete(.useTheirs) }
        }
    }
}

/// "Yours / Theirs" facts under the message (Mac addition: the two save times side by side).
struct PersistConflictFacts: View {
    let conflict: DataFileConflict

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: AASpacing.m, verticalSpacing: 4) {
            GridRow {
                Label("Your version", systemImage: "person.crop.circle")
                    .foregroundStyle(AAColor.muted)
                Text(conflict.ourTime).font(.aaMono(AAType.small)).monospacedDigit()
            }
            GridRow {
                Label("Their version", systemImage: theirSymbol)
                    .foregroundStyle(AAColor.muted)
                Text(theirText).font(.aaMono(AAType.small)).monospacedDigit()
            }
        }
        .font(.system(size: AAType.small))
        .padding(AASpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AAColor.panelAlt.opacity(0.6), in: RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous).strokeBorder(AAColor.border))
    }

    private var theirSymbol: String {
        switch conflict.kind {
        case .changed: return "doc.badge.arrow.up"
        case .deleted: return "trash"
        case .unreadable: return "lock.doc"
        }
    }

    private var theirText: String {
        switch conflict.kind {
        case .deleted: return "deleted"
        case .unreadable(let reason):
            return conflict.theirTime == PersistConflictText.noSaveDate
                ? "can't be opened (\(reason))" : "\(conflict.theirTime) — can't be opened (\(reason))"
        case .changed: return conflict.theirTime
        }
    }
}
