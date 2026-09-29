// Spec: 01 DATA-029, §6.4 (same-directory temp, F_FULLFSYNC, rename, fallbacks, temp always removed).
import Foundation
import Darwin

public enum AtomicWriteError: Error, LocalizedError, Sendable {
    case posix(operation: String, path: String, code: Int32)
    public var errorDescription: String? {
        switch self {
        case let .posix(op, path, code):
            return "Could not \(op) \(path): \(String(cString: strerror(code)))"
        }
    }
}

public enum AtomicWrite {
    /// Writes `data` to a unique temp file next to `url`, flushes it to disk (`F_FULLFSYNC`, falling back to
    /// `fsync`) and renames it over `url`, so a concurrent reader never sees a torn file. On `EXDEV`/`EPERM`/
    /// `EACCES` falls back to `FileManager.replaceItemAt`, then (last resort) a plain copy. The temp file is always
    /// removed.
    public static func write(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = tempURL(for: url)
        defer { unlink(tmp.path) }
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw AtomicWriteError.posix(operation: "create", path: tmp.path, code: errno) }
        var writeError: Int32 = 0
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + off, raw.count - off)
                if n < 0 {
                    if errno == EINTR { continue }
                    writeError = errno
                    return
                }
                off += n
            }
        }
        if writeError == 0, fcntl(fd, F_FULLFSYNC) != 0, fsync(fd) != 0 { writeError = errno }
        close(fd)
        guard writeError == 0 else { throw AtomicWriteError.posix(operation: "write", path: tmp.path, code: writeError) }
        if rename(tmp.path, url.path) == 0 { return }
        let code = errno
        guard code == EXDEV || code == EPERM || code == EACCES else {
            throw AtomicWriteError.posix(operation: "replace", path: url.path, code: code)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            if (try? FileManager.default.replaceItemAt(url, withItemAt: tmp)) != nil { return }
        }
        try data.write(to: url)                                   // last resort: keep the data over losing it
    }

    /// `"<path>.<32 lowercase hex>.tmp"` in the same directory.
    public static func tempURL(for url: URL) -> URL {
        URL(fileURLWithPath: url.path + "." + UUID().netN + ".tmp")
    }
}
