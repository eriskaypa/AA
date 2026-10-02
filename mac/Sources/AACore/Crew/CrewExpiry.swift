// PLACEHOLDER(W-CREW) — contract: ARCHITECTURE.md §6.8
// Spec: 09 CREW-050…053 (+ consumers 03 SHELL-030/133). Compiling stub created by F1; W-CREW replaces this file in
// place. The stubs report no expiring crew (ARCH §11).
import Foundation

public enum CrewExpiry {
    public static let warnDays = 60, criticalDays = 30

    @MainActor public static func expiringCount(_ crew: [CrewMember], today: CivilDate) -> Int {
        // PLACEHOLDER(W-CREW)
        0
    }

    /// "Crew  ⚠ n".
    public static func badgeText(_ n: Int) -> String {
        // PLACEHOLDER(W-CREW)
        ""
    }
}
