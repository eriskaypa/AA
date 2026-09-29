// Spec: 01 DATA-215 (Keychain registry), DATA-220 / OC-07 / OC-32 (identifiers, scene ids), 01 §6.7 (UTTypes);
//       ARCHITECTURE.md §6.1.
import Foundation
import UniformTypeIdentifiers

/// One place for every Mac-private identifier (OC-07).
public enum Identifiers {
    public static let bundleID = "com.eriskay.aa"
    public static let logSubsystem = "com.eriskay.aa"
    public static let utBundle = "com.eriskay.aa.bundle"        // .aaz, conforms to public.zip-archive
    public static let utSchedule = "com.eriskay.aa.schedule"    // aasched.json (declared only; never in panels)
    public static let utXaml = "com.eriskay.aa.xaml"            // pasteboard, conforms to public.data
    public static let utTaskRef = "com.eriskay.aa.task-ref"     // Board drag
    public static let utJobRef = "com.eriskay.aa.job-ref"       // Planner drag
    public static let utItemRef = "com.eriskay.aa.item-ref"     // sidebar → group drag, relationship drags
    public static let instanceRequestNotification = "com.eriskay.aa.InstanceRequest"
    public static let reminderNotificationID = "aa.reminder"    // OC-33

    /// 01 DATA-215 — every Keychain item the Mac build uses (nothing here travels between machines).
    public enum Keychain {
        public static let localDataKey = (service: "AA.LocalDataKey", account: "v1")
        public static let googleTokenKey = (service: "AA", account: "google-token-key")
        public static let gemini = (service: "com.eriskay.aa.gemini", account: "GeminiApiKey")
    }
}

/// Scene / window identifiers (01 DATA-220, OC-32) — also the snapshot hook's targets.
public enum SceneID: String, Sendable, CaseIterable {
    case main, splash, login, item, quickWork = "quick-work", search, activityLog = "activity-log",
         unitConverter = "unit-converter", folderBuilder = "folder-builder", dateCalculator = "date-calculator",
         flashSync = "flash-sync", crewTable = "crew-table", shortcuts, settings, about,
         bootstrap,                                           // 1×1 transparent helper scene (§7.1), never shown
         due, switcher                                        // NSPanels (logical ids for the snapshot hook)
}

public extension UTType {
    /// `.aaz` bundle (a ZIP).
    static var aaBundle: UTType { UTType(exportedAs: Identifiers.utBundle, conformingTo: .zip) }
    /// WPF XAML on the pasteboard.
    static var aaXaml: UTType { UTType(exportedAs: Identifiers.utXaml, conformingTo: .data) }
    static var aaTaskRef: UTType { UTType(exportedAs: Identifiers.utTaskRef, conformingTo: .data) }
    static var aaJobRef: UTType { UTType(exportedAs: Identifiers.utJobRef, conformingTo: .data) }
    static var aaItemRef: UTType { UTType(exportedAs: Identifiers.utItemRef, conformingTo: .data) }
    /// Office Open XML spreadsheet.
    static var xlsx: UTType {
        UTType("org.openxmlformats.spreadsheetml.sheet")
            ?? UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet", conformingTo: .zip)
    }
}
