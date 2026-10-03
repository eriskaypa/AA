// PLACEHOLDER(W-QUICK) — contract: ARCHITECTURE.md §7.7
// Spec: 08 §2.7 (Review changes before importing). Compiling stub created by F3; W-QUICK replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct ReviewChangesSheet: View {
    let request: ReviewChangesRequest
    let finish: (Bool) -> Void

    init(request: ReviewChangesRequest, finish: @escaping (Bool) -> Void) { self.request = request; self.finish = finish }

    var body: some View {
        // PLACEHOLDER(W-QUICK)
        VStack(spacing: 12) {
            AAEmptyState(title: "Review changes — not yet implemented", symbol: "arrow.left.arrow.right",
                         message: "PLACEHOLDER(W-QUICK)")
            HStack {
                Spacer()
                Button("Cancel") { finish(false) }.keyboardShortcut(.cancelAction)
                Button("Import (Overwrite)") { finish(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 760, height: 520)
        .aaSheet(.decision)
    }
}
