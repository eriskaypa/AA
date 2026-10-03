// PLACEHOLDER(W-DRIVE) — contract: ARCHITECTURE.md §7.7
// Spec: 14 §2 (Drive sync), 03 SHELL-010/011/121/122. Compiling stub created by F3; W-DRIVE replaces this file in place (same path, same signatures).
// Stubs return benign defaults and never crash or write files (ARCH §11).
import AppKit
import SwiftUI
import AACore

enum DriveOperation: Hashable { case upload, load, check, push }

@MainActor @Observable final class DriveSyncCoordinator {
    private(set) var inFlight: Set<DriveOperation> = []
    @ObservationIgnored private weak var env: AppEnvironment?

    init() {}

    func attach(_ env: AppEnvironment) {
        // PLACEHOLDER(W-DRIVE)
        self.env = env
    }

    func queueSyncAfterExplicitSave() {
        // PLACEHOLDER(W-DRIVE)
    }

    func checkRemoteNewer(interactive: Bool) async {
        // PLACEHOLDER(W-DRIVE)
    }

    func startupChecks() async {
        // PLACEHOLDER(W-DRIVE)
    }
}
