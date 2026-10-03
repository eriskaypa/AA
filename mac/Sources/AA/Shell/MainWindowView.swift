// Spec: 03 SHELL-006 (main window), SHELL-020/021/022 (title, header → toolbar, status line), SHELL-023 (shared-save
//       indicator; bottom bar while the toolbar is hidden, SHELL-526), SHELL-024 (shortcut strip), SHELL-025/026 (13
//       sections; page state survives switching), §6.2 (Mac layout), 01 §6.8 (foreign settings banner), §6.10 (safe-mode
//       banner); ARCHITECTURE.md §7.2.
import AppKit
import SwiftUI
import AACore

struct MainWindowView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var chrome = ShellMainChromeState()

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SectionSidebar()
                .navigationSplitViewColumnWidth(min: 196, ideal: 228, max: 320)
        } detail: {
            // The shortcut strip / bottom bar is laid out BELOW the sections, not as a safe-area inset: the AppKit
            // split views behind a section's `HSplitView` ignore SwiftUI insets, so their panes (and lists) would
            // run under the strip (REQ-W-CREW-01).
            // The banners are laid out ABOVE the sections for the same reason (01 DATA-021, §6.8, §6.10, DATA-174,
            // DATA-180, DATA-184): one banner row under the toolbar, the content below it.
            VStack(spacing: 0) {
                ShellBanners()
                SectionContentHost()
                ShellBottomBar(toolbarHidden: chrome.toolbarHidden)
            }
        }
        .navigationTitle(env.windowTitle)
        .navigationSubtitle(subtitle)
        .toolbar(id: "main") { ShellMainToolbar() }
        .background(ShellWindowCapture { window in chrome.attach(window) })
        .onAppear { LaunchCoordinator.shared.mainWindowAppeared() }
        .frame(minWidth: 860, minHeight: 560)
    }

    /// SHELL-022 status line; a read-only copy leads with `"Read-Only"` (01 DATA-174, REQ-W-PERSIST-02). Paths are shown
    /// abbreviated (`~`, middle-truncated); the full text is the status button's help and the history popover.
    private var subtitle: String {
        let m = ShellStatusText.subtitleDisplay(env.status.message)
        guard env.isReadOnlyInstance else { return m }
        return m.isEmpty ? PersistReadOnlyText.windowSubtitle : "\(PersistReadOnlyText.windowSubtitle) — \(m)"
    }
}

/// Tracks main-window chrome the SwiftUI view cannot observe directly (toolbar visibility, SHELL-526).
@MainActor @Observable
final class ShellMainChromeState {
    var toolbarHidden = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    func attach(_ window: NSWindow) {
        guard observation == nil, let toolbar = window.toolbar else {
            if window.toolbar == nil {
                Task { @MainActor [weak self, weak window] in
                    try? await Task.sleep(for: .milliseconds(200))
                    if let window { self?.attach(window) }
                }
            }
            return
        }
        toolbarHidden = !toolbar.isVisible
        observation = toolbar.observe(\.isVisible, options: [.new]) { [weak self] tb, _ in
            MainActor.assumeIsolated { self?.toolbarHidden = !tb.isVisible }
        }
    }
}

// MARK: Content host

extension EnvironmentValues {
    /// False while a visited section is kept alive but hidden (`SectionContentHost`). A page whose model is expensive
    /// to rebuild marks itself stale instead of rebuilding while this is false, and rebuilds on the change to true.
    @Entry var aaSectionIsVisible: Bool = true
}

/// Shows the selected section's root; visited roots stay alive (opacity / hit testing) so page state survives
/// switching, like WPF tabs (ARCH §7.2).
struct SectionContentHost: View {
    @Environment(AppEnvironment.self) private var env
    @State private var visited: [SectionID] = []

    var body: some View {
        let selected = env.navigator.selectedSection
        ZStack {
            ForEach(visited, id: \.self) { s in
                ShellSectionRoot(section: s)
                    .opacity(s == selected ? 1 : 0)
                    .allowsHitTesting(s == selected)
                    // A hidden page keeps its state but leaves the key-view loop and its keyboard shortcuts (HIER-025).
                    .disabled(s != selected)
                    .accessibilityHidden(s != selected)
                    // V2-SCALE: pages that rebuild whole-database models (Calendar, Board, Buckets) read this to
                    // suspend observation-driven rebuilds while hidden and rebuild once when shown again.
                    .environment(\.aaSectionIsVisible, s == selected)
                    .zIndex(s == selected ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: selected)
        .onAppear { visit(selected) }
        .onChange(of: selected) { _, s in
            visit(s)
            // HIER-025/040/120: keystrokes after a section switch must never reach the page just hidden (WPF removes
            // an unselected tab from the visual tree, so it cannot keep keyboard focus).
            DispatchQueue.main.async { ShellFocus.leaveHiddenSection(in: LaunchCoordinator.shared.mainWindow) }
        }
    }

    private func visit(_ s: SectionID) {
        if !visited.contains(s) { visited.append(s) }
    }
}

/// Keyboard focus in the main window: after a section switch (and at launch) the first responder moves to the section
/// sidebar unless it is already there, so it can never stay in a page that is kept alive but hidden.
@MainActor
enum ShellFocus {
    /// The sidebar list (the first column of the main window's `NavigationSplitView`).
    static func sidebarList(in window: NSWindow) -> NSView? {
        guard let root = window.contentView else { return nil }
        func firstSplit(_ v: NSView) -> NSSplitView? {
            if let s = v as? NSSplitView, s.arrangedSubviews.count >= 2 { return s }
            for sv in v.subviews { if let r = firstSplit(sv) { return r } }
            return nil
        }
        func firstTable(_ v: NSView) -> NSView? {
            if v is NSTableView { return v }
            for sv in v.subviews { if let r = firstTable(sv) { return r } }
            return nil
        }
        guard let split = firstSplit(root), let column = split.arrangedSubviews.first else { return nil }
        return firstTable(column)
    }

    /// The view that currently has keyboard focus (the field editor resolves to the field it edits).
    static func focusedView(in window: NSWindow) -> NSView? {
        guard let r = window.firstResponder else { return nil }
        if let tv = r as? NSTextView, tv.isFieldEditor, let owner = tv.delegate as? NSView { return owner }
        return r as? NSView
    }

    static func leaveHiddenSection(in window: NSWindow?) {
        guard let window else { return }
        let sidebar = sidebarList(in: window)
        if let sidebar, let focused = focusedView(in: window), focused === sidebar || focused.isDescendant(of: sidebar) {
            return
        }
        if let sidebar, window.makeFirstResponder(sidebar) { return }
        window.makeFirstResponder(nil)
    }
}

/// The owner's root view for a section (ARCH §7.7).
struct ShellSectionRoot: View {
    let section: SectionID

    var body: some View {
        Group {
            switch section {
            case .equipment: HierarchyTabView(kind: .equipment)
            case .tasks: HierarchyTabView(kind: .task)
            case .procedures: HierarchyTabView(kind: .procedure)
            case .vessels: HierarchyTabView(kind: .vessel)
            case .calendar: CalendarTabView()
            case .board: BoardTabView()
            case .planner: PlannerTabView()
            case .map: RelationshipMapTabView()
            case .crew: CrewTabView()
            case .lists: SavedListsTabView()
            case .buckets: BucketsTabView()
            case .ports: PortsDatabaseTabView()
            case .sire: SireTabView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Banners (safe mode, read-only instance, data-file conflict, foreign settings paths)

struct ShellBanners: View {
    @Environment(AppEnvironment.self) private var env
    @State private var foreignDismissed = MacPreferences.shared.bool(.shellForeignPathsBannerDismissed, default: false)

    var body: some View {
        ShellBannerStack {
            if env.isSafeMode {
                AABanner(style: .danger,
                         text: "Read-only safe mode — the data file couldn't be read; nothing will be saved.")
                    .transition(.aaBanner)
            }
            if env.isReadOnlyInstance {
                ReadOnlyInstanceBanner().transition(.aaBanner)
            }
            DataFileConflictBanner()
            if !foreignDismissed, !env.settings.foreignPathKeys.isEmpty {
                AABanner(style: .warning,
                         text: "This settings file came from Windows — choose the shared save file for this Mac.",
                         actions: [
                            AABannerAction(title: "Choose…", isProminent: true) {
                                env.router.perform(.setSharedSaveFile)
                            },
                            AABannerAction(title: "Dismiss") {
                                withAnimation(.snappy) { foreignDismissed = true }
                                MacPreferences.shared.set(true, .shellForeignPathsBannerDismissed)
                            },
                         ])
                    .transition(.aaBanner)
            }
        }
        .animation(.snappy, value: env.isSafeMode)
        .animation(.snappy, value: env.isReadOnlyInstance)
    }
}

/// Stacks the banners vertically at the detail column's width. The wrapping banner texts use
/// `fixedSize(horizontal: false, vertical: true)`; when AppKit asks the hosting view for its minimum size it proposes a
/// near-zero width, at which such a text is thousands of points tall — and the split view then grew past the window
/// (V-01: 1045 pt with one banner, 4211 pt with two). Measuring never narrower than `minMeasureWidth` keeps every banner
/// one or two lines high whatever the query.
struct ShellBannerStack: Layout {
    static let minMeasureWidth: CGFloat = 560

    private func measureWidth(_ proposal: ProposedViewSize) -> CGFloat {
        max(proposal.width ?? Self.minMeasureWidth, Self.minMeasureWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = measureWidth(proposal)
        let h = subviews.reduce(0) { $0 + $1.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = max(bounds.width, 1)
        var y = bounds.minY
        for v in subviews {
            let h = v.sizeThatFits(ProposedViewSize(width: max(w, Self.minMeasureWidth), height: nil)).height
            v.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: h))
            y += h
        }
    }
}

extension MacPreferences.Key {
    static let shellForeignPathsBannerDismissed = MacPreferences.Key("aa.shell.foreignPathsBannerDismissed")
}

// MARK: Bottom bar (shortcut strip + shared indicator while the toolbar is hidden)

struct ShellBottomBar: View {
    @Environment(AppEnvironment.self) private var env
    let toolbarHidden: Bool

    var body: some View {
        let showStrip = env.store.data.ui.showShortcutBar
        let showShared = toolbarHidden && ShellSharedIndicatorModel(env: env).isVisible
        if showStrip || showShared {
            HStack(spacing: AASpacing.s) {
                if showShared { SharedSaveIndicator() }
                if showStrip { ShortcutStrip() }
            }
            .padding(.horizontal, AASpacing.m)
            .padding(.vertical, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// SHELL-024 / §6.2: `⌨  ⌘S Save · ⌘F Search · …` with the key names semibold, and the ✕ hide button.
struct ShortcutStrip: View {
    @Environment(AppEnvironment.self) private var env

    static let items: [(key: String, label: String)] = [
        ("⌘S", "Save"), ("⌘F", "Search"), ("⌘N", "Quick work"), ("⌘O", "Go to (quick switcher)"),
        ("⌘R", "Due-dates window"), ("⌘1…9", "Switch tab"), ("F2", "Rename"), ("⌘Z", "Undo delete"),
    ]

    var body: some View {
        HStack(spacing: AASpacing.s) {
            Image(systemName: "keyboard").font(.system(size: AAType.strip)).foregroundStyle(AAColor.muted)
                .accessibilityLabel("Keyboard shortcuts")
            Text(stripText)
                .font(.system(size: AAType.strip))
                .foregroundStyle(AAColor.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                env.setShortcutBarVisible(false)
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AAColor.muted)
            .help("Hide this shortcuts strip (View ▸ Shortcut Bar to bring it back).")
            .accessibilityLabel("Hide the shortcuts strip")
        }
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, 5)
        .aaGlass(in: Capsule())
    }

    private var stripText: AttributedString {
        var s = AttributedString()
        for (i, item) in Self.items.enumerated() {
            if i > 0 { s += AttributedString(" · ") }
            var k = AttributedString(item.key)
            k.font = .system(size: AAType.strip, weight: .semibold)
            k.foregroundColor = AAColor.fg
            s += k
            s += AttributedString(" " + item.label)
        }
        return s
    }
}
