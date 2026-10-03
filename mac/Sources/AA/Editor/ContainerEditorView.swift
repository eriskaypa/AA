// PLACEHOLDER(W-CONT) — contract: ARCHITECTURE.md §7.7
// Spec: 05 §2.1–2.4 (container editor). Compiling stub created by F3; W-CONT replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct ContainerEditorContext {
    var title: String
    var host: EditorHost
    var isEnabled = true
    var showsFileBank = true
}

enum EditorHost: Hashable {
    case mainPane(ItemKind), itemWindow(UUID), component(UUID), subtask(UUID), step(UUID), savedListItem(UUID)
}

struct ContainerEditorView: View {
    let container: Container
    let context: ContainerEditorContext

    init(container: Container, context: ContainerEditorContext) { self.container = container; self.context = context }

    var body: some View {
        // PLACEHOLDER(W-CONT)
        AAEmptyState(title: "Notes editor — not yet implemented", symbol: "doc.richtext", message: "PLACEHOLDER(W-CONT)")
    }
}
