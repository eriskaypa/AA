// PLACEHOLDER(W-PERSIST) — contract: ARCHITECTURE.md §6.6
// Spec: 01 §E, §3.12, §6.9; 03 SHELL-023, SHELL-123…126. Compiling stub created by F1; W-PERSIST replaces this
// file in place. The stub stays `.off`, never syncs and writes nothing (ARCH §11).
import Foundation
import Observation

/// Implemented by F3's AppEnvironment.
@MainActor public protocol SharedSaveHost: AnyObject {
    func flushAllEditors()
    func captureUiState()
    /// D27: "Reload (Discard My Changes)" / "Keep Mine".
    func confirmReloadDiscardingChanges() async -> Bool
    /// LoadDataAndInitUi + status "Reloaded the shared save…".
    func reloadAfterSharedImport(identity: String?)
    func postStatus(_ text: String)
}

@MainActor @Observable public final class SharedSaveCoordinator {
    nonisolated public enum Health: Sendable, Equatable {
        case off, online(lastSync: Date?), offline(since: Date), notSaving(since: Date)
    }

    @ObservationIgnored private let store: AppStore
    @ObservationIgnored public weak var host: SharedSaveHost?
    public private(set) var health: Health = .off
    public private(set) var lastSeen: NetDateTime?
    public private(set) var lastSynced: NetDateTime?

    public init(store: AppStore) {
        self.store = store
    }

    /// SHELL-023 exact texts.
    public var indicatorText: String {
        // PLACEHOLDER(W-PERSIST)
        ""
    }

    public var indicatorHelp: String {
        // PLACEHOLDER(W-PERSIST)
        ""
    }

    public func start() {
        // PLACEHOLDER(W-PERSIST)
        _ = store
    }

    public func stop() {
        // PLACEHOLDER(W-PERSIST)
    }

    public func checkForUpdate() async {
        // PLACEHOLDER(W-PERSIST)
    }

    /// Synchronous (menu / on close).
    public func push(label: String) throws {
        // PLACEHOLDER(W-PERSIST)
        throw PersistPlaceholderError.notAvailable
    }

    public func pushInBackground(label: String) {
        // PLACEHOLDER(W-PERSIST)
    }

    /// DATA-055 rule.
    public func pushOnCloseIfNeeded() {
        // PLACEHOLDER(W-PERSIST)
    }

    /// D28 outcomes (the menu flow is W-SHELL's).
    public func adoptSharedFile(_ url: URL, useItsContents: Bool) async throws {
        // PLACEHOLDER(W-PERSIST)
        throw PersistPlaceholderError.notAvailable
    }

    public func stopUsing() {
        // PLACEHOLDER(W-PERSIST)
    }
}
