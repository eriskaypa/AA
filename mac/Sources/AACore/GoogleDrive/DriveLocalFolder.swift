// Spec: 14 TOOLS-002/003/005/006, §6.2 (macOS detection order: CloudStorage GoogleDrive-*/My Drive sorted by name,
//       /Volumes/GoogleDrive/My Drive then /Volumes/*/My Drive, then ~/My Drive, ~/Google Drive, ~/GoogleDrive; a stored
//       non-absolute path is treated as missing and left untouched, Q-17), vectors 7.1; 01 DATA-153; 03 SHELL-074.
import Foundation

/// The synced-folder ("Google Drive for desktop") side: detection and file names.
public enum DriveLocalFolder {
    /// The sub-folder that receives synced-folder backups (`MW:671`).
    public static let backupsSubfolder = "AA Backups"

    /// Candidate folders in detection order (first existing directory wins).
    public static func candidates(home: URL, volumes: URL = URL(filePath: "/Volumes", directoryHint: .isDirectory),
                                  fileManager: FileManager = .default) -> [URL] {
        var out: [URL] = []
        let cloud = home.appending(path: "Library/CloudStorage", directoryHint: .isDirectory)
        let accounts = ((try? fileManager.contentsOfDirectory(atPath: cloud.path)) ?? [])
            .filter { $0.hasPrefix("GoogleDrive-") }
            .sorted()
        for a in accounts { out.append(cloud.appending(path: a, directoryHint: .isDirectory).appending(path: "My Drive", directoryHint: .isDirectory)) }
        out.append(volumes.appending(path: "GoogleDrive", directoryHint: .isDirectory).appending(path: "My Drive", directoryHint: .isDirectory))
        let vols = ((try? fileManager.contentsOfDirectory(atPath: volumes.path)) ?? []).sorted()
        for v in vols where v != "GoogleDrive" {
            out.append(volumes.appending(path: v, directoryHint: .isDirectory).appending(path: "My Drive", directoryHint: .isDirectory))
        }
        for name in ["My Drive", "Google Drive", "GoogleDrive"] {
            out.append(home.appending(path: name, directoryHint: .isDirectory))
        }
        return out
    }

    static func isDirectory(_ url: URL, _ fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// TOOLS-005 / DATA-153: the first existing candidate, or nil.
    public static func detect(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                              volumes: URL = URL(filePath: "/Volumes", directoryHint: .isDirectory),
                              fileManager: FileManager = .default) -> URL? {
        candidates(home: home, volumes: volumes, fileManager: fileManager).first { isDirectory($0, fileManager) }
    }

    /// A remembered folder is used only when it is an absolute POSIX path that exists (Q-17).
    public static func usableStored(_ stored: String?, fileManager: FileManager = .default) -> URL? {
        guard let s = stored, !NetText.isBlank(s), s.hasPrefix("/") else { return nil }
        let u = URL(filePath: s, directoryHint: .isDirectory)
        return isDirectory(u, fileManager) ? u : nil
    }

    /// TOOLS-006: `aa-data-{SafeIdentity}-{yyyyMMdd-HHmmss}.zip` (local wall clock).
    public static func backupFileName(identity: String, now: NetDateTime) -> String {
        "aa-data-\(WindowsFileName.safeIdentity(identity))-\(now.format(.stampSecond)).zip"
    }

    /// TOOLS-014 step 3: `aa-data-{yyyyMMdd-HHmmss}.zip` (no identity).
    public static func uploadTempName(now: NetDateTime) -> String { "aa-data-\(now.format(.stampSecond)).zip" }

    /// TOOLS-015 step 5: `aa-drive-{yyyyMMddHHmmss}.zip` (no dash).
    public static func loadTempName(now: NetDateTime) -> String {
        "aa-drive-\(now.format(.stampSecond).replacingOccurrences(of: "-", with: "")).zip"
    }

    /// §3.2.4: `aa-drive-{Guid:N}.zip`.
    public static func checkTempName(_ id: UUID = UUID()) -> String { "aa-drive-\(guidN(id)).zip" }

    /// TOOLS-021: `aa-sync-{Guid:N}.zip`.
    public static func syncTempName(_ id: UUID = UUID()) -> String { "aa-sync-\(guidN(id)).zip" }

    /// .NET `Guid.ToString("N")`: 32 lower-case hex digits.
    public static func guidN(_ id: UUID) -> String { id.uuidString.lowercased().replacingOccurrences(of: "-", with: "") }
}
