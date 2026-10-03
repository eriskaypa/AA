// Spec: 04 HIER-001/002 (one page per kind; sidebar 280 pt, resizable splitter, details fill), HIER-120 (navigation
//       requests, selected after the tab switch; Q-04/Q-05 by identity, revealed), HIER-121 (selection persistence),
//       HIER-122 (F2 rename), HIER-124 (status messages), HIER-125 (live refresh), §6.1 (HSplitView inside the main
//       shell), §6.9 (⇧⌘N, F2, ⌘⌫), 03 SHELL-540…542 (New {Kind}, Open in New Window, Rename via SectionCommands),
//       SHELL-654 (Tools ▸ Vessel ▸ via VesselActions), SHELL-517 (⌥⌘F → the sidebar search); ARCHITECTURE.md §7.2
//       (internal layouts use HSplitView), §7.6, §7.7.
import AppKit
import SwiftUI
import AACore

struct HierarchyTabView: View {
    let kind: ItemKind
    @Environment(AppEnvironment.self) private var env
    @State private var model: HierPageModel?

    init(kind: ItemKind) { self.kind = kind }

    var body: some View {
        Group {
            if let model {
                HierPageView(model: model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil { model = HierPageModel(kind: kind, env: env) }
        }
    }
}

struct HierPageView: View {
    @Bindable var model: HierPageModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    private var section: SectionID { SectionID.section(for: model.kind) }

    var body: some View {
        HierSplit(kind: model.kind) {
            HierSidebarPane(model: model)
        } detail: {
            HierDetailPane(model: model)
        }
        .aaSectionCommands(section, sectionCommands)
        .onAppear { handleNavigation() }
        .onChange(of: env.navigator.request(for: model.kind)?.id) { _, _ in handleNavigation() }
    }

    private var sectionCommands: SectionCommands {
        var c = SectionCommands(
            newItemTitle: section.newItemTitle,
            newItem: { model.newItem(dialogs: dialogs) },
            rename: { model.beginRename() },
            openInNewWindow: { model.openInWindow(model.selectedItems, dialogs: dialogs) },
            hierarchySelection: model.hierarchySelectionState,
            focusSearchField: { model.searchLocator.focus() },
            searchFieldIsFocused: model.searchLocator.isFocused)
        if model.kind == .vessel, let v = model.primaryItem, !env.locks.isGated(v) {
            c.vessel = VesselActions.menuActions(vesselID: v.id, env: env, dialogs: dialogs) { tab in
                switch tab {
                case .quickCards: model.detailTab = .quickCards
                case .workOrders: model.detailTab = .workOrders
                case .ports: model.detailTab = .ports
                }
            }
        }
        return c
    }

    /// HIER-120: select the requested item (by identity), reveal it, then consume the request.
    private func handleNavigation() {
        guard let request = env.navigator.request(for: model.kind) else { return }
        env.navigator.consume(request)
        model.navigate(to: request.itemID, childID: request.childID)
    }
}

/// HIER-002: sidebar (default 280 pt, 220…480) | 1-pt divider with a 7-pt drag handle | details (fill). The width is
/// remembered per kind for the window (§6.1 addition; Windows does not persist it).
struct HierSplit<Sidebar: View, Detail: View>: View {
    let kind: ItemKind
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail
    @SceneStorage("aa.hier.sidebarWidth") private var storedWidths = ""
    @State private var width: CGFloat = 280
    @State private var dragStart: CGFloat?
    @State private var hovering = false

    static var minWidth: CGFloat { 220 }
    static var maxWidth: CGFloat { 480 }

    var body: some View {
        GeometryReader { geo in
            let maxW = max(Self.minWidth, min(Self.maxWidth, geo.size.width - 360))
            let w = min(max(width, Self.minWidth), maxW)
            HStack(spacing: 0) {
                sidebar()
                    .frame(width: w)
                    .frame(maxHeight: .infinity)
                    .background(AAColor.panel.opacity(0.0))
                Rectangle()
                    .fill(hovering || dragStart != nil ? AAColor.tint.opacity(0.6) : AAColor.border)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .overlay {
                        Color.clear
                            .frame(width: 7)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                hovering = inside
                                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                            }
                            .gesture(DragGesture(minimumDistance: 1)
                                .onChanged { g in
                                    if dragStart == nil { dragStart = w }
                                    width = min(max((dragStart ?? w) + g.translation.width, Self.minWidth), maxW)
                                }
                                .onEnded { _ in
                                    dragStart = nil
                                    save()
                                })
                    }
                    .accessibilityHidden(true)
                detail()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { width = load() }
    }

    private func load() -> CGFloat {
        for pair in storedWidths.split(separator: ";") {
            let kv = pair.split(separator: "=")
            if kv.count == 2, Int(kv[0]) == kind.rawValue, let v = Double(kv[1]) { return CGFloat(v) }
        }
        return 280
    }

    private func save() {
        var parts = storedWidths.split(separator: ";").map(String.init).filter { !$0.hasPrefix("\(kind.rawValue)=") }
        parts.append("\(kind.rawValue)=\(Int(width))")
        storedWidths = parts.joined(separator: ";")
    }
}
