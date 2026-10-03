// Spec: 03 Appendix A.4 (status-line messages), A.3 (dialog texts owned by the shell: D1, D2, D4, D5, D10, D15, D26,
//       D35), §6.5.1.9 (Mac key renderings), SHELL-008/009/050/052, 01 DATA-021/022/026/027, REPO-009, 02 REPO-077.
import Foundation

/// Exact status-line and dialog strings the shell itself posts (times are local `HH:mm:ss`, en_US_POSIX).
public enum ShellStatusText {
    public static func hms(_ t: NetDateTime) -> String { t.format(.isoSecond).suffix(8).description }

    public static func loaded(_ path: String) -> String { "Loaded — \(path)" }
    public static let safeModeStatus = "⚠ Data file unreadable — read-only safe mode (not saving)."
    public static func reloaded(_ t: NetDateTime) -> String { "Reloaded \(hms(t))" }
    public static func saved(_ t: NetDateTime) -> String { "Saved \(hms(t))" }
    public static func autosaved(_ t: NetDateTime) -> String { "Autosaved \(hms(t))" }
    public static func autosaveNoChanges(_ t: NetDateTime) -> String { "Autosave — no changes (\(hms(t)))" }
    public static func autosaveFailed(_ message: String) -> String { "Autosave failed: \(message)" }
    public static let nothingToUndo = "Nothing to undo."
    public static func restored(_ n: Int) -> String {
        n > 1 ? "Restored \(n) deleted items (⌘Z)." : "Restored the last deleted item (⌘Z)."
    }
    public static let darkModeOn = "Dark mode on."
    public static let darkModeOff = "Dark mode off."
    public static let appliedFromIPhone = "Applied changes received from the iPhone"

    /// `AA — {identity}` (SHELL-020).
    public static func windowTitle(identity: String) -> String { "AA — \(identity)" }

    /// The main window subtitle's display form of a status message (V-DESIGN rule 3): an absolute path in it (from the
    /// first " /" or a leading "/" to the end) is shown with `~` for the home folder and middle-truncated to about
    /// `limit` characters. The message itself (status history, `.help`, SmokeTest's "Loaded — " prefix) is unchanged.
    public static func subtitleDisplay(_ message: String, home: String = NSHomeDirectory(), limit: Int = 60) -> String {
        let start: String.Index
        if message.hasPrefix("/") {
            start = message.startIndex
        } else if let r = message.range(of: " /") {
            start = message.index(after: r.lowerBound)
        } else {
            return message
        }
        var path = String(message[start...])
        let h = home.hasSuffix("/") ? String(home.dropLast()) : home
        if !h.isEmpty, path == h || path.hasPrefix(h + "/") { path = "~" + path.dropFirst(h.count) }
        if path.count > limit, limit > 8 {
            let tail = (limit - 1) * 3 / 5
            let head = limit - 1 - tail
            path = String(path.prefix(head)) + "…" + String(path.suffix(tail))
        }
        return String(message[..<start]) + path
    }

    // MARK: Dialogs owned by the shell (A.3)

    public static let safeModeTitle = "Data file unreadable — safe mode"                              // D1
    public static let safeModeMessage = "Your data file is present but could not be read — it may be locked by another program, still being written, corrupt, or (if you enabled local encryption) created under a different user account or on another computer (a file encrypted by AA on Windows can only be opened on that PC — export a bundle there and import it here).\n\nAA opened in READ-ONLY safe mode and will NOT save over it, so nothing already on disk is lost. Close AA, restore a copy if needed (File ▸ Trash or a backup), then reopen."
    /// D1 with the cause the load reported (01 §6.5, DECISIONS 01 DPAPI): a Windows-encrypted file or a missing Mac
    /// Keychain key leads with its own clear sentence, every other cause gets the generic text.
    public static func safeModeMessage(cause: DataLoadError?) -> String {
        switch cause {
        case .windowsEncrypted?, .macKeyUnavailable?:
            return (cause?.errorDescription ?? "") + "\n\n" + safeModeMessage
        default:
            return safeModeMessage
        }
    }
    /// The status line in safe mode, naming a Windows-encrypted file or a missing Keychain key.
    public static func safeModeStatus(cause: DataLoadError?) -> String {
        switch cause {
        case .windowsEncrypted?: return safeModeStatus + " The file was encrypted by AA on Windows."
        case .macKeyUnavailable?: return safeModeStatus + " The Keychain key for this Mac's encrypted file is unavailable."
        default: return safeModeStatus
        }
    }
    public static let newerFormatTitle = "Newer data format"                                          // D2
    public static func newerFormatMessage(version: Int, current: Int) -> String {
        "This data file was saved by a newer version of AA (format v\(version); this build understands v\(current)).\n\nYou can keep working — newer fields are preserved — but update AA on this Mac to avoid missing new features' data."
    }
    public static let safeModeSaveTitle = "Safe mode — not saving"                                    // D4
    public static let safeModeSaveMessage = "AA is in read-only safe mode because the data file couldn't be read at startup, so saving is disabled to protect the file on disk. Close and reopen AA once the file is available."
    public static let saveFailedTitle = "Save failed"                                                 // D5
    public static let confirmImportTitle = "Confirm import"                                           // D15
    public static func confirmImportMessage(sourceName: String) -> String {
        "Replace your current data with '\(sourceName)'?\n(Could not read a change preview for this source.)"
    }
    public static let aboutTitle = "About AA"                                                         // D26
    public static let aboutText = "Created by B.E.P. Avida - May 2026"

    /// DECISIONS 03 Q-5: a failed final save offers Retry / Quit Anyway / Cancel.
    public static let quitSaveFailedTitle = "Save failed"
    public static func quitSaveFailedMessage(_ error: String) -> String {
        "AA couldn't save your data before quitting:\n\n\(error)\n\nRetry the save, quit without saving the latest changes, or cancel and keep AA open."
    }
}
