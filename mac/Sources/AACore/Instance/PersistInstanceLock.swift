// Spec: 01 MP DATA-170 (flock on AppFolder/.aa.lock; never deleted/renamed/replaced), DATA-176 (stale lock after a
//       crash), DATA-177 (lease mode on network volumes), §MP.3.1 (acquire), §MP.3.2 (readRecord/writeRecord),
//       §MP.3.3 (classify / leaseHeld / thisHostId), §MP.3.7 (constants), §MP.4.1 (record format), MP.7.1/7.3 vectors.
import Foundation
import CryptoKit
import AppKit
import Darwin

// MARK: Record (§MP.4.1)

/// The JSON claim kept in `.aa.lock` (and in the per-user external-file locks, plus `DataFile`).
public struct PersistLockRecord: Sendable, Equatable {
    public var format = 1
    public var mode = "Owner"
    public var lockKind = "flock"
    public var pid: Int32 = 0
    public var processStartUtc: Date?
    public var acquiredUtc: Date?
    public var heartbeatUtc: Date?
    public var hostId = ""
    public var host = ""
    public var user = ""
    public var uid: UInt32 = 0
    public var appPath = ""
    public var version = "dev"
    public var platform = "macOS"
    public var appFolder = ""
    public var dataFile: String?

    public init(format: Int = 1, mode: String = "Owner", lockKind: String = "flock", pid: Int32 = 0,
                processStartUtc: Date? = nil, acquiredUtc: Date? = nil, heartbeatUtc: Date? = nil, hostId: String = "",
                host: String = "", user: String = "", uid: UInt32 = 0, appPath: String = "", version: String = "dev",
                platform: String = "macOS", appFolder: String = "", dataFile: String? = nil) {
        self.format = format; self.mode = mode; self.lockKind = lockKind; self.pid = pid
        self.processStartUtc = processStartUtc; self.acquiredUtc = acquiredUtc; self.heartbeatUtc = heartbeatUtc
        self.hostId = hostId; self.host = host; self.user = user; self.uid = uid; self.appPath = appPath
        self.version = version; self.platform = platform; self.appFolder = appFolder; self.dataFile = dataFile
    }

    static func utcText(_ d: Date) -> String { NetDateTime(date: d, kind: .utc).jsonString() }
    static func utcDate(_ s: String?) -> Date? {
        guard let s, let v = NetDateTime(parsing: s) else { return nil }
        return v.foundationDate()
    }

    /// Compact UTF-8 JSON, keys in the §MP.4.1 order, non-ASCII escaped (the app's JSON writer).
    public func jsonData() -> Data {
        var o = JSONObject()
        o.set("Format", .number(JSONNumber(format)))
        o.set("Mode", .string(mode))
        o.set("LockKind", .string(lockKind))
        o.set("Pid", .number(JSONNumber(Int(pid))))
        if let processStartUtc { o.set("ProcessStartUtc", .string(Self.utcText(processStartUtc))) }
        if let acquiredUtc { o.set("AcquiredUtc", .string(Self.utcText(acquiredUtc))) }
        if let heartbeatUtc { o.set("HeartbeatUtc", .string(Self.utcText(heartbeatUtc))) }
        o.set("HostId", .string(hostId))
        o.set("Host", .string(host))
        o.set("User", .string(user))
        o.set("Uid", .number(JSONNumber(Int(uid))))
        o.set("AppPath", .string(appPath))
        o.set("Version", .string(version))
        o.set("Platform", .string(platform))
        o.set("AppFolder", .string(appFolder))
        if let dataFile { o.set("DataFile", .string(dataFile)) }
        return (try? JSONWriter.data(.object(o))) ?? Data()
    }

    /// Tolerant reader: unknown keys ignored, missing keys default; nil when not a JSON object.
    public init?(json: Data) {
        guard let root = try? JSONParser.parse(json), let o = root.objectValue else { return nil }
        func int(_ k: String) -> Int? { o[k]?.numberValue?.intValue }
        func str(_ k: String) -> String? { o[k]?.stringValue }
        format = int("Format") ?? 1
        mode = str("Mode") ?? "Owner"
        lockKind = str("LockKind") ?? "flock"
        pid = Int32(int("Pid") ?? 0)
        processStartUtc = Self.utcDate(str("ProcessStartUtc"))
        acquiredUtc = Self.utcDate(str("AcquiredUtc"))
        heartbeatUtc = Self.utcDate(str("HeartbeatUtc"))
        hostId = str("HostId") ?? ""
        host = str("Host") ?? ""
        user = str("User") ?? ""
        uid = UInt32(max(0, int("Uid") ?? 0))
        appPath = str("AppPath") ?? ""
        version = str("Version") ?? "dev"
        platform = str("Platform") ?? "macOS"
        appFolder = str("AppFolder") ?? ""
        dataFile = str("DataFile")
    }
}

// MARK: Classification (§MP.3.3)

/// Who holds a lock, as far as the record tells.
public enum PersistHolder: Sendable, Equatable {
    case unknown, released, dead
    case sameUser(pid: Int32, started: Date?)
    case sameUserNoApp(pid: Int32, started: Date?)
    case otherUser(String)
    case otherHostFresh(host: String, heartbeat: Date)
    case otherHostStale(host: String, heartbeat: Date)
}

/// Process facts the classifier needs (injected in tests, MP.7 "How to test").
public protocol PersistProcessProbe: Sendable {
    /// `kill(pid, 0) == 0 || errno == EPERM`.
    func isAlive(_ pid: Int32) -> Bool
    /// `proc_pidinfo(PROC_PIDTBSDINFO)` start time; nil when unavailable.
    func startTime(_ pid: Int32) -> Date?
    /// `NSRunningApplication(processIdentifier:)` is non-nil.
    func hasRunningApplication(_ pid: Int32) -> Bool
}

public struct PersistLiveProcessProbe: PersistProcessProbe {
    public init() {}
    public func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
    public func startTime(_ pid: Int32) -> Date? { PersistHost.processStart(pid) }
    public func hasRunningApplication(_ pid: Int32) -> Bool { NSRunningApplication(processIdentifier: pid) != nil }
}

/// Everything the lock logic reads from the outside world (injectable).
public struct PersistLockEnvironment: Sendable {
    public var probe: PersistProcessProbe
    public var now: @Sendable () -> Date
    public var hostId: String
    public var uid: UInt32
    public var isNetworkVolume: @Sendable (URL) -> Bool
    /// The record fields describing this process (pid, start, host, user, app path, version).
    public var me: PersistLockRecord

    public init(probe: PersistProcessProbe, now: @escaping @Sendable () -> Date, hostId: String, uid: UInt32,
                isNetworkVolume: @escaping @Sendable (URL) -> Bool, me: PersistLockRecord) {
        self.probe = probe; self.now = now; self.hostId = hostId; self.uid = uid
        self.isNetworkVolume = isNetworkVolume; self.me = me
    }

    public static var live: PersistLockEnvironment {
        PersistLockEnvironment(probe: PersistLiveProcessProbe(), now: { Date() }, hostId: PersistHost.thisHostId(),
                               uid: getuid(), isNetworkVolume: { PersistHost.isNetworkVolume($0) }, me: PersistHost.myRecord())
    }
}

public enum PersistLockConstants {
    public static let alertRecheck: TimeInterval = 1          // DATA-172
    public static let upgradePoll: TimeInterval = 5           // DATA-175
    public static let heartbeat: TimeInterval = 30            // DATA-177
    public static let leaseFreshness: TimeInterval = 90       // DATA-177, §MP.3.3
    public static let startTolerance: TimeInterval = 2        // §MP.3.3
    public static let recordRetries = 3                       // §MP.3.2 (20 ms apart)
    public static let recordMaxBytes = 64 * 1024
}

public enum PersistLockClassifier {
    /// §MP.3.3 `classify(rec)`; `lockMTime` is used for an unreadable record or a missing heartbeat.
    public static func classify(_ rec: PersistLockRecord?, env: PersistLockEnvironment, lockMTime: Date?) -> PersistHolder {
        guard let rec else { return .unknown }
        if rec.mode == "Released" { return .released }
        if rec.hostId == env.hostId {
            guard env.probe.isAlive(rec.pid) else { return .dead }
            if let start = env.probe.startTime(rec.pid), let claimed = rec.processStartUtc,
               abs(start.timeIntervalSince(claimed)) > PersistLockConstants.startTolerance {
                return .dead                                                            // pid reused
            }
            if rec.uid != env.uid { return .otherUser(rec.user) }
            return env.probe.hasRunningApplication(rec.pid)
                ? .sameUser(pid: rec.pid, started: rec.processStartUtc)
                : .sameUserNoApp(pid: rec.pid, started: rec.processStartUtc)
        }
        let hb = rec.heartbeatUtc ?? lockMTime ?? .distantPast
        let age = env.now().timeIntervalSince(hb)
        return age <= PersistLockConstants.leaseFreshness
            ? .otherHostFresh(host: rec.host, heartbeat: hb) : .otherHostStale(host: rec.host, heartbeat: hb)
    }

    /// §MP.3.3 `leaseHeld(rec)`.
    public static func leaseHeld(_ rec: PersistLockRecord?, env: PersistLockEnvironment, lockMTime: Date?) -> Bool {
        let c = classify(rec, env: env, lockMTime: lockMTime)
        switch c {
        case .released, .dead: return false
        case .unknown:
            guard let m = lockMTime else { return false }
            return env.now().timeIntervalSince(m) <= PersistLockConstants.leaseFreshness
        default: return true
        }
    }
}

// MARK: Host facts

public enum PersistHost {
    /// First 16 lowercase hex digits of SHA-256 over the upper-case `gethostuuid()` UUID string (§MP.3.3).
    public static func thisHostId() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        var wait = timespec(tv_sec: 1, tv_nsec: 0)
        let ok = bytes.withUnsafeMutableBufferPointer { gethostuuid($0.baseAddress, &wait) } == 0
        let text: String
        if ok {
            let u = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
            text = u.uuidString.uppercased()
        } else {
            text = SettingsStore.defaultIdentity()
        }
        return String(sha256Hex(Data(text.utf8)).prefix(16))
    }

    public static func sha256Hex(_ d: Data) -> String {
        SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    /// `proc_pidinfo(PROC_PIDTBSDINFO)` start time.
    public static func processStart(_ pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }

    /// `statfs` without `MNT_LOCAL` (smbfs, nfs, afpfs, webdav, …).
    public static func isNetworkVolume(_ url: URL) -> Bool {
        var s = statfs()
        guard statfs(url.path, &s) == 0 else { return false }
        return (s.f_flags & UInt32(MNT_LOCAL)) == 0
    }

    /// This process as a record (pid, start, host id/name, user, uid, app path, version).
    public static func myRecord() -> PersistLockRecord {
        let bundle = Bundle.main
        let isApp = bundle.bundleURL.pathExtension == "app"
        let appPath = isApp ? bundle.bundlePath : (bundle.executablePath ?? CommandLine.arguments.first ?? "")
        var version = "dev"
        if let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            version = "\(short) (\(build))"
        }
        return PersistLockRecord(pid: getpid(), processStartUtc: processStart(getpid()), hostId: thisHostId(),
                                 host: SettingsStore.defaultIdentity(), user: NSUserName(), uid: getuid(),
                                 appPath: appPath, version: version)
    }

    /// `realpath` (falls back to the standardised path when the file does not exist yet).
    public static func canonicalPath(_ url: URL) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(url.path, &buf) != nil {
            return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

// MARK: The lock file (§MP.3.1, §MP.3.2)

/// One advisory lock file. All methods are thread-safe (one internal lock).
public final class PersistInstanceLock: @unchecked Sendable {
    public enum Outcome: Sendable, Equatable {
        case owner
        case blocked(record: PersistLockRecord?, holder: PersistHolder, lease: Bool)
        case unguarded(String)
    }

    public let lockURL: URL
    public let env: PersistLockEnvironment
    /// Fields added to every record this lock writes (e.g. `AppFolder`, `DataFile`).
    public let decorate: @Sendable (inout PersistLockRecord) -> Void

    private let lock = NSLock()
    private var fd: Int32 = -1
    private var writable = false
    private var flocked = false
    private var owner = false
    private var lease = false
    private var acquired: Date?
    private var lastConfirmed: Date?

    public init(lockURL: URL, env: PersistLockEnvironment, decorate: @escaping @Sendable (inout PersistLockRecord) -> Void = { _ in }) {
        self.lockURL = lockURL; self.env = env; self.decorate = decorate
    }

    deinit { if fd >= 0 { close(fd) } }

    public var isOwner: Bool { lock.lock(); defer { lock.unlock() }; return owner }
    public var isLeaseMode: Bool { lock.lock(); defer { lock.unlock() }; return lease }

    /// §MP.3.1. On `.owner` the descriptor stays open for the process lifetime.
    public func acquire() -> Outcome {
        lock.lock(); defer { lock.unlock() }
        return acquireLocked(force: false)
    }

    /// "Take Over…" (DATA-177): claims the folder even though a fresh foreign lease exists.
    public func takeOver() -> Outcome {
        lock.lock(); defer { lock.unlock() }
        return acquireLocked(force: true)
    }

    private func acquireLocked(force: Bool) -> Outcome {
        if owner { return .owner }
        let folder = lockURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var d = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o666)
        var canWrite = true
        if d < 0, errno == EACCES || errno == EPERM {
            d = open(lockURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            canWrite = false
        }
        if d < 0 { return .unguarded(String(cString: strerror(errno))) }
        var network = env.isNetworkVolume(folder)
        var gotFlock = false
        while true {
            if flock(d, LOCK_EX | LOCK_NB) == 0 { gotFlock = true; break }
            let e = errno
            if e == EINTR { continue }
            if e == EWOULDBLOCK {
                if force { network = true; break }
                let rec = PersistInstanceLock.readRecord(d)
                let holder = PersistLockClassifier.classify(rec, env: env, lockMTime: PersistInstanceLock.mtime(d))
                close(d)
                return .blocked(record: rec, holder: holder, lease: network)
            }
            if e == ENOTSUP || e == EOPNOTSUPP { network = true; break }
            close(d)
            return .unguarded(String(cString: strerror(e)))
        }
        if network, !force {
            let rec = PersistInstanceLock.readRecord(d)
            let m = PersistInstanceLock.mtime(d)
            if PersistLockClassifier.leaseHeld(rec, env: env, lockMTime: m) {
                if gotFlock { flock(d, LOCK_UN) }
                let holder = PersistLockClassifier.classify(rec, env: env, lockMTime: m)
                close(d)
                return .blocked(record: rec, holder: holder, lease: true)
            }
        }
        fd = d; writable = canWrite; flocked = gotFlock; owner = true; lease = network
        acquired = env.now(); lastConfirmed = acquired
        writeRecordLocked(mode: "Owner")
        return .owner
    }

    /// DATA-172 retry / DATA-175 upgrade poll: one non-blocking attempt; true when this process is now the owner.
    public func tryAcquire() -> Bool {
        if case .owner = acquire() { return true }
        return false
    }

    /// DATA-175 "Stay Read-Only": gives the lock back (the file stays; the record is not rewritten).
    public func relinquish() {
        lock.lock(); defer { lock.unlock() }
        guard fd >= 0 else { return }
        if flocked { flock(fd, LOCK_UN) }
        close(fd)
        fd = -1; owner = false; flocked = false; lease = false
    }

    /// Clean quit (§MP.3.6): `Mode: "Released"`, then the descriptor is closed (the kernel drops the flock).
    public func release() {
        lock.lock(); defer { lock.unlock() }
        guard fd >= 0 else { return }
        if owner { writeRecordLocked(mode: "Released") }
        close(fd)
        fd = -1; owner = false; flocked = false; lease = false
    }

    /// Lease heartbeat: rewrites `HeartbeatUtc` in place. Returns false (and writes nothing) when another
    /// host's process has taken over the record meanwhile.
    @discardableResult
    public func heartbeat() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard owner, fd >= 0 else { return false }
        if let rec = PersistInstanceLock.readRecord(fd), !isMine(rec) { return false }
        writeRecordLocked(mode: "Owner")
        lastConfirmed = env.now()
        return true
    }

    /// Lease mode: before a write after a gap of more than 90 s (and after wake), re-read the record. False when
    /// another computer has taken over. Always true outside lease mode.
    public func confirmLease(force: Bool = false) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard lease, owner, fd >= 0 else { return true }
        let now = env.now()
        if !force, let last = lastConfirmed, now.timeIntervalSince(last) <= PersistLockConstants.leaseFreshness { return true }
        guard let rec = PersistInstanceLock.readRecord(fd) else { lastConfirmed = now; return true }
        if isMine(rec) { lastConfirmed = now; return true }
        return false
    }

    /// The record currently in the file (nil when unreadable).
    public func currentRecord() -> PersistLockRecord? {
        lock.lock(); defer { lock.unlock() }
        if fd >= 0 { return PersistInstanceLock.readRecord(fd) }
        let d = open(lockURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard d >= 0 else { return nil }
        defer { close(d) }
        return PersistInstanceLock.readRecord(d)
    }

    private func isMine(_ rec: PersistLockRecord) -> Bool {
        rec.mode == "Released" || (rec.hostId == env.hostId && rec.pid == env.me.pid)
    }

    private func writeRecordLocked(mode: String) {
        guard fd >= 0, writable else { return }
        var r = env.me
        r.mode = mode
        r.lockKind = lease ? "lease" : "flock"
        r.acquiredUtc = acquired
        r.heartbeatUtc = env.now()
        decorate(&r)
        let bytes = r.jsonData()
        _ = bytes.withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, 0) }
        ftruncate(fd, off_t(bytes.count))
    }

    /// §MP.3.2: `pread` the whole file (≤ 64 KiB), parse; 3 retries 20 ms apart; nil when still unreadable.
    static func readRecord(_ d: Int32) -> PersistLockRecord? {
        for attempt in 0...PersistLockConstants.recordRetries {
            if attempt > 0 { usleep(20_000) }
            var st = stat()
            guard fstat(d, &st) == 0 else { return nil }
            let size = Int(st.st_size)
            if size == 0 || size > PersistLockConstants.recordMaxBytes { return nil }
            var buf = [UInt8](repeating: 0, count: size)
            let n = buf.withUnsafeMutableBytes { pread(d, $0.baseAddress, size, 0) }
            if n == size, let rec = PersistLockRecord(json: Data(buf)) { return rec }
        }
        return nil
    }

    static func mtime(_ d: Int32) -> Date? {
        var st = stat()
        guard fstat(d, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9)
    }
}
