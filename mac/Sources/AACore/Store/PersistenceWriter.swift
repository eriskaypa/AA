// Spec: 02 REPO-003a (ordered write chain, never on the UI thread), 01 DATA-029, DATA-071, DATA-180 / §MP.3.4
//       (write guard on the writer queue); ARCHITECTURE.md §2.3, §5.2.
import Foundation
import CryptoKit

/// One queued write: immutable bytes (the snapshot), the URL captured at enqueue time, and the local-data key
/// when the file must be encrypted.
public struct WriteJob: Sendable {
    public var bytes: Data
    public var url: URL
    public var encryptionKey: SymmetricKey?
    public init(bytes: Data, url: URL, encryptionKey: SymmetricKey?) {
        self.bytes = bytes; self.url = url; self.encryptionKey = encryptionKey
    }
}

/// Serial FIFO writer (`DispatchQueue "aa.data-writer"`): writes commit strictly in enqueue order, so a newer
/// snapshot can never be overwritten by an older one. Never needs the main thread.
public final class PersistenceWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "aa.data-writer")
    private let lock = NSLock()
    private var guardStorage: DataFileWriteGuard?
    private var hookStorage: (@Sendable (WriteJob) -> Void)?

    public init() {}

    /// The DATA-180 guard (nil = no check). Lock-protected.
    public var writeGuard: DataFileWriteGuard? {
        get { lock.lock(); defer { lock.unlock() }; return guardStorage }
        set { lock.lock(); guardStorage = newValue; lock.unlock() }
    }

    /// Test hook: runs on the writer queue before each job (e.g. to simulate a slow or stuck volume).
    var beforeEachJob: (@Sendable (WriteJob) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return hookStorage }
        set { lock.lock(); hookStorage = newValue; lock.unlock() }
    }

    /// Queues `job` after every earlier job. `completion` runs on the writer queue.
    @discardableResult
    public func enqueue(_ job: WriteJob, completion: @escaping @Sendable (Result<Void, Error>) -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.beforeEachJob?(job)
            do {
                try PersistenceWriter.perform(job, guard: self.writeGuard)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
        queue.async(execute: item)
        return item
    }

    /// Runs `work` on the writer queue (W-PERSIST's watcher check can never race a write).
    public func runOnWriterQueue(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// Blocks until every job queued so far has run, or `timeout` elapses. Returns false on timeout.
    public func waitUntilIdle(timeout: TimeInterval) -> Bool {
        let sema = DispatchSemaphore(value: 0)
        queue.async { sema.signal() }
        return sema.wait(timeout: .now() + timeout) == .success
    }

    /// guard?.shouldWrite → encrypt (when a key is given) → AtomicWrite → guard?.didWrite.
    static func perform(_ job: WriteJob, guard writeGuard: DataFileWriteGuard?) throws {
        if let writeGuard, !writeGuard.shouldWrite(to: job.url) { throw AppStoreError.pausedByGuard }
        let bytes: Data
        if let key = job.encryptionKey {
            bytes = try LocalEncryption.encrypt(job.bytes, key: key)
        } else {
            bytes = job.bytes
        }
        try AtomicWrite.write(bytes, to: job.url)
        writeGuard?.didWrite(to: job.url, bytes: bytes)
    }
}
