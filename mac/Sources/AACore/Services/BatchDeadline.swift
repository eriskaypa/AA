// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 02 REPO-052 (batch set / clear deadline). Compiling stub created by F1; F2 replaces this file in place.
// The stubs change nothing (ARCH §11).
import Foundation

@MainActor public enum BatchDeadline {
    public static func setDeadline(_ item: AnyObject?, date: NetDateTime?) -> Bool {
        // PLACEHOLDER(F2)
        false
    }

    public static func setDeadlineAll(_ items: [AnyObject], date: NetDateTime?) -> Int {
        // PLACEHOLDER(F2)
        0
    }

    /// Prefill for the date prompt: `.some(nil)` = every item has no deadline; `nil` = mixed.
    public static func sharedDeadline(of items: [AnyObject]) -> NetDateTime?? {
        // PLACEHOLDER(F2)
        nil
    }
}
