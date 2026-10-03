// W-SHELL's contract flag, read by `ContractStatus.isImplemented(.wShell)` (ARCHITECTURE.md §6.1, §11).
// The W-SHELL contracts (ShellFlows, SettingsView, AboutView, KeyboardShortcutsView, MenuBarExtraContent,
// ReminderCenter, NotificationCenterBridge, SmokeTest) and the AACore helpers in this folder are real.
extension ContractStatus { public static let wShellImplemented = true }
