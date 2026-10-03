// Test doubles for the Drive family (14 §7.6 "mock DriveClient"): a scripted DriveAPI and a scripted HTTP transport.
// Tests never touch the network (ARCHITECTURE.md §10.1).
import Foundation
@testable import AACore

/// A scripted `DriveAPI` that records every call.
final class DriveMockAPI: DriveAPI, @unchecked Sendable {
    private let lock = NSLock()
    var files: [DriveFile] = []
    var folders: [String: String] = [:]                 // name → id
    var downloads: [String: Data] = [:]                 // id → bytes
    var calls: [String] = []
    var listQueries: [String] = []
    var listFields: [String] = []
    /// Explicit `EnsureFolder` matches per name (Q-3 tests); `folders` answers otherwise.
    var folderCandidates: [String: [DriveFile]] = [:]
    var created: [(name: String, parents: [String]?, props: [String: String])] = []
    var updated: [(id: String, props: [String: String])] = []
    var failPrepare: DriveError?
    var failList: DriveError?

    private func record(_ s: String) { lock.withLock { calls.append(s) } }

    func prepare() async throws {
        record("prepare")
        if let failPrepare { throw failPrepare }
    }

    func list(q: String, fields: String, orderBy: String?, pageSize: Int?, wholeDrive: Bool, maxPages: Int) async throws -> [DriveFile] {
        record("list")
        lock.withLock { listQueries.append(q); listFields.append(fields) }
        if let failList { throw failList }
        if q.hasPrefix("mimeType='application/vnd.google-apps.folder' and name='") {
            let name = String(q.dropFirst("mimeType='application/vnd.google-apps.folder' and name='".count).prefix { $0 != "'" })
            if let candidates = folderCandidates[name] { return candidates }
            return folders[name].map { [DriveFile(id: $0, name: name, mimeType: DriveConstants.folderMimeType)] } ?? []
        }
        if q.contains("name='AA-sync.zip' and trashed=false") {
            return files.filter { $0.name == DriveConstants.syncFileName }.prefix(1).map { DriveFile(id: $0.id, name: $0.name) }
        }
        return files
    }

    func createFolder(name: String) async throws -> String {
        record("createFolder:\(name)")
        let id = "folder-\(name.replacingOccurrences(of: " ", with: "-"))"
        lock.withLock { folders[name] = id }
        return id
    }

    func download(fileID: String, to destination: URL) async throws {
        record("download:\(fileID)")
        try (downloads[fileID] ?? Data("zip".utf8)).write(to: destination)
    }

    func create(name: String, parents: [String]?, appProperties: [String: String], from file: URL, fields: String) async throws -> DriveFile {
        record("create:\(name)")
        lock.withLock { created.append((name, parents, appProperties)) }
        return DriveFile(id: "new-\(name)", name: name, webViewLink: "https://drive.google.com/file/d/new/view")
    }

    func update(fileID: String, appProperties: [String: String], from file: URL, fields: String) async throws -> DriveFile {
        record("update:\(fileID)")
        lock.withLock { updated.append((fileID, appProperties)) }
        return DriveFile(id: fileID, name: DriveConstants.syncFileName)
    }
}

/// A scripted HTTP transport: each request goes to `handler`, which returns status, headers and body.
final class DriveMockTransport: DriveHTTPTransport, @unchecked Sendable {
    struct Reply { var status: Int; var headers: [String: String] = [:]; var body: Data = Data() }
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    var handler: (URLRequest, Int) -> Reply

    init(handler: @escaping (URLRequest, Int) -> Reply) { self.handler = handler }

    private func reply(_ r: URLRequest) -> (Reply, HTTPURLResponse) {
        let index: Int = lock.withLock { requests.append(r); return requests.count - 1 }
        let rep = handler(r, index)
        let resp = HTTPURLResponse(url: r.url!, statusCode: rep.status, httpVersion: "HTTP/1.1", headerFields: rep.headers)!
        return (rep, resp)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (rep, resp) = reply(request)
        return (rep.body, resp)
    }

    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        let (rep, resp) = reply(request)
        let u = FileManager.default.temporaryDirectory.appending(path: "aa-drive-mock-\(UUID().uuidString)")
        try rep.body.write(to: u)
        return (u, resp)
    }

    var all: [URLRequest] { lock.withLock { requests } }
}

enum DriveFixture {
    static func json(_ s: String) -> Data { Data(s.utf8) }

    static let clientSecret = #"{"installed":{"client_id":"123.apps.googleusercontent.com","project_id":"aa","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","client_secret":"GOCSPX-test","redirect_uris":["http://localhost"]}}"#

    static func query(_ r: URLRequest) -> [String: String] {
        let comps = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)
        var out: [String: String] = [:]
        for i in comps?.queryItems ?? [] { out[i.name] = i.value ?? "" }
        return out
    }
}
