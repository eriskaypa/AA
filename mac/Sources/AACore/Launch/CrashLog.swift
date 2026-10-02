// Spec: 03 SHELL-001 (crash dialog text), SHELL-197 (crash.log location, fallback, block format), BD.3.5 (crash sink,
//       signal marker), 01 DATA-004; ARCHITECTURE.md §6.9, §9.2. Vectors: 03 BD.7.5.
import Foundation

/// `crash.log` blocks: `[yyyy-MM-dd HH:mm:ss] {details}\r\n\r\n` (local time, UTF-8, appended).
public enum CrashLog {
    public static let fileName = "crash.log"
    public static let dialogTitle = "AA — error"
    public static let notWrittenLine = "The details could not be written to a log file."

    /// `~/Library/Logs/AA/crash.log` (SHELL-197 fallback, W-17).
    public static var fallbackURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/AA", directoryHint: .isDirectory).appending(path: fileName)
    }

    public static func block(details: String, at date: Date) -> String {
        block(details: details, at: date, zone: .current)
    }

    /// Same, with an explicit zone (tests).
    public static func block(details: String, at date: Date, zone: TimeZone) -> String {
        let stamp = NetDateTime(date: date, kind: .local, zone: zone).format(.isoSecond, zone: zone)
        return "[\(stamp)] \(details)\r\n\r\n"
    }

    /// Appends a block to `<appFolder>/crash.log`, else to the fallback; returns the file written, nil if both failed.
    @discardableResult
    public static func append(_ details: String, appFolder: URL?) -> URL? {
        append(details, appFolder: appFolder, fallback: fallbackURL, at: Date())
    }

    @discardableResult
    public static func append(_ details: String, appFolder: URL?, fallback: URL, at date: Date) -> URL? {
        let text = block(details: details, at: date)
        if let appFolder, appendText(text, to: appFolder.appending(path: fileName)) {
            return appFolder.appending(path: fileName)
        }
        if appendText(text, to: fallback) { return fallback }
        return nil
    }

    static func appendText(_ text: String, to url: URL) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) {
                guard fm.createFile(atPath: url.path, contents: nil) else { return false }
            }
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: Data(text.utf8))
            return true
        } catch {
            return false
        }
    }

    /// The SHELL-001 / BD.3.5 dialog body.
    public static func dialogMessage(message: String, writtenTo url: URL?) -> String {
        "AA hit an unexpected error and had to stop:\n\n\(message)\n\n"
            + (url.map { "The full details were written to:\n\($0.path)" } ?? notWrittenLine)
    }

    /// Details for a Swift error: `String(reflecting:)`, a newline, then the call stack.
    public static func details(for error: Error, context: String? = nil, stack: [String] = Thread.callStackSymbols) -> String {
        var s = String(reflecting: error)
        if let context, !context.isEmpty { s = "\(context): " + s }
        return s + "\n" + stack.joined(separator: "\n")
    }

    /// Details for an Objective-C exception.
    public static func details(exceptionName: String, reason: String?, stack: [String]) -> String {
        "\(exceptionName): \(reason ?? "")\n" + stack.joined(separator: "\n")
    }

    // MARK: Signal marker (BD.3.5)

    /// `"[crash marker] signal <n>\r\n\r\n"`.
    public static func markerLine(signal: Int32) -> String { "[crash marker] signal \(signal)\r\n\r\n" }

    public static let markerPrefix = "[crash marker] signal "

    /// Installs async-signal-safe handlers for SIGABRT, SIGSEGV, SIGBUS, SIGILL and SIGTRAP that write the marker to a
    /// pre-opened descriptor (primary, else fallback), restore `SIG_DFL` and re-raise. Returns the file used.
    @discardableResult
    public static func installSignalMarker(appFolder: URL?) -> URL? {
        var target: URL?
        var fd: Int32 = -1
        for u in [appFolder?.appending(path: fileName), fallbackURL].compactMap({ $0 }) {
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            fd = open(u.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            if fd >= 0 { target = u; break }
        }
        guard fd >= 0 else { return nil }
        CrashSignalState.install(fd: fd)
        return target
    }

    /// The signal numbers of every marker line in `text` (the next launch scans the part of crash.log written since
    /// its previous scan).
    public static func markers(in text: String) -> [Int32] {
        var out: [Int32] = []
        for line in text.components(separatedBy: "\r\n") where line.hasPrefix(markerPrefix) {
            if let n = Int32(line.dropFirst(markerPrefix.count)) { out.append(n) }
        }
        return out
    }
}

/// Pre-built marker buffers indexed by signal number and the descriptor; only `write(2)` runs inside the handler.
private enum CrashSignalState {
    static let maxSignal = 32
    nonisolated(unsafe) static var fd: Int32 = -1
    nonisolated(unsafe) static var lengths = UnsafeMutablePointer<Int>.allocate(capacity: maxSignal)
    nonisolated(unsafe) static var texts = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>.allocate(capacity: maxSignal)

    static func install(fd newFD: Int32) {
        fd = newFD
        for i in 0..<maxSignal { lengths[i] = 0; texts[i] = nil }
        for s in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP] where s > 0 && Int(s) < maxSignal {
            let bytes = Array(CrashLog.markerLine(signal: s).utf8)
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
            p.initialize(from: bytes, count: bytes.count)
            texts[Int(s)] = p
            lengths[Int(s)] = bytes.count
            signal(s, crashSignalHandler)
        }
    }
}

private func crashSignalHandler(_ sig: Int32) {
    let fd = CrashSignalState.fd
    if fd >= 0, sig > 0, Int(sig) < CrashSignalState.maxSignal, let p = CrashSignalState.texts[Int(sig)] {
        _ = write(fd, p, CrashSignalState.lengths[Int(sig)])
    }
    signal(sig, SIG_DFL)
    raise(sig)
}
