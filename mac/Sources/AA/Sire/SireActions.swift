// PLACEHOLDER(W-SIRE) — contract: ARCHITECTURE.md §7.7
// Spec: 12 SIRE-036/038, 03 SHELL-099/100. Compiling stub created by F3; W-SIRE replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

@MainActor enum SireActions {
    static func showExportDialog(env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-SIRE)
    }

    static func setGeminiKey(env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-SIRE)
    }
}

struct GeminiKeySettingsSection: View {
    var body: some View {
        // PLACEHOLDER(W-SIRE)
        AAEmptyState(title: "Gemini API key — not yet implemented", symbol: "key", message: "PLACEHOLDER(W-SIRE)")
    }
}
