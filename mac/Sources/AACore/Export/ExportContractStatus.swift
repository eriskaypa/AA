// Spec: ARCHITECTURE.md §6.1, §11 — W-PDF's contract flag, read by `ContractStatus.isImplemented(.wPdf)`: every
// W-PDF contract (AACore/Export, AA/Export `PdfExportFlows`) is real.
extension ContractStatus { public static let wPdfImplemented = true }
