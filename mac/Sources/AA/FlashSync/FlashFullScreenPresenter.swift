// Spec: 13 FLASH-134 (optional: present the QR full-screen on a chosen display — brightest / facing the phone),
//       FLASH-016 (white plate, quiet zone, crisp integer modules), §6.5 (hide the cursor over the plate while flashing).
import AppKit
import AACore

/// A borderless white window covering one display, showing the live frame. Click or Esc returns.
@MainActor
final class FlashFullScreenPresenter {
    private var window: FlashFullScreenWindow?
    private let plate = FlashQRPlateView()
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) { self.onClose = onClose }

    func present(on screen: NSScreen, frame: FlashRenderedFrame?) {
        let w = window ?? FlashFullScreenWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered,
                                                defer: false)
        w.setFrame(screen.frame, display: true)
        w.level = .screenSaver
        w.backgroundColor = .white
        w.isOpaque = true
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        w.onDismiss = { [weak self] in self?.dismissFromUser() }

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        plate.frame = container.bounds.insetBy(dx: 48, dy: 48)
        plate.autoresizingMask = [.width, .height]
        container.addSubview(plate)

        let hint = NSTextField(labelWithString: FlashSyncTexts.exitFullScreen)
        hint.textColor = NSColor(white: 0.45, alpha: 1)
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.sizeToFit()
        hint.frame.origin = NSPoint(x: (container.bounds.width - hint.frame.width) / 2, y: 16)
        hint.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        container.addSubview(hint)

        w.contentView = container
        plate.frameImage = frame
        window = w
        w.makeKeyAndOrderFront(nil)
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    func show(_ frame: FlashRenderedFrame) {
        plate.frameImage = frame
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }

    private func dismissFromUser() {
        dismiss()
        onClose()
    }
}

final class FlashFullScreenWindow: NSWindow {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?() } else { super.keyDown(with: event) }        // Esc
    }

    override func mouseDown(with event: NSEvent) { onDismiss?() }
}
