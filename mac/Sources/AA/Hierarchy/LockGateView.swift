// PLACEHOLDER(W-HIER) — contract: ARCHITECTURE.md §7.7
// Spec: 04 §6.4, HIER-050…058 (lock gate, item lock sheet). Compiling stub created by F3; W-HIER replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct LockGateView: View {
    let itemID: UUID

    init(itemID: UUID) { self.itemID = itemID }

    var body: some View {
        // PLACEHOLDER(W-HIER)
        AAEmptyState(title: "Lock gate — not yet implemented", symbol: "lock", message: "PLACEHOLDER(W-HIER)")
    }
}

struct ItemLockSheet: View {
    let itemID: UUID

    init(itemID: UUID) { self.itemID = itemID }

    var body: some View {
        // PLACEHOLDER(W-HIER)
        AAEmptyState(title: "Item lock — not yet implemented", symbol: "lock", message: "PLACEHOLDER(W-HIER)")
    }
}
