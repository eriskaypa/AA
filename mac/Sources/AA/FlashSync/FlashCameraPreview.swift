// Spec: 13 FLASH-036 / §6.4 step 6 (AVCaptureVideoPreviewLayer, resizeAspect, black rounded plate, min height 280,
//       GPU-composited so no throttle is needed; the preview may be mirrored for built-in cameras — the data path never is).
import AppKit
import AVFoundation
import SwiftUI

final class FlashCameraPreviewView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }

    /// Natural hand–eye feel for a camera facing the user (built-in / display cameras); external cameras unmirrored.
    func setMirrored(_ mirrored: Bool) {
        guard let c = previewLayer.connection, c.isVideoMirroringSupported else { return }
        c.automaticallyAdjustsVideoMirroring = false
        c.isVideoMirrored = mirrored
    }
}

struct FlashCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool

    func makeNSView(context: Context) -> FlashCameraPreviewView { FlashCameraPreviewView(session: session) }

    func updateNSView(_ nsView: FlashCameraPreviewView, context: Context) { nsView.setMirrored(mirrored) }
}
