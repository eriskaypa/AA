// Spec: 14 TOOLS-008 (installed-app loopback flow, "Received verification code…" page), TOOLS-009 (scopes),
//       §3.1.14 (RFC 8252 loopback + PKCE S256 + state; token exchange; one retry with prompt=consent when no refresh
//       token came back; refresh keeps the old refresh token; a 4xx refresh deletes the stored token, 5xx keeps it;
//       401 → refresh once), §6.3 (NWListener on 127.0.0.1 port 0, NSWorkspace browser, Cancel + 5-minute timeout,
//       "Google sign-in cancelled."), Q-7, §3.1.6 (library deletes the token after a rejected refresh).
import Foundation
import CryptoKit
import Network

// MARK: PKCE and the consent URL

public enum DrivePKCE {
    static let unreserved = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Random octets behind one `code_verifier`: 48 → exactly 64 base64url characters, no padding.
    public static let verifierOctets = 48

    /// A 64-character `code_verifier` (RFC 7636 §4.1: 43…128 unreserved characters): the base64url encoding of
    /// `verifierOctets` random octets, as §4.1 recommends. Every 6-bit group maps to one character, so each of the
    /// 64 characters is equally likely (the earlier `byte % 66` mapping favoured the first 58 characters).
    public static func makeVerifier() -> String { verifier(from: SecureRandom.bytes(verifierOctets)) }

    /// The deterministic half of `makeVerifier` (tests feed fixed octets).
    static func verifier(from octets: Data) -> String { base64URL(octets) }

    /// `BASE64URL(SHA256(verifier))` without padding.
    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func makeState() -> String { base64URL(SecureRandom.bytes(24)) }

    public static func base64URL(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum DriveOAuthURL {
    /// `http://127.0.0.1:{port}/authorize/` (the .NET `LocalServerCodeReceiver` callback path).
    public static func redirectURI(port: UInt16) -> String { "http://127.0.0.1:\(port)/authorize/" }

    /// The consent URL of §3.1.14 step 3 (`prompt=consent` on the one retry of step 4).
    public static func authorization(secret: DriveClientSecret, redirectURI: String, challenge: String, state: String,
                                     forceConsent: Bool) -> URL? {
        guard var c = URLComponents(string: secret.authURI) else { return nil }
        var items = c.queryItems ?? []
        items.append(contentsOf: [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: secret.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: DriveConstants.scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ])
        if forceConsent { items.append(URLQueryItem(name: "prompt", value: "consent")) }
        c.queryItems = items
        // URLComponents leaves '+' and '&'-safe characters alone; make the value encoding strict for the few that
        // matter in OAuth parameters.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url
    }
}

// MARK: Loopback receiver

/// The parsed request line of a browser redirect.
public struct DriveLoopbackRequest: Sendable, Equatable {
    public var path: String
    public var query: [String: String]

    /// Parses the head of an HTTP request (`GET /authorize/?code=…&state=… HTTP/1.1`).
    public static func parse(head: String) -> DriveLoopbackRequest? {
        let scalars = head.unicodeScalars
        let end = scalars.firstIndex { $0 == "\r" || $0 == "\n" } ?? scalars.endIndex
        let line = String(scalars[scalars.startIndex..<end])
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        let target = String(parts[1])
        if let q = target.firstIndex(of: "?") {
            return DriveLoopbackRequest(path: String(target[..<q]), query: DriveForm.parse(String(target[target.index(after: q)...])))
        }
        return DriveLoopbackRequest(path: target, query: [:])
    }

    public var isAuthorizeCallback: Bool { path == "/authorize/" || path == "/authorize" }
}

/// What the redirect carried.
public enum DriveRedirectOutcome: Sendable, Equatable {
    case code(String)
    case error(code: String, description: String)
}

/// A one-shot HTTP listener on `127.0.0.1` (ephemeral port) that waits for Google's redirect with the expected
/// `state`, answers the browser and reports the code (14 §3.1.14 steps 3–4).
public final class DriveLoopbackReceiver: @unchecked Sendable {
    public static let successPage = "<html><head><meta charset=\"utf-8\"><title>AA</title></head><body style=\"font-family:-apple-system,Helvetica,sans-serif;margin:3em\"><h3>Received verification code. You may now close this window.</h3></body></html>"

    private let expectedState: String
    private let queue = DispatchQueue(label: "com.eriskay.aa.drive.loopback")
    private let lock = NSLock()
    private var listener: NWListener?
    private var portContinuation: CheckedContinuation<UInt16, Error>?
    private var waitContinuation: CheckedContinuation<DriveRedirectOutcome, Error>?
    private var finished: Result<DriveRedirectOutcome, Error>?

    public init(expectedState: String) { self.expectedState = expectedState }

    /// Starts listening; returns the bound port.
    public func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        params.allowLocalEndpointReuse = true
        let l: NWListener
        do { l = try NWListener(using: params) } catch { throw DriveError.loopbackFailed(error.localizedDescription) }
        lock.withLock { listener = l }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            lock.lock(); portContinuation = cont; lock.unlock()
            l.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.resumePort(.success(l.port?.rawValue ?? 0))
                case .failed(let e):
                    self.resumePort(.failure(DriveError.loopbackFailed(e.localizedDescription)))
                case .cancelled:
                    self.resumePort(.failure(DriveError.signInCancelled))
                default: break
                }
            }
            l.start(queue: queue)
        }
    }

    private func resumePort(_ r: Result<UInt16, Error>) {
        lock.lock(); let c = portContinuation; portContinuation = nil; lock.unlock()
        c?.resume(with: r)
    }

    /// Waits for the matching redirect (or a cancellation).
    public func waitForRedirect() async throws -> DriveRedirectOutcome {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<DriveRedirectOutcome, Error>) in
            lock.lock()
            if let f = finished { lock.unlock(); cont.resume(with: f); return }
            waitContinuation = cont
            lock.unlock()
        }
    }

    /// Stops listening and fails the wait with `error` (Cancel button, timeout).
    public func cancel(_ error: DriveError = .signInCancelled) { finish(.failure(error)) }

    private func finish(_ r: Result<DriveRedirectOutcome, Error>) {
        lock.lock()
        if finished != nil { lock.unlock(); return }
        finished = r
        let c = waitContinuation; waitContinuation = nil
        let l = listener; listener = nil
        lock.unlock()
        l?.cancel()
        c?.resume(with: r)
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { c.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                self.handle(c, head: String(decoding: buf[..<range.lowerBound], as: UTF8.self))
            } else if complete || error != nil || buf.count > 1_048_576 {
                c.cancel()
            } else {
                self.receive(c, buffer: buf)
            }
        }
    }

    private func handle(_ c: NWConnection, head: String) {
        guard let req = DriveLoopbackRequest.parse(head: head), req.isAuthorizeCallback,
              req.query["state"] == expectedState else {
            respond(c, status: "404 Not Found", body: "<html><body>Not found.</body></html>")
            return
        }
        respond(c, status: "200 OK", body: DriveLoopbackReceiver.successPage)
        if let err = req.query["error"] {
            finish(.success(.error(code: err, description: req.query["error_description"] ?? "")))
        } else if let code = req.query["code"], !code.isEmpty {
            finish(.success(.code(code)))
        } else {
            finish(.success(.error(code: "invalid_request", description: "No authorization code in the redirect.")))
        }
    }

    private func respond(_ c: NWConnection, status: String, body: String) {
        let b = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(b.count)\r\nConnection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + b, completion: .contentProcessed { _ in c.cancel() })
    }
}

// MARK: Authorizer

/// Callbacks the UI provides for the interactive part (the waiting sheet with Cancel, 14 §6.3).
public struct DriveSignInHooks: Sendable {
    /// Called when the browser is about to open with the consent URL; `cancel` aborts the sign-in.
    public var started: @Sendable (_ consentURL: URL, _ cancel: @escaping @Sendable () -> Void) async -> Void
    /// Called when the interactive part ended (success, failure or cancel).
    public var ended: @Sendable () async -> Void
    /// Opens the consent URL in the default browser.
    public var openBrowser: @Sendable (URL) async -> Bool

    public init(started: @escaping @Sendable (_ consentURL: URL, _ cancel: @escaping @Sendable () -> Void) async -> Void,
                ended: @escaping @Sendable () async -> Void,
                openBrowser: @escaping @Sendable (URL) async -> Bool) {
        self.started = started; self.ended = ended; self.openBrowser = openBrowser
    }

    /// No UI: interactive sign-in is refused (tests, background).
    public static let none = DriveSignInHooks(started: { _, _ in }, ended: {}, openBrowser: { _ in false })
}

/// Hands out access tokens: cached → refreshed → interactive loopback flow. One interactive flow at a time; other
/// callers join it.
public actor DriveAuthorizer {
    public let clientSecretFile: URL
    public let vault: DriveTokenVault
    public let transport: DriveHTTPTransport
    public let clock: AppClock
    public let hooks: DriveSignInHooks
    public let signInTimeout: Duration

    private var interactiveTask: Task<DriveTokenResponse, Error>?

    public init(clientSecretFile: URL, vault: DriveTokenVault, transport: DriveHTTPTransport, clock: AppClock,
                hooks: DriveSignInHooks, signInTimeout: Duration = .seconds(300)) {
        self.clientSecretFile = clientSecretFile; self.vault = vault; self.transport = transport; self.clock = clock
        self.hooks = hooks; self.signInTimeout = signInTimeout
    }

    /// A Bearer token valid for ≥ 5 minutes. `interactive == false` never opens a browser.
    public func accessToken(interactive: Bool) async throws -> String {
        let secret = try DriveClientSecret.load(from: clientSecretFile)
        vault.ensureFolder()
        if let t = vault.load() {
            if t.isValid(at: clock.utcNow()) { return t.accessToken }
            if t.refreshToken != nil {
                let refreshed = try await refresh(t, secret: secret)
                return refreshed.accessToken
            }
        }
        guard interactive else { throw DriveError.interactiveSignInRequired }
        return try await interactiveToken(secret: secret).accessToken
    }

    /// After a 401: refresh once (or sign in again when there is no refresh token).
    public func tokenAfterUnauthorized(interactive: Bool) async throws -> String {
        let secret = try DriveClientSecret.load(from: clientSecretFile)
        if let t = vault.load(), t.refreshToken != nil {
            return try await refresh(t, secret: secret).accessToken
        }
        guard interactive else { throw DriveError.interactiveSignInRequired }
        return try await interactiveToken(secret: secret).accessToken
    }

    // MARK: Refresh

    func refresh(_ token: DriveTokenResponse, secret: DriveClientSecret) async throws -> DriveTokenResponse {
        guard let refreshToken = token.refreshToken, let url = URL(string: secret.tokenURI) else {
            throw DriveError.interactiveSignInRequired
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = DriveForm.body([("grant_type", "refresh_token"), ("client_id", secret.clientID),
                                       ("client_secret", secret.clientSecret), ("refresh_token", refreshToken)])
        let (data, resp) = try await transport.data(for: req)
        guard (200..<300).contains(resp.statusCode) else {
            let err = DriveAuthorizer.oauthError(data, status: resp.statusCode)
            if (400..<500).contains(resp.statusCode) { vault.deleteToken() }   // §3.1.14 step 5
            throw err
        }
        guard let o = try? JSONParser.parse(data).objectValue,
              var fresh = DriveTokenResponse(endpointJSON: o, issuedUtc: clock.utcNow()) else {
            throw DriveError.transport("Unexpected answer from Google's token endpoint.")
        }
        if fresh.refreshToken == nil { fresh.refreshToken = refreshToken }   // keep the old refresh token
        try vault.store(fresh)
        return fresh
    }

    static func oauthError(_ data: Data, status: Int) -> DriveError {
        if let o = try? JSONParser.parse(data).objectValue {
            if let code = o["error"]?.stringValue {
                return .oauth(code: code, description: o["error_description"]?.stringValue ?? "")
            }
            if let e = o["error"]?.objectValue {
                return .api(status: status, message: e["message"]?.stringValue ?? "", reason: nil)
            }
        }
        return .oauth(code: "http_\(status)", description: String(decoding: data.prefix(300), as: UTF8.self))
    }

    // MARK: Interactive

    private func interactiveToken(secret: DriveClientSecret) async throws -> DriveTokenResponse {
        if let running = interactiveTask { return try await running.value }
        let task = Task { () throws -> DriveTokenResponse in
            try await self.runInteractive(secret: secret)
        }
        interactiveTask = task
        defer { interactiveTask = nil }
        return try await task.value
    }

    private func runInteractive(secret: DriveClientSecret) async throws -> DriveTokenResponse {
        let first = try await consentRound(secret: secret, forceConsent: false)
        var token = first
        if token.refreshToken == nil {
            token = try await consentRound(secret: secret, forceConsent: true)   // ensure an offline token
        }
        try vault.store(token)
        return token
    }

    private func consentRound(secret: DriveClientSecret, forceConsent: Bool) async throws -> DriveTokenResponse {
        let state = DrivePKCE.makeState()
        let verifier = DrivePKCE.makeVerifier()
        let receiver = DriveLoopbackReceiver(expectedState: state)
        let port = try await receiver.start()
        let redirect = DriveOAuthURL.redirectURI(port: port)
        guard let url = DriveOAuthURL.authorization(secret: secret, redirectURI: redirect,
                                                    challenge: DrivePKCE.challenge(for: verifier), state: state,
                                                    forceConsent: forceConsent) else {
            receiver.cancel(.invalidClientFile)
            throw DriveError.invalidClientFile
        }
        await hooks.started(url) { receiver.cancel(.signInCancelled) }
        let timeout = signInTimeout
        let timer = Task {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { receiver.cancel(.signInTimedOut) }
        }
        let outcome: DriveRedirectOutcome
        do {
            if await !hooks.openBrowser(url) {
                receiver.cancel(.transport("Could not open the web browser for Google sign-in."))
            }
            outcome = try await receiver.waitForRedirect()
            timer.cancel()
            await hooks.ended()
        } catch {
            timer.cancel()
            await hooks.ended()
            throw error
        }
        switch outcome {
        case .error(let code, let description):
            throw DriveError.oauth(code: code, description: description)
        case .code(let code):
            return try await exchange(code: code, verifier: verifier, redirectURI: redirect, secret: secret)
        }
    }

    private func exchange(code: String, verifier: String, redirectURI: String,
                          secret: DriveClientSecret) async throws -> DriveTokenResponse {
        guard let url = URL(string: secret.tokenURI) else { throw DriveError.invalidClientFile }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = DriveForm.body([("grant_type", "authorization_code"), ("code", code),
                                       ("client_id", secret.clientID), ("client_secret", secret.clientSecret),
                                       ("redirect_uri", redirectURI), ("code_verifier", verifier)])
        let (data, resp) = try await transport.data(for: req)
        guard (200..<300).contains(resp.statusCode) else { throw DriveAuthorizer.oauthError(data, status: resp.statusCode) }
        guard let o = try? JSONParser.parse(data).objectValue,
              let token = DriveTokenResponse(endpointJSON: o, issuedUtc: clock.utcNow()) else {
            throw DriveError.transport("Unexpected answer from Google's token endpoint.")
        }
        return token
    }
}
