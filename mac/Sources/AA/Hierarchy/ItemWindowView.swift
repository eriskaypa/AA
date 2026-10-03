// PLACEHOLDER(W-HIER) — contract: ARCHITECTURE.md §7.7
// Spec: 04 HIER-110…117 (item windows). Compiling stub created by F3; W-HIER replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct ItemWindowView: View {
    let itemID: UUID

    init(itemID: UUID) { self.itemID = itemID }

    var body: some View {
        // PLACEHOLDER(W-HIER)
        AAEmptyState(title: "Item window — not yet implemented", symbol: "macwindow", message: "PLACEHOLDER(W-HIER)")
    }
}
