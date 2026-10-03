// Spec: ARCHITECTURE.md §9.6 — W-HIER's debug sheets for the snapshot hook (`--sheet w-hier.<name>`). The pages
// themselves are snapshotted with `--snapshot TabEquipment|TabTasks|TabProcedures|TabVessels [--select <uuid>]` and the
// item window with `--snapshot item --select <uuid>` (fixture: Tests/AACoreTests/Fixtures/ui/w-hier/).
#if DEBUG
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_HIER() {
        // HIER-058 Set mode: the first unprotected item; Change mode: the first protected one.
        register("w-hier.item-lock") { env in
            let target = env.store.allItems().first { !$0.isLockProtected } ?? env.store.allItems().first
            return AnyView(ItemLockSheet(itemID: target?.id ?? UUID()).environment(env))
        }
        register("w-hier.item-lock-change") { env in
            let target = env.store.allItems().first { $0.isLockProtected } ?? env.store.allItems().first
            return AnyView(ItemLockSheet(itemID: target?.id ?? UUID()).environment(env))
        }
        // HIER-071: the first component of the first equipment that has one.
        register("w-hier.component-editor") { env in
            let eq = env.store.data.equipment.first { !$0.components.isEmpty }
            let c = eq?.components.first
            return AnyView(HierComponentEditorSheet(equipmentID: eq?.id ?? UUID(), componentID: c?.id ?? UUID(),
                                                    close: {}).environment(env))
        }
        // HIER-050: the lock gate on its own (as an item window shows it).
        register("w-hier.lock-gate") { env in
            let target = env.store.allItems().first { $0.isLockProtected }
            return AnyView(LockGateView(itemID: target?.id ?? UUID()).environment(env).frame(width: 640, height: 460))
        }
    }
}
#endif
