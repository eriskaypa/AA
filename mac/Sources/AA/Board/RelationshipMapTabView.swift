// Spec: 07 §3.5 VIEW-170…182 (Relationship Map: Inspect list with search, title, 1-hop graph of RelatedItems on a
//       310-pt circle in a 1400 × 900 canvas, solid centre edges and dashed neighbour edges, node style, click to
//       recentre, focus persistence in Ui.MapFocusedItemId), §7.5 (Mac: per-kind colours, animated recentre that also
//       selects the Inspect row, live redraw, optional zoom), 02 REPO-031, DECISIONS 07 Q-10, W-13 / W-14 / W-19 fixes,
//       VIEW-205 (navigation call site — double-click / context menu, Mac addition).
import AppKit
import SwiftUI
import AACore

@MainActor @Observable
final class MapPageModel {
    var query = ""
    var focusID: UUID?
    var zoom: Double = 1
    var hovered: UUID?
    @ObservationIgnored private(set) weak var store: AppStore?
    @ObservationIgnored private var loadedGeneration = -1

    static let minZoom = 0.35, maxZoom = 2.5

    /// VIEW-180 / VIEW-207: on (re)load, draw the persisted focus when it still resolves.
    func attach(_ store: AppStore) {
        guard self.store !== store || loadedGeneration != store.generation else { return }
        self.store = store
        loadedGeneration = store.generation
        focusID = MapLayout.persistedFocus(store: store)?.id
    }

    var centre: HierarchyItem? { focusID.flatMap { store?.item(id: $0) } }

    /// VIEW-173 / VIEW-179: recentre (the focus is written to Ui like CaptureUiState would; per-device, no dirty).
    func focus(_ id: UUID) {
        focusID = id
        if store?.data.ui.mapFocusedItemId != id { store?.data.ui.mapFocusedItemId = id }
    }

    func setZoom(_ z: Double) { zoom = min(max(z, Self.minZoom), Self.maxZoom) }
}

struct RelationshipMapTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = MapPageModel()
    @State private var selectedRow: String?

    var body: some View {
        let rows = MapLayout.filter(MapLayout.inspectRows(store: env.store), query: model.query)
        HSplitView {
            inspectPane(rows)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 380)
            MapCanvasPane(model: model)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .background(AAColor.bg)
        .onAppear {
            model.attach(env.store)
            syncSelection(rows)
        }
        .onChange(of: env.store.generation) { _, _ in
            model.attach(env.store)
            syncSelection(MapLayout.filter(MapLayout.inspectRows(store: env.store), query: model.query))
        }
        .onChange(of: model.focusID) { _, _ in syncSelection(rows) }
        .onChange(of: model.query) { _, _ in selectedRow = nil }        // VIEW-172: re-filtering clears the selection
        .aaSectionCommands(.map, SectionCommands())
    }

    private func inspectPane(_ rows: [MapInspectRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CalPaneTitle(title: MapLayout.inspectTitle, symbol: "point.3.connected.trianglepath.dotted")
            AASearchField(text: $model.query, prompt: "Search")
                .aaFilterField(for: .main)
                .padding(.horizontal, AASpacing.s)
                .padding(.bottom, AASpacing.s)
            List(selection: Binding(get: { selectedRow }, set: { id in
                selectedRow = id
                if let id, let row = rows.first(where: { $0.id == id }) {
                    withAnimation(.spring(duration: 0.45)) { model.focus(row.item.id) }
                }
            })) {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Circle().fill(AAColor.kind(row.item.kind)).frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(AAColor.border, lineWidth: 0.5))
                        Text(row.text)
                            .font(.aaMono(AAType.small))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .help(row.text)
                    .tag(row.id)
                }
            }
            .listStyle(.inset)
            .tint(AAColor.tint)
            .scrollContentBackground(.hidden)
            .aaListCommands(ListCommands(role: .relationships, selectionCount: selectedRow == nil ? 0 : 1))
            Text(rows.count == 1 ? "1 item" : "\(rows.count) items")
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .padding(.horizontal, AASpacing.m)
                .padding(.vertical, AASpacing.s)
        }
        .background(AAPaneBackground())
    }

    /// W-13 fix: the Inspect selection follows the centre (also after a node click).
    private func syncSelection(_ rows: [MapInspectRow]) {
        guard let id = model.focusID else { selectedRow = nil; return }
        if let current = selectedRow, rows.first(where: { $0.id == current })?.item.id == id { return }
        selectedRow = rows.first { $0.item.id == id }?.id
    }
}

// MARK: Map pane

private struct MapCanvasPane: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var model: MapPageModel
    @State private var position = ScrollPosition(edge: .top)
    @State private var offset: CGPoint = .zero
    @State private var dragStart: CGPoint?
    @State private var pinchBase: Double?
    @State private var viewport: CGSize = .zero

    var body: some View {
        let centre = model.centre
        let graph = centre.map { MapLayout.graph(centre: $0, store: env.store) }
        VStack(spacing: 0) {
            CalPageHeader(title: MapLayout.title(centre), subtitle: subtitle(graph),
                          symbol: "point.3.connected.trianglepath.dotted") {
                zoomControls
            }
            ZStack(alignment: .bottomLeading) {
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical]) {
                        MapGraphCanvas(model: model, graph: graph)
                            .frame(width: MapLayout.canvasWidth, height: MapLayout.canvasHeight)
                            .scaleEffect(model.zoom, anchor: .topLeading)
                            .frame(width: MapLayout.canvasWidth * model.zoom,
                                   height: MapLayout.canvasHeight * model.zoom, alignment: .topLeading)
                            .background(MapDotGrid(zoom: model.zoom))
                            .gesture(panGesture)
                    }
                    .scrollPosition($position)
                    .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { _, new in offset = new }
                    .simultaneousGesture(magnifyGesture)
                    .onAppear { viewport = geo.size }
                    .task {
                        // Once the scroll view has laid out, bring the focused node to the middle.
                        for _ in 0..<3 {
                            try? await Task.sleep(for: .milliseconds(120))
                            viewport = geo.size
                            centreView(animated: false)
                        }
                    }
                    .onChange(of: geo.size) { _, s in viewport = s }
                }
                .background(AAColor.bg)
                if graph == nil {
                    AAEmptyState(title: "Nothing to inspect yet", symbol: "point.3.connected.trianglepath.dotted",
                                 message: "Select an item in the Inspect list to draw it with its related items.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
                MapLegend()
                    .padding(AASpacing.m)
            }
        }
    }

    private func subtitle(_ g: MapGraph?) -> String {
        guard let g else { return "" }
        let n = g.related.count
        return (n == 1 ? "1 related item" : "\(n) related items") + "  \u{00B7}  click a node to recentre, double-click to open"
    }

    private var zoomControls: some View {
        HStack(spacing: AASpacing.s) {
            ControlGroup {
                Button { withAnimation(.snappy) { model.setZoom(model.zoom / 1.25) } } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(model.zoom <= MapPageModel.minZoom)
                Button { withAnimation(.snappy) { model.setZoom(1) }; centreView(animated: true) } label: {
                    Text("\(Int((model.zoom * 100).rounded()))%").monospacedDigit().frame(minWidth: 40)
                }
                .help("Actual size")
                Button { withAnimation(.snappy) { model.setZoom(model.zoom * 1.25) } } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .disabled(model.zoom >= MapPageModel.maxZoom)
            }
            .fixedSize()
            Button {
                let fit = min(viewport.width / MapLayout.canvasWidth, viewport.height / MapLayout.canvasHeight)
                withAnimation(.snappy) { model.setZoom(fit) }
                position.scrollTo(point: .zero)
            } label: {
                Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Fit the whole map in the window")
            .fixedSize()
            Button { centreView(animated: true) } label: { Label("Center", systemImage: "scope") }
                .help("Scroll the focused item to the middle")
                .fixedSize()
        }
        .labelStyle(.iconOnly)
    }

    /// Scrolls so the canvas centre (the focused node) sits in the middle of the viewport.
    private func centreView(animated: Bool) {
        let z = model.zoom
        let x = max(0, MapLayout.centre.x * z - viewport.width / 2)
        let y = max(0, MapLayout.centre.y * z - viewport.height / 2)
        if animated {
            withAnimation(.snappy) { position.scrollTo(point: CGPoint(x: x, y: y)) }
        } else {
            position.scrollTo(point: CGPoint(x: x, y: y))
        }
    }

    /// Drag on the background pans (trackpad scrolling pans too).
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { v in
                let start = dragStart ?? offset
                if dragStart == nil { dragStart = start }
                position.scrollTo(point: CGPoint(x: max(0, start.x - v.translation.width),
                                                 y: max(0, start.y - v.translation.height)))
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Pinch to zoom.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                let base = pinchBase ?? model.zoom
                if pinchBase == nil { pinchBase = base }
                model.setZoom(base * v.magnification)
            }
            .onEnded { _ in pinchBase = nil }
    }
}

/// A faint dot grid behind the graph (canvas texture; `Bg` stays the base colour).
private struct MapDotGrid: View {
    let zoom: Double

    var body: some View {
        Canvas { ctx, size in
            let step = 28 * zoom
            guard step > 4 else { return }
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)),
                             with: .color(AAColor.muted.opacity(0.22)))
                    x += step
                }
                y += step
            }
        }
        .background(AAColor.bg)
        .allowsHitTesting(false)
    }
}

/// Per-kind colour key (DECISIONS 07 Q-10).
private struct MapLegend: View {
    var body: some View {
        HStack(spacing: AASpacing.m) {
            ForEach(ItemKind.allKinds, id: \.rawValue) { k in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).fill(AAColor.kind(k)).frame(width: 12, height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.6), lineWidth: 0.5))
                    Text(k.name).font(.system(size: 11, weight: .medium)).foregroundStyle(AAColor.fg)
                }
            }
        }
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, 6)
        .aaGlass(in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Colour key: Equipment blue, Task orange, Procedure green, Vessel purple")
    }
}

// MARK: Graph

private struct MapEdgeKey: Hashable { let a: UUID; let b: UUID; let dashed: Bool }

private struct MapGraphCanvas: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var model: MapPageModel
    let graph: MapGraph?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let g = graph {
                let hovered = model.hovered
                // VIEW-177: edges beneath the nodes.
                ForEach(edges(g), id: \.key) { e in
                    let lit = hovered != nil && (e.key.a == hovered || e.key.b == hovered)
                    MapEdgeShape(from: e.from, to: e.to)
                        .stroke(e.key.dashed ? AAColor.muted : (lit ? AAColor.tint : AAColor.accent),
                                style: StrokeStyle(lineWidth: e.key.dashed ? 1 : (lit ? 2.5 : 1.5),
                                                   lineCap: .round, dash: e.key.dashed ? [4, 3] : []))
                        .opacity(e.key.dashed ? 0.6 : (lit ? 0.95 : 0.65))
                        .transition(.opacity)
                }
                ForEach(nodes(g), id: \.item.id) { n in
                    MapNodeView(item: n.item, isCentre: n.isCentre, model: model)
                        .position(n.point)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .zIndex(n.isCentre ? 2 : (hovered == n.item.id ? 3 : 1))
                }
            }
        }
        .animation(.spring(duration: 0.45), value: graph?.centre.id)
    }

    private struct Edge { let key: MapEdgeKey; let from: CGPoint; let to: CGPoint }
    private struct Node { let item: HierarchyItem; let point: CGPoint; let isCentre: Bool }

    private func point(_ id: UUID, _ g: MapGraph) -> CGPoint {
        let p = g.positions[id] ?? MapLayout.centre
        return CGPoint(x: p.x, y: p.y)
    }

    private func edges(_ g: MapGraph) -> [Edge] {
        var out: [Edge] = []
        let c = point(g.centre.id, g)
        for r in g.related {
            out.append(Edge(key: MapEdgeKey(a: g.centre.id, b: r.id, dashed: false), from: c, to: point(r.id, g)))
        }
        for (i, j) in g.dashedEdges {
            let a = g.related[i], b = g.related[j]
            out.append(Edge(key: MapEdgeKey(a: a.id, b: b.id, dashed: true), from: point(a.id, g), to: point(b.id, g)))
        }
        return out
    }

    private func nodes(_ g: MapGraph) -> [Node] {
        [Node(item: g.centre, point: point(g.centre.id, g), isCentre: true)]
            + g.related.map { Node(item: $0, point: point($0.id, g), isCentre: false) }
    }
}

/// An edge whose endpoints animate when the map recentres.
private struct MapEdgeShape: Shape {
    var from: CGPoint
    var to: CGPoint

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(from.x, from.y), AnimatablePair(to.x, to.y)) }
        set {
            from = CGPoint(x: newValue.first.first, y: newValue.first.second)
            to = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        p.addLine(to: to)
        return p
    }
}

/// VIEW-178 (+ DECISIONS 07 Q-10): rounded 8, pastel kind fill, black text and border (3 pt centre, 1 pt others),
/// padding 10 × 6, kind name (10) over the bold name (no wrapping).
private struct MapNodeView: View {
    @Environment(AppEnvironment.self) private var env
    let item: HierarchyItem
    let isCentre: Bool
    let model: MapPageModel

    var body: some View {
        let hovered = model.hovered == item.id
        VStack(alignment: .leading, spacing: 1) {
            Text(item.kind.name)
                .font(.system(size: 10))
                .foregroundStyle(.black.opacity(0.75))
            Text(item.name.isEmpty ? " " : item.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AAColor.kind(item.kind), in: RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous)
            .strokeBorder(.black.opacity(0.85), lineWidth: isCentre ? 3 : 1))
        .overlay {
            if isCentre {   // focus halo, visible on the dark canvas too
                RoundedRectangle(cornerRadius: AARadius.tile + 4, style: .continuous)
                    .stroke(AAColor.tint.opacity(0.7), lineWidth: 2)
                    .padding(-5)
            }
        }
        .shadow(color: .black.opacity(isCentre ? 0.28 : (hovered ? 0.25 : 0.12)), radius: isCentre ? 8 : (hovered ? 6 : 3),
                y: 2)
        .scaleEffect(hovered && !isCentre ? 1.05 : 1)
        .contentShape(RoundedRectangle(cornerRadius: AARadius.tile))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { model.hovered = h ? item.id : (model.hovered == item.id ? nil : model.hovered) } }
        .onTapGesture(count: 2) { env.navigator.navigate(to: item.id) }
        .onTapGesture { withAnimation(.spring(duration: 0.45)) { model.focus(item.id) } }   // VIEW-179
        .help("\(item.kind.name): \(item.name)\nClick to recentre \u{2022} double-click to open")
        .contextMenu {
            Button("Focus Here", systemImage: "scope") { withAnimation(.spring(duration: 0.45)) { model.focus(item.id) } }
            Button("Show in \(SectionID.section(for: item.kind).title)", systemImage: "arrow.right.circle") {
                env.navigator.navigate(to: item.id)
            }
            Button("Open in New Window", systemImage: "macwindow.badge.plus") { env.open(.item(item.id)) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isCentre ? "Focused item" : "Click to recentre the map on this item")
    }
}
