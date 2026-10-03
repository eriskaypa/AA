// Tests for 14 §7.6-8 (HasToken / NeedsReconsent), TOOLS-007/010/012/013, §3.1.14 (client file, PKCE, consent URL,
// loopback redirect, token refresh rules, 401 retry), §6.4 (paging, resumable upload, download), TOOLS-034 (errors).
import Foundation
import Testing
@testable import AACore

@Suite struct DriveAuthTests {
    private func vault(_ folder: TempFolder, _ secrets: InMemorySecretStore = InMemorySecretStore()) -> DriveTokenVault {
        DriveTokenVault(folder: folder.url.appending(path: "google-token"), secrets: secrets)
    }

    private func token(_ access: String = "AT", refresh: String? = "RT", issued: NetDateTime, expiresIn: Int64 = 3599) -> DriveTokenResponse {
        DriveTokenResponse(accessToken: access, expiresIn: expiresIn, refreshToken: refresh,
                           scope: DriveConstants.scopes.joined(separator: " "), issuedUtc: issued)
    }

    // TV: 14 §7.6-8
    @Test func hasTokenAndReconsent() throws {
        let f = TempFolder("aa-gtok")
        let v = vault(f)
        #expect(!v.hasToken && !v.needsReconsentForWholeDrive)                  // no folder
        try FileManager.default.createDirectory(at: v.folder, withIntermediateDirectories: true)
        #expect(!v.hasToken && !v.needsReconsentForWholeDrive)                  // empty folder
        try Data("{}".utf8).write(to: v.folder.appending(path: "Google.Apis.Auth.OAuth2.Responses.TokenResponse-user"))
        #expect(!v.hasToken && v.needsReconsentForWholeDrive)                   // legacy key only
        try (DriveTokenVault.windowsMagic + Data([1, 2, 3])).write(to: v.tokenFile)
        #expect(!v.hasToken && v.needsReconsentForWholeDrive)                   // Windows DPAPI file on a Mac
        #expect(v.load() == nil)
        try v.store(token(issued: NetDateTime(ticks: 0, kind: .utc)))
        #expect(v.hasToken && !v.needsReconsentForWholeDrive)                   // Mac magic
        let head = try Data(contentsOf: v.tokenFile).prefix(8)
        #expect(head == Data("AAKCGCM1".utf8))
        v.signOut()
        #expect(!FileManager.default.fileExists(atPath: v.folder.path))
        #expect(!v.hasToken && !v.needsReconsentForWholeDrive)
    }

    // TV: TOOLS-012 round trip, Keychain item, legacy plaintext re-stored, undecryptable → no token
    @Test func tokenVaultRoundTrip() throws {
        let f = TempFolder("aa-gtok")
        let secrets = InMemorySecretStore()
        let v = vault(f, secrets)
        let issued = NetDateTime(year: 2026, month: 9, day: 30, hour: 8, minute: 15, second: 30, kind: .utc)
        let t = token(issued: issued)
        try v.store(t)
        #expect(v.load() == t)
        #expect(try secrets.read(service: "AA", account: "google-token-key")?.count == 32)
        let raw = try Data(contentsOf: v.tokenFile)
        #expect(!String(decoding: raw, as: UTF8.self).contains("AT"))

        // Lost Keychain key → "no token" (the next action re-prompts).
        try secrets.delete(service: "AA", account: "google-token-key")
        #expect(v.load() == nil)

        // Legacy plaintext JSON under the current key is returned and re-stored encrypted.
        try t.json().write(to: v.tokenFile)
        #expect(v.load()?.accessToken == "AT")
        #expect(try Data(contentsOf: v.tokenFile).prefix(8) == Data("AAKCGCM1".utf8))

        let o = try JSONParser.parse(t.json(zone: TimeZone(secondsFromGMT: 8 * 3600)!)).objectValue!
        #expect(o.keys == ["access_token", "token_type", "expires_in", "refresh_token", "scope", "id_token", "Issued", "IssuedUtc"])
        #expect(o["scope"]?.stringValue == "https://www.googleapis.com/auth/drive.readonly https://www.googleapis.com/auth/drive.file")
        #expect(o.rawValue(forKey: "id_token")?.isNull == true)
        #expect(o["Issued"]?.stringValue == "2026-09-30T16:15:30+08:00")
        #expect(o["IssuedUtc"]?.stringValue == "2026-09-30T08:15:30Z")
    }

    @Test func tokenValidity() {
        let issued = NetDateTime(year: 2026, month: 9, day: 30, hour: 8, kind: .utc)
        let t = token(issued: issued, expiresIn: 3600)
        #expect(t.isValid(at: issued.addingTicks(54 * 60 * NetDateTime.ticksPerSecond)))
        #expect(!t.isValid(at: issued.addingTicks(55 * 60 * NetDateTime.ticksPerSecond)))
        #expect(!token(issued: issued, expiresIn: 0).isValid(at: issued))
    }

    // TV: TOOLS-007/008 client file
    @Test func clientSecretParsing() throws {
        let s = try DriveClientSecret.parse(Data(DriveFixture.clientSecret.utf8))
        #expect(s.clientID == "123.apps.googleusercontent.com" && s.clientSecret == "GOCSPX-test")
        #expect(s.authURI == "https://accounts.google.com/o/oauth2/auth" && s.tokenURI == "https://oauth2.googleapis.com/token")
        let web = try DriveClientSecret.parse(Data(#"{"web":{"client_id":"w","client_secret":"s"}}"#.utf8))
        #expect(web.authURI == DriveClientSecret.defaultAuthURI && web.tokenURI == DriveClientSecret.defaultTokenURI)
        for bad in ["", "[]", "{}", #"{"installed":{"client_id":"x"}}"#, #"{"other":{"client_id":"x","client_secret":"y"}}"#] {
            #expect(throws: DriveError.invalidClientFile) { try DriveClientSecret.parse(Data(bad.utf8)) }
        }
        let f = TempFolder("aa-client")
        #expect(throws: DriveError.notConfigured) { try DriveClientSecret.load(from: f.file("google_client_secret.json")) }
        let src = try f.write("downloaded.json", "not even json")               // copied byte-for-byte, no validation
        let dest = f.url.appending(path: "AA/google_client_secret.json")
        try DriveClientSecret.install(from: src, to: dest)
        #expect(try Data(contentsOf: dest) == Data("not even json".utf8))
        #expect(throws: DriveError.invalidClientFile) { try DriveClientSecret.load(from: dest) }
    }

    // TV: §3.1.14 step 3 (PKCE + consent URL)
    @Test func pkceAndConsentURL() throws {
        let v = DrivePKCE.makeVerifier()
        #expect(v.count == 64)
        #expect(v.allSatisfy { DrivePKCE.unreserved.contains($0) })
        // RFC 7636 appendix B vector.
        #expect(DrivePKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let s = try DriveClientSecret.parse(Data(DriveFixture.clientSecret.utf8))
        let url = DriveOAuthURL.authorization(secret: s, redirectURI: DriveOAuthURL.redirectURI(port: 53682),
                                              challenge: "CH", state: "ST", forceConsent: false)!
        let q = DriveFixture.query(URLRequest(url: url))
        #expect(url.absoluteString.hasPrefix("https://accounts.google.com/o/oauth2/auth?"))
        #expect(q["response_type"] == "code" && q["client_id"] == "123.apps.googleusercontent.com")
        #expect(q["redirect_uri"] == "http://127.0.0.1:53682/authorize/")
        #expect(q["scope"] == "https://www.googleapis.com/auth/drive.readonly https://www.googleapis.com/auth/drive.file")
        #expect(url.absoluteString.contains("scope=https://www.googleapis.com/auth/drive.readonly%20https://www.googleapis.com/auth/drive.file"))
        #expect(q["access_type"] == "offline" && q["code_challenge"] == "CH" && q["code_challenge_method"] == "S256")
        #expect(q["state"] == "ST" && q["prompt"] == nil)
        let forced = DriveOAuthURL.authorization(secret: s, redirectURI: "r", challenge: "c", state: "s", forceConsent: true)!
        #expect(DriveFixture.query(URLRequest(url: forced))["prompt"] == "consent")
    }

    @Test func loopbackRequestParsing() {
        let r = DriveLoopbackRequest.parse(head: "GET /authorize/?state=abc&code=4%2F0Ab_x&scope=a%20b HTTP/1.1\r\nHost: 127.0.0.1\r\n")
        #expect(r?.path == "/authorize/" && r?.isAuthorizeCallback == true)
        #expect(r?.query["code"] == "4/0Ab_x" && r?.query["state"] == "abc" && r?.query["scope"] == "a b")
        #expect(DriveLoopbackRequest.parse(head: "GET /favicon.ico HTTP/1.1")?.isAuthorizeCallback == false)
        #expect(DriveLoopbackRequest.parse(head: "POST /authorize/ HTTP/1.1") == nil)
        #expect(DriveForm.parse("error=access_denied&state=x")["error"] == "access_denied")
        #expect(String(decoding: DriveForm.body([("a b", "c/d+e")]), as: UTF8.self) == "a%20b=c%2Fd%2Be")
    }

    // TV: §3.1.14 step 4 — a live redirect on 127.0.0.1 (loopback only, no network)
    @Test func loopbackReceiverReceivesTheCode() async throws {
        let receiver = DriveLoopbackReceiver(expectedState: "S1")
        let port = try await receiver.start()
        #expect(port > 0)
        let wrong = URL(string: "http://127.0.0.1:\(port)/authorize/?state=OTHER&code=no")!
        let (_, wr) = try await URLSession.shared.data(from: wrong)
        #expect((wr as? HTTPURLResponse)?.statusCode == 404)
        let url = URL(string: "http://127.0.0.1:\(port)/authorize/?state=S1&code=4%2Fabc")!
        let (body, resp) = try await URLSession.shared.data(from: url)
        #expect((resp as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: body, as: UTF8.self).contains("Received verification code. You may now close this window."))
        #expect(try await receiver.waitForRedirect() == .code("4/abc"))

        let denied = DriveLoopbackReceiver(expectedState: "S2")
        let p2 = try await denied.start()
        _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(p2)/authorize/?state=S2&error=access_denied")!)
        #expect(try await denied.waitForRedirect() == .error(code: "access_denied", description: ""))

        let cancelled = DriveLoopbackReceiver(expectedState: "S3")
        _ = try await cancelled.start()
        cancelled.cancel()
        await #expect(throws: DriveError.signInCancelled) { try await cancelled.waitForRedirect() }
    }

    private func authorizer(_ f: TempFolder, _ transport: DriveMockTransport, clock: AppClock, secrets: InMemorySecretStore = InMemorySecretStore()) throws -> (DriveAuthorizer, DriveTokenVault) {
        let secretFile = try f.write("google_client_secret.json", DriveFixture.clientSecret)
        let v = vault(f, secrets)
        return (DriveAuthorizer(clientSecretFile: secretFile, vault: v, transport: transport, clock: clock, hooks: .none), v)
    }

    // TV: §3.1.14 steps 2 and 5 (refresh keeps the refresh token; 4xx deletes, 5xx keeps)
    @Test func refreshRules() async throws {
        let f = TempFolder("aa-auth")
        let clock = FixedClock(local: "2026-09-30T12:00:00", zone: TimeZone(identifier: "UTC")!)
        var status = 200
        let transport = DriveMockTransport { r, _ in
            #expect(r.url?.absoluteString == "https://oauth2.googleapis.com/token")
            let body = String(decoding: r.httpBody ?? Data(), as: UTF8.self)
            #expect(body.contains("grant_type=refresh_token") && body.contains("refresh_token=RT"))
            if status == 200 { return .init(status: 200, body: Data(#"{"access_token":"NEW","expires_in":3599,"token_type":"Bearer"}"#.utf8)) }
            if status == 400 { return .init(status: 400, body: Data(#"{"error":"invalid_grant","error_description":"Bad Request"}"#.utf8)) }
            return .init(status: 503, body: Data("busy".utf8))
        }
        let (auth, v) = try authorizer(f, transport, clock: clock)
        try v.store(token(issued: NetDateTime(year: 2026, month: 9, day: 30, hour: 9, kind: .utc)))   // expired
        #expect(try await auth.accessToken(interactive: false) == "NEW")
        #expect(v.load()?.refreshToken == "RT")
        #expect(try await auth.accessToken(interactive: false) == "NEW")   // cached now (valid ≥ 5 min)
        #expect(transport.all.count == 1)

        try v.store(token(issued: NetDateTime(year: 2026, month: 9, day: 30, hour: 9, kind: .utc)))
        status = 503
        await #expect(throws: DriveError.self) { try await auth.accessToken(interactive: false) }
        #expect(v.load() != nil)                                            // 5xx keeps the token
        status = 400
        do {
            _ = try await auth.accessToken(interactive: false)
            Issue.record("expected invalid_grant")
        } catch let e as DriveError {
            #expect(e == .oauth(code: "invalid_grant", description: "Bad Request"))
            #expect(e.localizedDescription == "Error:\"invalid_grant\", Description:\"Bad Request\", Uri:\"\"")
        }
        #expect(v.load() == nil && !v.hasToken)                              // 4xx deleted it
        await #expect(throws: DriveError.interactiveSignInRequired) { try await auth.accessToken(interactive: false) }
    }

    // TV: §3.1.5 + Q-1 paging, §3.1.4 whole-Drive parameters, 401 → refresh once and retry
    @Test func restListPagingAndUnauthorizedRetry() async throws {
        let f = TempFolder("aa-rest")
        let clock = FixedClock(local: "2026-09-30T12:00:00", zone: TimeZone(identifier: "UTC")!)
        let transport = DriveMockTransport { r, i in
            if r.url?.host == "oauth2.googleapis.com" {
                return .init(status: 200, body: Data(#"{"access_token":"FRESH","expires_in":3599}"#.utf8))
            }
            let q = DriveFixture.query(r)
            if r.value(forHTTPHeaderField: "Authorization") == "Bearer STALE" { return .init(status: 401, body: Data()) }
            if q["pageToken"] == nil {
                return .init(status: 200, body: Data(#"{"nextPageToken":"P2","files":[{"id":"1","name":"AA-sync.zip","appProperties":{"aaLastModified":"x"}}]}"#.utf8))
            }
            return .init(status: 200, body: Data(#"{"files":[{"id":"2","name":"aa-data-1.zip","modifiedTime":"2026-09-30T01:02:03.456Z","mimeType":"application/zip"}]}"#.utf8))
        }
        let (auth, v) = try authorizer(f, transport, clock: clock)
        try v.store(token("STALE", issued: NetDateTime(year: 2026, month: 9, day: 30, hour: 11, minute: 59, kind: .utc)))
        let client = DriveRESTClient(authorizer: auth, transport: transport, interactive: false)
        let files = try await client.list(q: DriveQuery.bestRemote, fields: "nextPageToken,files(id,name,appProperties,modifiedTime,mimeType)",
                                          orderBy: "modifiedTime desc", pageSize: 200, wholeDrive: true, maxPages: 10)
        #expect(files.map(\.id) == ["1", "2"])
        #expect(files[0].appProperties["aaLastModified"] == "x")
        #expect(files[1].modifiedUtc == NetDateTime(year: 2026, month: 9, day: 30, hour: 1, minute: 2, second: 3, fractionTicks: 4_560_000, kind: .utc))
        let listCalls = transport.all.filter { $0.url?.host == "www.googleapis.com" }
        let q0 = DriveFixture.query(listCalls[0])
        #expect(q0["q"] == DriveQuery.bestRemote && q0["spaces"] == "drive" && q0["pageSize"] == "200")
        #expect(q0["includeItemsFromAllDrives"] == "true" && q0["supportsAllDrives"] == "true" && q0["orderBy"] == "modifiedTime desc")
        #expect(listCalls[0].value(forHTTPHeaderField: "Authorization") == "Bearer STALE")
        #expect(listCalls[1].value(forHTTPHeaderField: "Authorization") == "Bearer FRESH")
        #expect(DriveFixture.query(listCalls.last!)["pageToken"] == "P2")
    }

    // TV: §6.4 resumable create (chunks), update (PATCH), download (supportsAllDrives), Drive error text
    @Test func restUploadDownloadAndErrors() async throws {
        let f = TempFolder("aa-rest")
        let clock = FixedClock(local: "2026-09-30T12:00:00", zone: TimeZone(identifier: "UTC")!)
        let payload = Data(repeating: 7, count: 1000)
        let file = try f.write("aa-data-20260930-140307.zip", payload)
        let transport = DriveMockTransport { r, _ in
            let url = r.url!.absoluteString
            if url.hasPrefix("https://www.googleapis.com/upload/drive/v3/files") {
                let q = DriveFixture.query(r)
                #expect(q["uploadType"] == "resumable" && q["supportsAllDrives"] == "true")
                #expect(r.value(forHTTPHeaderField: "X-Upload-Content-Type") == "application/zip")
                #expect(r.value(forHTTPHeaderField: "X-Upload-Content-Length") == "1000")
                return .init(status: 200, headers: ["Location": "https://upload.example/session/1"])
            }
            if url == "https://upload.example/session/1" {
                #expect(r.httpMethod == "PUT")
                #expect(r.value(forHTTPHeaderField: "Content-Range") == "bytes 0-999/1000")
                #expect(r.httpBody?.count == 1000)
                return .init(status: 200, body: Data(#"{"id":"F1","name":"aa-data-20260930-140307.zip","webViewLink":"https://drive.google.com/file/d/F1/view"}"#.utf8))
            }
            if url.contains("alt=media") {
                #expect(DriveFixture.query(r)["supportsAllDrives"] == "true")
                if url.contains("/missing?") {
                    return .init(status: 404, body: Data(#"{"error":{"code":404,"message":"File not found: missing.","errors":[{"reason":"notFound"}]}}"#.utf8))
                }
                return .init(status: 200, body: Data("ZIPBYTES".utf8))
            }
            return .init(status: 500)
        }
        let (auth, v) = try authorizer(f, transport, clock: clock)
        try v.store(token(issued: NetDateTime(year: 2026, month: 9, day: 30, hour: 11, minute: 59, kind: .utc)))
        let client = DriveRESTClient(authorizer: auth, transport: transport, interactive: false)
        let created = try await client.create(name: file.lastPathComponent, parents: ["P"], appProperties: ["aaIdentity": "Vessel-Alpha"],
                                              from: file, fields: "id, name, webViewLink")
        #expect(created.id == "F1" && created.webViewLink == "https://drive.google.com/file/d/F1/view")
        let initReq = transport.all.first { $0.url?.host == "www.googleapis.com" }!
        let meta = try JSONParser.parse(initReq.httpBody!).objectValue!
        #expect(meta["name"]?.stringValue == "aa-data-20260930-140307.zip")
        #expect(meta["parents"]?.arrayValue?.first?.stringValue == "P")
        #expect(meta["appProperties"]?.objectValue?["aaIdentity"]?.stringValue == "Vessel-Alpha")

        let dest = f.url.appending(path: "aa-drive-20260930140307.zip")
        try await client.download(fileID: "abc", to: dest)
        #expect(try Data(contentsOf: dest) == Data("ZIPBYTES".utf8))
        do {
            try await client.download(fileID: "missing", to: f.url.appending(path: "x.zip"))
            Issue.record("expected a 404")
        } catch {
            #expect(error.localizedDescription == "The service drive has thrown an exception. HttpStatusCode is NotFound. File not found: missing.")
        }
    }

    // TV: TOOLS-034 hints, Q-8
    @Test func errorTexts() {
        let denied = DriveError.oauth(code: "access_denied", description: "")
        #expect(denied.localizedDescription.hasPrefix("Error:\"access_denied\", Description:\"\", Uri:\"\"\n\n"))
        #expect(denied.localizedDescription.hasSuffix(DriveError.setupHint))
        let perms = DriveError.api(status: 403, message: "Insufficient permissions.", reason: "insufficientPermissions")
        #expect(perms.localizedDescription.contains("HttpStatusCode is Forbidden. Insufficient permissions."))
        #expect(perms.localizedDescription.hasSuffix(DriveError.setupHint))
        let long = String(repeating: "x", count: 120)
        let e = DriveRESTClient.metadataError(Data(#"{"error":{"code":400,"message":"Bad"}}"#.utf8), status: 400,
                                              appProperties: ["aaIdentity": long])
        #expect(e.localizedDescription.hasPrefix("App identity is too long for Google Drive metadata."))
        let short = DriveRESTClient.metadataError(Data(#"{"error":{"code":400,"message":"Bad"}}"#.utf8), status: 400,
                                                  appProperties: ["aaIdentity": "Vessel"])
        #expect(short == .api(status: 400, message: "Bad", reason: nil))
    }
}

/// The interactive loopback flow end to end: a fake "browser" follows the consent URL's redirect to 127.0.0.1 and
/// the token endpoint is the mock transport (no network).
@Suite struct DriveInteractiveSignInTests {
    final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        var events: [String] = []
        var consentURLs: [URL] = []
        func add(_ e: String) { lock.withLock { events.append(e) } }
    }

    private static func follow(_ url: URL, code: String?, error: String? = nil) async -> Bool {
        let q = DriveFixture.query(URLRequest(url: url))
        guard let redirect = q["redirect_uri"], let state = q["state"] else { return false }
        var target = "\(redirect)?state=\(state)"
        if let code { target += "&code=\(code)" }
        if let error { target += "&error=\(error)" }
        Task.detached { _ = try? await URLSession.shared.data(from: URL(string: target)!) }
        return true
    }

    // TV: §3.1.14 steps 3–4 and 6 (PKCE exchange, retry with prompt=consent when no refresh token, token stored)
    @Test func interactiveFlowStoresAnOfflineToken() async throws {
        let f = TempFolder("aa-signin")
        let rec = Recorder()
        var exchanges = 0
        let transport = DriveMockTransport { r, _ in
            let body = String(decoding: r.httpBody ?? Data(), as: UTF8.self)
            #expect(body.contains("grant_type=authorization_code") && body.contains("code_verifier="))
            #expect(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A"))
            exchanges += 1
            if exchanges == 1 {   // no refresh token on the first round → one retry with prompt=consent
                return .init(status: 200, body: Data(#"{"access_token":"A1","expires_in":3599,"token_type":"Bearer"}"#.utf8))
            }
            return .init(status: 200, body: Data(#"{"access_token":"A2","expires_in":3599,"refresh_token":"R2","token_type":"Bearer"}"#.utf8))
        }
        let hooks = DriveSignInHooks(
            started: { url, _ in rec.add("started"); rec.lock.withLock { rec.consentURLs.append(url) } },
            ended: { rec.add("ended") },
            openBrowser: { url in await DriveInteractiveSignInTests.follow(url, code: "4/xyz") })
        let secretFile = try f.write("google_client_secret.json", DriveFixture.clientSecret)
        let vault = DriveTokenVault(folder: f.url.appending(path: "google-token"), secrets: InMemorySecretStore())
        let auth = DriveAuthorizer(clientSecretFile: secretFile, vault: vault, transport: transport,
                                   clock: FixedClock(local: "2026-09-30T12:00:00", zone: TimeZone(identifier: "UTC")!),
                                   hooks: hooks)
        await #expect(throws: DriveError.interactiveSignInRequired) { try await auth.accessToken(interactive: false) }
        #expect(FileManager.default.fileExists(atPath: vault.folder.path))   // created by the first Drive action
        let token = try await auth.accessToken(interactive: true)
        #expect(token == "A2")
        #expect(vault.hasToken && vault.load()?.refreshToken == "R2")
        #expect(rec.events == ["started", "ended", "started", "ended"])
        #expect(DriveFixture.query(URLRequest(url: rec.consentURLs[0]))["prompt"] == nil)
        #expect(DriveFixture.query(URLRequest(url: rec.consentURLs[1]))["prompt"] == "consent")
    }

    // TV: §3.1.14 step 4 (consent refused) and §6.3 (Cancel / timeout)
    @Test func refusedCancelledAndTimedOut() async throws {
        let f = TempFolder("aa-signin")
        let secretFile = try f.write("google_client_secret.json", DriveFixture.clientSecret)
        let transport = DriveMockTransport { _, _ in .init(status: 500) }
        let clock = FixedClock(local: "2026-09-30T12:00:00", zone: TimeZone(identifier: "UTC")!)
        func make(_ hooks: DriveSignInHooks, timeout: Duration = .seconds(300)) -> DriveAuthorizer {
            DriveAuthorizer(clientSecretFile: secretFile,
                            vault: DriveTokenVault(folder: f.url.appending(path: "google-token"), secrets: InMemorySecretStore()),
                            transport: transport, clock: clock, hooks: hooks, signInTimeout: timeout)
        }
        let denied = make(DriveSignInHooks(started: { _, _ in }, ended: {},
                                           openBrowser: { url in await DriveInteractiveSignInTests.follow(url, code: nil, error: "access_denied") }))
        do {
            _ = try await denied.accessToken(interactive: true)
            Issue.record("expected access_denied")
        } catch let e as DriveError {
            #expect(e == .oauth(code: "access_denied", description: ""))
            #expect(e.localizedDescription.hasSuffix(DriveError.setupHint))
        }
        let cancelled = make(DriveSignInHooks(started: { _, cancel in cancel() }, ended: {}, openBrowser: { _ in true }))
        await #expect(throws: DriveError.signInCancelled) { try await cancelled.accessToken(interactive: true) }
        let slow = make(DriveSignInHooks(started: { _, _ in }, ended: {}, openBrowser: { _ in true }), timeout: .milliseconds(200))
        await #expect(throws: DriveError.signInTimedOut) { try await slow.accessToken(interactive: true) }
        let noClient = DriveAuthorizer(clientSecretFile: f.file("missing.json"),
                                       vault: DriveTokenVault(folder: f.url.appending(path: "t"), secrets: InMemorySecretStore()),
                                       transport: transport, clock: clock, hooks: .none)
        await #expect(throws: DriveError.notConfigured) { try await noClient.accessToken(interactive: true) }
    }
}
