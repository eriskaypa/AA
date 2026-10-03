// PLACEHOLDER(W-PERSIST) — contract: ARCHITECTURE.md §7.7
// Spec: 01 DATA-180 (data-file conflict sheet). Compiling stub created by F3; W-PERSIST replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct DataFileConflictSheet: View {
    let conflict: DataFileConflict
    let finish: (DataFileConflictChoice) -> Void

    init(conflict: DataFileConflict, finish: @escaping (DataFileConflictChoice) -> Void) {
        self.conflict = conflict; self.finish = finish
    }

    var body: some View {
        // PLACEHOLDER(W-PERSIST)
        VStack(spacing: 12) {
            AAEmptyState(title: "Data file changed — not yet implemented", symbol: "exclamationmark.triangle",
                         message: "PLACEHOLDER(W-PERSIST)")
            Button("Keep Mine") { finish(.keepMine) }.keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(width: 520, height: 320)
        .aaSheet(.decision)
    }
}
