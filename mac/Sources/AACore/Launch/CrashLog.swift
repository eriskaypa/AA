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

    /// 01 DATA-183: `open(O_WRONLY|O_APPEND|O_CREAT|O_CLOEXEC, 0644)` and the whole block in ONE `write`, so blocks
    /// from several processes (a read-only copy and the editor) never overwrite each other.
    static func appendText(_ text: String, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return false
        }
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty else { return true }
        var written = 0
        while written < bytes.count {
            let n = bytes.withUnsafeBytes { buf in
                write(fd, buf.baseAddress!.advanced(by: written), bytes.count - written)
            }
            if n < 0 {
                if errno == EINTR { continue }
                return false
            }
            written += n
        }
        return true
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

    /// Installs async-signal-safe handlers for SIGABRT, SIGSEGV, SIGBUS, SIGILL and SIGTRAP that append the marker to
    /// crash.log (primary if its folder is writable, else the fallback), restore `SIG_DFL` and re-raise. The file is
    /// opened inside the handler (`open(2)` / `write(2)` are async-signal-safe), so a clean run never creates it.
    @discardableResult
    public static func installSignalMarker(appFolder: URL?) -> URL? {
        var target: URL?
        for u in [appFolder?.appending(path: fileName), fallbackURL].compactMap({ $0 }) {
            let dir = u.deletingLastPathComponent()
            if u == fallbackURL { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
            if access(dir.path, W_OK) == 0 { target = u; break }
        }
        guard let target else { return nil }
        CrashSignalState.install(path: target.path)
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

    // MARK: Next-launch scan (SHELL-197), one offset per data folder

    /// The pre-fix single key; read once as the starting offset of a folder that has no key of its own yet, then
    /// removed (a second folder must never inherit it).
    public static let legacyScanOffsetKey = MacPreferences.Key("aa.shell.crashLogScanOffset")

    /// `aa.shell.crashLogScanOffset.<sha-256 of the canonical folder path, 16 hex>` — crash.log lives in the data
    /// folder, so the default folder and a portable / `--data-dir` folder each keep their own offset.
    public static func scanOffsetKey(appFolder: URL) -> MacPreferences.Key {
        let hex = PersistHost.sha256Hex(Data(PersistHost.canonicalPath(appFolder).utf8))
        return MacPreferences.Key(legacyScanOffsetKey.rawValue + "." + hex.prefix(16))
    }

    /// Scans the bytes written since `storedOffset` (a stored offset past the end means the log was replaced or
    /// truncated → from byte 0). Returns the offset to store and the last marker's signal, if any.
    public static func scan(_ data: Data, storedOffset: Int?) -> (newOffset: Int, signal: Int32?) {
        let stored = max(storedOffset ?? 0, 0)
        let start = stored <= data.count ? stored : 0
        let fresh = String(decoding: data[(data.startIndex + start)...], as: UTF8.self)
        return (data.count, markers(in: fresh).last)
    }

    /// Reads `<appFolder>/crash.log`, scans it from this folder's stored offset and stores the new offset.
    public static func scanForPreviousCrash(appFolder: URL, prefs: MacPreferences) -> (log: URL, signal: Int32)? {
        let log = appFolder.appending(path: fileName)
        guard let data = try? Data(contentsOf: log) else { return nil }
        let key = scanOffsetKey(appFolder: appFolder)
        var stored = prefs.string(key).flatMap { Int($0) }
        if stored == nil, let legacy = prefs.string(legacyScanOffsetKey).flatMap({ Int($0) }) {
            stored = legacy
            prefs.set(nil as String?, legacyScanOffsetKey)
        }
        let r = scan(data, storedOffset: stored)
        prefs.set(String(r.newOffset), key)
        return r.signal.map { (log, $0) }
    }
}

/// Pre-built marker buffers indexed by signal number and the log path; only `open`/`write` run inside the handler.
private enum CrashSignalState {
    static let maxSignal = 32
    nonisolated(unsafe) static var path: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) static var lengths = UnsafeMutablePointer<Int>.allocate(capacity: maxSignal)
    nonisolated(unsafe) static var texts = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>.allocate(capacity: maxSignal)

    static func install(path newPath: String) {
        path = strdup(newPath)
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
    if let path = CrashSignalState.path, sig > 0, Int(sig) < CrashSignalState.maxSignal,
       let p = CrashSignalState.texts[Int(sig)] {
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        if fd >= 0 {
            _ = write(fd, p, CrashSignalState.lengths[Int(sig)])
            close(fd)
        }
    }
    signal(sig, SIG_DFL)
    raise(sig)
}
