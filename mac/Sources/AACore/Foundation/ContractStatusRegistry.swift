// Spec: ARCHITECTURE.md §6.1, §10.5, §11 — placeholder bookkeeping for wave-owned AACore contracts.
import Foundation

/// The wave owners that have AACore contracts (F1/F2/F3 are merged before Stage W starts).
public enum ContractOwner: String, CaseIterable, Sendable {
    case wShell, wPersist, wRich, wCont, wFiles, wHier, wBuild, wPlan, wQuick, wCrew, wVessel, wPdf, wSire, wFlash, wDrive
}

// `ContractStatus` is ONE type: the crew contract-status enum of ARCHITECTURE.md §4.5 (declared in
// Model/CrewMember.swift) also carries this registry, so `ContractStatus.isImplemented(.wRich)` and
// `member.contractStatus(on:)` coexist (two same-named types cannot; recorded in Docs/Deviations/F1.md).
// Each wave owner declares its flag in a one-line file INSIDE ITS OWN FOLDER, e.g.
// `Sources/AACore/RichText/RichTextContractStatus.swift`:
//     extension ContractStatus { public static let wRichImplemented = false }
// and flips it to `true` when its contracts are real. `isImplemented` reads those flags.
extension ContractStatus {
    /// True once `owner` has replaced its placeholders with real implementations. Tests that need another
    /// owner's real code use `@Test(.enabled(if: ContractStatus.isImplemented(.wRich)))`.
    public static func isImplemented(_ owner: ContractOwner) -> Bool {
        // The per-owner flag files are created together with the placeholders (ARCHITECTURE.md §11); until then
        // every wave contract counts as not implemented, which is the correct answer for a placeholder.
        switch owner {
        case .wShell, .wPersist, .wRich, .wCont, .wFiles, .wHier, .wBuild, .wPlan, .wQuick, .wCrew, .wVessel,
             .wPdf, .wSire, .wFlash, .wDrive:
            return false
        }
    }
}
