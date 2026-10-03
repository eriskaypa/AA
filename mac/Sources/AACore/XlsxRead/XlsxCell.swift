// Spec: 10 §X.4.5 (cell loading), §X.4.10 (IsEmpty), VESSEL-305 (typed cell model), VESSEL-316 (the seven error
//       codes), VESSEL-319.
import Foundation

/// Cell error values (`t="e"`); unknown error texts (e.g. `#SPILL!`) leave the cell blank (X.8.7).
public enum XlsxErrorCode: String, Sendable, Hashable, CaseIterable {
    case null = "#NULL!", divisionByZero = "#DIV/0!", value = "#VALUE!", reference = "#REF!", name = "#NAME?",
         number = "#NUM!", notAvailable = "#N/A"
}

/// Exactly one kind per cell; DateTime and TimeSpan keep ClosedXML's representation (the serial, already shifted for
/// 1904 — VESSEL-310); calendar values are computed on demand and can throw (VESSEL-309).
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

    /// X.4.10 / VESSEL-319: blank or empty text, no formula, no comment (whitespace-only text is NOT empty).
    public var isEmpty: Bool {
        (value == .blank || value == .text("")) && !hasFormula && !hasComment
    }
}
