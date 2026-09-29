// Shared test helpers (ARCHITECTURE.md §10.1): TempFolder, Fixtures, StoreFactory, JSONAssert, withTimeZone.
// Tests never touch the login Keychain, ~/Library/Application Support/AA, the network or notifications.
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
