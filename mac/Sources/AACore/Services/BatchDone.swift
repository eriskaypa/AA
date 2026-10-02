// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 02 REPO-042 (batch mark done / not done). Compiling stub created by F1; F2 replaces this file in place.
// The stubs change nothing and report zero changes (ARCH §11).
import Foundation

@MainActor public enum BatchDone {
    public static func setDone(_ item: AnyObject?, done: Bool) -> Bool {
        // PLACEHOLDER(F2)
        false
    }

    public static func setDoneAll(_ items: [AnyObject], done: Bool) -> Int {
        // PLACEHOLDER(F2)
        0
    }
}
