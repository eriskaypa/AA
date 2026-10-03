// PLACEHOLDER(W-SHELL) — contract: ARCHITECTURE.md §7.7
// Spec: 03 §6.8, DECISIONS Q-13 (MenuBarExtra). Compiling stub created by F3; W-SHELL replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

struct MenuBarExtraContent: View {
    var body: some View {
        // PLACEHOLDER(W-SHELL)
        Button("Show AA") { LaunchCoordinator.shared.env?.showMainWindow() }
    }
}
