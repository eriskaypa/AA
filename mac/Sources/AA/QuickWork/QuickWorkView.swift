// Spec: 08 §2.2 (QUICK-040…084), §6.2-B (pinned board over an HSplitView: left list 360 pt, right detail; segmented
//       All / Tasks / Procedures; Section per bucket; `.contextMenu(forSelectionType:)`; strike-through; flush on
//       close), QUICK-082 (flush on close), QUICK-083 (re-point after reload), QUICK-084 (theme tokens; tile overdue
//       red fixed); DECISIONS 08 OQ-10 (friendly Status labels), OQ-5 (explicit "no date" control); 03 §6.5.1.5 (Quick
//       work: ⌘W close (flush), ⌥⌘F → filter); ARCHITECTURE.md §7.2 (HSplitView inside sections), §7.7, §8.
import AppKit
import SwiftUI
import AACore

/// ⌘N — "Quick work — all tasks & procedures".
struct QuickWorkView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var model = QuickWorkModel()
    @State private var subscription: EventSubscription?

    /// Debug snapshots pre-select an item.
    var initialSelection: UUID? = nil

    var body: some View {
        VStack(spacing: 10) {
            QuickWorkPinnedBoard(model: model)
            HSplitView {
                QuickWorkListPane(model: model)
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 560)
                QuickWorkDetailPane(model: model)
                    .frame(minWidth: 420, maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(AAColor.bg)
        .frame(minWidth: 900, idealWidth: 1200, minHeight: 600, idealHeight: 800)
        .navigationTitle(QuickWorkText.windowTitle)
        .onAppear {
            model.attach(env)
            if let id = initialSelection { model.select(id) }
            #if DEBUG
            if initialSelection == nil, let snap = LaunchCoordinator.shared.options.snapshot,
               snap.target == SceneID.quickWork.rawValue, let id = snap.select {
                model.select(id)
            }
            #endif
            let m = model
            subscription = env.store.dataReplaced.subscribe { [weak m] _ in m?.reloaded() }
        }
        .onDisappear {
            subscription?.cancel()
            subscription = nil
            QuickWorkFlows.flushIfDirty(env, dialogs: dialogs)                     // QUICK-082
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { n in
            // Q-11: changes made in other windows show up when this window comes back to the front.
            if let w = n.object as? NSWindow, w === SceneOpener.shared.window(for: .quickWork) { model.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { n in
            if let w = n.object as? NSWindow, w === SceneOpener.shared.window(for: .quickWork) {
                QuickWorkFlows.flushIfDirty(env, dialogs: dialogs)
            }
        }
    }
}

// MARK: - Panel chrome

/// A bordered, rounded `Panel` box with a `PanelAlt` header strip (08 QUICK-041).
struct QuickWorkPanelBox<Header: View, Content: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AAColor.panelAlt)
                .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
            content()
        }
        .background(AAColor.panel)
        .clipShape(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
    }
}

// MARK: - Pinned board (QUICK-060…064)

struct QuickWorkPinnedBoard: View {
    @Bindable var model: QuickWorkModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var collapsed = false

    var body: some View {
        QuickWorkPanelBox {
            HStack(spacing: 8) {
                Button { withAnimation(.snappy) { collapsed.toggle() } } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .foregroundStyle(AAColor.muted)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .help(collapsed ? "Show the pinned squares" : "Hide the pinned squares")
                Image(systemName: "pin.fill").foregroundStyle(AAColor.tint).rotationEffect(.degrees(30))
                Text(QuickWorkText.pinnedHeader).font(.aaMono(AAType.body, weight: .bold)).foregroundStyle(AAColor.accent)
                if !model.tiles.isEmpty {
                    Text("\(model.tiles.count)").font(.system(size: AAType.caption)).foregroundStyle(AAColor.muted)
                } else {
                    Text(QuickWorkText.pinnedHint)
                        .font(.system(size: AAType.caption))
                        .foregroundStyle(AAColor.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(QuickWorkText.pinnedHint)
                }
                Spacer(minLength: 0)
            }
        } content: {
            if !collapsed && !model.tiles.isEmpty {
                ScrollView(.vertical) {
                    QuickWorkFlowLayout(spacing: 8) {
                        ForEach(model.tiles) { tile in
                            QuickWorkTileView(tile: tile, isCurrent: tile.id == model.currentID,
                                              onSelect: { model.select(tile.id) },
                                              onUnpin: { QuickWorkFlows.togglePin(tile.id, env: env, dialogs: dialogs, model: model) },
                                              onDone: { QuickWorkFlows.setTileDone(tile.id, done: $0, env: env, dialogs: dialogs, model: model) })
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
                        }
                    }
                    .padding(8)
                    .animation(.snappy, value: model.tiles)
                }
                .frame(maxHeight: 240)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// QUICK-062: 172 pt wide, min 156 tall (grows with a wrapped name), radius 8, padding 9.
struct QuickWorkTileView: View {
    let tile: QuickWorkTile
    let isCurrent: Bool
    let onSelect: () -> Void
    let onUnpin: () -> Void
    let onDone: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: tile.kind == .task ? "checkmark.circle" : "list.clipboard")
                    .foregroundStyle(AAColor.kindGlyph(tile.kind))
                Text(tile.kindLabel).foregroundStyle(AAColor.muted)
                Spacer(minLength: 2)
                Button(action: onUnpin) {
                    Image(systemName: hovering ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(hovering ? AAColor.Status.danger : AAColor.muted)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help(QuickWorkText.unpinHelp)
            }
            .font(.system(size: 11))
            Text(tile.displayName)
                .font(.aaMono(AAType.body, weight: .bold))
                .foregroundStyle(AAColor.fg)
                .strikethrough(tile.isDone)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
            Spacer(minLength: 2)
            Text(tile.progressText).font(.system(size: 11)).foregroundStyle(AAColor.muted)
            if tile.progressTotal > 0 {
                ProgressView(value: tile.fraction)
                    .progressViewStyle(.linear)
                    .tint(AAColor.tint)
                    .controlSize(.small)
                    .padding(.top, 3)
            }
            HStack(spacing: 4) {
                if let chip = tile.deadlineText {
                    Text(chip)
                        .font(.system(size: 11, weight: tile.deadlineIsOverdue ? .semibold : .regular))
                        .foregroundStyle(tile.deadlineIsOverdue ? AAColor.Status.danger : AAColor.muted)
                        .monospacedDigit()
                }
                Spacer(minLength: 2)
                Toggle("Done", isOn: Binding(get: { tile.isDone }, set: { onDone($0) }))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }
            .padding(.top, 6)
        }
        .padding(9)
        .frame(width: 172, alignment: .topLeading)
        .frame(minHeight: 156, alignment: .topLeading)
        .background(tile.isDone ? AAColor.panelAlt : AAColor.panel,
                    in: RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous)
            .strokeBorder(isCurrent ? AAColor.tint : AAColor.border, lineWidth: isCurrent ? 2 : 1))
        .opacity(tile.isDone ? 0.72 : 1)
        .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: 6, y: 2)
        .scaleEffect(hovering ? 1.01 : 1)
        .contentShape(RoundedRectangle(cornerRadius: AARadius.tile))
        .onTapGesture(perform: onSelect)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .help(QuickWorkText.tileHelp)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tile.kindLabel): \(tile.displayName)")
    }
}

/// A simple wrapping flow (tiles, builder buttons).
struct QuickWorkFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Left list (QUICK-042…055)

struct QuickWorkListPane: View {
    @Bindable var model: QuickWorkModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        QuickWorkPanelBox {
            Text(QuickWorkText.listHeader)
                .font(.aaMono(15, weight: .bold))
                .foregroundStyle(AAColor.accent)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                controls
                list
                Text(model.listing.countLine)
                    .font(.system(size: AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Picker("", selection: $model.filter) {
                    ForEach(QuickWorkFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 4)
                Button { Task { await QuickWorkFlows.newItem(.task, env: env, dialogs: dialogs, model: model) } } label: {
                    Label(QuickWorkText.newTask, systemImage: "plus").labelStyle(.titleOnly)
                }
                .help("Create a task (it is added to the Tasks list).")
                Button { Task { await QuickWorkFlows.newItem(.procedure, env: env, dialogs: dialogs, model: model) } } label: {
                    Text(QuickWorkText.newProcedure)
                }
                .help("Create a procedure (it is added to the Procedures list).")
            }
            HStack(spacing: 6) {
                Button {
                    Task { await QuickWorkFlows.sortCurrentIntoBuckets(model.currentItem, env: env, dialogs: dialogs, model: model) }
                } label: { Label(QuickWorkText.sortIntoBuckets, systemImage: "tray.2") }
                    .help(QuickWorkText.sortIntoBucketsHelp)
                Button(QuickWorkText.removeFromBuckets) {
                    QuickWorkFlows.removeFromBuckets(model.currentItem, env: env, dialogs: dialogs, model: model)
                }
                .help(QuickWorkText.removeFromBucketsHelp)
            }
            .controlSize(.small)
            AASearchField(text: $model.query, prompt: QuickWorkText.searchPrompt)
                .aaFilterField(for: .quickWork)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var list: some View {
        List(selection: $model.selection) {
            if model.listing.isGrouped {
                ForEach(model.listing.groups) { g in
                    Section {
                        ForEach(g.rows) { QuickWorkRowView(row: $0).tag($0.id) }
                    } header: {
                        QuickWorkGroupHeader(group: g)
                    }
                }
            } else {
                ForEach(model.listing.rows) { QuickWorkRowView(row: $0).tag($0.id) }
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty { contextMenu(ids) }
        }
        .overlay {
            if model.listing.rows.isEmpty {
                AAEmptyState(title: model.query.isEmpty ? "No tasks or procedures" : "No matches",
                             symbol: "tray",
                             message: model.query.isEmpty ? "Use + Task or + Procedure to create one." : nil)
                    .allowsHitTesting(false)
            }
        }
        .aaListCommands(ListCommands(role: .quickWorkList, selectionCount: model.selection.count,
                                     deleteTitle: "Move to Trash\u{2026}",
                                     delete: model.currentItem == nil ? nil : {
                                         if let item = model.currentItem {
                                             Task { await QuickWorkFlows.delete(item, env: env, dialogs: dialogs, model: model) }
                                         }
                                     }))
    }

    /// QUICK-050: ✓ / ○ / 📅 · ─ · 🪣 / Remove.
    @ViewBuilder
    private func contextMenu(_ ids: Set<String>) -> some View {
        let items = model.items(forRowIDs: ids)
        Button { QuickWorkFlows.markDone(items, done: true, env: env, dialogs: dialogs, model: model) } label: {
            Label(QuickWorkText.markDone, systemImage: "checkmark.circle")
        }
        Button { QuickWorkFlows.markDone(items, done: false, env: env, dialogs: dialogs, model: model) } label: {
            Label(QuickWorkText.markNotDone, systemImage: "circle")
        }
        Button { Task { await QuickWorkFlows.setDeadline(items, env: env, dialogs: dialogs, model: model) } } label: {
            Label(QuickWorkText.setDeadline, systemImage: "calendar.badge.clock")
        }
        .help(QuickWorkText.setDeadlineHelp)
        Divider()
        let target = items.first { $0.id == model.currentID } ?? items.first
        Button {
            Task { await QuickWorkFlows.sortCurrentIntoBuckets(target, env: env, dialogs: dialogs, model: model) }
        } label: { Label(QuickWorkText.sortIntoBuckets, systemImage: "tray.2") }
        Button { QuickWorkFlows.removeFromBuckets(target, env: env, dialogs: dialogs, model: model) } label: {
            Label(QuickWorkText.removeFromBuckets, systemImage: "tray")
        }
    }
}

/// `🪣 {name} ({rowCount})` — icon and name in Accent, name bold, count muted (QUICK-046).
struct QuickWorkGroupHeader: View {
    let group: QuickWorkGroup

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: group.key.isEmpty ? "tray" : "tray.2.fill")
                .foregroundStyle(group.key.isEmpty ? AAColor.muted : AAColor.tint)
            Text(group.name).font(.aaMono(AAType.small, weight: .bold)).foregroundStyle(AAColor.accent)
            Text("(\(group.rows.count))").font(.system(size: AAType.caption)).foregroundStyle(AAColor.muted)
        }
        .accessibilityLabel(group.header)
    }
}

/// QUICK-044: bold title (struck through when done), muted 11-pt subtitle; both wrap.
struct QuickWorkRowView: View {
    let row: QuickWorkRow

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.isDone ? "checkmark.circle.fill" : (row.kind == .task ? "circle" : "list.clipboard"))
                .foregroundStyle(row.isDone ? AAColor.Status.ok : AAColor.kindGlyph(row.kind))
                .font(.system(size: 13))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.aaMono(AAType.body, weight: .bold))
                    .strikethrough(row.isDone)
                    .foregroundStyle(row.isDone ? AAColor.muted : AAColor.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.subtitle)
                    .font(.system(size: AAType.caption))
                    .foregroundStyle(row.subtitle.contains("OVERDUE") && !row.isDone ? AAColor.Status.danger : AAColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
