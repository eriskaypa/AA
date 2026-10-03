// PLACEHOLDER(W-SHELL) — contract: ARCHITECTURE.md §7.7
// Spec: 03 SHELL-205, BD.3.12 (--smoke-test). Compiling stub created by F3; W-SHELL replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

enum SmokeTest {
    /// Non-zero = refused (AAMain exits with it); 0 = the harness is armed and the launch continues.
    @MainActor static func run(options: LaunchOptions) -> Int32 {
        // PLACEHOLDER(W-SHELL)
        0
    }
}
