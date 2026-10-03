// PLACEHOLDER(W-QUICK) — contract: ARCHITECTURE.md §7.7
// Spec: 08 §2.1 (floating due-dates window). Compiling stub created by F3; W-QUICK replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

@MainActor final class DueDatesPanelController {
    static let shared = DueDatesPanelController()
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(env: AppEnvironment) {
        // PLACEHOLDER(W-QUICK) — a plain floating panel so the shell and the snapshot hook have a window to show.
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 480),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.title = "Overdue, today & tomorrow"
            p.level = .floating
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.contentView = NSHostingView(rootView: AAEmptyState(title: "Due dates — not yet implemented",
                                                                 symbol: "pin", message: "PLACEHOLDER(W-QUICK)")
                .environment(env))
            p.center()
            panel = p
            SceneOpener.shared.registerPanel(p, as: .due)
        }
        panel?.orderFront(nil)
    }

    func refresh() {
        // PLACEHOLDER(W-QUICK)
    }
}
