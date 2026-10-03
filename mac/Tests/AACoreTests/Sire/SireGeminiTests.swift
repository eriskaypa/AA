// Tests: 12 §7.7 (TV-GEM-1…7 through a URLProtocol stub — never the network), §3.8 outcome texts, §6.9 (header key,
//        ephemeral session), DECISIONS 12 Q-6 (maxOutputTokens 8192); GeminiKeyStore (§6.9, BUILD-A26, DECISIONS 12).
import Foundation
import Testing
@testable import AACore

/// Routes each stubbed session to its own handler (tests run in parallel).
final class SireStubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest, Data) throws -> (Int, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var captured: [String: (URLRequest, Data)] = [:]

    static func session(_ handler: @escaping Handler) -> (URLSession, String) {
        let id = UUID().uuidString
        lock.lock(); handlers[id] = handler; lock.unlock()
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [SireStubURLProtocol.self]
        c.httpAdditionalHeaders = ["X-Sire-Stub": id]
        return (URLSession(configuration: c), id)
    }

    static func lastRequest(_ id: String) -> (URLRequest, Data)? { lock.lock(); defer { lock.unlock() }; return captured[id] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Sire-Stub") ?? ""
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                body.append(buf, count: n)
            }
            stream.close()
        }
        Self.lock.lock()
        let handler = Self.handlers[id]
        Self.captured[id] = (request, body)
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, data) = try handler(request, body)
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite struct SireGeminiTests {
    let q = SireSynthetic.q2110

    // TV: 12 TV-GEM-1
    @Test func parseNumberedLines() throws {
        let body = #"{"candidates":[{"content":{"parts":[{"text":"1. Verify the log.\n2) Check pump\n\n3- Inspect hoses thoroughly\n- Review plan\nOK\n10.Test alarm\n   \n123456\n12345"}]}}]}"#
        #expect(try SireGeminiClient.parseResponse(Data(body.utf8))
                == ["Verify the log.", "Check pump", "Inspect hoses thoroughly", "- Review plan", "Test alarm", "123456"])
    }

    // TV: 12 TV-GEM-2
    @Test func candidatesAndPartsConcatenate() throws {
        let body = #"{"candidates":[{"content":{"parts":[{"text":"1. First task here"},{"text":"2. Second task here"}]}},{"content":{"parts":[{"text":"Third task here"}]}},{"finishReason":"MAX_TOKENS"}]}"#
        #expect(try SireGeminiClient.parseResponse(Data(body.utf8)) == ["First task here", "Second task here", "Third task here"])
        #expect(throws: SireGeminiError.self) { _ = try SireGeminiClient.parseResponse(Data(#"{"candidates":{}}"#.utf8)) }
        #expect(throws: SireGeminiError.self) { _ = try SireGeminiClient.parseResponse(Data("not json".utf8)) }
    }

    // TV: 12 TV-GEM-3
    @Test func emptyResponse() async {
        let (s, _) = SireStubURLProtocol.session { _, _ in (200, Data("{}".utf8)) }
        let r = await SireGeminiClient(session: s).suggestTasks(for: q, apiKey: "k")
        #expect(r == .failure(SireGeminiError("Gemini returned an empty response. Try again.")))
    }

    // TV: 12 TV-GEM-4
    @Test func apiError() async {
        let (s, _) = SireStubURLProtocol.session { _, _ in
            (400, Data(#"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}"#.utf8))
        }
        let r = await SireGeminiClient(session: s).suggestTasks(for: q, apiKey: "bad")
        #expect(r == .failure(SireGeminiError("Gemini API error 400: API key not valid. Please pass a valid API key.")))
    }

    // TV: 12 TV-GEM-5
    @Test func nonJSONErrorBody() async {
        let plain = String(repeating: "x", count: 250)
        let (s, _) = SireStubURLProtocol.session { _, _ in (503, Data(plain.utf8)) }
        let r = await SireGeminiClient(session: s).suggestTasks(for: q, apiKey: "k")
        #expect(r == .failure(SireGeminiError("Gemini API error 503: " + String(repeating: "x", count: 200) + "...")))
        #expect(SireGeminiClient.extractErrorMessage(#"{"error":{"message":null}}"#) == "Unknown error")
        #expect(SireGeminiClient.extractErrorMessage(#"{"error":{"message":5}}"#) == #"{"error":{"message":5}}"#)
        #expect(SireGeminiClient.extractErrorMessage("short") == "short")
    }

    // TV: 12 TV-GEM-6
    @Test func prompt() {
        let p = SireGeminiClient.buildPrompt(q)
        #expect(p.hasPrefix(SireGeminiClient.preamble + "\n\nEach task must be a concrete action"))
        #expect(p.contains("Question Number: 2.1.10\n"))
        #expect(p.contains("Chapter: Ch 2: Certs\n"))
        #expect(p.contains("Vessel Types: Oil, LNG\n"))
        #expect(p.contains("ROVIQ Sequence: Bridge, Documentation\n"))
        #expect(p.contains("Full Question Text:\nIs beta ok?\n"))
        #expect(p.contains("\nObjective:\nObj B\n"))
        #expect(p.contains("\nExpected Evidence:\nEv B\n"))
        #expect(!p.contains("Suggested Inspector Actions:"))
        #expect(!p.contains("\r"))
        #expect(!SireGeminiClient.buildPrompt(SireSynthetic.q212).contains("Expected Evidence:"))
    }

    // TV: 12 TV-GEM-7 (+ DECISIONS 12 Q-6: header key, 8192 tokens)
    @Test func requestShape() async throws {
        let (s, id) = SireStubURLProtocol.session { _, _ in
            (200, Data(#"{"candidates":[{"content":{"parts":[{"text":"1. Verify the crew list\n2. Check the log"}]}}]}"#.utf8))
        }
        let r = await SireGeminiClient(session: s).suggestTasks(for: q, apiKey: "AIza-test-key")
        #expect(r == .success(["Verify the crew list", "Check the log"]))
        let (req, body) = try #require(SireStubURLProtocol.lastRequest(id))
        #expect(req.httpMethod == "POST")
        #expect(req.url?.path == "/v1beta/models/gemini-2.5-pro:generateContent")
        #expect(req.url?.host == "generativelanguage.googleapis.com")
        #expect(req.url?.query == nil)
        #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "AIza-test-key")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")
        guard case .object(let o) = try JSONParser.parse(body),
              case .array(let contents) = o["contents"], case .object(let c0) = contents[0],
              case .array(let parts) = c0["parts"], case .object(let p0) = parts[0],
              case .object(let gen) = o["generationConfig"] else { Issue.record("body shape"); return }
        #expect(p0["text"]?.stringValue == SireGeminiClient.buildPrompt(q))
        #expect(gen["temperature"]?.numberValue?.doubleValue == 0.4)
        #expect(gen["maxOutputTokens"]?.numberValue?.intValue == 8192)
    }

    @Test func networkErrorsAndBlankKey() async {
        let (timeout, _) = SireStubURLProtocol.session { _, _ in throw URLError(.timedOut) }
        #expect(await SireGeminiClient(session: timeout).suggestTasks(for: q, apiKey: "k")
                == .failure(SireGeminiError("Request timed out. Check your internet connection and try again.")))
        let (offline, _) = SireStubURLProtocol.session { _, _ in throw URLError(.notConnectedToInternet) }
        let r = await SireGeminiClient(session: offline).suggestTasks(for: q, apiKey: "k")
        if case .failure(let e) = r { #expect(e.message.hasPrefix("Network error: ")) } else { Issue.record("expected failure") }
        #expect(await SireGeminiClient(session: offline).suggestTasks(for: q, apiKey: "  ")
                == .failure(SireGeminiError("No Gemini API key set. Use Tools ▸ 'Set Gemini API key…' first.")))
        let (garbage, _) = SireStubURLProtocol.session { _, _ in (200, Data("<html>".utf8)) }
        let g = await SireGeminiClient(session: garbage).suggestTasks(for: q, apiKey: "k")
        if case .failure(let e) = g { #expect(e.message.hasPrefix("Unexpected error: ")) } else { Issue.record("expected failure") }
    }
}

/// One isolated key-store environment; removes its preferences domain when released.
@MainActor private final class SireKeyEnv {
    let folder = TempFolder("aa-sire-key")
    let secrets = InMemorySecretStore()
    let suite = "aa-sire-tests-\(UUID().uuidString)"
    let settings: SettingsStore
    let prefs: MacPreferences
    let store: GeminiKeyStore

    init(settingsJSON: String? = nil) throws {
        if let settingsJSON { try folder.write("settings-under-test.json", settingsJSON) }
        settings = SettingsStore(fileURL: folder.file("settings-under-test.json"), secrets: secrets)
        settings.reload()
        prefs = MacPreferences(defaults: UserDefaults(suiteName: suite)!)
        store = GeminiKeyStore(secrets: secrets, settings: settings, preferences: prefs)
    }

    isolated deinit { UserDefaults().removePersistentDomain(forName: suite) }
}

@MainActor @Suite struct GeminiKeyStoreTests {
    // BUILD-A26 / Q-5: blank deletes the Keychain item; non-blank stores the trimmed value.
    @Test func setAndClear() throws {
        let env = try SireKeyEnv()
        let store = env.store, secrets = env.secrets
        #expect(!store.hasKey && store.key() == nil)
        try store.setKey("  AIza-key \n")
        #expect(store.key() == "AIza-key" && store.hasKey)
        #expect(try secrets.read(service: "com.eriskay.aa.gemini", account: "GeminiApiKey") == Data("AIza-key".utf8))
        try store.setKey("   ")
        #expect(store.key() == nil && !store.hasKey)
        #expect(try secrets.read(service: "com.eriskay.aa.gemini", account: "GeminiApiKey") == nil)
        try store.setKey(nil)
        secrets.failAll = true
        #expect(throws: SecretStoreError.self) { try store.setKey("x") }
        #expect(store.key() == nil)
    }

    // DECISIONS 12: imported once; the settings key stays untouched; a later clear survives a "restart".
    @Test func importOnce() throws {
        let original = #"{"DarkMode":true,"GeminiApiKey":"AIza-from-windows"}"#
        let env = try SireKeyEnv(settingsJSON: original)
        env.store.importFromSettingsOnce()
        #expect(env.store.key() == "AIza-from-windows")
        #expect(try env.folder.readText("settings-under-test.json") == original)
        try env.store.setKey("")
        let relaunched = GeminiKeyStore(secrets: env.secrets, settings: env.settings, preferences: env.prefs)
        relaunched.importFromSettingsOnce()
        #expect(relaunched.key() == nil)
        #expect(try env.folder.readText("settings-under-test.json") == original)
    }

    @Test func noLegacyKeyLeavesTheImportPending() throws {
        let env = try SireKeyEnv(settingsJSON: #"{"DarkMode":false}"#)
        env.store.importFromSettingsOnce()
        #expect(!env.prefs.bool(GeminiKeyStore.importedKey, default: false))
        #expect(env.store.key() == nil)
    }

    @Test func importDoesNotOverwriteAnExistingKey() throws {
        let env = try SireKeyEnv(settingsJSON: #"{"GeminiApiKey":"old"}"#)
        try env.store.setKey("mac-key")
        env.store.importFromSettingsOnce()
        #expect(env.store.key() == "mac-key")
    }
}
