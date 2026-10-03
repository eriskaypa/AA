// PLACEHOLDER(W-QUICK) — contract: ARCHITECTURE.md §7.7
// Spec: 08 §2.6 (Trash). Compiling stub created by F3; W-QUICK replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct TrashSheet: View {
    let onFinish: (() -> Void)?

    init(onFinish: (() -> Void)? = nil) { self.onFinish = onFinish }

    var body: some View {
        // PLACEHOLDER(W-QUICK)
        AAEmptyState(title: "Trash — not yet implemented", symbol: "trash", message: "PLACEHOLDER(W-QUICK)")
            .frame(width: 640, height: 420)
            .aaSheet(.closeType)
    }
}
