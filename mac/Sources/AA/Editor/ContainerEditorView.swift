// Spec: 05 CONT-001 (composite layout: editor over a 6 pt splitter over the 260 pt file bank; rounded bordered
//       panes; the split is not persisted), CONT-002 (hosts bind once and flush before they unbind), CONT-006 /
//       §6.7 (withheld notes are read-only with an inline banner), CONT-008 / §6.12 (one editor per container),
//       CONT-009 (orphaned / disabled editor), CONT-010 (paper in both appearances, chrome follows the theme);
//       ARCHITECTURE.md §2.4 (identity rebind on reload), §7.7 (embed contract — exact initialiser).
import AppKit
import SwiftUI
import AACore

struct ContainerEditorContext {
    var title: String
    var host: EditorHost
    var isEnabled = true
    var showsFileBank = true
}

enum EditorHost: Hashable {
    case mainPane(ItemKind), itemWindow(UUID), component(UUID), subtask(UUID), step(UUID), savedListItem(UUID)
}

/// The notes editor (rich text + file bank) of one container. Hosts embed it with `.id(ObjectIdentifier(container))`.
struct ContainerEditorView: View {
    let container: Container
    let context: ContainerEditorContext

    init(container: Container, context: ContainerEditorContext) { self.container = container; self.context = context }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var controller = EditorController()
    @State private var fileBankHeight: CGFloat = 260
    /// Height of the format bar plus any banner above the paper (measured; the bar may fold or wrap).
    @State private var chromeHeight: CGFloat = 33

    static let splitterHeight: CGFloat = 6
    /// The paper itself keeps at least this much height before the file bank gives way (V-05: the 260 pt bank default
    /// squeezed the paper to ~130 pt in a short item window). CONT-001's 260 is the default bank height only.
    static let minPaperHeight: CGFloat = 200
    static let minFileBankHeight: CGFloat = 110

    /// The notes pane's minimum: the measured chrome plus the paper minimum.
    private var minEditorHeight: CGFloat { chromeHeight + Self.minPaperHeight + 2 * EditorPane.paperInset }

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.height
            let bank = context.showsFileBank ? Self.clampedBank(fileBankHeight, total: total, minEditor: minEditorHeight) : 0
            VStack(spacing: 0) {
                EditorPane(controller: controller, title: context.title) { chromeHeight = $0 }
                    .frame(height: context.showsFileBank ? max(0, total - bank - Self.splitterHeight) : total)
                if context.showsFileBank {
                    EditorSplitHandle(height: $fileBankHeight, total: total, minEditor: minEditorHeight)
                    FileBankView(container: container, context: FileBankContext(host: context.host, isEnabled: context.isEnabled))
                        .frame(height: bank)
                }
            }
        }
        .onAppear { bind() }
        .onDisappear { controller.viewDisappeared() }
        .onChange(of: ObjectIdentifier(container)) { _, _ in bind() }
        .onChange(of: context.isEnabled) { _, enabled in controller.setHostEnabled(enabled) }
        .onChange(of: context.host) { _, _ in bind() }
    }

    private func bind() {
        controller.bind(container: container, host: context.host, isEnabled: context.isEnabled, env: env, dialogs: dialogs)
    }

    /// The bank's height: the user's (or the 260 default) clamped so the paper keeps `minPaperHeight`; the bank never
    /// drops below its own minimum (on a very short pane the paper gives way first).
    static func clampedBank(_ wanted: CGFloat, total: CGFloat, minEditor: CGFloat) -> CGFloat {
        let maxBank = max(minFileBankHeight, total - minEditor - splitterHeight)
        return min(max(wanted, minFileBankHeight), maxBank)
    }
}

/// The rich-text half: format bar, state banners, transient notices and the paper.
struct EditorPane: View {
    let controller: EditorController
    var title: String = ""
    /// Reports the height of the format bar + banners (the host keeps the paper's minimum below them).
    var onChromeHeight: ((CGFloat) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    /// The paper is presented as a page: inset from the pane, rounded, hairline border, a soft shadow in dark mode
    /// (V-DESIGN rule 9). Its colour stays #FCFCFC in both appearances (CONT-010).
    static let paperInset: CGFloat = AASpacing.s
    static let paperRadius: CGFloat = AARadius.boardCard

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                EditorFormatBar(controller: controller)
                banners
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onChromeHeight?($0) }
            EditorTextArea(controller: controller)
                .clipShape(RoundedRectangle(cornerRadius: Self.paperRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Self.paperRadius, style: .continuous)
                    .strokeBorder(AAColor.border, lineWidth: 1))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0), radius: 4, y: 1)
                .overlay(alignment: .bottom) { noticeView }
                .padding(Self.paperInset)
                .accessibilityLabel(title.isEmpty ? "Notes" : "Notes — \(title)")
        }
        .background(AAColor.panel)
        .clipShape(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
        .animation(.snappy, value: controller.withheld)
        .animation(.snappy, value: controller.parkedByOtherEditor)
        .animation(.snappy, value: controller.orphaned)
    }

    @ViewBuilder private var banners: some View {
        if controller.orphaned && controller.hostEnabled {      // a disabled host shows its own message
            AABanner(style: .danger, text: "This item is no longer in the loaded data — nothing typed here will be saved.")
                .transition(.aaBanner)
        } else if controller.parkedByOtherEditor {
            AABanner(style: .info,
                     text: "This note is open in another editor. Edit it there — this view refreshes when that editor closes.")
                .transition(.aaBanner)
        } else if let w = controller.withheld {
            AABanner(style: w == .legacyLocked ? .warning : .danger, text: w.bannerText,
                     actions: w == .legacyLocked
                        ? [AABannerAction(title: "Unlock…", isProminent: true) { Task { await controller.unlockAndReload() } }]
                        : [])
                .transition(.aaBanner)
        }
    }

    /// Notice text with the lock emoji drawn as SF Symbols.
    static func noticeText(_ raw: String) -> Text {
        let body = raw.hasPrefix("🔒 ") ? String(raw.dropFirst(2)) : raw
        let parts = body.components(separatedBy: "🔓")
        var t = Text(verbatim: parts[0])
        for p in parts.dropFirst() {
            t = Text("\(t)\(Image(systemName: "lock.open"))\(Text(verbatim: p))")
        }
        return t
    }

    @ViewBuilder private var noticeView: some View {
        if let n = controller.notice {
            HStack(spacing: 8) {
                Image(systemName: n.style == .success ? "checkmark.circle.fill"
                      : n.style == .warning ? "lock.fill" : "info.circle.fill")
                    .foregroundStyle(n.style == .success ? AAColor.Status.ok
                                     : n.style == .warning ? AAColor.Status.dueSoon : AAColor.tint)
                // The lock hint's emoji are icons (ARCH §8.5): the leading 🔒 is the symbol on the left, the 🔓 in
                // the sentence is the format bar's `lock.open` symbol inline.
                Self.noticeText(n.text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color(nsColor: EditorFormatting.editorInk))
                    .fixedSize(horizontal: false, vertical: true)
                Button { controller.dismissNotice() } label: {
                    Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .padding(.horizontal, AASpacing.m)
            .padding(.vertical, AASpacing.s)
            .background(AAColor.panel, in: Capsule())          // light (the scheme is pinned below)
            .overlay(Capsule().strokeBorder(AAColor.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .padding(.bottom, AASpacing.m)
            .padding(.horizontal, AASpacing.l)
            .environment(\.colorScheme, .light)                 // floats on the light paper
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(n.id)
        }
    }
}

/// Hosts the controller's AppKit scroll view (TextKit 1 text view inside).
struct EditorTextArea: NSViewRepresentable {
    let controller: EditorController

    func makeNSView(context: Context) -> EditorScrollView { controller.scrollView }

    func updateNSView(_ nsView: EditorScrollView, context: Context) {}
}

/// CONT-001: the 6 pt splitter between the notes and the file bank (size not persisted).
struct EditorSplitHandle: View {
    @Binding var height: CGFloat
    let total: CGFloat
    var minEditor: CGFloat = ContainerEditorView.minPaperHeight
    @State private var start: CGFloat?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color.clear)
            Capsule()
                .fill(hovering || start != nil ? AAColor.muted : AAColor.border)
                .frame(width: 36, height: 3)
        }
        .frame(height: ContainerEditorView.splitterHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { g in
                    if start == nil { start = height }
                    let proposed = (start ?? height) - g.translation.height
                    height = ContainerEditorView.clampedBank(proposed, total: total, minEditor: minEditor)
                }
                .onEnded { _ in start = nil }
        )
        .accessibilityElement()
        .accessibilityLabel("Resize the file bank")
        .accessibilityAddTraits(.isButton)
    }
}
