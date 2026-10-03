// Spec: 14 TOOLS-002/003/007/011/014/015/020/023/027/030/031/033 (every status string and message box of the Drive
//       family, exact), 03 SHELL-010 (D3), SHELL-073…080 (D6/D8/D16/D18/D20/D21/D23/D25). `▸` = U+25B8, `…` = U+2026,
//       `—` = U+2014, `“ ”` = U+201C/U+201D, `•` = U+2022.
import Foundation

public enum DriveText {
    // MARK: Status line (TOOLS-033)

    public static let syncing = "Syncing to Google Drive\u{2026}"
    public static func synced(_ hms: String) -> String { "Synced to Google Drive \(hms)" }
    public static func syncFailed(_ msg: String) -> String { "Drive sync failed: \(msg)" }
    public static let nothingOnDrive = "No AA save found on Google Drive yet."
    public static func upToDate(_ hms: String) -> String { "Google Drive is up to date (\(hms))." }
    public static func newerFound(identity: String?) -> String {
        let who = NetText.isBlank(identity) ? "" : " from \u{201C}\(identity!)\u{201D}"
        return "Newer save on Google Drive\(who) \u{2014} downloading to preview\u{2026}"
    }
    public static let keptLocal = "Kept local version (Drive has a newer one)."
    public static let loadedNewerDataOnly = "Loaded newer save from Google Drive (text only \u{2014} attachments unchanged)."
    public static let loadedNewerWithAttachments = "Loaded newer save from Google Drive (with attachments)."
    public static func checkFailed(_ msg: String) -> String { "Drive check failed: \(msg)" }
    public static let syncOn = "Google Drive sync on save: ON"
    public static let syncOff = "Google Drive sync on save: OFF"
    public static func savedCopy(_ path: String) -> String { "Saved a copy to Google Drive: \(path)" }
    public static func folderSet(_ path: String) -> String { "Google Drive folder set: \(path)" }
    public static let clientSet = "Google OAuth client set."
    public static let uploading = "Signing in to Google and uploading\u{2026} (a browser window may open)"
    public static func uploaded(_ name: String) -> String { "Uploaded to Google Drive: \(name)" }
    public static let uploadFailedStatus = "Google Drive upload failed."
    public static let listing = "Signing in to Google and listing backups\u{2026} (a browser window may open)"
    public static let noBackupsStatus = "No backups found on Google Drive."
    public static func downloading(_ name: String) -> String { "Downloading \(name)\u{2026}" }
    public static let loadCancelled = "Load from Google Drive cancelled."
    public static func loadedBackup(_ name: String, dataOnly: Bool) -> String {
        "Loaded backup from Google Drive: \(name)" + (dataOnly ? " (text only \u{2014} attachments unchanged)." : " (with attachments).")
    }
    public static let loadFailedStatus = "Load from Google Drive failed."
    public static let signedOut = "Signed out of Google (OAuth token cleared)."
    /// 14 §6.3 (Mac addition: the waiting sheet's Cancel).
    public static let signInCancelled = "Google sign-in cancelled."

    // MARK: Message boxes (title, text)

    public static let savedToDriveTitle = "Saved to Google Drive"
    public static func savedToDriveMessage(_ zip: String) -> String {
        "A backup was saved to your Google Drive folder:\n\n\(zip)\n\nGoogle Drive for desktop will sync it to the cloud."
    }
    public static let saveToDriveFailedTitle = "Save to Google Drive failed"

    public static let locateTitle = "Locate Google Drive"
    public static let locateForced = "Select your Google Drive folder \u{2014} the local folder that Google Drive for desktop syncs."
    public static let locateNotFound = "Couldn't find your Google Drive folder automatically. Please locate the local folder that Google Drive for desktop syncs."
    public static let folderPickerMessage = "Select your Google Drive folder"

    public static let clientPickerMessage = "Select the OAuth client_secret.json downloaded from Google Cloud Console"
    public static let oauthTitle = "Google OAuth"
    public static let clientSavedMessage = "Google OAuth client saved.\n\nMake sure in Google Cloud Console you have:\n  \u{2022} Enabled the Google Drive API\n  \u{2022} Created an OAuth client of type 'Desktop app'\n  \u{2022} Added your Google account as a test user (if the consent screen is in Testing)\n\nNow use File \u{25B8} 'Upload backup to Google Drive (OAuth)...'."
    public static let setClientFailedTitle = "Set OAuth client failed"
    public static let notConfiguredQuestion = "No Google OAuth client is configured yet. Choose your client_secret.json now?"

    public static let uploadedTitle = "Uploaded to Google Drive"
    public static func uploadedMessage(name: String, link: String?) -> String {
        "Uploaded '\(name)' to your Google Drive (folder 'AA Backups')." + (NetText.isBlank(link) ? "" : "\n\n\(link!)")
    }
    public static let uploadFailedTitle = "Google Drive upload failed"

    public static let loadTitle = "Load from Google Drive"
    public static let noBackupsMessage = "No backups were found in your Google Drive 'AA Backups' folder.\n\nUpload one first with File \u{25B8} 'Upload backup to Google Drive (OAuth)...'."
    public static let pickerPrompt = "Choose a backup to load from Google Drive (newest first)"
    public static let loadFailedTitle = "Load from Google Drive failed"

    public static let syncTitle = "Google Drive sync"
    public static let syncOnNotConfigured = "Sync is on. Set your Google OAuth client via File \u{25B8} 'Set Google OAuth client...' so saves can reach Drive."
    public static let checkNotConfigured = "Turn on 'Sync to Google Drive on save' and set a Google OAuth client first."
    public static let checkFailedTitle = "Drive sync check failed"

    public static let reconsentTitle = "Google Drive \u{2014} one more sign-in needed"
    public static let reconsentMessage = "AA can now find your backups anywhere in Google Drive \u{2014} including files you put there by hand, that Google Drive for desktop synced in, or that the iPhone app uploaded. Previously it could only see files AA itself created.\n\nThat needs broader permission than your existing sign-in granted, so the next Drive action will ask you to sign in to Google once more. AA asks for read access to your Drive plus write access only to its own files \u{2014} it cannot change or delete anything it did not create."

    // MARK: Review sources (TOOLS-027)

    public static let newerSaveSource = "Google Drive (newer save)"
    public static func backupSource(_ name: String) -> String { "Google Drive: \(name)" }

    // MARK: Sign-in sheet (14 §6.3, Mac addition)

    public static let waitingTitle = "Waiting for Google sign-in in your browser\u{2026}"
    public static let waitingMessage = "Finish signing in to Google in the browser window that just opened. AA asks for read access to your Drive plus write access only to the files it creates."
}
