// Tests for 14 §7.1 (names), §7.2 (restorable rule), §7.6 (Drive decisions with a mock client, query strings,
// "o" round trip), §7.8 (AgeVerdict), TOOLS-018 (picker rows), §6.2 (synced-folder detection).
import Foundation
import Testing
@testable import AACore

@Suite struct DriveDecisionTests {
    let plus8 = TimeZone(secondsFromGMT: 8 * 3600)!
    let minus5 = TimeZone(secondsFromGMT: -5 * 3600)!

    // TV: 14 §7.1
    @Test func backupNames() {
        let now = NetDateTime(year: 2026, month: 9, day: 30, hour: 14, minute: 3, second: 7, kind: .local)
        #expect(DriveLocalFolder.backupFileName(identity: "Vessel-Alpha", now: now) == "aa-data-Vessel-Alpha-20260930-140307.zip")
        #expect(DriveLocalFolder.backupFileName(identity: "Vessel Alpha", now: now) == "aa-data-VesselAlpha-20260930-140307.zip")
        #expect(DriveLocalFolder.backupFileName(identity: "M/V Nord: 1", now: now) == "aa-data-MVNord1-20260930-140307.zip")
        #expect(DriveLocalFolder.backupFileName(identity: "   ", now: now) == "aa-data-AA-20260930-140307.zip")
        #expect(DriveLocalFolder.backupFileName(identity: "Eris's MacBook Pro", now: now) == "aa-data-Eris'sMacBookPro-20260930-140307.zip")
        #expect(WindowsFileName.safeIdentity("A<B>C|D?E*F\"G") == "ABCDEFG")
        #expect(DriveLocalFolder.uploadTempName(now: now) == "aa-data-20260930-140307.zip")
        #expect(DriveLocalFolder.loadTempName(now: now) == "aa-drive-20260930140307.zip")
        let g = UUID(uuidString: "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9")!
        #expect(DriveLocalFolder.checkTempName(g) == "aa-drive-0a1b2c3d4e5f60718293a4b5c6d7e8f9.zip")
        #expect(DriveLocalFolder.syncTempName(g) == "aa-sync-0a1b2c3d4e5f60718293a4b5c6d7e8f9.zip")
    }

    // TV: 14 §7.2
    @Test(arguments: [
        ("AA-backup-iOS-20260930-101500.aaz", "application/octet-stream", true),
        ("AA-backup-iOS-dataonly-20260930-101500.aaz", nil, true),
        ("aa-data-20260930-101500.zip", "application/zip", true),
        ("aa-data-Vessel-Alpha-20260930-101500.zip", "application/x-zip-compressed", true),
        ("AA-sync.zip", "application/zip", true),
        ("AA-DATA-X.ZIP", nil, true),
        ("My renamed backup.AAZ", nil, true),
        ("xaa-backupx.zip", nil, true),
        ("aa-database notes", "application/vnd.google-apps.document", false),
        ("AA Backups", "application/vnd.google-apps.folder", false),
        ("backup.aaz", "application/vnd.google-apps.shortcut", false),
        ("holiday-photos.zip", "application/zip", false),
        ("aa-data.json", "application/json", false),
        ("aa-data.zip.txt", "text/plain", false),
        ("", "application/zip", false),
        ("", nil, false),
    ] as [(String, String?, Bool)])
    func restorable(name: String, mime: String?, expected: Bool) {
        #expect(BundleName.isRestorable(name: name, mimeType: mime) == expected)
    }

    // TV: 14 §7.6-7 query strings (byte-for-byte)
    @Test func queryStrings() {
        #expect(DriveQuery.bundleNames == "(name contains 'aa-data' or name contains 'AA-backup' or name contains 'AA-sync' or name contains '.aaz')")
        #expect(DriveQuery.listBackups(folderID: "F1") == "('F1' in parents or (name contains 'aa-data' or name contains 'AA-backup' or name contains 'AA-sync' or name contains '.aaz')) and trashed=false and mimeType!='application/vnd.google-apps.folder'")
        #expect(DriveQuery.listBackups(folderID: nil) == "(name contains 'aa-data' or name contains 'AA-backup' or name contains 'AA-sync' or name contains '.aaz') and trashed=false and mimeType!='application/vnd.google-apps.folder'")
        // §3.1.10 hardened per DECISIONS 14 Q-3 ('me' in owners; capabilities read for the pick).
        #expect(DriveQuery.folder(named: "AA Backups") == "mimeType='application/vnd.google-apps.folder' and name='AA Backups' and 'me' in owners and trashed=false")
        #expect(DriveQuery.folder(named: "AA Sync") == "mimeType='application/vnd.google-apps.folder' and name='AA Sync' and 'me' in owners and trashed=false")
        #expect(DriveQuery.folderFields == "files(id,name,capabilities/canAddChildren)")
        #expect(DriveQuery.bestRemote == "trashed=false and mimeType!='application/vnd.google-apps.folder' and (name='AA-sync.zip' or (name contains 'aa-data' or name contains 'AA-backup' or name contains 'AA-sync' or name contains '.aaz'))")
        #expect(DriveQuery.syncFile(folderID: "S9") == "'S9' in parents and name='AA-sync.zip' and trashed=false")
        #expect(DriveQuery.syncFile(folderID: nil) == "name='AA-sync.zip' and trashed=false")
        #expect(DriveQuery.literal("it's a\\b") == "it\\'s a\\\\b")
    }

    // TV: 14 §7.6-1 best remote: stamps vs Drive time (Q-5 kept)
    @Test func bestRemoteMixesKinds() {
        let a = DriveFile(id: "A", name: "AA-sync.zip", mimeType: "application/zip", modifiedTime: "2026-09-30T02:00:05.000Z",
                          appProperties: ["aaLastModified": "2026-09-30T10:00:00.0000000+08:00", "aaIdentity": "Vessel-Alpha"])
        let b = DriveFile(id: "B", name: "aa-data-20260930-090000.zip", mimeType: "application/zip",
                          modifiedTime: "2026-09-30T05:00:00.000Z")
        #expect(DriveOperations.selectBest([a, b], zone: plus8)?.fileID == "A")
        #expect(DriveOperations.selectBest([b, a], zone: plus8)?.fileID == "A")
        #expect(DriveOperations.selectBest([a, b], zone: minus5)?.fileID == "B")
        let best = DriveOperations.selectBest([a, b], zone: plus8)!
        #expect(best.identity == "Vessel-Alpha")
        #expect(best.lastModified?.kind == .local)
        #expect(best.driveModified == NetDateTime(year: 2026, month: 9, day: 30, hour: 2, minute: 0, second: 5, kind: .utc))
    }

    // TV: 14 §7.6-2 not a bundle; ties keep the earlier file; MinValue never wins; blank identity → nil
    @Test func bestRemoteSkipsNonBundlesAndKeepsFirstOnTies() {
        let doc = DriveFile(id: "D", name: "aa-data notes", mimeType: "application/vnd.google-apps.document",
                            modifiedTime: "2026-09-30T09:00:00Z")
        let x = DriveFile(id: "X", name: "aa-data-1.zip", modifiedTime: "2026-09-30T08:00:00Z", appProperties: ["aaIdentity": "  "])
        let y = DriveFile(id: "Y", name: "aa-data-2.zip", modifiedTime: "2026-09-30T08:00:00Z")
        let z = DriveFile(id: "Z", name: "aa-data-3.zip")
        let best = DriveOperations.selectBest([doc, x, y, z], zone: plus8)
        #expect(best?.fileID == "X")
        #expect(best?.identity == nil)
        #expect(DriveOperations.selectBest([z], zone: plus8) == nil)
        #expect(DriveOperations.selectBest([], zone: plus8) == nil)
        let emptyStamp = DriveFile(id: "E", name: "AA-sync.zip", modifiedTime: "2026-09-30T08:00:00Z", appProperties: ["aaLastModified": ""])
        #expect(DriveOperations.selectBest([emptyStamp], zone: plus8)?.lastModified == nil)
    }

    private func ops(_ api: DriveMockAPI) -> DriveOperations { DriveOperations(api: api, identity: "Vessel-Alpha") }

    private func input(interactive: Bool, local: NetDateTime?, lastSeen: NetDateTime? = nil, hasToken: Bool = true) -> DriveCheckInput {
        DriveCheckInput(interactive: interactive, syncOnSave: true, configured: true, hasToken: hasToken, localStamp: local,
                        lastSeenRemote: lastSeen)
    }

    // TV: 14 §7.6-3 no stamp → download and read the bundle's LastModified
    @Test func noStampDownloadsToPeek() async throws {
        let api = DriveMockAPI()
        api.files = [DriveFile(id: "B", name: "aa-data-20260930-110000.zip", modifiedTime: "2026-09-30T03:00:00Z")]
        let tmp = TempFolder("aa-drive-check")
        let zone = plus8
        let local = NetDateTime(parsing: "2026-09-30T10:59:59.9999999+08:00", zone: zone)!
        let (result, lastSeen) = try await DriveRemoteCheck.run(
            input(interactive: false, local: local), operations: ops(api), zone: zone,
            makeTempURL: { tmp.url.appending(path: "aa-drive-x.zip") },
            peekStamp: { _ in NetDateTime(parsing: "2026-09-30T11:00:00+08:00", zone: zone) })
        guard case .newer(let remote, let identity, let fileID, let downloaded) = result else {
            Issue.record("expected newer, got \(result)"); return
        }
        #expect(fileID == "B" && identity == nil)
        #expect(remote.ticks == NetDateTime(parsing: "2026-09-30T11:00:00+08:00", zone: zone)!.ticks)
        #expect(downloaded == tmp.url.appending(path: "aa-drive-x.zip"))
        #expect(lastSeen == remote)
        #expect(api.calls.contains("download:B"))
    }

    // TV: 14 §7.6-4 decline memory
    @Test func declineMemory() async throws {
        let api = DriveMockAPI()
        api.files = [DriveFile(id: "S", name: "AA-sync.zip", modifiedTime: "2026-09-30T03:00:00Z",
                               appProperties: ["aaLastModified": "2026-09-30T11:00:00.0000000+08:00"])]
        let tmp = TempFolder("aa-drive-check")
        let local = NetDateTime(parsing: "2026-09-30T10:00:00+08:00", zone: plus8)!
        let mk: @Sendable () -> URL = { tmp.url.appending(path: "t.zip") }
        let (first, seen) = try await DriveRemoteCheck.run(input(interactive: false, local: local), operations: ops(api),
                                                           zone: plus8, makeTempURL: mk, peekStamp: { _ in nil })
        guard case .newer(_, _, _, let downloaded) = first else { Issue.record("expected newer"); return }
        #expect(downloaded == nil)                         // stamped: the caller downloads after the status
        let (again, seen2) = try await DriveRemoteCheck.run(input(interactive: false, local: local, lastSeen: seen),
                                                            operations: ops(api), zone: plus8, makeTempURL: mk, peekStamp: { _ in nil })
        #expect(again == .alreadySeen)
        #expect(seen2 == seen)
        let (interactive, _) = try await DriveRemoteCheck.run(input(interactive: true, local: local, lastSeen: seen),
                                                              operations: ops(api), zone: plus8, makeTempURL: mk, peekStamp: { _ in nil })
        if case .newer = interactive {} else { Issue.record("interactive must re-offer") }
    }

    // TV: 14 §7.6-5 own push not offered back (needs exact 100 ns ticks)
    @Test func ownPushIsUpToDate() async throws {
        let zone = plus8
        let stamp = NetDateTime(parsing: "2026-09-30T16:15:29.9876543+08:00", zone: zone)!
        let pushed = stamp.format(.roundTripO, zone: zone)
        let api = DriveMockAPI()
        api.files = [DriveFile(id: "S", name: "AA-sync.zip", modifiedTime: "2026-09-30T08:15:31Z",
                               appProperties: ["aaLastModified": pushed])]
        let (r, _) = try await DriveRemoteCheck.run(input(interactive: false, local: stamp, lastSeen: stamp), operations: ops(api),
                                                    zone: zone, makeTempURL: { URL(filePath: "/tmp/never") }, peekStamp: { _ in nil })
        #expect(r == .upToDate)
    }

    // TV: 14 §7.6-6 round trip "o"
    @Test func roundTripO() {
        let zone = plus8
        let local = NetDateTime(year: 2026, month: 9, day: 30, hour: 16, minute: 15, second: 29, fractionTicks: 9_876_543, kind: .local)
        let text = local.format(.roundTripO, zone: zone)
        #expect(text == "2026-09-30T16:15:29.9876543+08:00")
        let back = NetDateTime(parsing: text, zone: zone)!
        #expect(back.ticks == local.ticks && back.kind == .local)
        let utc = NetDateTime(parsing: "2026-09-30T08:15:29.9876540Z", zone: zone)!
        #expect(utc.kind == .utc && utc.format(.roundTripO, zone: zone) == "2026-09-30T08:15:29.9876540Z")
        let unspecified = NetDateTime(parsing: "2026-09-30T16:15:29.9876540", zone: zone)!
        #expect(unspecified.kind == .unspecified && unspecified.format(.roundTripO, zone: zone) == "2026-09-30T16:15:29.9876540")
    }

    // TV: 14 §3.2.4 gating (sync off / unconfigured / background without token / nothing on Drive)
    @Test func gating() async throws {
        let api = DriveMockAPI()
        let mk: @Sendable () -> URL = { URL(filePath: "/tmp/never") }
        var off = input(interactive: true, local: nil)
        off.syncOnSave = false
        #expect(try await DriveRemoteCheck.run(off, operations: ops(api), zone: plus8, makeTempURL: mk, peekStamp: { _ in nil }).0 == .notConfigured)
        var unconfigured = input(interactive: false, local: nil)
        unconfigured.configured = false
        #expect(try await DriveRemoteCheck.run(unconfigured, operations: ops(api), zone: plus8, makeTempURL: mk, peekStamp: { _ in nil }).0 == .notConfigured)
        #expect(try await DriveRemoteCheck.run(input(interactive: false, local: nil, hasToken: false), operations: ops(api),
                                               zone: plus8, makeTempURL: mk, peekStamp: { _ in nil }).0 == .noToken)
        #expect(api.calls.isEmpty)                         // never touched Drive
        #expect(try await DriveRemoteCheck.run(input(interactive: true, local: nil), operations: ops(api), zone: plus8,
                                               makeTempURL: mk, peekStamp: { _ in nil }).0 == .nothingOnDrive)
        // A stamp-less remote whose bundle cannot be read is "not newer"; its temp file is removed.
        let tmp = TempFolder("aa-drive-check")
        api.files = [DriveFile(id: "B", name: "aa-data-x.zip", modifiedTime: "2026-09-30T03:00:00Z")]
        let target = tmp.url.appending(path: "t.zip")
        let (r, _) = try await DriveRemoteCheck.run(input(interactive: true, local: nil), operations: ops(api), zone: plus8,
                                                    makeTempURL: { target }, peekStamp: { _ in nil })
        #expect(r == .upToDate)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(DriveRemoteCheck.isNewer(remote: NetDateTime(ticks: 5, kind: .utc), local: nil))
        #expect(!DriveRemoteCheck.isNewer(remote: nil, local: nil))
        #expect(!DriveRemoteCheck.isNewer(remote: NetDateTime(ticks: 5, kind: .utc), local: NetDateTime(ticks: 5, kind: .local)))
    }

    // TV: TOOLS-014/016/022 operations over the mock
    @Test func operationsUploadListPush() async throws {
        let api = DriveMockAPI()
        api.files = [
            DriveFile(id: "1", name: "AA-sync.zip", modifiedTime: "2026-09-30T08:00:00.000Z"),
            DriveFile(id: "2", name: "AA Backups notes", mimeType: "application/vnd.google-apps.document"),
            DriveFile(id: "3", name: "AA-backup-iOS-20260930-101500.aaz", modifiedTime: "bogus"),
        ]
        let tmp = TempFolder("aa-drive-ops")
        let file = try tmp.write("aa-data-20260930-140307.zip", "zip")
        let up = try await ops(api).uploadBackup(file)
        #expect(up.name == "aa-data-20260930-140307.zip" && up.link != nil)
        #expect(api.created.last?.parents == ["folder-AA-Backups"])
        #expect(api.created.last?.props == ["aaIdentity": "Vessel-Alpha"])
        #expect(api.calls.first == "prepare")

        let list = try await ops(api).listBackups()
        #expect(list.map(\.id) == ["1", "3"])
        #expect(list[1].modified == nil)
        #expect(api.listQueries.last == DriveQuery.listBackups(folderID: "folder-AA-Backups"))

        let stamp = NetDateTime(parsing: "2026-09-30T16:15:29.9876543+08:00", zone: plus8)!
        try await ops(api).pushSync(file, lastModified: stamp, zone: plus8)
        #expect(api.updated.last?.id == "1")
        #expect(api.updated.last?.props == ["aaLastModified": "2026-09-30T16:15:29.9876543+08:00", "aaIdentity": "Vessel-Alpha"])

        let empty = DriveMockAPI()
        try await ops(empty).pushSync(file, lastModified: nil, zone: plus8)
        #expect(empty.created.last?.name == "AA-sync.zip")
        #expect(empty.created.last?.parents == ["folder-AA-Sync"])
        #expect(empty.created.last?.props == ["aaLastModified": "", "aaIdentity": "Vessel-Alpha"])

        // EnsureFolder failure → Drive root (parents omitted).
        let failing = DriveMockAPI()
        failing.failList = .api(status: 403, message: "nope", reason: nil)
        #expect(await ops(failing).ensureFolder("AA Backups") == nil)
    }

    // TV: 14 §3.1.10 / §8 Q-3 hardened EnsureFolder (DECISIONS 14 "Q-3 harden EnsureFolder: yes")
    @Test func ensureFolderHardened() async throws {
        let folder = DriveConstants.folderMimeType
        // A read-only (hand-made / other-app) match is skipped for a writable one, whatever the order.
        let api = DriveMockAPI()
        api.folderCandidates["AA Backups"] = [
            DriveFile(id: "hand-made", name: "AA Backups", mimeType: folder, canAddChildren: false),
            DriveFile(id: "aa-made", name: "AA Backups", mimeType: folder, canAddChildren: true),
        ]
        #expect(await ops(api).ensureFolder("AA Backups") == "aa-made")
        #expect(api.listQueries.last == DriveQuery.folder(named: "AA Backups"))
        #expect(api.listFields.last == DriveQuery.folderFields)
        #expect(!api.calls.contains { $0.hasPrefix("createFolder") })

        // Every match read-only → AA creates its own folder in My Drive root (the upload then succeeds).
        let readOnly = DriveMockAPI()
        readOnly.folderCandidates["AA Sync"] = [DriveFile(id: "shared", name: "AA Sync", mimeType: folder, canAddChildren: false)]
        #expect(await ops(readOnly).ensureFolder("AA Sync") == "folder-AA-Sync")
        #expect(readOnly.calls.contains("createFolder:AA Sync"))

        // Capability not sent → Windows' first result.
        #expect(DriveOperations.pickFolder([DriveFile(id: "x", name: "AA Sync"), DriveFile(id: "y", name: "AA Sync")]) == "x")
        #expect(DriveOperations.pickFolder([DriveFile(id: "", name: "AA Sync", canAddChildren: true)]) == nil)
        #expect(DriveOperations.pickFolder([]) == nil)

        // The REST row carries capabilities.canAddChildren.
        let row = try #require(JSONParser.parse(Data(#"{"id":"F","name":"AA Backups","capabilities":{"canAddChildren":false}}"#.utf8)).objectValue)
        #expect(DriveFile(json: row).canAddChildren == false)
        let bare = try #require(JSONParser.parse(Data(#"{"id":"F","name":"AA Backups"}"#.utf8)).objectValue)
        #expect(DriveFile(json: bare).canAddChildren == nil)
    }

    // TV: TOOLS-018 picker rows
    @Test func backupDisplay() {
        let utc = TimeZone(identifier: "UTC")!
        let b = DriveBackup(id: "1", name: "aa-data-x.zip", modified: NetDateTime(parsing: "2026-09-30T02:00:00Z", zone: utc))
        #expect(b.display(zone: plus8) == "aa-data-x.zip    (uploaded 2026-09-30 10:00)")
        #expect(DriveBackup(id: "2", name: "n.aaz", modified: nil).display(zone: plus8) == "n.aaz")
    }

    // TV: 14 §7.8 AgeVerdict usage
    @Test func ageVerdict() {
        let inc = NetDateTime(year: 2026, month: 9, day: 30, hour: 10, kind: .local)
        let cur = NetDateTime(year: 2026, month: 9, day: 29, hour: 8, kind: .local)
        #expect(AgeVerdict.text(incoming: inc, current: cur) == "Incoming saved: 2026-09-30 10:00:00\nCurrent saved:  2026-09-29 08:00:00\n\u{279C} The incoming data is NEWER than your current data.")
        #expect(AgeVerdict.text(incoming: nil, current: cur) == "Incoming saved: (no save date)\nCurrent saved:  2026-09-29 08:00:00\n\u{279C} The incoming data has no save date (older format); it may be older.")
    }

    // TV: 14 §6.2 detection order, Q-17
    @Test func syncedFolderDetection() throws {
        let home = TempFolder("aa-home"), vols = TempFolder("aa-vols")
        let fm = FileManager.default
        #expect(DriveLocalFolder.detect(home: home.url, volumes: vols.url) == nil)
        try fm.createDirectory(at: home.url.appending(path: "GoogleDrive"), withIntermediateDirectories: true)
        #expect(DriveLocalFolder.detect(home: home.url, volumes: vols.url)?.lastPathComponent == "GoogleDrive")
        try fm.createDirectory(at: home.url.appending(path: "Google Drive"), withIntermediateDirectories: true)
        #expect(DriveLocalFolder.detect(home: home.url, volumes: vols.url)?.lastPathComponent == "Google Drive")
        try fm.createDirectory(at: vols.url.appending(path: "Backup/My Drive"), withIntermediateDirectories: true)
        #expect(DriveLocalFolder.detect(home: home.url, volumes: vols.url)?.path.hasSuffix("Backup/My Drive") == true)
        try fm.createDirectory(at: vols.url.appending(path: "GoogleDrive/My Drive"), withIntermediateDirectories: true)
        #expect(DriveLocalFolder.detect(home: home.url, volumes: vols.url)?.path.hasSuffix("GoogleDrive/My Drive") == true)
        try fm.createDirectory(at: home.url.appending(path: "Library/CloudStorage/GoogleDrive-zz@example.com/My Drive"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: home.url.appending(path: "Library/CloudStorage/GoogleDrive-aa@example.com/My Drive"),
                               withIntermediateDirectories: true)
        #expect(DriveLocalFolder.detect(home: home.url, volumes: vols.url)?.path.contains("GoogleDrive-aa@example.com") == true)
        #expect(DriveLocalFolder.usableStored("G:\\My Drive") == nil)
        #expect(DriveLocalFolder.usableStored(home.url.path)?.path == home.url.path)
        #expect(DriveLocalFolder.usableStored(home.url.path + "/missing") == nil)
    }

    // TV: TOOLS-033 / TOOLS-030 status strings
    @Test func statusTexts() {
        #expect(DriveText.newerFound(identity: "Vessel-Alpha") == "Newer save on Google Drive from \u{201C}Vessel-Alpha\u{201D} \u{2014} downloading to preview\u{2026}")
        #expect(DriveText.newerFound(identity: nil) == "Newer save on Google Drive \u{2014} downloading to preview\u{2026}")
        #expect(DriveText.newerFound(identity: " ") == "Newer save on Google Drive \u{2014} downloading to preview\u{2026}")
        #expect(DriveText.loadedBackup("x.zip", dataOnly: true) == "Loaded backup from Google Drive: x.zip (text only \u{2014} attachments unchanged).")
        #expect(DriveText.loadedBackup("x.zip", dataOnly: false) == "Loaded backup from Google Drive: x.zip (with attachments).")
        #expect(DriveText.uploadedMessage(name: "a.zip", link: nil) == "Uploaded 'a.zip' to your Google Drive (folder 'AA Backups').")
        #expect(DriveText.uploadedMessage(name: "a.zip", link: "https://x") == "Uploaded 'a.zip' to your Google Drive (folder 'AA Backups').\n\nhttps://x")
        #expect(DriveText.upToDate("09:15:00") == "Google Drive is up to date (09:15:00).")
        #expect(DriveText.synced("09:15:00") == "Synced to Google Drive 09:15:00")
        #expect(DriveError.notConfigured.localizedDescription == "No Google OAuth client configured. Use File \u{25B8} 'Set Google OAuth client...' first.")
    }
}
