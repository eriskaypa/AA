// Spec: 01 §6.6 (a Windows live link that cannot be opened: "Windows path — not available on this Mac" with
//       "Locate…" which stores a Mac-side mapping), 05 §6.9 (UNC → /Volumes/share → mount smb://server/share and retry;
//       unmapped drive letters point to Settings ▸ File Links), OC-12 (missing file message shows the resolved path),
//       DECISIONS 10 Q4; ARCHITECTURE.md §9.4. Additive helper for every owner that opens attachments (W-FILES,
//       W-VESSEL, W-HIER viewers): the whole open-with-recovery flow on top of `AttachmentOpener`.
import AppKit
import SwiftUI
import AACore

@MainActor enum PersistOpenFlow {
    /// Opens a stored attachment/link and handles every failure with the matching dialog. Returns the final outcome.
    @discardableResult
    static func open(stored: String, isLink: Bool, env: AppEnvironment, dialogs: DialogPresenter) async -> OpenOutcome {
        await run(stored: stored, isLink: isLink, env: env, dialogs: dialogs) {
            AttachmentOpener.open(stored: stored, isLink: isLink, dataStore: env.dataStore)
        }
    }

    /// "Open containing folder" / Show in Finder with the same recovery.
    @discardableResult
    static func reveal(stored: String, env: AppEnvironment, dialogs: DialogPresenter) async -> OpenOutcome {
        await run(stored: stored, isLink: false, env: env, dialogs: dialogs) {
            AttachmentOpener.revealInFinder(stored: stored, dataStore: env.dataStore)
        }
    }

    private static func run(stored: String, isLink: Bool, env: AppEnvironment, dialogs: DialogPresenter,
                            attempt: () -> OpenOutcome) async -> OpenOutcome {
        let outcome = attempt()
        switch outcome {
        case .opened:
            return outcome
        case .notFound(let path):
            await dialogs.warning("File not found", PersistOpenerText.missing(path))
            return outcome
        case .failed(let message):
            await dialogs.error("Could not open", message)
            return outcome
        case .windowsPathUnmapped(let windowsPath):
            guard await recover(windowsPath, env: env, dialogs: dialogs) else { return outcome }
            let retry = attempt()
            if case .notFound(let path) = retry { await dialogs.warning("File not found", PersistOpenerText.missing(path)) }
            return retry
        }
    }

    /// The unmapped-Windows-path alert: Locate… (stores a mapping), Connect to Server… (UNC), File Links Settings, Cancel.
    /// True when a retry makes sense.
    private static func recover(_ windowsPath: String, env: AppEnvironment, dialogs: DialogPresenter) async -> Bool {
        let share = PathMapper.smbShareURL(forUNC: windowsPath)
        var buttons = [AlertButton(title: "Locate…", role: .default)]
        if share != nil { buttons.append(AlertButton(title: "Connect to Server…")) }
        buttons.append(AlertButton(title: "File Links Settings…"))
        buttons.append(AlertButton(title: "Cancel", role: .cancel))
        let spec = AlertSpec(title: "Windows path — not available on this Mac",
                             message: "\(windowsPath)\n\n\(PersistOpenerText.unmapped(windowsPath))",
                             style: .informational, buttons: buttons)
        let picked = await dialogs.alert(spec)
        guard picked >= 0, picked < buttons.count else { return false }
        switch buttons[picked].title {
        case "Locate…":
            let urls = await dialogs.openPanel(OpenPanelConfig(message: "Locate “\(leaf(windowsPath))” on this Mac",
                                                               canChooseFiles: true, canChooseDirectories: true))
            guard let chosen = urls.first, let m = PathMapper.inferredMapping(windowsPath: windowsPath, chosen: chosen) else {
                return false
            }
            PathMapper.shared.upsert(m)
            env.status.post("Mapped \(m.windowsPrefix) to \(m.macPath) on this Mac.")
            return true
        case "Connect to Server…":
            guard let share else { return false }
            NSWorkspace.shared.open(share)                    // Finder mounts it under /Volumes; the user retries
            return false
        case "File Links Settings…":
            env.open(.settings(tab: .fileLinks))
            return false
        default:
            return false
        }
    }

    private static func leaf(_ windowsPath: String) -> String {
        windowsPath.replacingOccurrences(of: "/", with: "\\").split(separator: "\\").last.map(String.init) ?? windowsPath
    }
}
