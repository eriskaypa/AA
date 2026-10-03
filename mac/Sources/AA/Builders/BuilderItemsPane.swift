// Spec: 06 §A BUILD-001…017 (shared checklist builder), §D BUILD-041…045 (subtask builder: same panes, subtask
//       wording, no Manage), §6.2 (HSplitView, monospaced bulk editor, ⌘↩ Add all, SF Symbol button bar with the
//       Windows tooltips, context menu, double-click / ↩ = Edit…, drag reorder = BUILD-A3), 03 SHELL-668 (⌘↩),
//       SHELL-581…583 / SHELL-544 / SHELL-670 via ListCommands role `builderItems` (T-KB-32), SHELL-667 (↩ = Edit…).
// The two-pane builder used by every host: bulk entry on the left, the live list with its button bar on the right,
// and the "Saved lists:" strip on top. Generic over the item type (ChecklistStep or TaskItem) through BuilderEngine.
import AppKit
import SwiftUI
import AACore

/// The host-specific wording of the builder panes (BUILD-002 vs BUILD-041/042).
struct BuilderPaneStrings {
    var noun: String
    var bulkHeader: String
    var replaceHelp: String
    var currentHeader: String
    var addTitle: String
    var addHelp: String
    var insertBeforeHelp: String
    var insertAfterHelp: String
    var editHelp: String
    var upHelp: String
    var downHelp: String
    var moveToHelp: String
    var promptTitle: String
    var promptLabel: String
    var saveHelp: String
    var loadHelp: String
    var manageHelp: String?
    var emptySaveMessage: String
    var subtasks: Bool
    var emptyListHint: String

    /// BUILD-002 (procedure, crew and saved-list hosts).
    static let checklist = BuilderPaneStrings(
        noun: "item",
        bulkHeader: "Bulk entry (one item per line)",
        replaceHelp: "Replace all existing items instead of appending.",
        currentHeader: "Current items",
        addTitle: "Item",
        addHelp: "Append a new item to the end of the list.",
        insertBeforeHelp: "Insert a new item immediately above the (first) selected item.",
        insertAfterHelp: "Insert a new item immediately below the (last) selected item.",
        editHelp: "Open the full editor for the selected item — deadline, done, notes & files.",
        upHelp: "Move selected item(s) up.",
        downHelp: "Move selected item(s) down.",
        moveToHelp: "Move selected item(s) to a specific position.",
        promptTitle: "New item",
        promptLabel: "Title:",
        saveHelp: "Save the current checklist to the database as a reusable saved list.",
        loadHelp: "Insert a saved list (reuse it over and over). You choose whether to append or replace.",
        manageHelp: "Rename or delete saved lists in the database.",
        emptySaveMessage: "Add some items first, then save the list.",
        subtasks: false,
        emptyListHint: "No items yet — type one per line on the left and click Add all.")

    /// BUILD-041/042 (subtask builder).
    static let subtaskList = BuilderPaneStrings(
        noun: "subtask",
        bulkHeader: "Bulk entry (one subtask per line)",
        replaceHelp: "Replace all existing subtasks instead of appending.",
        currentHeader: "Current subtasks",
        addTitle: "Subtask",
        addHelp: "Append a new subtask to the end of the list.",
        insertBeforeHelp: "Insert a new subtask immediately above the (first) selected subtask.",
        insertAfterHelp: "Insert a new subtask immediately below the (last) selected subtask.",
        editHelp: "Open the full subtask editor (deadline / recurrence / status / notes / files).",
        upHelp: "Move selected subtask(s) up by one position.",
        downHelp: "Move selected subtask(s) down by one position.",
        moveToHelp: "Move selected subtask(s) to a specific position (top / bottom / before another subtask).",
        promptTitle: "New subtask",
        promptLabel: "Name:",
        saveHelp: "Save the current subtasks to the database as a reusable saved list.",
        loadHelp: "Insert a saved list as subtasks (append or replace).",
        manageHelp: nil,
        emptySaveMessage: "Add some subtasks first, then save the list.",
        subtasks: true,
        emptyListHint: "No subtasks yet — type one per line on the left and click Add all.")
}

/// One row of the right-hand list (BUILD-003 / BUILD-043).
struct BuilderRowDisplay: Identifiable, Hashable {
    var id: UUID
    var title: String
    var struck: Bool
    /// `"due yyyy-MM-dd"` (steps), `"yyyy-MM-dd"` (subtasks) or `""`.
    var trailing: String
    /// Deeper subtasks carried by this subtask (BUILD-045; shown as a small badge, 0 = none).
    var nested: Int = 0
}

/// The bulk + list builder (both panes and the saved-lists strip).
struct BuilderItemsPane<Item: AnyObject>: View {
    let engine: BuilderEngine<Item>
    let strings: BuilderPaneStrings
    let display: (Item) -> BuilderRowDisplay
    /// Opens the full editor for one item (the host presents the sheet and flushes afterwards).
    let edit: (UUID) async -> Void
    @Binding var selection: Set<UUID>

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var bulkText = ""
    @State private var replaceExisting = false
    @State private var busy = false
    /// The row to bring into view after add / insert / Move to (BUILD-006, BUILD-009 `SelectByReference`).
    @State private var scrollTarget: UUID?

    var body: some View {
        VStack(spacing: 0) {
            savedListsStrip
            HSplitView {
                bulkPane
                    .frame(minWidth: 240, idealWidth: 360, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                itemsPane
                    .frame(minWidth: 320, idealWidth: 420, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
        }
    }

    // MARK: Saved lists strip (BUILD-002 top, BUILD-041)

    private var savedListsStrip: some View {
        // The full strip when it fits; in a narrow host the three commands collapse into one "Saved lists" menu.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AASpacing.s) {
                Label("Saved lists:", systemImage: "list.bullet.rectangle")
                    .font(.aaMono(AAType.small, weight: .bold))
                    .foregroundStyle(AAColor.accent)
                ForEach(savedListCommands.indices, id: \.self) { i in
                    BuilderIconButton(command: savedListCommands[i], showsTitle: true)
                }
            }
            .fixedSize()
            Menu {
                ForEach(savedListCommands.indices, id: \.self) { i in
                    let c = savedListCommands[i]
                    Button(c.title, systemImage: c.symbol, action: c.action).help(c.help)
                }
            } label: {
                Label("Saved lists", systemImage: "list.bullet.rectangle")
            }
            .menuStyle(.button)
            .buttonStyle(.accessoryBar)
            .fixedSize()
            .help("Save as list…, Load a saved list…\(strings.manageHelp == nil ? "" : ", Manage saved lists…")")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, AASpacing.xs)
        .frame(minHeight: 36)
        .background(AAColor.panelAlt)
        .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
    }

    /// BUILD-002 / BUILD-041 strip commands ("Manage saved lists…" only for step hosts).
    private var savedListCommands: [BuilderBarCommand] {
        var out = [
            BuilderBarCommand(title: "Save as list…", symbol: "square.and.arrow.down", help: strings.saveHelp) {
                run { await BuilderTemplateFlows.saveAsList(engine, env: env, dialogs: dialogs,
                                                            emptyMessage: strings.emptySaveMessage) }
            },
            BuilderBarCommand(title: "Load a saved list…", symbol: "list.clipboard", help: strings.loadHelp) {
                run {
                    let ids = engine.ids
                    if await BuilderTemplateFlows.load(engine, env: env, dialogs: dialogs, subtasks: strings.subtasks) {
                        selection = selection.filter { ids.contains($0) && engine.ids.contains($0) }
                    }
                }
            },
        ]
        if let manageHelp = strings.manageHelp {
            out.append(BuilderBarCommand(title: "Manage saved lists…", symbol: "folder.badge.gearshape", help: manageHelp) {
                run { await BuilderTemplateFlows.manage(env: env, dialogs: dialogs) }
            })
        }
        return out
    }

    // MARK: Bulk entry (BUILD-004/005)

    private var bulkPane: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            Text(strings.bulkHeader).font(.aaMono(AAType.small, weight: .bold)).foregroundStyle(AAColor.fg)
            // One row when it fits, else "Replace existing" drops below the buttons — never wrapped mid-label.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AASpacing.s) { addAllButton; clearButton; replaceToggle }
                VStack(alignment: .leading, spacing: AASpacing.xs) {
                    HStack(spacing: AASpacing.s) { addAllButton; clearButton }
                    replaceToggle
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            BuilderBulkTextView(text: $bulkText)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            let lineCount = BuilderBulk.lines(bulkText).count
            Text(lineCount == 0 ? "One \(strings.noun) per line." : "\(lineCount) line\(lineCount == 1 ? "" : "s") ready to add.")
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .contentTransition(.numericText())
        }
        .padding(AASpacing.m)
    }

    private var addAllButton: some View {
        Button {
            addAll()
        } label: {
            Label("Add all", systemImage: "text.badge.plus")
        }
        .aaProminent()
        .controlSize(.small)
        .keyboardShortcut(.return, modifiers: .command)
        .help("Add every line as a new \(strings.noun) (⌘↩).")
        .fixedSize()
    }

    private var clearButton: some View {
        Button("Clear") { bulkText = "" }
            .controlSize(.small)
            .help("Clear the text box.")
            .fixedSize()
    }

    private var replaceToggle: some View {
        Toggle("Replace existing", isOn: $replaceExisting)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .help(strings.replaceHelp)
            .fixedSize()
    }

    private func addAll() {
        let added = engine.addAll(text: bulkText, replace: replaceExisting)
        guard !added.isEmpty else { return }
        bulkText = ""
        // Refresh keeping the previous selection by Id (BUILD-004).
        let ids = Set(engine.ids)
        selection = selection.filter { ids.contains($0) }
    }

    // MARK: Current items (BUILD-002 right, BUILD-003, BUILD-006…014)

    private var itemsPane: some View {
        let rows = engine.items.map(display)
        let count = rows.count
        return VStack(alignment: .leading, spacing: AASpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(strings.currentHeader).font(.aaMono(AAType.small, weight: .bold)).foregroundStyle(AAColor.fg)
                Text("\(count)").font(.aaMono(AAType.caption, weight: .semibold)).foregroundStyle(AAColor.muted)
                    .monospacedDigit()
                Spacer(minLength: 0)
                if !selection.isEmpty {
                    Text("\(selection.count) selected").font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted)
                }
            }
            BuilderCommandBar(groups: [
                [BuilderBarCommand(title: strings.addTitle, symbol: "plus", help: strings.addHelp) {
                    run { await add(at: engine.items.count) }
                 },
                 BuilderBarCommand(title: "Insert before", symbol: "arrow.up.to.line.compact", help: strings.insertBeforeHelp) {
                    run { await add(at: engine.insertIndex(before: true, selection: selection)) }
                 },
                 BuilderBarCommand(title: "Insert after", symbol: "arrow.down.to.line.compact", help: strings.insertAfterHelp) {
                    run { await add(at: engine.insertIndex(before: false, selection: selection)) }
                 },
                 BuilderBarCommand(title: "Edit…", symbol: "pencil", help: strings.editHelp, disabled: selection.isEmpty) {
                    editPrimary(selection)
                 }],
                [BuilderBarCommand(title: "Move up", symbol: "chevron.up", help: strings.upHelp,
                                   disabled: !engine.canMoveUp(selection), iconOnly: true) { moveUp() },
                 BuilderBarCommand(title: "Move down", symbol: "chevron.down", help: strings.downHelp,
                                   disabled: !engine.canMoveDown(selection), iconOnly: true) { moveDown() },
                 BuilderBarCommand(title: "Move to…", symbol: "arrow.up.and.down.text.horizontal", help: strings.moveToHelp,
                                   disabled: selection.isEmpty) { run { await moveTo() } }],
                [BuilderBarCommand(title: "Delete", symbol: "trash", help: "Delete the selected \(strings.noun)s.",
                                   disabled: selection.isEmpty) { run { await delete(selection) } }],
            ])
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        BuilderItemRowView(index: index + 1, row: row)
                            .tag(row.id)
                            .listRowSeparator(.visible)
                    }
                    .onMove { source, destination in
                        let moved = engine.dropMove(from: source, to: destination)
                        if !moved.isEmpty { selection = Set(moved) }
                    }
                }
                .onChange(of: scrollTarget) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) }
                    scrollTarget = nil
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            .overlay {
                if rows.isEmpty {
                    Text(strings.emptyListHint)
                        .font(.aaMono(AAType.small))
                        .foregroundStyle(AAColor.muted)
                        .multilineTextAlignment(.center)
                        .padding(AASpacing.xl)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
            .contextMenu(forSelectionType: UUID.self) { ids in
                contextMenu(ids)
            } primaryAction: { ids in
                editPrimary(ids)
            }
            .aaListCommands(listCommands)
        }
        .padding(AASpacing.m)
    }

    @ViewBuilder
    private func contextMenu(_ ids: Set<UUID>) -> some View {
        if !ids.isEmpty {
            Button("Edit…", systemImage: "pencil") { editPrimary(ids) }
            Divider()
            Button("Insert before…", systemImage: "arrow.up.to.line.compact") {
                selection = ids
                run { await add(at: engine.insertIndex(before: true, selection: ids)) }
            }
            Button("Insert after…", systemImage: "arrow.down.to.line.compact") {
                selection = ids
                run { await add(at: engine.insertIndex(before: false, selection: ids)) }
            }
            Divider()
            Button("Move Up", systemImage: "chevron.up") { selection = ids; moveUp() }
                .disabled(!engine.canMoveUp(ids))
            Button("Move Down", systemImage: "chevron.down") { selection = ids; moveDown() }
                .disabled(!engine.canMoveDown(ids))
            Button("Move to…", systemImage: "arrow.up.and.down.text.horizontal") { selection = ids; run { await moveTo() } }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { selection = ids; run { await delete(ids) } }
        } else {
            Button(strings.addTitle == "Item" ? "New Item…" : "New Subtask…", systemImage: "plus") {
                run { await add(at: engine.items.count) }
            }
        }
    }

    private var listCommands: ListCommands {
        ListCommands(role: .builderItems, selectionCount: selection.count,
                     deleteTitle: "Delete",
                     delete: { run { await delete(selection) } },
                     deleteConfirms: true,
                     canMoveUp: engine.canMoveUp(selection), canMoveDown: engine.canMoveDown(selection),
                     move: { dir in if dir == .up { moveUp() } else { moveDown() } },
                     moveTo: selection.isEmpty ? nil : { run { await moveTo() } },
                     primary: { editPrimary(selection) })
    }

    // MARK: Actions

    /// Serialises async flows so a double click cannot start two prompts at once.
    private func run(_ body: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            await body()
            busy = false
        }
    }

    /// BUILD-006…008: prompt "New item" / "Title:" (or "New subtask" / "Name:"); raw value; blank = no-op.
    private func add(at index: Int) async {
        guard engine.isBound,
              let title = await BuilderUI.nonBlankPrompt(dialogs, title: strings.promptTitle, prompt: strings.promptLabel),
              let id = engine.insert(title: title, at: index) else { return }
        withAnimation(.snappy(duration: 0.2)) { selection = [id] }
        scrollTarget = id
    }

    /// BUILD-010: the primary selected item (first in list order) opens in its editor; then Flush and refresh.
    private func editPrimary(_ ids: Set<UUID>) {
        guard let first = engine.selectedIndices(ids).first else { return }
        let id = engine.ids[first]
        run { await edit(id) }
    }

    private func moveUp() {
        guard engine.moveUp(selection) else { return }
    }

    private func moveDown() {
        guard engine.moveDown(selection) else { return }
    }

    /// BUILD-013: single-select picker titled `Move {n} item(s) to...`.
    private func moveTo() async {
        let n = engine.selectedIndices(selection).count
        guard n > 0 else { return }
        let options = engine.moveToOptions(selection)
        guard let target = await BuilderUI.pickOne(dialogs, prompt: BuilderWording.moveTitle(n, noun: strings.noun),
                                                   rows: options.map { (display: $0.display, tag: $0.target) })
        else { return }
        let moved = engine.moveTo(selection, target: target)
        guard let first = moved.first else { return }
        withAnimation(.snappy(duration: 0.2)) { selection = Set(moved) }
        scrollTarget = first
    }

    /// BUILD-014: "Confirm" / "Delete {n} item(s)?" → permanent removal.
    private func delete(_ ids: Set<UUID>) async {
        let n = engine.selectedIndices(ids).count
        guard n > 0 else { return }
        guard await BuilderUI.confirmDelete(dialogs, title: "Confirm",
                                            message: BuilderWording.deleteQuestion(n, noun: strings.noun)) else { return }
        engine.delete(ids)
        selection.subtract(ids)
    }
}

/// One builder row: position, title (strikethrough when done) and the muted due text.
struct BuilderItemRowView: View {
    let index: Int
    let row: BuilderRowDisplay

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
            Text("\(index).")
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .monospacedDigit()
                .frame(minWidth: 22, alignment: .trailing)
            Text(row.title.isEmpty ? " " : row.title)
                .font(.aaMono(AAType.body))
                .strikethrough(row.struck)
                .foregroundStyle(row.struck ? AAColor.muted : AAColor.fg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if row.nested > 0 {
                Label("\(row.nested)", systemImage: "arrow.turn.down.right")
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
                    .help("\(row.nested) deeper subtask\(row.nested == 1 ? "" : "s") — open this subtask's editor to work on them.")
            }
            if !row.trailing.isEmpty {
                Text(row.trailing)
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
        .animation(.easeOut(duration: 0.15), value: row.struck)
        .accessibilityElement(children: .combine)
    }
}

/// A wrapping button bar (BUILD-002: "a wrapping button bar").
struct BuilderFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Break into lines first, then centre every item vertically within its line.
        var lines: [[(Int, CGSize)]] = [[]]
        var x = bounds.minX
        for (i, s) in subviews.enumerated() {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                lines.append([])
                x = bounds.minX
            }
            lines[lines.count - 1].append((i, size))
            x += size.width + spacing
        }
        var y = bounds.minY
        for line in lines {
            let h = line.map(\.1.height).max() ?? 0
            var lx = bounds.minX
            for (i, size) in line {
                subviews[i].place(at: CGPoint(x: lx, y: y + (h - size.height) / 2), proposal: ProposedViewSize(size))
                lx += size.width + spacing
            }
            y += h + lineSpacing
        }
    }
}

/// The bulk-entry text box: monospaced, no wrapping, both scrollbars, no smart substitutions (BUILD-002, A28-style
/// raw text).
struct BuilderBulkTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = AAColor.NS.panelAlt
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.font = AAFont.mono(AAType.body)
        tv.textColor = AAColor.NS.fg
        tv.backgroundColor = AAColor.NS.panelAlt
        tv.drawsBackground = true
        tv.insertionPointColor = AAColor.NS.fg
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.textContainerInset = NSSize(width: 6, height: 6)
        // No wrapping: an unbounded container width and a horizontally resizable text view.
        tv.isHorizontallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.string = text
        tv.delegate = context.coordinator
        tv.setAccessibilityLabel("Bulk entry")
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let value = tv.string
            MainActor.assumeIsolated { text.wrappedValue = value }
        }
    }
}
