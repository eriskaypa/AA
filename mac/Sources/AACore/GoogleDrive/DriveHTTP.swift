// Spec: 14 §6.4 (URLSession REST: streamed download to a file, resumable upload; 308 "Resume Incomplete" must not be
//       treated as a redirect), §3.1.14 step 6 (`User-Agent: AA/<version> (macOS)`). The transport is a protocol so
//       the Drive decisions are tested against a mock (14 §7.6) and tests never touch the network (ARCH §10.1).
import Foundation

public protocol DriveHTTPTransport: Sendable {
    /// Sends a request and returns the whole body.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Streams the body into a temporary file the caller then owns (moves or deletes).
    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse)
}

/// The production transport: an ephemeral `URLSession` that never follows redirects (Drive's resumable protocol
/// answers 308 without a Location) and never caches.
public final class DriveURLSessionTransport: NSObject, DriveHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public override init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 60
        config.httpAdditionalHeaders = ["User-Agent": DriveURLSessionTransport.userAgent]
        let holder = DriveRedirectBlocker()
        session = URLSession(configuration: config, delegate: holder, delegateQueue: nil)
        super.init()
    }

    /// `AA/<CFBundleShortVersionString> (macOS)`, `AA/dev (macOS)` when unbundled.
    public static var userAgent: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "AA/\(v ?? "dev") (macOS)"
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (d, r) = try await session.data(for: request)
            guard let http = r as? HTTPURLResponse else { throw DriveError.transport("No HTTP response from Google.") }
            return (d, http)
        } catch let e as DriveError {
            throw e
        } catch {
            throw DriveError.transport(error.localizedDescription)
        }
    }

    public func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        do {
            let (u, r) = try await session.download(for: request)
            guard let http = r as? HTTPURLResponse else { throw DriveError.transport("No HTTP response from Google.") }
            // Move out of URLSession's staging location before it can be reclaimed.
            let own = FileManager.default.temporaryDirectory.appending(path: "aa-drive-dl-\(UUID().uuidString.lowercased())")
            try FileManager.default.moveItem(at: u, to: own)
            return (own, http)
        } catch let e as DriveError {
            throw e
        } catch {
            throw DriveError.transport(error.localizedDescription)
        }
    }
}

private final class DriveRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

/// `application/x-www-form-urlencoded` bodies (unreserved characters kept, everything else percent-encoded).
public enum DriveForm {
    static let unreserved: CharacterSet = {
        var s = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        s.insert(charactersIn: "-._~")
        return s
    }()

    public static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    public static func body(_ pairs: [(String, String)]) -> Data {
        Data(pairs.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&").utf8)
    }

    /// Parses `a=b&c=d` (percent-decoding, `+` as space).
    public static func parse(_ query: String) -> [String: String] {
        var out: [String: String] = [:]
        for part in query.split(separator: "&", omittingEmptySubsequences: true) {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            func dec(_ s: Substring) -> String {
                String(s).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(s)
            }
            let k = dec(kv[0])
            if out[k] == nil { out[k] = kv.count > 1 ? dec(kv[1]) : "" }
        }
        return out
    }
}
