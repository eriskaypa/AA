// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 10 §X.4.13 (error model), VESSEL-301/302/309. Compiling stub created by F1; F2 replaces this file in place.
import Foundation

/// `.gate` carries the VESSEL-301 message verbatim; `.message` carries the VESSEL-309 verbatim messages;
/// `.corrupt(detail:)` renders "The file could not be opened as an Excel workbook (.xlsx)." + detail (VESSEL-302).
/// Reader-level errors ("Could not find the Shippalm header row …", "The workbook is empty.") stay in the owning
/// readers (W-CREW, W-VESSEL).
public enum XlsxReadError: Error, LocalizedError, Sendable {
    case gate(String)
    case message(String)
    case corrupt(detail: String)

    public var errorDescription: String? {
        // PLACEHOLDER(F2) — F2 owns the exact VESSEL-302 composition.
        switch self {
        case .gate(let m), .message(let m): return m
        case .corrupt(let detail): return "The file could not be opened as an Excel workbook (.xlsx)." + detail
        }
    }
}
