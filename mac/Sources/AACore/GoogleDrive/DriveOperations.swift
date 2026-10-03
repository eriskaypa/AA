// Spec: 14 TOOLS-014/016/019/022/025, §3.1.8 UploadAsync, §3.1.9 ListBackupsAsync (creates `AA Backups` as a side
//       effect, Q-2), §3.1.10 EnsureFolderAsync (first result; null on any error → Drive root; Q-3/Q-4 kept),
//       §3.1.12 GetBestRemoteAsync (tick comparison, first wins on ties, Kind-mixing quirk Q-5 kept), §3.1.13
//       PushSyncAsync (overwrite in place, appProperties replaced key-wise), §3.2.10 (7-digit tick precision),
//       Q-1 (fields include nextPageToken). Source: AA/Services/GoogleDriveUploader.cs.
import Foundation

/// The high-level Drive operations of `GoogleDriveUploader`, over any `DriveAPI`.
public struct DriveOperations: Sendable {
    public let api: DriveAPI
    /// `DataStore.AppIdentity` at the time of the call (stamped into `aaIdentity`).
    public let identity: String

    /// The whole-Drive search page size (§3.1.4) and page cap (§3.1.5).
    public static let pageSize = 200
    public static let maxPages = 10

    public init(api: DriveAPI, identity: String) { self.api = api; self.identity = identity }

    /// §3.1.10: the first non-trashed folder with that name, else a new one in My Drive root; nil on any error.
    public func ensureFolder(_ name: String) async -> String? {
        do {
            let found = try await api.list(q: DriveQuery.folder(named: name), fields: "files(id,name)", orderBy: nil,
                                           pageSize: nil, wholeDrive: false, maxPages: 1)
            if let first = found.first, !first.id.isEmpty { return first.id }
            return try await api.createFolder(name: name)
        } catch {
            return nil
        }
    }

    /// §3.1.8 — uploads `file` (named after its basename) into `AA Backups` (root when the folder is unavailable).
    public func uploadBackup(_ file: URL) async throws -> DriveUploadResult {
        try await api.prepare()
        let folderID = await ensureFolder(DriveConstants.backupFolderName)
        let name = file.lastPathComponent
        let created = try await api.create(name: name, parents: folderID.map { [$0] },
                                           appProperties: [DriveConstants.identityProp: identity], from: file,
                                           fields: "id, name, webViewLink")
        return DriveUploadResult(name: created.name.isEmpty ? name : created.name, link: created.webViewLink)
    }

    /// §3.1.9 — every restorable bundle across the whole Drive, newest modified first.
    public func listBackups() async throws -> [DriveBackup] {
        try await api.prepare()
        let folderID = await ensureFolder(DriveConstants.backupFolderName)
        let files = try await api.list(q: DriveQuery.listBackups(folderID: folderID),
                                       fields: "nextPageToken,files(id,name,modifiedTime,mimeType)",
                                       orderBy: "modifiedTime desc", pageSize: DriveOperations.pageSize, wholeDrive: true,
                                       maxPages: DriveOperations.maxPages)
        return files.filter(\.isBundleCandidate).map { DriveBackup(id: $0.id, name: $0.name, modified: $0.modifiedUtc) }
    }

    /// §3.1.12 — the restorable file with the greatest key (`aaLastModified` round-trip in `zone`, else Drive's
    /// modified time as UTC ticks, else MinValue); first wins on ties.
    public func bestRemote(zone: TimeZone = .current) async throws -> DriveRemoteState? {
        try await api.prepare()
        let files = try await api.list(q: DriveQuery.bestRemote,
                                       fields: "nextPageToken,files(id,name,appProperties,modifiedTime,mimeType)",
                                       orderBy: "modifiedTime desc", pageSize: DriveOperations.pageSize, wholeDrive: true,
                                       maxPages: DriveOperations.maxPages)
        return DriveOperations.selectBest(files, zone: zone)
    }

    /// The pure selection of §3.1.12 (vector 7.6-1/2).
    public static func selectBest(_ files: [DriveFile], zone: TimeZone) -> DriveRemoteState? {
        var best: DriveRemoteState?
        var bestKey: Int64 = 0                                      // DateTime.MinValue
        for f in files where f.isBundleCandidate {
            let last = f.appProperties[DriveConstants.lastModifiedProp].flatMap { NetDateTime(parsing: $0, zone: zone) }
                .map { NetDateTime(ticks: $0.ticks, kind: $0.kind) }
            let rawIdentity = f.appProperties[DriveConstants.identityProp]
            let identity = NetText.isBlank(rawIdentity) ? nil : rawIdentity
            let driveMod = f.modifiedUtc
            let key = last?.ticks ?? driveMod?.ticks ?? 0
            if key > bestKey {
                bestKey = key
                best = DriveRemoteState(fileID: f.id, lastModified: last, driveModified: driveMod, identity: identity)
            }
        }
        return best
    }

    public func download(fileID: String, to destination: URL) async throws {
        try await api.download(fileID: fileID, to: destination)
    }

    /// §3.1.13 — overwrites (or creates) `AA Sync/AA-sync.zip` with `aaLastModified` = the stamp in `"o"` format
    /// (or `""`) and `aaIdentity`.
    public func pushSync(_ file: URL, lastModified: NetDateTime?, zone: TimeZone = .current) async throws {
        try await api.prepare()
        let folderID = await ensureFolder(DriveConstants.syncFolderName)
        let existing = try await api.list(q: DriveQuery.syncFile(folderID: folderID), fields: "files(id)", orderBy: nil,
                                          pageSize: 1, wholeDrive: false, maxPages: 1).first?.id
        let props = [DriveConstants.lastModifiedProp: lastModified.map { $0.format(.roundTripO, zone: zone) } ?? "",
                     DriveConstants.identityProp: identity]
        if let existing, !existing.isEmpty {
            _ = try await api.update(fileID: existing, appProperties: props, from: file, fields: "id")
        } else {
            _ = try await api.create(name: DriveConstants.syncFileName, parents: folderID.map { [$0] }, appProperties: props,
                                     from: file, fields: "id")
        }
    }
}
