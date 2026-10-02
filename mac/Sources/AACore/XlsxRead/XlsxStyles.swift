// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5, 10 §X.7.1
// Spec: 10 §X.4.3 (styles → numeric kind), §X.4.4 (custom-format classifier), X.8.2. Compiling stub created by F1;
// F2 replaces this file in place. The stubs classify everything as a plain number (ARCH §11).
import Foundation

public enum NumberKind: Sendable, Hashable { case number, dateTime, timeSpan }

public enum XlsxStyles {
    /// Built-in `numFmtId` → kind (18–21, 45–47 → timeSpan; 14–16, 22 → dateTime; else number).
    public static func builtinKind(_ numFmtId: Int) -> NumberKind {
        // PLACEHOLDER(F2)
        .number
    }

    /// Exact port of ClosedXML `GetDataTypeFromFormat` (X.4.4).
    public static func classifyCustom(_ code: String) -> NumberKind {
        // PLACEHOLDER(F2)
        .number
    }
}
