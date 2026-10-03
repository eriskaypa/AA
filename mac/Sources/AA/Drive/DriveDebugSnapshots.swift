// Debug snapshot registrations of W-DRIVE (ARCHITECTURE.md §9.6; sheet ids "w-drive.<name>"): the sign-in waiting
// sheet, Settings ▸ Sync's Drive section, and the three tools with realistic state (14 §7.3–7.5 vectors).
#if DEBUG
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_DRIVE() {
        register("w-drive.sign-in") { _ in
            let model = DriveSignInModel(cancel: {})
            model.consentURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")
            return AnyView(DriveSignInSheet(model: model, dismiss: {}))
        }
        register("w-drive.settings") { _ in
            // `.font(.body)`: the Settings scene is system-font chrome; a sheet on the main window would otherwise
            // inherit the content monospace and misrepresent the pane.
            AnyView(Form { DriveSettingsSection() }
                .formStyle(.grouped)
                .font(.body)
                .frame(width: 680, height: 620))
        }
        register("w-drive.folder-builder") { _ in
            AnyView(FolderBuilderView(initialText: ToolFolderPlan.exampleText + "Docs\ndocs/Sub\n\tInner\n")
                .frame(width: 820, height: 620))
        }
        register("w-drive.date-calculator") { _ in
            let cal = Calendar(identifier: .gregorian)
            let today = cal.date(from: DateComponents(year: 2026, month: 9, day: 30)) ?? Date()
            let to = cal.date(from: DateComponents(year: 2027, month: 3, day: 1)) ?? Date()
            return AnyView(DateCalculatorView(today: today, to: to, amount: "1000", unit: .days, inclusive: true))
        }
        register("w-drive.unit-converter") { _ in
            var s = ToolUnitConverterState(categoryIndex: 2)
            s.edit(row: 2, text: "14.7")
            return AnyView(UnitConverterView(sessionID: UUID(), state: s).frame(width: 500, height: 640))
        }
    }
}
#endif
