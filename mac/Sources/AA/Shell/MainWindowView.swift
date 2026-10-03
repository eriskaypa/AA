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
            SectionContentHost()
                .safeAreaInset(edge: .top, spacing: 0) { ShellBanners() }
                .safeAreaInset(edge: .bottom, spacing: 0) { ShellBottomBar(toolbarHidden: chrome.toolbarHidden) }
        }
        .navigationTitle(env.windowTitle)
        .navigationSubtitle(env.status.message)
        .toolbar(id: "main") { ShellMainToolbar() }
        .background(ShellWindowCapture { window in chrome.attach(window) })
        .onAppear { LaunchCoordinator.shared.mainWindowAppeared() }
        .frame(minWidth: 860, minHeight: 560)
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
                    .accessibilityHidden(s != selected)
                    .zIndex(s == selected ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: selected)
        .onAppear { visit(selected) }
        .onChange(of: selected) { _, s in visit(s) }
    }

    private func visit(_ s: SectionID) {
        if !visited.contains(s) { visited.append(s) }
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
        VStack(spacing: 0) {
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
