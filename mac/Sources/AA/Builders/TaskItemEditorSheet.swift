// PLACEHOLDER(W-BUILD) — contract: ARCHITECTURE.md §7.7
// Spec: 06 §F (subtask / task editor). Compiling stub created by F3; W-BUILD replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct TaskItemEditorSheet: View {
    let taskID: UUID

    init(taskID: UUID) { self.taskID = taskID }

    var body: some View {
        // PLACEHOLDER(W-BUILD)
        AAEmptyState(title: "Task editor — not yet implemented", symbol: "pencil", message: "PLACEHOLDER(W-BUILD)")
    }
}
