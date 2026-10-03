// Spec: 14 TOOLS-040 (layout and exact texts), TOOLS-041 (base location: Browse..., persisted at once, never cleared),
//       TOOLS-042…048 (live parse, preview header, Clear / Example), TOOLS-049 (Create folders flow and messages),
//       TOOLS-050 (Open base folder → Finder, "Open failed"), TOOLS-051 (Close), TOOLS-052 (theme), §6.7 (Mac layout:
//       resizable split, fully expanded outline with folder symbols, path display, ⌘↩ Create, ⌘W/Esc Close), Q-15/Q-17;
//       ARCHITECTURE.md §7.7 (`FolderBuilderView()`), §8 (design tokens).
import AppKit
import SwiftUI
import AACore

struct FolderBuilderView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var base: String?
    @State private var status = ""
    @State private var plan: ToolFolderPlan

    /// `initialText` exists for the debug snapshot registry; the menu opens the empty window (TOOLS-042).
    init(initialText: String = "") {
        _text = State(initialValue: initialText)
        _plan = State(initialValue: ToolFolderPlan.parse(initialText))
    }

    private var baseText: String { base ?? ToolFolderPlan.usableStoredBase(env.settings.values.folderBuilderBase) }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            VStack(alignment: .leading, spacing: AASpacing.xs) {
                Text(ToolFolderPlan.title).font(.aaMono(15, weight: .bold))
                Text(ToolFolderPlan.helpText)
                    .font(.aaMono(AAType.small))
                    .foregroundStyle(AAColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            baseLocationPanel
            HSplitView {
                editorPane.frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity).background(AAColor.bg)
                previewPane.frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity).background(AAColor.bg)
            }
            .frame(minHeight: 260)
            bottomBar
        }
        .padding(AASpacing.m)
        .frame(minWidth: 640, idealWidth: 820, minHeight: 520, idealHeight: 660)
        .background(AAColor.bg)
        .onChange(of: text) { _, new in plan = ToolFolderPlan.parse(new) }
    }

    // MARK: Base location (TOOLS-041)

    private var baseLocationPanel: some View {
        HStack(spacing: AASpacing.s) {
            Text("Base location:").font(.aaMono(AAType.body, weight: .medium))
            HStack(spacing: AASpacing.xs) {
                Image(systemName: baseText.isEmpty ? "folder.badge.questionmark" : "folder.fill")
                    .foregroundStyle(baseText.isEmpty ? AAColor.muted : AAColor.tint)
                Text(baseText.isEmpty ? "No base location chosen" : baseText)
                    .font(.aaMono(AAType.small))
                    .foregroundStyle(baseText.isEmpty ? AAColor.muted : AAColor.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(baseText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AASpacing.s)
            .padding(.vertical, 5)
            .background(AAColor.panel, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border))
            Button("Browse...") { Task { @MainActor in await browse() } }
        }
        .padding(AASpacing.s)
        .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border))
    }

    private func browse() async {
        let current = ToolFolderPlan.directoryExists(baseText) ? URL(filePath: baseText, directoryHint: .isDirectory) : nil
        guard let url = await DriveActions.chooseFolder(message: ToolFolderPlan.browseMessage, directory: current,
                                                        dialogs: dialogs) else { return }
        base = url.path
        env.settings.setFolderBuilderBase(url.path)
    }

    // MARK: Panes

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            Text("Folder list (one per line; indent to nest)").font(.aaMono(AAType.body, weight: .bold))
            HStack(spacing: AASpacing.s) {
                Button { text = "" } label: { Label("Clear", systemImage: "xmark.circle") }
                Button { text = ToolFolderPlan.exampleText } label: { Label("Example", systemImage: "text.badge.plus") }
                    .help("Fill in a small example structure.")
                Spacer()
            }
            .controlSize(.small)
            ToolBulkTextView(text: $text)
                .clipShape(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border))
        }
        .padding(AASpacing.s)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            HStack {
                Text(plan.header).font(.aaMono(AAType.body, weight: .bold)).contentTransition(.numericText())
                Spacer()
            }
            .animation(.snappy, value: plan.count)
            Group {
                if plan.roots.isEmpty {
                    AAEmptyState(title: "Nothing to preview", symbol: "folder.badge.plus",
                                 message: "Type folder names on the left.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(ToolFolderRow.flatten(plan.roots)) { row in
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(AAColor.tint)
                                .imageScale(.medium)
                            Text(row.name).font(.aaMono(AAType.body)).lineLimit(1).truncationMode(.tail)
                        }
                        .padding(.leading, CGFloat(row.depth) * 18)
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AAColor.panel)
            .clipShape(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border))
        }
        .padding(AASpacing.s)
    }

    // MARK: Bottom bar (TOOLS-049…051)

    private var bottomBar: some View {
        HStack(spacing: AASpacing.s) {
            Text(status)
                .font(.aaMono(AAType.small))
                .foregroundStyle(AAColor.muted)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
            Button("Open base folder") { openBase(baseText) }
            Button { Task { @MainActor in await create() } } label: { Text("Create folders") }
                .aaProminent()
                .keyboardShortcut(.return, modifiers: .command)
            Button("Close") { dismiss() }
                .frame(minWidth: 80)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.top, AASpacing.xs)
    }

    private func yesNo(_ title: String, _ message: String, style: NSAlert.Style = .informational) async -> Bool {
        await dialogs.alert(AlertSpec(title: title, message: message, style: style,
                                      buttons: [AlertButton(title: "Yes", role: .default),
                                                AlertButton(title: "No", role: .cancel)])) == 0
    }

    private func create() async {
        let baseDir = NetText.trim(baseText)
        if NetText.isBlank(baseDir) {
            await dialogs.info(ToolFolderPlan.title, ToolFolderPlan.chooseBaseFirst)
            return
        }
        let current = ToolFolderPlan.parse(text)
        if current.count == 0 {
            status = ToolFolderPlan.nothingToCreate
            return
        }
        if !ToolFolderPlan.directoryExists(baseDir) {
            guard await yesNo(ToolFolderPlan.title, ToolFolderPlan.baseMissingQuestion(baseDir)) else { return }
            do {
                try ToolFolderPlan.createBase(baseDir)
            } catch {
                await dialogs.error(ToolFolderPlan.title, error.localizedDescription)
                return
            }
        }
        guard await yesNo("Confirm", ToolFolderPlan.confirmCreate(count: current.count, base: baseDir)) else { return }
        let result = current.create(under: URL(filePath: baseDir, directoryHint: .isDirectory))
        env.settings.setFolderBuilderBase(baseDir)
        base = baseDir
        withAnimation(.snappy) { status = result.statusText }
        if result.created > 0, await yesNo(ToolFolderPlan.title, ToolFolderPlan.openAfterCreate(created: result.created)) {
            openBase(baseDir)
        }
    }

    /// TOOLS-050 (uses the untrimmed text, like Windows).
    private func openBase(_ dir: String) {
        guard ToolFolderPlan.directoryExists(dir) else {
            status = ToolFolderPlan.baseNotFound
            return
        }
        if !NSWorkspace.shared.open(URL(filePath: dir, directoryHint: .isDirectory)) {
            Task { @MainActor in await dialogs.error("Open failed", "Finder could not open \(dir).") }
        }
    }
}

/// One visible row of the always-expanded preview tree.
struct ToolFolderRow: Identifiable, Hashable {
    let id: String
    let name: String
    let depth: Int

    static func flatten(_ nodes: [ToolFolderNode], depth: Int = 0) -> [ToolFolderRow] {
        var out: [ToolFolderRow] = []
        for n in nodes {
            out.append(ToolFolderRow(id: n.id, name: n.name, depth: depth))
            if let kids = n.children { out.append(contentsOf: flatten(kids, depth: depth + 1)) }
        }
        return out
    }
}
