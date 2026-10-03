// The production transport at its network boundary (14 §6.4, §3.1.14 step 6): `DriveURLSessionTransport` driven
// through a real `URLSession` whose only protocol class is a scripted `URLProtocol` — no network (ARCH §10.1).
// Covers what the `DriveHTTPTransport` mocks cannot: 308 is never followed, the `User-Agent` header reaches the wire,
// downloads leave URLSession's staging folder, and failures map to `DriveError.transport`.
import Foundation
import Testing
@testable import AACore

/// A scripted HTTP endpoint. Each test registers its own host (`<uuid>.invalid`), so parallel tests never share a
/// script. A 3xx answer with a `Location` is reported as a redirect, the way CFNetwork's HTTP protocol does — the
/// session's delegate then decides whether to follow it.
final class DriveScriptedURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
        var fail: URLError.Code?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: @Sendable (URLRequest) -> Reply] = [:]
    nonisolated(unsafe) private static var seen: [String: [URLRequest]] = [:]

    /// Registers a fresh host and returns its base URL.
    static func host(_ reply: @escaping @Sendable (URLRequest) -> Reply) -> URL {
        let host = "\(UUID().uuidString.lowercased()).invalid"
        lock.withLock { replies[host] = reply; seen[host] = [] }
        return URL(string: "https://\(host)")!
    }

    static func requests(to base: URL) -> [URLRequest] { lock.withLock { seen[base.host() ?? ""] ?? [] } }

    static var configuration: URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [DriveScriptedURLProtocol.self]
        return c
    }

    override class func canInit(with request: URLRequest) -> Bool {
        lock.withLock { replies[request.url?.host() ?? ""] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        let reply = Self.lock.withLock { () -> (@Sendable (URLRequest) -> Reply)? in
            Self.seen[host, default: []].append(request)
            return Self.replies[host]
        }
        guard let reply, let url = request.url else { return }
        let r = reply(request)
        if let code = r.fail {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.headers)!
        if (300..<400).contains(r.status), let loc = r.headers["Location"], let target = URL(string: loc, relativeTo: url) {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target.absoluteURL), redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: r.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite struct DriveTransportTests {
    // TV: 14 §3.1.14 step 6 — `User-Agent: AA/<version> (macOS)` on every request; 200 body returned whole.
    @Test func userAgentOnTheWire() async throws {
        let base = DriveScriptedURLProtocol.host { _ in .init(status: 200, body: Data(#"{"files":[]}"#.utf8)) }
        let t = DriveURLSessionTransport(configuration: DriveScriptedURLProtocol.configuration)
        let (data, response) = try await t.data(for: URLRequest(url: base.appending(path: "drive/v3/files")))
        #expect(response.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == #"{"files":[]}"#)
        let sent = try #require(DriveScriptedURLProtocol.requests(to: base).first)
        #expect(sent.value(forHTTPHeaderField: "User-Agent") == DriveURLSessionTransport.userAgent)
        #expect(DriveURLSessionTransport.userAgent.hasPrefix("AA/") && DriveURLSessionTransport.userAgent.hasSuffix(" (macOS)"))
    }

    // TV: 14 §6.4 — the resumable upload's 308 "Resume Incomplete" is returned to the caller, never followed, even
    // when the answer carries a Location.
    @Test func resumeIncomplete308IsNotFollowed() async throws {
        let base = DriveScriptedURLProtocol.host { req in
            if req.url?.path() == "/elsewhere" { return .init(status: 200, body: Data("followed".utf8)) }
            return .init(status: 308, headers: ["Range": "bytes=0-262143", "Location": "/elsewhere"])
        }
        let t = DriveURLSessionTransport(configuration: DriveScriptedURLProtocol.configuration)
        var put = URLRequest(url: base.appending(path: "upload/drive/v3/files").appending(queryItems: [.init(name: "upload_id", value: "u1")]))
        put.httpMethod = "PUT"
        put.setValue("bytes */1048576", forHTTPHeaderField: "Content-Range")
        let (data, response) = try await t.data(for: put)
        #expect(response.statusCode == 308)
        #expect(response.value(forHTTPHeaderField: "Range") == "bytes=0-262143")
        #expect(String(decoding: data, as: UTF8.self) != "followed")
        #expect(DriveScriptedURLProtocol.requests(to: base).map { $0.url?.path() } == ["/upload/drive/v3/files"])
    }

    // TV: 14 §6.4 — a streamed download is moved out of URLSession's staging location into a file the caller owns.
    @Test func downloadLeavesTheStagingFolder() async throws {
        let payload = Data((0..<70_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let base = DriveScriptedURLProtocol.host { _ in .init(status: 200, body: payload) }
        let t = DriveURLSessionTransport(configuration: DriveScriptedURLProtocol.configuration)
        let (file, response) = try await t.download(for: URLRequest(url: base.appending(path: "drive/v3/files/F1")))
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(response.statusCode == 200)
        #expect(file.lastPathComponent.hasPrefix("aa-drive-dl-"))
        #expect(file.deletingLastPathComponent().standardizedFileURL.path()
                == FileManager.default.temporaryDirectory.standardizedFileURL.path())
        #expect(try Data(contentsOf: file) == payload)
        let sent = try #require(DriveScriptedURLProtocol.requests(to: base).first)
        #expect(sent.value(forHTTPHeaderField: "User-Agent") == DriveURLSessionTransport.userAgent)
    }

    // A non-2xx answer is handed back as-is (the Drive client parses `error.message`); a transport failure becomes
    // `DriveError.transport` for both calls.
    @Test func errorsAndFailures() async throws {
        let base = DriveScriptedURLProtocol.host { req in
            req.url?.path() == "/down" ? .init(status: 0, fail: .notConnectedToInternet)
                                       : .init(status: 403, body: Data(#"{"error":{"message":"nope"}}"#.utf8))
        }
        let t = DriveURLSessionTransport(configuration: DriveScriptedURLProtocol.configuration)
        let (body, r) = try await t.data(for: URLRequest(url: base.appending(path: "x")))
        #expect(r.statusCode == 403 && String(decoding: body, as: UTF8.self).contains("nope"))
        await #expect { _ = try await t.data(for: URLRequest(url: base.appending(path: "down"))) } throws: { e in
            if case DriveError.transport = e { return true } else { return false }
        }
        await #expect { _ = try await t.download(for: URLRequest(url: base.appending(path: "down"))) } throws: { e in
            if case DriveError.transport = e { return true } else { return false }
        }
    }
}
