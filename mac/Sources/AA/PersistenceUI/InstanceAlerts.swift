// Spec: 01 DATA-172 (application-modal second-launch alert, 1 s lock re-check in the .modalPanel run-loop mode, the
//       alert closes itself with NSApp.abortModal() when the lock comes free), DATA-173 (Switch to Running AA: forward the
//       launch documents, hand activation over), DATA-177 ("Take Over…" with the critical confirmation), DATA-179
//       (external-file variant); ARCHITECTURE.md §6.6, §7.7.
import AppKit
import SwiftUI
import AACore

enum InstanceAlertChoice { case switchToRunning, openReadOnly, quit, takeOver }

@MainActor enum InstanceAlerts {
    /// Shows the DATA-172 alert for a refused guard and returns the user's choice. `.takeOver` means this process now
    /// holds the lock (the user took over, or the other copy quit while the alert was up) and continues as the editor.
    static func presentBlocked(_ r: InstanceGuardResult, appFolder: URL) -> InstanceAlertChoice {
        let info = InstanceGuard.folderBlocked ?? InstanceGuard.externalBlocked
        let isExternal: Bool
        if case .externalFile = info?.target { isExternal = true } else { isExternal = false }
        while true {
            let text = PersistInstanceAlertText.make(info ?? fallbackInfo(r, appFolder: appFolder),
                                                     now: Date(), zone: .current)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = text.messageText
            alert.informativeText = text.informativeText
            for b in text.buttons {
                let button = alert.addButton(withTitle: b.rawValue)
                if b == .quit { button.keyEquivalent = "\u{1b}" }
                if b == .takeOver, text.buttons.first != .takeOver { button.hasDestructiveAction = true }
            }
            // Re-check the lock every second while the alert is up (DATA-172).
            let timer = Timer(timeInterval: PersistLockConstants.alertRecheck, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let free = isExternal ? InstanceGuard.retryExternalLock() : InstanceGuard.retryFolderLock()
                    if free { NSApp.abortModal() }
                }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            NSApp.activate()
            let response = alert.runModal()
            timer.invalidate()
            if response == .abort { return .takeOver }
            let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            guard index >= 0, index < text.buttons.count else { return .quit }
            switch text.buttons[index] {
            case .quit:
                return .quit
            case .openReadOnly:
                return .openReadOnly
            case .switchToRunning:
                if let pid = info?.localPid {
                    _ = InstanceGuard.forwardToRunningInstance(pid: pid, documents: LaunchCoordinator.shared.takePendingDocuments())
                }
                return .switchToRunning
            case .takeOver:
                if confirmTakeOver(host: info?.record?.host ?? ""), InstanceGuard.takeOver() { return .takeOver }
                // Cancelled (or the take-over failed): show the alert again.
            }
        }
    }

    /// The DATA-177 critical confirmation.
    static func confirmTakeOver(host: String) -> Bool {
        let a = NSAlert()
        a.alertStyle = .critical
        a.messageText = PersistReadOnlyText.takeOverTitle
        a.informativeText = PersistReadOnlyText.takeOverMessage(host: host)
        let take = a.addButton(withTitle: "Take Over")
        take.hasDestructiveAction = true
        let cancel = a.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        return a.runModal() == .alertFirstButtonReturn
    }

    /// When the guard kept no detail (should not happen): a holder-less folder alert.
    private static func fallbackInfo(_ r: InstanceGuardResult, appFolder: URL) -> PersistBlockedInfo {
        let holder: PersistHolder
        switch r {
        case .otherUser(let u) where !u.isEmpty: holder = .otherUser(u)
        case .sameUserNoApp(let pid): holder = .sameUserNoApp(pid: pid, started: nil)
        case let .remote(host, lastSeen, stale):
            holder = stale ? .otherHostStale(host: host, heartbeat: lastSeen) : .otherHostFresh(host: host, heartbeat: lastSeen)
        default: holder = .unknown
        }
        return PersistBlockedInfo(target: .folder(appFolder), record: nil, holder: holder, lease: false)
    }
}
