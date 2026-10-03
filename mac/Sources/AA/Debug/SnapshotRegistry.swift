// Spec: ARCHITECTURE.md §9.6 (sheet registry: each UI owner registers its sheets in its own
//       `AA/<Dir>/<Area>DebugSnapshots.swift`; F3 calls every `registerW_*()` at launch in DEBUG). The registrations are
//       compiled only #if DEBUG (F3's own file is; the calls below are; each wave owner wraps its file, V-PACKAGE).
import SwiftUI
import AACore

/// Debug sheets the snapshot hook can present with `--sheet <owner>.<name>`.
@MainActor
enum SnapshotRegistry {
    private(set) static var sheets: [String: @MainActor (AppEnvironment) -> AnyView] = [:]
    private static var registered = false

    static func register(_ id: String, _ make: @escaping @MainActor (AppEnvironment) -> AnyView) {
        sheets[id] = make
    }

    /// F3's demo sheets plus every wave owner's registrations.
    static func registerAll() {
        #if DEBUG
        guard !registered else { return }
        registered = true
        registerF3()
        registerW_SHELL()
        registerW_PERSIST()
        registerW_CONT()
        registerW_FILES()
        registerW_HIER()
        registerW_BUILD()
        registerW_PLAN()
        registerW_QUICK()
        registerW_CREW()
        registerW_VESSEL()
        registerW_PDF()
        registerW_SIRE()
        registerW_FLASH()
        registerW_DRIVE()
        #endif
    }
}
