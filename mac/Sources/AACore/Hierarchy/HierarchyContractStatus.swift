// Spec: ARCHITECTURE.md §6.1, §11 — W-HIER's contract flag, read by `ContractStatus.isImplemented(.wHier)`.
// Every W-HIER AACore contract (§6.8 TagParser) is real.
extension ContractStatus { public static let wHierImplemented = true }
