// PLACEHOLDER(W-BUILD) — contract: ARCHITECTURE.md §7.7
// Spec: 06 §A–§C (checklist builder). Compiling stub created by F3; W-BUILD replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

enum ChecklistBuilderHost: Hashable { case procedure(UUID), crew(UUID), savedList(UUID) }

struct ChecklistBuilderView: View {
    let host: ChecklistBuilderHost

    init(host: ChecklistBuilderHost) { self.host = host }

    var body: some View {
        // PLACEHOLDER(W-BUILD)
        AAEmptyState(title: "Checklist builder — not yet implemented", symbol: "hammer", message: "PLACEHOLDER(W-BUILD)")
    }
}

struct ChecklistBuilderSheet: View {
    let host: ChecklistBuilderHost

    init(host: ChecklistBuilderHost) { self.host = host }

    var body: some View {
        // PLACEHOLDER(W-BUILD)
        AAEmptyState(title: "Checklist builder — not yet implemented", symbol: "hammer", message: "PLACEHOLDER(W-BUILD)")
    }
}
