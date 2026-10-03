// W-PERSIST test helpers (ARCHITECTURE.md §12.2: prefixed, own folder): an advancing clock, scripted shared-save and
// data-file-conflict hosts, ZIP builders and a polling wait.
import Foundation
import Testing
@testable import AACore

/// A clock that starts at a local wall-clock time and only moves when told to.
final class PersistTestClock: AppClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    let timeZone: TimeZone

    init(local: String = "2026-09-30T14:15:02", zone: TimeZone = .current) {
        timeZone = zone
        current = FixedClock(local: local, zone: zone).instant()
    }

    func instant() -> Date { lock.lock(); defer { lock.unlock() }; return current }
    func now() -> NetDateTime { NetDateTime(date: instant(), kind: .local, zone: timeZone) }
    func utcNow() -> NetDateTime { NetDateTime(date: instant(), kind: .utc, zone: timeZone) }
    func today() -> CivilDate { now().civilDate }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock()
    }

    /// `HH:mm` / `HH:mm:ss` of the current instant (what the status texts show).
    var hhmm: String { now().format(.time, zone: timeZone) }
    var hms: String { String(now().format(.isoSecond).suffix(8)) }
}

/// A scripted F3 host for the shared-save coordinator.
@MainActor final class PersistFakeSharedHost: SharedSaveHost {
    let store: AppStore
    var answerReload = true
    private(set) var prompts = 0
    private(set) var statuses: [String] = []
    private(set) var reloads: [String?] = []
    private(set) var flushes = 0

    init(store: AppStore) { self.store = store }

    func flushAllEditors() { flushes += 1 }
    func captureUiState() {}
    func confirmReloadDiscardingChanges() async -> Bool { prompts += 1; return answerReload }
    func reloadAfterSharedImport(identity: String?) {
        reloads.append(identity)
        store.dataStore.loadSettings()
        store.replaceData(store.dataStore.load(), reason: .sharedSavePull)
        statuses.append(PersistSharedText.reloaded(identity: identity, "00:00:00"))
    }
    func postStatus(_ text: String) { statuses.append(text) }
    var lastStatus: String? { statuses.last }
}

/// A scripted F3 host for DATA-180.
@MainActor final class PersistFakeConflictHost: DataFileConflictHost {
    var choice: DataFileConflictChoice = .keepMine
    private(set) var presented: [DataFileConflict] = []
    func presentConflict(_ c: DataFileConflict) async -> DataFileConflictChoice {
        presented.append(c)
        return choice
    }
}

enum PersistZip {
    /// Builds a ZIP at `url` from (name, bytes?) pairs; nil bytes = a directory entry.
    static func make(_ url: URL, _ entries: [(String, Data?)]) throws {
        let w = try ZipWriter(url: url)
        for (name, data) in entries {
            if let data { try w.addData(data, named: name, modified: Date()) } else { try w.addDirectory(named: name) }
        }
        try w.finish()
    }

    static func names(_ url: URL) throws -> [String] { try ZipReader(url: url).entries.map(\.name) }

    static func entry(_ url: URL, _ name: String) throws -> Data? {
        let r = try ZipReader(url: url)
        guard let e = r.entry(named: name) else { return nil }
        return try r.data(for: e)
    }
}

/// Polls `condition` on the main actor (10 ms steps) until it holds or `timeout` passes.
@MainActor func persistWait(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// A data.json body with one equipment item named `name`, stamped `stamp`.
@MainActor func persistDataJSON(_ ds: DataStore, name: String, stamp: NetDateTime?) throws -> Data {
    let d = AppData()
    let e = Equipment(name: name)
    d.equipment.append(e)
    d.lastModified = stamp
    return try ds.serializeForSave(d)
}

/// Sizes and names of the top-level files of a folder (for attachment assertions).
func persistListing(_ dir: URL) -> [String: Int] {
    var out: [String: Int] = [:]
    for n in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
        let v = try? FileManager.default.attributesOfItem(atPath: dir.appending(path: n).path)
        out[n] = (v?[.size] as? NSNumber)?.intValue ?? 0
    }
    return out
}
