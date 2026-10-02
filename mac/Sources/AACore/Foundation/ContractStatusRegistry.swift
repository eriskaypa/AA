// Spec: ARCHITECTURE.md §6.1, §10.5, §11 — placeholder bookkeeping for wave-owned AACore contracts.
import Foundation

/// The wave owners that have AACore contracts (F1/F2/F3 are merged before Stage W starts).
public enum ContractOwner: String, CaseIterable, Sendable {
    case wShell, wPersist, wRich, wCont, wFiles, wHier, wBuild, wPlan, wQuick, wCrew, wVessel, wPdf, wSire, wFlash, wDrive
}

// `ContractStatus` is ONE type: the crew contract-status enum of ARCHITECTURE.md §4.5 (declared in
// Model/CrewMember.swift) also carries this registry, so `ContractStatus.isImplemented(.wRich)` and
// `member.contractStatus(on:)` coexist (two same-named types cannot; recorded in Docs/Deviations/F1.md).
// Each wave owner's flag lives in a one-line file INSIDE ITS OWN FOLDER (created by F1 with the placeholders):
//     Sources/AACore/RichText/RichTextContractStatus.swift:
//     extension ContractStatus { public static let wRichImplemented = false }
// and the owner flips it to `true` when its contracts are real. Nobody edits another owner's flag file.
extension ContractStatus {
    /// True once `owner` has replaced its placeholders with real implementations. Tests that need another
    /// owner's real code use `@Test(.enabled(if: ContractStatus.isImplemented(.wRich)))`.
    public static func isImplemented(_ owner: ContractOwner) -> Bool {
        switch owner {
        case .wShell: return wShellImplemented        // ShellSupport/ShellSupportContractStatus.swift
        case .wPersist: return wPersistImplemented    // Bundles/BundlesContractStatus.swift
        case .wRich: return wRichImplemented          // RichText/RichTextContractStatus.swift
        case .wCont: return wContImplemented          // Editor/EditorContractStatus.swift
        case .wFiles: return wFilesImplemented        // FileBank/FileBankContractStatus.swift
        case .wHier: return wHierImplemented          // Hierarchy/HierarchyContractStatus.swift
        case .wBuild: return wBuildImplemented        // Builders/BuildersContractStatus.swift
        case .wPlan: return wPlanImplemented          // Calendar/CalendarContractStatus.swift
        case .wQuick: return wQuickImplemented        // Windows/WindowsContractStatus.swift
        case .wCrew: return wCrewImplemented          // Crew/CrewContractStatus.swift
        case .wVessel: return wVesselImplemented      // Vessel/VesselContractStatus.swift
        case .wPdf: return wPdfImplemented            // Export/ExportContractStatus.swift
        case .wSire: return wSireImplemented          // Sire/SireContractStatus.swift
        case .wFlash: return wFlashImplemented        // FlashSync/FlashSyncContractStatus.swift
        case .wDrive: return wDriveImplemented        // GoogleDrive/GoogleDriveContractStatus.swift
        }
    }
}
