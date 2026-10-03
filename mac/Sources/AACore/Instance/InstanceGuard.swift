// Spec: 01 MP DATA-170…179 as simplified by DECISIONS ("a second launch activates the running instance"), §MP.3.1–3.7,
//       §MP.4.1–4.2, §MP.6.1–6.2, MP.7.1/7.2/7.7/7.8 vectors; DATA-178 (stale temp files), DATA-179 (external active
//       data file), DATA-184 (evidence: a foreign data.json temp file at launch); ARCHITECTURE.md §6.6.
import Foundation
import AppKit
import os

public enum InstanceGuardResult: Sendable, Equatable {
    case editor, unguarded(String), runningHere(pid: Int32), otherUser(String),
         remote(host: String, lastSeen: Date, stale: Bool)
}

/// Why this process could not edit: the full detail behind an `InstanceGuardResult` (alert wording, buttons).
public struct PersistBlockedInfo: Sendable, Equatable {
    public enum Target: Sendable, Equatable { case folder(URL), externalFile(URL) }
    public var target: Target
    public var record: PersistLockRecord?
    public var holder: PersistHolder
    public var lease: Bool

    public init(target: Target, record: PersistLockRecord?, holder: PersistHolder, lease: Bool) {
        self.target = target; self.record = record; self.holder = holder; self.lease = lease
    }

    /// The pid of a holder on this Mac (Switch to Running AA / Switch to Other AA).
    public var localPid: Int32? {
        switch holder {
        case .sameUser(let pid, _), .sameUserNoApp(let pid, _): return pid
        default: return nil
        }
    }
}

@MainActor public enum InstanceGuard {
    static let log = AALog.logger("instance")

    /// Injected in tests (probe, clock, host id, volume kind).
    static var environment: PersistLockEnvironment = .live
    /// `~/Library/Application Support/AA-locks` (DATA-179); tests redirect it.
    static var externalLocksFolder: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/AA-locks", directoryHint: .isDirectory)

    static var folderLock: PersistInstanceLock?
    static var externalLock: PersistInstanceLock?
    static var externalKey: String?
    private static var forwardObserver: NSObjectProtocol?
    private static var wakeObserver: NSObjectProtocol?
    private static var heartbeatTimer: Timer?

    /// The canonical AppFolder of the last `acquire` (forwarded requests are matched against it).
    public private(set) static var canonicalFolder: String?
    /// Detail of the last refused `acquire` / `acquireExternal` (nil when not blocked).
    public private(set) static var folderBlocked: PersistBlockedInfo?
    public private(set) static var externalBlocked: PersistBlockedInfo?
    /// DATA-184 evidence: a `data.json.{32hex}.tmp` existed when this process started.
    public private(set) static var foreignTempFileAtLaunch = false
    /// DATA-177: called when a lease-mode editor finds that another computer took over (after wake or before a write).
    public static var onLeaseLost: (@MainActor (_ host: String) -> Void)?

    /// True while this process holds the data-folder lock (editor).
    public static var isEditor: Bool { folderLock?.isOwner ?? false }

    // MARK: Data folder (DATA-170…177)

    public static func acquire(appFolder: URL) -> InstanceGuardResult {
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        let canonical = PersistHost.canonicalPath(appFolder)
        canonicalFolder = canonical
        foreignTempFileAtLaunch = PersistTempFiles.hasForeignDataTemp(in: appFolder)
        let lock = PersistInstanceLock(lockURL: appFolder.appending(path: ".aa.lock"), env: environment) { r in
            r.appFolder = canonical
        }
        let outcome = lock.acquire()
        switch outcome {
        case .owner:
            folderLock = lock
            folderBlocked = nil
            PersistTempFiles.cleanStale(in: appFolder, now: environment.now())          // DATA-178
            startLeaseMonitoring()
            return .editor
        case .unguarded(let why):
            log.notice("instance guard unavailable for \(appFolder.path, privacy: .public): \(why, privacy: .public)")
            return .unguarded(why)
        case let .blocked(record, holder, lease):
            folderLock = lock
            folderBlocked = PersistBlockedInfo(target: .folder(appFolder), record: record, holder: holder, lease: lease)
            return result(for: holder, record: record)
        }
    }

    /// The `InstanceGuardResult` for a holder (§MP.3.3 → DECISIONS).
    static func result(for holder: PersistHolder, record: PersistLockRecord?) -> InstanceGuardResult {
        switch holder {
        case .sameUser(let pid, _): return .runningHere(pid: pid)
        case .sameUserNoApp: return .otherUser(record?.user ?? NSUserName())
        case .otherUser(let u): return .otherUser(u)
        case let .otherHostFresh(host, hb): return .remote(host: host, lastSeen: hb, stale: false)
        case let .otherHostStale(host, hb): return .remote(host: host, lastSeen: hb, stale: true)
        case .unknown, .released, .dead: return .otherUser(record?.user ?? "")
        }
    }

    /// DATA-172 retry (1 s while the alert is up) and DATA-175 upgrade poll (5 s while read-only): one attempt.
    /// On success this process becomes the editor (the record is written; DATA-178 housekeeping runs).
    public static func retryFolderLock() -> Bool {
        guard let lock = folderLock, let info = folderBlocked, case .folder(let folder) = info.target else {
            return folderLock?.isOwner ?? false
        }
        guard lock.tryAcquire() else { return false }
        folderBlocked = nil
        PersistTempFiles.cleanStale(in: folder, now: environment.now())
        startLeaseMonitoring()
        return true
    }

    /// DATA-175 "Stay Read-Only": hands the lock back and keeps polling later.
    public static func relinquishFolderLock() {
        guard let lock = folderLock, lock.isOwner else { return }
        lock.relinquish()
        stopLeaseMonitoring()
        if folderBlocked == nil, let folder = canonicalFolder {
            folderBlocked = PersistBlockedInfo(target: .folder(URL(fileURLWithPath: folder)), record: nil,
                                               holder: .unknown, lease: false)
        }
    }

    /// DATA-177 "Take Over" (after the critical confirmation).
    public static func takeOver() -> Bool {
        guard let lock = folderLock else { return false }
        guard case .owner = lock.takeOver() else { return false }
        if case .folder(let folder) = folderBlocked?.target {
            PersistTempFiles.cleanStale(in: folder, now: environment.now())
        }
        folderBlocked = nil
        startLeaseMonitoring()
        return true
    }

    /// Clean quit: `Mode: "Released"` then the descriptors close (never deletes the lock files).
    public static func release() {
        stopLeaseMonitoring()
        folderLock?.release()
        folderLock = nil
        releaseExternal()
    }

    // MARK: Forwarding (DATA-173, DECISIONS)

    /// `runningHere` → tell the editor (distributed notification), hand activation over to it. True when the running
    /// application was found and asked to activate.
    public static func forwardToRunningInstance(pid: Int32, documents: [URL]) -> Bool {
        let info = PersistInstanceRequest.userInfo(documents: documents, appFolder: canonicalFolder ?? "",
                                                   fromPid: getpid())
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Identifiers.instanceRequestNotification), object: String(pid), userInfo: info,
            deliverImmediately: true)
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if let nsApp = NSApp { nsApp.yieldActivation(to: app) }
        return app.activate(from: NSRunningApplication.current, options: [])
    }

    /// The editor side: requests addressed to this pid for this data folder activate the app and deliver documents.
    public static func listenForForwardedDocuments(_ handler: @escaping @MainActor ([URL]) -> Void) {
        if let forwardObserver { DistributedNotificationCenter.default().removeObserver(forwardObserver) }
        forwardObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Identifiers.instanceRequestNotification), object: String(getpid()),
            queue: .main) { note in
            let info = note.userInfo
            MainActor.assumeIsolated {
                guard let urls = PersistInstanceRequest.accept(info, canonicalFolder: canonicalFolder) else { return }
                NSApp?.activate()
                handler(urls)
            }
        }
    }

    // MARK: External active data file (DATA-179)

    /// Per-user flock on `~/Library/Application Support/AA-locks/external-{sha256}.lock`. `.editor` when held.
    public static func acquireExternal(fileURL: URL) -> InstanceGuardResult {
        let key = externalLockKey(fileURL)
        if key == externalKey, externalLock?.isOwner == true { return .editor }
        releaseExternal()
        let canonical = canonicalFolder ?? ""
        let dataFile = PersistHost.canonicalPath(fileURL)
        let lock = PersistInstanceLock(lockURL: externalLocksFolder.appending(path: "external-\(key).lock"),
                                       env: environment) { r in
            r.appFolder = canonical
            r.dataFile = dataFile
        }
        switch lock.acquire() {
        case .owner:
            externalLock = lock
            externalKey = key
            externalBlocked = nil
            return .editor
        case .unguarded(let why):
            log.notice("external-file lock unavailable: \(why, privacy: .public)")
            return .unguarded(why)
        case let .blocked(record, holder, lease):
            externalBlocked = PersistBlockedInfo(target: .externalFile(fileURL), record: record, holder: holder, lease: lease)
            externalLock = lock
            externalKey = key
            return result(for: holder, record: record)
        }
    }

    /// When the active file goes back to the default (bundle import, Flash Sync apply, DATA-049).
    public static func releaseExternal() {
        externalLock?.release()
        externalLock = nil
        externalKey = nil
        externalBlocked = nil
    }

    /// DATA-172 retry for the external-file alert.
    public static func retryExternalLock() -> Bool {
        guard let lock = externalLock, externalBlocked != nil else { return externalLock?.isOwner ?? false }
        guard lock.tryAcquire() else { return false }
        externalBlocked = nil
        return true
    }

    /// Lowercase hex SHA-256 of the canonical path (`realpath`, then lowercased).
    public nonisolated static func externalLockKey(_ fileURL: URL) -> String {
        PersistHost.sha256Hex(Data(NetText.toLowerInvariant(PersistHost.canonicalPath(fileURL)).utf8))
    }

    // MARK: Lease monitoring (DATA-177)

    static func startLeaseMonitoring() {
        stopLeaseMonitoring()
        guard let lock = folderLock, lock.isLeaseMode else { return }
        PersistLeaseGate.shared.install(lock)
        let t = Timer(timeInterval: PersistLockConstants.heartbeat, repeats: true) { _ in
            MainActor.assumeIsolated { InstanceGuard.heartbeatTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        heartbeatTimer = t
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { InstanceGuard.checkLeaseAfterWake() }
        }
    }

    static func stopLeaseMonitoring() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        PersistLeaseGate.shared.install(nil)
    }

    static func heartbeatTick() {
        guard let lock = folderLock, lock.isOwner else { return }
        if !lock.heartbeat() { leaseLost(lock) }
    }

    static func checkLeaseAfterWake() {
        guard let lock = folderLock, lock.isOwner else { return }
        if !lock.confirmLease(force: true) { leaseLost(lock) }
    }

    static func leaseLost(_ lock: PersistInstanceLock) {
        let host = lock.currentRecord()?.host ?? ""
        stopLeaseMonitoring()
        lock.relinquish()
        if let folder = canonicalFolder {
            folderBlocked = PersistBlockedInfo(target: .folder(URL(fileURLWithPath: folder)), record: lock.currentRecord(),
                                               holder: .unknown, lease: true)
        }
        onLeaseLost?(host)
    }
}

/// Lock-protected access to the lease for the writer queue (DATA-177 "before its first write after a gap").
public final class PersistLeaseGate: @unchecked Sendable {
    public static let shared = PersistLeaseGate()
    private let lock = NSLock()
    private var current: PersistInstanceLock?

    func install(_ l: PersistInstanceLock?) { lock.lock(); current = l; lock.unlock() }

    /// True unless this process is a lease-mode editor whose claim another computer has taken.
    public func mayWrite() -> Bool {
        lock.lock(); let l = current; lock.unlock()
        guard let l else { return true }
        if l.confirmLease() { return true }
        Task { @MainActor in InstanceGuard.leaseLost(l) }
        return false
    }
}

/// The distributed-notification payload of DATA-173 (`com.eriskay.aa.InstanceRequest`).
public enum PersistInstanceRequest {
    public static func userInfo(documents: [URL], appFolder: String, fromPid: Int32) -> [String: Any] {
        ["Action": documents.isEmpty ? "activate" : "open", "URLs": documents.map(\.path), "AppFolder": appFolder,
         "FromPid": Int(fromPid)]
    }

    /// The URLs of an accepted request (empty for `activate`), or nil when it is for another data folder (F-2).
    public static func accept(_ info: [AnyHashable: Any]?, canonicalFolder: String?) -> [URL]? {
        guard let info, let folder = info["AppFolder"] as? String, let mine = canonicalFolder,
              NetText.equalsIgnoreCase(folder, mine) else { return nil }
        let action = info["Action"] as? String ?? "activate"
        guard action == "open" else { return [] }
        return (info["URLs"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
    }
}

/// DATA-178 housekeeping and the DATA-184 temp-file evidence.
public enum PersistTempFiles {
    public static let staleAge: TimeInterval = 10 * 60

    /// `^(data\.json|settings\.json)\.[0-9a-f]{32}\.tmp$`, `qrsync-baseline.json.tmp`, `qrsync-baseline.json.{32hex}.tmp`.
    public static func isAtomicTemp(_ name: String) -> Bool {
        if name == "qrsync-baseline.json.tmp" { return true }
        for base in ["data.json.", "settings.json.", "qrsync-baseline.json."] where name.hasPrefix(base) && name.hasSuffix(".tmp") {
            let mid = name.dropFirst(base.count).dropLast(4)
            if mid.count == 32, mid.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) { return true }
        }
        return false
    }

    /// Deletes matching top-level files older than 10 minutes; returns the deleted names. Failures are ignored.
    @discardableResult
    public static func cleanStale(in folder: URL, now: Date) -> [String] {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: []) else { return [] }
        var deleted: [String] = []
        for k in kids where isAtomicTemp(k.lastPathComponent) {
            guard let m = (try? k.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now.timeIntervalSince(m) > staleAge else { continue }
            if (try? fm.removeItem(at: k)) != nil { deleted.append(k.lastPathComponent) }
        }
        return deleted.sorted()
    }

    /// A `data.json.{32hex}.tmp` at the top level (one this process did not create — called before any write).
    public static func hasForeignDataTemp(in folder: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.contains { $0.hasPrefix("data.json.") && isAtomicTemp($0) }
    }
}
