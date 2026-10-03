// TV: 01 MP.7.1 (guard G-1…G-11), MP.7.2 (F-1…F-3), MP.7.3 (lease table), MP.7.7 (external file E-1/E-2),
//     MP.7.8 (temp-file cleanup), MP.7.9 (shared-with-Windows evidence), §MP.4.1 (record), DATA-172 texts, DATA-175.
import Foundation
import Testing
import Darwin
@testable import AACore

/// A process probe whose answers the test sets.
struct PersistFakeProbe: PersistProcessProbe {
    var alive: Bool = true
    var start: Date? = nil
    var hasApp: Bool = true
    func isAlive(_ pid: Int32) -> Bool { alive }
    func startTime(_ pid: Int32) -> Date? { start }
    func hasRunningApplication(_ pid: Int32) -> Bool { hasApp }
}

@MainActor
@Suite("W-PERSIST instance guard", .serialized)
struct PersistInstanceGuardTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_790_000_000)          // 2026-09-21
    nonisolated static let hostH = "9f86d081884c7d65"

    private func env(probe: PersistProcessProbe = PersistFakeProbe(), network: Bool = false, pid: Int32 = 4242,
                     host: String = PersistInstanceGuardTests.hostH, uid: UInt32 = 501,
                     now: Date = PersistInstanceGuardTests.now) -> PersistLockEnvironment {
        var me = PersistLockRecord(pid: pid, processStartUtc: now.addingTimeInterval(-60), hostId: host, host: "Eris-MacBook-Pro",
                                   user: "eriskay", uid: uid, appPath: "/Applications/AA.app", version: "1.0 (42)")
        me.appFolder = "/tmp/T"
        return PersistLockEnvironment(probe: probe, now: { now }, hostId: host, uid: uid, isNetworkVolume: { _ in network }, me: me)
    }

    private func lock(_ folder: URL, _ e: PersistLockEnvironment) -> PersistInstanceLock {
        PersistInstanceLock(lockURL: folder.appending(path: ".aa.lock"), env: e)
    }

    @Test("G-11 two open() calls on one file conflict under flock in one process")
    func inProcessFlock() throws {
        let t = TempFolder("persist-g11")
        let path = t.file(".aa.lock").path
        let fd1 = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        defer { close(fd1) }
        #expect(flock(fd1, LOCK_EX | LOCK_NB) == 0)
        let fd2 = open(path, O_RDWR | O_CLOEXEC)
        defer { close(fd2) }
        #expect(flock(fd2, LOCK_EX | LOCK_NB) == -1)
        #expect(errno == EWOULDBLOCK)
        close(fd1)
        #expect(flock(fd2, LOCK_EX | LOCK_NB) == 0)
    }

    @Test("G-1 a second launch is refused; the record and the folder are untouched; the alert text")
    func secondLaunchRefused() throws {
        let t = TempFolder("persist-g1")
        let p1 = lock(t.url, env(pid: 4242))
        #expect(p1.acquire() == .owner)
        let before = try t.read(".aa.lock")
        let listing = try FileManager.default.contentsOfDirectory(atPath: t.url.path)
        let p2 = lock(t.url, env(pid: 5000))
        guard case let .blocked(rec, holder, lease) = p2.acquire() else { Issue.record("not blocked"); return }
        #expect(rec?.pid == 4242)
        #expect(rec?.mode == "Owner")
        #expect(rec?.lockKind == "flock")
        #expect(lease == false)
        #expect(holder == .sameUser(pid: 4242, started: PersistInstanceGuardTests.now.addingTimeInterval(-60)))
        #expect(try t.read(".aa.lock") == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: t.url.path) == listing)
        let info = PersistBlockedInfo(target: .folder(URL(fileURLWithPath: "/Users/u/Library/Application Support/AA")),
                                      record: rec, holder: holder, lease: lease)
        let zone = TimeZone(identifier: "UTC")!
        let alert = PersistInstanceAlertText.make(info, now: PersistInstanceGuardTests.now, zone: zone, home: "/Users/u")
        let started = PersistInstanceAlertText.time(PersistInstanceGuardTests.now.addingTimeInterval(-60),
                                                    now: PersistInstanceGuardTests.now, zone: zone)
        #expect(alert.messageText == "AA is already running with this data folder")
        #expect(alert.informativeText == "Another copy of AA (started \(started), process 4242) is using:\n\n~/Library/Application Support/AA\n\nOnly one copy of AA can edit a data folder at a time — two copies would overwrite each other's changes. Switch to the copy that is already running, or open this one read-only to look without saving.")
        #expect(alert.buttons.map(\.rawValue) == ["Switch to Running AA", "Open Read-Only", "Quit"])
        p1.release()
    }

    @Test("G-3 a clean quit leaves Mode Released; the file stays; the next acquire owns it (same inode)")
    func cleanQuit() throws {
        let t = TempFolder("persist-g3")
        let p1 = lock(t.url, env())
        #expect(p1.acquire() == .owner)
        let ino = try FileManager.default.attributesOfItem(atPath: t.file(".aa.lock").path)[.systemFileNumber] as? Int
        p1.release()
        let rec = PersistLockRecord(json: try t.read(".aa.lock"))
        #expect(rec?.mode == "Released")
        let p2 = lock(t.url, env(pid: 7))
        #expect(p2.acquire() == .owner)
        #expect(PersistLockRecord(json: try t.read(".aa.lock"))?.pid == 7)
        #expect(try FileManager.default.attributesOfItem(atPath: t.file(".aa.lock").path)[.systemFileNumber] as? Int == ino)
        p2.release()
    }

    @Test("G-5 symlinked path and G-6 case variant compete for the same lock; G-7 other folders do not")
    func samFolderDifferentPaths() throws {
        let t = TempFolder("persist-g5")
        let real = t.file("AA")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = t.file("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let p1 = lock(real, env())
        #expect(p1.acquire() == .owner)
        if case .blocked = lock(link, env(pid: 9)).acquire() {} else { Issue.record("symlink path not blocked") }
        let caseInsensitive = (try? real.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames == false
        if caseInsensitive {
            let variant = t.file("aa")
            if case .blocked = lock(variant, env(pid: 9)).acquire() {} else { Issue.record("case variant not blocked") }
        }
        let other = t.file("Other")
        let p3 = lock(other, env(pid: 10))
        #expect(p3.acquire() == .owner)
        p1.release(); p3.release()
    }

    @Test("G-8 a planted symlink at .aa.lock → unguarded (ELOOP)")
    func plantedSymlink() throws {
        let t = TempFolder("persist-g8")
        let target = TempFolder("persist-elsewhere")
        try FileManager.default.createSymbolicLink(at: t.file(".aa.lock"), withDestinationURL: target.file("x"))
        let outcome = lock(t.url, env()).acquire()
        #expect(outcome == .unguarded(String(cString: strerror(ELOOP))))
        #expect(outcome == .unguarded("Too many levels of symbolic links"))
    }

    @Test("G-2 a lock held by a killed process is reclaimed silently (spawned helper)")
    func staleAfterKill() async throws {
        let t = TempFolder("persist-g2")
        let lockPath = t.file(".aa.lock").path
        FileManager.default.createFile(atPath: lockPath, contents: nil)
        let ino = try FileManager.default.attributesOfItem(atPath: lockPath)[.systemFileNumber] as? Int
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        helper.arguments = ["-e", "use Fcntl qw(:flock); open(my $f, '+<', $ARGV[0]) or die; flock($f, LOCK_EX) or die; $|=1; print \"locked\\n\"; sleep 60;", lockPath]
        let out = Pipe()
        helper.standardOutput = out
        try helper.run()
        _ = out.fileHandleForReading.availableData                         // wait for "locked"
        if case .blocked = lock(t.url, env()).acquire() {} else { Issue.record("helper lock not seen") }
        kill(helper.processIdentifier, SIGKILL)
        helper.waitUntilExit()
        let p2 = lock(t.url, env(pid: 77))
        #expect(p2.acquire() == .owner)
        #expect(PersistLockRecord(json: try t.read(".aa.lock"))?.pid == 77)
        #expect(try FileManager.default.attributesOfItem(atPath: lockPath)[.systemFileNumber] as? Int == ino)
        p2.release()
    }

    @Test("G-4 the lock descriptor is not inherited by child processes (O_CLOEXEC)")
    func noInheritance() throws {
        let t = TempFolder("persist-g4")
        let p1 = lock(t.url, env())
        #expect(p1.acquire() == .owner)
        var pid: pid_t = 0
        let args: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sleep"), strdup("30"), nil]
        defer { args.forEach { free($0) } }
        #expect(posix_spawn(&pid, "/bin/sleep", nil, nil, args, environ) == 0)
        defer { kill(pid, SIGKILL); var s: Int32 = 0; waitpid(pid, &s, 0) }
        p1.release()
        let p2 = lock(t.url, env(pid: 88))
        #expect(p2.acquire() == .owner)
        p2.release()
    }

    @Test("MP.7.3 lease table (classify / leaseHeld)")
    func leaseTable() {
        let now = PersistInstanceGuardTests.now
        func rec(_ mode: String = "Owner", host: String, pid: Int32 = 4242, uid: UInt32 = 501, start: Date? = nil,
                 hb: Date? = nil, user: String = "ana") -> PersistLockRecord {
            PersistLockRecord(mode: mode, lockKind: "lease", pid: pid, processStartUtc: start, heartbeatUtc: hb, hostId: host,
                              host: "Bridge-Mac", user: user, uid: uid)
        }
        let H = PersistInstanceGuardTests.hostH
        let start = now.addingTimeInterval(-3600)
        // Released → free.
        #expect(!PersistLockClassifier.leaseHeld(rec("Released", host: "x"), env: env(), lockMTime: now))
        // Same host, dead pid → .dead.
        #expect(PersistLockClassifier.classify(rec(host: H), env: env(probe: PersistFakeProbe(alive: false)), lockMTime: nil) == .dead)
        // Same host, pid reused (start differs by 10 s) → .dead.
        #expect(PersistLockClassifier.classify(rec(host: H, start: start),
                                               env: env(probe: PersistFakeProbe(start: start.addingTimeInterval(10))), lockMTime: nil) == .dead)
        // Same host, alive, same uid, same start → held .sameUser.
        #expect(PersistLockClassifier.classify(rec(host: H, start: start), env: env(probe: PersistFakeProbe(start: start)),
                                               lockMTime: nil) == .sameUser(pid: 4242, started: start))
        // Same host, EPERM (alive), other uid → held .otherUser.
        #expect(PersistLockClassifier.classify(rec(host: H, uid: 502, start: start), env: env(probe: PersistFakeProbe(start: start)),
                                               lockMTime: nil) == .otherUser("ana"))
        // Same user without an app bundle (swift run) → .sameUserNoApp.
        #expect(PersistLockClassifier.classify(rec(host: H), env: env(probe: PersistFakeProbe(hasApp: false)), lockMTime: nil)
                == .sameUserNoApp(pid: 4242, started: nil))
        // Other host, heartbeat 30 s → fresh; 91 s → stale.
        let fresh = now.addingTimeInterval(-30), stale = now.addingTimeInterval(-91)
        #expect(PersistLockClassifier.classify(rec(host: "other", hb: fresh), env: env(), lockMTime: nil)
                == .otherHostFresh(host: "Bridge-Mac", heartbeat: fresh))
        #expect(PersistLockClassifier.classify(rec(host: "other", hb: stale), env: env(), lockMTime: nil)
                == .otherHostStale(host: "Bridge-Mac", heartbeat: stale))
        #expect(PersistLockClassifier.leaseHeld(rec(host: "other", hb: stale), env: env(), lockMTime: nil))
        // Unreadable record: lock-file mtime 10 s → held; 10 min → free.
        #expect(PersistLockClassifier.leaseHeld(nil, env: env(), lockMTime: now.addingTimeInterval(-10)))
        #expect(!PersistLockClassifier.leaseHeld(nil, env: env(), lockMTime: now.addingTimeInterval(-600)))
    }

    @Test("Lease mode on a network volume: fresh foreign claim → blocked; stale → Take Over default; take over writes ours")
    func leaseMode() throws {
        let t = TempFolder("persist-lease")
        let now = PersistInstanceGuardTests.now
        var other = PersistLockRecord(lockKind: "lease", pid: 999, heartbeatUtc: now.addingTimeInterval(-30), hostId: "other",
                                      host: "Engine-Mac", user: "chief", uid: 501)
        try other.jsonData().write(to: t.file(".aa.lock"))
        let l = lock(t.url, env(network: true))
        guard case let .blocked(rec, holder, lease) = l.acquire() else { Issue.record("not blocked"); return }
        #expect(lease)
        #expect(rec?.host == "Engine-Mac")
        let freshText = PersistInstanceAlertText.make(PersistBlockedInfo(target: .folder(t.url), record: rec, holder: holder, lease: true),
                                                      now: now, zone: .current)
        #expect(freshText.buttons == [.openReadOnly, .quit, .takeOver])
        #expect(freshText.informativeText.contains(" on “Engine-Mac” (last seen "))
        other.heartbeatUtc = now.addingTimeInterval(-120)
        try other.jsonData().write(to: t.file(".aa.lock"))
        guard case let .blocked(rec2, holder2, _) = l.acquire() else { Issue.record("not blocked"); return }
        let staleText = PersistInstanceAlertText.make(PersistBlockedInfo(target: .folder(t.url), record: rec2, holder: holder2, lease: true),
                                                      now: now, zone: .current)
        #expect(staleText.buttons == [.takeOver, .openReadOnly, .quit])
        #expect(staleText.informativeText.contains("\n\nThat copy hasn't updated its claim since "))
        #expect(staleText.informativeText.hasSuffix("If that computer crashed or was switched off, you can take over."))
        #expect(l.takeOver() == .owner)
        let mine = try #require(PersistLockRecord(json: try t.read(".aa.lock")))
        #expect(mine.pid == 4242)
        #expect(mine.lockKind == "lease")
        #expect(mine.mode == "Owner")
        #expect(l.heartbeat())
        l.release()
        // The very first launch on a network folder (no .aa.lock yet, an empty file just created) is not blocked by
        // its own empty file; a garbage record with a fresh mtime still counts as held.
        let fresh = TempFolder("persist-lease-first")
        let first = lock(fresh.url, env(network: true, now: Date()))
        #expect(first.acquire() == .owner)
        #expect(PersistLockRecord(json: try fresh.read(".aa.lock"))?.lockKind == "lease")
        first.release()
        let garbage = TempFolder("persist-lease-garbage")
        try Data("{\"Mode\":\"Own".utf8).write(to: garbage.file(".aa.lock"))
        if case .blocked(nil, .unknown, true) = lock(garbage.url, env(network: true, now: Date())).acquire() {} else {
            Issue.record("a fresh unreadable claim was not treated as held")
        }
        #expect(l.takeOver() == .owner)
        // Another computer takes over → the heartbeat notices and confirmLease reports it.
        try other.jsonData().write(to: t.file(".aa.lock"))
        #expect(!l.heartbeat())
        #expect(!l.confirmLease(force: true))
        l.release()
    }

    @Test("§MP.4.1 record format: key order, UTC dates, tolerant reading")
    func recordFormat() throws {
        let d = Date(timeIntervalSince1970: 1_790_000_000.25)
        let r = PersistLockRecord(pid: 4242, processStartUtc: d, acquiredUtc: d, heartbeatUtc: d, hostId: "9f86d081884c7d65",
                                  host: "Eris-MacBook-Pro", user: "eriskay", uid: 501, appPath: "/Applications/AA.app",
                                  version: "1.0 (42)", appFolder: "/Users/eriskay/Library/Application Support/AA")
        let text = String(decoding: r.jsonData(), as: UTF8.self)
        #expect(text.hasPrefix(#"{"Format":1,"Mode":"Owner","LockKind":"flock","Pid":4242,"ProcessStartUtc":"2026-09-21T"#))
        #expect(text.contains(#".25Z","AcquiredUtc":"#))
        #expect(text.hasSuffix(#""HostId":"9f86d081884c7d65","Host":"Eris-MacBook-Pro","User":"eriskay","Uid":501,"AppPath":"/Applications/AA.app","Version":"1.0 (42)","Platform":"macOS","AppFolder":"/Users/eriskay/Library/Application Support/AA"}"#))
        let back = try #require(PersistLockRecord(json: r.jsonData()))
        #expect(back.pid == 4242)
        #expect(abs((back.heartbeatUtc ?? .distantPast).timeIntervalSince(d)) < 0.001)
        let tolerant = try #require(PersistLockRecord(json: Data(#"{"Pid":7,"Extra":true}"#.utf8)))
        #expect(tolerant.pid == 7 && tolerant.mode == "Owner" && tolerant.hostId.isEmpty)
        #expect(PersistLockRecord(json: Data("[1]".utf8)) == nil)
        #expect(PersistHost.thisHostId().count == 16)
    }

    @Test("F-1/F-2 forwarded request payload; other folders are ignored")
    func forwardPayload() {
        let urls = [URL(fileURLWithPath: "/tmp/x.aaz")]
        let info = PersistInstanceRequest.userInfo(documents: urls, appFolder: "/T", fromPid: 5)
        #expect(info["Action"] as? String == "open")
        #expect(info["URLs"] as? [String] == ["/tmp/x.aaz"])
        #expect(info["AppFolder"] as? String == "/T")
        #expect(info["FromPid"] as? Int == 5)
        #expect(PersistInstanceRequest.accept(info, canonicalFolder: "/T") == urls)
        #expect(PersistInstanceRequest.accept(info, canonicalFolder: "/Other") == nil)
        let activate = PersistInstanceRequest.userInfo(documents: [], appFolder: "/T", fromPid: 5)
        #expect(activate["Action"] as? String == "activate")
        #expect(PersistInstanceRequest.accept(activate, canonicalFolder: "/T") == [])
        #expect(PersistInstanceRequest.accept(nil, canonicalFolder: "/T") == nil)
    }

    @Test("F-3 another user's copy: no Switch button; the holder and choice texts")
    func otherUserText() {
        let info = PersistBlockedInfo(target: .folder(URL(fileURLWithPath: "/Users/Shared/AA")), record: nil,
                                      holder: .otherUser("ana"), lease: false)
        let a = PersistInstanceAlertText.make(info, now: PersistInstanceGuardTests.now, zone: .current, home: "/Users/u")
        #expect(a.buttons.map(\.rawValue) == ["Open Read-Only", "Quit"])
        #expect(a.informativeText.contains("(running for the user “ana” on this Mac)"))
        #expect(a.informativeText.contains("\n\n/Users/Shared/AA\n\n"))
        #expect(a.informativeText.hasSuffix("You can open this one read-only to look without saving, or quit."))
        let unknown = PersistInstanceAlertText.make(PersistBlockedInfo(target: .folder(URL(fileURLWithPath: "/T")), record: nil,
                                                                       holder: .unknown, lease: false),
                                                    now: PersistInstanceGuardTests.now, zone: .current)
        #expect(unknown.informativeText.hasPrefix("Another copy of AA is using:"))
        let ext = PersistInstanceAlertText.make(PersistBlockedInfo(target: .externalFile(URL(fileURLWithPath: "/tmp/shared.json")),
                                                                   record: nil, holder: .otherUser("ana"), lease: false),
                                                now: PersistInstanceGuardTests.now, zone: .current)
        #expect(ext.messageText == "The data file is open in another copy of AA")
        #expect(ext.informativeText == "“shared.json” is being edited by another copy of AA (running for the user “ana” on this Mac). Two copies would overwrite each other's changes. You can open this one read-only to look without saving, or quit.")
        let zone = TimeZone(identifier: "UTC")!
        let today = PersistInstanceAlertText.time(PersistInstanceGuardTests.now.addingTimeInterval(-60), now: PersistInstanceGuardTests.now, zone: zone)
        #expect(today.count == 5)
        let older = PersistInstanceAlertText.time(PersistInstanceGuardTests.now.addingTimeInterval(-86_400 * 2), now: PersistInstanceGuardTests.now, zone: zone)
        #expect(older.count == 16)
    }

    @Test("InstanceGuard: editor, map results, external file E-1/E-2, release keeps the file")
    func guardFacade() throws {
        let t = TempFolder("persist-guard")
        let locks = TempFolder("persist-locks")
        let savedFolder = InstanceGuard.externalLocksFolder
        InstanceGuard.externalLocksFolder = locks.url
        defer { InstanceGuard.release(); InstanceGuard.externalLocksFolder = savedFolder }
        #expect(InstanceGuard.acquire(appFolder: t.url) == .editor)
        #expect(InstanceGuard.isEditor)
        let rec = try #require(PersistLockRecord(json: try t.read(".aa.lock")))
        #expect(rec.pid == getpid())
        #expect(rec.appFolder == PersistHost.canonicalPath(t.url))
        // A second "process" on the same folder is blocked; its holder is this (test) process.
        let second = PersistInstanceLock(lockURL: t.file(".aa.lock"), env: .live)
        if case .blocked = second.acquire() {} else { Issue.record("second editor allowed") }
        // E-1: the external file lock.
        let shared = TempFolder("persist-ext")
        let file = try shared.write("shared.json", "{}")
        #expect(InstanceGuard.acquireExternal(fileURL: file) == .editor)
        let key = InstanceGuard.externalLockKey(file)
        #expect(key == PersistHost.sha256Hex(Data(PersistHost.canonicalPath(file).lowercased().utf8)))
        let upper = URL(fileURLWithPath: file.path.replacingOccurrences(of: "shared.json", with: "SHARED.json"))
        let caseInsensitive = (try? shared.url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames == false
        if caseInsensitive { #expect(InstanceGuard.externalLockKey(upper) == key) }
        let p2 = PersistInstanceLock(lockURL: locks.file("external-\(key).lock"), env: .live)
        if case .blocked = p2.acquire() {} else { Issue.record("external lock not held") }
        // E-2: the active file goes back to the default → released; the other copy's retry succeeds.
        InstanceGuard.releaseExternal()
        #expect(p2.tryAcquire())
        p2.release()
        InstanceGuard.release()
        #expect(FileManager.default.fileExists(atPath: t.file(".aa.lock").path))
        #expect(PersistLockRecord(json: try t.read(".aa.lock"))?.mode == "Released")
    }

    @Test("G-9 analogue: a folder this process cannot write, with no .aa.lock → unguarded (launch continues)")
    func unwritableFolder() throws {
        let t = TempFolder("persist-g9")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: t.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: t.url.path) }
        guard case .unguarded(let why) = lock(t.url, env()).acquire() else { Issue.record("not unguarded"); return }
        #expect(!why.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: t.file(".aa.lock").path))
    }

    @Test("§MP.3.1 a lock file this user cannot write is still locked through a read-only descriptor; no record")
    func readOnlyLockFile() throws {
        let t = TempFolder("persist-rofile")
        let foreign = PersistLockRecord(mode: "Released", pid: 77, hostId: "x", host: "Other", user: "ana", uid: 502)
        try foreign.jsonData().write(to: t.file(".aa.lock"))
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: t.file(".aa.lock").path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: t.file(".aa.lock").path) }
        let before = try t.read(".aa.lock")
        let a = lock(t.url, env())
        #expect(a.acquire() == .owner)
        #expect(try t.read(".aa.lock") == before)                       // the record could not be rewritten
        let b = lock(t.url, env(pid: 5151))
        if case .blocked = b.acquire() {} else { Issue.record("second process allowed") }
        a.release()
        #expect(try t.read(".aa.lock") == before)
    }

    @Test("G-10 the lock comes free while blocked → retry makes this process the editor; DATA-175 Stay Read-Only hands it back")
    func retryAndRelinquish() throws {
        let t = TempFolder("persist-g10")
        defer { InstanceGuard.release() }
        let other = PersistInstanceLock(lockURL: t.file(".aa.lock"), env: env(pid: 999_999))
        #expect(other.acquire() == .owner)
        #expect(InstanceGuard.acquire(appFolder: t.url) != .editor)
        #expect(InstanceGuard.folderBlocked != nil)
        #expect(!InstanceGuard.isEditor)
        #expect(!InstanceGuard.retryFolderLock())                         // the 1 s re-check while the alert is up
        other.release()                                                   // the other copy quits
        #expect(InstanceGuard.retryFolderLock())
        #expect(InstanceGuard.isEditor)
        #expect(InstanceGuard.folderBlocked == nil)
        let rec = try #require(PersistLockRecord(json: try t.read(".aa.lock")))
        #expect(rec.pid == getpid())
        #expect(rec.mode == "Owner")
        // A third process is now blocked (DATA-175: the lock is kept, so nobody else can take it)…
        let third = PersistInstanceLock(lockURL: t.file(".aa.lock"), env: env(pid: 888_888))
        if case .blocked = third.acquire() {} else { Issue.record("third process allowed") }
        // …until "Stay Read-Only" hands it back.
        InstanceGuard.relinquishFolderLock()
        #expect(!InstanceGuard.isEditor)
        #expect(InstanceGuard.folderBlocked != nil)
        #expect(third.acquire() == .owner)
        third.release()
    }

    @Test("DATA-179 + DATA-175: a copy read-only because of the external file upgrades on THAT lock, and hands it back")
    func externalUpgrade() throws {
        let t = TempFolder("persist-ext-ro")
        let locks = TempFolder("persist-ext-locks")
        let savedFolder = InstanceGuard.externalLocksFolder
        InstanceGuard.externalLocksFolder = locks.url
        defer { InstanceGuard.release(); InstanceGuard.externalLocksFolder = savedFolder }
        #expect(InstanceGuard.acquire(appFolder: t.url) == .editor)
        let shared = TempFolder("persist-ext-file")
        let file = try shared.write("shared.json", "{}")
        let key = InstanceGuard.externalLockKey(file)
        let other = PersistInstanceLock(lockURL: locks.file("external-\(key).lock"), env: env(pid: 999_999))
        #expect(other.acquire() == .owner)
        #expect(InstanceGuard.acquireExternal(fileURL: file) != .editor)
        #expect(!InstanceGuard.canEdit)
        #expect(!InstanceGuard.retryEditing())                            // the folder is ours, the file is not
        #expect(InstanceGuard.isEditor)
        other.release()
        #expect(InstanceGuard.retryEditing())
        #expect(InstanceGuard.canEdit)
        // Stay Read-Only gives back the external lock (not the folder's).
        InstanceGuard.relinquishEditing()
        #expect(!InstanceGuard.canEdit)
        #expect(InstanceGuard.externalBlocked != nil)
        #expect(InstanceGuard.isEditor)
        let third = PersistInstanceLock(lockURL: locks.file("external-\(key).lock"), env: env(pid: 777_777))
        #expect(third.acquire() == .owner)
        third.release()
        #expect(InstanceGuard.retryEditing())
    }

    @Test("L-1 lease lost while asleep: wake check → onLeaseLost(host); -mine copy only when dirty; read-only gate")
    func leaseLostAfterWake() throws {
        let t = TempFolder("persist-l1")
        let savedEnv = InstanceGuard.environment
        let savedHandler = InstanceGuard.onLeaseLost
        InstanceGuard.environment = env(network: true, pid: getpid())
        defer {
            InstanceGuard.release()
            InstanceGuard.environment = savedEnv
            InstanceGuard.onLeaseLost = savedHandler
        }
        var lostTo: [String] = []
        InstanceGuard.onLeaseLost = { lostTo.append($0) }
        #expect(InstanceGuard.acquire(appFolder: t.url) == .editor)
        #expect(InstanceGuard.folderLock?.isLeaseMode == true)
        InstanceGuard.checkLeaseAfterWake()                               // still ours: nothing happens
        #expect(lostTo.isEmpty)
        #expect(InstanceGuard.isEditor)
        let foreign = PersistLockRecord(lockKind: "lease", pid: 31337, heartbeatUtc: PersistInstanceGuardTests.now,
                                        hostId: "0123456789abcdef", host: "Engine-Mac", user: "chief", uid: 501)
        try foreign.jsonData().write(to: t.file(".aa.lock"))               // rewritten in place by the other Mac
        InstanceGuard.checkLeaseAfterWake()
        #expect(lostTo == ["Engine-Mac"])
        #expect(!InstanceGuard.isEditor)
        #expect(InstanceGuard.folderBlocked?.lease == true)
        // The model side (UI bridge → PersistLeaseLoss): a clean model writes no copy…
        let clean = StoreFactory.make()
        #expect(PersistLeaseLoss.enterReadOnly(clean.store, hasUnsavedChanges: false) == nil)
        #expect(ConflictCopies.list(clean.dataStore).isEmpty)
        #expect(clean.store.suspendSaving)
        #expect(clean.dataStore.settings.isWriteGated)
        // …a dirty one keeps its edits as conflicts/data-…-mine.json.
        let dirty = StoreFactory.make()
        dirty.store.data.equipment.append(Equipment(name: "Unsaved pump"))
        dirty.store.markDirty()
        let name = try #require(PersistLeaseLoss.enterReadOnly(dirty.store, hasUnsavedChanges: dirty.store.isDirty))
        #expect(name.hasSuffix("-mine.json"))
        let copy = try #require(ConflictCopies.list(dirty.dataStore).first)
        #expect(ConflictCopies.peekData(copy, dirty.dataStore)?.equipment.first?.name == "Unsaved pump")
        #expect(PersistReadOnlyText.leaseLostTitle == "Another copy of AA took over this data folder")
        #expect(PersistReadOnlyText.leaseLostMessage(host: "Engine-Mac")
                == "While this Mac was asleep, the copy of AA on “Engine-Mac” took over editing. This copy is now read-only so neither overwrites the other.")
    }

    @Test("Result mapping per holder (DECISIONS: runningHere forwards; others get the alert)")
    func resultMapping() {
        let d = PersistInstanceGuardTests.now
        #expect(InstanceGuard.result(for: .sameUser(pid: 9, started: nil), record: nil) == .runningHere(pid: 9))
        #expect(InstanceGuard.result(for: .otherUser("ana"), record: nil) == .otherUser("ana"))
        #expect(InstanceGuard.result(for: .otherHostFresh(host: "M", heartbeat: d), record: nil)
                == .remote(host: "M", lastSeen: d, stale: false))
        #expect(InstanceGuard.result(for: .otherHostStale(host: "M", heartbeat: d), record: nil)
                == .remote(host: "M", lastSeen: d, stale: true))
        #expect(InstanceGuard.result(for: .sameUserNoApp(pid: 9, started: nil), record: PersistLockRecord(user: "me")) == .otherUser("me"))
    }

    @Test("MP.7.8 temp-file cleanup at the top level only, older than 10 minutes")
    func tempCleanup() throws {
        let t = TempFolder("persist-tmp")
        let now = Date()
        func make(_ name: String, age: TimeInterval) throws {
            let u = try t.write(name, "x")
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: u.path)
        }
        let hex = "0123456789abcdef0123456789abcdef"
        try make("data.json.\(hex).tmp", age: 11 * 60)
        try make("settings.json.fedcba9876543210fedcba9876543210.tmp", age: 3600)
        try make("qrsync-baseline.json.tmp", age: 3600)
        try make("data.json.tmp", age: 3600)
        try make("files/x.\(hex).tmp", age: 3600)
        try make(".aa.lock", age: 3600)
        let young = t.file("young")
        try FileManager.default.createDirectory(at: young, withIntermediateDirectories: true)
        let deleted = PersistTempFiles.cleanStale(in: t.url, now: now)
        #expect(deleted == ["data.json.\(hex).tmp", "qrsync-baseline.json.tmp", "settings.json.fedcba9876543210fedcba9876543210.tmp"])
        try make("data.json.\(hex).tmp", age: 5 * 60)
        #expect(PersistTempFiles.cleanStale(in: t.url, now: now).isEmpty)
        #expect(t.exists("data.json.tmp") && t.exists("files/x.\(hex).tmp") && t.exists(".aa.lock"))
        #expect(PersistTempFiles.hasForeignDataTemp(in: t.url))
        #expect(PersistTempFiles.isAtomicTemp("qrsync-baseline.json.\(hex).tmp"))
        #expect(!PersistTempFiles.isAtomicTemp("data.json.0123.tmp"))
    }

    @Test("MP.7.9 shared-with-Windows evidence and the per-folder Don't Show Again")
    func windowsEvidence() throws {
        let prefs = MacPreferences(defaults: UserDefaults(suiteName: "persist-tests-\(UUID().uuidString)")!)
        let none = TempFolder("persist-ev0")
        #expect(!PersistWindowsEvidence.detect(appFolder: none.url, settings: AppSettings(), foreignTempAtLaunch: false, outsideWriteSeen: false))
        let enc = TempFolder("persist-ev1")
        try enc.write("data.json", Data("AAENC1\n".utf8) + Data([1, 2, 3]))
        #expect(PersistWindowsEvidence.detect(appFolder: enc.url, settings: AppSettings(), foreignTempAtLaunch: false, outsideWriteSeen: false))
        let tok = TempFolder("persist-ev2")
        try tok.write("google-token/Google.Apis.Auth.OAuth2.Responses.TokenResponse-v2-wholedrive", Data("AADPAPI1".utf8) + Data([9]))
        #expect(PersistWindowsEvidence.detect(appFolder: tok.url, settings: AppSettings(), foreignTempAtLaunch: false, outsideWriteSeen: false))
        var s = AppSettings()
        s.currentDataFile = #"C:\Users\bob\AppData\Local\AA\data.json"#
        #expect(PersistWindowsEvidence.detect(appFolder: none.url, settings: s, foreignTempAtLaunch: false, outsideWriteSeen: false))
        let qr = TempFolder("persist-ev3")
        try FileManager.default.createDirectory(at: qr.file("qrmodels"), withIntermediateDirectories: true)
        #expect(PersistWindowsEvidence.detect(appFolder: qr.url, settings: AppSettings(), foreignTempAtLaunch: false, outsideWriteSeen: false))
        #expect(PersistWindowsEvidence.detect(appFolder: none.url, settings: AppSettings(), foreignTempAtLaunch: true, outsideWriteSeen: false))
        #expect(PersistWindowsEvidence.detect(appFolder: none.url, settings: AppSettings(), foreignTempAtLaunch: false, outsideWriteSeen: true))
        #expect(PersistWindowsEvidence.shouldWarn(appFolder: enc.url, settings: AppSettings(), foreignTempAtLaunch: false,
                                                  outsideWriteSeen: false, prefs: prefs))
        PersistWindowsEvidence.dismiss(appFolder: enc.url, prefs: prefs)
        #expect(!PersistWindowsEvidence.shouldWarn(appFolder: enc.url, settings: AppSettings(), foreignTempAtLaunch: false,
                                                   outsideWriteSeen: false, prefs: prefs))
        #expect(PersistWindowsEvidence.shouldWarn(appFolder: tok.url, settings: AppSettings(), foreignTempAtLaunch: false,
                                                  outsideWriteSeen: false, prefs: prefs))
        #expect(PersistWindowsEvidence.warnedKey(enc.url).rawValue.hasPrefix("AA.SharedWithWindowsWarned."))
    }

    @Test("DATA-175 read-only session: the upgrade poll and the live view")
    func readOnlySession() async throws {
        let t = TempFolder("persist-ro")
        let file = try t.write("data.json", "{}")
        var canLock = false
        var saves = 0
        let s = PersistReadOnlySession(dataFile: { file }, tryUpgrade: { canLock }, onSaveSeen: { saves += 1 })
        s.rememberDisk()
        s.pollOnce()
        #expect(s.phase == .readOnly)
        canLock = true
        s.pollOnce()
        #expect(s.phase == .canEdit)
        s.stayReadOnly()
        #expect(s.phase == .readOnly)
        #expect(s.upgradeDeclined)
        // Stay Read-Only is not undone by the next 5 s poll (the lock it just handed back is free).
        s.pollOnce()
        #expect(s.phase == .readOnly)
        s.checkDisk()
        #expect(saves == 0)
        try AtomicWrite.write(Data(#"{"Equipment":[]}"#.utf8), to: file)
        s.checkDisk()
        #expect(saves == 1)
        s.checkDisk()
        #expect(saves == 1)
        // Another editor saved: once it quits, Edit Here is offered again.
        #expect(!s.upgradeDeclined)
        s.pollOnce()
        #expect(s.phase == .canEdit)
    }

    @Test("The directory watcher fires after its debounce and re-arms when the folder comes back")
    func directoryWatcher() async throws {
        let t = TempFolder("persist-watch")
        let dir = t.file("watched")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var fired = 0
        let w = PersistDirectoryWatcher(directory: dir, debounce: .milliseconds(50)) { fired += 1 }
        w.rearmInterval = .milliseconds(50)
        w.start()
        defer { w.stop() }
        #expect(w.isArmed)
        try AtomicWrite.write(Data("x".utf8), to: dir.appending(path: "a.json"))
        #expect(await persistWait { fired >= 1 })
        try FileManager.default.removeItem(at: dir)
        #expect(await persistWait { !w.isArmed })
        let before = fired
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(await persistWait { w.isArmed && fired > before })
    }
}
