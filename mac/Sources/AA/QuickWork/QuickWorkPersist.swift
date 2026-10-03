// Spec: 08 QUICK-213 (safe mode: `save()` is a no-op, memory only), QUICK-214 (a failed save is caught and shown;
//       the app keeps running and the data stays dirty for the next attempt), 02 REPO-003 / REPO-008 (Save /
//       FlushIfDirty); ARCHITECTURE.md §9.1 (errors → alert with the spec's title).
import AppKit
import SwiftUI
import AACore

/// The "Save" / "MarkDirty + FlushIfDirty" calls of every W-QUICK window, with the Mac error handling of QUICK-214.
@MainActor enum QuickWorkPersist {
    /// `AppRepository.Save()`: a confirmed write. On failure the store stays dirty (the debounce retries) and the
    /// error is shown on the window that triggered it.
    static func save(_ env: AppEnvironment, dialogs: DialogPresenter) {
        do {
            try env.store.save()
        } catch {
            report(error, env: env, dialogs: dialogs)
        }
    }

    /// `MarkDirty(); FlushIfDirty()` — persist this change now.
    static func flush(_ env: AppEnvironment, dialogs: DialogPresenter) {
        env.store.markDirty()
        do {
            try env.store.flushIfDirty()
        } catch {
            report(error, env: env, dialogs: dialogs)
        }
    }

    private static func report(_ error: Error, env: AppEnvironment, dialogs: DialogPresenter) {
        env.store.markDirty()
        let message = error.localizedDescription
        let target = dialogs === DialogPresenter.unbound ? env.mainDialogs : dialogs
        Task { @MainActor in await target.error(ShellStatusText.saveFailedTitle, message) }
    }
}
