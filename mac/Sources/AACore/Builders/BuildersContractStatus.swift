// Spec: ARCHITECTURE.md §6.1, §11 — W-BUILD's contract flag, read by `ContractStatus.isImplemented(.wBuild)`.
// W-BUILD's AACore code (AACore/Builders: builder engine, saved-list rows, editing rules) is real.
extension ContractStatus { public static let wBuildImplemented = true }
