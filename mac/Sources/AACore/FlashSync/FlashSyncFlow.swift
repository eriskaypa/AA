// Spec: 13 §2.2–2.3 — the Send and Receive tab state machines of FlashSyncWindow.xaml.cs, as pure value types so the
//       button enablement, texts and key handling are testable: FLASH-010…020 (prepare, summary, Start/Stop, speed,
//       progress, confirm, pending baseline), FLASH-030…048 (camera list, Rescan disabled while capturing — Q-7 fix,
//       statuses, completion guard), DECISIONS 13 Q-4 (clear a stale encoder/pending baseline), Q-9 (framesShown resets
//       per prepare on the Mac), Q-8 (estimate refreshed live with the slider), 03 SHELL-676 / T-KB-46/47 (⌘. / ⎋ stop).

/// The Send tab.
public struct FlashSendFlow: Sendable, Equatable {
    public enum Prepared: Sendable, Equatable {
        case none
        case nothingToSend
        case snapshot(chunks: Int)
        case changeSet(label: String, chunks: Int)
        case unavailable(String)
    }

    public static let minFps = 6, maxFps = 15, defaultFps = 12

    public private(set) var prepared: Prepared = .none
    public private(set) var isFlashing = false
    public private(set) var confirmEnabled = false
    public private(set) var framesShown = 0
    public var fps: Int = FlashSendFlow.defaultFps {
        didSet { fps = min(max(fps, FlashSendFlow.minFps), FlashSendFlow.maxFps) }
    }

    public init(fps: Int = FlashSendFlow.defaultFps) {
        self.fps = min(max(fps, FlashSendFlow.minFps), FlashSendFlow.maxFps)
    }

    public var hasPayload: Bool {
        switch prepared {
        case .snapshot, .changeSet: return true
        default: return false
        }
    }

    public var chunkCount: Int {
        switch prepared {
        case .snapshot(let k), .changeSet(_, let k): return k
        default: return 0
        }
    }

    public var startEnabled: Bool { hasPayload && !isFlashing }
    public var stopEnabled: Bool { isFlashing }
    /// The speed slider and Reset Pairing are only offered when no transfer is mid-flight.
    public var canResetPairing: Bool { !isFlashing && !confirmEnabled }
    /// `prepareSend` must never run while flashing or while a confirmation is pending (it would change the session).
    public var canRePrepare: Bool { !isFlashing && !confirmEnabled }

    public var summaryText: String {
        switch prepared {
        case .none: return ""
        case .nothingToSend: return FlashSyncTexts.nothingToSend
        case .snapshot(let k): return FlashSyncTexts.snapshotSummary(chunks: k, fps: fps)
        case .changeSet(let label, let k): return FlashSyncTexts.changeSetSummary(label: label, chunks: k, fps: fps)
        case .unavailable(let message): return message
        }
    }

    public var progressText: String {
        framesShown == 0 ? "" : FlashSyncTexts.flashingProgress(framesShown: framesShown, chunks: chunkCount)
    }

    /// FLASH-010 with a payload: a new encoder (new session) was built.
    public mutating func didPrepare(kind: FlashFrameKind, label: String, chunks: Int) {
        prepared = kind == .fullSnapshot ? .snapshot(chunks: chunks) : .changeSet(label: label, chunks: chunks)
        framesShown = 0
    }

    /// FLASH-010 nothing to send — and Q-4: any stale encoder and pending baseline are gone, flashing stops.
    public mutating func didFindNothingToSend() {
        prepared = .nothingToSend
        isFlashing = false
        confirmEnabled = false
        framesShown = 0
    }

    /// Q-5: the database (or settings) could not be read — nothing can be sent.
    public mutating func didFail(_ message: String) {
        prepared = .unavailable(message)
        isFlashing = false
        confirmEnabled = false
        framesShown = 0
    }

    /// FLASH-013: returns false (no-op) without a payload.
    @discardableResult
    public mutating func start() -> Bool {
        guard startEnabled else { return false }
        isFlashing = true
        confirmEnabled = true
        return true
    }

    /// FLASH-014: the confirm button stays as it was; counters are kept (Start continues the same stream).
    @discardableResult
    public mutating func stop() -> Bool {
        guard isFlashing else { return false }
        isFlashing = false
        return true
    }

    /// SHELL-676 / T-KB-46/47: ⌘. or ⎋ stops flashing when running, otherwise does nothing.
    public mutating func stopCommand() -> Bool { stop() }

    public mutating func frameShown() { framesShown += 1 }

    /// FLASH-020: after the baseline was written — stop, disable confirm, drop the encoder, clear the progress text.
    public mutating func didConfirm() {
        isFlashing = false
        confirmEnabled = false
        prepared = .none
        framesShown = 0
    }

    /// FLASH-018: a frame could not be drawn.
    public mutating func drawFailed() { isFlashing = false }
}

/// The Receive tab.
public struct FlashReceiveFlow: Sendable, Equatable {
    public enum CameraAccess: Sendable, Equatable { case unknown, granted, denied, unbundled }

    public private(set) var cameraNames: [String] = []
    public var selectedCamera: Int?
    public private(set) var isCapturing = false
    public private(set) var isApplying = false
    public private(set) var access: CameraAccess = .unknown
    public private(set) var solved = 0
    public private(set) var total = 0
    public private(set) var statusText = ""
    public private(set) var labelText = ""
    /// True while the status shows a problem the user must act on (styled as a warning).
    public private(set) var statusIsProblem = false

    public init() {}

    public var startEnabled: Bool {
        access != .denied && access != .unbundled && !cameraNames.isEmpty && selectedCamera != nil && !isCapturing && !isApplying
    }
    public var stopEnabled: Bool { isCapturing }
    /// Q-7 fix: Rescan and the picker are disabled while the camera runs.
    public var rescanEnabled: Bool { !isCapturing && !isApplying && access != .unbundled }
    public var pickerEnabled: Bool { !isCapturing && !isApplying && !cameraNames.isEmpty }
    public var progress: Double { total > 0 ? Double(solved) / Double(total) : 0 }

    public mutating func setAccess(_ a: CameraAccess) {
        access = a
        switch a {
        case .denied: status(FlashSyncTexts.cameraDenied, problem: true)
        case .unbundled: status(FlashSyncTexts.unbundledCamera, problem: true)
        case .granted, .unknown:
            // DEV-FLASH-26: the user allowed the camera in System Settings and came back — the denied text goes.
            if statusText == FlashSyncTexts.cameraDenied { status("", problem: false) }
        }
    }

    /// FLASH-030/031: the list (real device names on the Mac); empty → the "No camera found" status.
    public mutating func camerasListed(_ names: [String], preferred: Int? = nil) {
        cameraNames = names
        if names.isEmpty {
            selectedCamera = nil
            if access != .denied && access != .unbundled { status(FlashSyncTexts.noCamera, problem: true) }
        } else {
            if (selectedCamera ?? Int.max) >= names.count {            // keep a still-valid choice
                selectedCamera = preferred.flatMap { $0 < names.count ? $0 : nil } ?? 0
            }
            if statusText == FlashSyncTexts.noCamera { status("", problem: false) }
        }
    }

    /// FLASH-033: a fresh decoder; status "Looking…"; bar 0; label cleared.
    public mutating func cameraStarting() {
        solved = 0
        total = 0
        labelText = ""
        status(FlashSyncTexts.looking, problem: false)
        isCapturing = true
    }

    /// FLASH-035 (the decoder's partial state is kept by the caller until the next Start).
    @discardableResult
    public mutating func cameraStopped() -> Bool {
        guard isCapturing else { return false }
        isCapturing = false
        return true
    }

    /// SHELL-676: ⌘. / ⎋ stops the camera when running, otherwise nothing.
    public mutating func stopCommand() -> Bool { cameraStopped() }

    /// FLASH-039: the camera stopped with an error; the message replaces the status.
    public mutating func cameraFailed(_ message: String) {
        isCapturing = false
        status(message, problem: true)
    }

    /// FLASH-038: progress after each frame. Returns true when the transfer just completed and an apply may start
    /// (FLASH-041/048: exactly once, never while applying).
    public mutating func progressed(solved s: Int, total k: Int, label: String, complete: Bool) -> Bool {
        guard !isApplying else { return false }
        if k > 0 {
            solved = s
            total = k
            status(FlashSyncTexts.receiving(solved: s, of: k), problem: false)
            if !NetText.isBlank(label) { labelText = FlashSyncTexts.incoming(label) }
        } else {
            status(FlashSyncTexts.looking, problem: false)
        }
        if complete {
            isApplying = true
            isCapturing = false
            return true
        }
        return false
    }

    public enum Outcome: Sendable, Equatable {
        case damaged, unreadable, discarded, applied(summary: String), failed
    }

    /// FLASH-042…047: the end of a receive; clears the applying guard.
    public mutating func finished(_ outcome: Outcome) {
        isApplying = false
        switch outcome {
        case .damaged: status(FlashSyncTexts.damaged, problem: true)
        case .unreadable: status(FlashSyncTexts.unreadable, problem: true)
        case .discarded: status(FlashSyncTexts.discarded, problem: false)
        case .applied(let summary): status(FlashSyncTexts.applied(summary), problem: false)
        case .failed: status(FlashSyncTexts.applyFailedStatus, problem: true)
        }
    }

    private mutating func status(_ text: String, problem: Bool) {
        statusText = text
        statusIsProblem = problem
    }
}
