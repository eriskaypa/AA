// Spec: 03 SHELL-056 (close/exit pipeline), 01 DATA-028, DATA-174 (the read-only / no-write list), DATA-180 ("Stop
//       Editing Here": a deliberate no-write state), DECISIONS 03 Q-5 (the failed-save alert is for real failures);
//       01 DATA-021 (leaving safe mode by an import / reload), 03 SHELL-131 (the 30-min reminder timer).
import Foundation

/// Pure decisions of the quit pipeline (`ShellQuitPipeline`).
public enum ShellQuitPlan {
    /// Step 3: nothing is written or pushed — safe mode, a read-only instance, no data loaded yet, or editing stopped
    /// here (DATA-180; the store is paused, so a save would only throw `.writesPaused` and raise the Q-5 alert).
    public static func skipsFinalSave(safeMode: Bool, readOnlyInstance: Bool, mainLoaded: Bool,
                                      stoppedEditing: Bool) -> Bool {
        safeMode || readOnlyInstance || !mainLoaded || stoppedEditing
    }
}

/// Pure decisions of `AppEnvironment.loadDataAndInitUI` (03 SHELL-007, 01 DATA-020/021).
public enum ShellLoadPlan {
    /// A reload (Import from File…, Import Data Folder (ZIP)…, Reload from Disk, a shared pull) that leaves safe mode
    /// in an editor starts what the safe-mode launch skipped: the startup housekeeping (trash prune, recurrence
    /// reconcile) and the reminder centre (30-min reminders, digest, Dock badge, menu-bar counts). Windows starts its
    /// reminder timer at load regardless of safe mode, so reminders resume after an import there too.
    public static func startsSkippedServices(initial: Bool, wasSafeMode: Bool, isSafeMode: Bool,
                                             readOnlyInstance: Bool) -> Bool {
        !initial && wasSafeMode && !isSafeMode && !readOnlyInstance
    }
}
