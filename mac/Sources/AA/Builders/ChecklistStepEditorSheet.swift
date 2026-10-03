// PLACEHOLDER(W-BUILD) — contract: ARCHITECTURE.md §7.7
// Spec: 06 §E (checklist step editor). Compiling stub created by F3; W-BUILD replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct ChecklistStepEditorSheet: View {
    let stepID: UUID?
    let detachedStep: ChecklistStep?
    let onCommit: ((ChecklistStep) -> Void)?

    init(stepID: UUID) { self.stepID = stepID; detachedStep = nil; onCommit = nil }

    /// Internal overload for detached template steps (06 BUILD-063).
    init(step: ChecklistStep, onCommit: @escaping (ChecklistStep) -> Void) {
        stepID = nil; detachedStep = step; self.onCommit = onCommit
    }

    var body: some View {
        // PLACEHOLDER(W-BUILD)
        AAEmptyState(title: "Step editor — not yet implemented", symbol: "pencil", message: "PLACEHOLDER(W-BUILD)")
    }
}
