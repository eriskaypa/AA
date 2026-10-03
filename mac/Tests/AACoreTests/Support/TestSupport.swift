// Shared test helpers (ARCHITECTURE.md §10.1): TempFolder, Fixtures, StoreFactory, JSONAssert, withTimeZone.
// Tests never touch the login Keychain, ~/Library/Application Support/AA, ~/Library/Preferences (no UserDefaults
// suite on disk: MacPreferences.inMemory(), DECISIONS "Stage V rulings"), the network or notifications.
import Foundation
import Testing
@testable import AACore

/// A unique temporary folder, deleted when the object is released.
final class TempFolder: @unchecked Sendable {
    let url: URL

    init(_ label: String = "aa-tests") {
        url = FileManager.default.temporaryDirectory
            .appending(path: "\(label)-\(UUID().uuidString.lowercased())", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func file(_ name: String) -> URL { url.appending(path: name) }

    @discardableResult
    func write(_ name: String, _ data: Data) throws -> URL {
        let u = file(name)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: u)
        return u
    }

    @discardableResult
    func write(_ name: String, _ text: String) throws -> URL { try write(name, Data(text.utf8)) }

    func read(_ name: String) throws -> Data { try Data(contentsOf: file(name)) }
    func readText(_ name: String) throws -> String { String(decoding: try read(name), as: UTF8.self) }
    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: file(name).path) }
}

/// Transitional shim, entirely in memory (DECISIONS "Stage V rulings": no test creates a UserDefaults suite on
/// disk). New tests use `MacPreferences.inMemory()`; this type only keeps the older call sites compiling until their
/// owners convert them, then it is deleted. `defaults` is a `UserDefaults` whose every read and write goes to the
/// same in-memory store as `preferences`, so nothing reaches cfprefsd or `~/Library/Preferences`.
final class TempDefaults: @unchecked Sendable {
    let defaults: UserDefaults
    let preferences: MacPreferences

    init(_ label: String = "aa-tests") {
        let d = InMemoryUserDefaults()
        defaults = d
        preferences = MacPreferences(backend: d.store)
    }

    /// Nothing to remove (kept for the existing `defer { temp.remove() }` call sites).
    func remove() {}
}

/// A `UserDefaults` that never touches the preferences system: every accessor the tests use is overridden to read
/// and write an `InMemoryPreferences` store (the superclass instance is never read or written).
final class InMemoryUserDefaults: UserDefaults, @unchecked Sendable {
    let store = InMemoryPreferences()

    init() { super.init(suiteName: nil)! }

    override func object(forKey defaultName: String) -> Any? { store.object(forKey: defaultName) }
    override func set(_ value: Any?, forKey defaultName: String) { store.set(value, forKey: defaultName) }
    override func set(_ value: Bool, forKey defaultName: String) { store.set(value, forKey: defaultName) }
    override func set(_ value: Int, forKey defaultName: String) { store.set(value, forKey: defaultName) }
    override func set(_ value: Double, forKey defaultName: String) { store.set(value, forKey: defaultName) }
    override func set(_ value: Float, forKey defaultName: String) { store.set(value, forKey: defaultName) }
    override func set(_ url: URL?, forKey defaultName: String) { store.set(url, forKey: defaultName) }
    override func removeObject(forKey defaultName: String) { store.removeObject(forKey: defaultName) }
    override func bool(forKey defaultName: String) -> Bool { store.bool(forKey: defaultName) }
    override func string(forKey defaultName: String) -> String? { store.string(forKey: defaultName) }
    override func data(forKey defaultName: String) -> Data? { store.data(forKey: defaultName) }
    override func integer(forKey defaultName: String) -> Int { (store.object(forKey: defaultName) as? NSNumber)?.intValue ?? 0 }
    override func double(forKey defaultName: String) -> Double { (store.object(forKey: defaultName) as? NSNumber)?.doubleValue ?? 0 }
    override func float(forKey defaultName: String) -> Float { (store.object(forKey: defaultName) as? NSNumber)?.floatValue ?? 0 }
    override func url(forKey defaultName: String) -> URL? { store.object(forKey: defaultName) as? URL }
    override func array(forKey defaultName: String) -> [Any]? { store.object(forKey: defaultName) as? [Any] }
    override func dictionary(forKey defaultName: String) -> [String: Any]? { store.object(forKey: defaultName) as? [String: Any] }
    override func stringArray(forKey defaultName: String) -> [String]? { store.object(forKey: defaultName) as? [String] }
    override func synchronize() -> Bool { true }
}

/// Test fixtures under `Tests/AACoreTests/Fixtures/` (copied whole into the test bundle).
enum Fixtures {
    static var root: URL {
        Bundle.module.resourceURL!.appending(path: "Fixtures", directoryHint: .isDirectory)
    }
    static func url(_ relativePath: String) -> URL { root.appending(path: relativePath) }
    static func data(_ relativePath: String) throws -> Data { try Data(contentsOf: url(relativePath)) }
    static func string(_ relativePath: String) throws -> String {
        String(decoding: try data(relativePath), as: UTF8.self)
    }
}

/// Time-zone helpers: tests pass zones explicitly and never mutate the process-wide default.
enum TZ {
    static let athens = TimeZone(identifier: "Europe/Athens")!
    static let newYork = TimeZone(identifier: "America/New_York")!
    static let london = TimeZone(identifier: "Europe/London")!
    static let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    static let utc = TimeZone(identifier: "UTC")!
}

func withTimeZone<T>(_ identifier: String, _ body: (TimeZone) throws -> T) rethrows -> T {
    try body(TimeZone(identifier: identifier)!)
}

/// Deterministic GUID source: 00000000-0000-0000-0000-00000000000N, N = 1, 2, …
final class SequentialGuids: @unchecked Sendable {
    private let lock = NSLock()
    private var n: UInt64 = 0
    func next() -> UUID {
        lock.lock(); defer { lock.unlock() }
        n += 1
        return UUID(netString: String(format: "00000000-0000-0000-0000-%012llx", n))!
    }
}

/// Builds `G(n)` ids used by the golden fixtures: `00000000-0000-0000-0000-{n as 12 hex digits}`.
func G(_ n: Int) -> UUID { UUID(netString: String(format: "00000000-0000-0000-0000-%012x", n))! }

enum JSONAssert {
    /// Canonical text of a JSON document (object keys sorted ordinally, compact) — for order-insensitive checks.
    static func canonical(_ v: JSONValue) -> String {
        func sortTree(_ v: JSONValue) -> JSONValue {
            switch v {
            case .object(let o):
                let pairs = o.pairs.sorted { Ordinal.compare($0.key, $1.key) == .orderedAscending }
                return .object(JSONObject(pairs.map { ($0.key, sortTree($0.value)) }))
            case .array(let a): return .array(a.map(sortTree))
            default: return v
            }
        }
        return (try? JSONWriter.string(sortTree(v))) ?? ""
    }

    static func equalCanonical(_ a: String, _ b: String) throws -> Bool {
        canonical(try JSONParser.parse(a)) == canonical(try JSONParser.parse(b))
    }
}

/// Flag settable from `@Sendable` observation callbacks.
final class TestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// Literal goldens shared by several suites.
enum Goldens {
    /// 01 §4.2.1 / ARCHITECTURE.md §4.10 — `AppData()` with SchemaVersion 1.
    static let freshDB = #"{"Equipment":[],"Tasks":[],"Procedures":[],"Vessels":[],"Groups":[],"Crew":[],"Log":[],"ChecklistTemplates":[],"ListGroups":[],"QuickBuckets":[],"Ports":[],"ScheduleTemplates":[],"Trash":[],"Sire":{"QuestionStatuses":{},"Bookmarks":[],"ForExport":[],"Tasks":[],"QuestionBodies":{}},"Ui":{"SelectedMainTabIndex":0,"ShowShortcutBar":true,"QuickViewPinIds":[],"TabColors":{},"TabOrder":[],"SortAZ":{},"GroupExpanded":{},"CrewTableColumns":[],"CrewTableShownColumns":[]},"SchemaVersion":1}"#
}

/// Builds an `AppStore` over a temporary AppFolder with an in-memory Keychain (ARCHITECTURE.md §10.1).
/// The folder lives as long as the returned `folder` reference.
@MainActor
enum StoreFactory {
    struct Made {
        let store: AppStore
        let dataStore: DataStore
        let folder: TempFolder
        let secrets: InMemorySecretStore
    }

    static func make(data: AppData? = nil, clock: AppClock = SystemClock(),
                     secrets: InMemorySecretStore? = nil) -> Made {
        let secrets = secrets ?? InMemorySecretStore()
        let folder = TempFolder("aa-store")
        let ds = DataStore(appFolder: folder.url, secrets: secrets, clock: clock)
        ds.loadSettings()
        return Made(store: AppStore(dataStore: ds, data: data ?? AppData(), clock: clock), dataStore: ds, folder: folder, secrets: secrets)
    }
}
