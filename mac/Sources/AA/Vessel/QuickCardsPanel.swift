// Spec: 10 §B (VESSEL-010 header, 011 canvas + SizeCanvas, 012 empty state, 013 card rendering, 014 readable
//       foreground, 015 tooltip, 016 grip, 017 drag to move, 018 resize, 019 double-click opens, 020 context menu,
//       021 add, 022 edit, 023 duplicate, 024 delete, 025 open, 026 persistence, 027 z-order, 028 keyboard as a Mac
//       enhancement), §3.1, §6.2 (canvas, hover lift, drag shadow, spring on drop, cursors, Quick Look, drag-in);
//       VESSEL-004 (locked vessel), DECISIONS 10 Q5 (any window shows its own vessel); ARCHITECTURE.md §7.7, §8.4
//       (radius `quickCard` 10, no glass on quick cards).
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

/// The per-vessel Quick Cards dashboard (the vessel's first screen).
struct QuickCardsPanel: View {
    let vesselID: UUID

    init(vesselID: UUID) { self.vesselID = vesselID }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        if let vessel = env.store.vessel(id: vesselID) {
            if env.locks.isGated(vessel) {
                VesselLockedPlaceholder()
            } else {
                QuickCardsPanelContent(vessel: vessel)
                    .id(ObjectIdentifier(vessel))
            }
        } else {
            VesselMissingPlaceholder()
        }
    }
}

struct QuickCardsPanelContent: View {
    let vessel: Vessel

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var canvas = QuickCardLayout.canvasSize([])
    @State private var focusedCard: UUID?
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: AASpacing.s) {
            header
            canvasArea
        }
        .padding(AASpacing.m)
        .onAppear { sizeCanvas() }
        .onChange(of: VesselSessionState.shared.revision) { _, _ in sizeCanvas() }
        .onChange(of: vessel.quickCards.count) { _, _ in sizeCanvas() }
    }

    // MARK: Header (VESSEL-010)

    private var header: some View {
        HStack(spacing: 14) {
            Text(QuickCardLayout.headerTitle)
                .font(.aaMono(AAType.title, weight: .bold))
                .foregroundStyle(AAColor.accent)
                .fixedSize()
            Text(QuickCardLayout.headerHint)
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: AASpacing.s)
            Button {
                Task { await VesselFlows.addQuickCard(vesselID: vessel.id, env: env, dialogs: dialogs) }
            } label: {
                Label(QuickCardLayout.addButtonTitle.replacingOccurrences(of: "+ ", with: ""), systemImage: "plus")
            }
            .aaProminent()
            .help("Add a shortcut to a file, folder, or web link.")
            .accessibilityLabel(QuickCardLayout.addButtonTitle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AAColor.panel, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
    }

    // MARK: Canvas (VESSEL-011, 012, 027)

    private var canvasArea: some View {
        GeometryReader { geo in
            // The content is never smaller than the viewport, so the canvas origin stays top-left (no centring).
            let w = max(canvas.width, geo.size.width), h = max(canvas.height, geo.size.height)
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    QuickCardCanvasBackground()
                        .frame(width: w, height: h)
                        .contentShape(Rectangle())
                        .onTapGesture { focusedCard = nil }
                    ForEach(vessel.quickCards) { card in
                        QuickCardTile(card: card, vesselID: vessel.id, isFocused: focusedCard == card.id,
                                      onFocus: { focusedCard = card.id }, onLayoutChanged: sizeCanvas)
                    }
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .coordinateSpace(.named(QuickCardTile.canvasSpace))
            }
        }
        .background(AAColor.bg)
        .overlay {
            if vessel.quickCards.isEmpty {
                // VESSEL-012 text: its first line is the title, the second the next action.
                let lines = QuickCardLayout.emptyText.components(separatedBy: "\n")
                AAEmptyState(title: lines[0], symbol: "square.grid.2x2",
                             message: lines.dropFirst().joined(separator: "\n"))
                    .padding(AASpacing.xl)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
        // DATA-174: no drag-in while the write gate is closed (a plain file drop imports a copy into files/).
        .onDrop(of: VesselFlows.isWriteGated(env) ? [] : [.fileURL, .url], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func sizeCanvas() {
        let s = QuickCardLayout.canvasSize(cards: vessel.quickCards)
        if s.width != canvas.width || s.height != canvas.height { canvas = s }
    }

    // MARK: Drag-in (10 §6.2 optional enhancement: a Finder file / folder / URL opens the editor pre-filled)

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !VesselFlows.isWriteGated(env), let provider = providers.first else { return false }
        let linkInPlace = NSEvent.modifierFlags.contains(.option) || NSEvent.modifierFlags.contains(.shift)
        let vesselID = vessel.id
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await QuickCardDropFlow.dropped(fileURL: url, linkInPlace: linkInPlace, vesselID: vesselID,
                                                    env: env, dialogs: dialogs)
                }
            }
            return true
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                await QuickCardDropFlow.dropped(webURL: url, vesselID: vesselID, env: env, dialogs: dialogs)
            }
        }
        return true
    }
}

/// Drop handling: a plain file drop imports a copy, ⌥/⇧ links in place, a folder links the folder, a URL is a web link
/// (the file-bank convention, SHELL-679). The editor opens pre-filled; only OK adds the card.
@MainActor enum QuickCardDropFlow {
    static func dropped(fileURL url: URL, linkInPlace: Bool, vesselID: UUID, env: AppEnvironment,
                        dialogs: DialogPresenter) async {
        guard let vessel = env.store.vessel(id: vesselID) else { return }
        let card = QuickCardLayout.newCard(existingCount: vessel.quickCards.count)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        if isDir.boolValue && !isPackage {
            card.title = QuickCardLayout.titleForFolder(url)
            QuickCardLayout.setTarget(card, url.path, kind: .folder)
        } else if linkInPlace {
            card.title = QuickCardLayout.titleForFile(url)
            QuickCardLayout.setTarget(card, url.path, kind: .liveFile)
        } else {
            do {
                let stored = try AttachmentStore.importFile(env.dataStore, from: url)
                card.title = QuickCardLayout.titleForFile(url)
                QuickCardLayout.setTarget(card, stored, kind: .importedCopy)
            } catch {
                await dialogs.error("Import failed", error.localizedDescription)
                return
            }
        }
        await commit(card, vesselID: vesselID, env: env, dialogs: dialogs)
    }

    static func dropped(webURL url: URL, vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard let vessel = env.store.vessel(id: vesselID) else { return }
        let card = QuickCardLayout.newCard(existingCount: vessel.quickCards.count)
        QuickCardLayout.setTarget(card, url.absoluteString, kind: .webLink)
        await commit(card, vesselID: vesselID, env: env, dialogs: dialogs)
    }

    private static func commit(_ card: QuickCard, vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard await VesselFlows.presentEditor(card, env: env, dialogs: dialogs),
              let live = env.store.vessel(id: vesselID) else { return }
        live.quickCards.append(card)
        VesselFlows.saveNow(env)
        VesselSessionState.shared.bump()
    }
}

/// A faint dot grid behind the cards (content surface: no glass, §8.4).
struct QuickCardCanvasBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 28
            var y: CGFloat = step
            while y < size.height {
                var x: CGFloat = step
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)),
                             with: .color(AAColor.muted.opacity(0.22)))
                    x += step
                }
                y += step
            }
        }
        .background(AAColor.bg)
    }
}

// MARK: - One card (VESSEL-013…020)

struct QuickCardTile: View {
    static let canvasSpace = "vessel.quickcards.canvas"

    let card: QuickCard
    let vesselID: UUID
    let isFocused: Bool
    let onFocus: () -> Void
    let onLayoutChanged: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var hover = false
    @State private var dragging = false
    @State private var dragOrigin: CGPoint?
    @State private var consumedByDoubleClick = false
    @State private var resizeStart: CGSize?

    var body: some View {
        let bg = MaritimeIcons.parseColor(card.color)
        let fg = AAColor.color(MaritimeIcons.readableForeground(bg))
        let shape = RoundedRectangle(cornerRadius: QuickCardLayout.cardCornerRadius, style: .continuous)
        // Icon size is evaluated from the stored size, re-evaluated when the card re-renders after a resize.
        let iconSize = QuickCardLayout.iconSize(width: card.width, height: card.height)

        ZStack(alignment: .bottomTrailing) {
            shape.fill(AAColor.color(bg))
            VStack(spacing: 0) {
                Text(card.icon)
                    .font(.system(size: iconSize))
                    .foregroundStyle(fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !NetText.isBlank(card.title) {
                    Text(card.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(fg)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(6)
            .frame(width: card.width, height: card.height)
            grip(fg)
        }
        .frame(width: card.width, height: card.height)
        .overlay(shape.strokeBorder(isFocused ? Color.accentColor : AAColor.border, lineWidth: isFocused ? 2 : 1))
        .compositingGroup()
        .shadow(color: .black.opacity(dragging ? 0.32 : (hover ? 0.22 : 0.10)),
                radius: dragging ? 14 : (hover ? 8 : 3), y: dragging ? 8 : (hover ? 4 : 1.5))
        .scaleEffect(dragging ? 1.02 : 1, anchor: .center)
        .opacity(dragging ? 0.95 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: dragging)
        .animation(.easeOut(duration: 0.15), value: hover)
        .contentShape(shape)
        .onHover { hover = $0 }
        .pointerStyle(.link)
        .help(QuickCardLayout.tooltip(card))
        .gesture(moveGesture)
        .contextMenu { menu }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.return) { open(); return .handled }
        .onKeyPress(.space) { VesselFlows.quickLook(card, env: env); return .handled }
        .onKeyPress(.delete) { delete(); return .handled }
        .onKeyPress(.deleteForward) { delete(); return .handled }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(NetText.isBlank(card.title) ? (MaritimeIcons.name(of: card.icon) ?? card.icon) : card.title)
        .accessibilityHint(QuickCardLayout.kind(of: card).label)
        .accessibilityAction { open() }
        .offset(x: card.x, y: card.y)
    }

    // MARK: Grip (VESSEL-016, 018)

    private func grip(_ fg: Color) -> some View {
        QuickCardGripShape()
            .fill(fg.opacity(0.8))
            .frame(width: QuickCardLayout.gripSize, height: QuickCardLayout.gripSize)
            .opacity(0.55)
            .padding(.trailing, 2)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: .bottomTrailing))
            .highPriorityGesture(resizeGesture)
            .help("Drag to resize")
    }

    // MARK: Gestures (§3.1.5)

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                if dragOrigin == nil && !consumedByDoubleClick {
                    onFocus()
                    // VESSEL-019: a press with ClickCount == 2 opens the target instead of starting a move.
                    if let ev = NSApp.currentEvent, ev.type == .leftMouseDown || ev.type == .leftMouseDragged,
                       ev.clickCount == 2 {
                        consumedByDoubleClick = true
                        open()
                        return
                    }
                    dragOrigin = CGPoint(x: card.x, y: card.y)
                }
                guard let origin = dragOrigin, !consumedByDoubleClick else { return }
                if !dragging, abs(value.translation.width) + abs(value.translation.height) > 1 { dragging = true }
                let p = QuickCardLayout.dragged(originX: origin.x, originY: origin.y,
                                                dx: value.translation.width, dy: value.translation.height)
                if card.x != p.x { card.x = p.x }
                if card.y != p.y { card.y = p.y }
            }
            .onEnded { _ in
                defer { dragOrigin = nil; dragging = false; consumedByDoubleClick = false }
                guard dragOrigin != nil, !consumedByDoubleClick else { return }
                onLayoutChanged()
                VesselFlows.saveNow(env)                       // even with no movement (harmless, VESSEL-017)
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                if resizeStart == nil { resizeStart = CGSize(width: card.width, height: card.height); onFocus() }
                guard let s = resizeStart else { return }
                let r = QuickCardLayout.resized(width: s.width, height: s.height,
                                                dx: value.translation.width, dy: value.translation.height)
                if card.width != r.width { card.width = r.width }
                if card.height != r.height { card.height = r.height }
            }
            .onEnded { _ in
                resizeStart = nil
                onLayoutChanged()
                VesselFlows.saveNow(env)
            }
    }

    // MARK: Context menu (VESSEL-020)

    @ViewBuilder private var menu: some View {
        Button("Open") { open() }
        Button("Edit…") {
            Task { await VesselFlows.editQuickCard(card, vesselID: vesselID, env: env, dialogs: dialogs) }
        }
        Button("Duplicate") { VesselFlows.duplicateQuickCard(card, vesselID: vesselID, env: env) }
        if !card.isLink && !NetText.isBlank(card.target) {
            Button("Quick Look") { VesselFlows.quickLook(card, env: env) }
        }
        Divider()
        Button("Delete…", role: .destructive) { delete() }
    }

    private func open() { Task { await VesselFlows.openQuickCard(card, env: env, dialogs: dialogs) } }

    private func delete() { Task { await VesselFlows.deleteQuickCard(card, vesselID: vesselID, env: env, dialogs: dialogs) } }
}

/// `M16,0 L16,16 L0,16 Z` — the resize grip triangle.
struct QuickCardGripShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
