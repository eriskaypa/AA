// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 02 REPO-050 (working-range coercion; changed dates come out `.asCalendarDate`, ARCH §3.4). Compiling stub
// created by F1; F2 replaces this file in place. The stub returns both dates unchanged (ARCH §11).
import Foundation

public enum WorkRange {
    public static func coerce(start: NetDateTime?, deadline: NetDateTime?, editedStart: Bool)
        -> (start: NetDateTime?, deadline: NetDateTime?) {
        // PLACEHOLDER(F2)
        (start: start, deadline: deadline)
    }
}
