// Spec: 13 §2.1–2.3 (FLASH-003…048), §6.4–6.6 (Mac window: single instance, flush + blocking save before every prepare
//       and apply, never re-prepare while flashing, refresh when the window becomes key and is idle, apply → reload →
//       theme → status), FLASH-130 (live theme after apply — loadDataAndInitUI re-applies the appearance), FLASH-131
//       (Reset pairing), FLASH-134 (full screen), FLASH-135 (rich review sheet), DECISIONS 13 (Q-4, Q-5, Q-10, Q-18
//       speed per device), 03 SHELL-199 (unbundled: no camera), SHELL-676 (⌘. / ⎋ stop).
import AppKit
import AVFoundation
import Observation
import SwiftUI
import AACore

extension MacPreferences.Key {
    /// DECISIONS 13 Q-18 — the Speed slider, per device (never settings.json).
    static let flashSpeed = MacPreferences.Key("aa.flash.speed")
    /// The last tab shown (per device).
    static let flashTab = MacPreferences.Key("aa.flash.tab")
}

enum FlashTab: String, CaseIterable, Identifiable {
    case send, receive
    var id: String { rawValue }
    var title: String { self == .send ? FlashSyncTexts.sendTab : FlashSyncTexts.receiveTab }
    var symbol: String { self == .send ? "qrcode" : "camera.viewfinder" }
}

/// A review waiting for the user's decision.
struct FlashPendingReview: Identifiable {
    let id = UUID()
    let change: FlashIncomingChange
}

@MainActor @Observable
final class FlashSyncModel {
    // Tabs
    var tab: FlashTab = .send {
        didSet { if persistsTab { MacPreferences.shared.set(tab.rawValue, .flashTab) } }
    }
    /// False while a DEBUG snapshot override chose the tab (never write the user's preferences from a snapshot run).
    @ObservationIgnored private var persistsTab = true

    // Send
    private(set) var send = FlashSendFlow()
    private(set) var frame: FlashRenderedFrame?
    private(set) var preparing = false
    @ObservationIgnored private let sender = FlashFrameSender()
    @ObservationIgnored private var pending: FlashOutgoing?
    @ObservationIgnored private var prepareToken = 0

    // Receive
    private(set) var receive = FlashReceiveFlow()
    private(set) var cameras: [FlashCameraDevice] = []
    private(set) var solvedPulse = 0
    var review: FlashPendingReview?
    @ObservationIgnored private(set) var receiver: FlashCameraReceiver?
    @ObservationIgnored private var deviceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var reviewContinuation: CheckedContinuation<Bool, Never>?

    // Full screen
    @ObservationIgnored private var fullScreen: FlashFullScreenPresenter?
    private(set) var isFullScreen = false

    @ObservationIgnored private weak var env: AppEnvironment?
    @ObservationIgnored private var dialogs: DialogPresenter = .unbound
    @ObservationIgnored private var store: FlashSyncStore?
    @ObservationIgnored private(set) var started = false

    init() {
        let savedFps = MacPreferences.shared.codable(.flashSpeed, as: Int.self) ?? FlashSendFlow.defaultFps
        send = FlashSendFlow(fps: savedFps)
        if let t = MacPreferences.shared.string(.flashTab).flatMap(FlashTab.init(rawValue:)) { tab = t }
        #if DEBUG
        if let t = ProcessInfo.processInfo.environment["AA_FLASH_DEBUG_TAB"].flatMap(FlashTab.init(rawValue:)) {
            persistsTab = false
            tab = t
        }
        #endif
        sender.fps = send.fps
        sender.onFrame = { [weak self] f in self?.show(f) }
        sender.onFailure = { [weak self] message in self?.drawFailed(message) }
    }

    // MARK: Lifecycle

    /// FLASH-010: on first appearance prepare the send payload and list the cameras.
    func attach(env: AppEnvironment, dialogs: DialogPresenter) {
        self.dialogs = dialogs
        guard !started else { return }
        started = true
        self.env = env
        store = FlashSyncStore(dataStore: env.dataStore)
        prepareSend()
        setUpCamera()
        #if DEBUG
        if ProcessInfo.processInfo.environment["AA_FLASH_DEBUG_AUTOSTART"] != nil {
            Task { @MainActor in
                for _ in 0 ..< 100 where !send.startEnabled { try? await Task.sleep(for: .milliseconds(50)) }
                startFlashing()
            }
        }
        #endif
    }

    /// FLASH-005: stop flashing (release keep-awake), stop the camera, close full screen. Nothing is written.
    func close() {
        sender.stop()
        send.stop()
        receiver?.stop()
        _ = receive.cameraStopped()
        exitFullScreen()
        deviceObservers.forEach(NotificationCenter.default.removeObserver)
        deviceObservers = []
        reviewContinuation?.resume(returning: false)
        reviewContinuation = nil
        started = false
    }

    /// §6.6 point 3: when the window becomes key and is idle, refresh the summary.
    func windowBecameKey() {
        guard started, send.canRePrepare, !preparing, review == nil, !receive.isApplying else { return }
        prepareSend()
    }

    // MARK: Send (FLASH-010…024)

    /// Flushes every editor, saves synchronously, then builds the payload off the main actor.
    func prepareSend() {
        guard let env, let store, send.canRePrepare else { return }
        prepareToken += 1
        let token = prepareToken
        if env.isSafeMode {
            dropStream()
            send.didFail(FlashSyncError.databaseUnreadableMessage)
            return
        }
        env.flushAllEditors()                                              // FLASH-002 / §6.6 point 1
        if env.store.isDirty { try? env.saveQuietly() }
        let inputs: FlashSendInputs
        do { inputs = try store.captureSendInputs() } catch {
            dropStream()
            send.didFail(error.localizedDescription)
            return
        }
        preparing = true
        let identity = env.settings.appIdentity
        let now = env.clock.now()
        Task.detached(priority: .userInitiated) {
            let result: Result<(FlashOutgoing, FlashEncoder)?, Error>
            do {
                if let out = try FlashSyncStore.buildOutgoing(inputs, from: identity, now: now) {
                    let enc = try FlashEncoder(payload: out.payload, kind: out.kind, label: out.label,
                                               session: FlashEncoder.newSession())
                    result = .success((out, enc))
                } else {
                    result = .success(nil)
                }
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in self?.prepared(result, token: token) }
        }
    }

    private func prepared(_ result: Result<(FlashOutgoing, FlashEncoder)?, Error>, token: Int) {
        guard token == prepareToken else { return }
        preparing = false
        guard send.canRePrepare else { return }
        switch result {
        case .success(nil):
            dropStream()                                                   // Q-4
            send.didFindNothingToSend()
        case .success(let (out, enc)?):
            pending = out
            frame = nil
            sender.setEncoder(enc)
            send.didPrepare(kind: out.kind, label: out.label, chunks: enc.chunkCount)
        case .failure(let e):
            dropStream()
            send.didFail(e.localizedDescription)
        }
    }

    private func dropStream() {
        sender.setEncoder(nil)
        pending = nil
        frame = nil
    }

    /// FLASH-013.
    func startFlashing() {
        guard send.start() else { return }
        sender.start(on: SceneOpener.shared.window(for: .flashSync)?.screen)
    }

    /// FLASH-014.
    func stopFlashing() {
        sender.stop()
        send.stop()
    }

    var fps: Int {
        get { send.fps }
        set {
            send.fps = newValue
            sender.fps = send.fps                                          // FLASH-015: immediately, even while flashing
            MacPreferences.shared.setCodable(send.fps, .flashSpeed)
        }
    }

    private func show(_ f: FlashRenderedFrame) {
        frame = f
        send.frameShown()
        fullScreen?.show(f)
    }

    private func drawFailed(_ message: String) {
        send.drawFailed()
        Task { await dialogs.warning(FlashSyncTexts.dialogTitle, FlashSyncTexts.drawFailure(message)) }
    }

    /// FLASH-019/020.
    func confirmReceived() async {
        guard let out = pending, let store else { return }
        let spec = AlertSpec(title: FlashSyncTexts.confirmTitle, message: FlashSyncTexts.confirmMessage, style: .informational,
                             buttons: [AlertButton(title: FlashSyncTexts.confirmNo, role: .cancel),
                                       AlertButton(title: FlashSyncTexts.confirmYes, role: .normal)])
        guard await dialogs.alert(spec) == 1 else { return }
        store.writeBaseline(data: out.pendingData, settings: out.pendingSettings)
        sender.stop()
        send.didConfirm()
        dropStream()
        exitFullScreen()
        prepareSend()
        await dialogs.info(FlashSyncTexts.dialogTitle, FlashSyncTexts.recorded)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: FlashSyncTexts.recorded])
    }

    /// FLASH-131.
    func resetPairing() async {
        guard let store, send.canResetPairing else { return }
        let ok = await dialogs.confirm(FlashSyncTexts.resetPairingTitle, FlashSyncTexts.resetPairingMessage,
                                       confirm: FlashSyncTexts.resetPairingConfirm, cancel: "Cancel",
                                       destructive: true, defaultIsCancel: true)
        guard ok else { return }
        store.clearBaseline()
        prepareSend()
        env?.status.post(FlashSyncTexts.resetPairingDone)
    }

    var hasBaseline: Bool { store?.hasBaseline ?? false }

    // MARK: Full screen (FLASH-134)

    func enterFullScreen(on screen: NSScreen?) {
        guard let screen = screen ?? SceneOpener.shared.window(for: .flashSync)?.screen ?? NSScreen.main else { return }
        let p = fullScreen ?? FlashFullScreenPresenter { [weak self] in self?.fullScreenClosed() }
        fullScreen = p
        p.present(on: screen, frame: frame)
        isFullScreen = true
    }

    func exitFullScreen() {
        fullScreen?.dismiss()
        fullScreen = nil
        isFullScreen = false
    }

    private func fullScreenClosed() {
        fullScreen = nil
        isFullScreen = false
    }

    // MARK: Receive (FLASH-030…048)

    private func setUpCamera() {
        guard let env else { return }
        guard env.isBundled else {                                         // SHELL-199
            receive.setAccess(.unbundled)
            return
        }
        switch FlashCameraReceiver.authorization {
        case .authorized: receive.setAccess(.granted)
        case .denied, .restricted: receive.setAccess(.denied)
        default: receive.setAccess(.unknown)
        }
        let r = FlashCameraReceiver()
        r.onProgress = { [weak self] p in self?.progressed(p) }
        r.onError = { [weak self] message in
            self?.receive.cameraFailed(message)
        }
        receiver = r
        rescan()
        let nc = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            deviceObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.receive.isCapturing else { return }
                    self.rescan()
                }
            })
        }
    }

    /// FLASH-030/032 — real device names; preselect the system default camera.
    func rescan() {
        guard receive.access != .unbundled else { return }
        let (devices, preferred) = FlashCameraReceiver.discover()
        let previous = receive.selectedCamera.flatMap { $0 < cameras.count ? cameras[$0].id : nil }
        cameras = devices
        let keep = previous.flatMap { id in devices.firstIndex { $0.id == id } }
        receive.selectedCamera = keep
        receive.camerasListed(devices.map(\.name), preferred: keep ?? preferred)
    }

    func selectCamera(_ index: Int) { receive.selectedCamera = index }

    /// The selected camera faces the user (preview mirroring only).
    var previewMirrored: Bool {
        guard let i = receive.selectedCamera, i < cameras.count,
              let d = AVCaptureDevice(uniqueID: cameras[i].id) else { return false }
        return d.deviceType == .builtInWideAngleCamera || d.position == .front
    }

    /// FLASH-033 — permission first (Mac), then a fresh decoder and the session.
    func startCamera() async {
        guard let receiver, let i = receive.selectedCamera, i < cameras.count, receive.startEnabled else { return }
        if FlashCameraReceiver.authorization == .notDetermined {
            let granted = await FlashCameraReceiver.requestAccess()
            receive.setAccess(granted ? .granted : .denied)
            guard granted else { return }
        } else if FlashCameraReceiver.authorization != .authorized {
            receive.setAccess(.denied)
            return
        } else {
            receive.setAccess(.granted)
        }
        receive.cameraStarting()
        receiver.start(deviceID: cameras[i].id)
    }

    /// FLASH-035.
    func stopCamera() {
        receiver?.stop()
        _ = receive.cameraStopped()
    }

    func openCameraSettings() {
        if let url = URL(string: FlashSyncTexts.cameraSettingsURL) { NSWorkspace.shared.open(url) }
    }

    /// SHELL-676: ⌘. / ⎋ — stop whatever runs on the visible tab (flashing or the camera); otherwise nothing.
    func stopCommand() {
        if isFullScreen { exitFullScreen(); return }
        switch tab {
        case .send: if send.isFlashing { stopFlashing() }
        case .receive: if receive.isCapturing { stopCamera() }
        }
    }

    private func progressed(_ p: FlashReceiveProgress) {
        let before = receive.solved
        if receive.progressed(solved: p.solved, total: p.total, label: p.label, complete: p.complete) {
            receiver?.applying = true
            Task { await finishReceive() }
        }
        if receive.solved > before { solvedPulse += 1 }
    }

    /// FLASH-041…047.
    private func finishReceive() async {
        guard let receiver, let store, let env else { return }
        receiver.stop()
        let (payload, kind) = await receiver.finish()
        defer { receiver.applying = false }
        guard let payload else {
            receive.finished(.damaged)
            announce(FlashSyncTexts.damaged)
            return
        }
        guard let change = FlashSyncStore.preview(payload, kind: kind) else {
            receive.finished(.unreadable)
            announce(FlashSyncTexts.unreadable)
            return
        }
        guard await askToApply(change) else {
            receive.finished(.discarded)
            return
        }
        if env.isSafeMode || env.isReadOnlyInstance {
            await dialogs.error(FlashSyncTexts.dialogTitle, FlashSyncTexts.applyFailed(FlashSyncError.databaseUnreadableMessage))
            receive.finished(.failed)
            return
        }
        do {
            env.flushAllEditors()
            if env.store.isDirty { try env.saveQuietly() }
            env.store.cancelPendingAutosave()
            _ = try store.apply(change)
            env.loadDataAndInitUI(reason: .flashSyncApply, status: FlashSyncTexts.appliedStatusBar)   // FLASH-006/130
            receive.finished(.applied(summary: change.summary))
            announce(FlashSyncTexts.applied(change.summary))
            if send.canRePrepare { prepareSend() }                         // the baseline moved
            else { stopFlashing(); send.didConfirm(); dropStream(); prepareSend() }
        } catch {
            await dialogs.error(FlashSyncTexts.dialogTitle, FlashSyncTexts.applyFailed(error.localizedDescription))
            receive.finished(.failed)
        }
    }

    /// FLASH-044 / FLASH-135: the rich review sheet (safe default: Don't Apply).
    private func askToApply(_ change: FlashIncomingChange) async -> Bool {
        await withCheckedContinuation { cont in
            reviewContinuation = cont
            review = FlashPendingReview(change: change)
        }
    }

    func finishReview(_ apply: Bool) {
        review = nil
        reviewContinuation?.resume(returning: apply)
        reviewContinuation = nil
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: text])
    }
}
