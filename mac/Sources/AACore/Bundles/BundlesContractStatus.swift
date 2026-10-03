// Spec: ARCHITECTURE.md §6.1, §11 — W-PERSIST's contract flag, read by `ContractStatus.isImplemented(.wPersist)`:
// every W-PERSIST AACore contract of §6.6 (Bundles, Attachments, SharedSave, Instance) is real.
extension ContractStatus { public static let wPersistImplemented = true }
