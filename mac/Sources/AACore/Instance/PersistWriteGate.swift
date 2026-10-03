// Spec: 01 DATA-174 (a read-only instance MUST NOT create, change, rename or delete anything inside the data folder;
//       imports, adding attachments and Flash Sync are disabled with "Not available in a read-only copy of AA."),
//       §MP.3.5 (one write gate: `.readOnlyInstance` and `.externalConflict` apply the DATA-174 list), DATA-180 ("Stop
//       Editing Here"); Requests/W-PERSIST.md REQ-W-PERSIST-02 (the menu enablement is F3's — this is the service-level
//       backstop so no path can write while the gate is closed).
import Foundation

/// Thrown by W-PERSIST's writers into the data folder while the write gate is closed.
public enum PersistWriteGateError: Error, LocalizedError, Sendable, Equatable {
    case readOnly

    public var errorDescription: String? { PersistReadOnlyText.disabledHelp }
}

/// The write gate as W-PERSIST's services see it: `SettingsStore.isWriteGated` is set by F3 for a read-only instance
/// (DATA-174) and by `DataFileFingerprint` while editing is stopped (DATA-180); safe mode leaves it open (imports are
/// the safe-mode remedy, DATA-021).
@MainActor public enum PersistWriteGate {
    /// True when this process may write into the data folder.
    public static func canWriteDataFolder(_ ds: DataStore) -> Bool { !ds.settings.isWriteGated }

    /// Throws `PersistWriteGateError.readOnly` (before anything is touched) while the gate is closed.
    public static func check(_ ds: DataStore) throws {
        if !canWriteDataFolder(ds) { throw PersistWriteGateError.readOnly }
    }
}
