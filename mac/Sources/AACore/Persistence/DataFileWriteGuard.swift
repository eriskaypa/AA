// Spec: 01 DATA-180, §MP.3.4 (pre-write fingerprint check); ARCHITECTURE.md §5.2. F1 declares and calls the hook;
//       W-PERSIST implements it (DataFileFingerprint) and F3 installs it at launch.
import Foundation

public protocol DataFileWriteGuard: AnyObject, Sendable {
    /// Called on the writer queue right before the atomic write of `url`; false → the job fails `.pausedByGuard`.
    func shouldWrite(to url: URL) -> Bool
    /// Called on the writer queue after the rename, with the exact bytes now on disk (after encryption).
    func didWrite(to url: URL, bytes: Data)
    /// Called after every load of the active data file, with the raw bytes read (before decryption).
    func didLoad(from url: URL, bytes: Data)
}
