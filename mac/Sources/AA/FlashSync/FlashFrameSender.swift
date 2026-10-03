// Spec: 13 §6.5 (frame clock from a display link — every code held for a whole number of refreshes; pre-render frame
//       n+1 on a background serial queue while frame n is shown, the encoder confined to that queue; keep-awake via
//       ProcessInfo activity ≙ ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED), FLASH-013 (first frame one interval after
//       Start), FLASH-014, FLASH-015 (speed applies immediately), FLASH-018 (draw failure stops flashing), FLASH-023,
//       FLASH-024, FLASH-071 (Apple-reader-safe masks, DEV-FLASH-05).
import AppKit
import QuartzCore
import AACore

/// A rendered frame: the QR at 1 px per module with its 4-module quiet zone.
struct FlashRenderedFrame: @unchecked Sendable {
    let image: CGImage
    let modules: Int
}

/// Drives the endless QR stream for the Send tab.
@MainActor
final class FlashFrameSender {
    private let renderQueue = DispatchQueue(label: "FlashSync render", qos: .userInteractive)
    private var encoder: FlashEncoder?
    private var link: CADisplayLink?
    private var proxy: FlashDisplayLinkProxy?
    /// Fallback clock: a display link pauses while its display sleeps or the window is occluded; then a 60 Hz common-mode
    /// timer (≙ the Windows DispatcherTimer) keeps the stream going until the link ticks again.
    private var fallback: Timer?
    private var lastLinkTick: CFTimeInterval = 0
    private var activity: NSObjectProtocol?
    private var ready: FlashRenderedFrame?
    /// At most one background render; a replaced encoder frees the slot (a stale completion is ignored).
    private var gate = FlashRenderGate()
    private var lastShown: CFTimeInterval = 0
    private(set) var isRunning = false

    var fps = FlashSendFlow.defaultFps
    /// Called with every frame as it is shown.
    var onFrame: ((FlashRenderedFrame) -> Void)?
    /// Called (after stopping) when a frame could not be drawn.
    var onFailure: ((String) -> Void)?

    /// Replaces the stream (a new session after every prepare). Stops a running clock.
    /// A render still in flight for the old encoder is abandoned: `gate.reset()` frees the slot, so the new stream's
    /// first render is never blocked by the old one's late completion (FLASH-013/020/023 after a confirm or apply).
    func setEncoder(_ e: FlashEncoder?) {
        stop()
        encoder = e
        ready = nil
        gate.reset()
    }

    var hasEncoder: Bool { encoder != nil }

    func start(on screen: NSScreen?) {
        guard encoder != nil, !isRunning else { return }
        isRunning = true
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
            reason: "Flash Sync is showing QR codes")
        lastShown = CACurrentMediaTime()                                       // first frame after one interval
        renderNext()
        let p = FlashDisplayLinkProxy { [weak self] t in
            self?.lastLinkTick = CACurrentMediaTime()
            self?.tick(t)
        }
        proxy = p
        let l = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.displayLink(target: p, selector: #selector(FlashDisplayLinkProxy.tick(_:)))
        l?.add(to: .main, forMode: .common)
        link = l
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, CACurrentMediaTime() - self.lastLinkTick > 0.1 else { return }
                self.tick(CACurrentMediaTime())
            }
        }
        RunLoop.main.add(t, forMode: .common)
        fallback = t
    }

    func stop() {
        link?.invalidate()
        link = nil
        proxy = nil
        fallback?.invalidate()
        fallback = nil
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
        activity = nil
        isRunning = false
    }

    private func tick(_ timestamp: CFTimeInterval) {
        guard isRunning else { return }
        let interval = 1.0 / Double(max(1, fps))
        // Small tolerance so a 60 Hz display holds each code for exactly ⌈60/fps⌉ refreshes, never one fewer.
        guard timestamp - lastShown >= interval - 0.004, let frame = ready else { return }
        lastShown = timestamp
        ready = nil
        onFrame?(frame)
        renderNext()
    }

    private func renderNext() {
        guard let encoder, ready == nil, let gen = gate.begin() else { return }
        renderQueue.async { [weak self] in
            let text = encoder.next()
            let result: Result<FlashRenderedFrame, Error>
            do {
                let qr = try FlashQRCode.flashFrame(text)
                if let img = FlashQRRaster.cgImage(qr, scale: 1) {
                    result = .success(FlashRenderedFrame(image: img, modules: qr.size + 2 * FlashQRRaster.quietZone))
                } else {
                    result = .failure(FlashSendRenderError.raster)
                }
            } catch {
                result = .failure(error)
            }
            Task { @MainActor [weak self] in
                guard let self, self.gate.complete(gen) else { return }
                switch result {
                case .success(let f): self.ready = f
                case .failure(let e):
                    self.stop()
                    self.onFailure?(String(describing: e))
                }
            }
        }
    }
}

enum FlashSendRenderError: Error, CustomStringConvertible {
    case raster
    var description: String { "the image could not be created." }
}

/// `CADisplayLink` needs an NSObject target.
final class FlashDisplayLinkProxy: NSObject {
    private let handler: @MainActor (CFTimeInterval) -> Void
    init(_ handler: @escaping @MainActor (CFTimeInterval) -> Void) { self.handler = handler }

    @objc func tick(_ link: CADisplayLink) {
        let t = link.targetTimestamp
        MainActor.assumeIsolated { handler(t) }
    }
}
