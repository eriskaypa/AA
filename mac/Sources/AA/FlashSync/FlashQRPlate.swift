// Spec: 13 FLASH-016 (white plate in both appearances, radius 4, padding 18, min height 300; nearest-neighbour; each frame
//       fitted independently), §6.3 "Rendering" (an INTEGER number of device pixels per module, recomputed on resize /
//       screen change, pixel-aligned, interpolation off — crisper than Windows' uniform stretch), §6.6 accessibility
//       (label "Flash Sync code", frame churn hidden from VoiceOver), ARCH §8.4 (never glass on the plate).
import AppKit
import SwiftUI
import AACore

/// Draws a 1-px-per-module QR image at the largest integer device-pixel scale that fits, centred and pixel-aligned,
/// with interpolation off. White in both appearances.
final class FlashQRPlateView: NSView {
    var frameImage: FlashRenderedFrame? {
        didSet { if oldValue?.image !== frameImage?.image { needsDisplay = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(FlashSyncTexts.qrAccessibilityLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isOpaque: Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    /// The code's rectangle in view points: whole device pixels per module, centred on a device-pixel boundary.
    func codeRect(scale: CGFloat) -> CGRect? {
        guard let f = frameImage, f.modules > 0 else { return nil }
        let sidePx = min(bounds.width, bounds.height) * scale
        let modulePx = max(1, Int(sidePx / CGFloat(f.modules)))
        let side = CGFloat(modulePx * f.modules) / scale
        let x = ((bounds.width - side) / 2 * scale).rounded(.down) / scale
        let y = ((bounds.height - side) / 2 * scale).rounded(.down) / scale
        return CGRect(x: x, y: y, width: side, height: side)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext, let image = frameImage?.image,
              let rect = codeRect(scale: window?.backingScaleFactor ?? 2) else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(image, in: rect)
        ctx.restoreGState()
    }
}

struct FlashQRPlate: NSViewRepresentable {
    let frame: FlashRenderedFrame?

    func makeNSView(context: Context) -> FlashQRPlateView { FlashQRPlateView() }

    func updateNSView(_ nsView: FlashQRPlateView, context: Context) { nsView.frameImage = frame }
}
