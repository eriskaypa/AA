// Spec: 03 SHELL-056 (close/exit pipeline), SHELL-505 (⌘Q deferred by a decision sheet, close-type sheets close first),
//       SHELL-513 (⌘W on main = quit), SHELL-054 (flush + close item windows first), 01 DATA-028, DECISIONS 03 Q-5
//       (failed final save → Retry / Quit Anyway / Cancel); ARCHITECTURE.md §5.4 (quit row).
import AppKit
import AACore

@MainActor
enum ShellQuitPipeline {
    /// `applicationShouldTerminate` — runs the whole pipeline synchronously (bounded by the 15 s save timeout).
    static func shouldTerminate(env: AppEnvironment?) -> NSApplication.TerminateReply {
        let coordinator = LaunchCoordinator.shared
        guard coordinator.phase == .main, let env else { return .terminateNow }

        // SHELL-505: a decision sheet or an alert refuses ⌘Q (beep, bring it front).
        if NSApp.modalWindow != nil {
            NSSound.beep()
            return .terminateCancel
        }
        for w in NSApp.windows {
            guard let sheet = w.attachedSheet else { continue }
            let kind = SceneOpener.shared.sheetInfo(of: sheet)?.kind ?? .decision
            if kind == .decision {
                sheet.makeKeyAndOrderFront(nil)
                NSSound.beep()
                return .terminateCancel
            }
        }

        // 1–2. Stop shared sync, reminders, timers and the DATA-180 watcher so our own final write cannot trigger a
        //      reload (REQ-W-PERSIST-01).
        env.sharedSave.stop()
        ReminderCenter.shared.stop()
        env.stopAutosaveTimer()
        env.dataFileGuard?.stop()

        // 3. Safe mode / read-only instance: nothing is written or pushed.
        if env.isSafeMode || env.isReadOnlyInstance || !env.mainLoaded {
            InstanceGuard.releaseExternal()
            return .terminateNow
        }

        // 4. Close-type sheets (builders, Trash) save by flushing; item windows flush and close first.
        env.flushAllEditors()
        for w in SceneOpener.shared.itemWindows { w.close() }

        // 5. Flush, capture, final save (DECISIONS 03 Q-5: Retry / Quit Anyway / Cancel on failure).
        env.flushAllEditors()
        env.captureUiState()
        while true {
            do {
                try env.store.save()
                break
            } catch {
                switch askAfterFailedSave(error.localizedDescription) {
                case .retry: continue
                case .quitAnyway: break
                case .cancel:
                    resumeAfterCancelledQuit(env)
                    return .terminateCancel
                }
                break
            }
        }

        // 6. The conditional shared push (DATA-055 rule, W-PERSIST), then wait for queued writes.
        env.sharedSave.pushOnCloseIfNeeded()
        _ = env.store.waitForQueuedWrites(timeout: AppStore.saveTimeout)
        InstanceGuard.releaseExternal()
        return .terminateNow
    }

    enum FailedSaveChoice { case retry, quitAnyway, cancel }

    static func askAfterFailedSave(_ message: String) -> FailedSaveChoice {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = ShellStatusText.quitSaveFailedTitle
        alert.informativeText = ShellStatusText.quitSaveFailedMessage(message)
        alert.addButton(withTitle: "Retry")
        let quit = alert.addButton(withTitle: "Quit Anyway")
        quit.hasDestructiveAction = true
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .retry
        case .alertSecondButtonReturn: return .quitAnyway
        default: return .cancel
        }
    }

    /// The user cancelled a quit after a failed save: restart what step 1 stopped.
    static func resumeAfterCancelledQuit(_ env: AppEnvironment) {
        env.sharedSave.start()
        env.startAutosaveTimer()
        if !env.isSafeMode, !env.isReadOnlyInstance, env.dataFileGuard?.state.mode == .normal { env.dataFileGuard?.start() }
        if !env.isSafeMode, !env.isReadOnlyInstance { ReminderCenter.shared.start(env: env) }
        env.showMainWindow()
    }
}
