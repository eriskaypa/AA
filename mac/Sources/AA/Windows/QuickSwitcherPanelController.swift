// PLACEHOLDER(W-QUICK) — contract: ARCHITECTURE.md §7.7
// Spec: 08 §2.3 (quick switcher). Compiling stub created by F3; W-QUICK replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

@MainActor final class QuickSwitcherPanelController {
    static let shared = QuickSwitcherPanelController()
    private var panel: NSPanel?

    func show(env: AppEnvironment) {
        // PLACEHOLDER(W-QUICK) — a plain floating panel so the shell and the snapshot hook have a window to show.
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.title = "Go to item"
            p.level = .floating
            p.isReleasedWhenClosed = false
            p.contentView = NSHostingView(rootView: AAEmptyState(title: "Quick switcher — not yet implemented",
                                                                 symbol: "arrow.right.circle", message: "PLACEHOLDER(W-QUICK)")
                .environment(env))
            p.center()
            panel = p
            SceneOpener.shared.registerPanel(p, as: .switcher)
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}
