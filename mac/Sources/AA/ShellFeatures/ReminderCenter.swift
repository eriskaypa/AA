// PLACEHOLDER(W-SHELL) — contract: ARCHITECTURE.md §7.7
// Spec: 03 SHELL-130…133, §9.3 (reminders, digest, Dock badge). Compiling stub created by F3; W-SHELL replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

enum DigestReason { case launch, timer, dayChanged, wake }

@MainActor final class ReminderCenter {
    static let shared = ReminderCenter()

    func start(env: AppEnvironment) {
        // PLACEHOLDER(W-SHELL)
    }

    func stop() {
        // PLACEHOLDER(W-SHELL)
    }

    func runDigest(reason: DigestReason) {
        // PLACEHOLDER(W-SHELL)
    }
}
