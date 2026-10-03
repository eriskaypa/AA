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

    static let splitterHeight: CGFloat = 6
    static let minEditorHeight: CGFloat = 150
    static let minFileBankHeight: CGFloat = 110

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.height
            let bank = context.showsFileBank ? clampedBank(total) : 0
            VStack(spacing: 0) {
                EditorPane(controller: controller, title: context.title)
                    .frame(height: context.showsFileBank ? max(Self.minEditorHeight, total - bank - Self.splitterHeight) : total)
                if context.showsFileBank {
                    EditorSplitHandle(height: $fileBankHeight, total: total)
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

    private func clampedBank(_ total: CGFloat) -> CGFloat {
        let maxBank = max(Self.minFileBankHeight, total - Self.minEditorHeight - Self.splitterHeight)
        return min(max(fileBankHeight, Self.minFileBankHeight), maxBank)
    }
}

/// The rich-text half: format bar, state banners, transient notices and the paper.
struct EditorPane: View {
    let controller: EditorController
    var title: String = ""

    var body: some View {
        VStack(spacing: 0) {
            EditorFormatBar(controller: controller)
            banners
            EditorTextArea(controller: controller)
                .overlay(alignment: .bottom) { noticeView }
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

    @ViewBuilder private var noticeView: some View {
        if let n = controller.notice {
            HStack(spacing: 8) {
                Image(systemName: n.style == .success ? "checkmark.circle.fill"
                      : n.style == .warning ? "lock.fill" : "info.circle.fill")
                    .foregroundStyle(n.style == .success ? AAColor.Status.ok
                                     : n.style == .warning ? AAColor.Status.dueSoon : AAColor.tint)
                // The lock hint's leading emoji is replaced by the symbol on the left.
                Text(verbatim: n.text.hasPrefix("🔒 ") ? String(n.text.dropFirst(2)) : n.text)
                    .font(.system(size: AAType.small, weight: .medium))
                    .foregroundStyle(Color(nsColor: EditorFormatting.editorInk))
                    .fixedSize(horizontal: false, vertical: true)
                Button { controller.dismissNotice() } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.96), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .padding(.bottom, 12)
            .padding(.horizontal, 16)
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
                    let maxBank = total - ContainerEditorView.minEditorHeight - ContainerEditorView.splitterHeight
                    height = min(max(proposed, ContainerEditorView.minFileBankHeight), max(ContainerEditorView.minFileBankHeight, maxBank))
                }
                .onEnded { _ in start = nil }
        )
        .accessibilityElement()
        .accessibilityLabel("Resize the file bank")
        .accessibilityAddTraits(.isButton)
    }
}
