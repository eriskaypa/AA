// PLACEHOLDER(W-SHELL) — contract: ARCHITECTURE.md §7.7
// Spec: 03 SHELL-061…072, 101, 102 (File / Tools flows), SHELL-185. Compiling stub created by F3; W-SHELL replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

@MainActor enum ShellFlows {
    static func perform(_ c: CommandID, env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-SHELL)
    }

    static func handles(_ c: CommandID) -> Bool {
        // PLACEHOLDER(W-SHELL)
        false
    }

    static func openDocuments(_ urls: [URL], env: AppEnvironment) async {
        // PLACEHOLDER(W-SHELL)
    }
}
