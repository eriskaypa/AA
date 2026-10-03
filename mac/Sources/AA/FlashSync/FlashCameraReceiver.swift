// Spec: 13 §6.4 (AVFoundation + Vision receive: permission, enumeration with real names and hot-plug refresh, format
//       ≤ 1920×1080 at the highest frame rate, continuous autofocus where supported, AVCaptureVideoDataOutput 420f with
//       late frames discarded on a serial "FlashSync capture" queue, unmirrored data path, per-frame detection fed
//       untrimmed to the decoder, ≤ 15 Hz UI updates, errors), FLASH-030…041, FLASH-048, 03 SHELL-199 (never touch the
//       camera when unbundled — the caller checks `env.isBundled`).
import AVFoundation
import CoreVideo
import Foundation
import AACore

/// One camera the picker offers.
struct FlashCameraDevice: Identifiable, Hashable, Sendable {
    let id: String          // AVCaptureDevice.uniqueID
    let name: String        // localizedName
}

/// What the capture queue reports to the main actor.
struct FlashReceiveProgress: Sendable, Equatable {
    var solved: Int
    var total: Int
    var label: String
    var complete: Bool
}

/// Owns the capture session, the QR detector and the fountain decoder. Everything except the public entry points runs on
/// the serial capture queue; the decoder and detector are confined to it.
final class FlashCameraReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let queueLabel = "FlashSync capture"
    /// FLASH-039: no sample for this long after start / between samples → "The camera stopped sending frames."
    static let stallInterval: TimeInterval = 1.2

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: FlashCameraReceiver.queueLabel, qos: .userInitiated)
    private let lock = NSLock()

    // Capture-queue state.
    private var decoder = FlashDecoder()
    private var detector: FlashQRDetector?
    private var lastSample = Date.distantPast
    private var lastPost = Date.distantPast
    private var lastPosted: FlashReceiveProgress?
    private var running = false
    private var watchdog: DispatchSourceTimer?

    // Shared flags (lock-protected).
    private var _applying = false
    var applying: Bool {
        get { lock.withLock { _applying } }
        set { lock.withLock { _applying = newValue } }
    }

    /// Main-actor callbacks.
    var onProgress: (@MainActor (FlashReceiveProgress) -> Void)?
    var onError: (@MainActor (String) -> Void)?

    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] n in
            let e = (n.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription ?? "unknown error"
            self?.fail(FlashSyncTexts.cameraError(e))
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.fail(FlashSyncTexts.cameraStoppedSending)
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Devices (FLASH-030)

    static func discover() -> (devices: [FlashCameraDevice], preferred: Int?) {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera]
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
        let devices = found.map { FlashCameraDevice(id: $0.uniqueID, name: $0.localizedName) }
        let def = AVCaptureDevice.default(for: .video)?.uniqueID
        return (devices, devices.firstIndex { $0.id == def })
    }

    static var authorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    static func requestAccess() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }

    // MARK: Start / stop (FLASH-033…035)

    /// Configures and starts the session for a device (fresh decoder). Errors arrive through `onError`.
    func start(deviceID: String) {
        applying = false
        queue.async { [self] in
            stopOnQueue()
            decoder = FlashDecoder()
            if detector == nil { detector = FlashQRDetector() }
            lastPosted = nil
            lastPost = .distantPast
            guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                post(error: FlashSyncTexts.cameraOpenFailed); return
            }
            let input: AVCaptureDeviceInput
            do { input = try AVCaptureDeviceInput(device: device) } catch {
                post(error: FlashSyncTexts.cameraStartFailed(error.localizedDescription)); return
            }
            session.beginConfiguration()
            for i in session.inputs { session.removeInput(i) }
            for o in session.outputs { session.removeOutput(o) }
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                post(error: FlashSyncTexts.cameraOpenFailed); return
            }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true                       // ≙ buffer size 1: freshest frame
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                post(error: FlashSyncTexts.cameraOpenFailed); return
            }
            session.addOutput(output)
            if let c = output.connection(with: .video), c.isVideoMirroringSupported {
                c.automaticallyAdjustsVideoMirroring = false
                c.isVideoMirrored = false                                     // the data path is never mirrored
            }
            if !configureFormat(device) { session.sessionPreset = .high }
            session.commitConfiguration()
            session.startRunning()
            guard session.isRunning else { post(error: FlashSyncTexts.cameraOpenFailed); return }
            running = true
            lastSample = Date()
            startWatchdog()
        }
    }

    /// The largest format ≤ 1920×1080 (exactly 1080p preferred) at its highest frame rate; continuous autofocus.
    private func configureFormat(_ device: AVCaptureDevice) -> Bool {
        var best: (AVCaptureDevice.Format, AVFrameRateRange, Int32, Int32)?
        for f in device.formats {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            guard d.width <= 1920, d.height <= 1080, let range = f.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) else { continue }
            if let b = best {
                let area = Int(d.width) * Int(d.height), bestArea = Int(b.2) * Int(b.3)
                if area < bestArea || (area == bestArea && range.maxFrameRate <= b.1.maxFrameRate) { continue }
            }
            best = (f, range, d.width, d.height)
        }
        guard let (format, range, _, _) = best else { return false }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = range.minFrameDuration
            device.activeVideoMaxFrameDuration = range.minFrameDuration
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    /// FLASH-035: stops capture; the decoder keeps its partial state until the next start.
    func stop() {
        queue.async { [self] in stopOnQueue() }
    }

    private func stopOnQueue() {
        watchdog?.cancel()
        watchdog = nil
        running = false
        if session.isRunning { session.stopRunning() }
    }

    /// FLASH-041: reassemble + verify + inflate on the capture queue (the decoder lives there).
    func finish() async -> (payload: [UInt8]?, kind: FlashFrameKind) {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                cont.resume(returning: (decoder.finish(), decoder.manifest?.kind ?? .changeSet))
            }
        }
    }

    // MARK: Frames (FLASH-037, FLASH-038)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lastSample = Date()
        guard running, !applying, let px = CMSampleBufferGetImageBuffer(sampleBuffer), let detector else { return }
        for text in detector.detect(pixelBuffer: px) { decoder.ingest(text) }
        let p = FlashReceiveProgress(solved: decoder.solvedCount, total: decoder.chunkCount, label: decoder.label,
                                     complete: decoder.isComplete)
        let now = Date()
        // ≤ 15 Hz, but never drop a change in the solved count, the label or completion.
        if p != lastPosted && (now.timeIntervalSince(lastPost) >= 1.0 / 15 || p.complete || p.solved != lastPosted?.solved
                               || p.label != lastPosted?.label) {
            lastPosted = p
            lastPost = now
            if p.complete { running = false }
            let cb = onProgress
            Task { @MainActor in cb?(p) }
        }
        if p.complete { stopOnQueue() }
    }

    private func startWatchdog() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + FlashCameraReceiver.stallInterval, repeating: 0.3)
        t.setEventHandler { [weak self] in
            guard let self, self.running else { return }
            if Date().timeIntervalSince(self.lastSample) > FlashCameraReceiver.stallInterval {
                self.stopOnQueue()
                self.post(error: FlashSyncTexts.cameraStoppedSending)
            }
        }
        watchdog = t
        t.resume()
    }

    private func fail(_ message: String) {
        queue.async { [self] in
            guard running else { return }
            stopOnQueue()
            post(error: message)
        }
    }

    private func post(error message: String) {
        let cb = onError
        Task { @MainActor in cb?(message) }
    }
}
