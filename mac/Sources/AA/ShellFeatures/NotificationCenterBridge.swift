// PLACEHOLDER(W-SHELL) — contract: ARCHITECTURE.md §7.7
// Spec: 03 §6.8, SHELL-199 (notifications). Compiling stub created by F3; W-SHELL replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

@MainActor enum NotificationCenterBridge {
    static var isAvailable: Bool {
        // PLACEHOLDER(W-SHELL)
        false
    }

    static func install(env: AppEnvironment) {
        // PLACEHOLDER(W-SHELL)
    }

    static func post(id: String, title: String, body: String, onClick: SceneRequest?) {
        // PLACEHOLDER(W-SHELL)
    }
}
