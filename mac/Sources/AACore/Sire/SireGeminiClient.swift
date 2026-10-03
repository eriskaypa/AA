// Spec: 12 SIRE-029, §3.8 (GeminiService: endpoint, 60 s timeout, body, BuildPrompt, ParseResponse, outcome texts,
//       ExtractErrorMessage), §6.9 (URLSession ephemeral, key in the `x-goog-api-key` header, error mapping,
//       constants in one place), DECISIONS 12 Q-6 (keep model/params, `maxOutputTokens` raised to 8192), §7.7 vectors.
import Foundation

/// Google Gemini REST client for AI task suggestions. Sendable; one call per request.
public struct SireGeminiClient: Sendable {
    public static let model = "gemini-2.5-pro"
    public static let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    public static let temperature = 0.4
    /// DECISIONS 12 Q-6 (Windows: 2048 — thinking tokens count against it).
    public static let maxOutputTokens = 8192
    public static let timeout: TimeInterval = 60

    public static let noKeyMessage = "No Gemini API key set. Use Tools ▸ 'Set Gemini API key…' first."
    public static let emptyResponseMessage = "Gemini returned an empty response. Try again."
    public static let timeoutMessage = "Request timed out. Check your internet connection and try again."

    let session: URLSession

    /// `session` defaults to an ephemeral session with a 60 s request timeout (tests inject a stubbed one).
    public init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = SireGeminiClient.timeout
        self.session = URLSession(configuration: c)
    }

    public static var endpoint: URL {
        URL(string: "\(baseURL)/models/\(model):generateContent")!
    }

    /// The POST request: JSON body, key in the `x-goog-api-key` header (never in the URL).
    public static func request(prompt: String, apiKey: String) -> URLRequest {
        var r = URLRequest(url: endpoint, timeoutInterval: timeout)
        r.httpMethod = "POST"
        r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let body: JSONValue = .object(JSONObject([
            ("contents", .array([.object(JSONObject([("parts", .array([.object(JSONObject([("text", .string(prompt))]))]))]))])),
            ("generationConfig", .object(JSONObject([("temperature", .number(JSONNumber(lexeme: "0.4"))),
                                                     ("maxOutputTokens", .number(JSONNumber(maxOutputTokens)))]))),
        ]))
        r.httpBody = (try? JSONWriter.data(body)) ?? Data()
        return r
    }

    /// `GenerateTaskSuggestionsAsync`: the tasks, or the exact error text of §3.8.
    public func suggestTasks(for q: SireQuestion, apiKey: String) async -> Result<[String], SireGeminiError> {
        if NetText.isBlank(apiKey) { return .failure(SireGeminiError(SireGeminiClient.noKeyMessage)) }
        let req = SireGeminiClient.request(prompt: SireGeminiClient.buildPrompt(q), apiKey: apiKey)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError {
            if e.code == .timedOut { return .failure(SireGeminiError(SireGeminiClient.timeoutMessage)) }
            return .failure(SireGeminiError("Network error: \(e.localizedDescription)"))
        } catch is CancellationError {
            return .failure(SireGeminiError(SireGeminiClient.timeoutMessage))
        } catch {
            return .failure(SireGeminiError("Unexpected error: \(error.localizedDescription)"))
        }
        let body = String(decoding: data, as: UTF8.self)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            return .failure(SireGeminiError("Gemini API error \(status): \(SireGeminiClient.extractErrorMessage(body))"))
        }
        do {
            let tasks = try SireGeminiClient.parseResponse(data)
            return tasks.isEmpty ? .failure(SireGeminiError(SireGeminiClient.emptyResponseMessage)) : .success(tasks)
        } catch {
            return .failure(SireGeminiError("Unexpected error: \(error.message)"))
        }
    }

    // MARK: Prompt (BuildPrompt — LF throughout)

    public static let preamble = "You are a maritime SIRE 2.0 inspection expert. Based on the following SIRE 2.0 inspection question, generate specific, actionable inspection tasks that an inspector should complete. Generate as many tasks as needed to thoroughly cover the question — do not limit yourself."

    public static func buildPrompt(_ q: SireQuestion) -> String {
        var s = ""
        func line(_ t: String = "") { s += t; s += "\n" }
        line(preamble)
        line()
        line("Each task must be a concrete action using verbs like: verify, check, review, confirm, inspect, examine, ensure, compare, test, record.")
        line("Return ONLY a numbered list (1. 2. 3. etc.) with one task per line. No headings, explanations, or additional commentary.")
        line()
        line("=== QUESTION CONTEXT ===")
        line()
        line("Question Number: \(q.questionNumber)")
        line("Chapter: \(q.chapterDisplay)")
        line("Vessel Types: \(q.vesselTypesDisplay)")
        line("ROVIQ Sequence: \(q.roviqSequence)")
        line()
        line("Full Question Text:\n\(q.fullQuestionText)")
        let optional: [(String, String)] = [
            ("Objective", q.objective), ("Expected Evidence", q.expectedEvidence),
            ("Suggested Inspector Actions", q.suggestedInspectorActions),
            ("Potential Negative Observation Grounds", q.potentialNegativeObservationGrounds),
            ("Industry Guidance", q.industryGuidance), ("Inspection Guidance", q.inspectionGuidance),
            ("Publications", q.publications),
        ]
        for (label, value) in optional where !NetText.isBlank(value) { line("\n\(label):\n\(value)") }
        return s
    }

    // MARK: Response parsing (ParseResponse — exact)

    /// .NET `JsonElement` type names used in its InvalidOperationException text.
    static func kindName(_ v: JSONValue) -> String {
        switch v {
        case .null: return "Null"
        case .bool(let b): return b ? "True" : "False"
        case .number: return "Number"
        case .string, .rawString: return "String"
        case .array: return "Array"
        case .object: return "Object"
        }
    }

    static func typeMismatch(_ wanted: String, _ v: JSONValue) -> SireGeminiError {
        SireGeminiError("The requested operation requires an element of type '\(wanted)', but the target element has type '\(kindName(v))'.")
    }

    /// `ParseResponse`: every candidate → content → parts → text, split on `\n` (empties removed), trimmed, the
    /// leading `^\d+[\.\)\-]\s*` removed, trimmed again, kept when longer than 5 UTF-16 units.
    public static func parseResponse(_ data: Data) throws(SireGeminiError) -> [String] {
        let root: JSONValue
        do { root = try JSONParser.parse(data) } catch { throw SireGeminiError(String(describing: error)) }
        guard case .object(let o) = root else { throw typeMismatch("Object", root) }
        var tasks: [String] = []
        guard let candidates = o.rawValue(forKey: "candidates") else { return tasks }
        guard case .array(let cands) = candidates else { throw typeMismatch("Array", candidates) }
        for candidate in cands {
            guard case .object(let co) = candidate else { throw typeMismatch("Object", candidate) }
            guard let content = co.rawValue(forKey: "content") else { continue }
            guard case .object(let cto) = content else { throw typeMismatch("Object", content) }
            guard let parts = cto.rawValue(forKey: "parts") else { continue }
            guard case .array(let pa) = parts else { throw typeMismatch("Array", parts) }
            for part in pa {
                guard case .object(let po) = part else { throw typeMismatch("Object", part) }
                guard let textElem = po.rawValue(forKey: "text") else { continue }
                let text: String
                switch textElem {
                case .null: text = ""
                case .string(let s), .rawString(let s): text = s
                default: throw typeMismatch("String", textElem)
                }
                for line in SireText.split(SireText.units(text), on: [0x0A], removeEmpty: true) {
                    let t = SireText.trim(stripNumbering(SireText.trim(line)))
                    if t.count > 5 { tasks.append(SireText.string(t)) }
                }
            }
        }
        return tasks
    }

    /// Removes `^\d+[\.\)\-]\s*` (.NET: `\d` = Unicode Nd, `\s` = white space incl. U+0085 and Z*).
    static func stripNumbering(_ u: [UInt16]) -> [UInt16] {
        var i = 0
        while i < u.count, SireText.isDigit(u[i]) { i += 1 }
        guard i > 0, i < u.count, u[i] == 0x2E || u[i] == 0x29 || u[i] == 0x2D else { return u }
        i += 1
        while i < u.count, isRegexSpace(u[i]) { i += 1 }
        return Array(u[i...])
    }

    static func isRegexSpace(_ u: UInt16) -> Bool {
        switch u {
        case 0x09...0x0D, 0x20, 0x85: return true
        default:
            switch SireText.category(u) {
            case .spaceSeparator?, .lineSeparator?, .paragraphSeparator?: return true
            default: return false
            }
        }
    }

    /// `ExtractErrorMessage`: `error.message` (or "Unknown error" when null), else the body (first 200 UTF-16
    /// units + "..." when longer).
    public static func extractErrorMessage(_ body: String) -> String {
        if let root = try? JSONParser.parse(body), case .object(let o) = root,
           let err = o.rawValue(forKey: "error"), case .object(let eo) = err,
           let msg = eo.rawValue(forKey: "message") {
            switch msg {
            case .null: return "Unknown error"
            case .string(let s), .rawString(let s): return s
            default: break                                     // GetString() throws → caught → body
            }
        }
        let u = Array(body.utf16)
        return u.count > 200 ? SireText.string(u[..<200]) + "..." : body
    }
}

/// A Gemini outcome text shown verbatim in the `AI Suggest` warning.
public struct SireGeminiError: Error, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
