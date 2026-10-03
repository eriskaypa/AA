// Spec: ARCHITECTURE.md §6.1, §11 — W-QUICK's contract flag, read by `ContractStatus.isImplemented(.wQuick)`.
// W-QUICK's contracts are real: the AACore models of AACore/QuickWork and AACore/Windows and the AA-target windows
// of ARCHITECTURE.md §7.7 (QuickWorkView, DueDatesPanelController, QuickSwitcherPanelController, SearchWindowView,
// ActivityLogView, TrashSheet, ReviewChangesSheet).
extension ContractStatus { public static let wQuickImplemented = true }
