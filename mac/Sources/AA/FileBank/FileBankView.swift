// PLACEHOLDER(W-FILES) — contract: ARCHITECTURE.md §7.7
// Spec: 05 §2.5 (file bank). Compiling stub created by F3; W-FILES replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct FileBankContext {
    var host: EditorHost
    var isEnabled = true
}

struct FileBankView: View {
    let container: Container
    let context: FileBankContext

    init(container: Container, context: FileBankContext) { self.container = container; self.context = context }

    var body: some View {
        // PLACEHOLDER(W-FILES)
        AAEmptyState(title: "File bank — not yet implemented", symbol: "folder", message: "PLACEHOLDER(W-FILES)")
    }
}

@MainActor enum FileBankOperations {
    static func addImported(storedPath: String, displayName: String, to container: Container, env: AppEnvironment) -> FileItem {
        // PLACEHOLDER(W-FILES)
        FileItem()
    }

    static func addFiles(_ urls: [URL], linkInPlace: Bool, to container: Container, env: AppEnvironment) throws -> [FileItem] {
        // PLACEHOLDER(W-FILES)
        []
    }
}
