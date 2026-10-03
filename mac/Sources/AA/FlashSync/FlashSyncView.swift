// Spec: 13 §2.1 (FLASH-003 header/intro, FLASH-004/005 via the single-instance window, FLASH-006 reload),
//       §2.2 (Send tab, FLASH-010…024), §2.3 (Receive tab, FLASH-030…048), §6.6 (native layout: segmented Send | Receive
//       in the toolbar with SF Symbols, the white plate as the hero, Speed slider with "{n} / sec", prominent confirm
//       button, camera picker, black preview plate, progress + status + bold "Incoming:" line; header in the accent
//       token, muted text in the secondary colour; the QR plate stays white and the preview black in both appearances),
//       03 SHELL-676 (⌘. and ⎋ stop flashing or the camera; ↩ = focused primary button only), T-KB-46/47,
//       FLASH-131/134/135 (Mac additions); ARCH §7.7 (`FlashSyncView()` is the `flash-sync` scene's content).
import AppKit
import AVFoundation
import SwiftUI
import AACore

struct FlashSyncView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var model = FlashSyncModel()

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            FlashHeader()
            Picker("", selection: $model.tab) {
                ForEach(FlashTab.allCases) { t in Label(t.title, systemImage: t.symbol).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity)
            .padding(.bottom, AASpacing.m)
            .help("Send flashes codes for the iPhone to film; Receive films the iPhone's codes.")
            Divider()
            Group {
                switch model.tab {
                case .send: FlashSendPane(model: model)
                case .receive: FlashReceivePane(model: model)
                }
            }
            .padding(AASpacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 680, minHeight: 620)
        .background(AAColor.bg)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FlashMoreMenu(model: model)
            }
        }
        .background { FlashKeyCommands(model: model) }
        .sheet(item: $model.review) { r in
            FlashReviewSheet(change: r.change) { apply in model.finishReview(apply) }
        }
        .onAppear { model.attach(env: env, dialogs: dialogs) }
        .onDisappear { model.close() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { n in
            if let w = n.object as? NSWindow, w === SceneOpener.shared.window(for: .flashSync) { model.windowBecameKey() }
        }
    }
}

// MARK: Header (FLASH-003)

private struct FlashHeader: View {
    var body: some View {
        HStack(alignment: .top, spacing: AASpacing.m) {
            Image(systemName: "qrcode")
                .font(.system(size: AAType.brand, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(AAColor.tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(FlashSyncTexts.header)
                    .font(.aaMono(AAType.title, weight: .bold))
                    .foregroundStyle(AAColor.accent)
                AAHelpText(FlashSyncTexts.intro)
            }
        }
        .padding(.horizontal, AASpacing.l)
        .padding(.vertical, AASpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Overflow menu (FLASH-131, FLASH-134)

private struct FlashMoreMenu: View {
    let model: FlashSyncModel

    var body: some View {
        Menu {
            if NSScreen.screens.count > 1 {
                Menu(FlashSyncTexts.fullScreen) {
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in
                        Button(screen.localizedName) { model.enterFullScreen(on: screen) }
                            .help(FlashSyncTexts.fullScreenHelp)
                    }
                }
                .help(FlashSyncTexts.fullScreenHelp)
            } else {
                Button(FlashSyncTexts.fullScreen) { model.enterFullScreen(on: nil) }
                    .help(FlashSyncTexts.fullScreenHelp)
            }
            Divider()
            Button(FlashSyncTexts.resetPairing) { Task { await model.resetPairing() } }
                .disabled(!model.send.canResetPairing || !model.hasBaseline)
                .help(FlashSyncTexts.resetPairingHelp)
        } label: {
            Label(FlashSyncTexts.more, systemImage: "ellipsis.circle")
                .symbolRenderingMode(.hierarchical)
        }
        .menuIndicator(.hidden)
        .help(FlashSyncTexts.moreHelp)
        .accessibilityLabel(FlashSyncTexts.moreHelp)
    }
}

// MARK: Keys (SHELL-676 / T-KB-46 / T-KB-47)

private struct FlashKeyCommands: View {
    let model: FlashSyncModel

    var body: some View {
        ZStack {
            Button("Stop") { model.stopCommand() }.keyboardShortcut(".", modifiers: .command)
            Button("Stop") { model.stopCommand() }.keyboardShortcut(.cancelAction)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Send tab (FLASH-010…024)

private struct FlashSendPane: View {
    @Bindable var model: FlashSyncModel

    private var flow: FlashSendFlow { model.send }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            summary
            controls
            plate
            footer
        }
    }

    private var summarySymbol: (String, Color) {
        switch flow.prepared {
        case .nothingToSend: return ("checkmark.seal.fill", AAColor.Status.ok)
        case .snapshot: return ("externaldrive.fill", AAColor.tint)
        case .changeSet: return ("arrow.up.doc.fill", AAColor.tint)
        case .unavailable: return ("exclamationmark.triangle.fill", AAColor.Status.danger)
        case .none: return ("hourglass", AAColor.muted)
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: AASpacing.s) {
            Image(systemName: summarySymbol.0)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(summarySymbol.1)
                .font(.aaMono(AAType.title))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                if model.preparing && flow.summaryText.isEmpty {
                    HStack(spacing: AASpacing.s) {
                        ProgressView().controlSize(.small)
                        Text("Preparing…").font(.aaMono(AAType.body)).foregroundStyle(AAColor.muted)
                    }
                } else {
                    Text(flow.summaryText)
                        .font(.aaMono(AAType.body, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AAColor.fg)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                AAHelpText(FlashSyncTexts.sendHint)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: flow.summaryText)
    }

    private var controls: some View {
        HStack(spacing: AASpacing.s) {
            Button { model.startFlashing() } label: {
                Label(FlashSyncTexts.startFlashing, systemImage: "play.fill")
            }
            .aaProminent()
            .disabled(!flow.startEnabled)
            Button { model.stopFlashing() } label: {
                Label(FlashSyncTexts.stop, systemImage: "stop.fill")
            }
            .disabled(!flow.stopEnabled)
            .help("Stop flashing (⌘.)")
            Spacer(minLength: AASpacing.l)
            Text(FlashSyncTexts.speed).font(.aaMono(AAType.body)).foregroundStyle(AAColor.muted)
            Slider(value: Binding(get: { Double(model.fps) }, set: { model.fps = Int($0.rounded()) }),
                   in: Double(FlashSendFlow.minFps) ... Double(FlashSendFlow.maxFps), step: 1)
                .frame(width: 140)
                .labelsHidden()
            Text(FlashSyncTexts.fpsText(model.fps))
                .font(.aaMono(AAType.body).monospacedDigit())
                .foregroundStyle(AAColor.fg)
                .fixedSize()
                .frame(minWidth: 52, alignment: .leading)
        }
        .controlSize(.regular)
    }

    private var plate: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).fill(Color.white)
            FlashQRPlate(frame: model.frame)
                .padding(18)
            if model.frame == nil {
                VStack(spacing: AASpacing.s) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 44, weight: .ultraLight))
                    Text(flow.startEnabled ? "Press Start flashing, then point the iPhone at this code." : " ")
                        .font(.aaMono(AAType.caption))
                }
                .foregroundStyle(AAColor.Status.neutral)                     // the plate is white in both appearances
                .allowsHitTesting(false)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
            .strokeBorder(AAColor.border, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if flow.isFlashing {
                AAStatusCapsule(text: "Flashing", symbol: "dot.radiowaves.left.and.right", color: AAColor.Status.ok)
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: flow.isFlashing)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            Text(flow.progressText.isEmpty ? " " : flow.progressText)
                .font(.aaMono(AAType.caption).monospacedDigit())
                .foregroundStyle(AAColor.muted)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(alignment: .center, spacing: AASpacing.m) {
                Button { Task { await model.confirmReceived() } } label: {
                    Label(FlashSyncTexts.confirmButton, systemImage: "checkmark.seal")
                        .padding(.horizontal, 6)
                }
                .controlSize(.large)
                .disabled(!flow.confirmEnabled)
                .help(FlashSyncTexts.confirmTooltip)
                Label(FlashSyncTexts.brightnessHint, systemImage: "sun.max")
                    .font(.aaMono(AAType.caption))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AAColor.muted)
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
            AAHelpText(FlashSyncTexts.confirmCaution)
        }
    }
}

// MARK: Receive tab (FLASH-030…048)

private struct FlashReceivePane: View {
    @Bindable var model: FlashSyncModel
    @Environment(AppEnvironment.self) private var env
    @State private var pulse = false

    private var flow: FlashReceiveFlow { model.receive }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            controls
            VStack(alignment: .leading, spacing: AASpacing.xs) {
                AAHelpText(FlashSyncTexts.receiveHint)
                AAHelpText(FlashSyncTexts.macCameraHint)
            }
            preview
            progress
        }
    }

    private var controls: some View {
        HStack(spacing: AASpacing.s) {
            Text(FlashSyncTexts.camera).font(.aaMono(AAType.body)).foregroundStyle(AAColor.muted)
            Picker("", selection: Binding(get: { flow.selectedCamera ?? -1 }, set: { model.selectCamera($0) })) {
                if model.cameras.isEmpty { Text("None").tag(-1) }
                ForEach(Array(model.cameras.enumerated()), id: \.offset) { i, c in Text(c.name).tag(i) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(!flow.pickerEnabled)
            Button { Task { await model.startCamera() } } label: {
                Label(FlashSyncTexts.startCamera, systemImage: "video.fill")
            }
            .aaProminent()
            .disabled(!flow.startEnabled)
            Button { model.stopCamera() } label: { Label(FlashSyncTexts.stop, systemImage: "stop.fill") }
                .disabled(!flow.stopEnabled)
                .help("Stop the camera (⌘.)")
            Button { model.rescan() } label: { Label(FlashSyncTexts.rescan, systemImage: "arrow.clockwise") }
                .disabled(!flow.rescanEnabled)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).fill(Color.black)
            if let r = model.receiver, flow.isCapturing || flow.isApplying {
                FlashCameraPreview(session: r.session, mirrored: model.previewMirrored)
                    .clipShape(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
            } else {
                placeholder
            }
        }
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
            .strokeBorder(AAColor.Status.ok.opacity(pulse ? 0.9 : 0), lineWidth: 3))
        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
        .onChange(of: model.solvedPulse) {
            pulse = true
            withAnimation(.easeOut(duration: 0.45)) { pulse = false }
        }
    }

    private var placeholder: some View {
        VStack(spacing: AASpacing.m) {
            Image(systemName: placeholderSymbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AAColor.Status.neutral)                     // the preview is black in both appearances
            if flow.access == .denied {
                Button(FlashSyncTexts.openSystemSettings) { model.openCameraSettings() }
                    .buttonStyle(.bordered)
                    .environment(\.colorScheme, .dark)
            } else if flow.access != .unbundled && !model.cameras.isEmpty {
                Text("Press Start camera, then hold the iPhone in view.")
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.Status.neutral)
            }
        }
        .padding()
    }

    private var placeholderSymbol: String {
        switch flow.access {
        case .denied: return "video.slash"
        case .unbundled: return "shippingbox"
        default: return model.cameras.isEmpty ? "video.slash" : "camera.viewfinder"
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(flow.solved), total: Double(max(flow.total, 1)))
                .progressViewStyle(.linear)
                .tint(flow.total > 0 && flow.solved == flow.total ? AAColor.Status.ok : AAColor.tint)
                .frame(height: 16)
                .animation(.easeOut(duration: 0.2), value: flow.solved)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if flow.statusIsProblem {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.aaMono(AAType.caption))
                        .foregroundStyle(AAColor.Status.dueSoon)
                }
                Text(flow.statusText.isEmpty ? " " : flow.statusText)
                    .font(.aaMono(AAType.caption).monospacedDigit())
                    .foregroundStyle(flow.statusIsProblem ? AAColor.fg : AAColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(flow.labelText.isEmpty ? " " : flow.labelText)
                .font(.aaMono(AAType.body, weight: .bold))                   // §6.6: the bold "Incoming:" line
                .foregroundStyle(AAColor.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
