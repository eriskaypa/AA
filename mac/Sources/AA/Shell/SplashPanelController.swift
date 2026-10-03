// Spec: 03 SHELL-003 (splash: Splash.png 560×632 on white, 1-px border, 2.4 s, no click-to-dismiss), §6.1 (plain
//       floating window, centred; 0.2 s fade allowed); ARCHITECTURE.md §7.1 (SceneOpener opens and dismisses it).
import AppKit
import SwiftUI

/// The splash as a borderless, non-activating floating panel brought forward with `orderFrontRegardless()` — never
/// made key. (A SwiftUI `.plain` Window opened with `openWindow` is sent `makeKeyAndOrderFront`, and AppKit logs
/// "-[NSWindow makeKeyWindow] called on … which returned NO from -[NSWindow canBecomeKeyWindow]" — V-PACKAGE.)
@MainActor
final class SplashPanelController {
    static let shared = SplashPanelController()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let host = NSHostingView(rootView: SplashView().aaWindowRoot(.splash))
            host.sizingOptions = [.preferredContentSize]
            let size = host.fittingSize
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.title = "AA"
            p.contentView = host
            p.level = .floating
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isRestorable = false
            p.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
            panel = p
        }
        panel?.center()
        panel?.orderFrontRegardless()
    }

    func close() {
        panel?.close()
        panel = nil
    }
}
