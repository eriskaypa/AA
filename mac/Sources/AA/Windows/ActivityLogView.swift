// Spec: 08 §2.5 (QUICK-150…156), §3.5, §4.6, §6.2-E (Table, filter field, Export (.csv)… with NSSavePanel +
//       NSWorkspace.open, Clear log behind a destructive confirmation), Q-11 (the list may update live while keeping
//       selection and scroll); 02 REPO-092; DECISIONS 08 OQ-3 (one reusable window); 03 §6.5.1.5 (⎋ clears the
//       filter field, ⌥⌘F focuses it); ARCHITECTURE.md §7.7, §9.1 (Export failed → its own alert title).
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

/// Tools ▸ Activity Log… — the UTC activity log, newest first.
struct ActivityLogView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var filter = ""
    @State private var rows: [ActivityLogRow] = []
    @State private var selection = Set<Int>()
    @State private var busy = false

    /// Rebuild trigger: the log's size, its newest stamp (the 10 000 cap keeps the size constant) and the store
    /// generation (reloads replace the graph).
    private var logSignature: [Int64] {
        [Int64(env.store.data.log.count), env.store.data.log.last?.timestampUtc.ticks ?? 0, Int64(env.store.generation)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            Table(rows, selection: $selection) {
                TableColumn(ActivityLogText.columns[0]) { r in
                    Text(r.timeUtc).font(.aaMono(AAType.caption)).monospacedDigit().lineLimit(1)
                }
                .width(min: 160, ideal: 172)
                TableColumn(ActivityLogText.columns[1]) { r in
                    Text(r.timeLocal).font(.aaMono(AAType.caption)).monospacedDigit().foregroundStyle(AAColor.muted)
                        .lineLimit(1)
                }
                .width(min: 130, ideal: 142)
                TableColumn(ActivityLogText.columns[2]) { r in
                    ActivityLogActionBadge(action: r.action)
                }
                .width(min: 70, ideal: 76)
                TableColumn(ActivityLogText.columns[3]) { r in
                    Text(r.kind).lineLimit(2)
                }
                .width(min: 80, ideal: 100)
                TableColumn(ActivityLogText.columns[4]) { r in
                    Text(r.name).lineLimit(4).fixedSize(horizontal: false, vertical: true).help(r.name)
                }
                .width(min: 110, ideal: 160)
                TableColumn(ActivityLogText.columns[5]) { r in
                    Text(r.detail).foregroundStyle(AAColor.muted).lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true).help(r.detail)
                }
                .width(min: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .font(.aaMono(AAType.small))
            .overlay {
                if rows.isEmpty {
                    AAEmptyState(title: env.store.data.log.isEmpty ? "No activity yet" : "No matching entries",
                                 symbol: "list.bullet.clipboard",
                                 message: env.store.data.log.isEmpty ? nil : "Nothing matches \u{201C}\(NetText.trim(filter))\u{201D}.")
                        .allowsHitTesting(false)
                }
            }
            Divider()
            Text(ActivityLogText.countLine(shown: rows.count, total: env.store.data.log.count))
                .font(.system(size: AAType.caption))
                .foregroundStyle(AAColor.muted)
                .monospacedDigit()
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 420, idealHeight: 620)
        .navigationTitle(ActivityLogText.windowTitle)
        .onAppear(perform: refresh)
        .onChange(of: filter) { _, _ in refresh() }
        .onChange(of: logSignature) { _, _ in refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .center, spacing: 12) {
            Text(ActivityLogText.header)
                .font(.aaMono(AAType.title, weight: .bold))
                .foregroundStyle(AAColor.accent)
            Spacer(minLength: 12)
            AASearchField(text: $filter, prompt: ActivityLogText.filterPrompt)
                .frame(width: 210)
                .aaFilterField(for: .activityLog)
            Button { export() } label: { Label(ActivityLogText.exportButton, systemImage: "square.and.arrow.up") }
                .disabled(busy)
                .help("Export every entry, oldest first, as a CSV file.")
            Button(role: .destructive) { clear() } label: { Label(ActivityLogText.clearButton, systemImage: "trash") }
                .disabled(busy || env.store.data.log.isEmpty)
        }
        AAHelpText(ActivityLogText.help)
        }
    }

    /// QUICK-152/153: a snapshot rebuilt on open, on every filter keystroke and when the log changes (Q-11).
    private func refresh() {
        let fresh = ActivityLog.rows(env.store.data.log, filter: filter)
        if fresh != rows { rows = fresh }
        let live = Set(fresh.map(\.id))
        selection = selection.filter { live.contains($0) }
    }

    // MARK: Clear (QUICK-154)

    private func clear() {
        let n = env.store.data.log.count
        guard n > 0 else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            let ok = await dialogs.confirm(ActivityLogText.clearTitle, ActivityLogText.clearMessage(n),
                                           confirm: "Clear Log", destructive: true, defaultIsCancel: true)
            guard ok else { return }
            env.store.clearLog()
            QuickWorkPersist.save(env, dialogs: dialogs)
            refresh()
        }
    }

    // MARK: Export (QUICK-155, §4.6)

    private func export() {
        busy = true
        let name = ActivityLog.exportFileName(utcNow: env.clock.utcNow())
        Task { @MainActor in
            defer { busy = false }
            guard let url = await dialogs.savePanel(SavePanelConfig(title: ActivityLogText.exportTitle, defaultName: name,
                                                                    allowedTypes: [.commaSeparatedText],
                                                                    allowsOtherTypes: true)) else { return }
            let data = ActivityLog.csv(env.store.data.log)
            do {
                try AtomicWrite.write(data, to: url)
            } catch {
                await dialogs.error(ActivityLogText.exportFailedTitle, error.localizedDescription)
                return
            }
            NSWorkspace.shared.open(url)          // failures ignored (QUICK-155)
        }
    }
}

/// `Added` / `Removed` as a small tinted capsule (the text is the stored Action, verbatim).
struct ActivityLogActionBadge: View {
    let action: String

    var body: some View {
        let added = action == "Added", removed = action == "Removed"
        let color: Color = added ? AAColor.Status.diffAdded : (removed ? AAColor.Status.diffRemoved : AAColor.muted)
        Text(action)
            .font(.system(size: AAType.caption, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}
