// Spec: 08 §2.3 (QUICK-100…107), §3.3 (scoring — F2's QuickSwitcherScoring; Move(delta) clamps, never wraps),
//       §6.2-C ("Open Quickly"-style NSPanel titled "Go to item", 620×480, centred over the main window, floating,
//       closes on Esc and on resign-key; the placeholder is rendered), Q-14; 02 REPO-107; DECISIONS 08 OQ-2 (floating
//       Open-Quickly panel), OQ-8 + REQ-F2-02 (rows built with the session lock state `env.locks.isGated`, so a locked
//       description never ranks); 03 SHELL-672 (↑ ↓ ↩ ⎋ in the query field), §6.5.1.5, SHELL-526 (excluded from the
//       Window menu); F3 REQ-F3-03 (the panel registers itself with `SceneOpener`); ARCHITECTURE.md §7.7, §8.4.
import AppKit
import SwiftUI
import AACore

/// ⌘O / ⇧⌘O — "Go to item".
@MainActor final class QuickSwitcherPanelController: NSObject, NSWindowDelegate {
    static let shared = QuickSwitcherPanelController()
    private var panel: SwitcherPanel?

    static let size = NSSize(width: 620, height: 480)

    /// A fresh switcher each time (Windows: a new modal window per Ctrl+O); an open one is just focused.
    func show(env: AppEnvironment) {
        if let p = panel, p.isVisible {
            p.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        if let old = panel { panel = nil; old.close() }
        let p = SwitcherPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.borderless, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
        p.title = SwitcherText.windowTitle
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .transient]
        p.contentMinSize = NSSize(width: 420, height: 300)
        p.delegate = self
        SceneOpener.shared.registerPanel(p, as: .switcher)
        let dialogs = SceneOpener.shared.dialogs(of: p) ?? .unbound
        let model = SwitcherModel(rows: QuickSwitcherScoring.rows(store: env.store, isGated: env.locks.isGated))
        let root = SwitcherView(model: model, onOpen: { [weak self] id in self?.open(id, env: env) },
                                onClose: { [weak self] in self?.close() })
            .environment(env)
            .environment(\.dialogs, dialogs)
            .environment(\.aaWindowRole, .switcher)
            .font(.aaMono(AAType.body))
            .tint(AAColor.tint)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        p.contentView = host
        p.setFrame(Self.centeredFrame(size: Self.size), display: false)
        panel = p
        NSApp.activate()
        p.makeKeyAndOrderFront(nil)
    }

    /// QUICK-107: close the switcher first, THEN navigate (the main window switches section and selects the item).
    private func open(_ id: UUID, env: AppEnvironment) {
        close()
        env.navigator.navigate(to: id)
    }

    func close() {
        guard let p = panel else { return }
        panel = nil
        p.orderOut(nil)
        p.close()
    }

    /// Centred over the main window (or the main screen).
    private static func centeredFrame(size: NSSize) -> NSRect {
        let anchor = SceneOpener.shared.window(for: .main)?.frame ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.midY - size.height / 2 + anchor.height * 0.08)
        if let vf = NSScreen.main?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
            origin.y = min(max(origin.y, vf.minY), vf.maxY - size.height)
        }
        return NSRect(origin: origin, size: size)
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // 08 §6.2-C: an Open-Quickly panel closes when it loses key status (an attached alert keeps it open).
        guard let p = panel, notification.object as? NSWindow === p, p.attachedSheet == nil else { return }
        // Only a DEBUG snapshot run keeps the panel up (ARCH §9.6); `snapshotMode` is never set in a release build,
        // where `--snapshot` prints its notice and the launch continues normally (SHELL-192).
        if LaunchCoordinator.shared.snapshotMode { return }
        close()
    }
}

/// A borderless panel that can take keyboard focus (borderless windows refuse key status by default).
final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// ⌘W / ⌘. / ⎋ close the switcher (03 §6.5.1.5).
    override func performClose(_ sender: Any?) { QuickSwitcherPanelController.shared.close() }
    override func cancelOperation(_ sender: Any?) { QuickSwitcherPanelController.shared.close() }
}

/// The switcher's state: the row snapshot, the query, the ranked rows and the selected index.
@MainActor @Observable
final class SwitcherModel {
    let all: [QuickSwitcherScoring.Row]
    var query = "" { didSet { if query != oldValue { rerank() } } }
    private(set) var ranked: [QuickSwitcherScoring.Row] = []
    var selected: Int?

    init(rows: [QuickSwitcherScoring.Row], query: String = "") {
        all = rows
        self.query = query
        rerank()
    }

    /// QUICK-105: re-ranked on every keystroke; the first row is selected after every refresh (when any).
    func rerank() {
        ranked = QuickSwitcherScoring.rank(all, query: query)
        selected = ranked.isEmpty ? nil : 0
    }

    /// QUICK-106 / §3.3.4.
    func move(_ delta: Int) { selected = SwitcherText.move(selected: selected, delta: delta, count: ranked.count) }

    var selectedRow: QuickSwitcherScoring.Row? { selected.flatMap { ranked.indices.contains($0) ? ranked[$0] : nil } }
}

struct SwitcherView: View {
    @Bindable var model: SwitcherModel
    let onOpen: (UUID) -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool
    @State private var hovered: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AAColor.muted)
                TextField(SwitcherText.prompt, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .regular))
                    .focused($focused)
                    .onKeyPress(.downArrow) { model.move(1); return .handled }
                    .onKeyPress(.upArrow) { model.move(-1); return .handled }
                    .onKeyPress(.return) { openSelected(); return .handled }
                    .onKeyPress(.escape) { onClose(); return .handled }
                    .onSubmit { openSelected() }
                Text("\u{2318}O")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AAColor.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AAColor.muted.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Rectangle().fill(AAColor.border).frame(height: 1)
            rowsView
            Rectangle().fill(AAColor.border).frame(height: 1)
            Text(SwitcherText.hint)
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.fg.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .background(AAColor.panel.opacity(0.92))
        .aaGlass(in: RoundedRectangle(cornerRadius: AARadius.floatingPanel, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: AARadius.floatingPanel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.floatingPanel, style: .continuous)
            .strokeBorder(AAColor.border, lineWidth: 1))
        .onAppear { focused = true }
        .onExitCommand { onClose() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SwitcherText.windowTitle)
    }

    private func openSelected() {
        if let r = model.selectedRow { onOpen(r.id) }
    }

    private var rowsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.ranked.enumerated()), id: \.element.id) { k, row in
                        SwitcherRow(row: row, selected: model.selected == k, hovered: hovered == row.id)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onHover { inside in hovered = inside ? row.id : (hovered == row.id ? nil : hovered) }
                            .onTapGesture(count: 2) { onOpen(row.id) }
                            .onTapGesture { model.selected = k }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .overlay {
                if model.ranked.isEmpty {
                    Text(SwitcherText.noMatches).font(.aaMono(AAType.body)).foregroundStyle(AAColor.muted)
                }
            }
            .onChange(of: model.selected) { _, k in
                guard let k, model.ranked.indices.contains(k) else { return }
                proxy.scrollTo(model.ranked[k].id)
            }
        }
    }
}

/// QUICK-102: kind chip (`KindLabel`; per-kind pastel fill with black text — sanctioned in Deviations/W-QUICK.md),
/// name (one line, no `(unnamed)` fallback), tags at 60 %.
struct SwitcherRow: View {
    let row: QuickSwitcherScoring.Row
    let selected: Bool
    let hovered: Bool

    var body: some View {
        HStack(spacing: AASpacing.m) {
            Text(row.kindLabel)
                .font(.aaMono(AAType.caption, weight: .semibold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(AAColor.kind(row.kind), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(AAColor.border.opacity(0.6), lineWidth: 0.5))
                .frame(width: 112, alignment: .leading)
            Text(row.name)
                .font(.aaMono(AAType.body, weight: .semibold))
                .foregroundStyle(selected ? AAColor.selectionFg : AAColor.fg)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: AASpacing.s)
            Text(SwitcherText.tags(row.tags))
                .font(.aaMono(AAType.caption))
                .foregroundStyle(selected ? AAColor.selectionFg.opacity(0.8) : AAColor.fg.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 22)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? AAColor.selectionBg : (hovered ? AAColor.hover : Color.clear))
        }
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}
