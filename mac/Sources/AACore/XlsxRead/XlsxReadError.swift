// Spec: 10 §X.4.13 (error model), VESSEL-301 (gate messages verbatim), VESSEL-302 (corrupt package: the Mac wording
//       plus a one-line detail), VESSEL-309 (the two date-serial messages verbatim), VESSEL-331.
import Foundation

/// `.gate` carries the VESSEL-301 message verbatim; `.message` carries the VESSEL-309 verbatim messages;
/// `.corrupt(detail:)` renders "The file could not be opened as an Excel workbook (.xlsx)." + detail (VESSEL-302).
/// Reader-level errors ("Could not find the Shippalm header row …", "The workbook is empty.") stay in the owning
/// readers (W-CREW, W-VESSEL).
public enum XlsxReadError: Error, LocalizedError, Sendable, Equatable {
    case gate(String)
    case message(String)
    case corrupt(detail: String)

    public static let corruptHeadline = "The file could not be opened as an Excel workbook (.xlsx)."

    /// The text shown inside the importer's "Could not import the … file:\n\n{msg}" box.
    public var errorDescription: String? {
        switch self {
        case .gate(let m), .message(let m): return m
        case .corrupt(let detail):
            return detail.isEmpty ? Self.corruptHeadline : Self.corruptHeadline + "\n" + detail
        }
    }
}
