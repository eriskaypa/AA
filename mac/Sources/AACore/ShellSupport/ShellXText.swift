// Spec: 03 SHELL-061…072, 101, 102, 130…133, 185, 190, 196 (strings of the File / Tools flows, reminders and the
//       Mac launch sheets), 03 Appendix A.3 (dialogs D9–D13, D26, D28–D34), A.4 (status lines), §6.5 (Mac button
//       names), 01 DATA-012, 032…034, 040, 042, 043, 048, 050, 051, 070, 080, DATA-179 (import refusal sheet),
//       06 BUILD-145 B1, DECISIONS 01 Q-4/Q-5, 03 Q-7 (shared-save cadence text corrected), §6.5.1.9 (key renderings).
import Foundation

/// Every user-visible string of W-SHELL's flows, verbatim from the Windows build with the Mac renderings the specs
/// require ("PC" → "Mac" where the text names this machine, Mac verb buttons, "Finder"). Pure; no state.
public enum ShellXText {
    // MARK: Panels (SHELL-061, 063, 066, 070, 071)

    /// Save a Copy As JSON — default name (SHELL-061 / DATA-032).
    public static let saveCopyDefaultName = "aa-data.json"
    /// Set Shared Save File — default name (SHELL-066 / DATA-050).
    public static let sharedDefaultName = "aa-shared.zip"
    /// Set Shared Save File — the WPF dialog title, used as the panel message (03 §6.9).
    public static let sharedPanelMessage = "Choose the single shared save file (put it on a network drive or synced folder). It bundles your data AND attachments."

    /// Export Data Folder (ZIP) — `aa-data-{yyyyMMdd-HHmm}.zip`, local time (SHELL-070 / DATA-040).
    public static func exportDefaultName(_ now: NetDateTime, zone: TimeZone = .current) -> String {
        "aa-data-\(now.format(.stampMinute, zone: zone)).zip"
    }

    // MARK: Status lines (03 Appendix A.4)

    public static func exportedTo(_ path: String) -> String { "Exported to \(path)" }
    public static func exportedDataFolder(_ path: String) -> String { "Exported data folder to \(path)" }

    /// SHELL-071 / SHELL-185 / DATA-043.
    public static func importedBundle(fileName: String, dataOnly: Bool) -> String {
        dataOnly ? "Imported \(fileName) (text only — your attachments are untouched)"
                 : "Imported \(fileName) (with attachments)"
    }

    public static let textOnlyOn = "Exports carry text only (no attachments)"
    public static let textOnlyOff = "Exports carry everything, attachments included"
    public static func textOnlyStatus(_ on: Bool) -> String { on ? textOnlyOn : textOnlyOff }

    public static let encryptedOn = "Local data file is now encrypted at rest."
    public static let encryptedOff = "Local data file is now plaintext."
    public static func encryptionStatus(_ on: Bool) -> String { on ? encryptedOn : encryptedOff }

    public static func sharedSet(_ path: String) -> String { "Shared save file set — \(path)" }
    public static let sharedNone = "No shared save file is set."
    public static let sharedStopped = "Stopped using the shared save file (now saving locally)."
    /// Check Shared Save Now found nothing to reload (Mac addition, 01 §6.10).
    public static func sharedChecked(_ t: NetDateTime, zone: TimeZone = .current) -> String {
        "Checked the shared save file (\(t.format(.isoSecond, zone: zone).suffix(8)))."
    }

    public static func identitySet(_ identity: String) -> String { "App identity set: \(identity)" }
    /// 01 DATA-174 settings setters in a read-only copy: the normal status text plus
    /// `" (this window only — read-only)"` (REQ-W-PERSIST-02).
    public static func settingStatus(_ text: String, gated: Bool) -> String {
        gated ? text + PersistReadOnlyText.settingsSuffix : text
    }
    public static let passwordUpdated = "App password updated."
    public static let lockedNow = "Locked. Locked containers and entries will require re-unlocking."

    // MARK: Dialogs (03 Appendix A.3, §6.5 button names)

    public static let saveAsFailedTitle = "Save As failed"                                    // D9
    public static let confirmReloadTitle = "Confirm reload"                                   // D10
    public static let confirmReloadMessage = "Reload data from disk? Unsaved changes will be lost."
    public static let confirmReloadButton = "Reload"
    public static let importFailedTitle = "Import failed"                                     // D11
    public static let openFailedTitle = "Open failed"                                         // D12
    public static func openFolderFailedMessage(_ path: String) -> String {
        "Finder couldn't open the data folder:\n\n\(path)"
    }
    public static let exportFailedTitle = "Export failed"                                     // D13
    /// DATA-040: a destination inside AppFolder is refused with this message.
    public static let exportInsideAppFolder = "Choose a destination outside the AA data folder."

    public static let sharedSaveFileTitle = "Shared save file"                                // D28 / D29
    /// D28 with the Mac button names (03 §6.5: "Use Its Contents" / "Overwrite It" / "Cancel").
    public static func sharedExistsMessage(fileName: String) -> String {
        "'\(fileName)' already exists.\n\nUse ITS contents (data + attachments) as your data (Use Its Contents), or keep your current data and overwrite it (Overwrite It)?"
    }
    public static let sharedUseItsContents = "Use Its Contents"
    public static let sharedOverwriteIt = "Overwrite It"
    /// D29 — DECISIONS 03 Q-7 corrects "every 10 minutes" to the real cadence (W-2).
    public static func sharedSetInfo(path: String) -> String {
        "This copy of AA now saves to and syncs from:\n\n\(path)\n\nIt bundles your data AND all attachments, autosaves there every minute, and reloads automatically when another copy of AA updates it. Point every computer at this same file."
    }
    public static let setSharedFailedTitle = "Set shared save file failed"                    // D30
    public static let stopSharedTitle = "Stop shared save file"                               // D31
    public static let stopSharedMessage = "Stop using the shared save file and save locally on this Mac only from now on?\n(Your current data is kept.)"
    public static let stopSharedButton = "Stop Using Shared File"

    /// 03 §6.9 MAC-ADAPT: NSSavePanel always asks before replacing, so the Set flow first asks Join or Create.
    public static let sharedChoiceTitle = "Set Shared Save File"
    public static let sharedChoiceMessage = "Join a shared save file that another copy of AA already uses, or create a new one from your current data?\n\nThe shared file bundles your data AND attachments; put it on a network drive or a synced folder."
    public static let sharedJoinButton = "Join an Existing Shared Save File…"
    public static let sharedCreateButton = "Create a New Shared Save File…"

    public static let safeModeTitle = "Safe mode"                                             // D32
    public static let encryptInSafeMode = "Can't change encryption in read-only safe mode."
    public static let encryptTitle = "Encrypt local data file"                               // D33
    /// 01 §6.5 Mac wording (owner of the DATA-070 strings per DATA-202 A14), verbatim.
    public static let encryptConfirmMessage = "Encrypt this Mac's data file at rest with a key stored in your macOS Keychain (tied to your user account on this Mac)?\n\n• Only THIS Mac's local file is encrypted.\n• Shared-save bundles, ZIP exports and Google Drive backups stay portable plaintext, so syncing between computers still works.\n• It can only be read back under your user account on this Mac."
    public static let encryptButton = "Encrypt"
    public static let encryptFailedTitle = "Encrypt local data file failed"                   // D34

    /// SHELL-196 / Q-16 guard: the setting arrived from another computer and this Mac has no key yet.
    public static let encryptForeignMessage = "This data folder is set to be encrypted at rest, but that setting came from another computer. Encrypting it here means only this Mac can open it. Encrypt it on this Mac?"
    public static let keepPlaintextButton = "Keep Plaintext"

    // MARK: Identity (SHELL-068, DATA-048, BUILD-145 B1)

    public static let identityTitle = "App identity"                                          // P2
    public static let identityPrompt = "Name this installation (e.g. a vessel or operator). It is stamped into every shared save and Google Drive export so you can tell which machine/operator produced a save:"
    public static func identityHelp(defaultName: String) -> String {
        "Leave blank to use this Mac's name (\(defaultName))."
    }

    // MARK: Import from file (SHELL-063, DATA-034, DECISIONS 01 Q-5, DATA-179)

    public static let importPlacementTitle = "Import from File"
    public static func importPlacementMessage(fileName: String) -> String {
        "Copy “\(fileName)” into the AA data folder, or keep using the file where it is?\n\nCopy into AA Folder: AA saves to its own data file from now on; the original stays untouched.\nUse in Place: AA saves back into “\(fileName)” itself (as on Windows), so it must stay reachable."
    }
    public static let copyIntoFolderButton = "Copy into AA Folder"
    public static let useInPlaceButton = "Use in Place"
    /// DATA-179: another process holds the external-file lock at import.
    public static let externalFileInUse = "That file is already open in another copy of AA."

    // MARK: Password (SHELL-101, DATA-080)

    public static let passwordFailedTitle = "Password"

    // MARK: Translocation (SHELL-190 — Mac-only strings)

    public static let translocationTitle = "Move AA to Applications"
    public static let translocationMessage = "AA is running from a temporary, read-only location that macOS uses for apps opened straight from a download.\n\nQuit AA, drag it into your Applications folder, and open it from there. Your data is not affected."

    // MARK: Reminders (SHELL-131, REPO-112)

    public static let reminderTitle = "AA — due soon"
    public static let showDueDates = "Show Due Dates…"
    public static let showAA = "Show AA"
}
