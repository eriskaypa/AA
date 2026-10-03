// Spec: 03 SHELL-021 (header buttons Due / Search / Go to / Load / Save → toolbar), SHELL-022 (status line; history
//       popover), SHELL-023 (shared-save indicator texts, colours, tooltip; visible while in trouble), SHELL-510 (no key
//       equivalents on toolbar items; help shows the key), §6.2, §6.5.1.9 (help strings); ARCHITECTURE.md §7.2.
import AppKit
import SwiftUI
import AACore

struct ShellMainToolbar: CustomizableToolbarContent {
    @Environment(AppEnvironment.self) private var env

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "shared", placement: .navigation) {
            SharedSaveIndicator()
        }
        ToolbarItem(id: "status", placement: .automatic, showsByDefault: true) {
            ShellStatusHistoryButton()
        }
        ToolbarItem(id: "due", placement: .primaryAction) {
            Button { env.router.perform(.dueDates) } label: { Label("Due", systemImage: "pin") }
                .help(ShortcutRegistry.toolbarHelp(.dueDates, base: "Show a small floating window of tasks and procedures due today and tomorrow. (Ship work-order notifications live in each vessel's Work Orders tab.)"))
        }
        ToolbarItem(id: "search", placement: .primaryAction) {
            Button { env.router.perform(.searchAll) } label: { Label("Search", systemImage: "magnifyingglass") }
                .help("Search all items (⌘F; ⇧⌘F from inside a note)")
        }
        ToolbarItem(id: "goto", placement: .primaryAction) {
            Button { env.router.perform(.quickSwitcher) } label: { Label("Go to", systemImage: "arrow.right.circle") }
                .help("Quick switcher — fuzzy-jump to any item by name, kind or #tag. (⌘O)")
        }
        ToolbarItem(id: "reload", placement: .primaryAction) {
            Button { env.router.perform(.reloadFromDisk) } label: { Label("Reload", systemImage: "arrow.clockwise") }
                .help("Reload data from disk")
        }
        ToolbarItem(id: "save", placement: .primaryAction) {
            Button { env.router.perform(.save) } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .buttonStyle(.borderedProminent)
                .help("Save (⌘S)")
        }
    }
}

/// The SHELL-023 state, derived from W-PERSIST's coordinator.
@MainActor struct ShellSharedIndicatorModel {
    let env: AppEnvironment

    var isVisible: Bool {
        if case .off = env.sharedSave.health { return false }
        return !env.sharedSave.indicatorText.isEmpty
    }

    var inTrouble: Bool {
        switch env.sharedSave.health {
        case .offline, .notSaving: return true
        default: return false
        }
    }

    /// The exact text without its leading glyph (the glyph becomes an SF Symbol on the Mac).
    var text: String {
        var t = env.sharedSave.indicatorText
        for glyph in ["⚠ ", "🔗 "] where t.hasPrefix(glyph) { t.removeFirst(glyph.count) }
        return t
    }

    var help: String {
        let h = env.sharedSave.indicatorHelp
        return h.isEmpty ? "Shared save status. Turns red and stays visible if the shared file goes offline (e.g. a VSAT drop) so you know your edits aren't reaching it yet." : h
    }
}

struct SharedSaveIndicator: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showDetails = false

    var body: some View {
        let m = ShellSharedIndicatorModel(env: env)
        if m.isVisible {
            Button { showDetails.toggle() } label: {
                AAStatusCapsule(text: m.text, symbol: m.inTrouble ? "exclamationmark.triangle.fill" : "link",
                                color: m.inTrouble ? AAColor.Status.danger : AAColor.Status.sharedOK)
                    .symbolEffect(.pulse, isActive: m.inTrouble)
            }
            .buttonStyle(.plain)
            .help(m.help)
            .popover(isPresented: $showDetails, arrowEdge: .bottom) { ShellSharedSavePopover() }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}

/// Path, last sync and "Check Now" (01 §6.9 enhancement).
struct ShellSharedSavePopover: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            Text("Shared save file").font(.headline)
            AAMonoText(env.settings.values.sharedSaveFile ?? "", size: AAType.small)
                .foregroundStyle(AAColor.muted)
            Divider()
            HStack {
                Button("Check Now") { env.router.perform(.checkSharedSaveNow) }
                    .disabled(!env.router.decision(.checkSharedSaveNow).enabled)
                Spacer()
                Button("Stop Shared Save File…") { env.router.perform(.stopSharedSaveFile) }
                    .disabled(!env.router.decision(.stopSharedSaveFile).enabled)
            }
            .controlSize(.small)
        }
        .padding(AASpacing.m)
        .frame(width: 360)
    }
}

/// The status line's recent messages (SHELL-022: the subtitle shows the latest; this popover the last 20).
struct ShellStatusHistoryButton: View {
    @Environment(AppEnvironment.self) private var env
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: { Label("Recent messages", systemImage: "text.bubble") }
            .help(env.status.message.isEmpty ? "Recent status messages" : env.status.message)
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recent messages").font(.headline).padding(AASpacing.m)
                    Divider()
                    if env.status.history.isEmpty {
                        Text("No messages yet.").foregroundStyle(AAColor.muted).padding(AASpacing.m)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(env.status.history.enumerated()), id: \.offset) { i, line in
                                    Text(line)
                                        .font(.aaMono(AAType.small))
                                        .foregroundStyle(i == 0 ? AAColor.fg : AAColor.muted)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(AASpacing.m)
                        }
                        .frame(maxHeight: 300)
                    }
                }
                .frame(width: 420)
            }
    }
}
