// PLACEHOLDER(W-DRIVE) — contract: ARCHITECTURE.md §7.7
// Spec: 14 TOOLS-001…035, 03 SHELL-073…080. Compiling stub created by F3; W-DRIVE replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

@MainActor enum DriveActions {
    static func saveCopyToSyncedFolder(env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-DRIVE)
    }

    static func setDriveFolder(env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-DRIVE)
    }

    static func uploadBackup(env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-DRIVE)
    }

    static func loadBackup(env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-DRIVE)
    }

    static func setOAuthClient(env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-DRIVE)
    }

    static func signOut(env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-DRIVE)
    }

    static func toggleSyncOnSave(env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-DRIVE)
    }

    static func checkForNewer(env: AppEnvironment, dialogs: DialogPresenter) async {
        // PLACEHOLDER(W-DRIVE)
    }
}

struct DriveSettingsSection: View {
    var body: some View {
        // PLACEHOLDER(W-DRIVE)
        AAEmptyState(title: "Google Drive — not yet implemented", symbol: "externaldrive.badge.icloud", message: "PLACEHOLDER(W-DRIVE)")
    }
}
