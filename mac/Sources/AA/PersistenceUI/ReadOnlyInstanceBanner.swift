// Spec: 01 DATA-174 (read-only banner under the toolbar: lock.fill, "Switch to Other AA", "Edit Here"), DATA-175
//       ("The other copy of AA has closed…" with "Edit Here" / "Stay Read-Only"), DATA-180 ("Stop Editing Here" banner
//       with "Resume Editing"), DATA-181 / ARCH §6.6 ("Show Conflict Copies…" / "Conflict Copies…" items), DATA-184
//       (shared-with-Windows banner, "Show Me How" / "Don't Show Again"), MP.6.5 (banners use the standard material and
//       animate in and out); ARCHITECTURE.md §7.7, §8.
import AppKit
import SwiftUI
import AACore

/// The read-only instance banner (F3 shows it while `env.isReadOnlyInstance`).
struct ReadOnlyInstanceBanner: View {
    @Environment(AppEnvironment.self) private var env
    private var bridge: PersistUIBridge { .shared }

    var body: some View {
        PersistReadOnlyBannerContent(
            phase: bridge.readOnlySession?.phase ?? .readOnly,
            canSwitch: bridge.otherAppPid != nil,
            onSwitch: { bridge.switchToOther() },
            onEditHere: { Task { await bridge.editHere() } },
            onStay: { bridge.stayReadOnly() },
            onConflictCopies: { showConflictCopies() })
            .onAppear {
                bridge.attach(env)
                bridge.startReadOnly()
            }
            .animation(.snappy, value: bridge.readOnlySession?.phase)
    }

    private func showConflictCopies() {
        Task { await env.mainDialogs.presentSheet(.closeType) { _ in ConflictCopiesSheet() } }
    }
}

/// The DATA-180 "stopped editing" banner and the DATA-184 shared-with-Windows warning (F3 always includes this view in
/// the banner area; it also attaches W-PERSIST's machinery to the environment).
struct DataFileConflictBanner: View {
    @Environment(AppEnvironment.self) private var env
    private var bridge: PersistUIBridge { .shared }

    var body: some View {
        let stopped = env.dataFileGuard?.state.mode == .stoppedEditing
        VStack(spacing: 0) {
            Color.clear.frame(height: 0)
            if stopped {
                PersistStoppedBannerContent(
                    onResume: { withAnimation(.snappy) { env.dataFileGuard?.resumeEditing() } },
                    onConflictCopies: { Task { await env.mainDialogs.presentSheet(.closeType) { _ in ConflictCopiesSheet() } } })
                    .transition(.aaBanner)
            }
            if bridge.showsWindowsWarning {
                PersistWindowsBannerContent(onShowMe: { bridge.showSharedSaveHelp() },
                                            onDontShow: { bridge.dismissWindowsWarning() })
                    .transition(.aaBanner)
            }
        }
        .animation(.snappy, value: stopped)
        .animation(.snappy, value: bridge.showsWindowsWarning)
        .onAppear { bridge.attach(env) }
    }
}

// MARK: Banner contents (stateless — also rendered by the debug snapshots)

struct PersistReadOnlyBannerContent: View {
    let phase: PersistReadOnlySession.Phase
    let canSwitch: Bool
    let onSwitch: () -> Void
    let onEditHere: () -> Void
    let onStay: () -> Void
    let onConflictCopies: () -> Void

    var body: some View {
        PersistBannerFrame(symbol: phase == .canEdit ? "lock.open.fill" : "lock.fill",
                           tint: phase == .canEdit ? AAColor.Status.ok : AAColor.Status.warning,
                           text: phase == .canEdit ? PersistReadOnlyText.canEditBanner : PersistReadOnlyText.banner) {
            if phase == .canEdit {
                Button(PersistReadOnlyText.stayReadOnly, action: onStay).buttonStyle(.bordered)
                Button(PersistReadOnlyText.editHere, action: onEditHere).buttonStyle(.borderedProminent)
            } else {
                Menu {
                    Button("Show Conflict Copies…", action: onConflictCopies)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                if canSwitch {
                    Button(PersistReadOnlyText.switchToOther, action: onSwitch).buttonStyle(.bordered)
                }
            }
        }
    }
}

struct PersistStoppedBannerContent: View {
    let onResume: () -> Void
    let onConflictCopies: () -> Void

    var body: some View {
        PersistBannerFrame(symbol: "pause.circle.fill", tint: AAColor.Status.warning, text: PersistConflictText.stoppedBanner) {
            Button(PersistConflictText.conflictCopies, action: onConflictCopies).buttonStyle(.bordered)
            Button(PersistConflictText.resumeEditing, action: onResume).buttonStyle(.borderedProminent)
        }
    }
}

struct PersistWindowsBannerContent: View {
    let onShowMe: () -> Void
    let onDontShow: () -> Void

    var body: some View {
        PersistBannerFrame(symbol: "exclamationmark.triangle.fill", tint: AAColor.Status.dueSoon,
                           text: PersistWindowsEvidence.message) {
            Button(PersistWindowsEvidence.dontShowAgain, action: onDontShow).buttonStyle(.bordered)
            Button(PersistWindowsEvidence.showMeHow, action: onShowMe).buttonStyle(.borderedProminent)
        }
    }
}

/// The shared banner look: material background, tinted edge, symbol, wrapping text, small trailing buttons.
struct PersistBannerFrame<Actions: View>: View {
    let symbol: String
    let tint: Color
    let text: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: AASpacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 20)
            Text(text)
                .font(.system(size: AAType.small, weight: .medium))
                .foregroundStyle(AAColor.fg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: AASpacing.s) { actions() }
                .controlSize(.small)
                .fixedSize()
        }
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, AASpacing.s)
        .background(.bar)
        .background(tint.opacity(0.10))
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
        .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text)
    }
}
