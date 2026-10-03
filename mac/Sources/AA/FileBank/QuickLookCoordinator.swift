// Spec: 03 SHELL-669 (Space = Quick Look in file tables), SHELL-543 (⌘Y Quick Look), 05 §6.9 / CONT-096 (Quick Look on
//       the Mac), 04 HIER-M06 (Quick Look in the read-only viewer); ARCHITECTURE.md §7.7 (responder-chain
//       implementation: a responder implementing `acceptsPreviewPanelControl` / `beginPreviewPanelControl` /
//       `endPreviewPanelControl` is spliced into the key window's responder chain while previewing — never a free-standing
//       data source without a controller), §9.4.
import AppKit
import QuickLookUI
import SwiftUI
import AACore

/// The app's Quick Look controller. `preview(_:selectedIndex:)` shows (or retargets) the shared `QLPreviewPanel`;
/// while the panel is under its control this responder sits right after the key window in the responder chain.
@MainActor final class QuickLookCoordinator: NSResponder, @MainActor QLPreviewPanelDataSource, @MainActor QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()

    private(set) var urls: [URL] = []
    private var index = 0
    private weak var hostWindow: NSWindow?
    private var isControlling = false

    private override init() { super.init() }
    required init?(coder: NSCoder) { nil }

    /// Shows `urls` in the Quick Look panel starting at `selectedIndex` (local file URLs; anything else is skipped).
    /// An empty list beeps.
    func preview(_ urls: [URL], selectedIndex: Int = 0) {
        let local = urls.filter { $0.isFileURL }
        guard !local.isEmpty, let panel = QLPreviewPanel.shared() else { NSSound.beep(); return }
        self.urls = local
        index = min(max(selectedIndex, 0), local.count - 1)
        if isControlling, panel.isVisible {
            panel.reloadData()
            panel.currentPreviewItemIndex = index
            return
        }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow
                ?? NSApp.orderedWindows.first(where: { $0.isVisible && $0.canBecomeKey }) else { NSSound.beep(); return }
        splice(into: window)
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
        if !isControlling {
            // No key window chain reached this responder (the app is not active): never show an empty panel.
            panel.orderOut(nil)
            unsplice()
            NSSound.beep()
        }
    }

    /// Space semantics (Finder): close the panel when it is showing our items, else preview.
    func toggle(_ urls: [URL], selectedIndex: Int = 0) {
        if isVisible { close() } else { preview(urls, selectedIndex: selectedIndex) }
    }

    /// Follows a selection change while the panel is open (no-op when it is closed).
    func updateIfVisible(_ urls: [URL], selectedIndex: Int) {
        guard isVisible else { return }
        let local = urls.filter { $0.isFileURL }
        guard !local.isEmpty else { return }
        preview(local, selectedIndex: selectedIndex)
    }

    var isVisible: Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else { return false }
        return isControlling && panel.isVisible
    }

    func close() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else { return }
        panel.orderOut(nil)
    }

    // MARK: Responder chain

    private func splice(into window: NSWindow) {
        if hostWindow === window, window.nextResponder === self { return }
        unsplice()
        nextResponder = window.nextResponder
        window.nextResponder = self
        hostWindow = window
    }

    private func unsplice() {
        guard let w = hostWindow else { return }
        var r: NSResponder? = w
        while let cur = r {
            if cur.nextResponder === self {
                cur.nextResponder = nextResponder
                break
            }
            r = cur.nextResponder
        }
        nextResponder = nil
        hostWindow = nil
    }

    // MARK: QLPreviewPanelController (informal protocol)

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        isControlling = true
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = index
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        isControlling = false
        panel.dataSource = nil
        panel.delegate = nil
        unsplice()
    }

    // MARK: Data source

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }

    // MARK: Delegate

    /// Arrow keys inside the panel step through the items (the panel itself handles ← / →); Space closes it.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        if event.keyCode == 49 {                                          // Space
            panel.orderOut(nil)
            return true
        }
        return false
    }
}
