// PLACEHOLDER(W-PERSIST) — contract: ARCHITECTURE.md §11 (stub support, not a contract)
// The error W-PERSIST's placeholder stubs throw instead of reading or writing anything. Delete this file together
// with the last W-PERSIST placeholder.
import Foundation

enum PersistPlaceholderError: Error, LocalizedError {
    case notAvailable

    var errorDescription: String? {
        // PLACEHOLDER(W-PERSIST)
        "This feature is not available in this build yet."
    }
}
