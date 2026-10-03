// Contract: ARCHITECTURE.md §6.1, §11 — W-FLASH's contract flag, read by `ContractStatus.isImplemented(.wFlash)`.
// Every W-FLASH contract (AACore/FlashSync, `FlashSyncView`, `AAFlashSyncInterop`) is real.
extension ContractStatus { public static let wFlashImplemented = true }
