// PLACEHOLDER(W-PERSIST) — contract: ARCHITECTURE.md §7.7
// Spec: 01 DATA-172 (instance alerts). Compiling stub created by F3; W-PERSIST replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

enum InstanceAlertChoice { case switchToRunning, openReadOnly, quit, takeOver }

@MainActor enum InstanceAlerts {
    static func presentBlocked(_ r: InstanceGuardResult, appFolder: URL) -> InstanceAlertChoice {
        // PLACEHOLDER(W-PERSIST)
        .quit
    }
}
