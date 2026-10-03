// Spec: 14 TOOLS-023/024/026/030, §3.2.4 CheckRemoteNewer (the decision part, up to "download to preview"), §3.2.10
//       (tick comparisons ignore Kind), vectors 7.6-3/4/5; 03 SHELL-122. The UI half (status, review, smart import,
//       reload) is the coordinator's (AA/Drive/DriveSyncCoordinator.swift).
import Foundation

/// What the decision part of `CheckRemoteNewer` concluded.
public enum DriveCheckResult: Sendable, Equatable {
    /// Sync is off or no client is configured (interactive → info box "Turn on…", background → silent).
    case notConfigured
    /// Background check without a current-scope token: return without opening a browser.
    case noToken
    /// Nothing restorable on Drive (interactive → status `No AA save found on Google Drive yet.`).
    case nothingOnDrive
    /// The remote is not newer (status `Google Drive is up to date ({HH:mm:ss}).`).
    case upToDate
    /// Background check, and the remote stamp equals the one last seen/declined/pushed: silent.
    case alreadySeen
    /// Newer: offer it. `downloaded` is the temp ZIP when the stamp had to be read from the bundle itself (the
    /// caller owns and deletes it); otherwise the caller downloads `fileID` itself after posting the status.
    case newer(remote: NetDateTime, identity: String?, fileID: String, downloaded: URL?)
}

public struct DriveCheckInput: Sendable {
    public var interactive: Bool
    public var syncOnSave: Bool
    public var configured: Bool
    public var hasToken: Bool
    /// `_repo.Data.LastModified`.
    public var localStamp: NetDateTime?
    /// `_lastSeenRemote`.
    public var lastSeenRemote: NetDateTime?

    public init(interactive: Bool, syncOnSave: Bool, configured: Bool, hasToken: Bool, localStamp: NetDateTime?,
                lastSeenRemote: NetDateTime?) {
        self.interactive = interactive; self.syncOnSave = syncOnSave; self.configured = configured
        self.hasToken = hasToken; self.localStamp = localStamp; self.lastSeenRemote = lastSeenRemote
    }
}

public enum DriveRemoteCheck {
    /// `newer = remote != null && (local == null || remote > local)` on ticks.
    public static func isNewer(remote: NetDateTime?, local: NetDateTime?) -> Bool {
        guard let remote else { return false }
        guard let local else { return true }
        return remote.ticks > local.ticks
    }

    /// The decision part of §3.2.4. Returns the result and the new `_lastSeenRemote` (set before the review, so a
    /// background decline is not re-offered for the same stamp). Temp files other than the returned one are deleted.
    /// - Parameters:
    ///   - makeTempURL: `<tmp>/aa-drive-{Guid:N}.zip`.
    ///   - peekStamp: `PeekZipLastModified` (nil when unreadable or unstamped).
    public static func run(_ input: DriveCheckInput, operations: DriveOperations, zone: TimeZone,
                           makeTempURL: @Sendable () -> URL,
                           peekStamp: @Sendable (URL) -> NetDateTime?) async throws -> (DriveCheckResult, NetDateTime?) {
        var lastSeen = input.lastSeenRemote
        guard input.syncOnSave, input.configured else { return (.notConfigured, lastSeen) }
        if !input.interactive && !input.hasToken { return (.noToken, lastSeen) }
        var temp: URL?
        do {
            guard let best = try await operations.bestRemote(zone: zone) else { return (.nothingOnDrive, lastSeen) }
            var remote = best.lastModified
            if remote == nil {
                let t = makeTempURL()
                temp = t
                try await operations.download(fileID: best.fileID, to: t)
                remote = peekStamp(t)
            }
            guard isNewer(remote: remote, local: input.localStamp), let stamp = remote else {
                if let temp { try? FileManager.default.removeItem(at: temp) }
                return (.upToDate, lastSeen)
            }
            if !input.interactive, let seen = lastSeen, seen.ticks == stamp.ticks {
                if let temp { try? FileManager.default.removeItem(at: temp) }
                return (.alreadySeen, lastSeen)
            }
            lastSeen = stamp
            return (.newer(remote: stamp, identity: best.identity, fileID: best.fileID, downloaded: temp), lastSeen)
        } catch {
            if let temp { try? FileManager.default.removeItem(at: temp) }
            throw error
        }
    }
}
