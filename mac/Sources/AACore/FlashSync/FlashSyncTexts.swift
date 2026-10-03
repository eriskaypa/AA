// Spec: 13 §2.1–2.3 (FLASH-003, 011, 012, 013–020, 030–048 — every user-visible string verbatim from the Windows
//       build, "this PC" → "this Mac" where §2 says so), §6.4 (camera permission text), §6.5 (brightness hint),
//       §6.6 (Mac dialog buttons), FLASH-131/132/134, 03 SHELL-199 (unbundled camera text), DECISIONS 13 Q-5.
// One place for every string the Flash Sync window shows, so tests pin them and the view never improvises wording.

public enum FlashSyncTexts {
    // MARK: Window (FLASH-003)
    public static let windowTitle = "Flash Sync with iPhone"
    public static let header = "Flash Sync with iPhone"
    public static let intro = "Moves your text, changes and formatting between this Mac and the iPhone app by flashing QR codes on screen — no network, no cable, no Wi-Fi. Attachments are not carried; files already on the other device are left exactly as they are."
    public static let sendTab = "Send to iPhone"
    public static let receiveTab = "Receive from iPhone"
    public static let dialogTitle = "Flash Sync"

    // MARK: Send (FLASH-011…020)
    public static let nothingToSend = "Nothing to send — the iPhone already has everything, as of the last transfer it confirmed."
    public static let sendHint = "On the iPhone: More ▸ Backup & Transfer ▸ Flash Sync with PC ▸ Receive, then point it at this window."
    public static let startFlashing = "Start flashing"
    public static let stop = "Stop"
    public static let speed = "Speed"
    public static let confirmButton = "The iPhone says it got it"
    public static let confirmTooltip = "Press this only once the iPhone reports the transfer completed. It records what the phone now has, so next time only your newer changes need to be sent."
    public static let confirmCaution = "Only press that when the phone has actually confirmed. It is what makes the next sync short — and if it is pressed early, the changes it skips would never be sent again."
    public static let confirmTitle = "Confirm the iPhone received it"
    public static let confirmMessage = "Has the iPhone actually reported that the transfer finished?\n\nOnly confirm if it has. This records what the phone now holds, so future syncs send just your newer changes. Confirming too early would skip the changes it never received, and they would not be sent again."
    public static let confirmYes = "Yes, It Finished"
    public static let confirmNo = "Not Yet"
    public static let recorded = "Recorded. Next time only your newer changes need to go across."
    public static let brightnessHint = "Turn your screen brightness up — it is the biggest factor in a clean capture."
    public static let qrAccessibilityLabel = "Flash Sync code"

    /// FLASH-015: "{fps} / sec".
    public static func fpsText(_ fps: Int) -> String { "\(fps) / sec" }

    /// FLASH-011 `EstimateSeconds`: `secs = ceil(K × 1.35 / fps) + 1` (fps ≤ 0 → 12); "{secs} seconds" below a
    /// minute, else "{m} min {s} s". Double arithmetic exactly like the C# (`Math.Ceiling(chunks * 1.35 / fps)`), so
    /// the IEEE rounding of 1.35 gives the same figure (e.g. K=80 at 12 fps → 11 seconds on both).
    public static func estimate(chunks: Int, fps: Int) -> String {
        let f = fps <= 0 ? 12.0 : Double(fps)
        let secs = Int((Double(chunks) * 1.35 / f).rounded(.up)) + 1
        return secs < 60 ? "\(secs) seconds" : "\(secs / 60) min \(secs % 60) s"
    }

    /// FLASH-011 snapshot summary (no singular form for "pieces").
    public static func snapshotSummary(chunks: Int, fps: Int) -> String {
        "First transfer to this iPhone, so the whole database goes across: \(chunks) pieces, about \(estimate(chunks: chunks, fps: fps))."
    }

    /// FLASH-011 change-set summary.
    public static func changeSetSummary(label: String, chunks: Int, fps: Int) -> String {
        "Sending your changes since the last confirmed transfer — \(label). \(chunks) piece\(chunks == 1 ? "" : "s"), about \(estimate(chunks: chunks, fps: fps))."
    }

    /// FLASH-017: passes = framesShown / max(1, K).
    public static func flashingProgress(framesShown: Int, chunks: Int) -> String {
        let passes = chunks > 0 ? framesShown / max(1, chunks) : 0
        return "Flashing — \(framesShown) frames shown, \(passes) full pass\(passes == 1 ? "" : "es"). Keep going until the iPhone says it is done."
    }

    /// FLASH-018.
    public static func drawFailure(_ message: String) -> String { "Could not draw the QR code: \(message)" }

    // MARK: Reset pairing (FLASH-131, Mac addition)
    public static let resetPairing = "Reset Pairing…"
    public static let resetPairingHelp = "Forget what the iPhone was last confirmed to have, so the next send is the whole database."
    public static let resetPairingTitle = "Reset pairing with the iPhone?"
    public static let resetPairingMessage = "The next transfer will send the whole database instead of just your newer changes. Use this when the two devices have drifted apart."
    public static let resetPairingConfirm = "Reset Pairing"
    public static let resetPairingDone = "Pairing reset. The next send is the whole database."

    // MARK: Full screen (FLASH-134, Mac addition)
    public static let fullScreen = "Show Full Screen"
    public static let fullScreenHelp = "Show the code on its own, filling a display — drag this window to the brightest screen first."
    public static let exitFullScreen = "Click or press Esc to return"

    // MARK: Receive (FLASH-030…048)
    public static let camera = "Camera"
    public static let startCamera = "Start camera"
    public static let rescan = "Rescan"
    public static let noCamera = "No camera found. Plug one in and press Rescan — or use the Send tab, which needs no camera at all."
    public static let looking = "Looking for the iPhone's screen…"
    public static let receiveHint = "On the iPhone: More ▸ Backup & Transfer ▸ Flash Sync with PC ▸ Send. Hold the phone steady, fairly close, screen bright and square-on to the camera. Missed frames are normal — the transfer repairs itself and simply takes a moment longer."
    public static let macCameraHint = "Mac cameras are fixed-focus: hold the phone 25–40 cm from the camera, filling at least half the preview. A Continuity Camera or any USB webcam also works."
    public static let cameraOpenFailed = "That camera could not be opened. Another app may be using it."
    public static let cameraStoppedSending = "The camera stopped sending frames."
    public static func cameraStartFailed(_ message: String) -> String { "Could not start the camera: \(message)" }
    public static func cameraError(_ message: String) -> String { "Camera error: \(message)" }
    public static func readerStartFailed(_ message: String) -> String { "The QR reader could not start: \(message)" }
    public static let cameraDenied = "Camera access is turned off for AA. Allow it in System Settings ▸ Privacy & Security ▸ Camera."
    public static let openSystemSettings = "Open System Settings"
    public static let cameraSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
    /// 03 SHELL-199 — developer-only text for `swift run` (no Info.plist, no camera usage description).
    public static let unbundledCamera = "The camera needs the packaged app. Build it with Scripts/build-app.sh and open dist/AA.app."

    /// FLASH-038.
    public static func receiving(solved: Int, of total: Int) -> String { "Receiving — \(solved) of \(total) pieces. Hold steady." }
    public static func incoming(_ label: String) -> String { "Incoming: \(label)" }

    public static let damaged = "The transfer arrived damaged, so nothing was changed. Start the iPhone sending again."
    public static let unreadable = "That transfer was not readable as Flash Sync data. Nothing was changed."
    public static let applyTitle = "Apply the received changes?"
    public static let applyButton = "Apply"
    public static let dontApplyButton = "Don't Apply"
    public static let snapshotWarning = "\n\nThis REPLACES your current database with the iPhone's copy. Anything on this Mac that is not on the phone will be lost."
    /// FLASH-132 (protocol §10: say so when settings are absent).
    public static let noSettingsNote = "This copy carries no settings (dark mode etc. stay as they are)."
    public static let discarded = "Discarded — nothing was changed."
    public static func applied(_ summary: String) -> String { "Applied. \(summary)" }
    public static func applyFailed(_ message: String) -> String { "Could not apply the transfer: \(message)" }
    public static let applyFailedStatus = "Failed to apply — your data was not changed."
    /// FLASH-006 status-bar text after the reload.
    public static let appliedStatusBar = "Applied changes received from the iPhone"

    /// FLASH-044 review text (+ FLASH-132 note for a snapshot without settings).
    public static func applyQuestion(_ change: FlashIncomingChange) -> String {
        var text = "Received from the iPhone:\n\n    \(change.summary)"
        if change.isSnapshot { text += snapshotWarning }
        if change.isSnapshot && !change.carriesSettings { text += "\n\n" + noSettingsNote }
        return text + "\n\nApply it now?"
    }
}
