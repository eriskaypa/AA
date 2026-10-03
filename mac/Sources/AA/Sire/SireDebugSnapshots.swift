// Spec: ARCHITECTURE.md §9.6 — W-SIRE's debug sheets for the snapshot hook (`--sheet w-sire.<name>`): the candidate
//       picker (SIRE-030), the kind picker (SIRE-034), the export sheet (SIRE-036/037, §6.8), the Gemini key prompt
//       (SIRE-038) and the Settings ▸ AI section. Synthetic task texts only (no bank content).
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_SIRE() {
        register("w-sire.candidates") { _ in
            AnyView(SireCandidatePickerSheet(
                prompt: "12 tasks identified for Q 2.1.1 — tick to add:",
                candidates: ["Review the document register for the latest class survey status report",
                             "Verify that the certificates listed in the survey status report are on board and valid",
                             "Check that any conditions of class or memoranda have been dealt with by the due date",
                             "Confirm that the company procedure for defect reporting to class has been followed",
                             "Interview the Master on the process for monitoring certificate expiry dates",
                             "Verify availability of: the HVPQ and the latest PIQ",
                             "Verify that there is a record of the last internal audit",
                             "Verify that the Chief Officer is familiar with the procedure",
                             "Sight the planned maintenance records for the emergency generator",
                             "Review the oil record book entries for the last three months",
                             "Verify that the crew has completed familiarisation training",
                             "Check the calibration records of the fixed gas detection system"]) { _ in })
        }
        register("w-sire.kind") { _ in AnyView(SireKindPickerSheet(defaultKind: .procedure) { _ in }) }
        register("w-sire.kind-group") { _ in AnyView(SireKindPickerSheet(defaultKind: .equipment, scope: .group) { _ in }) }
        register("w-sire.export") { env in
            SireViewModel.shared.attach(env)
            return AnyView(SireExportSheet { _ in })
        }
        register("w-sire.gemini-prompt") { _ in
            AnyView(TextPromptSheet(request: TextPromptRequest(title: SireActions.geminiPromptTitle,
                                                               prompt: SireActions.geminiPrompt,
                                                               initial: "AIzaSyExampleExampleExample", isSecure: true,
                                                               helpText: SireActions.geminiHelp)) { _ in })
        }
        register("w-sire.gemini-settings") { _ in
            AnyView(Form { GeminiKeySettingsSection() }.formStyle(.grouped).frame(width: 560, height: 360))
        }
    }
}
