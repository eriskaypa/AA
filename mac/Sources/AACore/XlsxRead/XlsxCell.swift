// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5, 10 §X.7.1
// Spec: 10 §X.4.5 (cell loading), §X.4.10 (IsEmpty), VESSEL-305. Compiling stub created by F1; F2 replaces this
// file in place (same types, may add API).
import Foundation

/// Cell error values (`t="e"`); unknown error texts (e.g. `#SPILL!`) leave the cell blank (X.8.7).
public enum XlsxErrorCode: String, Sendable, Hashable, CaseIterable {
    case null = "#NULL!", divisionByZero = "#DIV/0!", value = "#VALUE!", reference = "#REF!", name = "#NAME?",
         number = "#NUM!", notAvailable = "#N/A"
}

public enum XlsxValue: Sendable, Equatable {
    case blank, text(String), number(Double), boolean(Bool), error(XlsxErrorCode), dateTime(serial: Double),
         timeSpan(serial: Double)
}

public struct XlsxCell: Sendable, Equatable {
    public var value: XlsxValue
    public var hasFormula: Bool
    public var hasComment: Bool

    public init(value: XlsxValue = .blank, hasFormula: Bool = false, hasComment: Bool = false) {
        self.value = value; self.hasFormula = hasFormula; self.hasComment = hasComment
    }

    /// X.4.10: blank or empty text, no formula, no comment.
    public var isEmpty: Bool {
        (value == .blank || value == .text("")) && !hasFormula && !hasComment
    }
}
