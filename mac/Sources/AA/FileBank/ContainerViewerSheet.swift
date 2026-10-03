// PLACEHOLDER(W-FILES) — contract: ARCHITECTURE.md §7.7
// Spec: 04 HIER-136 (read-only viewer). Compiling stub created by F3; W-FILES replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct ContainerViewerSheet: View {
    let title: String
    let container: Container

    init(title: String, container: Container) { self.title = title; self.container = container }

    var body: some View {
        // PLACEHOLDER(W-FILES)
        AAEmptyState(title: "Viewer — not yet implemented", symbol: "doc.text.magnifyingglass", message: "PLACEHOLDER(W-FILES)")
    }
}
