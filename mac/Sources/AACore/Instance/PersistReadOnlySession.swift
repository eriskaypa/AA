// Spec: 01 DATA-174 (read-only instance: live view of the editor's saves, texts), DATA-175 (5 s upgrade poll, keep the
//       lock, "Edit Here" / "Stay Read-Only"), DATA-184 (shared-with-Windows evidence and its once-per-folder banner),
//       §MP.3.5 (write gate texts), §MP.3.7 (constants), MP.7.4 R-1…R-4, MP.7.9; DATA-177 / MP.7.3 L-1 (lease lost).
import Foundation
import Observation

/// Texts of the read-only instance mode (exact, DATA-172…175).
public enum PersistReadOnlyText {
    public static let banner = "Read-only — another copy of AA is editing this data folder. Changes here are not saved."
    public static let canEditBanner = "The other copy of AA has closed. You can edit here now."
    public static let switchToOther = "Switch to Other AA", editHere = "Edit Here", stayReadOnly = "Stay Read-Only"
    public static let discardTitle = "Discard the changes you made in this read-only window and start editing the saved data?"
    public static let discardAndEdit = "Discard and Edit"
    public static func nowEditing(_ dataFile: String) -> String { "Now editing — \(dataFile)" }
    public static func updated(_ hms: String) -> String { "Updated from the other copy of AA (\(hms))." }
    public static let saveTitle = "Read-only — not saving"
    public static let saveMessage = "This copy of AA opened read-only because another copy is editing the same data folder. Nothing you change here is saved. Switch to the other copy to make changes."
    public static let settingsSuffix = " (this window only — read-only)"
    public static let disabledHelp = "Not available in a read-only copy of AA."
    public static let windowSubtitle = "Read-Only"
    public static let leaseLostTitle = "Another copy of AA took over this data folder"
    public static func leaseLostMessage(host: String) -> String {
        "While this Mac was asleep, the copy of AA on “\(host)” took over editing. This copy is now read-only so neither overwrites the other."
    }
    public static let takeOverTitle = "Take over this data folder?"
    public static func takeOverMessage(host: String) -> String {
        "Only do this if you are sure the copy of AA on “\(host)” is no longer running. If it is still running, both copies will overwrite each other's changes."
    }
    public static let externalBusySheet = "That file is already open in another copy of AA."
}

/// The read-only instance's background work: the upgrade poll and the live view of the editor's saves.
@MainActor @Observable public final class PersistReadOnlySession {
    public enum Phase: Sendable, Equatable { case readOnly, canEdit }
    public private(set) var phase: Phase = .readOnly
    public private(set) var isRunning = false
    /// "Stay Read-Only" was chosen: the upgrade poll pauses until the live view sees another editor save (then the
    /// next time that editor quits, "Edit Here" is offered again). Without the pause the poll would take the freed
    /// lock back within 5 s and show the same banner again.
    public private(set) var upgradeDeclined = false

    @ObservationIgnored private let dataFile: () -> URL
    @ObservationIgnored private let tryUpgrade: () -> Bool
    @ObservationIgnored private let onSaveSeen: @MainActor () -> Void
    @ObservationIgnored private let table = PersistFingerprintTable()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: PersistDirectoryWatcher?

    @ObservationIgnored var upgradeInterval: Duration = .seconds(PersistLockConstants.upgradePoll)
    @ObservationIgnored var watchDebounce: Duration = .milliseconds(1500)
    @ObservationIgnored var watchPoll: Duration = .seconds(60)

    /// `dataFile` = the active data file; `tryUpgrade` = one non-blocking lock attempt (DATA-175);
    /// `onSaveSeen` = the editor saved (reload silently and post `updated`).
    public init(dataFile: @escaping () -> URL, tryUpgrade: @escaping () -> Bool, onSaveSeen: @escaping @MainActor () -> Void) {
        self.dataFile = dataFile; self.tryUpgrade = tryUpgrade; self.onSaveSeen = onSaveSeen
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        rememberDisk()
        let every = upgradeInterval
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: every)
                guard !Task.isCancelled, let self, self.isRunning else { return }
                self.pollOnce()
            }
        }
        let w = PersistDirectoryWatcher(directory: dataFile().deletingLastPathComponent(), debounce: watchDebounce,
                                        poll: watchPoll) { [weak self] in self?.checkDisk() }
        watcher = w
        w.start()
    }

    public func stop() {
        isRunning = false
        pollTask?.cancel(); pollTask = nil
        watcher?.stop(); watcher = nil
    }

    /// One upgrade attempt (the 5 s poll body).
    public func pollOnce() {
        guard phase == .readOnly, !upgradeDeclined else { return }
        if tryUpgrade() { phase = .canEdit }
    }

    /// "Stay Read-Only": the caller hands the lock back; upgrade attempts pause until another editor is seen saving.
    public func stayReadOnly() {
        phase = .readOnly
        upgradeDeclined = true
    }

    /// Records the data file as currently on disk (after a reload).
    public func rememberDisk() {
        let url = dataFile()
        if let d = try? Data(contentsOf: url) { table.record(url, bytes: d) } else { table.acceptCurrent(url) }
    }

    /// Live view: when the editor replaced the file, reload (the callback) and remember the new version.
    public func checkDisk() {
        let url = dataFile()
        guard table.check(url) != .ok else { return }
        table.acceptCurrent(url)
        upgradeDeclined = false                                   // another editor is at work: offer again later
        onSaveSeen()
    }
}

/// DATA-177 (MP.7.3 L-1): what a lease-mode editor does to its own model when another computer took the folder over.
@MainActor public enum PersistLeaseLoss {
    /// Keeps unsaved changes as a `-mine` conflict copy (only when there are any — DATA-181), then closes every write
    /// path of this process: repository saving is suspended and settings become memory-only (read-only instance mode,
    /// DATA-174). Returns the conflict copy's file name, if one was written.
    @discardableResult
    public static func enterReadOnly(_ store: AppStore, hasUnsavedChanges: Bool) -> String? {
        var name: String?
        if hasUnsavedChanges { name = try? ConflictCopies.saveMine(store) }
        store.suspendSaving = true
        store.dataStore.settings.isWriteGated = true
        return name
    }
}

/// DATA-184: a data folder that also seems to be used by AA on Windows.
@MainActor public enum PersistWindowsEvidence {
    public static let message = "This data folder also seems to be used by AA on Windows. Two copies of AA must not edit one data folder — they overwrite each other's changes. Give each computer its own data folder and connect them with a shared save file (File ▸ Shared Save File ▸ Set…)."
    public static let showMeHow = "Show Me How", dontShowAgain = "Don't Show Again"
    public static let helpAnchor = "shared-save-setup"

    /// `UserDefaults` key `AA.SharedWithWindowsWarned.<sha256hex of the canonical AppFolder>`.
    public static func warnedKey(_ appFolder: URL) -> MacPreferences.Key {
        MacPreferences.Key("AA.SharedWithWindowsWarned." + PersistHost.sha256Hex(Data(PersistHost.canonicalPath(appFolder).utf8)))
    }

    /// Any one piece of evidence is enough (MP.7.9).
    public static func detect(appFolder: URL, settings: AppSettings, foreignTempAtLaunch: Bool, outsideWriteSeen: Bool) -> Bool {
        if foreignTempAtLaunch || outsideWriteSeen { return true }
        let fm = FileManager.default
        if let h = FileHandle(forReadingAtPath: appFolder.appending(path: "data.json").path) {
            defer { try? h.close() }
            if let head = try? h.read(upToCount: LocalEncryption.windowsMagic.count), head == LocalEncryption.windowsMagic {
                return true
            }
        }
        let token = appFolder.appending(path: "google-token", directoryHint: .isDirectory)
        for f in (try? fm.contentsOfDirectory(at: token, includingPropertiesForKeys: nil)) ?? [] {
            if let h = FileHandle(forReadingAtPath: f.path) {
                defer { try? h.close() }
                if let head = try? h.read(upToCount: 8), head == Data("AADPAPI1".utf8) { return true }
            }
        }
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: appFolder.appending(path: "qrmodels").path, isDirectory: &isDir), isDir.boolValue { return true }
        for v in [settings.currentDataFile, settings.sharedSaveFile, settings.googleDriveFolder, settings.folderBuilderBase] {
            if let v, PathMapper.isWindowsPath(v) { return true }
        }
        return false
    }

    /// Evidence present and not dismissed for this folder.
    public static func shouldWarn(appFolder: URL, settings: AppSettings, foreignTempAtLaunch: Bool, outsideWriteSeen: Bool,
                                  prefs: MacPreferences = .shared) -> Bool {
        guard !prefs.bool(warnedKey(appFolder), default: false) else { return false }
        return detect(appFolder: appFolder, settings: settings, foreignTempAtLaunch: foreignTempAtLaunch,
                      outsideWriteSeen: outsideWriteSeen)
    }

    /// "Don't Show Again" (per canonical folder).
    public static func dismiss(appFolder: URL, prefs: MacPreferences = .shared) {
        prefs.set(true, warnedKey(appFolder))
    }
}
