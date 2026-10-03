// Spec: 14 §3.1.4 (SearchWholeDrive: spaces=drive, includeItemsFromAllDrives, supportsAllDrives, pageSize=200),
//       §3.1.5 + Q-1 / DECISIONS 14 (real paging via nextPageToken, ≤10 pages), §3.1.8 / §3.1.13 (resumable
//       create / update, application/zip), TOOLS-019 + Q-6 / DECISIONS 14 (download with supportsAllDrives=true),
//       §6.4 (URLSession REST, chunks that are multiples of 256 KiB, PATCH for update), §3.1.14 step 6 (Bearer, 401 →
//       refresh once and retry), TOOLS-034 (Drive's own error message), Q-8 (identity too long).
import Foundation

/// The Drive v3 calls AA makes. A protocol so the decisions are tested with a mock (14 §7.6).
public protocol DriveAPI: Sendable {
    /// Obtains a usable access token (`GetServiceAsync`): signs in when needed and allowed.
    func prepare() async throws
    func list(q: String, fields: String, orderBy: String?, pageSize: Int?, wholeDrive: Bool, maxPages: Int) async throws -> [DriveFile]
    func createFolder(name: String) async throws -> String
    func download(fileID: String, to destination: URL) async throws
    func create(name: String, parents: [String]?, appProperties: [String: String], from file: URL, fields: String) async throws -> DriveFile
    func update(fileID: String, appProperties: [String: String], from file: URL, fields: String) async throws -> DriveFile
}

public struct DriveRESTClient: DriveAPI {
    public static let apiBase = "https://www.googleapis.com/drive/v3/files"
    public static let uploadBase = "https://www.googleapis.com/upload/drive/v3/files"
    /// 8 MiB (a multiple of 256 KiB).
    public static let chunkSize = 8 * 1024 * 1024

    public let authorizer: DriveAuthorizer
    public let transport: DriveHTTPTransport
    /// May this operation open the browser to sign in?
    public let interactive: Bool

    public init(authorizer: DriveAuthorizer, transport: DriveHTTPTransport, interactive: Bool) {
        self.authorizer = authorizer; self.transport = transport; self.interactive = interactive
    }

    public func prepare() async throws { _ = try await authorizer.accessToken(interactive: interactive) }

    // MARK: Requests with auth

    private func authorized(_ build: () throws -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        var req = try build()
        req.setValue("Bearer \(try await authorizer.accessToken(interactive: interactive))", forHTTPHeaderField: "Authorization")
        var (data, resp) = try await transport.data(for: req)
        if resp.statusCode == 401 {
            req.setValue("Bearer \(try await authorizer.tokenAfterUnauthorized(interactive: interactive))",
                         forHTTPHeaderField: "Authorization")
            (data, resp) = try await transport.data(for: req)
        }
        return (data, resp)
    }

    /// Drive's `{"error":{"code":…,"message":…,"errors":[{"reason":…}]}}` → `DriveError.api`.
    static func apiError(_ data: Data, status: Int) -> DriveError {
        if let o = try? JSONParser.parse(data).objectValue {
            if let e = o["error"]?.objectValue {
                let reason = e["errors"]?.arrayValue?.first?.objectValue?["reason"]?.stringValue
                return .api(status: status, message: e["message"]?.stringValue ?? "", reason: reason)
            }
            if let code = o["error"]?.stringValue {
                return .oauth(code: code, description: o["error_description"]?.stringValue ?? "")
            }
        }
        let text = String(decoding: data.prefix(500), as: UTF8.self)
        return .api(status: status, message: text, reason: nil)
    }

    static func url(_ base: String, _ items: [(String, String)]) throws -> URL {
        guard var c = URLComponents(string: base) else { throw DriveError.transport("Bad Drive URL.") }
        c.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        // `q` values contain '+'-free text but may contain '&'/'=' only inside quotes; URLComponents encodes those
        // query-item characters it must. Make '+' explicit so Google never reads it as a space.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let u = c.url else { throw DriveError.transport("Bad Drive URL.") }
        return u
    }

    // MARK: files.list

    public func list(q: String, fields: String, orderBy: String?, pageSize: Int?, wholeDrive: Bool,
                     maxPages: Int) async throws -> [DriveFile] {
        var all: [DriveFile] = []
        var token: String?
        for _ in 0..<max(maxPages, 1) {
            var items: [(String, String)] = [("q", q), ("fields", fields), ("spaces", "drive")]
            if let orderBy { items.append(("orderBy", orderBy)) }
            if wholeDrive {
                items.append(("includeItemsFromAllDrives", "true"))
                items.append(("supportsAllDrives", "true"))
            }
            if let pageSize { items.append(("pageSize", String(pageSize))) }
            if let token { items.append(("pageToken", token)) }
            let (data, resp) = try await authorized {
                var r = URLRequest(url: try DriveRESTClient.url(DriveRESTClient.apiBase, items))
                r.httpMethod = "GET"
                return r
            }
            guard (200..<300).contains(resp.statusCode) else { throw DriveRESTClient.apiError(data, status: resp.statusCode) }
            let o = (try? JSONParser.parse(data).objectValue) ?? JSONObject()
            for f in o["files"]?.arrayValue ?? [] { if let fo = f.objectValue { all.append(DriveFile(json: fo)) } }
            token = o["nextPageToken"]?.stringValue
            if token == nil || token!.isEmpty { break }
        }
        return all
    }

    // MARK: Folder create

    public func createFolder(name: String) async throws -> String {
        var meta = JSONObject()
        meta.set("name", .string(name))
        meta.set("mimeType", .string(DriveConstants.folderMimeType))
        let body = try JSONWriter.data(.object(meta))
        let (data, resp) = try await authorized {
            var r = URLRequest(url: try DriveRESTClient.url(DriveRESTClient.apiBase, [("fields", "id")]))
            r.httpMethod = "POST"
            r.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            r.httpBody = body
            return r
        }
        guard (200..<300).contains(resp.statusCode) else { throw DriveRESTClient.apiError(data, status: resp.statusCode) }
        guard let id = (try? JSONParser.parse(data).objectValue)?["id"]?.stringValue else {
            throw DriveError.transport("Google Drive returned no folder id.")
        }
        return id
    }

    // MARK: Download (alt=media)

    public func download(fileID: String, to destination: URL) async throws {
        let url = try DriveRESTClient.url(DriveRESTClient.apiBase + "/" + DriveForm.encode(fileID),
                                          [("alt", "media"), ("supportsAllDrives", "true")])
        var req = URLRequest(url: url)
        req.setValue("Bearer \(try await authorizer.accessToken(interactive: interactive))", forHTTPHeaderField: "Authorization")
        var (tmp, resp) = try await transport.download(for: req)
        if resp.statusCode == 401 {
            try? FileManager.default.removeItem(at: tmp)
            req.setValue("Bearer \(try await authorizer.tokenAfterUnauthorized(interactive: interactive))",
                         forHTTPHeaderField: "Authorization")
            (tmp, resp) = try await transport.download(for: req)
        }
        guard (200..<300).contains(resp.statusCode) else {
            let body = (try? Data(contentsOf: tmp)) ?? Data()
            try? FileManager.default.removeItem(at: tmp)
            throw DriveRESTClient.apiError(body, status: resp.statusCode)
        }
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: tmp, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw DriveError.downloadIncomplete
        }
    }

    // MARK: Resumable upload

    public func create(name: String, parents: [String]?, appProperties: [String: String], from file: URL,
                       fields: String) async throws -> DriveFile {
        var meta = JSONObject()
        meta.set("name", .string(name))
        meta.set("appProperties", .object(DriveRESTClient.props(appProperties)))
        if let parents { meta.set("parents", .array(parents.map(JSONValue.string))) }
        return try await resumable(method: "POST", path: DriveRESTClient.uploadBase, metadata: meta, file: file,
                                   fields: fields, appProperties: appProperties, incomplete: .uploadIncomplete)
    }

    public func update(fileID: String, appProperties: [String: String], from file: URL, fields: String) async throws -> DriveFile {
        var meta = JSONObject()
        meta.set("appProperties", .object(DriveRESTClient.props(appProperties)))
        return try await resumable(method: "PATCH", path: DriveRESTClient.uploadBase + "/" + DriveForm.encode(fileID),
                                   metadata: meta, file: file, fields: fields, appProperties: appProperties,
                                   incomplete: .syncUploadIncomplete)
    }

    /// Stable key order (aaLastModified, aaIdentity first) for readable requests.
    static func props(_ p: [String: String]) -> JSONObject {
        var o = JSONObject()
        for k in [DriveConstants.lastModifiedProp, DriveConstants.identityProp] { if let v = p[k] { o.set(k, .string(v)) } }
        for k in p.keys.sorted() where k != DriveConstants.lastModifiedProp && k != DriveConstants.identityProp {
            o.set(k, .string(p[k]!))
        }
        return o
    }

    private func resumable(method: String, path: String, metadata: JSONObject, file: URL, fields: String,
                           appProperties: [String: String], incomplete: DriveError) async throws -> DriveFile {
        let size = ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? NSNumber)?.int64Value ?? 0
        let body = try JSONWriter.data(.object(metadata))
        let (initData, initResp) = try await authorized {
            var r = URLRequest(url: try DriveRESTClient.url(path, [("uploadType", "resumable"),
                                                                  ("supportsAllDrives", "true"), ("fields", fields)]))
            r.httpMethod = method
            r.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            r.setValue(DriveConstants.zipMimeType, forHTTPHeaderField: "X-Upload-Content-Type")
            r.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
            r.httpBody = body
            return r
        }
        guard (200..<300).contains(initResp.statusCode) else {
            throw DriveRESTClient.metadataError(initData, status: initResp.statusCode, appProperties: appProperties)
        }
        guard let loc = initResp.value(forHTTPHeaderField: "Location"), let session = URL(string: loc) else {
            throw incomplete
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var offset: Int64 = 0
        var stalled = 0
        while true {
            let chunk = try handle.read(upToCount: DriveRESTClient.chunkSize) ?? Data()
            if chunk.isEmpty && size > 0 { throw incomplete }
            var req = URLRequest(url: session)
            req.httpMethod = "PUT"
            req.setValue(DriveConstants.zipMimeType, forHTTPHeaderField: "Content-Type")
            if size == 0 {
                req.setValue("bytes */0", forHTTPHeaderField: "Content-Range")
            } else {
                req.setValue("bytes \(offset)-\(offset + Int64(chunk.count) - 1)/\(size)", forHTTPHeaderField: "Content-Range")
            }
            req.httpBody = chunk
            let (data, resp) = try await transport.data(for: req)
            if resp.statusCode == 308 {
                // Resume Incomplete: continue after what the server acknowledged.
                let previous = offset
                if let range = resp.value(forHTTPHeaderField: "Range"), let dash = range.lastIndex(of: "-"),
                   let last = Int64(range[range.index(after: dash)...]) {
                    offset = last + 1
                } else {
                    offset = 0
                }
                stalled = offset > previous ? 0 : stalled + 1
                if stalled >= 3 || offset > size { throw incomplete }
                try handle.seek(toOffset: UInt64(offset))
                continue
            }
            guard (200..<300).contains(resp.statusCode) else {
                throw DriveRESTClient.metadataError(data, status: resp.statusCode, appProperties: appProperties)
            }
            guard let o = try? JSONParser.parse(data).objectValue else { throw incomplete }
            return DriveFile(json: o)
        }
    }

    /// Q-8: a 400 while an appProperty exceeds Drive's 124-byte limit is reported as "identity too long".
    static func metadataError(_ data: Data, status: Int, appProperties: [String: String]) -> DriveError {
        let base = apiError(data, status: status)
        if status == 400, let id = appProperties[DriveConstants.identityProp],
           (DriveConstants.identityProp + id).utf8.count > DriveConstants.appPropertyByteLimit {
            return .identityTooLong(underlying: base.localizedDescription)
        }
        return base
    }
}
