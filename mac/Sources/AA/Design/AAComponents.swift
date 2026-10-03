// Spec: 03 §6.6.5 (control styling, SHELL-155/156), Appendix B; ARCHITECTURE.md §8.4 (materials / Liquid Glass),
//       §8.6 (reusable components — wave agents use these, never fork them).
import AppKit
import SwiftUI
import AACore

// MARK: Buttons

/// WPF `AccentButton` → `.borderedProminent` + bold.
struct AAProminentButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) { configuration.label }
            .buttonStyle(.borderedProminent)
            .fontWeight(.semibold)
    }
}

/// WPF `ToolbarButton` → `.bordered`, small, min width 30.
struct AAToolbarButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.frame(minWidth: 30)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

extension View {
    func aaProminent() -> some View { buttonStyle(AAProminentButtonStyle()) }
    func aaToolbarButton() -> some View { buttonStyle(AAToolbarButtonStyle()) }

    /// Floating chrome only (shared-save capsule, shortcut strip, switcher, due header, planner/board controls).
    func aaGlass<S: Shape>(in shape: S) -> some View { glassEffect(.regular, in: shape) }

    /// Disabled app-drawn elements at 45 % opacity (03 §6.6.5).
    func aaDisabledOpacity(_ disabled: Bool) -> some View { opacity(disabled ? 0.45 : 1) }
}

// MARK: Surfaces

/// Side panes (filter / inspect panes) use the regular material (§8.4).
struct AAPaneBackground: View {
    var body: some View { Rectangle().fill(.regularMaterial) }
}

/// Panel background, control radius, 1-pt border.
struct AACard<Content: View>: View {
    var padding: CGFloat = AASpacing.m
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(AAColor.panel, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
                .strokeBorder(AAColor.border, lineWidth: 1))
    }
}

// MARK: Text

/// Bold title + secondary count (grouped lists).
struct AASectionHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
            Text(title).font(.aaMono(AAType.small, weight: .bold)).foregroundStyle(AAColor.fg)
            if let count {
                Text("\(count)").font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }
}

/// Strikethrough rows (SHELL-156).
struct AAStrikeText: View {
    let text: String
    let struck: Bool
    init(_ text: String, struck: Bool) { self.text = text; self.struck = struck }

    var body: some View {
        Text(text).strikethrough(struck).foregroundStyle(struck ? AAColor.muted : AAColor.fg)
    }
}

/// Muted wrapping help lines.
struct AAHelpText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Monospaced, selectable value text.
struct AAMonoText: View {
    let text: String
    var size: CGFloat = AAType.body
    init(_ text: String, size: CGFloat = AAType.body) { self.text = text; self.size = size }
    var body: some View { Text(text).font(.aaMono(size)).textSelection(.enabled) }
}

// MARK: Capsules and badges

/// Shared-save indicator, notifications bar, badges.
struct AAStatusCapsule: View {
    let text: String
    var symbol: String? = nil
    var color: Color = AAColor.muted

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).imageScale(.small).symbolRenderingMode(.hierarchical) }
            Text(text).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: AAType.caption, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
    }
}

/// A kind capsule with the per-kind pastel fill and black text (DECISIONS 07 Q-10).
struct AAKindBadge: View {
    let kind: ItemKind
    var compact = false

    var body: some View {
        Text(compact ? String(label.prefix(1)) : label)
            .font(.system(size: compact ? 9 : 10, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, 1.5)
            .background(AAColor.kind(kind), in: Capsule())
            .overlay(Capsule().strokeBorder(AAColor.border.opacity(0.6), lineWidth: 0.5))
            .accessibilityLabel(label)
    }

    var label: String {
        switch kind {
        case .task: return "Task"
        case .procedure: return "Procedure"
        case .vessel: return "Vessel"
        default: return "Equipment"
        }
    }
}

/// Tab-colour / quick-card swatch; nil colour = theme default with a small "default" label (SHELL-029).
struct AAColorSwatch: View {
    let color: Color?
    var size = CGSize(width: 46, height: 24)

    var body: some View {
        RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
            .fill(color ?? AAColor.panel)
            .overlay {
                if color == nil {
                    Text("default").font(.system(size: 10)).foregroundStyle(AAColor.muted)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
                .strokeBorder(AAColor.border, lineWidth: 1))
            .frame(width: size.width, height: size.height)
    }
}

// MARK: States and banners

/// `ContentUnavailableView` wrapper.
struct AAEmptyState: View {
    let title: String
    var symbol: String = "tray"
    var message: String? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message { Text(message) }
        }
    }
}

enum AABannerStyle {
    case danger, warning, info, success

    var color: Color {
        switch self {
        case .danger: return AAColor.Status.danger
        case .warning: return AAColor.Status.dueSoon
        case .info: return AAColor.tint
        case .success: return AAColor.Status.ok
        }
    }

    var symbol: String {
        switch self {
        case .danger: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }
}

struct AABannerAction: Identifiable {
    let id = UUID()
    let title: String
    var isProminent = false
    let action: () -> Void
}

/// Safe-mode / read-only / warning banners (animated in and out by the host with `.transition(.aaBanner)`).
struct AABanner: View {
    let style: AABannerStyle
    let text: String
    var actions: [AABannerAction] = []

    var body: some View {
        HStack(alignment: .center, spacing: AASpacing.s) {
            Image(systemName: style.symbol).foregroundStyle(style.color).imageScale(.medium)
            Text(text).font(.system(size: AAType.small, weight: .medium)).foregroundStyle(AAColor.fg)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AASpacing.s)
            ForEach(actions) { a in
                if a.isProminent {
                    Button(a.title, action: a.action).buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    Button(a.title, action: a.action).buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, AASpacing.s)
        .background(style.color.opacity(0.12))
        .overlay(alignment: .bottom) { Rectangle().fill(style.color.opacity(0.35)).frame(height: 1) }
        .overlay(alignment: .leading) { Rectangle().fill(style.color).frame(width: 3) }
    }
}

extension AnyTransition {
    static var aaBanner: AnyTransition { .move(edge: .top).combined(with: .opacity) }
}

/// Busy state replacing the WPF wait cursor; appears only after ~300 ms.
struct AAProgressOverlay: View {
    let text: String
    @State private var visible = false

    var body: some View {
        ZStack {
            if visible {
                Color.black.opacity(0.08).ignoresSafeArea()
                VStack(spacing: AASpacing.m) {
                    ProgressView().controlSize(.large)
                    Text(text).font(.system(size: AAType.body, weight: .medium))
                }
                .padding(AASpacing.xl)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AARadius.floatingPanel, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.18)) { visible = true }
        }
    }
}
