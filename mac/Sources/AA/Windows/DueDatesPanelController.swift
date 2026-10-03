// Spec: 08 §2.1 (QUICK-001…025), §3.1, §6.2-A (borderless NSPanel hosting SwiftUI: `.floating`, `isFloatingPanel`,
//       `hidesOnDeactivate = false`, `canBecomeKey`, full-screen auxiliary, clear background + shadow, 12-pt rounded
//       content, min 260×220, title "Overdue, today & tomorrow", header-only drag, corner grip + native edge resize,
//       size persisted to `Ui.DueWindowWidth/Height` on every change, bottom-right initial frame, single instance,
//       SF Symbols for the glyphs, `.checkbox` toggles, animated removal, `NSCalendarDayChanged` refresh — Q-5 fix),
//       §6.5 (no taskbar → excluded from the Window menu); 09 CREW-090; 02 REPO-044, REPO-114; 03 §6.5.1.5 (⌘W closes
//       through a custom `performClose`, ⎋ does nothing); F3 REQ-F3-03 (registers with `SceneOpener`);
//       ARCHITECTURE.md §7.7, §8.2 (floating colours), §8.4 (header glass).
import AppKit
import SwiftUI
import AACore

/// The floating due-dates panel (⌘R, toolbar Due, Tools menu, notification click, digest).
@MainActor final class DueDatesPanelController: NSObject, NSWindowDelegate {
    static let shared = DueDatesPanelController()

    private var panel: DuePanel?
    private weak var env: AppEnvironment?
    private let model = DueModel()
    private var subscriptions: [EventSubscription] = []
    private var dayObserver: NSObjectProtocol?
    private var applyingFrame = false

    var isVisible: Bool { panel?.isVisible ?? false }

    /// QUICK-001: re-open = `Activate()` then `Refresh()` (every entry point — ⌘R, toolbar, Tools menu, notification
    /// click, digest — goes through here, so none can show a stale list); else create, size from `Ui`, place
    /// bottom-right, show.
    func show(env: AppEnvironment) {
        self.env = env
        if let p = panel {
            p.makeKeyAndOrderFront(nil)
            refresh()
            return
        }
        let p = DuePanel(contentRect: NSRect(x: 0, y: 0, width: DueWindowGeometry.defaultWidth,
                                             height: DueWindowGeometry.defaultHeight),
                         styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        p.title = DueList.windowTitle
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        p.contentMinSize = NSSize(width: DueWindowGeometry.minWidth, height: DueWindowGeometry.minHeight)
        p.minSize = p.contentMinSize
        p.delegate = self
        SceneOpener.shared.registerPanel(p, as: .due)
        let dialogs = SceneOpener.shared.dialogs(of: p) ?? .unbound
        let root = DueDatesView(model: model,
                                onRefresh: { [weak self] in self?.refresh() },
                                onClose: { [weak self] in self?.close() },
                                onResize: { [weak self] dx, dy in self?.resizeBy(dx: dx, dy: dy) })
            .frame(minWidth: DueWindowGeometry.minWidth, maxWidth: .infinity,
                   minHeight: DueWindowGeometry.minHeight, maxHeight: .infinity)
            .environment(env)
            .environment(\.dialogs, dialogs)
            .environment(\.aaWindowRole, .due)
            .font(.aaMono(AAType.body))
            .tint(AAColor.tint)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        p.contentView = host
        panel = p
        subscribe(env)
        refresh()
        let frame = initialFrame(env: env)
        applyingFrame = true
        p.setFrame(frame, display: false)
        p.makeKeyAndOrderFront(nil)
        p.setFrame(frame, display: true)
        applyingFrame = false
    }

    /// QUICK-007: rebuild the lists ("today" evaluated now).
    func refresh() {
        guard let env else { return }
        model.update(DueListBuilder.build(store: env.store, today: env.clock.today()))
    }

    /// QUICK-023: ✕ / ⌘W closes; the panel is recreated (and placed bottom-right again) on the next show.
    func close() {
        guard let p = panel else { return }
        panel = nil
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        if let o = dayObserver { NotificationCenter.default.removeObserver(o); dayObserver = nil }
        p.orderOut(nil)
        p.close()
    }

    // MARK: Frame (QUICK-004 … QUICK-006)

    private func initialFrame(env: AppEnvironment) -> NSRect {
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let ui = env.store.data.ui
        let size = DueWindowGeometry.restoredSize(width: ui.dueWindowWidth, height: ui.dueWindowHeight,
                                                  maxWidth: vf.width - 2 * DueWindowGeometry.inset,
                                                  maxHeight: vf.height - 2 * DueWindowGeometry.inset)
        let o = DueWindowGeometry.initialOrigin(visibleX: vf.minX, visibleY: vf.minY, visibleWidth: vf.width,
                                                width: size.width)
        return NSRect(x: o.x, y: o.y, width: size.width, height: size.height)
    }

    /// The corner grip: `Width = max(MinWidth, Width + dx)`, `Height = max(MinHeight, Height + dy)`, keeping the
    /// top-left corner where it is (AppKit y grows upward).
    private func resizeBy(dx: CGFloat, dy: CGFloat) {
        guard let p = panel else { return }
        var f = p.frame
        let w = max(DueWindowGeometry.minWidth, f.width + dx)
        let h = max(DueWindowGeometry.minHeight, f.height + dy)
        f.origin.y += f.height - h
        f.size = NSSize(width: w, height: h)
        p.setFrame(f, display: true)
    }

    /// QUICK-006 / §6.2-A: every size change is written to `Ui.DueWindowWidth/Height` with MarkDirty (persisting during
    /// the resize is deliberate — writing only on close missed the debounce at shutdown).
    func windowDidResize(_ notification: Notification) {
        guard !applyingFrame, let p = panel, notification.object as? NSWindow === p, let env else { return }
        let size = p.contentRect(forFrameRect: p.frame).size
        let v = DueWindowGeometry.persisted(width: size.width, height: size.height)
        let ui = env.store.data.ui
        guard ui.dueWindowWidth != v.width || ui.dueWindowHeight != v.height else { return }
        ui.dueWindowWidth = v.width
        ui.dueWindowHeight = v.height
        env.store.markDirty()
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === panel { panel = nil }
    }

    // MARK: Live refresh (QUICK-007, QUICK-024, Q-5)

    private func subscribe(_ env: AppEnvironment) {
        subscriptions.forEach { $0.cancel() }
        // `saved` is already forwarded by AppEnvironment while visible; reloads replace the whole graph.
        subscriptions = [env.store.dataReplaced.subscribe { [weak self] _ in self?.refresh() }]
        if dayObserver == nil {
            dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil,
                                                                 queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }
}

/// Borderless windows refuse key status by default; this one takes it (clicking it focuses it like the WPF window).
final class DuePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// ⌘W (Window ▸ Close) closes through the controller; ⎋ does nothing (faithful).
    override func performClose(_ sender: Any?) { DueDatesPanelController.shared.close() }
}

/// The observed list (rebuilt by the controller).
@MainActor @Observable
final class DueModel {
    private(set) var list = DueList()

    func update(_ l: DueList) {
        guard l != list else { return }
        withAnimation(.snappy(duration: 0.25)) { list = l }
    }
}

struct DueDatesView: View {
    let model: DueModel
    let onRefresh: () -> Void
    let onClose: () -> Void
    let onResize: (CGFloat, CGFloat) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.list.sections.enumerated()), id: \.element.id) { k, s in
                        DueSectionView(section: s, isFirst: k == 0, onTick: tick, onOpen: open)
                    }
                    if model.list.isEverythingEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(AAColor.Status.ok)
                            Text(DueList.emptyMessage)
                                .font(.aaMono(AAType.body))
                                .foregroundStyle(AAColor.muted)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.automatic)
        }
        .background(AAColor.panel)
        .clipShape(RoundedRectangle(cornerRadius: AARadius.floatingPanel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.floatingPanel, style: .continuous)
            .strokeBorder(AAColor.border, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            DueResizeGrip(onDrag: onResize).padding(.trailing, 2).padding(.bottom, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DueList.windowTitle)
    }

    // MARK: Header (QUICK-003, QUICK-011)

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Image(systemName: "pin.fill").font(.system(size: 14, weight: .semibold)).rotationEffect(.degrees(30))
                    Text(DueList.headerTitle).font(.aaMono(AAType.title, weight: .bold))
                }
                .foregroundStyle(.white)
                Text(model.list.headerSubtitle)
                    .font(.aaMono(AAType.caption))
                    .monospacedDigit()
                    .foregroundStyle(AAColor.Status.floatingTint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            DueHeaderButton(symbol: "arrow.clockwise", help: DueList.refreshHelp, action: onRefresh)
            DueHeaderButton(symbol: "xmark", help: DueList.closeHelp, action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(LinearGradient(colors: [AAColor.Status.floatingHeaderStart, AAColor.Status.floatingHeaderEnd],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .gesture(WindowDragGesture())
    }

    // MARK: Actions

    /// QUICK-022: tick → `BatchDone.setDone`; changed → MarkDirty + FlushIfDirty; then rebuild (the save also
    /// refreshes through `saved`). Unticking is only reachable in theory (done rows are never listed).
    private func tick(_ row: DueRow, _ done: Bool) {
        if DueListBuilder.setDone(row.completable, done: done, store: env.store) {
            QuickWorkPersist.flush(env, dialogs: dialogs)
        }
        Task { @MainActor in onRefresh() }
    }

    /// QUICK-020: rows navigate; the floating window stays open.
    private func open(_ row: DueRow) {
        switch row.target {
        case .item(let id, let child): env.navigator.navigate(to: id, childID: child)
        case .crew(let id): env.navigator.navigateToCrew(id)
        case .none: break
        }
    }
}

struct DueHeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(hovering ? 0.22 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// QUICK-008: `{LABEL}   ({count})`, then the rows or `— nothing —`.
struct DueSectionView: View {
    let section: DueSection
    let isFirst: Bool
    let onTick: (DueRow, Bool) -> Void
    let onOpen: (DueRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(section.header)
                .font(.aaMono(AAType.small, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(section.isOverdue ? AAColor.Status.floatingOverdue : AAColor.muted)
                .padding(.leading, 2)
                .padding(.bottom, 1)
            if section.rows.isEmpty {
                Text(DueList.nothingLine)
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .padding(.leading, 6)
            } else {
                ForEach(section.rows) { row in
                    DueRowView(row: row, onTick: onTick, onOpen: onOpen)
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .move(edge: .leading))))
                }
            }
        }
        .padding(.top, isFirst ? 0 : 14)
    }
}

/// QUICK-010: PanelAlt card, 4-pt accent bar, done checkbox, tinted glyph, title + muted subtitle (both wrap).
struct DueRowView: View {
    let row: DueRow
    let onTick: (DueRow, Bool) -> Void
    let onOpen: (DueRow) -> Void
    @State private var hovering = false
    @State private var ticked = false

    private var accent: Color { Color(nsColor: AAColor.hex(row.accent.hex)) }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Toggle("", isOn: Binding(get: { ticked }, set: { v in
                ticked = v
                onTick(row, v)
            }))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(DueList.markDoneHelp)
            .padding(.top, 1)
            Image(systemName: row.icon.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 24)
                .accessibilityLabel(row.icon.glyph)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.aaMono(AAType.body))
                    .foregroundStyle(AAColor.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.subtitle)
                    .font(.aaMono(AAType.caption))
                    .monospacedDigit()
                    .foregroundStyle(AAColor.Status.neutral)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if row.isClickable && hovering {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AAColor.muted)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 8 + 4)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
                    .fill(hovering && row.isClickable ? AAColor.hover : AAColor.panelAlt)
                Rectangle().fill(accent).frame(width: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
            .strokeBorder(AAColor.border.opacity(0.6), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { if row.isClickable { onOpen(row) } }
        // QUICK-010 / QUICK-020: hand over clickable rows, arrow elsewhere. A declarative pointer style (not an
        // NSCursor push/pop pair) so a row removed under the mouse by its own tick (QUICK-022) cannot leak a cursor.
        .pointerStyle(row.isClickable ? .link : nil)
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.isClickable ? .isButton : [])
    }
}

/// QUICK-006: the 18×18 corner grip (three diagonal strokes, Muted, 1.5 pt), tooltip "Drag to resize".
struct DueResizeGrip: View {
    let onDrag: (CGFloat, CGFloat) -> Void
    @State private var last: CGPoint?

    var body: some View {
        Canvas { ctx, _ in
            var p = Path()
            p.move(to: CGPoint(x: 16, y: 4)); p.addLine(to: CGPoint(x: 4, y: 16))
            p.move(to: CGPoint(x: 16, y: 9)); p.addLine(to: CGPoint(x: 9, y: 16))
            p.move(to: CGPoint(x: 16, y: 14)); p.addLine(to: CGPoint(x: 14, y: 16))
            ctx.stroke(p, with: .color(AAColor.muted), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .frame(width: 18, height: 18)
        .contentShape(Rectangle())
        .help(DueList.resizeHelp)
        .pointerStyle(.frameResize(position: .bottomTrailing))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                // Screen coordinates: the grip moves with the window while it resizes, so view-relative
                // translations would feed back. AppKit's y grows upward → a downward drag grows the height.
                let m = NSEvent.mouseLocation
                if let l = last { onDrag(m.x - l.x, l.y - m.y) }
                last = m
            }
            .onEnded { _ in last = nil })
        .accessibilityLabel(DueList.resizeHelp)
    }
}
